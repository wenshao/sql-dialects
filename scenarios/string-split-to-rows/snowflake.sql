-- Snowflake: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Snowflake SQL Reference - SPLIT_TO_TABLE
--       https://docs.snowflake.com/en/sql-reference/functions/split_to_table
--   [2] Snowflake SQL Reference - STRTOK_SPLIT_TO_TABLE
--       https://docs.snowflake.com/en/sql-reference/functions/strtok_split_to_table
--   [3] Snowflake SQL Reference - FLATTEN
--       https://docs.snowflake.com/en/sql-reference/functions/flatten

-- ============================================================
-- 示例数据
-- ============================================================
CREATE OR REPLACE TEMPORARY TABLE tags_csv (
    id   NUMBER AUTOINCREMENT,
    name VARCHAR(100),
    tags VARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 方法 1: SPLIT_TO_TABLE（推荐）
-- ============================================================
SELECT t.id, t.name, s.VALUE AS tag, s.INDEX AS pos
FROM   tags_csv t,
       LATERAL SPLIT_TO_TABLE(t.tags, ',') s;

-- ============================================================
-- 方法 2: STRTOK_SPLIT_TO_TABLE
-- ============================================================
SELECT t.id, t.name, s.VALUE AS tag, s.INDEX AS pos
FROM   tags_csv t,
       LATERAL STRTOK_SPLIT_TO_TABLE(t.tags, ',') s;

-- ============================================================
-- 方法 3: FLATTEN + SPLIT
-- ============================================================
SELECT t.id, t.name, f.VALUE::VARCHAR AS tag, f.INDEX AS pos
FROM   tags_csv t,
       LATERAL FLATTEN(INPUT => SPLIT(t.tags, ',')) f;

-- ============================================================
-- 方法 4: 递归 CTE
-- ============================================================
WITH RECURSIVE split_cte AS (
    SELECT id, name,
           SPLIT_PART(tags, ',', 1)       AS tag,
           SUBSTR(tags, LEN(SPLIT_PART(tags, ',', 1)) + 2) AS remaining,
           1 AS pos
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           SPLIT_PART(remaining, ',', 1),
           SUBSTR(remaining, LEN(SPLIT_PART(remaining, ',', 1)) + 2),
           pos + 1
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
