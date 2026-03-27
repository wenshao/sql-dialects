-- Materialize: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Materialize Documentation - String Functions
--       https://materialize.com/docs/sql/functions/#string-functions
--   [2] Materialize Documentation - UNNEST
--       https://materialize.com/docs/sql/functions/#unnest

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   INT,
    name TEXT,
    tags TEXT
);

INSERT INTO tags_csv VALUES
    (1, 'Alice', 'python,java,sql'),
    (2, 'Bob',   'go,rust'),
    (3, 'Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 方法 1: UNNEST + STRING_TO_ARRAY（推荐，兼容 PostgreSQL）
-- ============================================================
SELECT id, name, UNNEST(STRING_TO_ARRAY(tags, ',')) AS tag
FROM   tags_csv;

-- ============================================================
-- 方法 2: regexp_split_to_table
-- ============================================================
SELECT id, name, regexp_split_to_table(tags, ',') AS tag
FROM   tags_csv;
