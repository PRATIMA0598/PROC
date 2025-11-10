{% macro flatten_rule(col) %}
rules_{{ col }} AS (
    SELECT
        MARKET_DEFINITION_ID,
        MARKET_DEFINITION_NM,
        {{ col | upper }}_OPERATOR,
        TRIM(s.value) AS {{ col | upper }}_VALUE
    FROM rules,
    TABLE(SPLIT_TO_TABLE({{ col | upper }}, ';')) s
)
{% endmacro %}
