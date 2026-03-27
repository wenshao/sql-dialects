-- Derby: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Apache Derby Documentation - String Functions
--       https://db.apache.org/derby/docs/10.16/ref/
--   [2] Apache Derby Documentation - Built-in Functions
--       https://db.apache.org/derby/docs/10.16/ref/rrefsqlj29026.html

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(100),
    tags VARCHAR(500)
);

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 方法: 递归 CTE（Derby 10.12+）
-- Derby 功能有限，递归 CTE 是主要方法
-- ============================================================
WITH RECURSIVE split_cte (id, name, tag, remaining, pos) AS (
    SELECT id, name,
           CASE WHEN LOCATE(',', tags) > 0
                THEN SUBSTR(tags, 1, LOCATE(',', tags) - 1)
                ELSE tags END,
           CASE WHEN LOCATE(',', tags) > 0
                THEN SUBSTR(tags, LOCATE(',', tags) + 1)
                ELSE '' END,
           1
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           CASE WHEN LOCATE(',', remaining) > 0
                THEN SUBSTR(remaining, 1, LOCATE(',', remaining) - 1)
                ELSE remaining END,
           CASE WHEN LOCATE(',', remaining) > 0
                THEN SUBSTR(remaining, LOCATE(',', remaining) + 1)
                ELSE '' END,
           pos + 1
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;
