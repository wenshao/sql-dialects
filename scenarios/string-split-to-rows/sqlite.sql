-- SQLite: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] SQLite Documentation - Recursive CTE
--       https://www.sqlite.org/lang_with.html
--   [2] SQLite Documentation - json_each
--       https://www.sqlite.org/json1.html
--   [3] SQLite Documentation - Built-in String Functions
--       https://www.sqlite.org/lang_corefunc.html

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    tags TEXT
);

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 方法 1: json_each（推荐, SQLite 3.9.0+, 需启用 JSON1 扩展）
-- ============================================================
SELECT t.id, t.name, j.value AS tag
FROM   tags_csv t,
       json_each('["' || REPLACE(t.tags, ',', '","') || '"]') j;

-- ============================================================
-- 方法 2: 递归 CTE（SQLite 3.8.3+）
-- ============================================================
WITH RECURSIVE split_cte AS (
    SELECT id, name,
           CASE WHEN INSTR(tags, ',') > 0
                THEN SUBSTR(tags, 1, INSTR(tags, ',') - 1)
                ELSE tags END                    AS tag,
           CASE WHEN INSTR(tags, ',') > 0
                THEN SUBSTR(tags, INSTR(tags, ',') + 1)
                ELSE '' END                      AS remaining,
           1                                     AS pos
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           CASE WHEN INSTR(remaining, ',') > 0
                THEN SUBSTR(remaining, 1, INSTR(remaining, ',') - 1)
                ELSE remaining END,
           CASE WHEN INSTR(remaining, ',') > 0
                THEN SUBSTR(remaining, INSTR(remaining, ',') + 1)
                ELSE '' END,
           pos + 1
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
