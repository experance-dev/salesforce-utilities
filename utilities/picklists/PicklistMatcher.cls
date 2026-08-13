/**
 * @description Fuzzy-matching engine behind UtilPickLists.findClosestMatch. Scores a free-text
 *              search string against candidate picklist values and labels: everything is
 *              normalized (whitespace collapsed, lowercased) before Levenshtein comparison,
 *              confidence is 1 − distance ÷ longerStringLength (1 = exact after normalization),
 *              the caller sets the minimum confidence below which no match is returned, and
 *              confidence ties break deterministically to the candidate whose normalized value
 *              sorts first alphabetically. Kept separate from UtilPickLists so the describe
 *              utilities and the matching engine each stay within the complexity budget.
 * @group Picklists
 * @author David Wood
 * @since August 2026
 * @last 2026-08-13 — engine extracted from UtilPickLists with the result-object API
 */
// without sharing: pure string computation over caller-supplied candidates; no data access.
public without sharing class PicklistMatcher {
  // Scale for confidence arithmetic; enough precision that distinct distances never collide.
  private static final Integer CONFIDENCE_SCALE = 6;

  /**
   * @description Outcome of a fuzzy picklist match. When no candidate clears the caller's
   *              minimum confidence, matchedValue is null, confidence is 0, and wasExact is false.
   */
  public class PicklistMatchResult {
    /** @description The matched picklist API value; null when nothing cleared the minimum confidence. */
    public String matchedValue { get; private set; }
    /** @description Similarity of the winning candidate, normalized to 0–1 (1 = exact after normalization). */
    public Decimal confidence { get; private set; }
    /** @description True when the normalized search string equaled the candidate's value or label. */
    public Boolean wasExact { get; private set; }

    private PicklistMatchResult(
      String matchedValue,
      Decimal confidence,
      Boolean wasExact
    ) {
      this.matchedValue = matchedValue;
      this.confidence = confidence;
      this.wasExact = wasExact;
    }
  }

  /**
   * @description Fuzzy-matches a search string against candidate value → label pairs under the
   *              contract described on the class header.
   * @param valuesToLabels    Candidate picklist values mapped to their labels.
   * @param searchString      Free-text input to match.
   * @param minimumConfidence Minimum confidence (0–1, inclusive) a candidate must reach; below
   *        it, no match is returned. Null is treated as 0; out-of-range values are clamped.
   * @return PicklistMatchResult with the winning value, its confidence, and the exactness flag —
   *         or the no-match result (null value, 0 confidence) when nothing clears the minimum.
   */
  public static PicklistMatchResult findClosestMatch(
    Map<String, String> valuesToLabels,
    String searchString,
    Decimal minimumConfidence
  ) {
    String normalizedSearch = normalizeForMatch(searchString);
    if (
      valuesToLabels == null ||
      valuesToLabels.isEmpty() ||
      String.isBlank(normalizedSearch)
    ) {
      return noMatch();
    }

    BestCandidate best = new BestCandidate();
    for (String value : valuesToLabels.keySet()) {
      String normalizedValue = normalizeForMatch(value);
      best.offer(
        value,
        normalizedValue,
        Math.max(
          similarity(normalizedSearch, normalizedValue),
          similarity(
            normalizedSearch,
            normalizeForMatch(valuesToLabels.get(value))
          )
        )
      );
    }

    if (best.confidence < clampConfidence(minimumConfidence)) {
      return noMatch();
    }
    return new PicklistMatchResult(
      best.value,
      best.confidence,
      best.confidence == 1
    );
  }

  private static PicklistMatchResult noMatch() {
    return new PicklistMatchResult(null, 0, false);
  }

  // Running winner of the candidate scan. Tie-breaking is deterministic: higher confidence
  // wins; equal confidence goes to the candidate whose normalized value sorts first
  // alphabetically, regardless of map iteration order.
  private class BestCandidate {
    private String value = null;
    private String normalizedValue = null;
    private Decimal confidence = -1;

    private void offer(
      String candidateValue,
      String candidateNormalizedValue,
      Decimal candidateConfidence
    ) {
      if (!beatsCurrent(candidateNormalizedValue, candidateConfidence)) {
        return;
      }
      value = candidateValue;
      normalizedValue = candidateNormalizedValue;
      confidence = candidateConfidence;
    }

    // The first offer always wins (confidence starts at -1), so the tie branch never
    // dereferences a null normalizedValue.
    private Boolean beatsCurrent(
      String candidateNormalizedValue,
      Decimal candidateConfidence
    ) {
      if (candidateConfidence > confidence) {
        return true;
      }
      return candidateConfidence == confidence &&
        candidateNormalizedValue.compareTo(normalizedValue) < 0;
    }
  }

  // Whitespace collapsed and lowercased — the comparison space for all fuzzy matching.
  private static String normalizeForMatch(String input) {
    return input == null ? '' : input.normalizeSpace().toLowerCase();
  }

  // 1 − levenshtein ÷ longerLength over already-normalized strings; 1 means equal.
  private static Decimal similarity(String normalizedA, String normalizedB) {
    if (normalizedA.equals(normalizedB)) {
      return 1;
    }
    Integer longerLength = Math.max(
      normalizedA.length(),
      normalizedB.length()
    );
    Decimal distanceRatio = Decimal.valueOf(
        normalizedA.getLevenshteinDistance(normalizedB)
      )
      .divide(Decimal.valueOf(longerLength), CONFIDENCE_SCALE);
    return 1 - distanceRatio;
  }

  private static Decimal clampConfidence(Decimal minimumConfidence) {
    Decimal floor = minimumConfidence == null ? 0 : minimumConfidence;
    return Math.min(1, Math.max(0, floor));
  }
}
