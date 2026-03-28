-- Apache Doris: 临时表
--
-- 参考资料:
--   [1] Doris Documentation - CREATE TABLE
--       https://doris.apache.org/docs/sql-manual/sql-statements/

-- ============================================================
-- 1. 不支持临时表: 使用 CTE 和 Staging 表替代
-- ============================================================
-- Doris 不支持 CREATE TEMPORARY TABLE。
--
-- 设计理由:
--   临时表的核心价值: 存储中间结果，会话结束自动销毁。
--   OLAP 引擎的中间结果处理:
--     小数据量 → CTE(内存中，零成本)
--     大数据量 → Staging 表(持久化，需手动删除)
--
-- 对比:
--   StarRocks: 同样不支持(同源)
--   ClickHouse: 不支持临时表
--   MySQL:     CREATE TEMPORARY TABLE(会话级，自动销毁)
--   PostgreSQL: CREATE TEMP TABLE(事务/会话级)
--   BigQuery:  临时表(24 小时自动过期)

-- ============================================================
-- 2. CTE (推荐，适合中小数据量)
-- ============================================================
WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total
FROM users u JOIN stats s ON u.id = s.user_id;

-- ============================================================
-- 3. Staging 表 (适合大数据量)
-- ============================================================
CREATE TABLE staging_results (
    user_id BIGINT,
    total   DECIMAL(10,2)
) DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES ("replication_num" = "1");   -- 单副本降低开销

INSERT INTO staging_results
SELECT user_id, SUM(amount) FROM orders GROUP BY user_id;

-- 使用后删除
DROP TABLE staging_results;

-- ============================================================
-- 4. INSERT INTO SELECT (物化中间结果)
-- ============================================================
INSERT INTO result_table
SELECT u.username, SUM(o.amount) AS total
FROM users u JOIN orders o ON u.id = o.user_id
GROUP BY u.username;

-- 对引擎开发者的启示:
--   临时表需要 FE 元数据管理(创建/删除/会话绑定)。
--   在分布式引擎中，"会话绑定"的实现复杂度高
--   (会话可能跨多个 FE 节点)。CTE 是零成本替代。
