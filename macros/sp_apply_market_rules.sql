{% macro apply_market_rules() %}

{# 1. Truncate temporary tables #}
{% do run_query("TRUNCATE TABLE PROC.COND1") %}
{% do run_query("TRUNCATE TABLE PROC.LNK_MARKET_PRODUCT") %}

{# 2. Get market definitions #}
{% set market_definitions = run_query("""
    SELECT 
        M.MARKET_ID,
        MD.INCLUSION_FLAG,
        CASE
            WHEN UPPER(MD.MARKET_NM_OPERATOR) = 'NOT LIKE' THEN 'LIKE'
            WHEN UPPER(MD.MARKET_NM_OPERATOR) = '<>' THEN '='
            ELSE UPPER(MD.MARKET_NM_OPERATOR)
        END AS MARKET_NM_OPERATOR_D,
        MD.*
    FROM PROC.REF_MARKET_DEFINITION MD
    JOIN PROC.DIM_MARKET M
      ON UPPER(M.MARKET_NM) = UPPER(MD.MARKET_DEFINITION_NM)
    ORDER BY MARKET_DEFINITION_ID, MARKET_DEFINITION_ORDER ASC
""") %}

{# 3. Loop through each market definition and build dynamic conditions #}
{% for r in market_definitions %}

    {% set cond_parts = [] %}

    {# Fields to handle dynamically #}
    {% set dynamic_fields = [
        ['COUNTRY', 'COUNTRY_OPERATOR'],
        ['PANEL', 'PANEL_OPERATOR'],
        ['CHANNEL', 'CHANNEL_OPERATOR'],
        ['CLASS_TYPE', 'CLASS_TYPE_OPERATOR'],
        ['ATC4', 'ATC4_OPERATOR'],
        ['PRODUCT_LOCAL', 'PRODUCT_LOCAL_OPERATOR'],
        ['PRODUCT', 'PRODUCT_OPERATOR'],
        ['MANUFACTURER', 'MANUFACTURER_OPERATOR'],
        ['CORPORATION_LOCAL', 'CORPORATION_LOCAL_OPERATOR'],
        ['CORPORATION', 'CORPORATION_OPERATOR'],
        ['MOLECULE_LIST_LOCAL', 'MOLECULE_LIST_LOCAL_OPERATOR'],
        ['MOLECULE_LIST', 'MOLECULE_LIST_OPERATOR'],
        ['PACK', 'PACK_OPERATOR'],
        ['PACK_LOCAL', 'PACK_LOCAL_OPERATOR'],
        ['NFC123', 'NFC123_OPERATOR'],
        ['NFC123_LOCAL', 'NFC123_LOCAL_OPERATOR'],
        ['CHC_CLASS', 'CHC_CLASS_OPERATOR'],
        ['CHC_FORM', 'CHC_FORM_OPERATOR'],
        ['RX_STATUS', 'RX_STATUS_OPERATOR']
    ] %}

    {# 4. Build dynamic condition #}
    {% for field, operator in dynamic_fields %}
        {% set value = r[field] %}
        {% set op = r[operator] %}
        {% if value and value|trim != '' %}

            {# Determine table alias #}
            {% if field in ['CHANNEL', 'PANEL', 'CLASS_TYPE'] %}
                {% set col_ref = "P." ~ field %}
            {% else %}
                {% set col_ref = "SP." ~ field %}
            {% endif %}

            {# Handle multi-value (;) or single value #}
            {% if ';' in value %}
                {% set vals_list = value.split(';') %}
                {% set vals_upper = vals_list 
                    | map('trim') 
                    | map('upper') 
                    | map('replace', "'", "''") 
                    | list %}
                {% set vals_str = vals_upper | join("','") %}

                {# Use IN or NOT IN depending on operator #}
                {% if op == '<>' %}
                    {% set _ = cond_parts.append("UPPER(" ~ col_ref ~ ") NOT IN ('" ~ vals_str ~ "')") %}
                {% else %}
                    {% set _ = cond_parts.append("UPPER(" ~ col_ref ~ ") IN ('" ~ vals_str ~ "')") %}
                {% endif %}
            {% else %}
                {% set safe_value = value|upper|replace("'", "''") %}
                {% set _ = cond_parts.append("UPPER(" ~ col_ref ~ ") " ~ op ~ " '" ~ safe_value ~ "'") %}
            {% endif %}

        {% endif %}
    {% endfor %}

    {% set cond1 = cond_parts | join(' AND ') %}

    {# 5. Only build query if inclusion_flag = 1 #}
    {% if cond1 != "" and r.INCLUSION_FLAG == 1 %}
        {% set query_sql %}
INSERT INTO PROC.LNK_MARKET_PRODUCT(SOURCE_PRODUCT_ID, MARKET_ID)
SELECT DISTINCT SP.SOURCE_PRODUCT_ID, '{{ r.MARKET_ID }}'
FROM PROC.DIM_SOURCE_PRODUCT AS SP
INNER JOIN PROC.VW_LNK_PRODUCT_PNL SPN
    ON SPN.SOURCE_PRODUCT_ID = SP.SOURCE_PRODUCT_ID
INNER JOIN PROC.DIM_PANEL AS P
    ON SPN.PANEL_ID = P.PANEL_ID
WHERE IFNULL(P.EXCLUSION_FLAG,0) = 0
AND {{ cond1 }}
AND SP.COUNTRY ILIKE 'UKRAINE'
        {% endset %}

        {# Insert cond1 and query_sql into PROC.COND1 #}
        {#{% set insert_sql %}
            INSERT INTO PROC.COND1 (MARKET_DEFINITION_ID, COND1, QUER1)
            VALUES ('{{ r.MARKET_DEFINITION_ID }}', $$ {{ cond1 }} $$, $$ {{ query_sql }} $$)
        {% endset %}
        {% do run_query(insert_sql) %}#}

        {# Execute the query_sql to insert into PROC.LNK_MARKET_PRODUCT #}
        {% do run_query(query_sql) %}
    {% endif %}

{% endfor %}

{% endmacro %}
