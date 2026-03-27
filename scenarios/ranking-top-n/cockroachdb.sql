-- CockroachDB: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] CockroachDB Documentation - Window Functions
--       https://www.cockroachlabs.com/docs/stable/window-functions.html
--   [2] CockroachDB Documentation - LIMIT / OFFSET
--       https://www.cockroachlabs.com/docs/stable/limit-offset.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构（兼容 PostgreSQL 语法）:
--   orders(order_id SERIAL, customer_id INT, amount DECIMAL(10,2), order_date DATE)

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

SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;

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

-- CockroachDB 语法兼容 PostgreSQL
-- 分布式架构自动并行窗口函数
-- 使用 STORING 子句优化索引覆盖查询
-- 注意：CockroachDB 不支持 LATERAL / CROSS APPLY / QUALIFY / DISTINCT ON
