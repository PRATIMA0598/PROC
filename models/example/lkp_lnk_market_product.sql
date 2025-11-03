{{ config(
    materialized='table'
) }}

WITH rules AS (
    SELECT *
    FROM POC_PROC.PROC.REF_MARKET_DEFINITION
    WHERE MARKET_DEFINITION_ID = '860'
),

-- Flatten multi-value columns individually
rules_atc4 AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, ATC4_OPERATOR, TRIM(s.value) AS ATC4_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(ATC4, ';')) s
),
rules_channel AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, CHANNEL_OPERATOR, TRIM(s.value) AS CHANNEL_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(CHANNEL, ';')) s
),
rules_chc_class AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, CHC_CLASS_OPERATOR, TRIM(s.value) AS CHC_CLASS_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(CHC_CLASS, ';')) s
),
rules_chc_form AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, CHC_FORM_OPERATOR, TRIM(s.value) AS CHC_FORM_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(CHC_FORM, ';')) s
),
rules_class_type AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, CLASS_TYPE_OPERATOR, TRIM(s.value) AS CLASS_TYPE_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(CLASS_TYPE, ';')) s
),
rules_corporation AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, CORPORATION_OPERATOR, TRIM(s.value) AS CORPORATION_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(CORPORATION, ';')) s
),
rules_corporation_local AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, CORPORATION_LOCAL_OPERATOR, TRIM(s.value) AS CORPORATION_LOCAL_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(CORPORATION_LOCAL, ';')) s
),
rules_country AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, COUNTRY_OPERATOR, TRIM(s.value) AS COUNTRY_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(COUNTRY, ';')) s
),
rules_manufacturer AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, MANUFACTURER_OPERATOR, TRIM(s.value) AS MANUFACTURER_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(MANUFACTURER, ';')) s
),
rules_molecule_list AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, MOLECULE_LIST_OPERATOR, TRIM(s.value) AS MOLECULE_LIST_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(MOLECULE_LIST, ';')) s
),
rules_molecule_list_local AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, MOLECULE_LIST_LOCAL_OPERATOR, TRIM(s.value) AS MOLECULE_LIST_LOCAL_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(MOLECULE_LIST_LOCAL, ';')) s
),
rules_nfc123 AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, NFC123_OPERATOR, TRIM(s.value) AS NFC123_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(NFC123, ';')) s
),
rules_nfc123_local AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, NFC123_LOCAL_OPERATOR, TRIM(s.value) AS NFC123_LOCAL_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(NFC123_LOCAL, ';')) s
),
rules_pack AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, PACK_OPERATOR, TRIM(s.value) AS PACK_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(PACK, ';')) s
),
rules_pack_local AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, PACK_LOCAL_OPERATOR, TRIM(s.value) AS PACK_LOCAL_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(PACK_LOCAL, ';')) s
),
rules_panel AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, PANEL_OPERATOR, TRIM(s.value) AS PANEL_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(PANEL, ';')) s
),
rules_product AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, PRODUCT_OPERATOR, TRIM(s.value) AS PRODUCT_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(PRODUCT, ';')) s
),
rules_product_local AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, PRODUCT_LOCAL_OPERATOR, TRIM(s.value) AS PRODUCT_LOCAL_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(PRODUCT_LOCAL, ';')) s
),
rules_rx_status AS (
    SELECT MARKET_DEFINITION_ID, MARKET_DEFINITION_NM, RX_STATUS_OPERATOR, TRIM(s.value) AS RX_STATUS_VALUE
    FROM rules, TABLE(SPLIT_TO_TABLE(RX_STATUS, ';')) s
)

SELECT DISTINCT
    d.source_product_id,
    m.MARKET_ID,
    r_atc4.MARKET_DEFINITION_ID,
    d.COUNTRY
FROM {{ source('landing', 'DIM') }} d
JOIN {{ source('landing', 'VW') }} v ON d.source_product_id = v.source_product_id
JOIN {{ source('landing', 'PNL') }} pnl ON v.PANEL_ID = pnl.PANEL_ID
    AND IFNULL(d.EXCLUSION_FLAG,0) = 0
