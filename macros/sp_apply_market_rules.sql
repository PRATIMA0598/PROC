{% macro apply_market_rules() %}

-- 1. Truncate working tables
{% do run_query("TRUNCATE TABLE SL_SANDBOX.FLASH_HUB_POC.MARKET_RULE_SQL_LOG") %}
{% do run_query("TRUNCATE TABLE SL_SANDBOX.FLASH_HUB_POC.LNK_MARKET_PRODUCT") %}

-- 2. Pull all rules for the Market with flags for manufacturer/corporation
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
        MD.RULE_SET,
        MAX(CASE WHEN MD.ATTRIBUTE_NAME = 'MANUFACTURER' THEN 1 ELSE 0 END)
            OVER (PARTITION BY MD.RULE_NAME, MD.RULE_SET) AS HAS_MANUFACTURER,
        MAX(CASE WHEN MD.ATTRIBUTE_NAME = 'CORPORATION' THEN 1 ELSE 0 END)
            OVER (PARTITION BY MD.RULE_NAME, MD.RULE_SET) AS HAS_CORPORATION
    FROM SL_SANDBOX.FLASH_HUB_POC.REF_MARKET_RULES MD
    JOIN DF_SINERGI.DWH_MARKET_SALES.DIM_MARKET M
        ON UPPER(M.MARKET_NM) = UPPER(MD.RULE_NAME)
    WHERE (GLOBAL_FLAG IS NOT NULL AND INCLUSION_FLAG IS NOT NULL)
    ORDER BY RULE_NAME, RULE_SET
