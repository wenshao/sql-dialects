-- Teradata: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Teradata Documentation - STRTOK_SPLIT_TO_TABLE
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates
--   [2] Teradata Documentation - Recursive Queries
--       https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Manipulation-Language

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   INTEGER GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(100),
    tags VARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES ('Alice', 'python,java,sql');
INSERT INTO tags_csv (name, tags) VALUES ('Bob',   'go,rust');
INSERT INTO tags_csv (name, tags) VALUES ('Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 方法 1: STRTOK_SPLIT_TO_TABLE（推荐, Teradata 14.0+）
-- ============================================================
SELECT t.id, t.name, s.Token AS tag, s.TokenNum AS pos
FROM   tags_csv t,
       TABLE (STRTOK_SPLIT_TO_TABLE(t.id, t.tags, ',')
              RETURNS (id INTEGER, TokenNum INTEGER, Token VARCHAR(100))
       ) AS s;

-- ============================================================
-- 方法 2: 递归 CTE
-- ============================================================
WITH RECURSIVE split_cte (id, name, tag, remaining, pos) AS (
    SELECT id, name,
           CASE WHEN POSITION(',' IN tags) > 0
                THEN SUBSTR(tags, 1, POSITION(',' IN tags) - 1)
                ELSE tags END,
           CASE WHEN POSITION(',' IN tags) > 0
                THEN SUBSTR(tags, POSITION(',' IN tags) + 1)
                ELSE '' END,
           1
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           CASE WHEN POSITION(',' IN remaining) > 0
                THEN SUBSTR(remaining, 1, POSITION(',' IN remaining) - 1)
                ELSE remaining END,
           CASE WHEN POSITION(',' IN remaining) > 0
                THEN SUBSTR(remaining, POSITION(',' IN remaining) + 1)
                ELSE '' END,
           pos + 1
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
