-- Spark SQL: 字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Spark SQL - split / explode
--       https://spark.apache.org/docs/latest/api/sql/index.html#split

-- ============================================================
-- 示例数据
-- ============================================================
CREATE OR REPLACE TEMPORARY VIEW tags_csv AS
SELECT 1 AS id, 'Alice' AS name, 'python,java,sql' AS tags
UNION ALL SELECT 2, 'Bob',   'go,rust'
UNION ALL SELECT 3, 'Carol', 'sql,python,javascript,typescript';

-- ============================================================
-- 1. EXPLODE + SPLIT（推荐，最简洁）
-- ============================================================
SELECT id, name, EXPLODE(SPLIT(tags, ',')) AS tag
FROM tags_csv;

-- 设计分析:
--   SPLIT(str, regex) 返回 ARRAY<STRING>
--   EXPLODE(array) 将数组展开为多行
--   两者组合 = PostgreSQL 的 unnest(string_to_array(str, ','))
--   注意: SPLIT 使用正则表达式——特殊字符需要转义（如 '\\.' 而非 '.'）

-- ============================================================
-- 2. LATERAL VIEW EXPLODE（Hive 兼容语法）
-- ============================================================
SELECT t.id, t.name, tag
FROM tags_csv t
LATERAL VIEW EXPLODE(SPLIT(t.tags, ',')) exploded AS tag;

-- LATERAL VIEW 的优势: 可以与源表的其他列自由组合
-- LATERAL VIEW OUTER: 保留空数组/NULL 的行
SELECT t.id, t.name, tag
FROM tags_csv t
LATERAL VIEW OUTER EXPLODE(SPLIT(t.tags, ',')) exploded AS tag;

-- ============================================================
-- 3. POSEXPLODE: 带位置索引
-- ============================================================
SELECT t.id, t.name, pos, tag
FROM tags_csv t
LATERAL VIEW POSEXPLODE(SPLIT(t.tags, ',')) exploded AS pos, tag;

-- pos 从 0 开始，表示元素在数组中的位置
-- 对比: PostgreSQL 的 unnest WITH ORDINALITY

-- ============================================================
-- 4. 对比各引擎的字符串拆分方式
-- ============================================================

-- MySQL:      JSON_TABLE + JSON 转换（8.0+），或递归 CTE（极复杂）
-- PostgreSQL: unnest(string_to_array(str, ','))（最简洁）
--             或 regexp_split_to_table(str, ',')
-- Oracle:     CONNECT BY + REGEXP_SUBSTR（递归分割）
-- SQL Server: STRING_SPLIT(str, ',')（2016+）
-- BigQuery:   SPLIT(str, ',') + UNNEST
-- ClickHouse: arrayJoin(splitByChar(',', str))
-- Spark:      EXPLODE(SPLIT(str, ','))
-- Flink SQL:  UNNEST(SPLIT(str, ','))（标准 UNNEST 语法）

-- ============================================================
-- 5. 拆分后过滤与聚合
-- ============================================================

-- 过滤特定标签
SELECT id, name, tag FROM tags_csv
LATERAL VIEW EXPLODE(SPLIT(tags, ',')) t AS tag
WHERE tag IN ('python', 'sql');

-- 反向操作: 聚合为逗号分隔字符串
SELECT id, name, CONCAT_WS(',', COLLECT_LIST(tag)) AS tags_sorted
FROM (
    SELECT id, name, tag FROM tags_csv
    LATERAL VIEW EXPLODE(SPLIT(tags, ',')) t AS tag
    ORDER BY id, tag
)
GROUP BY id, name;

-- ============================================================
-- 6. 版本演进
-- ============================================================
-- Spark 2.0: SPLIT, EXPLODE, LATERAL VIEW, POSEXPLODE
-- Spark 2.4: LATERAL VIEW OUTER
-- Spark 3.4: EXPLODE 可直接在 SELECT 中使用（无需 LATERAL VIEW）
--
-- 限制:
--   SPLIT 使用正则表达式（特殊字符需转义: '\\.' 而非 '.'）
--   EXPLODE 在 Spark 3.4 之前只能在 LATERAL VIEW 中使用（不能直接在 SELECT）
--   无 STRING_SPLIT 表值函数（SQL Server 风格）
--   大数组展开可能导致数据膨胀（行数 = 原始行数 * 平均数组长度）
