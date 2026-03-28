-- StarRocks: 分页
--
-- 参考资料:
--   [1] StarRocks Documentation - SELECT
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/

-- ============================================================
-- 1. LIMIT / OFFSET (与 Doris 相同)
-- ============================================================
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;
SELECT * FROM users ORDER BY id LIMIT 20, 10;
SELECT * FROM users ORDER BY id LIMIT 10;

-- ============================================================
-- 2. 键集分页
-- ============================================================
SELECT * FROM users ORDER BY id LIMIT 10;
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- ============================================================
-- 3. QUALIFY (3.2+，简化 Top-N)
-- ============================================================
-- 传统方式(子查询):
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;

-- QUALIFY 方式(StarRocks 3.2+):
-- SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
-- FROM users QUALIFY rn <= 3;

-- 对比 Doris: 不支持 QUALIFY(需要子查询)。
-- 对比 BigQuery/Snowflake: 都支持 QUALIFY。

-- ============================================================
-- 4. Pipeline 引擎的 Top-N 优化
-- ============================================================
-- StarRocks Pipeline 引擎对 ORDER BY + LIMIT 有深度优化:
--   Local Top-N → Exchange → Global Top-N
--   每个 BE 只传输 Top-N 行到协调节点(减少网络)。
