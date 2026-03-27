-- TDSQL: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] TDSQL 兼容 MySQL 语法
--       https://cloud.tencent.com/document/product/557
--   [2] TDSQL-C (云原生) / TDSQL-A (分析型)

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100),
    tags VARCHAR(500)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO tags_csv (name, tags) VALUES
    ('Alice', 'python,java,sql'),
    ('Bob',   'go,rust'),
    ('Carol', 'sql,python,javascript,typescript');

-- ============================================================
-- 方法 1: JSON_TABLE（TDSQL MySQL 8.0 兼容模式）
-- ============================================================
SELECT t.id, t.name, j.tag
FROM   tags_csv t,
       JSON_TABLE(
           CONCAT('["', REPLACE(t.tags, ',', '","'), '"]'),
           '$[*]' COLUMNS (tag VARCHAR(100) PATH '$')
       ) AS j;

-- ============================================================
-- 方法 2: 递归 CTE
-- ============================================================
WITH RECURSIVE split_cte AS (
    SELECT id, name,
           SUBSTRING_INDEX(tags, ',', 1)  AS tag,
           CASE WHEN LOCATE(',', tags) > 0
                THEN SUBSTRING(tags, LOCATE(',', tags) + 1)
                ELSE '' END               AS remaining,
           1 AS pos
    FROM   tags_csv
    UNION ALL
    SELECT id, name,
           SUBSTRING_INDEX(remaining, ',', 1),
           CASE WHEN LOCATE(',', remaining) > 0
                THEN SUBSTRING(remaining, LOCATE(',', remaining) + 1)
                ELSE '' END,
           pos + 1
    FROM   split_cte
    WHERE  remaining <> ''
)
SELECT id, name, tag, pos FROM split_cte ORDER BY id, pos;

-- ============================================================
-- 方法 3: 数字辅助表 + SUBSTRING_INDEX
-- ============================================================
WITH RECURSIVE nums AS (
    SELECT 1 AS n UNION ALL SELECT n + 1 FROM nums WHERE n < 20
)
SELECT t.id, t.name,
       SUBSTRING_INDEX(SUBSTRING_INDEX(t.tags, ',', n.n), ',', -1) AS tag
FROM   tags_csv t
JOIN   nums n ON n.n <= 1 + LENGTH(t.tags) - LENGTH(REPLACE(t.tags, ',', ''))
ORDER BY t.id, n.n;
