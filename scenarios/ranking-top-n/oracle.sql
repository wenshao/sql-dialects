-- Oracle: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] Oracle Documentation - Analytic Functions
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Analytic-Functions.html
--   [2] Oracle Documentation - ROWNUM and Row Limiting
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SELECT.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id NUMBER, customer_id NUMBER, amount NUMBER(10,2), order_date DATE)

-- ============================================================
-- 1. Top-N 整体
-- ============================================================

-- FETCH FIRST（Oracle 12c+，推荐方式）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;

-- FETCH FIRST WITH TIES
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS WITH TIES;

-- OFFSET + FETCH（分页，Oracle 12c+）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- FETCH PERCENT
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 PERCENT ROWS ONLY;

-- ROWNUM 方式（Oracle 11g 及以下的经典方式）
SELECT *
FROM (
    SELECT order_id, customer_id, amount
    FROM orders
    ORDER BY amount DESC
)
WHERE ROWNUM <= 10;

-- ROWNUM 分页（Oracle 11g 及以下）
SELECT *
FROM (
    SELECT a.*, ROWNUM rnum
    FROM (
        SELECT order_id, customer_id, amount
        FROM orders
        ORDER BY amount DESC
    ) a
    WHERE ROWNUM <= 30
)
WHERE rnum > 20;

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
-- 3. LATERAL 内联视图（Oracle 12c+）
-- ============================================================

SELECT c.customer_id, t.order_id, t.amount
FROM (SELECT DISTINCT customer_id FROM orders) c,
LATERAL (
    SELECT order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
    FETCH FIRST 3 ROWS ONLY
) t;

-- CROSS APPLY（Oracle 12c+）
SELECT c.customer_id, t.order_id, t.amount
FROM customers c
CROSS APPLY (
    SELECT order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
    FETCH FIRST 3 ROWS ONLY
) t;

-- OUTER APPLY（包含无订单客户）
SELECT c.customer_id, c.username, t.order_id, t.amount
FROM customers c
OUTER APPLY (
    SELECT order_id, amount
    FROM orders o
    WHERE o.customer_id = c.customer_id
    ORDER BY amount DESC
    FETCH FIRST 3 ROWS ONLY
) t;

-- ============================================================
-- 4. 关联子查询方式（兼容所有版本）
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
-- 5. KEEP (DENSE_RANK) 聚合（Oracle 独有，取组内第一/最后值）
-- ============================================================

-- 每个客户金额最大的订单 ID
SELECT customer_id,
       MAX(order_id) KEEP (DENSE_RANK FIRST ORDER BY amount DESC) AS top_order_id,
       MAX(amount) AS max_amount
FROM orders
GROUP BY customer_id;

-- ============================================================
-- 6. 性能考量
-- ============================================================

-- 推荐索引
CREATE INDEX idx_orders_customer_amount ON orders (customer_id, amount DESC);

-- Oracle 12c+ FETCH FIRST 比 ROWNUM 方式可读性更好
-- CROSS APPLY + FETCH FIRST 在分组 Top-N 中性能最优
-- KEEP (DENSE_RANK) 只能取第一名，但效率极高（纯聚合）
-- ROWNUM 方式在 11g 及以下仍然是最优选择
-- 注意 ROWNUM 在 WHERE 前赋值，必须先 ORDER BY 再包一层子查询
