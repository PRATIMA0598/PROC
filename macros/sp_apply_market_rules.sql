{% macro apply_market_rules() %}

-- 1. Get dynamic target table
{% set target_table_row = run_query("SELECT TABLE_NAME FROM SL_SANDBOX.FLASH_HUB_POC.REF_DYNAMIC_JOINS WHERE SPECIAL_FLAG = 'MAIN_TABLE' LIMIT 1") %}
{% set target_table = target_table_row[0].TABLE_NAME %}
{% set log_table_row = run_query("SELECT TABLE_NAME FROM SL_SANDBOX.FLASH_HUB_POC.REF_DYNAMIC_JOINS WHERE SPECIAL_FLAG = 'LOG_TABLE' LIMIT 1") %}
{% set log_table = log_table_row[0].TABLE_NAME %}


-- 2. Truncate working tables dynamically
{% do run_query("TRUNCATE TABLE " ~ log_table) %}
{% do run_query("TRUNCATE TABLE " ~ target_table) %}

-- 3. Collect SQL for ordered execution
{% set global_inserts = [] %}
{% set global_deletes = [] %}
{% set local_inserts = [] %}
{% set local_deletes = [] %}

-- 4. Pull all rules for the Market
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

-- 5. Group rules
{% set grouped = {} %}
{% for r in rules %}
    {% set key = r.RULE_NAME ~ ':' ~ r.RULE_SET %}
    {% if key not in grouped %}
        {% set _ = grouped.update({key: {
            'MARKET_ID': r.MARKET_ID,
            'RULE_ID': r.RULE_ID,
            'RULE_NAME': r.RULE_NAME,
            'GLOBAL_FLAG': r.GLOBAL_FLAG,
            'INCLUSION_FLAG': r.INCLUSION_FLAG,
            'RULE_SET': r.RULE_SET,
            'HAS_MANUFACTURER': r.HAS_MANUFACTURER,
            'HAS_CORPORATION': r.HAS_CORPORATION,
            'rules': []
        }}) %}
    {% endif %}
    {% set _ = grouped[key]['rules'].append(r) %}
{% endfor %}

