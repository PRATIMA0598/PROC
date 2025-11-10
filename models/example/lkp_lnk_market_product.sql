{{ config(materialized='table') }}

{% set rule_columns = [
    'atc4', 'channel', 'chc_class', 'chc_form', 'class_type',
    'corporation', 'corporation_local', 'country', 'manufacturer',
    'molecule_list', 'molecule_list_local', 'nfc123', 'nfc123_local',
    'pack', 'pack_local', 'panel', 'product', 'product_local', 'rx_status'
] %}

{% set field_map = {
    'atc4': 'd.ATC4',
    'channel': 'pnl.CHANNEL',
    'chc_class': 'd.CHC_CLASS',
    'chc_form': 'd.CHC_FORM',
    'class_type': 'pnl.CLASS_TYPE',
    'corporation': 'd.CORPORATION',
    'corporation_local': 'd.CORPORATION_LOCAL',
    'country': 'd.COUNTRY',
    'manufacturer': 'd.MANUFACTURER',
    'molecule_list': 'd.MOLECULE_LIST',
    'molecule_list_local': 'd.MOLECULE_LIST_LOCAL',
    'nfc123': 'd.NFC123',
    'nfc123_local': 'd.NFC123_LOCAL',
    'pack': 'd.PACK',
    'pack_local': 'd.PACK_LOCAL',
    'panel': 'pnl.PANEL',
    'product': 'd.PRODUCT',
    'product_local': 'd.PRODUCT_LOCAL',
    'rx_status': 'd.RX_STATUS'
} %}

WITH rules AS (
    SELECT *
    FROM POC_PROC.PROC.REF_MARKET_DEFINITION
    WHERE MARKET_DEFINITION_ID = '860'
    AND INCLUSION_FLAG= 1
),

-- Generate flattened rule CTEs dynamically
{% for col in rule_columns %}
{{ flatten_rule(col) }}{% if not loop.last %},{% endif %}
{% endfor %}

SELECT DISTINCT
    d.source_product_id,
    m.MARKET_ID,
    r_atc4.MARKET_DEFINITION_ID,
    d.COUNTRY
FROM {{ source('landing', 'DIM') }} d
JOIN {{ source('landing', 'VW') }} v 
    ON d.source_product_id = v.source_product_id
JOIN {{ source('landing', 'PNL') }} pnl 
    ON v.PANEL_ID = pnl.PANEL_ID
    AND IFNULL(d.EXCLUSION_FLAG,0) = 0
JOIN {{ source('landing', 'MKT') }} m 
    ON 1=1

-- join (prevents NULL rule leakage)
JOIN rules_atc4 r_atc4
    ON UPPER(m.MARKET_NM) = UPPER(r_atc4.MARKET_DEFINITION_NM)

-- Optional rule sets via LEFT JOIN
{% for col in rule_columns if col != 'atc4' %}
LEFT JOIN rules_{{ col }} r_{{ col }}
    ON UPPER(m.MARKET_NM) = UPPER(r_{{ col }}.MARKET_DEFINITION_NM)
{% endfor %}

WHERE UPPER(d.COUNTRY) = 'UKRAINE'

-- Apply dynamic build_condition rules
{% for col in rule_columns %}
AND (
     r_{{ col }}.{{ col | upper }}_VALUE = '' 
     OR {{ build_condition(
            "r_" ~ col ~ "." ~ col|upper ~ "_OPERATOR",
            field_map[col],
            "r_" ~ col ~ "." ~ col|upper ~ "_VALUE"
        ) }}
)
{% endfor %}

