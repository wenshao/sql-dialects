-- ksqlDB: Top-N 查询（排名与分组取前 N 条）
--
-- 参考资料:
--   [1] ksqlDB Reference - SELECT
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/select-push-query/
--   [2] ksqlDB Reference - Aggregate Functions
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/aggregate-functions/

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设 STREAM / TABLE:
--   CREATE STREAM orders (order_id INT KEY, customer_id INT, amount DOUBLE, order_time BIGINT)
--   WITH (KAFKA_TOPIC='orders', VALUE_FORMAT='JSON');

-- ============================================================
-- 注意：ksqlDB 是流处理引擎，不支持传统的 Top-N 查询
-- ============================================================

-- ksqlDB 不支持窗口函数（ROW_NUMBER / RANK / DENSE_RANK）
-- ksqlDB 不支持 ORDER BY + LIMIT 的传统 Top-N 模式
-- 以下是可实现的近似方案：

-- ============================================================
-- 1. 使用 TOPK / TOPKDISTINCT 聚合函数
-- ============================================================

-- TOPK：返回每组前 K 个最大值（聚合函数）
SELECT customer_id,
       TOPK(amount, 3) AS top_3_amounts
FROM orders_stream
GROUP BY customer_id
EMIT CHANGES;

-- TOPKDISTINCT：返回每组前 K 个不重复最大值
SELECT customer_id,
       TOPKDISTINCT(amount, 3) AS top_3_distinct_amounts
FROM orders_stream
GROUP BY customer_id
EMIT CHANGES;

-- ============================================================
-- 2. 窗口聚合内的 TOPK
-- ============================================================

-- TUMBLING 窗口内的 Top-K
SELECT customer_id,
       TOPK(amount, 3) AS top_3_amounts,
       WINDOWSTART AS window_start,
       WINDOWEND AS window_end
FROM orders_stream
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP BY customer_id
EMIT CHANGES;

-- ============================================================
-- 3. Pull Query（拉取查询，物化表）
-- ============================================================

-- 先创建物化表
CREATE TABLE customer_top_amounts AS
SELECT customer_id,
       TOPK(amount, 3) AS top_3_amounts,
       COUNT(*) AS order_count
FROM orders_stream
GROUP BY customer_id
EMIT CHANGES;

-- 拉取查询获取特定客户的 Top-3
SELECT * FROM customer_top_amounts WHERE customer_id = 1001;

-- ============================================================
-- 4. 性能考量
-- ============================================================

-- ksqlDB 是流处理引擎，设计理念与批处理不同
-- TOPK/TOPKDISTINCT 是近似 Top-N 的最佳方案
-- 不支持 ROW_NUMBER / RANK / DENSE_RANK
-- 不支持 ORDER BY + LIMIT / QUALIFY / LATERAL / CROSS APPLY
-- 建议：需要复杂 Top-N 时，先将数据导入批处理引擎
