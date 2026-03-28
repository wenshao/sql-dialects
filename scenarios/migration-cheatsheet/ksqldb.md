# ksqlDB: 迁移速查表 (Migration Cheatsheet)

> 参考资料:
> - [ksqlDB Documentation](https://docs.ksqldb.io/en/latest/)


一、数据类型: Kafka流处理
INT→INT, BIGINT→BIGINT, DOUBLE→DOUBLE,
VARCHAR→VARCHAR/STRING, DECIMAL→DECIMAL(p,s), BOOLEAN→BOOLEAN,
DATE→DATE, TIMESTAMP→TIMESTAMP, BYTES→BYTES,
ARRAY→ARRAY<T>, MAP→MAP<K,V>, STRUCT→STRUCT<...>
二、函数: 流处理特有函数(EXPLODE, TIMESTAMPTOSTRING等)
三、陷阱: 基于Kafka的流处理引擎, 区分STREAM和TABLE,
持续查询(EMIT CHANGES), 无传统JOIN(只有Stream-Table/Stream-Stream Join),
数据格式由序列化决定(JSON/AVRO/PROTOBUF)
四、自增: 无（由Kafka消息key/value决定）
五、日期: 使用UNIX时间戳, TIMESTAMPTOSTRING(ts,'yyyy-MM-dd HH:mm:ss')
STRINGTOTIMESTAMP(s, 'yyyy-MM-dd HH:mm:ss');
FORMAT_DATE(d, 'yyyy-MM-dd'); PARSE_DATE(s, 'yyyy-MM-dd');
FORMAT_TIMESTAMP(ts, 'yyyy-MM-dd HH:mm:ss')
六、字符串: LEN, UCASE, LCASE, TRIM, SUBSTRING, REPLACE, INSTR, CONCAT

## 七、数据类型映射（从 SQL 数据库到 ksqlDB）

MySQL/PostgreSQL → ksqlDB:
- INT → INT/INTEGER, BIGINT → BIGINT,
- FLOAT/DOUBLE → DOUBLE, VARCHAR → VARCHAR/STRING,
- DECIMAL(p,s) → DECIMAL(p,s), BOOLEAN → BOOLEAN,
- DATE → DATE, TIMESTAMP → TIMESTAMP,
- BLOB → BYTES, JSON → 不适用 (用JSON格式序列化),
- ARRAY → ARRAY<T>, AUTO_INCREMENT → 不适用
特有类型:
MAP<K,V>, STRUCT<field_name TYPE, ...>, BYTES

### 八、函数等价映射

SQL → ksqlDB:
- COALESCE → COALESCE, IFNULL → IFNULL,
- NOW() → UNIX_TIMESTAMP(),
- LENGTH → LEN, UPPER → UCASE, LOWER → LCASE,
- SUBSTR → SUBSTRING,
- COUNT/SUM/AVG/MIN/MAX → 支持 (聚合)

### 九、常见陷阱补充

基于 Kafka 的流处理引擎，不是传统数据库

```
STREAM: 无界的事件流（追加模式）
TABLE: 有状态的最新视图（可更新）
```
- **持续查询 (EMIT CHANGES)**: 实时输出变更
- **Stream-Table JOIN**: 流与表的实时关联
- **Stream-Stream JOIN**: 两个流的窗口关联
- **数据序列化格式**: JSON, AVRO, PROTOBUF
无 DELETE/UPDATE (由 Kafka 消息语义决定)
- **窗口函数**: TUMBLING, HOPPING, SESSION

### 十、NULL 处理

IFNULL(a, b); COALESCE(a, b, c);
CASE WHEN a IS NULL THEN b ELSE a END;

### 十一、不支持的 SQL 特性

无 JOIN (传统SQL风格), 无 subquery, 无 HAVING (部分),
无 ORDER BY, 无 GROUP BY 窗口函数 (ROW_NUMBER等),
无 UNION/INTERSECT/EXCEPT

### 十二、持续查询示例

CREATE STREAM enriched AS
SELECT s.*, t.name
FROM event_stream s
LEFT JOIN lookup_table t ON s.id = t.id
EMIT CHANGES;
