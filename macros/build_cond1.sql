{% macro build_cond1(r) %}
    {% set cond1 = "" %}
    {% set columns = [
        ["ATC4", "ATC4_OPERATOR"],
        ["CHANNEL", "CHANNEL_OPERATOR"],
        ["CHC_CLASS", "CHC_CLASS_OPERATOR"],
        ["CHC_FORM", "CHC_FORM_OPERATOR"],
        ["CLASS_TYPE", "CLASS_TYPE_OPERATOR"],
        ["CORPORATION", "CORPORATION_OPERATOR"],
        ["CORPORATION_LOCAL", "CORPORATION_LOCAL_OPERATOR"],
        ["COUNTRY", "COUNTRY_OPERATOR"],
        ["MANUFACTURER", "MANUFACTURER_OPERATOR"],
        ["MOLECULE_LIST", "MOLECULE_LIST_OPERATOR"],
        ["MOLECULE_LIST_LOCAL", "MOLECULE_LIST_LOCAL_OPERATOR"],
        ["NFC123", "NFC123_OPERATOR"],
        ["NFC123_LOCAL", "NFC123_LOCAL_OPERATOR"],
        ["PACK", "PACK_OPERATOR"],
        ["PACK_LOCAL", "PACK_LOCAL_OPERATOR"],
        ["PANEL", "PANEL_OPERATOR"],
        ["PRODUCT", "PRODUCT_OPERATOR"],
        ["PRODUCT_LOCAL", "PRODUCT_LOCAL_OPERATOR"],
        ["RX_STATUS", "RX_STATUS_OPERATOR"]
    ] %}

    {% for col, op in columns %}
        {% set col_val = r[col|string] %}
        {% set op_val  = r[op|string] %}

        {% if col_val is not none and col_val != "" %}
            {% set raw_cond = udf_query_construct(col_val, op_val, "UPPER(" ~ col ~ ")") %}
            {% if raw_cond != "" %}
                {% if cond1 == "" %}
                    {% set cond1 = "(" ~ raw_cond ~ ")" %}
                {% else %}
                    {% set cond1 = cond1 ~ " AND (" ~ raw_cond ~ ")" %}
                {% endif %}
            {% endif %}
        {% endif %}
    {% endfor %}

    {{ cond1 }}
{% endmacro %}
