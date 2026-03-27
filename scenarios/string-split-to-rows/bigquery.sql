-- BigQuery: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] BigQuery SQL Reference - SPLIT
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#split
--   [2] BigQuery SQL Reference - UNNEST
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unnest

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TEMP TABLE tags_csv AS
SELECT 1 AS id, 'Alice' AS name, 'python,java,sql' AS tags
UNION ALL SELECT 2, 'Bob',   'go,rust'
UNION ALL SELECT 3, 'Carol', 'sql,python,javascript,typescript';

-- ============================================================
-- 方法 1: SPLIT + UNNEST（推荐）
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

-- ============================================================
-- 方法 3: REGEXP_EXTRACT_ALL + UNNEST
-- ============================================================
SELECT id, name, tag
FROM   tags_csv,
       UNNEST(REGEXP_EXTRACT_ALL(tags, r'[^,]+')) AS tag;
