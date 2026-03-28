# TimescaleDB: Views

> 参考资料:
> - [TimescaleDB Documentation - Continuous Aggregates](https://docs.timescale.com/use-timescale/latest/continuous-aggregates/)
> - [PostgreSQL Documentation - CREATE VIEW](https://www.postgresql.org/docs/current/sql-createview.html)
> - [TimescaleDB Documentation - Real-time Aggregates](https://docs.timescale.com/use-timescale/latest/continuous-aggregates/real-time-aggregates/)


## 基本视图（完全兼容 PostgreSQL）

```sql
CREATE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;

CREATE OR REPLACE VIEW active_users AS
SELECT id, username, email, created_at
FROM users
WHERE age >= 18;
```

## 可更新视图 + WITH CHECK OPTION

```sql
CREATE VIEW adult_users AS
SELECT id, username, email, age
FROM users
WHERE age >= 18
WITH CHECK OPTION;
```

## 连续聚合 (Continuous Aggregate) - TimescaleDB 的物化视图

这是 TimescaleDB 的核心功能


## 基于超表的连续聚合（TimescaleDB 2.0+ 推荐语法）

```sql
CREATE MATERIALIZED VIEW hourly_sensor_avg
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', ts) AS bucket,
    device_id,
    AVG(temperature) AS avg_temp,
    MAX(temperature) AS max_temp,
    MIN(temperature) AS min_temp,
    COUNT(*) AS reading_count
FROM sensor_data
GROUP BY bucket, device_id
WITH NO DATA;                               -- 创建时不填充
```

## 手动刷新

```sql
CALL refresh_continuous_aggregate('hourly_sensor_avg', '2024-01-01', '2024-02-01');
```

## 设置自动刷新策略

```sql
SELECT add_continuous_aggregate_policy('hourly_sensor_avg',
    start_offset    => INTERVAL '3 days',
    end_offset      => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour'
);
```

实时聚合（Real-time Aggregation）
默认启用：查询时自动合并物化数据和最新未物化数据
禁用实时聚合：

```sql
ALTER MATERIALIZED VIEW hourly_sensor_avg
SET (timescaledb.materialized_only = true);
```

## 分层连续聚合（连续聚合基于连续聚合）

```sql
CREATE MATERIALIZED VIEW daily_sensor_avg
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', bucket) AS day_bucket,
    device_id,
    AVG(avg_temp) AS daily_avg_temp,
    MAX(max_temp) AS daily_max_temp
FROM hourly_sensor_avg
GROUP BY day_bucket, device_id;
```

## PostgreSQL 标准物化视图（也支持）

```sql
CREATE MATERIALIZED VIEW mv_user_summary AS
SELECT user_id, COUNT(*) AS cnt
FROM orders
GROUP BY user_id;

REFRESH MATERIALIZED VIEW mv_user_summary;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_user_summary;
```

## 删除视图

```sql
DROP VIEW active_users;
DROP VIEW IF EXISTS active_users;
DROP MATERIALIZED VIEW hourly_sensor_avg;
DROP MATERIALIZED VIEW mv_user_summary;
```

## 删除连续聚合刷新策略

```sql
SELECT remove_continuous_aggregate_policy('hourly_sensor_avg');
```

限制：
连续聚合必须基于超表（hypertable）
连续聚合必须使用 time_bucket 函数
实时聚合对最新数据有延迟（取决于刷新策略）
连续聚合的 GROUP BY 必须包含 time_bucket