""") %}

-- 3. Group rules by RULE_NAME + RULE_SET
{% set grouped = {} %}
{% for r in rules %}
    {% set key = r.RULE_NAME ~ ':' ~ r.RULE_SET %}
    {% if key not in grouped %}
        {% set _ = grouped.update({
            key: {
                'MARKET_ID': r.MARKET_ID,
                'RULE_ID': r.RULE_ID,
                'RULE_NAME': r.RULE_NAME,
                'GLOBAL_FLAG': r.GLOBAL_FLAG,
                'INCLUSION_FLAG': r.INCLUSION_FLAG,
                'RULE_SET': r.RULE_SET,
                'HAS_MANUFACTURER': r.HAS_MANUFACTURER,
                'HAS_CORPORATION': r.HAS_CORPORATION,
                'rules': []
            }
        }) %}
    {% endif %}
    {% set _ = grouped[key]['rules'].append(r) %}
{% endfor %}

-- 4. Table mapping
{% set table_map = {
    'CHANNEL': 'PL', 'PANEL': 'PL',
    'COUNTRY': 'C',
    'ATC4_CD': 'ATC',
    'PRODUCT_LOCAL': 'DP', 'PRODUCT_CLEANED': 'DP',
    'ORGANIZATION_NAME': 'O', 'MANUFACTURER': 'O', 'CORPORATION': 'O',
    'MOLECULE_NAME_LOCAL': 'M', 'MOLECULE_NAME': 'M',
    'PACK_CLEANED': 'P', 'PACK_LOCAL': 'P', 'CHC_CLASS': 'P', 'CHC_FORM': 'P',
    'NFC123_LOCAL': 'NFC', 'NFC123_CD': 'NFC',
    'RX_STATUS': 'RS'
} %}

{% set column_map = {
    'MANUFACTURER': 'ORGANIZATION_NAME',
    'CORPORATION': 'ORGANIZATION_NAME',
    'ORGANIZATION_NAME': 'ORGANIZATION_NAME'
} %}

{% for grp_key, rule_data in grouped.items() %}

    {% set cond_parts = [] %}
    {% set needed_aliases = [] %}

    {% for r in rule_data.rules %}
        {% set field = r.ATTRIBUTE_NAME %}
        {% if field == 'CLASS_TYPE' %}
            {% continue %}
        {% endif %}

        {% set alias = table_map.get(field) %}
        {% if alias and alias not in needed_aliases %}
            {% set _ = needed_aliases.append(alias) %}
        {% endif %}

        {% set actual_col = column_map.get(field, field) %}  
        {% set col = alias ~ "." ~ actual_col %}             

        {% set op = r.ATTRIBUTE_OPERATOR %}
        {% set v = r.ATTRIBUTE_VALUE_LIST.replace("'", "''") %}

        {% if ';' in v %}
            {% set vals = v.split(';') | map('trim') | map('upper') | list %}
            {% set vals_str = vals | join("','") %}
            {% if op == '<>' %}
                {% set _ = cond_parts.append("UPPER(" ~ col ~ ") NOT IN ('" ~ vals_str ~ "')") %}
            {% else %}
                {% set _ = cond_parts.append("UPPER(" ~ col ~ ") IN ('" ~ vals_str ~ "')") %}
            {% endif %}
        {% else %}
            {% set _ = cond_parts.append("UPPER(" ~ col ~ ") " ~ op ~ " '" ~ v | upper ~ "'") %}
        {% endif %}
    {% endfor %}

    {% set final_condition = cond_parts | join(' AND ') %}
    {% set joins = [] %}

    {# --- DP + O joins --- #}
    {% if rule_data.HAS_MANUFACTURER == 1 or rule_data.HAS_CORPORATION == 1 %}
        {% set _ = joins.append("JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_PRODUCT DP ON DP.PRODUCT_ID = P.PACK_ID") %}
    {% endif %}

    {% if rule_data.HAS_MANUFACTURER == 1 %}
        {% set _ = joins.append("JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_ORGANIZATION O ON O.ORGANIZATION_ID = DP.ORGANIZATION_ID AND O.ORGANIZATION_TYPE ILIKE 'MNF'") %}
    {% endif %}

    {% if rule_data.HAS_CORPORATION == 1 %}
        {% set _ = joins.append("JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_ORGANIZATION O ON O.ORGANIZATION_ID = DP.ORGANIZATION_ID") %}
        {% set _ = joins.append("JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.ORGANIZATION_HIER H ON H.DEPT_ORGANIZATION_ID=O.ORGANIZATION_ID AND O.ORGANIZATION_TYPE ILIKE 'MNF'") %}
        {% set _ = joins.append("JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_ORGANIZATION H1 ON H.PARENT_ORGANIZATION_ID=H1.ORGANIZATION_ID AND H1.ORGANIZATION_TYPE ILIKE 'CORP'") %}
    {% endif %}

    {# --- Other joins --- #}
    {% if 'C' in needed_aliases %}
        {% set _ = joins.append("JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_COUNTRY C ON F.COUNTRY_ID = C.COUNTRY_ID") %}
    {% endif %}
    {% if 'ATC' in needed_aliases %}
        {% set _ = joins.append("JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_ATC ATC ON ATC.ATC_ID = P.ATC_ID") %}
    {% endif %}
    {% if 'M' in needed_aliases %}
        {% set _ = joins.append("JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_MOLECULE M ON M.MOLECULE_ID = P.MOLECULE_ID") %}
    {% endif %}
    {% if 'NFC' in needed_aliases %}
        {% set _ = joins.append("JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_NFC NFC ON NFC.NFC_ID = P.NFC_ID") %}
    {% endif %}
    {% if 'RS' in needed_aliases %}
        {% set _ = joins.append("JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.RX_STATUS RS ON RS.RX_STATUS_ID = P.RX_STATUS_ID") %}
    {% endif %}

    {# --- Insert and log --- #}
    {% if final_condition != "" and rule_data.INCLUSION_FLAG == 1 and rule_data.GLOBAL_FLAG == 1 %}

        {% set query_insert %}
INSERT INTO SL_SANDBOX.FLASH_HUB_POC.LNK_MARKET_PRODUCT
(RULE_ID, COUNTRY_ID, PANEL_ID, FREQUENCY, MARKET_ID, PACK_ID)
SELECT DISTINCT '{{ rule_data.RULE_ID }}', F.COUNTRY_ID, F.PANEL_ID, PL.FREQUENCY, '{{ rule_data.MARKET_ID }}', P.PACK_ID
FROM DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.FCT_SALES_NATIONAL F
JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_PACK P ON F.PACK_ID = P.PACK_ID
JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_PANEL PL ON F.PANEL_ID = PL.PANEL_ID
{{ joins | join('\n') }}
WHERE IFNULL(PL.EXCLUSION_FLAG,0) = 0
  AND {{ final_condition }}
        {% endset %}

        {% set log_insert %}
INSERT INTO SL_SANDBOX.FLASH_HUB_POC.MARKET_RULE_SQL_LOG 
(RULES_TYPE, RULE_NAME, RULE_SET, GENERATED_SQL)
VALUES ('GLOBAL_INSERT','{{ rule_data.RULE_NAME }}','{{ rule_data.RULE_SET }}',$$ {{ query_insert }} $$)
        {% endset %}

        {% do run_query(log_insert) %}
        {#{% do run_query(query_insert) %}#}
    {% endif %}
{# ------------------ GLOBAL DELETE LOGIC ------------------ #}
    {% if final_condition != "" and rule_data.INCLUSION_FLAG == 0 and rule_data.GLOBAL_FLAG == 1 %}

        {% set query_delete %}
DELETE FROM SL_SANDBOX.FLASH_HUB_POC.LNK_MARKET_PRODUCT
WHERE MARKET_ID = '{{ rule_data.MARKET_ID }}'
AND PACK_ID IN (
    SELECT DISTINCT P.PACK_ID
   FROM DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.FCT_SALES_NATIONAL F
   JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_PACK P ON F.PACK_ID = P.PACK_ID
   JOIN DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_PANEL PL ON F.PANEL_ID = PL.PANEL_ID
   {{ joins | join('\n') }}
   WHERE IFNULL(PL.EXCLUSION_FLAG,0) = 0
  AND {{ final_condition }}
)
        {% endset %}

        {% set log_delete %}
INSERT INTO SL_SANDBOX.FLASH_HUB_POC.MARKET_RULE_SQL_LOG (RULES_TYPE,RULE_NAME,RULE_SET,GENERATED_SQL)
VALUES ('GLOBAL_DELETE','{{ rule_data.RULE_NAME }}','{{ rule_data.RULE_SET }}',$$ {{ query_delete }} $$)
        {% endset %}

        {#{% do run_query(log_delete) %}#}
        {# {% do run_query(query_delete) %} #}

    {% endif %}
{% endfor %}
{% endmacro %}
