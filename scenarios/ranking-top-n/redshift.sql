-- Amazon Redshift: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] Redshift Documentation - Window Functions
--       https://docs.aws.amazon.com/redshift/latest/dg/c_Window_functions.html
--   [2] Redshift Documentation - LIMIT
--       https://docs.aws.amazon.com/redshift/latest/dg/r_LIMIT.html
--   [3] Redshift Documentation - QUALIFY
--       https://docs.aws.amazon.com/redshift/latest/dg/r_QUALIFY_clause.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_date DATE)
--   DISTKEY(customer_id) SORTKEY(order_date)

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
-- 2. Top-N 分组 + QUALIFY（Redshift 支持）
-- ============================================================

-- QUALIFY（Redshift 支持）
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

-- QUALIFY + RANK
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY RANK() OVER (
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
-- 5. CTE 方式
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

-- DISTKEY(customer_id) 使分组 Top-N 不需要跨节点 shuffle
-- SORTKEY(amount) 可加速 ORDER BY amount DESC
-- QUALIFY 是推荐方式
-- Redshift 是 MPP 架构，窗口函数自动并行
-- 注意：Redshift 不支持 LATERAL / CROSS APPLY
