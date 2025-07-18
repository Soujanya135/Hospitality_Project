select  count(*) from fact_bookings;

ALTER TABLE fact_bookings_sql 
MODIFY COLUMN check_in_date DATE;

ALTER TABLE fact_bookings_sql 
MODIFY COLUMN checkout_date DATE;

ALTER TABLE fact_bookings_sql 
MODIFY COLUMN booking_date DATE;

ALTER TABLE dim_date 
MODIFY COLUMN date DATE;

-- 1. Add new column
ALTER TABLE fact_aggregated_bookings
ADD COLUMN check_in_date_clean DATE;

-- 2. Convert old text to DATE format ('%d-%b-%y')
UPDATE fact_aggregated_bookings
SET check_in_date_clean = STR_TO_DATE(check_in_date, '%d-%b-%y');
--  This will work for '01-May-22', '13-Jul-22', etc.

-- 3. Drop old column
ALTER TABLE fact_aggregated_bookings
DROP COLUMN check_in_date;

-- 4. Rename new column
ALTER TABLE fact_aggregated_bookings
CHANGE check_in_date_clean check_in_date DATE;

-- Measures Q1-Q26
-- 1. Revenue
SELECT SUM(revenue_realized) AS total_revenue
FROM fact_bookings;

-- 2. Total Bookings
SELECT COUNT(booking_id) AS total_bookings
FROM fact_bookings;

-- 3. Total Capacity
SELECT SUM(capacity) AS total_capacity
FROM fact_aggregated_bookings;

-- 4. Total Successful Bookings
SELECT SUM(successful_bookings) AS total_successful_bookings
FROM fact_aggregated_bookings;

-- 5. Occupancy %
SELECT 
    (SUM(successful_bookings) * 100.0 / NULLIF(SUM(capacity), 0)) AS occupancy_percentage
FROM fact_aggregated_bookings;

-- 6. Average Rating
SELECT AVG(ratings_given) AS average_rating
FROM fact_bookings;

-- 7. No of Days
ALTER TABLE dim_date
MODIFY COLUMN date DATE;
SELECT DATEDIFF(MAX(date), MIN(date)) AS total_days
FROM dim_date;

-- 8. Total Cancelled Bookings
SELECT COUNT(*) AS cancelled_bookings
FROM fact_bookings
WHERE booking_status = 'Cancelled';

-- 9. Cancellation %
SELECT 
    (COUNT(CASE WHEN booking_status = 'Cancelled' THEN 1 END) * 100.0 / COUNT(*)) AS cancellation_percentage
FROM fact_bookings;

-- 10. Total Checked Out
SELECT COUNT(*) AS total_checked_out
FROM fact_bookings
WHERE booking_status = 'Checked Out';

-- 11. Total No Show Bookings
SELECT COUNT(*) AS total_no_show
FROM fact_bookings
WHERE booking_status = 'No Show';

-- 12. No Show Rate %
SELECT 
    (COUNT(CASE WHEN booking_status = 'No Show' THEN 1 END) * 100.0 / COUNT(*)) AS no_show_rate
FROM fact_bookings;
-- 13. Booking % by Platform
SELECT 
    booking_platform,
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS platform_percentage
FROM fact_bookings
GROUP BY booking_platform;

 -- % of Successful Bookings
SELECT 
    booking_status,
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM fact_bookings) AS percentage
FROM fact_bookings
GROUP BY booking_status;

-- 14. Booking % by Platform
SELECT 
    booking_platform,
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS platform_percentage
FROM fact_bookings
GROUP BY booking_platform;

-- 15.ADR 
SELECT 
    SUM(revenue_realized) * 1.0 / NULLIF(COUNT(*), 0) AS adr
FROM fact_bookings;

-- 17. RevPAR (Revenue per Available Room)
SELECT 
    (SELECT SUM(revenue_realized) FROM fact_bookings) * 1.0 /
    (SELECT SUM(capacity) FROM (
        SELECT DISTINCT property_id, check_in_date, capacity
        FROM fact_aggregated_bookings
    ) AS unique_cap) AS revpar;
    
-- 18. DBRN (Daily Booked Room Nights)
    SELECT 
    COUNT(*) * 1.0 / NULLIF(DATEDIFF(MAX(d.date), MIN(d.date)) + 1, 0) AS dbrn
FROM fact_bookings fb
JOIN dim_date d ON fb.check_in_date = d.date;

-- 19. DSRN (Daily Sellable Room Nights)
SELECT 
    SUM(fa.capacity) * 1.0 / NULLIF(DATEDIFF(MAX(d.date), MIN(d.date)) + 1, 0) AS dsrn
FROM fact_aggregated_bookings fa
JOIN dim_date d ON fa.check_in_date = d.date;

-- 20. DURN (Daily Utilized Room Nights)
SELECT 
    COUNT(*) * 1.0 / NULLIF(DATEDIFF(MAX(d.date), MIN(d.date)) + 1, 0) AS durn
FROM fact_bookings fb
JOIN dim_date d ON fb.checkout_date = d.date;

