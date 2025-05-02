############################################
############################################

## Amount of events during given period 5242
## November 1998
## December 2340
## January 904
SELECT
  user_pseudo_id,
  FORMAT_TIMESTAMP('%Y-%m-%d', TIMESTAMP_MICROS(event_timestamp)) AS event_date,
  event_name,
  purchase_revenue_in_usd,
FROM
  `turing_data_analytics.raw_events`
WHERE
  event_name = 'purchase'
  AND purchase_revenue_in_usd > 0
ORDER BY event_date;
  AND PARSE_DATE('%Y-%m-%d', FORMAT_TIMESTAMP('%Y-%m-%d', TIMESTAMP_MICROS(event_timestamp))) BETWEEN DATE('2021-01-01') AND DATE('2021-01-31');

############################################
############################################

##      New Users in the site 270154

select 
distinct user_pseudo_id
from `turing_data_analytics.raw_events`;

##     New users each month  

WITH first_month_users AS (
  SELECT
    user_pseudo_id,
    MIN(FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(event_timestamp))) AS first_month
  FROM `turing_data_analytics.raw_events`
  GROUP BY user_pseudo_id)
SELECT
  first_month AS event_month,
  COUNT(user_pseudo_id) AS distinct_user_count
FROM first_month_users
GROUP BY event_month
ORDER BY event_month;

##      users count for each day

WITH first_day_users AS (
  SELECT
    user_pseudo_id,
    MIN(FORMAT_TIMESTAMP('%Y-%m-%d', TIMESTAMP_MICROS(event_timestamp))) AS first_day
  FROM `turing_data_analytics.raw_events`
  GROUP BY user_pseudo_id)
SELECT
  first_day AS event_date,
  COUNT(user_pseudo_id) AS daily_user_count
FROM first_day_users
GROUP BY event_date
ORDER BY event_date;

##     Returning users count (2020-12 4651; 2021-01 3721)

WITH first_month_users AS (
  SELECT
    user_pseudo_id,
    MIN(FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(event_timestamp))) AS first_month
  FROM `turing_data_analytics.raw_events`
  GROUP BY user_pseudo_id),
user_activity AS (
  SELECT
    user_pseudo_id,
    FORMAT_TIMESTAMP('%Y-%m', TIMESTAMP_MICROS(event_timestamp)) AS activity_month
  FROM `turing_data_analytics.raw_events`),
returning_users AS (
  SELECT
    ua.activity_month,
    ua.user_pseudo_id
  FROM user_activity ua
  JOIN first_month_users fmu
    ON ua.user_pseudo_id = fmu.user_pseudo_id
  WHERE ua.activity_month > fmu.first_month -- Only include months after the first month
)
SELECT
  activity_month AS event_month,
  COUNT(DISTINCT user_pseudo_id) AS returning_user_count
FROM returning_users
GROUP BY activity_month
ORDER BY activity_month;

##      revenue count for all purchases each day

WITH first_day_events AS (
  SELECT
    FORMAT_TIMESTAMP('%Y-%m-%d', TIMESTAMP_MICROS(event_timestamp)) AS event_date,
    event_value_in_usd
  FROM `turing_data_analytics.raw_events`
  WHERE event_value_in_usd IS NOT NULL -- Ensure only rows with valid event values
)
SELECT
  event_date,
  SUM(event_value_in_usd) AS daily_event_value
FROM first_day_events
GROUP BY event_date
ORDER BY event_date;


############################################
############################################
-- daily count of purchases made by unique users 

WITH customer_purchases AS (
  SELECT
    user_pseudo_id,
    COUNTIF(event_name = 'purchase') AS purchase_count -- Count purchases per user
  FROM `turing_data_analytics.raw_events`
  GROUP BY user_pseudo_id
),
single_purchase_users AS (
  SELECT
    user_pseudo_id
  FROM customer_purchases
  WHERE purchase_count = 1 -- Retain only customers with 1 purchase
),
filtered_events AS (
  SELECT
    FORMAT_TIMESTAMP('%Y-%m-%d', TIMESTAMP_MICROS(event_timestamp)) AS event_date,
    event_value_in_usd
  FROM `turing_data_analytics.raw_events` re
  JOIN single_purchase_users spu
    ON re.user_pseudo_id = spu.user_pseudo_id -- Filter only events from single-purchase customers
  WHERE event_value_in_usd IS NOT NULL -- Ensure valid event values
)
SELECT
  event_date,
  SUM(event_value_in_usd) AS daily_event_value_unique_customers
