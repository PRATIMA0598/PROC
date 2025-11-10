{% macro apply_rule_conditions(rule_list) %}
{% for r in rule_list %}
AND ({{ r.alias }}.VALUE = '' 
     OR {{ build_condition(r.alias ~ '.OPERATOR', r.target, r.alias ~ '.VALUE') }})
{% endfor %}
{% endmacro %}
