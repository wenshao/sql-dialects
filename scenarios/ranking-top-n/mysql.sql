-- MySQL: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - Window Functions
--       https://dev.mysql.com/doc/refman/8.0/en/window-functions.html
--   [2] MySQL 8.0 Reference Manual - LIMIT
--       https://dev.mysql.com/doc/refman/8.0/en/select.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id INT AUTO_INCREMENT, customer_id INT, amount DECIMAL(10,2), order_date DATE)

-- ============================================================
-- 1. Top-N 整体
-- ============================================================

-- LIMIT 语法
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

-- LIMIT + OFFSET
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10 OFFSET 20;

-- ============================================================
-- 2. Top-N 分组（MySQL 8.0+ 窗口函数）
-- ============================================================

-- ROW_NUMBER() 方式（MySQL 8.0+）
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
-- 3. MySQL 5.7 及以下（无窗口函数）的替代方案
-- ============================================================

-- 用户变量模拟 ROW_NUMBER（MySQL 5.7）
SELECT order_id, customer_id, amount, order_date
FROM (
    SELECT order_id, customer_id, amount, order_date,
           @rn := IF(@cid = customer_id, @rn + 1, 1) AS rn,
           @cid := customer_id
    FROM orders, (SELECT @rn := 0, @cid := NULL) vars
    ORDER BY customer_id, amount DESC
) ranked
WHERE rn <= 3;

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
-- 4. LATERAL 派生表（MySQL 8.0.14+）
-- ============================================================

-- MySQL 8.0.14+ 支持 LATERAL
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
-- 5. CTE 方式（MySQL 8.0+）
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
-- 6. 性能考量
-- ============================================================

-- 推荐索引
CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);

-- MySQL 8.0+ 的窗口函数是最推荐的方式
-- MySQL 5.7 用户变量方式不可靠（执行顺序不保证），升级到 8.0 为佳
-- LATERAL 在 8.0.14+ 可用，配合索引性能好
-- 注意：MySQL 不支持 FETCH FIRST WITH TIES
