-- PostgreSQL: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] PostgreSQL Documentation - Window Functions
--       https://www.postgresql.org/docs/current/tutorial-window.html
--   [2] PostgreSQL Documentation - LIMIT and OFFSET
--       https://www.postgresql.org/docs/current/queries-limit.html
--   [3] PostgreSQL Documentation - Lateral Subqueries
--       https://www.postgresql.org/docs/current/queries-table-expressions.html#QUERIES-LATERAL

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id SERIAL, customer_id INT, amount NUMERIC(10,2), order_date DATE)
--   products(product_id SERIAL, category VARCHAR, price NUMERIC(10,2), product_name VARCHAR)

-- ============================================================
-- 1. Top-N 整体（最简单场景）
-- ============================================================

-- LIMIT 语法（PostgreSQL 经典方式）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

-- LIMIT + OFFSET（分页）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10 OFFSET 20;

-- FETCH FIRST（SQL 标准语法，PostgreSQL 8.4+）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;

-- WITH TIES（PostgreSQL 13+，包含并列行）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS WITH TIES;

-- ============================================================
-- 2. Top-N 分组（每组取前 N 条）
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

-- RANK() 方式（有并列时可能超过 N 条）
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
-- 3. DISTINCT ON（PostgreSQL 独有特性）
-- ============================================================

-- 每个客户金额最大的一笔订单
SELECT DISTINCT ON (customer_id)
       order_id, customer_id, amount, order_date
FROM orders
ORDER BY customer_id, amount DESC;

-- DISTINCT ON 取每个类别价格最高的产品
SELECT DISTINCT ON (category)
       product_id, category, price, product_name
FROM products
ORDER BY category, price DESC;

-- ============================================================
-- 4. LATERAL 子查询（PostgreSQL 9.3+）
-- ============================================================

-- 每个客户取前 3 笔订单（高效方式，可利用索引）
SELECT c.customer_id, t.order_id, t.amount, t.order_date
FROM (SELECT DISTINCT customer_id FROM orders) c
CROSS JOIN LATERAL (
    SELECT order_id, amount, order_date
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
    LIMIT 3
) t;

-- 配合实际 customers 表使用
SELECT c.customer_id, c.username, t.order_id, t.amount
FROM customers c
CROSS JOIN LATERAL (
    SELECT order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
    LIMIT 3
) t;

-- LEFT JOIN LATERAL（包含没有订单的客户）
SELECT c.customer_id, c.username, t.order_id, t.amount
FROM customers c
LEFT JOIN LATERAL (
    SELECT order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
    LIMIT 3
) t ON true;

-- ============================================================
-- 5. 关联子查询方式
-- ============================================================

SELECT o.*
FROM orders o
WHERE (
    SELECT COUNT(*)
    FROM orders o2
    WHERE o2.customer_id = o.customer_id
      AND (o2.amount > o.amount
           OR (o2.amount = o.amount AND o2.order_id < o.order_id))
) < 3
ORDER BY o.customer_id, o.amount DESC;

-- ============================================================
-- 6. CTE + 窗口函数
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
-- 7. 性能考量
-- ============================================================

-- 推荐索引
CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);

-- DISTINCT ON + 索引通常最快（取每组第 1 名）
-- LATERAL + LIMIT + 索引在分组 Top-N 中性能最优
-- ROW_NUMBER 方式需要全表窗口计算，大表可能较慢
-- 关联子查询 O(n^2)，仅适合小数据集

-- EXPLAIN ANALYZE 查看执行计划
EXPLAIN ANALYZE
SELECT DISTINCT ON (customer_id)
       order_id, customer_id, amount
FROM orders
ORDER BY customer_id, amount DESC;
