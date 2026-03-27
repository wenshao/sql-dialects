-- BigQuery: 分页
--
-- 参考资料:
--   [1] BigQuery SQL Reference - LIMIT and OFFSET
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#limit_and_offset_clause
--   [2] BigQuery SQL Reference - Query Syntax
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax

-- LIMIT / OFFSET
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 仅 LIMIT
SELECT * FROM users ORDER BY id LIMIT 10;

-- 窗口函数分页
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;

-- 游标分页（Keyset Pagination，推荐大数据量使用）
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;

-- TABLESAMPLE（采样，非精确分页但适合大表预览）
SELECT * FROM users TABLESAMPLE SYSTEM (1 PERCENT);

-- 注意：BigQuery 不支持 FETCH FIRST ... ROWS ONLY 标准语法
-- 注意：BigQuery 大 OFFSET 性能较差，建议使用游标分页
-- 注意：BigQuery 按扫描量计费，LIMIT 不会减少扫描量（除非配合分区表）
