-- Impala: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Impala Documentation - String Functions
--       https://impala.apache.org/docs/build/html/topics/impala_string_functions.html
--   [2] Impala Documentation - Complex Types
--       https://impala.apache.org/docs/build/html/topics/impala_complex_types.html

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   INT,
    name STRING,
    tags STRING
) STORED AS PARQUET;

-- ============================================================
-- 方法 1: 数字表 + SPLIT_PART（推荐）
-- Impala 不支持 LATERAL VIEW explode 对 split() 返回值
-- ============================================================
WITH nums AS (
    SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3
    UNION ALL SELECT 4 UNION ALL SELECT 5
    UNION ALL SELECT 6 UNION ALL SELECT 7
    UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
)
SELECT t.id, t.name,
       SPLIT_PART(t.tags, ',', n.n) AS tag
FROM   tags_csv t
JOIN   nums n
  ON   n.n <= SIZE(SPLIT(t.tags, ','))
WHERE  SPLIT_PART(t.tags, ',', n.n) <> ''
ORDER BY t.id, n.n;

-- ============================================================
-- 方法 2: 如果数据类型是 ARRAY<STRING>，直接用 UNNEST（Impala 3.x+）
-- ============================================================
-- 建表时直接用 ARRAY 类型的场景
-- SELECT t.id, t.name, item
-- FROM tags_array t, t.tags_arr item;
