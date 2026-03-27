-- Hive: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] Apache Hive - Window Functions
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+WindowingAndAnalytics
--   [2] Apache Hive - LIMIT
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_date STRING)

-- ============================================================
-- 1. Top-N 整体
-- ============================================================

SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10;

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
-- 4. CTE 方式（Hive 0.13+）
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

-- Hive 窗口函数从 0.11 开始支持
-- 使用分区表和桶化减少数据扫描
-- ORC/Parquet 格式自动列式优化
-- SORT BY 替代 ORDER BY 可在 reducer 内局部排序（更快）
-- 注意：Hive 不支持 LATERAL / CROSS APPLY / QUALIFY / OFFSET
-- 注意：Hive 的 ORDER BY 全局排序只用一个 reducer
