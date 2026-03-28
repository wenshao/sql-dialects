# Flink SQL: 索引

> 参考资料:
> - [Flink SQL Documentation](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/overview/)
> - [Flink SQL - Built-in Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/)
> - [Flink SQL - Data Types](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/types/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
CREATE TABLE users (
    id         BIGINT,
    username   STRING,
    email      STRING,
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'users'
);
```

The PRIMARY KEY helps Flink optimize changelog processing and lookup joins

## Lookup joins use the source system's indexes

When performing a lookup join against a JDBC table,
the database's own indexes are used for point queries
```sql
CREATE TABLE dim_users (
    id       BIGINT,
    username STRING,
    email    STRING,
    PRIMARY KEY (id) NOT ENFORCED
) WITH (
    'connector' = 'jdbc',
    'url' = 'jdbc:mysql://localhost:3306/mydb',
    'table-name' = 'users',
    'lookup.cache.max-rows' = '5000',
    'lookup.cache.ttl' = '10min'
);
```

The lookup join benefits from indexes on the MySQL side

## State backend configuration (optimizes stateful operations)

SET 'state.backend' = 'rocksdb';
SET 'state.backend.incremental' = 'true';
RocksDB uses LSM-tree internally, no user-level index control

## Partitioning for filesystem tables

```sql
CREATE TABLE logs (
    log_time   TIMESTAMP(3),
    level      STRING,
    message    STRING,
    dt         STRING,
    hr         STRING
) PARTITIONED BY (dt, hr) WITH (
    'connector' = 'filesystem',
    'path' = '/data/logs/',
    'format' = 'parquet'
);
```

Partition pruning helps skip irrelevant files

## Table hints for optimization (Flink 1.15+)

```sql
SELECT /*+ LOOKUP('table'='dim_users', 'retry-predicate'='lookup_miss',
           'retry-strategy'='fixed_delay', 'fixed-delay'='10s', 'max-attempts'='3') */
    e.*, d.username
FROM events AS e
JOIN dim_users FOR SYSTEM_TIME AS OF e.proc_time AS d
ON e.user_id = d.id;

```

Note: Flink has no CREATE INDEX or DROP INDEX statements
Note: Optimization comes from proper key declarations, partitioning,
      lookup caching, and leveraging external system indexes
Note: For stateful operations, Flink manages internal state using
      configurable state backends (HashMap, RocksDB)
