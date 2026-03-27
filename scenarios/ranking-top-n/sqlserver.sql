-- SQL Server: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] Microsoft Docs - TOP (Transact-SQL)
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/top-transact-sql
--   [2] Microsoft Docs - Ranking Functions
--       https://learn.microsoft.com/en-us/sql/t-sql/functions/ranking-functions-transact-sql
--   [3] Microsoft Docs - CROSS APPLY / OUTER APPLY
--       https://learn.microsoft.com/en-us/sql/t-sql/queries/from-transact-sql

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id INT IDENTITY, customer_id INT, amount DECIMAL(10,2), order_date DATE)

-- ============================================================
-- 1. Top-N 整体
-- ============================================================

-- TOP 语法（SQL Server 经典方式）
SELECT TOP 10 order_id, customer_id, amount
FROM orders
ORDER BY amount DESC;

-- TOP WITH TIES（包含并列行）
SELECT TOP 10 WITH TIES order_id, customer_id, amount
FROM orders
ORDER BY amount DESC;

-- TOP + PERCENT
SELECT TOP 10 PERCENT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC;

-- OFFSET-FETCH（SQL Server 2012+，标准语法）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;

-- 分页
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

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
-- 3. CROSS APPLY（SQL Server 特色，高效分组 Top-N）
-- ============================================================

-- 每个客户的前 3 笔最大订单
SELECT c.customer_id, t.order_id, t.amount, t.order_date
FROM (SELECT DISTINCT customer_id FROM orders) c
CROSS APPLY (
    SELECT TOP 3 order_id, amount, order_date
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
) t;

-- OUTER APPLY（包含没有订单的客户）
SELECT c.customer_id, c.username, t.order_id, t.amount
FROM customers c
OUTER APPLY (
    SELECT TOP 3 order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
) t;

-- ============================================================
-- 4. 关联子查询方式（兼容旧版本）
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
-- 5. CTE + 窗口函数
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

-- CROSS APPLY + TOP + 索引：最优方案，每组只扫描 N 行
-- ROW_NUMBER 方式需要全表计算，大表较慢
-- TOP WITH TIES 对整体排名很方便
-- OFFSET-FETCH 从 SQL Server 2012 开始支持
-- SQL Server 2005+ 支持所有窗口排名函数