-- 21. Revenue WoW % Change
WITH revenue_by_week AS (
  SELECT 
    d.`week no` AS week_no,
    SUM(fb.revenue_realized) AS revenue
  FROM fact_bookings fb
  JOIN dim_date d ON fb.check_in_date = d.date
  GROUP BY d.`week no`
),
ranked_weeks AS (
  SELECT 
    week_no,
    revenue,
    ROW_NUMBER() OVER (ORDER BY week_no) AS rn
  FROM revenue_by_week
),
final AS (
  SELECT 
    curr.week_no,
    curr.revenue AS current_revenue,
    prev.revenue AS previous_revenue
  FROM ranked_weeks curr
  JOIN ranked_weeks prev ON curr.rn = prev.rn + 1
)
SELECT 
  week_no,
  ROUND(((current_revenue * 1.0) / NULLIF(previous_revenue, 0) - 1) * 100, 2) AS revenue_wow_change_percent
FROM final;

-- 22: Occupancy WoW % 
WITH occupancy_by_week AS (
  SELECT 
    d.`week no` AS week_no,
    COUNT(fb.booking_id) AS total_bookings,
    SUM(fa.capacity) AS total_capacity
  FROM fact_bookings_sql fb
  JOIN fact_aggregated_bookings fa ON fb.property_id = fa.property_id AND fb.check_in_date = fa.check_in_date
  JOIN dim_date d ON fb.check_in_date = d.date
  GROUP BY d.`week no`
),
ranked AS (
  SELECT 
    week_no,
    total_bookings * 1.0 / NULLIF(total_capacity, 0) AS occupancy,
    ROW_NUMBER() OVER (ORDER BY week_no) AS rn
  FROM occupancy_by_week
),
final AS (
  SELECT 
    curr.week_no,
    curr.occupancy AS current,
    prev.occupancy AS previous
  FROM ranked curr
  JOIN ranked prev ON curr.rn = prev.rn + 1
)
SELECT 
  week_no,
  ROUND(((current / NULLIF(previous, 0)) - 1) * 100, 2) AS occupancy_wow_change_percent
FROM final;

-- 23: ADR WoW % 
WITH adr_by_week AS (
  SELECT 
    d.`week no` AS week_no,
    SUM(fb.revenue_realized) * 1.0 / NULLIF(COUNT(fb.booking_id), 0) AS adr
  FROM fact_bookings fb
  JOIN dim_date d ON fb.check_in_date = d.date
  GROUP BY d.`week no`
),
ranked AS (
  SELECT week_no, adr, ROW_NUMBER() OVER (ORDER BY week_no) AS rn FROM adr_by_week
),
final AS (
  SELECT 
    curr.week_no,
    curr.adr AS current,
    prev.adr AS previous
  FROM ranked curr
  JOIN ranked prev ON curr.rn = prev.rn + 1
)
SELECT 
  week_no,
  ROUND(((current / NULLIF(previous, 0)) - 1) * 100, 2) AS adr_wow_change_percent
FROM final;

-- 24: RevPAR WoW % (Corrected)
WITH revpar_by_week AS (
  SELECT 
    d.`week no` AS week_no,
    SUM(fb.revenue_realized) * 1.0 / NULLIF(SUM(fa.capacity), 0) AS revpar
  FROM fact_bookings_sql fb
  JOIN fact_aggregated_bookings fa ON fb.property_id = fa.property_id AND fb.check_in_date = fa.check_in_date
  JOIN dim_date d ON fb.check_in_date = d.date
  GROUP BY d.`week no`
),
ranked AS (
  SELECT week_no, revpar, ROW_NUMBER() OVER (ORDER BY week_no) AS rn FROM revpar_by_week
),
final AS (
  SELECT 
    curr.week_no,
    curr.revpar AS current,
    prev.revpar AS previous
  FROM ranked curr
  JOIN ranked prev ON curr.rn = prev.rn + 1
)
SELECT 
  week_no,
  ROUND(((current / NULLIF(previous, 0)) - 1) * 100, 2) AS revpar_wow_change_percent
FROM final;

-- 25: Realisation WoW % 
WITH realisation_by_week AS (
  SELECT 
    d.`week no` AS week_no,
    SUM(fb.revenue_realized) * 1.0 / NULLIF(SUM(fb.revenue_generated), 0) AS realisation
  FROM fact_bookings_sql fb
  JOIN dim_date d ON fb.check_in_date = d.date
  GROUP BY d.`week no`
),
ranked AS (
  SELECT week_no, realisation, ROW_NUMBER() OVER (ORDER BY week_no) AS rn FROM realisation_by_week
),
final AS (
  SELECT 
    curr.week_no,
    curr.realisation AS current,
    prev.realisation AS previous
  FROM ranked curr
  JOIN ranked prev ON curr.rn = prev.rn + 1
)
SELECT 
  week_no,
  ROUND(((current / NULLIF(previous, 0)) - 1) * 100, 2) AS realisation_wow_change_percent
FROM final;

