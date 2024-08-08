CREATE OR REPLACE PROCEDURE tpcds.ANALYTICS.populating_weekly_aggregated_sales_incrementally()
  RETURNS VARCHAR
  LANGUAGE SQL
  EXECUTE AS CALLER
  AS
  $$
      DECLARE 
        LAST_SOLD_WK_SK  number;
    BEGIN
	-- Getting Last Date
SET LAST_SOLD_WK_SK = (SELECT MAX(SOLD_WK_SK) FROM TPCDS.ANALYTICS.WEEKLY_SALES_INVENTORY);

-- Removing partial records from the last date
DELETE FROM TPCDS.ANALYTICS.WEEKLY_SALES_INVENTORY WHERE sold_wk_sk=:LAST_SOLD_WK_SK;

-- compiling all incremental sales records
CREATE OR REPLACE TEMPORARY TABLE TPCDS.ANALYTICS.WEEKLY_SALES_INVENTORY_TMP AS (
with aggregating_daily_sales_to_week as (
SELECT 
    WAREHOUSE_SK, 
    ITEM_SK, 
    MIN(SOLD_DATE_SK) AS SOLD_WK_SK, 
    SOLD_WK_NUM, 
    SOLD_YR_NUM, 
    SUM(DAILY_QTY) AS SUM_QTY_WK, 
    SUM(DAILY_SALES_AMT) AS SUM_AMT_WK, 
    SUM(DAILY_NET_PROFIT) AS SUM_PROFIT_WK
FROM
    TPCDS.INTERMEDIATE.DAILY_AGGREGATED_SALES
GROUP BY
    1,2,4,5
HAVING 
    sold_wk_sk >= NVL(:LAST_SOLD_WK_SK,0)
),

-- We need to have the same sold_wk_sk for all the items. Currently, any items that didn't have any sales on Sunday (first day of the week) would not have Sunday date as sold_wk_sk so this CTE will correct that.
finding_first_date_of_the_week as (
SELECT 
    WAREHOUSE_SK, 
    ITEM_SK, 
    date.d_date_sk AS SOLD_WK_SK, 
    SOLD_WK_NUM, 
    SOLD_YR_NUM, 
    SUM_QTY_WK, 
    SUM_AMT_WK, 
    SUM_PROFIT_WK
FROM
    aggregating_daily_sales_to_week daily_sales
INNER JOIN TPCDS.RAW.DATE_DIM as date
on daily_sales.SOLD_WK_NUM=date.wk_num
and daily_sales.sold_yr_num=date.yr_num
and date.day_of_wk_num=0
),

-- This will help sales and inventory tables to join together using wk_num and yr_num
date_columns_in_inventory_table as (
SELECT 
    inventory.*,
    date.wk_num as inv_wk_num,
    date.yr_num as inv_yr_num
FROM
    tpcds.raw.inventory inventory
INNER JOIN TPCDS.RAW.DATE_DIM as date
on inventory.inv_date_sk = date.d_date_sk
)

select 
       warehouse_sk, 
       item_sk, 
       min(SOLD_WK_SK) as sold_wk_sk,
       sold_wk_num as sold_wk_num,
       sold_yr_num as sold_yr_num,
       sum(sum_qty_wk) as sum_qty_wk,
       sum(sum_amt_wk) as sum_amt_wk,
       sum(sum_profit_wk) as sum_profit_wk,
       sum(sum_qty_wk)/7 as avg_qty_dy,
       sum(coalesce(inv.inv_quantity_on_hand, 0)) as inv_qty_wk, 
       sum(coalesce(inv.inv_quantity_on_hand, 0)) / sum(sum_qty_wk) as wks_sply,
       iff(avg_qty_dy>0 and avg_qty_dy>inv_qty_wk, true , false) as low_stock_flg_wk
from finding_first_date_of_the_week
left join date_columns_in_inventory_table inv 
    on inv_wk_num = sold_wk_num and inv_yr_num = sold_yr_num and item_sk = inv_item_sk and inv_warehouse_sk = warehouse_sk
group by 1, 2, 4, 5
-- extra precaution because we don't want negative or zero quantities in our final model
having sum(sum_qty_wk) > 0
);

-- Inserting new records
INSERT INTO TPCDS.ANALYTICS.WEEKLY_SALES_INVENTORY
(	
	WAREHOUSE_SK, 
    ITEM_SK, 
    SOLD_WK_SK, 
    SOLD_WK_NUM, 
    SOLD_YR_NUM, 
    SUM_QTY_WK, 
    SUM_AMT_WK, 
    SUM_PROFIT_WK, 
    AVG_QTY_DY, 
    INV_QTY_WK, 
    WKS_SPLY, 
    LOW_STOCK_FLG_WK
    
)
SELECT 
    DISTINCT
	WAREHOUSE_SK, 
    ITEM_SK, 
    SOLD_WK_SK, 
    SOLD_WK_NUM, 
    SOLD_YR_NUM, 
    SUM_QTY_WK, 
    SUM_AMT_WK, 
    SUM_PROFIT_WK, 
    AVG_QTY_DY, 
    INV_QTY_WK, 
    WKS_SPLY, 
    LOW_STOCK_FLG_WK
FROM TPCDS.ANALYTICS.WEEKLY_SALES_INVENTORY_TMP;
  END
  $$;