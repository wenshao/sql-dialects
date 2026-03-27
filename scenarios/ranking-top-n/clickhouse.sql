-- ClickHouse: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] ClickHouse Documentation - Window Functions
--       https://clickhouse.com/docs/en/sql-reference/window-functions
--   [2] ClickHouse Documentation - LIMIT
--       https://clickhouse.com/docs/en/sql-reference/statements/select/limit

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id UInt64, customer_id UInt64, amount Decimal(10,2), order_date Date)
--   ENGINE = MergeTree() ORDER BY (customer_id, order_date)

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

-- LIMIT BY（ClickHouse 独有：每组取 N 条）
SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 3 BY customer_id;

-- ============================================================
-- 2. LIMIT BY（ClickHouse 独有的分组 Top-N）
-- ============================================================

-- 每个客户取金额最大的 3 笔订单（最简洁方式）
SELECT order_id, customer_id, amount, order_date
FROM orders
ORDER BY customer_id, amount DESC
LIMIT 3 BY customer_id;

-- LIMIT BY 组合整体 LIMIT
SELECT order_id, customer_id, amount, order_date
FROM orders
ORDER BY customer_id, amount DESC
LIMIT 3 BY customer_id
LIMIT 100;

-- ============================================================
-- 3. 窗口函数方式（ClickHouse 21.1+）
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
-- 4. 数组函数方式（ClickHouse 特色）
-- ============================================================

-- arraySlice + groupArray 取每组前 N
SELECT customer_id,
       arraySlice(groupArray(order_id), 1, 3) AS top_order_ids,
       arraySlice(groupArray(amount), 1, 3) AS top_amounts
FROM (
    SELECT order_id, customer_id, amount
    FROM orders
    ORDER BY customer_id, amount DESC
)
GROUP BY customer_id;

-- ============================================================
-- 5. 关联子查询方式
-- ============================================================

SELECT o.*
FROM orders o
WHERE (
    SELECT count()
    FROM orders o2
    WHERE o2.customer_id = o.customer_id
      AND o2.amount > o.amount
) < 3
ORDER BY o.customer_id, o.amount DESC;

-- ============================================================
-- 6. 性能考量
-- ============================================================

-- LIMIT BY 是 ClickHouse 最高效的分组 Top-N 方式
-- LIMIT BY 不需要窗口函数，直接在排序后截断
-- 窗口函数从 21.1 版本开始支持，之前版本请用 LIMIT BY
-- ClickHouse 是列式存储，ORDER BY + LIMIT 自动优化
-- ORDER BY 键与表引擎的 ORDER BY 一致时性能最佳
-- 注意：ClickHouse 不支持 LATERAL / CROSS APPLY / QUALIFY