JOIN {{ source('landing', 'MKT') }} m ON 1=1

-- Join all rules CTEs individually
JOIN rules_atc4 r_atc4 ON UPPER(m.MARKET_NM) = UPPER(r_atc4.MARKET_DEFINITION_NM)
LEFT JOIN rules_channel r_channel ON UPPER(m.MARKET_NM) = UPPER(r_channel.MARKET_DEFINITION_NM)
LEFT JOIN rules_chc_class r_chc_class ON UPPER(m.MARKET_NM) = UPPER(r_chc_class.MARKET_DEFINITION_NM)
LEFT JOIN rules_chc_form r_chc_form ON UPPER(m.MARKET_NM) = UPPER(r_chc_form.MARKET_DEFINITION_NM)
LEFT JOIN rules_class_type r_class_type ON UPPER(m.MARKET_NM) = UPPER(r_class_type.MARKET_DEFINITION_NM)
LEFT JOIN rules_corporation r_corporation ON UPPER(m.MARKET_NM) = UPPER(r_corporation.MARKET_DEFINITION_NM)
LEFT JOIN rules_corporation_local r_corporation_local ON UPPER(m.MARKET_NM) = UPPER(r_corporation_local.MARKET_DEFINITION_NM)
LEFT JOIN rules_country r_country ON UPPER(m.MARKET_NM) = UPPER(r_country.MARKET_DEFINITION_NM)
LEFT JOIN rules_manufacturer r_manufacturer ON UPPER(m.MARKET_NM) = UPPER(r_manufacturer.MARKET_DEFINITION_NM)
LEFT JOIN rules_molecule_list r_molecule_list ON UPPER(m.MARKET_NM) = UPPER(r_molecule_list.MARKET_DEFINITION_NM)
LEFT JOIN rules_molecule_list_local r_molecule_list_local ON UPPER(m.MARKET_NM) = UPPER(r_molecule_list_local.MARKET_DEFINITION_NM)
LEFT JOIN rules_nfc123 r_nfc123 ON UPPER(m.MARKET_NM) = UPPER(r_nfc123.MARKET_DEFINITION_NM)
LEFT JOIN rules_nfc123_local r_nfc123_local ON UPPER(m.MARKET_NM) = UPPER(r_nfc123_local.MARKET_DEFINITION_NM)
LEFT JOIN rules_pack r_pack ON UPPER(m.MARKET_NM) = UPPER(r_pack.MARKET_DEFINITION_NM)
LEFT JOIN rules_pack_local r_pack_local ON UPPER(m.MARKET_NM) = UPPER(r_pack_local.MARKET_DEFINITION_NM)
LEFT JOIN rules_panel r_panel ON UPPER(m.MARKET_NM) = UPPER(r_panel.MARKET_DEFINITION_NM)
LEFT JOIN rules_product r_product ON UPPER(m.MARKET_NM) = UPPER(r_product.MARKET_DEFINITION_NM)
LEFT JOIN rules_product_local r_product_local ON UPPER(m.MARKET_NM) = UPPER(r_product_local.MARKET_DEFINITION_NM)
LEFT JOIN rules_rx_status r_rx_status ON UPPER(m.MARKET_NM) = UPPER(r_rx_status.MARKET_DEFINITION_NM)


