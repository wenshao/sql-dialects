# Flink SQL: DELETE

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
DELETE FROM users WHERE username = 'alice';

```

JDBC connector: Delete with condition (batch mode)
```sql
DELETE FROM users WHERE status = 0 AND last_login < TIMESTAMP '2023-01-01 00:00:00';

```

For streaming scenarios, "deletes" are handled via changelog:

## Retraction/changelog pattern

When a key disappears from a GROUP BY result, Flink emits a delete (-D) message
This is automatic when using connectors that support changelogs

## Upsert with NULL value (tombstone in Kafka)

Sending a NULL value for a key in upsert-kafka effectively deletes it
```sql
CREATE TABLE user_profiles (
    user_id  BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (user_id) NOT ENFORCED
) WITH (
    'connector' = 'upsert-kafka',
    'topic' = 'user-profiles',
    'properties.bootstrap.servers' = 'kafka:9092',
    'key.format' = 'json',
    'value.format' = 'json'
);
```

A retraction (-D) message will produce a tombstone (null value) in Kafka

## JDBC sink with changelog mode

When the upstream query produces delete messages, JDBC sink
translates them into DELETE statements on the target database
```sql
CREATE TABLE user_stats (
    user_id     BIGINT,
    event_count BIGINT,
    PRIMARY KEY (user_id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'user_stats'
);
```

If a user is removed from the source, the JDBC sink will
issue a DELETE statement to the target database

TRUNCATE TABLE (Flink 1.17+, batch mode, limited connector support)
```sql
TRUNCATE TABLE users;

```

Note: Traditional DELETE only works in batch mode (Flink 1.17+)
Note: Streaming tables use retraction/changelog for deletions
Note: Kafka is append-only; deletions are represented as tombstones
Note: No RETURNING clause
Note: No USING clause for multi-table delete
Note: No CTE + DELETE
Note: DELETE on streaming source tables will cause an error
