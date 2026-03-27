-- Trino: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Trino Documentation - String Functions
--       https://trino.io/docs/current/functions/string.html
--   [2] Trino Documentation - UNNEST
--       https://trino.io/docs/current/sql/select.html#unnest

-- ============================================================
-- 示例数据
-- ============================================================
-- Trino 使用 VALUES 子句或从已有数据源查询
-- CREATE TABLE tags_csv AS
-- SELECT * FROM (VALUES (1,'Alice','python,java,sql'),
--                       (2,'Bob','go,rust'),
--                       (3,'Carol','sql,python,javascript,typescript'))
--          AS t(id, name, tags);

-- ============================================================
-- 方法 1: CROSS JOIN UNNEST + split（推荐）
-- ============================================================
SELECT t.id, t.name, tag
FROM   tags_csv t
CROSS JOIN UNNEST(split(t.tags, ',')) AS x(tag);

-- ============================================================
-- 方法 2: UNNEST 带序号
-- ============================================================
SELECT t.id, t.name, tag, pos
FROM   tags_csv t
CROSS JOIN UNNEST(split(t.tags, ','))
           WITH ORDINALITY AS x(tag, pos);

-- ============================================================
-- 方法 3: regexp_extract_all + UNNEST
-- ============================================================
SELECT t.id, t.name, tag
FROM   tags_csv t
CROSS JOIN UNNEST(regexp_extract_all(t.tags, '[^,]+')) AS x(tag);
