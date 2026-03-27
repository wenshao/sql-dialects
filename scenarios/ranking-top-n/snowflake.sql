-- Snowflake: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] Snowflake Documentation - Window Functions
--       https://docs.snowflake.com/en/sql-reference/functions-analytic
--   [2] Snowflake Documentation - QUALIFY
--       https://docs.snowflake.com/en/sql-reference/constructs/qualify
--   [3] Snowflake Documentation - LIMIT / FETCH
--       https://docs.snowflake.com/en/sql-reference/constructs/limit

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id NUMBER, customer_id NUMBER, amount NUMBER(10,2), order_date DATE)

-- ============================================================
-- 1. Top-N 整体
-- ============================================================

-- LIMIT 语法
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

-- LIMIT + OFFSET
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10 OFFSET 20;

-- FETCH FIRST（SQL 标准语法）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS ONLY;

-- ============================================================
-- 2. Top-N 分组 + QUALIFY（Snowflake 特色）
-- ============================================================

-- QUALIFY 直接过滤窗口函数结果，无需子查询！
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

-- QUALIFY + RANK（包含并列）
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY RANK() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

-- QUALIFY + DENSE_RANK
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY DENSE_RANK() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

-- QUALIFY 与 WHERE 组合
SELECT order_id, customer_id, amount, order_date
FROM orders
WHERE order_date >= '2024-01-01'
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

-- ============================================================
-- 3. 传统子查询方式（也可以用）
-- ============================================================

-- ROW_NUMBER() 子查询
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

-- ============================================================
-- 4. CTE + QUALIFY
-- ============================================================

WITH filtered_orders AS (
    SELECT order_id, customer_id, amount, order_date
    FROM orders
    WHERE order_date >= '2024-01-01'
)
SELECT *
FROM filtered_orders
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY amount DESC
) <= 3;

-- ============================================================
-- 5. 关联子查询方式
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
-- 6. 性能考量
-- ============================================================

-- QUALIFY 是 Snowflake 推荐的方式，语法简洁且优化器支持好
-- Snowflake 无需手动创建索引（自动微分区和修剪）
-- 聚集键可优化大表扫描
ALTER TABLE orders CLUSTER BY (customer_id);
-- QUALIFY 在语义上等价于子查询 + WHERE，但可读性更好
-- Snowflake 的窗口函数在大规模数据上自动并行
