{% macro apply_market_rules() %}

-- 1. Truncate Working Tables
{% do run_query("TRUNCATE TABLE PROC.COND1") %}
{% do run_query("TRUNCATE TABLE PROC.LNK_MARKET_PRODUCT") %}

-- 2. Pull all rules for the Market
{% set rules = run_query("""
    SELECT 
        M.MARKET_ID,
        MD.RULE_NAME,       
        MD.RULE_ID,
        MD.GLOBAL_FLAG,
        MD.INCLUSION_FLAG,
        MD.ATTRIBUTE_NAME,
        MD.ATTRIBUTE_OPERATOR,
        MD.ATTRIBUTE_VALUE_LIST,
        MD.RULE_ORDER
    FROM PROC.REF_MARKET_RULES MD
    JOIN PROC.DIM_MARKET M
        ON UPPER(M.MARKET_NM) = UPPER(MD.RULE_NAME)
        WHERE RULE_NAME ILIKE'Acid Control_Boost'
    ORDER BY RULE_NAME, RULE_ORDER
""") %}

-- 3. Group rules by (RULE_NAME + RULE_ORDER)
{% set grouped = {} %}
{% for r in rules %}
    {% set key = r.RULE_NAME ~ ':' ~ r.RULE_ORDER %}  
    {% if key not in grouped %}
        {% set _ = grouped.update({
            key: {
                'MARKET_ID': r.MARKET_ID,
                'RULE_NAME': r.RULE_NAME,
                'GLOBAL_FLAG': r.GLOBAL_FLAG,
                'INCLUSION_FLAG': r.INCLUSION_FLAG,
                'RULE_ORDER': r.RULE_ORDER,
                'rules': []
            }
        }) %}
    {% endif %}
    {% set _ = grouped[key]['rules'].append(r) %}
{% endfor %}

-- 4. Build ONE combined WHERE clause per group
{% for grp_key, rule_data in grouped.items() %}

    {% set cond_parts = [] %}

    {% for r in rule_data.rules %}
        {% set field = r.ATTRIBUTE_NAME %}
        {% set op = r.ATTRIBUTE_OPERATOR %}
        {% set v = r.ATTRIBUTE_VALUE_LIST.replace("'", "''") %}

        {% if field in ['CHANNEL','PANEL','CLASS_TYPE'] %}
            {% set col = "P." ~ field %}
        {% else %}
            {% set col = "SP." ~ field %}
        {% endif %}

        {% if ';' in v %}
            {% set vals = v.split(';') | map('trim') | map('upper') | list %}
            {% set vals_str = vals | join("','") %}
            {% if op == '<>' %}
                {% set _ = cond_parts.append("UPPER(" ~ col ~ ") NOT IN ('" ~ vals_str ~ "')") %}
            {% else %}
                {% set _ = cond_parts.append("UPPER(" ~ col ~ ") IN ('" ~ vals_str ~ "')") %}
            {% endif %}
        {% else %}
            {% set safe_v = v | upper %}
            {% set _ = cond_parts.append("UPPER(" ~ col ~ ") " ~ op ~ " '" ~ safe_v ~ "'") %}
        {% endif %}

    {% endfor %}

    {% set final_condition = cond_parts | join(' AND ') %}

    {# ------------------ GLOBAL INSERT LOGIC ------------------ #}
    {% if final_condition != "" and rule_data.INCLUSION_FLAG == 1 and rule_data.GLOBAL_FLAG == 1 %}

        {% set query_insert %}
INSERT INTO PROC.LNK_MARKET_PRODUCT (SOURCE_PRODUCT_ID, MARKET_ID)
SELECT DISTINCT SP.SOURCE_PRODUCT_ID, '{{ rule_data.MARKET_ID }}'
FROM PROC.DIM_SOURCE_PRODUCT SP
JOIN PROC.VW_LNK_PRODUCT_PNL SPN ON SPN.SOURCE_PRODUCT_ID = SP.SOURCE_PRODUCT_ID
JOIN PROC.DIM_PANEL P ON P.PANEL_ID = SPN.PANEL_ID
WHERE IFNULL(P.EXCLUSION_FLAG,0) = 0
AND {{ final_condition }}
AND SP.COUNTRY ILIKE 'UKRAINE'
        {% endset %}

        {% set log_insert %}
INSERT INTO PROC.COND1 (RULE_NAME,RULE_ORDER,QUER1)
VALUES ('{{ rule_data.RULE_NAME }}','{{ rule_data.RULE_ORDER }}',$$ {{ query_insert }} $$)
        {% endset %}

        {% do run_query(log_insert) %}
        {# {% do run_query(query_insert) %} #}

    {% endif %}

    {# ------------------ GLOBAL DELETE LOGIC ------------------ #}
    {% if final_condition != "" and rule_data.INCLUSION_FLAG == 0 and rule_data.GLOBAL_FLAG == 0 %}

        {% set query_delete %}
DELETE FROM PROC.LNK_MARKET_PRODUCT
WHERE MARKET_ID = '{{ rule_data.MARKET_ID }}'
AND SOURCE_PRODUCT_ID IN (
    SELECT DISTINCT SP.SOURCE_PRODUCT_ID
    FROM PROC.DIM_SOURCE_PRODUCT SP
    JOIN PROC.VW_LNK_PRODUCT_PNL SPN ON SPN.SOURCE_PRODUCT_ID = SP.SOURCE_PRODUCT_ID
    JOIN PROC.DIM_PANEL P ON P.PANEL_ID = SPN.PANEL_ID
    WHERE {{ final_condition }}
)
        {% endset %}

        {% set log_delete %}
INSERT INTO PROC.COND1 (RULE_NAME,RULE_ORDER,QUER1)
VALUES ('{{ rule_data.RULE_NAME }}','{{ rule_data.RULE_ORDER }}',$$ {{ query_delete }} $$)
        {% endset %}

        {% do run_query(log_delete) %}
        {# {% do run_query(query_delete) %} #}

    {% endif %}

{% endfor %}

{% endmacro %}
