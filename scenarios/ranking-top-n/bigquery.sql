-- BigQuery: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] BigQuery Documentation - Analytic Functions
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/analytic-function-concepts
--   [2] BigQuery Documentation - QUALIFY
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#qualify_clause

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   project.dataset.orders(order_id INT64, customer_id INT64, amount NUMERIC, order_date DATE)

-- ============================================================
-- 1. Top-N 整体
-- ============================================================

-- LIMIT 语法
SELECT order_id, customer_id, amount
FROM `project.dataset.orders`
ORDER BY amount DESC
LIMIT 10;

-- LIMIT + OFFSET
SELECT order_id, customer_id, amount
FROM `project.dataset.orders`
ORDER BY amount DESC
LIMIT 10 OFFSET 20;

-- ============================================================
-- 2. Top-N 分组 + QUALIFY（BigQuery 支持）
-- ============================================================

-- QUALIFY 直接过滤窗口函数结果
SELECT order_id, customer_id, amount, order_date
FROM `project.dataset.orders`
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

-- QUALIFY + RANK
SELECT order_id, customer_id, amount, order_date
FROM `project.dataset.orders`
QUALIFY RANK() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

-- QUALIFY + DENSE_RANK
SELECT order_id, customer_id, amount, order_date
FROM `project.dataset.orders`
QUALIFY DENSE_RANK() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

-- QUALIFY 与 WHERE 组合
SELECT order_id, customer_id, amount, order_date
FROM `project.dataset.orders`
WHERE order_date >= '2024-01-01'
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

-- ============================================================
-- 3. 传统子查询方式
-- ============================================================

SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rn
    FROM `project.dataset.orders`
) ranked
WHERE rn <= 3;

-- ============================================================
-- 4. ARRAY_AGG 方式（BigQuery 特色）
-- ============================================================

-- 使用 ARRAY_AGG + UNNEST 取每组前 N
SELECT customer_id,
       top_order.order_id,
       top_order.amount
FROM (
    SELECT customer_id,
           ARRAY_AGG(
               STRUCT(order_id, amount)
               ORDER BY amount DESC
               LIMIT 3
           ) AS top_orders
    FROM `project.dataset.orders`
    GROUP BY customer_id
),
UNNEST(top_orders) AS top_order;

-- ============================================================
-- 5. 关联子查询方式
-- ============================================================

SELECT o.*
FROM `project.dataset.orders` o
WHERE (
    SELECT COUNT(*)
    FROM `project.dataset.orders` o2
    WHERE o2.customer_id = o.customer_id
      AND o2.amount > o.amount
) < 3
ORDER BY o.customer_id, o.amount DESC;

-- ============================================================
-- 6. 性能考量
-- ============================================================

-- BigQuery 无需手动创建索引（列式存储自动优化）
-- QUALIFY 是 BigQuery 推荐的方式
-- ARRAY_AGG + LIMIT 在某些场景下更高效（减少中间数据量）
-- 大表建议使用分区表和聚集列减少扫描
-- BigQuery 按扫描数据量计费，QUALIFY 不会额外增加扫描量
-- 注意：BigQuery 不支持 LATERAL / CROSS APPLY