FROM filtered_events
GROUP BY event_date
ORDER BY event_date;

##
-- check what is wrong with 11-20 - 11-23, only returning users purchased those days
##

-- select 
-- user_pseudo_id,
-- event_timestamp,
-- FORMAT_TIMESTAMP('%Y-%m-%d', TIMESTAMP_MICROS(event_timestamp)) AS event_date,
-- event_value_in_usd
-- from `turing_data_analytics.raw_events`
-- where event_name = 'purchase' AND event_value_in_usd IS NOT NULL 
-- AND FORMAT_TIMESTAMP('%Y-%m-%d', TIMESTAMP_MICROS(event_timestamp)) = '2020-11-19'
-- ORDER BY user_pseudo_id;

-- select *
-- from `turing_data_analytics.raw_events`
-- where user_pseudo_id = '8156646657.1507119761';

############################################
########## TIME TO PURCHASE ################
############################################

-- total events row is smaller (5086) than initial (5242) because this is only considering those events, 
-- where session start happened on the same day as purchase (and before purchase event)
-- If multiple purchases were done by same account time from first session start was calculated
-- (purchases on 01-31 all without event value, so had to clean it)

WITH ranked_events AS (
  SELECT 
    FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', TIMESTAMP_MICROS(user_first_touch_timestamp)) AS user_first_touch_date_time,
    TIMESTAMP_MICROS(event_timestamp) AS event_timestamp,
    event_name,
    event_value_in_usd,
    user_id,
    user_pseudo_id,
    DATE(TIMESTAMP_MICROS(event_timestamp)) AS event_date,
    ROW_NUMBER() OVER (PARTITION BY user_pseudo_id, DATE(TIMESTAMP_MICROS(event_timestamp)) ORDER BY event_timestamp) AS session_start_rank
  FROM `turing_data_analytics.raw_events`
  WHERE event_name IN ('session_start', 'purchase')),

session_start_times AS (
  SELECT
    user_pseudo_id,
    event_date,
    MIN(event_timestamp) AS session_start_timestamp -- First session_start timestamp of the day
  FROM ranked_events
  WHERE event_name = 'session_start'
  GROUP BY user_pseudo_id, event_date),

purchase_events AS (
  SELECT 
    user_pseudo_id,
    event_date,
    event_timestamp AS purchase_timestamp,
    event_value_in_usd
  FROM ranked_events
  WHERE event_name = 'purchase' AND event_value_in_usd > 0)

SELECT 
  ss.user_pseudo_id,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', ss.session_start_timestamp) AS session_start_event_date_time,
  FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', pe.purchase_timestamp) AS purchase_event_date_time,
  pe.event_value_in_usd,
  CAST(TIMESTAMP_DIFF(pe.purchase_timestamp, ss.session_start_timestamp, SECOND) AS INT64) AS time_to_purchase -- Time difference
FROM session_start_times ss
JOIN purchase_events pe
  ON ss.user_pseudo_id = pe.user_pseudo_id
  AND ss.event_date = pe.event_date
  AND pe.purchase_timestamp >= ss.session_start_timestamp -- Ensure positive time difference
ORDER BY ss.user_pseudo_id, ss.session_start_timestamp, pe.purchase_timestamp;

######################################

top 5 countries
WITH AggregatedEvents AS (
    SELECT 
        user_pseudo_id,
        event_name,
        MIN(event_timestamp) AS first_event_timestamp
    FROM 
        `turing_data_analytics.raw_events`
    GROUP BY 
        event_name, user_pseudo_id)
SELECT 
    raw_events.country,  -- Select the country column
    COUNT(*) AS event_count  -- Count the number of events per country
FROM 
    `turing_data_analytics.raw_events` raw_events
JOIN 
    AggregatedEvents agg 
    ON 
        raw_events.user_pseudo_id = agg.user_pseudo_id 
        AND raw_events.event_name = agg.event_name 
        AND raw_events.event_timestamp = agg.first_event_timestamp
