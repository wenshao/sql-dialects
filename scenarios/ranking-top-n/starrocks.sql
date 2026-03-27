-- StarRocks: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] StarRocks Documentation - Window Functions
--       https://docs.starrocks.io/docs/sql-reference/sql-functions/Window_function/
--   [2] StarRocks Documentation - SELECT
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/data-query/SELECT/

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_date DATE)

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
-- 2. Top-N 分组 + QUALIFY（StarRocks 3.0+ 支持）
-- ============================================================

-- QUALIFY（StarRocks 3.0+）
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

-- 传统子查询方式
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
-- 4. 性能考量
-- ============================================================

-- StarRocks 是 MPP 列式分析数据库，窗口函数自动并行
-- QUALIFY 从 StarRocks 3.0 开始支持
-- 使用 Colocation Group 优化分组查询（同组数据同节点）
-- StarRocks 自动优化 Top-N：Runtime Filter 加速
-- 注意：StarRocks 不支持 LATERAL / CROSS APPLY
