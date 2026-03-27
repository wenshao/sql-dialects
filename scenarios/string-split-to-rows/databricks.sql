-- Databricks: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Databricks SQL Reference - split
--       https://docs.databricks.com/sql/language-manual/functions/split.html
--   [2] Databricks SQL Reference - explode
--       https://docs.databricks.com/sql/language-manual/functions/explode.html

-- ============================================================
-- 示例数据
-- ============================================================
CREATE OR REPLACE TEMPORARY VIEW tags_csv AS
SELECT 1 AS id, 'Alice' AS name, 'python,java,sql' AS tags
UNION ALL SELECT 2, 'Bob',   'go,rust'
UNION ALL SELECT 3, 'Carol', 'sql,python,javascript,typescript';

-- ============================================================
-- 方法 1: explode + split（推荐）
-- ============================================================
SELECT id, name, explode(split(tags, ',')) AS tag
FROM   tags_csv;

-- ============================================================
-- 方法 2: LATERAL VIEW explode
-- ============================================================
SELECT t.id, t.name, tag
FROM   tags_csv t
LATERAL VIEW explode(split(t.tags, ',')) exploded AS tag;

-- ============================================================
-- 方法 3: posexplode（带位置序号）
-- ============================================================
SELECT t.id, t.name, pos, tag
FROM   tags_csv t
LATERAL VIEW posexplode(split(t.tags, ',')) exploded AS pos, tag;

-- ============================================================
-- 方法 4: LATERAL VIEW OUTER（保留 NULL 行）
-- ============================================================
SELECT t.id, t.name, tag
FROM   tags_csv t
LATERAL VIEW OUTER explode(split(t.tags, ',')) exploded AS tag;
