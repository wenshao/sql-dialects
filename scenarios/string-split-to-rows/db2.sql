-- DB2: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] IBM DB2 Documentation - XMLTABLE
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-xmltable
--   [2] IBM DB2 Documentation - Recursive CTE
--       https://www.ibm.com/docs/en/db2/11.5?topic=queries-common-table-expression

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(100),
    tags VARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 方法 1: XMLTABLE（推荐）
-- ============================================================
SELECT t.id, t.name, x.tag
FROM   tags_csv t,
       XMLTABLE(
           '$doc/token'
           PASSING XMLPARSE(DOCUMENT
               '<tokens>' ||
               REPLACE(REPLACE(t.tags, '&', '&amp;'), ',', '</token><token>') ||
               '</tokens>'
           ) AS "doc"
           COLUMNS tag VARCHAR(100) PATH '.'
       ) x;

-- ============================================================
-- 方法 2: 递归 CTE
-- ============================================================
WITH split_cte (id, name, tag, remaining, pos) AS (
    SELECT id, name,
           CASE WHEN LOCATE(',', tags) > 0
                THEN LEFT(tags, LOCATE(',', tags) - 1)
                ELSE tags END,
           CASE WHEN LOCATE(',', tags) > 0
                THEN SUBSTR(tags, LOCATE(',', tags) + 1)
                ELSE '' END,
           1
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           CASE WHEN LOCATE(',', remaining) > 0
                THEN LEFT(remaining, LOCATE(',', remaining) - 1)
                ELSE remaining END,
           CASE WHEN LOCATE(',', remaining) > 0
                THEN SUBSTR(remaining, LOCATE(',', remaining) + 1)
                ELSE '' END,
           pos + 1
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
