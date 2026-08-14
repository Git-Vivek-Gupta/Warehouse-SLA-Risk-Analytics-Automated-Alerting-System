CREATE TABLE zone_workload (
    order_id TEXT,
    zone TEXT,
    order_date DATE,
    store_id TEXT,
    priority_num INTEGER,
    sku_lines INTEGER,
    unique_skus INTEGER,
    total_qty NUMERIC,
    unique_bins INTEGER,
    total_weight_kg NUMERIC,
    total_volume_cm3 NUMERIC,
    zone_complexity_tier INTEGER,
    travel_seconds NUMERIC,
    pickup_seconds NUMERIC,
    base_work_seconds NUMERIC,
    base_work_minutes NUMERIC,
    simulated_work_seconds NUMERIC
);
select * from zone_workload
limit 20;

--Find the number of unique warehouse zones in the table.
SELECT COUNT(Distinct zone)
FROM zone_workload;

--Find how many unique orders belong to each priority level.
select priority_num, Count(Distinct order_id) as unique_orders
from zone_workload
group by priority_num;

--Find every order_id that is associated with more than one distinct priority_num.
select order_id, Count(Distinct priority_num) as double_priority
from zone_workload
group by order_id
having Count(Distinct priority_num)>1;

-- find for each zone:
-- Number of unique orders
-- Total quantity picked
-- Average quantity per order
select zone, Count(Distinct order_id) as unique_orders, Sum(total_qty) as picked_qty,  Avg(total_qty) as avg_qty_per_order
from zone_workload
group by zone;


SELECT
    zone,
    COUNT(DISTINCT order_id) AS unique_orders,
    AVG(total_qty) AS avg_qty_per_order,
    MAX(total_qty) AS max_qty_single_order
FROM zone_workload
GROUP BY zone
ORDER BY max_qty_single_order DESC;

-- For each zone, calculate:
-- total_work_minutes = sum of base_work_minutes
-- total_qty = sum of total_qty
-- order_count = distinct orders
SELECT
    zone,
    Sum(base_work_minutes) AS total_work_minutes,
    Sum(total_qty) AS total_qty,
    Count(distinct order_id) AS order_count
FROM zone_workload
GROUP BY zone;

--Which priority level creates the highest total picking workload?
SELECT
    priority_num,
    Sum(base_work_minutes) AS total_work_minutes,
    Sum(total_qty) AS total_qty,
    Count(distinct order_id) AS order_count
FROM zone_workload
GROUP BY priority_num
order by total_work_minutes DESC;

-- Which stores/PODs generate the most workload?
SELECT
    store_id,
    Sum(base_work_minutes) AS total_work_minutes,
    Sum(total_qty) AS total_qty,
    Count(distinct order_id) AS order_count
FROM zone_workload
GROUP BY store_id
order by total_work_minutes DESC
limit 10;

--Find zones where: Average base_work_minutes per order-zone is greater than 30 minutes.
SELECT
    zone,
    avg(base_work_minutes) AS avg_work_minutes,
    Count(distinct order_id) AS order_count
FROM zone_workload
GROUP BY zone
having avg(base_work_minutes)>30;

--Using zone_workload, find the top 10 order×zone rows with the highest base_work_minutes.
SELECT
    order_id, zone, total_qty, unique_bins,base_work_minutes
FROM zone_workload
order by base_work_minutes DESC
limit 10;

--Find zones where: base_work_minutes > 30 on average and the zone has more than 1500 distinct orders
SELECT
    zone,
    avg(base_work_minutes) AS avg_work_minutes,
    Count(distinct order_id) AS order_count
FROM zone_workload
GROUP BY zone
having avg(base_work_minutes)>30 and  Count(distinct order_id)>1500;

--Find the top 5 zones by total workload, but this time calculate workload using simulated_work_seconds.
SELECT
    zone,
    Sum(simulated_work_seconds) AS total_simulated_seconds,
    Sum(total_qty) AS total_qty,
    Count(distinct order_id) AS order_count
