CREATE OR REPLACE TASK tpcds.intermediate.creating_daily_aggregated_sales_incrementally
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON * 8 * * * UTC'
    AS
CALL populating_daily_aggregated_sales_incrementally();

CREATE OR REPLACE TASK tpcds.analytics.creating_weekly_aggregated_sales_incrementally
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON * 8 * * * UTC'
    AS
CALL populating_weekly_aggregated_sales_incrementally();

ALTER TASK tpcds.intermediate.creating_daily_aggregated_sales_incrementally RESUME;

EXECUTE TASK tpcds.intermediate.creating_daily_aggregated_sales_incrementally;


ALTER TASK tpcds.analytics.creating_weekly_aggregated_sales_incrementally RESUME;

EXECUTE TASK tpcds.analytics.creating_weekly_aggregated_sales_incrementally;
