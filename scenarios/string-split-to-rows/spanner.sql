-- Spanner: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Cloud Spanner SQL Reference - SPLIT
--       https://cloud.google.com/spanner/docs/reference/standard-sql/string_functions#split
--   [2] Cloud Spanner SQL Reference - UNNEST
--       https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax#unnest

-- ============================================================
-- 示例数据（DDL 和 DML 需分开执行）
-- ============================================================
CREATE TABLE tags_csv (
    id   INT64 NOT NULL,
    name STRING(100),
    tags STRING(500)
) PRIMARY KEY (id);

-- ============================================================
-- 方法 1: SPLIT + UNNEST（推荐，与 BigQuery 类似）
-- ============================================================
SELECT id, name, tag
FROM   tags_csv,
       UNNEST(SPLIT(tags, ',')) AS tag;

-- ============================================================
-- 方法 2: SPLIT + UNNEST 带序号
-- ============================================================
SELECT id, name, tag, pos
FROM   tags_csv,
       UNNEST(SPLIT(tags, ',')) AS tag WITH OFFSET AS pos
ORDER BY id, pos;
