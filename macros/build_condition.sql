{% macro build_condition(operator_col, target_col, value_col) %}
(
    -- Skip if operator or value is null/empty
    {{ operator_col }} IS NULL
    OR {{ value_col }} IS NULL
    OR TRIM({{ operator_col }}) = ''
    OR TRIM({{ value_col }}) = ''

    OR (
        {{ operator_col }} = '=' AND UPPER({{ target_col }}) = UPPER({{ value_col }})
    )
    OR (
        {{ operator_col }} = '<>' AND UPPER({{ target_col }}) <> UPPER({{ value_col }})
    )
    OR (
        {{ operator_col }} = 'LIKE' AND UPPER({{ target_col }}) LIKE '%' || UPPER({{ value_col }}) || '%'
    )
    OR (
        {{ operator_col }} = 'NOT LIKE' AND UPPER({{ target_col }}) NOT LIKE '%' || UPPER({{ value_col }}) || '%'
    )
    OR (
        {{ operator_col }} = 'START WITH' AND UPPER({{ target_col }}) LIKE UPPER({{ value_col }}) || '%'
    )
    OR (
        {{ operator_col }} = 'END WITH' AND UPPER({{ target_col }}) LIKE '%' || UPPER({{ value_col }})
    )
)
{% endmacro %}