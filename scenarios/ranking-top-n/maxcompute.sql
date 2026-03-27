-- MaxCompute (ODPS): Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] MaxCompute Documentation - Window Functions
--       https://help.aliyun.com/document_detail/34994.html
--   [2] MaxCompute Documentation - SELECT
--       https://help.aliyun.com/document_detail/73777.html

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id BIGINT, customer_id BIGINT, amount DECIMAL(10,2), order_date STRING)

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

-- MaxCompute 是阿里云大数据平台
-- 自动分布式执行窗口函数
-- 使用分区表减少扫描：PARTITION BY ds
-- ORDER BY + LIMIT 全局排序只用一个 instance
-- 注意：MaxCompute 不支持 LATERAL / CROSS APPLY / QUALIFY / OFFSET
