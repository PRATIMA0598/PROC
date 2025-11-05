{% macro generate_rule_ctes(rule_columns) %}
  {%- for col in rule_columns %}
    , rules_{{ col.name | lower }} AS (
        SELECT 
            MARKET_DEFINITION_ID,
            MARKET_DEFINITION_NM,
            {{ col.operator }} AS {{ col.operator | lower }},
            TRIM(s.value) AS {{ col.name | upper }}_VALUE
        FROM rules, TABLE(SPLIT_TO_TABLE({{ col.name }}, ';')) s
    )
  {%- endfor %}
{% endmacro %}
