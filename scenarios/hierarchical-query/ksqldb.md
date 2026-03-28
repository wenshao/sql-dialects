# ksqlDB: 层次查询与树形结构 (Hierarchical Query & Tree Traversal)

> 参考资料:
> - [ksqlDB Documentation - Queries](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/)
> - [ksqlDB Documentation - Joins](https://docs.ksqldb.io/en/latest/developer-guide/joins/join-streams-and-tables/)
> - ============================================================
> - ksqlDB 是流处理引擎，不支持传统层次查询
> - ============================================================
> - 创建组织架构表（物化为 TABLE）

```sql
CREATE TABLE employees (
    id INT PRIMARY KEY,
    name VARCHAR,
    parent_id INT,
    dept VARCHAR
) WITH (
    KAFKA_TOPIC = 'employees',
    VALUE_FORMAT = 'JSON'
);
```

## ksqlDB 中的层次数据处理方式


方法1: 将层次关系扁平化为物化路径，存入 Kafka topic
方法2: 使用多次 JOIN（仅支持 TABLE-TABLE JOIN）
两级 JOIN 示例

```sql
SELECT e1.name AS manager, e2.name AS direct_report
FROM employees e1
JOIN employees e2 ON e2.parent_id = e1.id
EMIT CHANGES;
```

## 使用 Kafka Streams 处理层次数据


对于复杂层次查询，推荐：
1. 使用 Kafka Streams API 实现递归遍历
2. 将结果写回 Kafka topic
3. 在 ksqlDB 中查询扁平化后的结果
注意：ksqlDB 不支持递归 CTE
注意：ksqlDB 不支持 CONNECT BY
注意：ksqlDB 的 JOIN 有严格限制
注意：推荐使用 Kafka Streams 或 Flink 处理层次数据
