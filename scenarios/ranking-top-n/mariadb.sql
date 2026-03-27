-- MariaDB: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] MariaDB Documentation - Window Functions
--       https://mariadb.com/kb/en/window-functions/
--   [2] MariaDB Documentation - LIMIT
--       https://mariadb.com/kb/en/limit/

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id INT AUTO_INCREMENT, customer_id INT, amount DECIMAL(10,2), order_date DATE)

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
LIMIT 10 OFFSET 20;

-- ============================================================
-- 2. Top-N 分组（MariaDB 10.2+ 窗口函数）
-- ============================================================

-- ROW_NUMBER() 方式（MariaDB 10.2+）
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
-- 3. MariaDB 10.1 及以下（无窗口函数）
-- ============================================================

-- 关联子查询方式
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
-- 4. CTE 方式（MariaDB 10.2+）
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
-- 5. LATERAL 派生表（MariaDB 10.6+）
-- ============================================================

-- MariaDB 10.6+ 支持 LATERAL
SELECT c.customer_id, t.order_id, t.amount
FROM (SELECT DISTINCT customer_id FROM orders) c,
LATERAL (
    SELECT order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
    LIMIT 3
) t;

-- ============================================================
-- 6. 性能考量
-- ============================================================

CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);

-- 窗口函数从 MariaDB 10.2 开始支持
-- CTE 从 MariaDB 10.2 开始支持
-- LATERAL 从 MariaDB 10.6 开始支持
-- 注意：MariaDB 不支持 QUALIFY / CROSS APPLY / FETCH FIRST WITH TIES
