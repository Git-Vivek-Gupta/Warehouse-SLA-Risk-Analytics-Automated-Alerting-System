--1. Top 10 bottleneck zones
SELECT
    zone,
    SUM(base_work_minutes) AS total_work_minutes,
    COUNT(DISTINCT order_id) AS order_count,
    AVG(base_work_minutes) AS avg_work_minutes
FROM zone_workload
GROUP BY zone
ORDER BY total_work_minutes DESC
LIMIT 10;

--2. Zone efficiency — workload per unit
SELECT
    zone,
    SUM(base_work_minutes) AS total_work_minutes,
    SUM(total_qty) AS total_qty,
    SUM(base_work_minutes) / NULLIF(SUM(total_qty), 0) AS minutes_per_unit
FROM zone_workload
GROUP BY zone
ORDER BY minutes_per_unit DESC
LIMIT 10;

--3. Zone complexity vs workload
SELECT
    zone,
    zone_complexity_tier,
    SUM(base_work_minutes) AS total_work_minutes,
    AVG(base_work_minutes) AS avg_work_minutes,
    SUM(total_qty) AS total_qty
FROM zone_workload
GROUP BY zone, zone_complexity_tier
ORDER BY total_work_minutes DESC;

--4. Priority workload
SELECT
    priority_num,
    COUNT(DISTINCT order_id) AS order_count,
    SUM(total_qty) AS total_qty,
    SUM(base_work_minutes) AS total_work_minutes,
    AVG(base_work_minutes) AS avg_work_minutes
FROM zone_workload
GROUP BY priority_num
ORDER BY priority_num;

--5. Highest-work orders across zones
SELECT
    order_id,
    SUM(base_work_minutes) AS total_order_work_minutes,
    COUNT(DISTINCT zone) AS zones_touched,
    SUM(total_qty) AS total_qty
FROM zone_workload
GROUP BY order_id
ORDER BY total_order_work_minutes DESC
LIMIT 10;

--6. Zones with unusually high workload
WITH zone_avg AS (
    SELECT
        zone,
        AVG(base_work_minutes) AS avg_zone_work
    FROM zone_workload
    GROUP BY zone
),
overall_avg AS (
    SELECT AVG(base_work_minutes) AS overall_work
    FROM zone_workload
)
SELECT
    z.zone,
    z.avg_zone_work,
    o.overall_work
FROM zone_avg z
CROSS JOIN overall_avg o
WHERE z.avg_zone_work > o.overall_work
ORDER BY z.avg_zone_work DESC;

--7. Day-over-day zone workload — LAG()
WITH daily_zone AS (
    SELECT
        order_date,
        zone,
        SUM(base_work_minutes) AS daily_work_minutes
    FROM zone_workload
    GROUP BY order_date, zone
)
SELECT
    order_date,
    zone,
    daily_work_minutes,
    LAG(daily_work_minutes) OVER (
        PARTITION BY zone
        ORDER BY order_date
    ) AS previous_day_work_minutes,
    daily_work_minutes
      - LAG(daily_work_minutes) OVER (
            PARTITION BY zone
            ORDER BY order_date
        ) AS workload_change
FROM daily_zone
ORDER BY zone, order_date;

--8. Final bottleneck ranking
WITH zone_metrics AS (
    SELECT
        zone,
        SUM(base_work_minutes) AS total_work_minutes,
        AVG(base_work_minutes) AS avg_work_minutes,
        SUM(total_qty) AS total_qty,
        COUNT(DISTINCT order_id) AS order_count
    FROM zone_workload
    GROUP BY zone
)
SELECT
    zone,
    total_work_minutes,
    avg_work_minutes,
    total_qty,
    order_count,
    RANK() OVER (
        ORDER BY total_work_minutes DESC
    ) AS workload_rank
FROM zone_metrics
ORDER BY workload_rank;