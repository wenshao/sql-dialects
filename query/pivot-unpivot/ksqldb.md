# ksqlDB: PIVOT / UNPIVOT（有限支持）

> 参考资料:
> - [ksqlDB Documentation - Aggregate Functions](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/aggregate-functions/)
> - [ksqlDB Documentation - Queries](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/select-push-query/)


## 注意：ksqlDB 是流处理引擎，不支持标准 PIVOT / UNPIVOT

可通过 CASE WHEN + GROUP BY 在窗口内做有限的行转列


## PIVOT: CASE WHEN + 窗口聚合

## 在时间窗口内做行转列

```sql
SELECT
    sensor_id,
    SUM(CASE WHEN metric_type = 'temperature' THEN metric_value ELSE 0 END) AS temperature,
    SUM(CASE WHEN metric_type = 'humidity' THEN metric_value ELSE 0 END) AS humidity,
    SUM(CASE WHEN metric_type = 'pressure' THEN metric_value ELSE 0 END) AS pressure
FROM sensor_readings
WINDOW TUMBLING (SIZE 1 MINUTE)
GROUP BY sensor_id
EMIT CHANGES;
```

## UNPIVOT: 多个 INSERT INTO 同一流

## 创建目标流

```sql
CREATE STREAM metric_values (
    sensor_id VARCHAR KEY,
    metric_name VARCHAR,
    metric_value DOUBLE,
    event_time TIMESTAMP
) WITH (
    KAFKA_TOPIC = 'metric_values',
    VALUE_FORMAT = 'JSON'
);
```

## 分别写入各指标（等价于 UNPIVOT）

```sql
INSERT INTO metric_values
SELECT sensor_id, 'temperature' AS metric_name, temperature AS metric_value, event_time
FROM sensor_readings
EMIT CHANGES;

INSERT INTO metric_values
SELECT sensor_id, 'humidity' AS metric_name, humidity AS metric_value, event_time
FROM sensor_readings
EMIT CHANGES;
```

## 注意事项

ksqlDB 不支持标准 PIVOT/UNPIVOT 语法
PIVOT 仅在时间窗口内通过 CASE WHEN 实现有限行转列
UNPIVOT 通过多个 INSERT INTO 同一流实现
流数据的 schema 必须预先定义，不支持动态列
所有操作都是持续查询
