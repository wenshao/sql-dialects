# ksqlDB: 执行计划与查询分析

> 参考资料:
> - [ksqlDB Documentation - EXPLAIN](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/explain/)
> - [ksqlDB Documentation - Processing Log](https://docs.ksqldb.io/en/latest/reference/processing-log/)


## EXPLAIN 基本用法


## 解释持久查询

```sql
EXPLAIN query_id;
```

## 解释 SQL 语句

```sql
EXPLAIN SELECT * FROM users_stream WHERE age > 25 EMIT CHANGES;
```

## EXPLAIN 输出内容


输出包含：
1. 查询 ID
2. 查询状态（RUNNING, PAUSED, ERROR）
3. Kafka Streams 拓扑
4. 执行计划（逻辑计划）
逻辑计划示例：
> [ FILTER ] | Schema: ...
>   > [ SOURCE ] | Schema: ...
>     > [ PROJECT ] | Schema: ...

## 查看运行中的查询


## 列出所有持久查询

```sql
SHOW QUERIES;
```

## 扩展信息

```sql
SHOW QUERIES EXTENDED;
```

## 拓扑描述


EXPLAIN 输出中的 Kafka Streams 拓扑：
Topologies:
Sub-topology: 0
Source:  KSTREAM-SOURCE-0000000000 (topics: [users])
> KSTREAM-TRANSFORMVALUES-0000000001
Processor: KSTREAM-TRANSFORMVALUES-0000000001
> KSTREAM-FILTER-0000000002
Processor: KSTREAM-FILTER-0000000002
> KSTREAM-SINK-0000000003
Sink: KSTREAM-SINK-0000000003 (topic: output)

## 查询性能指标


通过 REST API：
GET http://ksqldb-host:8088/clusterStatus
JMX 指标（Kafka Streams 指标）：
records-consumed-rate
records-produced-rate
process-latency-avg
commit-latency-avg

## Processing Log（处理日志）


ksqlDB 的处理日志是一个 Kafka Topic
默认 Topic: _confluent-ksql-default_ksql_processing_log
查看处理日志

```sql
CREATE STREAM processing_log_stream (
    logger STRING,
    level STRING,
    message STRING
) WITH (
    KAFKA_TOPIC='_confluent-ksql-default_ksql_processing_log',
    VALUE_FORMAT='JSON'
);

SELECT * FROM processing_log_stream EMIT CHANGES;
```

## 查询状态管理


## 暂停查询

```sql
PAUSE query_id;
```

## 恢复查询

```sql
RESUME query_id;
```

## 终止查询

```sql
TERMINATE query_id;
```

注意：ksqlDB EXPLAIN 显示 Kafka Streams 拓扑
注意：查询是长时间运行的流处理作业
注意：性能指标通过 JMX 或 REST API 获取
注意：Processing Log 记录处理错误和警告
注意：SHOW QUERIES EXTENDED 提供查询的详细状态信息
