{{ config(
    materialized='table',
    database='SL_SANDBOX'
) }}

SELECT *
FROM DF_FLASH_ANALYTICS.GOLD_MARKET_SALES.DIM_ATC