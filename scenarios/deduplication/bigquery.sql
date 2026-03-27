-- BigQuery: 数据去重策略（Deduplication）
--
-- 参考资料:
--   [1] BigQuery Documentation - QUALIFY
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#qualify_clause
--   [2] BigQuery Documentation - MERGE
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/dml-syntax#merge_statement
--   [3] BigQuery Documentation - APPROX_COUNT_DISTINCT
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/functions-and-operators#approx_count_distinct

-- ============================================================
-- 示例数据上下文
-- ============================================================
-- 假设表结构:
--   project.dataset.users(user_id INT64, email STRING, username STRING, created_at TIMESTAMP)

-- ============================================================
-- 1. 查找重复数据
-- ============================================================

SELECT email, COUNT(*) AS cnt
FROM `project.dataset.users`
GROUP BY email
HAVING COUNT(*) > 1;

-- ============================================================
-- 2. 保留每组一行 + QUALIFY
-- ============================================================

-- QUALIFY（BigQuery 推荐方式）
SELECT user_id, email, username, created_at
FROM `project.dataset.users`
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;

-- 传统子查询方式
SELECT *
FROM (
    SELECT user_id, email, username, created_at,
           ROW_NUMBER() OVER (
               PARTITION BY email
               ORDER BY created_at DESC
           ) AS rn
    FROM `project.dataset.users`
) ranked
WHERE rn = 1;

-- ============================================================
-- 3. 删除重复数据
-- ============================================================

-- MERGE 自连接删除重复
MERGE INTO `project.dataset.users` target
USING (
    SELECT user_id
    FROM (
        SELECT user_id,
               ROW_NUMBER() OVER (
                   PARTITION BY email
                   ORDER BY created_at DESC
               ) AS rn
        FROM `project.dataset.users`
    )
    WHERE rn > 1
) dups
ON target.user_id = dups.user_id
WHEN MATCHED THEN DELETE;

-- CTAS 方式（创建去重后的新表）
CREATE OR REPLACE TABLE `project.dataset.users` AS
SELECT user_id, email, username, created_at
FROM `project.dataset.users`
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY email
    ORDER BY created_at DESC
) = 1;

-- ============================================================
-- 4. ARRAY_AGG 去重
-- ============================================================

SELECT email,
       ARRAY_AGG(STRUCT(user_id, username, created_at) ORDER BY created_at DESC LIMIT 1)[OFFSET(0)].*
FROM `project.dataset.users`
GROUP BY email;

-- ============================================================
-- 5. DISTINCT vs GROUP BY
-- ============================================================

SELECT DISTINCT email FROM `project.dataset.users`;
SELECT email FROM `project.dataset.users` GROUP BY email;

-- ============================================================
-- 6. 近似去重（APPROX_COUNT_DISTINCT）
-- ============================================================

SELECT APPROX_COUNT_DISTINCT(email) AS approx_distinct_emails
FROM `project.dataset.users`;

-- HLL_COUNT（更灵活的 HyperLogLog）
SELECT HLL_COUNT.EXTRACT(HLL_COUNT.INIT(email)) AS hll_distinct
FROM `project.dataset.users`;

-- 跨表/跨分区合并 HLL
SELECT HLL_COUNT.EXTRACT(HLL_COUNT.MERGE(hll_sketch)) AS combined_distinct
FROM (
    SELECT HLL_COUNT.INIT(email) AS hll_sketch
    FROM `project.dataset.users`
    GROUP BY DATE(created_at)
);

-- ============================================================
-- 7. 性能考量
-- ============================================================

-- QUALIFY 是 BigQuery 推荐的去重方式
-- CTAS 重建表比 MERGE DELETE 更高效
-- APPROX_COUNT_DISTINCT 使用 HyperLogLog，误差 < 1%
-- HLL_COUNT 支持 sketch 的持久化和合并
-- BigQuery 按扫描数据量计费
-- 注意：BigQuery 不支持 ctid / ROWID 等物理行 ID
