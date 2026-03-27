-- Flink SQL: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Flink Documentation - String Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/#string-functions
--   [2] Flink Documentation - UNNEST
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/joins/#array-expansion

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE tags_csv (
    id   INT,
    name STRING,
    tags STRING
) WITH (
    'connector' = 'datagen'
);

-- ============================================================
-- 方法 1: CROSS JOIN UNNEST + STRING_TO_ARRAY（推荐, Flink 1.15+）
-- ============================================================
SELECT t.id, t.name, tag
FROM   tags_csv t
CROSS JOIN UNNEST(STRING_TO_ARRAY(t.tags, ',')) AS s(tag);

-- ============================================================
-- 方法 2: 自定义 UDTF（User-Defined Table Function）
-- 如果内置功能不满足需求，可注册 Java/Scala UDTF
-- ============================================================
-- CREATE FUNCTION split_str AS 'com.example.SplitFunction';
-- SELECT t.id, t.name, s.word
-- FROM tags_csv t, LATERAL TABLE(split_str(t.tags, ',')) AS s(word);
