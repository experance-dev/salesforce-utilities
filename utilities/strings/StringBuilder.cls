/**
 * @description Utility class for building strings, with support for CSV and field list generation.
 * Includes a ReportBuilder subclass for generating CSV reports based on SObject fields.
 *
 * @group Strings
 * @since August 2024
 * @last May 2026 — Wave 5 conformance
 */
public virtual without sharing class StringBuilder {
  protected String stringValue;

  public StringBuilder() {
  }

  public StringBuilder(List<String> values) {
    add(values);
  }

  public virtual void add(List<String> values) {
    for (String value : values) {
      add(value);
    }
  }

  public virtual void add(String value) {
    stringValue = (stringValue == null ? value : stringValue + value);
  }

  public virtual String getStringValue() {
    return stringValue;
  }

  /** Subclasses **/

  /**
   * @description Subclass for building CSV strings.
   */
  public virtual without sharing class CSVBuilder extends StringBuilder {
    public CSVBuilder() {
    }

    public CSVBuilder(List<String> values) {
      super(values);
    }

    public virtual override void add(String value) {
      stringValue = (stringValue == null
        ? '{0}' + value
        : stringValue + ',{0}' + value);
    }

    /**
     * @param itemPrefix Prefix to add before each item in the CSV string.
     * @return The CSV string with prefixed items.
     */
    public String getStringValue(String itemPrefix) {
      return stringValue == null
        ? null
        : String.format(stringValue, new List<String>{ itemPrefix });
    }

    public override String getStringValue() {
      return getStringValue('');
    }
  }

  /**
   * @description Subclass for building a list of field names from SObjectField values.
   */
  public virtual without sharing class FieldListBuilder extends CSVBuilder {
    /**
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
  public without sharing class MultiCurrencyFieldListBuilder extends FieldListBuilder {
    /**
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
  public without sharing class ReportBuilder extends StringBuilder {
    private CSVBuilder csvBuilder;
    private FieldListBuilder fieldListBuilder;

    /**
     * @param fields List of SObjectField values to include in the report.
     */
    public ReportBuilder(List<Schema.SObjectField> fields) {
      fieldListBuilder = new FieldListBuilder(fields);
      csvBuilder = new CSVBuilder(new List<String>());
    }

    /**
     * @param record SObject record whose field values will be added to the report.
     */
    public void addRecord(SObject record) {
      List<String> values = new List<String>();
      for (String fieldName : fieldListBuilder.getStringValue().split(',')) {
        values.add(String.valueOf(record.get(fieldName.trim())));
      }
      csvBuilder.add(values);
    }

    /**
     * @return The generated CSV report as a string.
     */
    public String generateReport() {
      add(fieldListBuilder.getStringValue());
      add('\n');
      add(csvBuilder.getStringValue());
      return getStringValue();
    }
  }
}
