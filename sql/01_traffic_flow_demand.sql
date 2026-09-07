/*

TRAFFIC FLOW & DEMAND ANALYSIS

OBJECTIVE:
This analysis examines the temporal and spatial patterns of traffic demand
across the smart-city transportation network. It establishes baseline traffic
behavior across intersections, city zones, road types, hours, and weekdays,
then identifies periods of unusually high traffic activity.

The primary objectives are to:
• Characterize hourly and weekly traffic-demand patterns.
• Identify hours with substantial weekday traffic increases over weekends.
• Detect high-traffic periods within individual city zones and road types.

Traffic volume is primarily represented by traffic_flow_rate, while medians
and percentile-based thresholds are used to provide robust comparisons across
groups and time periods.
========================
*/


/*
All 100 intersection IDs have the same count (2040)
*/
SELECT
  intersection_id,
  COUNT(*) AS counts,
  COUNT(*)/SUM(COUNT(*)) OVER() AS prop
FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
GROUP BY intersection_id
ORDER BY counts DESC;

/*
Suburban North (26%) -> Financial District (24%) -> Downtown Core (22%) -> Tech Park (11%) -> Residential West (9%) -> Industrial East (8%)
*/
SELECT
  city_zone,
  COUNT(*) AS counts,
  COUNT(*)/SUM(COUNT(*)) OVER() AS prop
FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
GROUP BY city_zone
ORDER BY counts DESC;

/*
Arterial (41%) -> Collector (28%) -> Highway (17%) -> Local Street (14%)
*/
SELECT
  road_type,
  COUNT(*) AS counts,
  COUNT(*)/SUM(COUNT(*)) OVER() AS prop
FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
GROUP BY road_type
ORDER BY counts DESC;

-- traffic_flow_rate & vehicle_count are the same thing!!!!
SELECT 
  vehicle_count, traffic_flow_rate,
FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
WHERE vehicle_count!=traffic_flow_rate;


  


-- How do vehicle activities change across hours? 
SELECT 
  hour, 
  APPROX_QUANTILES(vehicle_count,100)[OFFSET(50)]          AS median_vehicle_count,
  APPROX_QUANTILES(heavy_vehicle_count,100)[OFFSET(50)]    AS median_heavy_vehicle_count,
  APPROX_QUANTILES(motorcycle_count,100)[OFFSET(50)]       AS median_motorcycle_count,
  APPROX_QUANTILES(public_transport_count,100)[OFFSET(50)] AS median_public_transport_count
FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
GROUP BY hour ORDER BY hour;

-- How do traffic statistics change across hours?
SELECT 
  hour, 
  APPROX_QUANTILES(traffic_density,100)[OFFSET(50)]   AS median_traffic_density,
  APPROX_QUANTILES(traffic_flow_rate,100)[OFFSET(50)] AS median_traffic_flow_rate
FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
GROUP BY hour ORDER BY hour;

-- Higher (and uniform) traffic density, traffic flow rate, & vehicle counts on weekdays compared to weekends
SELECT 
  CASE 
    WHEN day_of_week=0 THEN "Monday"
    WHEN day_of_week=1 THEN "Tuesday"
    WHEN day_of_week=2 THEN "Wednesday"
    WHEN day_of_week=3 THEN "Thursday"
    WHEN day_of_week=4 THEN "Friday"
    WHEN day_of_week=5 THEN "Saturday"
    WHEN day_of_week=6 THEN "Sunday"
  END AS day_of_week_string,
  -- vehicle counts
  APPROX_QUANTILES(heavy_vehicle_count,100)[OFFSET(50)]    AS median_heavy_vehicle_count,
  APPROX_QUANTILES(motorcycle_count,100)[OFFSET(50)]       AS median_motorcycle_count,
  APPROX_QUANTILES(public_transport_count,100)[OFFSET(50)] AS median_public_transport_count,
  -- traffic statistics
  APPROX_QUANTILES(traffic_density,100)[OFFSET(50)]   AS median_traffic_density,
  APPROX_QUANTILES(traffic_flow_rate,100)[OFFSET(50)] AS median_traffic_flow_rate,
FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
GROUP BY day_of_week ORDER BY day_of_week;





/*
=======================================================================================================================================
QUESTION 1:
During which hours do BOTH vehicle traffic volume and traffic density exhibit unusually large weekday increases relative to weekends?

ANSWER: 
7-9AM and 4-7PM
=======================================================================================================================================
*/
-- Finds weekday percent change in traffic density relative to weekend
WITH density_change AS(
SELECT 
  *,
  100*SAFE_DIVIDE(weekday_median_traffic_density - weekend_median_traffic_density, weekend_median_traffic_density)
  AS weekday_pct_chg_traffic_density

FROM(
  SELECT
    hour,
    APPROX_QUANTILES(CASE WHEN is_weekend=0 THEN traffic_density END,100)[OFFSET(50)] AS weekday_median_traffic_density,
    APPROX_QUANTILES(CASE WHEN is_weekend=1 THEN traffic_density END,100)[OFFSET(50)] AS weekend_median_traffic_density,
  FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
  GROUP BY hour 
) AS t),
-- Finds weekday percent change in traffic flow rate relative to weekend
flow_change AS(
SELECT 
  *,
  100*SAFE_DIVIDE(weekday_median_traffic_flow_rate - weekend_median_traffic_flow_rate, weekend_median_traffic_flow_rate)
  AS weekday_pct_chg_traffic_flow_rate

FROM(
  SELECT
    hour,
    APPROX_QUANTILES(CASE WHEN is_weekend=0 THEN traffic_flow_rate END,100)[OFFSET(50)] AS weekday_median_traffic_flow_rate,
    APPROX_QUANTILES(CASE WHEN is_weekend=1 THEN traffic_flow_rate END,100)[OFFSET(50)] AS weekend_median_traffic_flow_rate,
  FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
  GROUP BY hour 
) AS t),


intermediate_pct_change_table AS(
SELECT 
  density_change.hour AS hour,
  flow_change.weekday_pct_chg_traffic_flow_rate  AS flow_rate_pct_change,
  density_change.weekday_pct_chg_traffic_density AS traffic_density_pct_change
FROM density_change 
INNER JOIN flow_change 
  ON density_change.hour = flow_change.hour  
),

thresholds AS(
  SELECT
    APPROX_QUANTILES(flow_rate_pct_change,100)[OFFSET(75)]       AS flow_rate_p75,
    APPROX_QUANTILES(traffic_density_pct_change,100)[OFFSET(75)] AS density_p75,
  FROM intermediate_pct_change_table
),

final_pct_change_table AS(
SELECT 
  p.*,
  t.*,
  p.flow_rate_pct_change >= t.flow_rate_p75     AS high_flow_change,
  p.traffic_density_pct_change >= t.density_p75 AS high_density_change,
FROM intermediate_pct_change_table AS p
CROSS JOIN thresholds AS t
ORDER BY p.hour
)

-- high hours are {7-9AM, 4-7PM}
SELECT * 
FROM final_pct_change_table
WHERE high_flow_change=true AND high_density_change=true;





/*
===========================================================================================================================
QUESTION 2:

Which hours have traffic volume unusually high relative to that city zone’s typical hourly pattern?
Which hours have traffic volume unusually high relative to that road’s typical hourly pattern?
===========================================================================================================================
*/
SELECT
  hour,
  -- Suburban North traffic volume
  APPROX_QUANTILES(
    CASE WHEN city_zone="Suburban North" THEN traffic_flow_rate END,100
  )[OFFSET(50)] AS sub_north_traffic_volume,
  -- Financial District traffic volume
  APPROX_QUANTILES(
    CASE WHEN city_zone="Financial District" THEN traffic_flow_rate END,100
  )[OFFSET(50)] AS fin_district_traffic_volume,
  -- Downtown Core traffic volume
  APPROX_QUANTILES(
    CASE WHEN city_zone="Downtown Core" THEN traffic_flow_rate END,100
  )[OFFSET(50)] AS downtown_core_traffic_volume,
  -- Tech Park traffic volume
  APPROX_QUANTILES(
    CASE WHEN city_zone="Tech Park" THEN traffic_flow_rate END,100
  )[OFFSET(50)] AS tech_park_traffic_volume,
  -- Residential West traffic volume
  APPROX_QUANTILES(
    CASE WHEN city_zone="Residential West" THEN traffic_flow_rate END,100
  )[OFFSET(50)] AS res_west_traffic_volume,
  -- Industrial East traffic volume
  APPROX_QUANTILES(
    CASE WHEN city_zone="Industrial East" THEN traffic_flow_rate END,100
  )[OFFSET(50)] AS indus_east_traffic_volume,
FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
GROUP BY hour ORDER BY hour; 


SELECT
  hour,
  -- Arterial rd traffic volume
  APPROX_QUANTILES(
    CASE WHEN road_type="Arterial" THEN traffic_flow_rate END,100
  )[OFFSET(50)] AS arterial_rd_traffic_volume,
  -- Collector rd traffic volume
  APPROX_QUANTILES(
    CASE WHEN road_type="Collector" THEN traffic_flow_rate END,100
  )[OFFSET(50)] AS collector_rd_traffic_volume,
  -- Highway rd traffic volume
  APPROX_QUANTILES(
    CASE WHEN road_type="Highway" THEN traffic_flow_rate END,100
  )[OFFSET(50)] AS highway_rd_traffic_volume,
  -- Local Street rd traffic volume
  APPROX_QUANTILES(
    CASE WHEN road_type="Local Street" THEN traffic_flow_rate END,100
  )[OFFSET(50)] AS local_street_rd_traffic_volume,
FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
GROUP BY hour ORDER BY hour; 



-- Computes median traffic volume for each city zone per hour
WITH city_hour_traffic AS(
  SELECT 
    hour,
    city_zone,
    APPROX_QUANTILES(traffic_flow_rate,100)[OFFSET(50)] AS traffic_volume,
  FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
  GROUP BY hour, city_zone),
-- Computes 75th percentile traffic volume for each city zone, aggregated across all hours
thresholds AS(
  SELECT
    city_zone,
    APPROX_QUANTILES(traffic_volume,100)[OFFSET(75)] volume_p75,
  FROM city_hour_traffic
  GROUP BY city_zone)
-- Find the hours which traffic volumes >= 75th percentile for each city zone
SELECT 
  city_zone,
  ARRAY_AGG(hour ORDER BY hour) AS high_traffic_hours
FROM(
  SELECT 
    c.*,
    c.traffic_volume >= t.volume_p75 AS high_traffic
  FROM city_hour_traffic as c
  INNER JOIN thresholds as t
    ON c.city_zone = t.city_zone) AS flagged_hours
WHERE high_traffic=true
GROUP BY city_zone ORDER BY city_zone;



-- Computes median traffic volume for each road type per hour
WITH road_hour_traffic AS(
  SELECT 
    hour,
    road_type,
    APPROX_QUANTILES(traffic_flow_rate,100)[OFFSET(50)] AS traffic_volume,
  FROM `traffic-urban-mobility.traffic_dataset.traffic_table`
  GROUP BY hour, road_type),
-- Computes 75th percentile traffic volume for each road type, aggregated across all hours
thresholds AS(
  SELECT
    road_type,
    APPROX_QUANTILES(traffic_volume,100)[OFFSET(75)] volume_p75,
  FROM road_hour_traffic
  GROUP BY road_type)
-- Find the hours which traffic volumes >= 75th percentile for each road type
SELECT 
  road_type,
  ARRAY_AGG(hour ORDER BY hour) AS high_traffic_hours
FROM(
  SELECT 
    c.*,
    c.traffic_volume >= t.volume_p75 AS high_traffic
  FROM road_hour_traffic as c
  INNER JOIN thresholds as t
    ON c.road_type = t.road_type) AS flagged_hours
WHERE high_traffic=true
GROUP BY road_type ORDER BY road_type;

