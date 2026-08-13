/**
 * @description Utility class for building strings, with support for CSV and field list generation.
 * Includes a ReportBuilder subclass for generating CSV reports based on SObject fields.
 * CSV values are assembled by plain concatenation — never String.format — so apostrophes
 * and braces in data pass through intact, and values containing a comma, quote, or newline
 * are wrapped in quotes with inner quotes doubled.
 *
 * @group Strings
 * @author David Wood
 * @since August 2024
 * @last May 2026 — conformance refactor
 * @last August 2026 — CSV escaping; String.format removed from value assembly; inherited sharing
 */
// inherited sharing: pure in-memory string assembly; no SOQL, DML, or record data access.
public virtual inherited sharing class StringBuilder {
  protected String stringValue;

  /**
   * @description Creates an empty builder.
   */
  public StringBuilder() {
  }

  /**
   * @description Creates a builder seeded with the supplied values, in order.
   * @param values Values to append on construction.
   */
  public StringBuilder(List<String> values) {
    add(values);
  }

  /**
   * @description Appends each value in the list, in order.
   * @param values Values to append.
   */
  public virtual void add(List<String> values) {
    for (String value : values) {
      add(value);
    }
  }

  /**
   * @description Appends a single value to the built string.
   * @param value Value to append.
   */
  public virtual void add(String value) {
    stringValue = (stringValue == null ? value : stringValue + value);
  }

  /**
   * @description Returns the built string.
   * @return The accumulated string, or null when nothing has been added.
   */
  public virtual String getStringValue() {
    return stringValue;
  }

  /**
   * @description Escapes a single value for CSV output: when the value contains a comma,
   *              quote, or newline it is wrapped in quotes with inner quotes doubled;
   *              otherwise it passes through unchanged.
   * @param value Raw value; null passes through as null.
   * @return The CSV-safe value.
   */
  private static String escapeCsvValue(String value) {
    if (value == null) {
      return value;
    }
    if (
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')
    ) {
      return '"' + value.replace('"', '""') + '"';
    }
    return value;
  }

  /** Subclasses **/

  /**
   * @description Subclass for building CSV strings.
   */
  // inherited sharing: pure in-memory string assembly; no SOQL, DML, or record data access.
  public virtual inherited sharing class CSVBuilder extends StringBuilder {
    // Escaped values are retained so an item prefix can be applied per value at read time.
    private List<String> csvValues;

    /**
     * @description Creates an empty CSV builder.
     */
    public CSVBuilder() {
    }

    /**
     * @description Creates a CSV builder seeded with the supplied values, in order.
     * @param values Values to append on construction.
     */
    public CSVBuilder(List<String> values) {
      super(values);
    }

    /**
     * @description Appends a single value, CSV-escaped when it contains a comma, quote, or newline.
     * @param value Value to append as the next CSV item.
     */
    public virtual override void add(String value) {
      // Lazy init: the base constructor dispatches here before this class's field initializers run.
      if (csvValues == null) {
        csvValues = new List<String>();
      }
      csvValues.add(escapeCsvValue(value));
    }

    /**
     * @description Builds the CSV string with a prefix concatenated before each item.
     * @param itemPrefix Prefix to add before each item in the CSV string; null is treated as empty.
     * @return The CSV string with prefixed items, or null when no values have been added.
     */
    public String getStringValue(String itemPrefix) {
      if (csvValues == null || csvValues.isEmpty()) {
        return null;
      }
      String prefix = (itemPrefix == null ? '' : itemPrefix);
      String result = '';
      for (Integer index = 0; index < csvValues.size(); index++) {
        result += (index == 0 ? '' : ',') + prefix + csvValues[index];
      }
      return result;
    }

    /**
     * @description Builds the CSV string with no item prefix.
     * @return The CSV string, or null when no values have been added.
     */
    public override String getStringValue() {
      return getStringValue('');
    }
  }

  /**
   * @description Subclass for building a list of field names from SObjectField values.
   */
  // inherited sharing: pure schema-name string assembly; no SOQL, DML, or record data access.
  public virtual inherited sharing class FieldListBuilder extends CSVBuilder {
    /**
     * @description Creates a field-list builder from the supplied fields.
     * @param values List of SObjectField values to include in the field list.
     */
    public FieldListBuilder(List<Schema.SObjectField> values) {
      for (Schema.SObjectField value : values) {
        add(value.getDescribe().getName());
      }
    }
  }

  /**
   * @description Subclass for building a field list with support for multi-currency organizations.
   */
  // inherited sharing: pure schema-name string assembly; no SOQL, DML, or record data access.
  public inherited sharing class MultiCurrencyFieldListBuilder extends FieldListBuilder {
    /**
     * @description Creates a field-list builder that appends CurrencyIsoCode in multi-currency orgs.
     * @param values List of SObjectField values to include in the field list.
     */
    public MultiCurrencyFieldListBuilder(List<Schema.SObjectField> values) {
      super(values);
      if (Userinfo.isMultiCurrencyOrganization()) {
        add('CurrencyIsoCode');
      }
    }
  }

  /** Report Builder **/

  /**
   * @description Subclass for building CSV reports based on a list of SObject fields.
   */
  // inherited sharing: formats caller-supplied records in memory; no SOQL, DML, or record data access.
  public inherited sharing class ReportBuilder extends StringBuilder {
    private FieldListBuilder fieldListBuilder;
    // Header field names, split once at construction rather than re-split per record.
    private List<String> headerFields;
    private List<String> rows;

    /**
     * @description Creates a report builder whose header row lists the supplied fields.
     * @param fields List of SObjectField values to include in the report.
     */
    public ReportBuilder(List<Schema.SObjectField> fields) {
      fieldListBuilder = new FieldListBuilder(fields);
      rows = new List<String>();
      headerFields = new List<String>();
      String header = fieldListBuilder.getStringValue();
      if (header != null) {
        for (String fieldName : header.split(',')) {
          headerFields.add(fieldName.trim());
        }
      }
    }

    /**
     * @description Adds one record's field values to the report as a CSV-escaped row.
     * @param record SObject record whose field values will be added to the report.
     */
    public void addRecord(SObject record) {
      String row = '';
      for (Integer index = 0; index < headerFields.size(); index++) {
        row +=
          (index == 0 ? '' : ',') +
          escapeCsvValue(String.valueOf(record.get(headerFields[index])));
      }
      rows.add(row);
    }

    /**
     * @description Builds the report: a header row followed by one newline-separated row per record.
     * @return The generated CSV report as a string.
     */
    public String generateReport() {
      add(fieldListBuilder.getStringValue());
      for (String row : rows) {
        add('\n');
        add(row);
      }
      return getStringValue();
    }
  }
}
