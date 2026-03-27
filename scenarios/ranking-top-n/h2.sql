-- H2 Database: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] H2 Documentation - Window Functions
--       https://h2database.com/html/functions-window.html
--   [2] H2 Documentation - SELECT
--       https://h2database.com/html/commands.html#select

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

SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10 OFFSET 20;

-- FETCH FIRST（SQL 标准语法）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;

-- TOP 语法
SELECT TOP 10 order_id, customer_id, amount
FROM orders
ORDER BY amount DESC;

-- ============================================================
-- 2. Top-N 分组（H2 1.4+ 窗口函数）
-- ============================================================

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
-- 3. QUALIFY（H2 2.0+ 支持）
-- ============================================================

-- H2 2.0+ 支持 QUALIFY
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

-- ============================================================
-- 4. 关联子查询方式
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
-- 5. 性能考量
-- ============================================================

CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);

-- H2 支持多种 Top-N 语法：LIMIT, TOP, FETCH FIRST
-- QUALIFY 从 H2 2.0 开始支持
-- H2 是内存数据库，小数据集性能极好
-- 注意：H2 不支持 LATERAL / CROSS APPLY
