{% macro udf_query_construct(input_list, input_operator, attribute_name) %}

{% set input_list = input_list | string | trim %}
{% set op = input_operator | upper %}
{% set attr = attribute_name %}
{% set sep = ";" %}

{% if input_list is none or input_list == '' %}
    {{ return("") }}
{% endif %}

{# Single value comparisons #}
{% if op in ["=", "<>"] and sep not in input_list %}
    {{ return(attr ~ op ~ "'" ~ input_list ~ "'") }}

{# Multi-value IN #}
{% elif op == "=" and sep in input_list %}
    {% set val = "('" ~ input_list.replace(sep, "','") ~ "')" %}
    {{ return(attr ~ " IN " ~ val) }}

{# Multi-value NOT IN #}
{% elif op == "<>" and sep in input_list %}
    {% set val = "('" ~ input_list.replace(sep, "','") ~ "')" %}
    {{ return(attr ~ " NOT IN " ~ val) }}

{# LIKE multi-conditions #}
{% elif op == "LIKE" %}
    {% set val = input_list.replace(sep, "%' OR " ~ attr ~ " LIKE '%") %}
    {{ return(attr ~ " LIKE '%" ~ val ~ "%'") }}

{% elif op == "NOT LIKE" %}
    {% set val = input_list.replace(sep, "%' AND " ~ attr ~ " NOT LIKE '%") %}
    {{ return(attr ~ " NOT LIKE '%" ~ val ~ "%'") }}

{% elif op == "START WITH" %}
    {% set val = input_list.replace(sep, "%' OR " ~ attr ~ " LIKE '") %}
    {{ return(attr ~ " LIKE '" ~ val ~ "%'") }}

{% elif op == "END WITH" %}
    {% set val = input_list.replace(sep, "' OR " ~ attr ~ " LIKE '%") %}
    {{ return(attr ~ " LIKE '%" ~ val ~ "'") }}

{% else %}
    {{ return("") }}
{% endif %}

{% endmacro %}