WHERE UPPER(d.country)='UKRAINE'
    -- Apply build_condition for all columns
    AND (r_atc4.ATC4_VALUE = '' OR {{ build_condition('r_atc4.ATC4_OPERATOR', 'd.ATC4', 'r_atc4.ATC4_VALUE') }})
    AND (r_channel.CHANNEL_VALUE = '' OR {{ build_condition('r_channel.CHANNEL_OPERATOR', 'pnl.CHANNEL', 'r_channel.CHANNEL_VALUE') }})
    AND (r_chc_class.CHC_CLASS_VALUE = '' OR {{ build_condition('r_chc_class.CHC_CLASS_OPERATOR', 'd.CHC_CLASS', 'r_chc_class.CHC_CLASS_VALUE') }})
    AND (r_chc_form.CHC_FORM_VALUE = '' OR {{ build_condition('r_chc_form.CHC_FORM_OPERATOR', 'd.CHC_FORM', 'r_chc_form.CHC_FORM_VALUE') }})
    AND (r_class_type.CLASS_TYPE_VALUE = '' OR {{ build_condition('r_class_type.CLASS_TYPE_OPERATOR', 'pnl.CLASS_TYPE', 'r_class_type.CLASS_TYPE_VALUE') }})
    AND (r_corporation.CORPORATION_VALUE = '' OR {{ build_condition('r_corporation.CORPORATION_OPERATOR', 'd.CORPORATION', 'r_corporation.CORPORATION_VALUE') }})
    AND (r_corporation_local.CORPORATION_LOCAL_VALUE = '' OR {{ build_condition('r_corporation_local.CORPORATION_LOCAL_OPERATOR', 'd.CORPORATION_LOCAL', 'r_corporation_local.CORPORATION_LOCAL_VALUE') }})
    AND (r_country.COUNTRY_VALUE = '' OR {{ build_condition('r_country.COUNTRY_OPERATOR', 'd.COUNTRY', 'r_country.COUNTRY_VALUE') }})
    AND (r_manufacturer.MANUFACTURER_VALUE = '' OR {{ build_condition('r_manufacturer.MANUFACTURER_OPERATOR', 'd.MANUFACTURER', 'r_manufacturer.MANUFACTURER_VALUE') }})
    AND (r_molecule_list.MOLECULE_LIST_VALUE = '' OR {{ build_condition('r_molecule_list.MOLECULE_LIST_OPERATOR', 'd.MOLECULE_LIST', 'r_molecule_list.MOLECULE_LIST_VALUE') }})
    AND (r_molecule_list_local.MOLECULE_LIST_LOCAL_VALUE = '' OR {{ build_condition('r_molecule_list_local.MOLECULE_LIST_LOCAL_OPERATOR', 'd.MOLECULE_LIST_LOCAL', 'r_molecule_list_local.MOLECULE_LIST_LOCAL_VALUE') }})
    AND (r_nfc123.NFC123_VALUE = '' OR {{ build_condition('r_nfc123.NFC123_OPERATOR', 'd.NFC123', 'r_nfc123.NFC123_VALUE') }})
    AND (r_nfc123_local.NFC123_LOCAL_VALUE = '' OR {{ build_condition('r_nfc123_local.NFC123_LOCAL_OPERATOR', 'd.NFC123_LOCAL', 'r_nfc123_local.NFC123_LOCAL_VALUE') }})
    AND (r_pack.PACK_VALUE = '' OR {{ build_condition('r_pack.PACK_OPERATOR', 'd.PACK', 'r_pack.PACK_VALUE') }})
    AND (r_pack_local.PACK_LOCAL_VALUE = '' OR {{ build_condition('r_pack_local.PACK_LOCAL_OPERATOR', 'd.PACK_LOCAL', 'r_pack_local.PACK_LOCAL_VALUE') }})
    AND (r_panel.PANEL_VALUE = '' OR {{ build_condition('r_panel.PANEL_OPERATOR', 'pnl.PANEL', 'r_panel.PANEL_VALUE') }})
    AND (r_product.PRODUCT_VALUE = '' OR {{ build_condition('r_product.PRODUCT_OPERATOR', 'd.PRODUCT', 'r_product.PRODUCT_VALUE') }})
    AND (r_product_local.PRODUCT_LOCAL_VALUE = '' OR {{ build_condition('r_product_local.PRODUCT_LOCAL_OPERATOR', 'd.PRODUCT_LOCAL', 'r_product_local.PRODUCT_LOCAL_VALUE') }})
    AND (r_rx_status.RX_STATUS_VALUE = '' OR {{ build_condition('r_rx_status.RX_STATUS_OPERATOR', 'd.RX_STATUS', 'r_rx_status.RX_STATUS_VALUE') }})

