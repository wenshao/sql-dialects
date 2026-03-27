-- Oracle: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Oracle Documentation - REGEXP_SUBSTR
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/REGEXP_SUBSTR.html
--   [2] Oracle Documentation - CONNECT BY
--       https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Hierarchical-Queries.html
--   [3] Oracle 21c - JSON_TABLE
--       https://docs.oracle.com/en/database/oracle/oracle-database/21/sqlrf/JSON_TABLE.html

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR2(100),
    tags VARCHAR2(500)
);

INSERT INTO tags_csv (name, tags) VALUES ('Alice', 'python,java,sql');
INSERT INTO tags_csv (name, tags) VALUES ('Bob',   'go,rust');
INSERT INTO tags_csv (name, tags) VALUES ('Carol', 'sql,python,javascript,typescript');
COMMIT;

-- ============================================================
-- 方法 1: CONNECT BY LEVEL + REGEXP_SUBSTR（推荐, Oracle 10g+）
-- ============================================================
SELECT id, name,
       TRIM(REGEXP_SUBSTR(tags, '[^,]+', 1, LEVEL)) AS tag,
       LEVEL AS pos
FROM   tags_csv
CONNECT BY LEVEL <= REGEXP_COUNT(tags, ',') + 1
       AND PRIOR id = id
       AND PRIOR SYS_GUID() IS NOT NULL
ORDER BY id, pos;

-- ============================================================
-- 方法 2: XMLTABLE（Oracle 10g+）
-- ============================================================
SELECT t.id, t.name, x.tag
FROM   tags_csv t,
       XMLTABLE(
           'for $s in ora:tokenize($str, ",") return $s'
           PASSING t.tags AS "str"
           COLUMNS tag VARCHAR2(100) PATH '.'
       ) x;

-- ============================================================
-- 方法 3: JSON_TABLE（Oracle 12c+）
-- ============================================================
SELECT t.id, t.name, j.tag
FROM   tags_csv t,
       JSON_TABLE(
           '["' || REPLACE(t.tags, ',', '","') || '"]',
           '$[*]' COLUMNS (tag VARCHAR2(100) PATH '$')
       ) j;

-- ============================================================
-- 方法 4: 递归 CTE（Oracle 11gR2+）
-- ============================================================
WITH split_cte (id, name, tag, remaining, pos) AS (
    SELECT id, name,
           REGEXP_SUBSTR(tags, '[^,]+', 1, 1),
           SUBSTR(tags, INSTR(tags || ',', ',') + 1),
           1
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           REGEXP_SUBSTR(remaining, '[^,]+', 1, 1),
           SUBSTR(remaining, INSTR(remaining || ',', ',') + 1),
           pos + 1
    FROM   split_cte
    WHERE  remaining IS NOT NULL AND remaining != ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
