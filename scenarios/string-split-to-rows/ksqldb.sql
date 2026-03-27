-- ksqlDB: 将分隔字符串拆分为多行 (String Split to Rows)
--
-- 参考资料:
--   [1] ksqlDB Documentation - SPLIT
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/scalar-functions/#split
--   [2] ksqlDB Documentation - EXPLODE
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/table-functions/#explode
--   [3] ksqlDB Documentation - Arrays
--       https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/data-types/#array

-- ============================================================
-- 1. 示例数据（流和表）
-- ============================================================

-- 流: 实时标签事件
CREATE STREAM tags_stream (
    id   INT KEY,
    name VARCHAR,
    tags VARCHAR
) WITH (
    KAFKA_TOPIC  = 'tags_topic',
    VALUE_FORMAT = 'JSON'
);

-- 表: 物化标签视图
CREATE TABLE tags_table (
    id   INT PRIMARY KEY,
    name VARCHAR,
    tags VARCHAR
) WITH (
    KAFKA_TOPIC  = 'tags_table_topic',
    VALUE_FORMAT = 'JSON'
);

-- 插入测试数据（通过 Kafka 生产者或 INSERT INTO）
-- INSERT INTO tags_stream (id, name, tags) VALUES (1, 'Alice', 'python,java,sql');
-- INSERT INTO tags_stream (id, name, tags) VALUES (2, 'Bob', 'go,rust');

-- ============================================================
-- 2. EXPLODE + SPLIT（流查询，推荐）
-- ============================================================

SELECT id, name, EXPLODE(SPLIT(tags, ',')) AS tag
FROM   tags_stream
EMIT CHANGES;

-- 设计分析: 流式字符串拆分
--   SPLIT(tags, ','): 字符串 → ARRAY
--   EXPLODE(): 数组 → 多行消息
--   EMIT CHANGES: 持续输出结果（流处理模式）
--   每条输入消息可能产生多条输出消息

-- ============================================================
-- 3. 创建展开后的新流（持续处理）
-- ============================================================

CREATE STREAM tags_expanded AS
SELECT id, name, EXPLODE(SPLIT(tags, ',')) AS tag
FROM   tags_stream;

-- 持续将拆分结果写入新的 Kafka 主题
-- 新流中的每条记录对应一个标签

-- 查询展开后的流
SELECT id, name, tag
FROM   tags_expanded
EMIT CHANGES;

-- ============================================================
-- 4. 拆分 + 聚合（表查询）
-- ============================================================

-- 按标签统计出现次数
SELECT tag, COUNT(*) AS tag_count
FROM   tags_expanded
GROUP  BY tag
EMIT CHANGES;

-- 聚合查询会持续更新结果（每条新消息到达时重新计算）

-- ============================================================
-- 5. 过滤和清洗
-- ============================================================

-- 去除空白标签
SELECT id, name, TRIM(tag) AS tag
FROM   tags_expanded
WHERE  TRIM(tag) != ''
EMIT CHANGES;

-- ============================================================
-- 6. 使用 ARRAY 类型存储
-- ============================================================

-- 如果数据源直接提供数组类型（而非分隔字符串）
CREATE STREAM tags_array_stream (
    id   INT KEY,
    name VARCHAR,
    tags ARRAY<VARCHAR>
) WITH (
    KAFKA_TOPIC  = 'tags_array_topic',
    VALUE_FORMAT = 'JSON'
);

-- 直接 EXPLODE 数组（无需 SPLIT）
SELECT id, name, EXPLODE(tags) AS tag
FROM   tags_array_stream
EMIT CHANGES;

-- 如果 JSON 数据中 tags 是数组格式 ["python","java","sql"]
-- ksqlDB 会自动解析为数组类型

-- ============================================================
-- 7. 拆分 + 窗口聚合（流式场景）
-- ============================================================

-- 按时间窗口统计标签频率
SELECT tag,
       COUNT(*) AS tag_count,
       WINDOW_START AS w_start,
       WINDOW_END   AS w_end
FROM   tags_expanded
WINDOW TUMBLING (SIZE 1 HOUR)
GROUP  BY tag
EMIT CHANGES;

-- TUMBLING 窗口: 每 1 小时统计一次标签出现次数
-- 适用于实时监控标签趋势

-- ============================================================
-- 8. ksqlDB 字符串处理函数
-- ============================================================

-- SPLIT: 按分隔符拆分为数组
--   SPLIT('a,b,c', ',') → ['a', 'b', 'c']
-- EXPLODE: 数组展开为多行
--   EXPLODE(ARRAY['a','b','c']) → 3 行
-- TRIM: 去除空白
--   TRIM(' hello ') → 'hello'

-- 其他相关函数:
SELECT SPLIT('python,java,sql', ',')    AS tag_array,     -- 拆分为数组
       ARRAY_LENGTH(SPLIT('a,b,c', ',')) AS array_len;     -- 数组长度

-- ============================================================
-- 9. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. ksqlDB 字符串拆分特性:
--   SPLIT + EXPLODE: 类似 Spark SQL 的组合方式
--   流式语义: 拆分结果是持续的流，而非一次性查询
--   窗口聚合: 可以结合时间窗口做实时统计
--
-- 2. 与其他流处理引擎对比:
--   ksqlDB:     SPLIT + EXPLODE + EMIT CHANGES
--   Flink SQL:  STRING_TO_ARRAY + UNNEST
--   Spark SS:   SPLIT + EXPLODE（与 ksqlDB 类似）
--   Materialize: STRING_TO_ARRAY + UNNEST（PostgreSQL 兼容）
--
-- 对引擎开发者:
--   流处理引擎的字符串拆分需要考虑"1:N"的消息扩展
--   EXPLODE 将一条消息变为多条，影响下游消费者
--   窗口聚合 + EXPLODE 是实时场景的常见组合
--   支持 ARRAY 类型可避免运行时 SPLIT 的开销
