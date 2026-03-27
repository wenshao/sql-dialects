-- Impala: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] Impala Documentation - Analytic Functions
--       https://impala.apache.org/docs/build/html/topics/impala_analytic_functions.html
--   [2] Impala Documentation - LIMIT
--       https://impala.apache.org/docs/build/html/topics/impala_limit.html

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

SELECT order_id, customer_id, amount
FROM orders
ORDER BY amount DESC
LIMIT 10 OFFSET 20;

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
-- 4. 性能考量
-- ============================================================

-- Impala 的 MPP 架构自动并行窗口函数
-- 使用 Parquet 格式存储优化列式查询
-- COMPUTE STATS orders; 确保优化器统计信息更新
-- Top-N 优化：Impala 自动对 ORDER BY + LIMIT 执行 top-N 排序
-- 注意：Impala 不支持 LATERAL / CROSS APPLY / QUALIFY / CTE（Impala 2.x 不支持）