-- KPIs-Q1-Q10
-- Establishing joins
SELECT *
FROM fact_bookings_sql fb
JOIN dim_hotels dh ON fb.property_id = dh.property_id
JOIN dim_date dd ON fb.check_in_date = dd.date
JOIN dim_rooms dr ON fb.room_category = dr.room_id
JOIN fact_aggregated_bookings fab 
    ON fb.property_id = fab.property_id
   AND fb.check_in_date = fab.check_in_date
   AND fb.room_category = fab.room_category
JOIN dim_date dd2 ON fab.check_in_date = dd2.date
JOIN dim_rooms dr2 ON fab.room_category = dr2.room_id;

-- column creation
SELECT 
    date,
    DATE_FORMAT(date, '%b') AS Date_Month,         
    MONTH(date) AS Date_Month_Index,              
    WEEK(date, 1) AS wn                             
FROM dim_date;

-- 1
SELECT 
    DATE_FORMAT(d.date, '%b') AS Month_Name,
    ROUND(SUM(fb.revenue_realized)/1000000, 0) AS Revenue_Millions
FROM fact_bookings_sql fb
JOIN dim_date d ON DATE(fb.check_in_date) = d.date
-- WHERE fb.booking_status = 'Successful'  -- Uncomment once you know the correct status
GROUP BY Month_Name
ORDER BY STR_TO_DATE(Month_Name, '%b');

-- 2
SELECT 
    DATE_FORMAT(d.date, '%b') AS Month_Name,
    ROUND(SUM(fab.successful_bookings) * 100.0 / SUM(fab.capacity), 0) AS Occupancy_Percent
FROM fact_aggregated_bookings fab
JOIN dim_date d ON fab.check_in_date = d.date
GROUP BY Month_Name
ORDER BY STR_TO_DATE(Month_Name, '%b');

-- 3
SELECT 
    h.property_name,
    ROUND(SUM(CASE WHEN fb.booking_status = 'Cancelled' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS cancelled_percent
FROM fact_bookings_sql fb
JOIN dim_hotels h ON fb.property_id = h.property_id
GROUP BY h.property_name
ORDER BY cancelled_percent DESC;

-- 4
SELECT 
    booking_platform,
    COUNT(*) AS total_bookings
FROM fact_bookings_sql
GROUP BY booking_platform
ORDER BY total_bookings DESC;

-- 5
SELECT 
    IFNULL(dr.room_class, 'Grand Total') AS room_class,
    SUM(fab.successful_bookings) AS total_bookings,
    SUM(fab.capacity) AS total_capacity
FROM fact_aggregated_bookings fab
JOIN dim_rooms dr ON fab.room_category = dr.room_id
GROUP BY dr.room_class WITH ROLLUP;

-- 6
SELECT 
    IFNULL(DATE_FORMAT(d.date, '%b'), 'Grand Total') AS Month_Name,
    ROUND(SUM(fb.discount_applied)/1000000, 0) AS discount_millions,
    ROUND(SUM(fb.revenue_realized)/1000000, 0) AS revenue_millions
FROM fact_bookings_sql fb
JOIN dim_date d ON DATE(fb.check_in_date) = d.date
GROUP BY Month_Name WITH ROLLUP;

-- 7
SELECT 
    IFNULL(day_type, 'Grand Total') AS Row_Label,
    ROUND(SUM(revenue_realized) * 100.0 / 
          (SELECT SUM(revenue_realized) FROM fact_bookings_sql), 2) AS revenue_percent
FROM (
    SELECT 
        fb.revenue_realized,
        CASE 
            WHEN DAYOFWEEK(fb.check_in_date) BETWEEN 2 AND 6 THEN 'weekday'
            ELSE 'weekend'
        END AS day_type
    FROM fact_bookings_sql fb
) AS t
GROUP BY day_type WITH ROLLUP;

-- 8
SELECT 
    IFNULL(h.city, 'Grand Total') AS Row_Label,
    ROUND(SUM(fab.successful_bookings) * 100.0 / 
          (SELECT SUM(successful_bookings) FROM fact_aggregated_bookings), 2) AS booking_percent,
    ROUND(SUM(fab.successful_bookings) * 100.0 / SUM(fab.capacity), 2) AS occupancy_percent
FROM fact_aggregated_bookings fab
JOIN dim_hotels h ON fab.property_id = h.property_id
GROUP BY h.city WITH ROLLUP;

-- 9
SELECT 
    IFNULL(dr.room_class, 'Grand Total') AS Row_Label,
    ROUND(SUM(fb.revenue_realized) * 100.0 / 
         (SELECT SUM(revenue_realized) FROM fact_bookings_sql), 2) AS revenue_percent
FROM fact_bookings_sql fb
JOIN dim_rooms dr ON fb.room_category = dr.room_id
GROUP BY dr.room_class WITH ROLLUP;

-- 10
SELECT 
    IFNULL(fb.booking_status, 'Grand Total') AS Row_Label,
    COUNT(fb.booking_id) AS booking_count
FROM fact_bookings_sql fb
GROUP BY fb.booking_status WITH ROLLUP;
