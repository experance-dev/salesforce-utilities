/**
 * @description Utility class for building strings, with support for CSV and field list generation.
 * Includes a ReportBuilder subclass for generating CSV reports based on SObject fields.
 *
 * @group Utilities
 * @since August 2024
 */
public virtual with sharing class StringBuilder {
  /**
   * @description Holds the concatenated string value.
   */
  protected String m_stringValue;

  /**
   * @description Default constructor.
   */
  public StringBuilder() {
  }

  /**
   * @description Constructs a StringBuilder with an initial list of values.
   * @param values List of String values to initialize the StringBuilder.
   */
  public StringBuilder(List<String> values) {
    add(values);
  }

  /**
   * @description Adds a list of values to the string.
   * @param values List of String values to add.
   */
  public virtual void add(List<String> values) {
    for (String value : values) {
      add(value);
    }
  }

  /**
   * @description Adds a single value to the string.
   * @param value String value to add.
   */
  public virtual void add(String value) {
    m_stringValue = (m_stringValue == null ? value : m_stringValue + value);
  }

  /**
   * @description Returns the concatenated string value.
   * @return The concatenated string.
   */
  public virtual String getStringValue() {
    return m_stringValue;
  }

  /** Subclasses **/

  /**
   * @description Subclass for building CSV strings.
   */
  public virtual with sharing class CSVBuilder extends StringBuilder {
    /**
     * @description Default constructor.
     */
    public CSVBuilder() {
    }

    /**
     * @description Constructs a CSVBuilder with an initial list of values.
     * @param values List of String values to initialize the CSVBuilder.
     */
    public CSVBuilder(List<String> values) {
      super(values);
    }

    /**
     * @description Adds a value to the CSV string.
     * @param value String value to add.
     */
    public virtual override void add(String value) {
      m_stringValue = (m_stringValue == null
        ? '{0}' + value
        : m_stringValue + ',{0}' + value);
    }

    /**
     * @description Returns the CSV string value, with an optional prefix for each item.
     * @param itemPrefix Prefix to add before each item in the CSV string.
     * @return The CSV string with prefixed items.
     */
    public String getStringValue(String itemPrefix) {
      return m_stringValue == null
        ? null
        : String.format(m_stringValue, new List<String>{ itemPrefix });
    }

    /**
     * @description Returns the CSV string value with no prefix.
     * @return The CSV string.
     */
    public override String getStringValue() {
      return getStringValue('');
    }
  }

  /**
   * @description Subclass for building a list of field names from SObjectField values.
   */
  public virtual with sharing class FieldListBuilder extends CSVBuilder {
    /**
     * @description Constructs a FieldListBuilder from a list of SObjectField values.
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
  public with sharing class MultiCurrencyFieldListBuilder extends FieldListBuilder {
    /**
     * @description Constructs a MultiCurrencyFieldListBuilder, adding the CurrencyIsoCode field if in a multi-currency org.
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
  public with sharing class ReportBuilder extends StringBuilder {
    private CSVBuilder csvBuilder;
    private FieldListBuilder fieldListBuilder;

    /**
     * @description Constructs a ReportBuilder from a list of SObjectField values.
     * @param fields List of SObjectField values to include in the report.
     */
    public ReportBuilder(List<Schema.SObjectField> fields) {
      fieldListBuilder = new FieldListBuilder(fields);
      csvBuilder = new CSVBuilder(new List<String>());
    }

    /**
     * @description Adds a record's field values to the report.
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
     * @description Generates the final CSV report, combining headers and record data.
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
