-- 达梦数据库 (DM): Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] 达梦数据库 SQL 参考手册
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/dmpl-sql-query.html
--   [2] 达梦数据库分析函数参考
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构（兼容 Oracle 语法）:
--   orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_date DATE)

-- ============================================================
-- 1. Top-N 整体
-- ============================================================

-- TOP 语法
SELECT TOP 10 order_id, customer_id, amount
FROM orders
ORDER BY amount DESC;

-- ROWNUM 方式（兼容 Oracle）
SELECT *
FROM (
    SELECT order_id, customer_id, amount
    FROM orders
    ORDER BY amount DESC
)
WHERE ROWNUM <= 10;

-- LIMIT 语法（DM8 支持）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

-- ============================================================
-- 2. Top-N 分组
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

CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);

-- 达梦数据库是国产数据库，兼容 Oracle 语法
-- 支持 TOP、ROWNUM、LIMIT 多种 Top-N 语法
-- 支持窗口函数、CTE
-- 注意：不支持 QUALIFY / LATERAL / CROSS APPLY
