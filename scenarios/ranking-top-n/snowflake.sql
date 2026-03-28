-- Snowflake: Top-N 查询
--
-- 参考资料:
--   [1] Snowflake Documentation - QUALIFY
--       https://docs.snowflake.com/en/sql-reference/constructs/qualify

-- ============================================================
-- 1. 全局 Top-N
-- ============================================================

SELECT order_id, customer_id, amount
FROM orders ORDER BY amount DESC LIMIT 10;

SELECT order_id, customer_id, amount
FROM orders ORDER BY amount DESC FETCH FIRST 10 ROWS ONLY;

SELECT TOP 10 order_id, customer_id, amount
FROM orders ORDER BY amount DESC;

-- ============================================================
-- 2. QUALIFY 分组 Top-N（Snowflake 核心优势）
-- ============================================================

-- 每个客户的前 3 大订单（最简洁写法）:
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) <= 3;

-- QUALIFY + RANK（包含并列）:
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC) <= 3;

-- QUALIFY + DENSE_RANK:
SELECT order_id, customer_id, amount, order_date
FROM orders
QUALIFY DENSE_RANK() OVER (PARTITION BY customer_id ORDER BY amount DESC) <= 3;

-- QUALIFY + WHERE 组合:
SELECT order_id, customer_id, amount, order_date
FROM orders
WHERE order_date >= '2024-01-01'
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) <= 3;

-- 对引擎开发者的启示:
--   分组 Top-N 是最常见的分析查询之一。
--   没有 QUALIFY 需要嵌套子查询（增加 SQL 复杂度和维护成本）。
--   QUALIFY 消除了这个嵌套，是 ROI 最高的语法扩展之一。
--   对比: PostgreSQL 和 MySQL 至今不支持 QUALIFY，
--   分组 Top-N 必须用子查询 + WHERE rn <= N。

-- ============================================================
-- 3. 传统子查询方式
-- ============================================================

SELECT * FROM (
    SELECT order_id, customer_id, amount, order_date,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rn
    FROM orders
) WHERE rn <= 3;

-- ============================================================
-- 4. CTE + QUALIFY
-- ============================================================

WITH filtered_orders AS (
    SELECT order_id, customer_id, amount, order_date
    FROM orders WHERE order_date >= '2024-01-01'
)
SELECT * FROM filtered_orders
QUALIFY ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) <= 3;

-- ============================================================
-- 5. 关联子查询方式（无需窗口函数）
-- ============================================================

SELECT o.* FROM orders o
WHERE (SELECT COUNT(*) FROM orders o2
       WHERE o2.customer_id = o.customer_id AND o2.amount > o.amount) < 3
ORDER BY o.customer_id, o.amount DESC;

-- ============================================================
-- 6. 性能优化
-- ============================================================

-- 聚簇键加速分组 Top-N:
ALTER TABLE orders CLUSTER BY (customer_id);
-- 聚簇后，同一客户的订单集中在少数微分区 → PARTITION BY 效率更高

-- ============================================================
-- 横向对比: Top-N 方案
-- ============================================================
-- 方案         | Snowflake        | BigQuery        | PostgreSQL    | MySQL
-- 全局TopN     | LIMIT/TOP/FETCH  | LIMIT           | LIMIT         | LIMIT
-- 分组TopN     | QUALIFY(最简)    | QUALIFY          | 子查询        | 子查询
-- QUALIFY      | 原生支持         | 原生支持        | 不支持        | 不支持
-- LATERAL TopN | LATERAL+LIMIT    | 不支持          | LATERAL+LIMIT | 8.0.14+
