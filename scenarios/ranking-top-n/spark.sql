-- Spark SQL: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] Spark SQL Documentation - Window Functions
--       https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-window.html
--   [2] Spark SQL Documentation - LIMIT
--       https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-limit.html

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
-- 3. LATERAL VIEW + 数组方式（Spark 特色）
-- ============================================================

SELECT customer_id, top_order.*
FROM (
    SELECT customer_id,
           slice(
               sort_array(collect_list(struct(amount, order_id, order_date)), false),
               1, 3
           ) AS top_orders
    FROM orders
    GROUP BY customer_id
)
LATERAL VIEW explode(top_orders) AS top_order;

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

-- Spark 自动并行分布式执行窗口函数
-- 使用分区表减少数据扫描
-- AQE（Adaptive Query Execution）自动优化 shuffle
-- 注意：Spark SQL 不支持 QUALIFY / CROSS APPLY / OFFSET
-- 注意：ORDER BY + LIMIT 全局排序只用一个分区
