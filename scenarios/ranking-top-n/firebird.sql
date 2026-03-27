-- Firebird: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] Firebird Documentation - Window Functions
--       https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html
--   [2] Firebird Documentation - FIRST / SKIP / ROWS
--       https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id INTEGER, customer_id INTEGER, amount DECIMAL(10,2), order_date DATE)

-- ============================================================
-- 1. Top-N 整体
-- ============================================================

-- FIRST 语法（Firebird 经典方式）
SELECT FIRST 10 order_id, customer_id, amount
FROM orders
ORDER BY amount DESC;

-- FIRST + SKIP（分页）
SELECT FIRST 10 SKIP 20 order_id, customer_id, amount
FROM orders
ORDER BY amount DESC;

-- ROWS 语法（Firebird 2.0+）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
ROWS 1 TO 10;

-- FETCH FIRST（Firebird 3.0+，SQL 标准语法）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;

-- OFFSET + FETCH（Firebird 3.0+）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- ============================================================
-- 2. Top-N 分组（Firebird 3.0+ 窗口函数）
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
-- 3. 关联子查询方式（兼容 Firebird 2.x）
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

CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);

-- 窗口函数从 Firebird 3.0 开始支持
-- FIRST/SKIP 是 Firebird 独有语法
-- ROWS 从 Firebird 2.0 开始支持
-- FETCH FIRST 从 Firebird 3.0 开始支持
-- 注意：Firebird 不支持 LATERAL / CROSS APPLY / QUALIFY / CTE（3.0 前）
