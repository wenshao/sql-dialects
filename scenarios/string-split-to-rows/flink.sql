-- Flink SQL: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] Flink Documentation - String Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/#string-functions
--   [2] Flink Documentation - UNNEST / Array Expansion
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/joins/#array-expansion
--   [3] Flink Documentation - Table Functions
--       https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/udfs/#table-functions

-- ============================================================
-- 1. 示例数据
-- ============================================================

CREATE TABLE tags_csv (
    id   INT,
    name STRING,
    tags STRING
) WITH (
    'connector' = 'datagen',
    'rows-per-second' = '1'
);

-- 生产环境中通常使用 Kafka、文件等连接器:
-- CREATE TABLE tags_csv (
--     id   INT,
--     name STRING,
--     tags STRING
-- ) WITH (
--     'connector' = 'kafka',
--     'topic'     = 'tags_topic',
--     'properties.bootstrap.servers' = 'localhost:9092',
--     'format'    = 'json'
-- );

-- ============================================================
-- 2. CROSS JOIN UNNEST + STRING_TO_ARRAY（推荐, Flink 1.15+）
-- ============================================================

SELECT t.id, t.name, s.tag
FROM   tags_csv t
CROSS JOIN UNNEST(STRING_TO_ARRAY(t.tags, ',')) AS s(tag);

-- 设计分析:
--   STRING_TO_ARRAY(tags, ','): 字符串 → ARRAY<STRING>
--   UNNEST(): 数组 → 多行
--   CROSS JOIN: 关联外表和展开结果
--   Flink 1.15+ 支持 STRING_TO_ARRAY 函数

-- ============================================================
-- 3. LATERAL TABLE 形式
-- ============================================================

SELECT t.id, t.name, s.tag
FROM   tags_csv t,
       LATERAL TABLE(UNNEST(STRING_TO_ARRAY(t.tags, ','))) AS s(tag);

-- LATERAL TABLE 是 Flink SQL 中表函数的标准调用方式
-- 等价于 CROSS JOIN UNNEST

-- ============================================================
-- 4. 带序号的展开
-- ============================================================

SELECT t.id, t.name, s.ordinality, s.tag
FROM   tags_csv t
CROSS JOIN UNNEST(STRING_TO_ARRAY(t.tags, ',')) WITH ORDINALITY AS s(tag, ordinality);

-- WITH ORDINALITY 为元素添加序号（从 1 开始）
-- 适用于需要保留原始顺序的场景

-- ============================================================
-- 5. 去除空白 + 过滤
-- ============================================================

SELECT t.id, t.name, TRIM(s.tag) AS tag
FROM   tags_csv t
CROSS JOIN UNNEST(STRING_TO_ARRAY(t.tags, ',')) AS s(tag)
WHERE  TRIM(s.tag) != '';

-- STRING_TO_ARRAY 可能产生含空白的元素
-- TRIM 去除前后空白，WHERE 过滤空字符串

-- ============================================================
-- 6. 拆分 + 聚合统计
-- ============================================================

SELECT s.tag, COUNT(*) AS user_count
FROM   tags_csv t
CROSS JOIN UNNEST(STRING_TO_ARRAY(t.tags, ',')) AS s(tag)
GROUP  BY s.tag;

-- 注意: 流式 SQL 中的 GROUP BY 需要 watermarks 或配置
-- 批处理模式下无此限制

-- ============================================================
-- 7. SPLIT 函数（Flink 1.16+）
-- ============================================================

-- Flink 1.16+ 也支持 SPLIT 函数（类似于 BigQuery）
-- SELECT t.id, t.name, s.tag
-- FROM tags_csv t, UNNEST(SPLIT(t.tags, ',')) AS s(tag);

-- SPLIT 和 STRING_TO_ARRAY 功能等价
-- SPLIT 语法更简洁，但 STRING_TO_ARRAY 兼容性更好

-- ============================================================
-- 8. 自定义 UDTF（扩展方案）
-- ============================================================

-- 如果内置函数不满足需求，可以注册 Java/Scala UDTF
-- Java UDTF 示例:
--
-- public class SplitFunction extends TableFunction<String> {
--     public void eval(String str, String delimiter) {
--         for (String s : str.split(delimiter)) {
--             collect(s.trim());
--         }
--     }
-- }
--
-- 注册和使用:
-- CREATE FUNCTION split_str AS 'com.example.SplitFunction';
-- SELECT t.id, t.name, s.word
-- FROM tags_csv t, LATERAL TABLE(split_str(t.tags, ',')) AS s(word);

-- UDTF 的优势:
--   可以实现复杂的拆分逻辑（如处理引号、转义字符等）
--   可以返回多列（如 (word, position)）
--   性能通常优于嵌套内置函数

-- ============================================================
-- 9. 流式 vs 批处理模式差异
-- ============================================================

-- 流处理模式:
--   UNNEST 对每条到达的消息实时展开
--   聚合查询需要声明 watermark 或使用 mini-batch 优化
--   结果持续更新（EMIT / INSERT INTO sink）

-- 批处理模式:
--   与传统 SQL 行为一致
--   GROUP BY 无 watermark 限制
--   一次性输出结果

-- ============================================================
-- 10. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. Flink SQL 字符串拆分特性:
--   STRING_TO_ARRAY + UNNEST: 标准方案（Flink 1.15+）
--   SPLIT: 简化方案（Flink 1.16+）
--   WITH ORDINALITY: 保留位置序号
--   UDTF: Java/Scala 自定义拆分逻辑
--
-- 2. 与其他引擎对比:
--   Flink SQL:  CROSS JOIN UNNEST(STRING_TO_ARRAY(...))
--   Spark SQL:  LATERAL VIEW explode(SPLIT(...))
--   ksqlDB:     EXPLODE(SPLIT(...))
--   BigQuery:   UNNEST(SPLIT(...))
--
-- 对引擎开发者:
--   Flink SQL 的 STRING_TO_ARRAY 命名兼容 PostgreSQL
--   CROSS JOIN UNNEST 是标准 SQL 语法（比 LATERAL VIEW 更标准）
--   UDTF 机制让用户可以扩展任意拆分逻辑
--   流式场景下需要注意 1:N 展开对水位线的影响