-- 6. Table mapping
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

    -- Load all join definitions
    {% set join_rows = run_query("SELECT TABLE_ALIAS, TABLE_NAME, JOIN_CONDITION, SPECIAL_FLAG, DEPENDENCY_ALIAS FROM SL_SANDBOX.FLASH_HUB_POC.REF_DYNAMIC_JOINS") %}

    {% set join_map = {} %}
    {% for row in join_rows %}
        {% set _ = join_map.update({ row.TABLE_ALIAS: row }) %}
    {% endfor %}

    -- Add special flags (Manufacturer / Corporation)
    {% for row in join_rows %}
        {% if row.SPECIAL_FLAG == 'MANUFACTURER' and rule_data.HAS_MANUFACTURER == 1 %}
            {% if row.TABLE_ALIAS not in needed_aliases %}
                {% set _ = needed_aliases.append(row.TABLE_ALIAS) %}
            {% endif %}
        {% endif %}
        {% if row.SPECIAL_FLAG == 'CORPORATION' and rule_data.HAS_CORPORATION == 1 %}
            {% if row.TABLE_ALIAS not in needed_aliases %}
                {% set _ = needed_aliases.append(row.TABLE_ALIAS) %}
            {% endif %}
        {% endif %}
    {% endfor %}

    -- Add dependency aliases recursively
    {% for _ in range(5000) %}
        {% set added = [] %}
        {% for alias in needed_aliases %}
            {% if alias in join_map %}
                {% set dep = join_map[alias].DEPENDENCY_ALIAS %}
                {% if dep is not none and dep not in needed_aliases %}
                    {% set _ = added.append(dep) %}
                {% endif %}
            {% endif %}
        {% endfor %}
        {% if added | length == 0 %}
            {% break %}
        {% endif %}
        {% set _ = needed_aliases.extend(added) %}
    {% endfor %}

    -- STATIC_BASE tables separated
    {% set first_static = join_rows | selectattr("SPECIAL_FLAG","equalto","STATIC_BASE") | selectattr("JOIN_CONDITION","equalto","1=1") | list %}
    {% set remaining_static = join_rows | selectattr("SPECIAL_FLAG","equalto","STATIC_BASE") | rejectattr("JOIN_CONDITION","equalto","1=1") | list %}

    -- Dynamic dependency joins
    {% set joins = [] %}
    {% set included_aliases = [] %}
    {% set remaining_aliases = needed_aliases[:] %}
    {% for _ in range(50) %}
        {% if remaining_aliases | length == 0 %}
            {% break %}
        {% endif %}
        {% set newly_included = [] %}
        {% for alias in remaining_aliases %}
            {% if alias in join_map %}
                {% set row = join_map[alias] %}
                {% set dep = row.DEPENDENCY_ALIAS %}
                {% if dep is none or dep in included_aliases %}
                    {% set join_sql = "JOIN " ~ row.TABLE_NAME ~ " " ~ row.TABLE_ALIAS ~ " ON " ~ row.JOIN_CONDITION %}
                    {% if join_sql not in joins %}
                        {% set _ = joins.append(join_sql) %}
                    {% endif %}
                    {% if row.TABLE_ALIAS not in included_aliases %}
                        {% set _ = newly_included.append(row.TABLE_ALIAS) %}
                    {% endif %}
                {% endif %}
            {% endif %}
        {% endfor %}
        {% if newly_included | length == 0 %}
            {% break %}
        {% endif %}
        {% set _ = included_aliases.extend(newly_included) %}
        {% set remaining_aliases = remaining_aliases | reject("in", included_aliases) | list %}
    {% endfor %}

    -- Build full FROM clause
{% set base_clause %} 
FROM {{ first_static[0].TABLE_NAME }} {{ first_static[0].TABLE_ALIAS }}
{% for r in remaining_static %} JOIN {{ r.TABLE_NAME }} {{ r.TABLE_ALIAS }} ON {{ r.JOIN_CONDITION }}{% endfor %}
{% for j in joins %} {{ j }}{% endfor %}
{% endset %}

    {# ------------------ GLOBAL INSERT ------------------ #}
    {% if final_condition != "" and rule_data.INCLUSION_FLAG == 1 and rule_data.GLOBAL_FLAG == 1 %}
        {% set query_insert %}
INSERT INTO {{ target_table }}
(RULE_SET, COUNTRY_ID, PANEL_ID, FREQUENCY, MARKET_ID, PACK_ID)
SELECT DISTINCT '{{ rule_data.RULE_SET }}', F.COUNTRY_ID, F.PANEL_ID, PL.FREQUENCY, '{{ rule_data.MARKET_ID }}', P.PACK_ID
{{ base_clause }}
WHERE IFNULL(PL.EXCLUSION_FLAG,0) = 0
  AND {{ final_condition }}
        {% endset %}

        {% set log_insert %}
INSERT INTO {{log_table}}
(RULES_TYPE, RULE_NAME, RULE_SET, GENERATED_SQL)
VALUES ('GLOBAL_INSERT','{{ rule_data.RULE_NAME }}','{{ rule_data.RULE_SET }}',$$ {{ query_insert }} $$)
        {% endset %}
        {% do global_inserts.append({'log': log_insert, 'query': query_insert}) %}
    {% endif %}

    {# ------------------ GLOBAL DELETE ------------------ #}
    {% if final_condition != "" and rule_data.INCLUSION_FLAG == 0 and rule_data.GLOBAL_FLAG == 1 %}
        {% set query_delete %}
DELETE FROM {{ target_table }}
WHERE MARKET_ID = '{{ rule_data.MARKET_ID }}'
AND PACK_ID IN (
    SELECT DISTINCT P.PACK_ID
    {{ base_clause }}
    WHERE IFNULL(PL.EXCLUSION_FLAG,0) = 0
    AND {{ final_condition }}
)
        {% endset %}

        {% set log_delete %}
INSERT INTO {{log_table}}
(RULES_TYPE,RULE_NAME,RULE_SET,GENERATED_SQL)
VALUES ('GLOBAL_DELETE','{{ rule_data.RULE_NAME }}','{{ rule_data.RULE_SET }}',$$ {{ query_delete }} $$)
        {% endset %}
        {% do global_deletes.append({'log': log_delete, 'query': query_delete}) %}
    {% endif %}

    {# ------------------ LOCAL INSERT ------------------ #}
    {% if final_condition != "" and rule_data.INCLUSION_FLAG == 1 and rule_data.GLOBAL_FLAG == 0 %}
        {% set query_insert_local %}
INSERT INTO {{ target_table }}
(RULE_SET, COUNTRY_ID, PANEL_ID, FREQUENCY, MARKET_ID, PACK_ID)
SELECT DISTINCT '{{ rule_data.RULE_SET }}', F.COUNTRY_ID, F.PANEL_ID, PL.FREQUENCY, '{{ rule_data.MARKET_ID }}', P.PACK_ID
{{ base_clause }}
WHERE IFNULL(PL.EXCLUSION_FLAG,0) = 0
  AND {{ final_condition }}
        {% endset %}

        {% set log_insert_local %}
INSERT INTO {{log_table}}
(RULES_TYPE,RULE_NAME,RULE_SET,GENERATED_SQL)
VALUES ('LOCAL_INSERT','{{ rule_data.RULE_NAME }}','{{ rule_data.RULE_SET }}',$$ {{ query_insert_local }} $$)
        {% endset %}
        {% do local_inserts.append({'log': log_insert_local, 'query': query_insert_local}) %}
    {% endif %}

    {# ------------------ LOCAL DELETE ------------------ #}
    {% if final_condition != "" and rule_data.INCLUSION_FLAG == 0 and rule_data.GLOBAL_FLAG == 0 %}
        {% set query_delete_local %}
DELETE FROM {{ target_table }}
WHERE MARKET_ID = '{{ rule_data.MARKET_ID }}'
AND PACK_ID IN (
    SELECT DISTINCT P.PACK_ID
    {{ base_clause }}
    WHERE IFNULL(PL.EXCLUSION_FLAG,0) = 0
    AND {{ final_condition }}
)
        {% endset %}

        {% set log_delete_local %}
INSERT INTO {{log_table}}
(RULES_TYPE,RULE_NAME,RULE_SET,GENERATED_SQL)
VALUES ('LOCAL_DELETE','{{ rule_data.RULE_NAME }}','{{ rule_data.RULE_SET }}',$$ {{ query_delete_local }} $$)
        {% endset %}
        {% do local_deletes.append({'log': log_delete_local, 'query': query_delete_local}) %}
    {% endif %}

{% endfor %}

-- 1) GLOBAL INSERT: write log then execute query
{% for pair in global_inserts %}
    {% do run_query(pair.log) %}
{% endfor %}

-- 2) GLOBAL DELETE
{% for pair in global_deletes %}
    {% do run_query(pair.log) %}
    {#{% do run_query(pair.query) %}#}
{% endfor %}

-- 3) LOCAL INSERT
{% for pair in local_inserts %}
    {% do run_query(pair.log) %}
{% endfor %}

-- 4) LOCAL DELETE
{% for pair in local_deletes %}
    {% do run_query(pair.log) %}
{% endfor %}

{% endmacro %}
