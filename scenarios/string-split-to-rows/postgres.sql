-- PostgreSQL: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] PostgreSQL Documentation - String Functions
--       https://www.postgresql.org/docs/current/functions-string.html
--   [2] PostgreSQL Documentation - regexp_split_to_table
--       https://www.postgresql.org/docs/current/functions-string.html#FUNCTIONS-STRING-OTHER
--   [3] PostgreSQL Documentation - STRING_TO_ARRAY / UNNEST
--       https://www.postgresql.org/docs/current/functions-array.html

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(100),
    tags VARCHAR(500)          -- 逗号分隔的标签
);

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 方法 1: STRING_TO_ARRAY + UNNEST（推荐）
-- 适用版本: PostgreSQL 8.1+
-- ============================================================
SELECT id, name, UNNEST(STRING_TO_ARRAY(tags, ',')) AS tag
FROM   tags_csv;

-- ============================================================
-- 方法 2: regexp_split_to_table
-- 适用版本: PostgreSQL 8.3+
-- ============================================================
SELECT id, name, regexp_split_to_table(tags, ',') AS tag
FROM   tags_csv;

-- ============================================================
-- 方法 3: LATERAL + UNNEST（保留序号）
-- 适用版本: PostgreSQL 9.3+
-- ============================================================
SELECT t.id, t.name, s.ordinality, s.tag
FROM   tags_csv t,
       LATERAL UNNEST(STRING_TO_ARRAY(t.tags, ','))
              WITH ORDINALITY AS s(tag, ordinality);

-- ============================================================
-- 方法 4: 递归 CTE
-- 适用版本: PostgreSQL 8.4+
-- ============================================================
WITH RECURSIVE split_cte AS (
    SELECT id, name,
           LEFT(tags, POSITION(',' IN tags || ',') - 1)   AS tag,
           SUBSTRING(tags FROM POSITION(',' IN tags || ',') + 1) AS remaining
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           LEFT(remaining, POSITION(',' IN remaining || ',') - 1),
           SUBSTRING(remaining FROM POSITION(',' IN remaining || ',') + 1)
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag FROM split_cte ORDER BY id;
