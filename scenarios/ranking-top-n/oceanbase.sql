-- OceanBase: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] OceanBase Documentation - Window Functions
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn
--   [2] OceanBase Documentation - SELECT
--       https://www.oceanbase.com/docs/common-oceanbase-database-cn

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构（MySQL 模式）:
--   orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_date DATE)

-- ============================================================
-- 1. Top-N 整体
-- ============================================================

-- MySQL 模式
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

-- Oracle 模式
-- SELECT order_id, customer_id, amount
-- FROM orders
-- ORDER BY amount DESC
-- FETCH FIRST 10 ROWS ONLY;

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

-- OceanBase 支持 MySQL 和 Oracle 两种兼容模式
-- 分布式架构自动并行窗口函数
-- 使用分区表和局部索引优化
-- 注意：不支持 LATERAL / CROSS APPLY / QUALIFY
