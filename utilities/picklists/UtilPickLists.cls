/**
 * @description Utility methods for working with picklist metadata via Schema.describe, including
 *              fuzzy matching of free-text input against active picklist entries. Fuzzy matching
 *              returns a PicklistMatcher.PicklistMatchResult carrying the matched value, a
 *              normalized confidence (0 = nothing alike, 1 = exact after normalization), and
 *              whether the match was exact; callers set the minimum confidence below which no
 *              match is returned. The scoring engine lives in PicklistMatcher; this class owns
 *              the describe plumbing and the picklist-facing API.
 * @group Picklists
 * @author David Wood
 * @since June 2024
 * @last May 2026 — conformance refactor
 * @last 2026-08-13 — result-object fuzzy matching: normalized confidence, caller-set minimum,
 *                    case/whitespace normalization, deterministic tie-breaker (PicklistMatcher)
 */
// without sharing: pure Schema.describe metadata operations; no record data access.
public without sharing class UtilPickLists {
  /**
   * @description Returns the raw values of a picklist field.
   * @param sObjectField The picklist field to inspect.
   * @return List of raw picklist values; empty if the field is null or not a picklist.
   */
  public static List<String> getPickListValues(
    Schema.SObjectField sObjectField
  ) {
    List<String> picklistValues = new List<String>();
    if (!isPicklistField(sObjectField)) {
      return picklistValues;
    }
    for (
      Schema.PicklistEntry entry : sObjectField.getDescribe()
        .getPicklistValues()
    ) {
      picklistValues.add(entry.getValue());
    }
    return picklistValues;
  }

  /**
   * @description Returns the raw values of a picklist field resolved by sObject and field API name.
   * @param sObjectName API name of the sObject.
   * @param fieldName   API name of the field.
   * @return List of raw picklist values; empty if the sObject or field is not found, or the field is not a picklist.
   */
  public static List<String> getPickListValues(
    String sObjectName,
    String fieldName
  ) {
    Schema.SObjectType sObjectType = Schema.getGlobalDescribe()
      .get(sObjectName);
    if (sObjectType == null) {
      return new List<String>();
    }
    Schema.SObjectField sObjectField = sObjectType.getDescribe(
        SObjectDescribeOptions.DEFERRED
      )
      .fields.getMap()
      .get(fieldName);
    return getPickListValues(sObjectField);
  }

  /**
   * @description Returns the active entries of a picklist field as a value-to-label map.
   * @param sObjectField The picklist field to inspect.
   * @return Map of value → label for active entries only; empty if null or not a picklist.
   */
  public static Map<String, String> getActivePickListValuesMapWithLabels(
    Schema.SObjectField sObjectField
  ) {
    Map<String, String> activeValues = new Map<String, String>();
    if (!isPicklistField(sObjectField)) {
      return activeValues;
    }
    for (
      Schema.PicklistEntry entry : sObjectField.getDescribe()
        .getPicklistValues()
    ) {
      if (entry.isActive()) {
        activeValues.put(entry.getValue(), entry.getLabel());
      }
    }
    return activeValues;
  }

  /**
   * @description Fuzzy-matches a search string against a field's active picklist entries.
   *              Search string, values, and labels are normalized (whitespace collapsed,
   *              lowercased) before Levenshtein comparison; each candidate scores against both
   *              its value and its label and keeps the better score. Confidence is
   *              1 − distance ÷ longerStringLength, so 1 means exact after normalization.
   *              Ties on confidence break deterministically to the candidate whose normalized
   *              picklist value sorts first alphabetically.
   * @param sObjectField      The picklist field to search.
   * @param searchString      Free-text input to match.
   * @param minimumConfidence Minimum confidence (0–1, inclusive) a candidate must reach; below
   *        it, no match is returned. Null is treated as 0; out-of-range values are clamped.
   * @return PicklistMatcher.PicklistMatchResult with the winning value, its confidence, and the
   *         exactness flag — or the no-match result (null value, 0 confidence) when nothing
   *         clears the minimum.
   */
  public static PicklistMatcher.PicklistMatchResult findClosestMatch(
    Schema.SObjectField sObjectField,
    String searchString,
    Decimal minimumConfidence
  ) {
    return PicklistMatcher.findClosestMatch(
      getActivePickListValuesMapWithLabels(sObjectField),
      searchString,
      minimumConfidence
    );
  }

  /**
   * @description Fuzzy-matches a search string against caller-supplied value → label candidates.
   *              Same normalization, confidence, threshold, and tie-break contract as the
   *              field-based overload; exposed so candidate sets from any source can be matched
   *              and so the engine is deterministic under test.
   * @param valuesToLabels    Candidate picklist values mapped to their labels.
   * @param searchString      Free-text input to match.
   * @param minimumConfidence Minimum confidence (0–1, inclusive) a candidate must reach; below
   *        it, no match is returned. Null is treated as 0; out-of-range values are clamped.
   * @return PicklistMatcher.PicklistMatchResult with the winning value, its confidence, and the
   *         exactness flag — or the no-match result (null value, 0 confidence) when nothing
   *         clears the minimum.
   */
  public static PicklistMatcher.PicklistMatchResult findClosestMatch(
    Map<String, String> valuesToLabels,
    String searchString,
    Decimal minimumConfidence
  ) {
    return PicklistMatcher.findClosestMatch(
      valuesToLabels,
      searchString,
      minimumConfidence
    );
  }

  /**
   * @description Finds the active picklist value matching a search string, exactly or by closest
   *              match. Deprecated: prefer findClosestMatch, which returns a result object
   *              (value, confidence, exactness) and lets the caller set a minimum confidence
   *              instead of always receiving the nearest value. The closest-match path of this
   *              wrapper now delegates to that engine with a minimum of 0, so it inherits the
   *              normalization and deterministic tie-break; the exact path keeps its historical
   *              case-sensitive comparison.
   * @param sObjectField  The picklist field to search.
   * @param searchString  String to match against picklist values or labels.
   * @param exactMatch    true for exact (case-sensitive) match; false for closest match.
   * @return Matching picklist value, or empty string if none found.
   */
  public static String getPickListMatch(
    Schema.SObjectField sObjectField,
    String searchString,
    Boolean exactMatch
  ) {
    Map<String, String> picklistValues = getActivePickListValuesMapWithLabels(
      sObjectField
    );

    if (
      picklistValues.isEmpty() ||
      String.isBlank(searchString) ||
      exactMatch == null
    ) {
      return '';
    }

    if (exactMatch) {
      return findExactMatch(picklistValues, searchString);
    }
    // With a minimum of 0 and the guards above satisfied, the engine always names a winner.
    return PicklistMatcher.findClosestMatch(picklistValues, searchString, 0)
      .matchedValue;
  }

  private static Boolean isPicklistField(Schema.SObjectField sObjectField) {
    return sObjectField != null &&
      sObjectField.getDescribe().getType() == Schema.DisplayType.Picklist;
  }

  private static String findExactMatch(
    Map<String, String> picklistValues,
    String searchString
  ) {
    for (String key : picklistValues.keySet()) {
      if (
        key.equals(searchString) ||
        picklistValues.get(key).equals(searchString)
      ) {
        return key;
      }
    }
    return '';
  }
}
