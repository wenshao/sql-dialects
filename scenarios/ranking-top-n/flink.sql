-- Apache Flink SQL: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] Flink Documentation - Top-N
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/topn/
--   [2] Flink Documentation - Window Top-N
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/window-topn/

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   orders(order_id INT, customer_id INT, amount DECIMAL(10,2), order_time TIMESTAMP(3),
--          WATERMARK FOR order_time AS order_time - INTERVAL '5' SECOND)

-- ============================================================
-- 1. Top-N 整体（流式 Top-N）
-- ============================================================

-- Flink 使用特殊的 Top-N 模式（必须用 ROW_NUMBER + WHERE rn <= N）
SELECT order_id, customer_id, amount
FROM (
    SELECT order_id, customer_id, amount,
           ROW_NUMBER() OVER (ORDER BY amount DESC) AS rn
    FROM orders
)
WHERE rn <= 10;

-- ============================================================
-- 2. Top-N 分组（流式，Flink 特有模式识别）
-- ============================================================

-- Flink 识别此模式并优化为增量 Top-N（无需全量排序）
SELECT order_id, customer_id, amount, order_time
FROM (
    SELECT order_id, customer_id, amount, order_time,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rn
    FROM orders
)
WHERE rn <= 3;

-- ============================================================
-- 3. 窗口 Top-N（基于时间窗口，Flink 1.13+）
-- ============================================================

-- TUMBLE 窗口内的 Top-N
SELECT *
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id, window_start, window_end
               ORDER BY amount DESC
           ) AS rn
    FROM TABLE(
        TUMBLE(TABLE orders, DESCRIPTOR(order_time), INTERVAL '1' HOUR)
    )
)
WHERE rn <= 3;

-- HOP 窗口内的 Top-N
SELECT *
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY customer_id, window_start, window_end
               ORDER BY amount DESC
           ) AS rn
    FROM TABLE(
        HOP(TABLE orders, DESCRIPTOR(order_time), INTERVAL '5' MINUTE, INTERVAL '1' HOUR)
    )
)
WHERE rn <= 3;

-- ============================================================
-- 4. RANK / DENSE_RANK
-- ============================================================

-- Flink 也支持 RANK 和 DENSE_RANK 的 Top-N 模式
SELECT order_id, customer_id, amount
FROM (
    SELECT order_id, customer_id, amount,
           RANK() OVER (
               PARTITION BY customer_id
               ORDER BY amount DESC
           ) AS rnk
    FROM orders
)
WHERE rnk <= 3;

-- ============================================================
-- 5. 性能考量
-- ============================================================

-- Flink 的 Top-N 是增量计算，不需要全量数据
-- 必须使用 ROW_NUMBER/RANK/DENSE_RANK + WHERE rn <= N 模式
-- Flink 优化器自动识别 Top-N 模式并生成高效计划
-- 窗口 Top-N 基于 watermark 触发计算
-- 注意：Flink 不支持 LIMIT（用于流式 Top-N 时）
-- 注意：Flink 不支持 QUALIFY / LATERAL / CROSS APPLY
