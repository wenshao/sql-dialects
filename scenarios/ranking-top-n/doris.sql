-- Apache Doris: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] Apache Doris Documentation - Window Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/window-functions/
--   [2] Apache Doris Documentation - LIMIT
--       https://doris.apache.org/docs/sql-manual/sql-statements/data-query/SELECT/

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

-- Doris 是 MPP 列式分析数据库
-- Duplicate 模型适合 Top-N 查询
-- 使用分桶（DISTRIBUTED BY HASH）优化分组查询
-- Doris 自动优化 Top-N：ORDER BY + LIMIT 使用堆排序
-- 注意：Doris 不支持 LATERAL / CROSS APPLY / QUALIFY