FROM zone_workload
GROUP BY zone
order by Sum(simulated_work_seconds) DESC
limit 5;

--Find which priority level has the highest average simulated workload per order-zone row.
SELECT
    priority_num,
    Sum(simulated_work_seconds) AS total_simulated_seconds,
    avg(simulated_work_seconds) AS avg_simulated_seconds,
    Count(distinct order_id) AS order_count
FROM zone_workload
GROUP BY priority_num
order by avg(simulated_work_seconds) DESC;

--Find the top 10 zones by average simulated seconds per SKU unit.
SELECT
    zone,
    Sum(simulated_work_seconds) AS total_simulated_seconds,
    Sum(total_qty) AS total_qty,
    (SUM(simulated_work_seconds) / SUM(total_qty)) AS simulated_seconds_per_unit
FROM zone_workload
GROUP BY zone
order by (SUM(simulated_work_seconds) / SUM(total_qty)) DESC
limit 10;

--Find all order_id + zone rows where base_work_minutes is greater than the overall average base_work_minutes across the entire table.
SELECT
	ORDER_ID,
	ZONE,
	TOTAL_QTY,
	UNIQUE_BINS,
	BASE_WORK_MINUTES
FROM
	ZONE_WORKLOAD
WHERE
	BASE_WORK_MINUTES > (
		SELECT
			AVG(BASE_WORK_MINUTES)
		FROM
			ZONE_WORKLOAD
	);

--Using zone_workload, find the zones whose total base_work_minutes is greater than the average total workload across all zones.
WITH zone_totals AS (
    SELECT
        zone,
        SUM(base_work_minutes) AS total_work_minutes
    FROM zone_workload
    GROUP BY zone
)
SELECT
    zone,
    total_work_minutes
FROM zone_totals
WHERE total_work_minutes > (
    SELECT AVG(total_work_minutes)
    FROM zone_totals
);

--create new table from existing table
drop table  if exists zone_master;

CREATE TABLE zone_master as (select 
							    zone,
							    zone_complexity_tier
								from zone_workload
							);

select * from zone_master
limit 20;

--Show each zone's complexity tier without duplicates.
SELECT Distinct w.zone, m.zone_complexity_tier
FROM zone_workload w
Join zone_master m
on w.zone = m.zone;

--Find any zones that exist in zone_master but do NOT exist in zone_workload.
SELECT Distinct m.zone
FROM zone_master m
left Join zone_workload w
on m.zone = w.zone
WHERE w.zone IS NULL;

--Find whether there are any zone_master rows where the zone_complexity_tier doesn't match the corresponding value in zone_workload.
SELECT DISTINCT
    w.zone,
    m.zone_complexity_tier AS master_tier,
    w.zone_complexity_tier AS workload_tier
FROM zone_master m
JOIN zone_workload w
    ON m.zone = w.zone
WHERE m.zone_complexity_tier <> w.zone_complexity_tier;

--
SELECT
    m.zone,
    m.zone_complexity_tier,
    SUM(w.base_work_minutes) AS total_work_minutes
FROM zone_master m
JOIN zone_workload w
    ON m.zone = w.zone
GROUP BY
    m.zone,
    m.zone_complexity_tier
ORDER BY total_work_minutes DESC;

--Using zone_workload, find the rank of each zone based on total base_work_minutes, highest workload = Rank 1.
SELECT
    zone,
    Sum(base_work_minutes) AS total_work_minutes,
    Rank() over(order by Sum(base_work_minutes) Desc) as workload_rank
FROM zone_workload
GROUP BY zone;

--For each zone, find the single order×zone row with the highest base_work_minutes.
SELECT
    zone,
    order_id,
    base_work_minutes
FROM (
    SELECT
        zone,
        order_id,
        base_work_minutes,
        ROW_NUMBER() OVER (
            PARTITION BY zone
            ORDER BY base_work_minutes DESC
        ) AS rn
    FROM zone_workload
) t
WHERE rn = 1;