GROUP BY 
    raw_events.country  -- Group by country to aggregate counts
ORDER BY 
    event_count DESC  
LIMIT 5;

############################################
################ FUNNELS ###################
############################################

-- Clean data
WITH AggregatedEvents AS (
    SELECT 
        user_pseudo_id,
        event_name,
        MIN(event_timestamp) AS first_event_timestamp
    FROM `turing_data_analytics.raw_events`
    GROUP BY event_name, user_pseudo_id
)
SELECT 
    raw_events.*
FROM 
    `turing_data_analytics.raw_events` raw_events
JOIN 
    AggregatedEvents agg 
    ON raw_events.user_pseudo_id = agg.user_pseudo_id 
    AND raw_events.event_name = agg.event_name 
    AND raw_events.event_timestamp = agg.first_event_timestamp
ORDER BY 
    raw_events.event_timestamp;

-- Find events for funnel analysis
WITH AggregatedEvents AS (
    SELECT 
        user_pseudo_id,
        event_name,
        MIN(event_timestamp) AS first_event_timestamp
    FROM 
        `turing_data_analytics.raw_events`
    GROUP BY 
        event_name, user_pseudo_id
)
SELECT 
    raw_events.event_name,  
    COUNT(*) AS event_count -- Count the occurrences of each event_name
FROM 
    `turing_data_analytics.raw_events` raw_events
JOIN 
    AggregatedEvents agg 
    ON 
        raw_events.user_pseudo_id = agg.user_pseudo_id 
        AND raw_events.event_name = agg.event_name 
        AND raw_events.event_timestamp = agg.first_event_timestamp
GROUP BY 
    raw_events.event_name -- Group by event_name to aggregate counts
ORDER BY 
    event_count DESC; 

-- Find top 3 countries
WITH AggregatedEvents AS (
    SELECT 
        user_pseudo_id,
        event_name,
        MIN(event_timestamp) AS first_event_timestamp
    FROM 
        `turing_data_analytics.raw_events`
    GROUP BY 
        event_name, user_pseudo_id
)
SELECT 
    raw_events.country,  -- Select the country column
    COUNT(*) AS event_count  -- Count the number of events per country
FROM 
    `turing_data_analytics.raw_events` raw_events
JOIN 
    AggregatedEvents agg 
    ON 
        raw_events.user_pseudo_id = agg.user_pseudo_id 
        AND raw_events.event_name = agg.event_name 
        AND raw_events.event_timestamp = agg.first_event_timestamp
GROUP BY 
    raw_events.country  -- Group by country to aggregate counts
ORDER BY 
    event_count DESC  
LIMIT 10;

-- Find aggregated and top3 countries selected funnels
WITH AggregatedEvents AS (
    SELECT 
        user_pseudo_id,
        event_name,
        MIN(event_timestamp) AS first_event_timestamp
    FROM 
        `turing_data_analytics.raw_events`
    WHERE 
        event_name IN ('session_start', 'scroll', 'view_item', 'add_to_cart', 'add_payment_info', 'purchase')
    GROUP BY 
        event_name, user_pseudo_id
)
SELECT 
    raw_events.event_name,                            
    COUNT(*) AS event_count,       -- Count the total occurrences of each event_name
    SUM(CASE WHEN raw_events.country = 'United States' THEN 1 ELSE 0 END) AS US_count,   
    SUM(CASE WHEN raw_events.country = 'India' THEN 1 ELSE 0 END) AS India_count,        
    SUM(CASE WHEN raw_events.country = 'Canada' THEN 1 ELSE 0 END) AS Canada_count       
FROM 
    `turing_data_analytics.raw_events` raw_events
JOIN 
    AggregatedEvents agg 
    ON 
        raw_events.user_pseudo_id = agg.user_pseudo_id 
        AND raw_events.event_name = agg.event_name 
        AND raw_events.event_timestamp = agg.first_event_timestamp
WHERE
    raw_events.event_name IN ('session_start', 'scroll', 'view_item', 'add_to_cart', 'add_payment_info', 'purchase')
GROUP BY 
    raw_events.event_name 
ORDER BY 
    event_count DESC;  
