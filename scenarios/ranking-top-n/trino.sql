-- Trino (formerly PrestoSQL): Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] Trino Documentation - Window Functions
--       https://trino.io/docs/current/functions/window.html
--   [2] Trino Documentation - SELECT
--       https://trino.io/docs/current/sql/select.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id INTEGER, customer_id INTEGER, amount DECIMAL(10,2), order_date DATE)

-- ============================================================
-- 1. Top-N 整体
-- ============================================================

SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
OFFSET 20 LIMIT 10;

-- FETCH FIRST（SQL 标准语法）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;

-- FETCH FIRST WITH TIES
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS WITH TIES;

-- ============================================================
-- 2. Top-N 分组
-- ============================================================

-- ROW_NUMBER() 方式
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rn
    FROM orders
) ranked
WHERE rn <= 3;

-- RANK() 方式
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           RANK() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rnk
    FROM orders
) ranked
WHERE rnk <= 3;

-- DENSE_RANK() 方式
SELECT *
FROM (
    SELECT order_id, customer_id, amount, order_date,
           DENSE_RANK() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS drnk
    FROM orders
) ranked
WHERE drnk <= 3;

-- ============================================================
-- 3. 关联子查询方式
-- ============================================================

SELECT o.*
FROM orders o
WHERE (
    SELECT COUNT(*)
    FROM orders o2
    WHERE o2.customer_id = o.customer_id
      AND o2.amount > o.amount
) < 3
ORDER BY o.customer_id, o.amount DESC;

-- ============================================================
-- 4. CTE 方式
-- ============================================================

WITH ranked_orders AS (
    SELECT order_id, customer_id, amount, order_date,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rn
    FROM orders
)
SELECT order_id, customer_id, amount, order_date
FROM ranked_orders
WHERE rn <= 3;

-- ============================================================
-- 5. 性能考量
-- ============================================================

-- Trino 是 MPP 查询引擎，窗口函数自动分布式执行
-- FETCH FIRST WITH TIES 在 Trino 中可用
-- 使用分区表和桶化优化分组 Top-N 查询
-- Trino 支持多种连接器（Hive, Iceberg, Delta Lake 等）
-- 注意：Trino 不支持 LATERAL / CROSS APPLY / QUALIFY
