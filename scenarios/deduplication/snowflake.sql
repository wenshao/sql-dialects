-- Snowflake: 数据去重策略（Deduplication）
--
-- 参考资料:
--   [1] Snowflake Documentation - QUALIFY
--       https://docs.snowflake.com/en/sql-reference/constructs/qualify
--   [2] Snowflake Documentation - MERGE
--       https://docs.snowflake.com/en/sql-reference/sql/merge
--   [3] Snowflake Documentation - APPROX_COUNT_DISTINCT
--       https://docs.snowflake.com/en/sql-reference/functions/approx_count_distinct

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   users(user_id NUMBER, email VARCHAR, username VARCHAR, created_at TIMESTAMP_NTZ)

-- ============================================================
-- 1. 查找重复数据
-- ============================================================

SELECT email, COUNT(*) AS cnt
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

-- ============================================================
-- 2. 保留每组一行 + QUALIFY（Snowflake 推荐方式）
-- ============================================================

-- QUALIFY 直接过滤（最简洁）
SELECT user_id, email, username, created_at
FROM users
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;

-- QUALIFY + RANK（保留并列最新的所有记录）
SELECT user_id, email, username, created_at
FROM users
QUALIFY RANK() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;

-- 传统子查询方式（也可以用）
SELECT *
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM users
) ranked
WHERE rn = 1;

-- ============================================================
-- 3. 删除重复数据
-- ============================================================

-- Snowflake 的 DELETE + 子查询
DELETE FROM users
WHERE user_id NOT IN (
    SELECT user_id FROM (
        SELECT user_id,
               ROW_NUMBER() OVER (
                   PARTITION BY email
                   ORDER BY created_at DESC
               ) AS rn
        FROM users
    ) WHERE rn = 1
);

-- 使用 SWAP 策略（推荐：CTAS + SWAP）
CREATE TABLE users_deduped AS
SELECT user_id, email, username, created_at
FROM users
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;

ALTER TABLE users SWAP WITH users_deduped;

-- ============================================================
-- 4. 防止重复（MERGE）
-- ============================================================

MERGE INTO users target
USING (SELECT 'a@b.com' AS email, 'alice' AS username, CURRENT_TIMESTAMP() AS created_at) source
ON target.email = source.email
WHEN MATCHED THEN
    UPDATE SET target.username = source.username, target.created_at = source.created_at
WHEN NOT MATCHED THEN
    INSERT (email, username, created_at) VALUES (source.email, source.username, source.created_at);

-- ============================================================
-- 5. DISTINCT vs GROUP BY
-- ============================================================

SELECT DISTINCT email FROM users;
SELECT email FROM users GROUP BY email;

-- ============================================================
-- 6. 近似去重（APPROX_COUNT_DISTINCT）
-- ============================================================

-- HyperLogLog 近似不重复计数
SELECT APPROX_COUNT_DISTINCT(email) AS approx_distinct_emails
FROM users;

-- HLL_ACCUMULATE / HLL_ESTIMATE（更灵活）
SELECT HLL_ESTIMATE(HLL_ACCUMULATE(email)) AS approx_distinct
FROM users;

-- HLL 合并（跨分段合并）
SELECT HLL_ESTIMATE(HLL_COMBINE(hll_val)) AS combined_approx
FROM (
    SELECT HLL_ACCUMULATE(email) AS hll_val
    FROM users
    GROUP BY DATE_TRUNC('month', created_at)
);

-- ============================================================
-- 7. 性能考量
-- ============================================================

-- QUALIFY 是 Snowflake 推荐的去重方式
-- CTAS + SWAP 比 DELETE 更高效（避免大量 DML）
-- Snowflake 的 APPROX_COUNT_DISTINCT 使用 HyperLogLog
-- 无需手动创建索引
-- 注意：Snowflake 的 PK/UNIQUE 约束不强制执行
