# TimescaleDB: UPSERT

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)
> - TimescaleDB 继承 PostgreSQL 的 ON CONFLICT（UPSERT）语法
> - 超级表要求 UNIQUE 约束包含时间列
> - ============================================================
> - ON CONFLICT DO UPDATE（标准 UPSERT）
> - ============================================================
> - 先创建唯一约束

```sql
CREATE TABLE sensor_data (
    time        TIMESTAMPTZ NOT NULL,
    sensor_id   INT NOT NULL,
    temperature DOUBLE PRECISION,
    humidity    DOUBLE PRECISION,
    UNIQUE (time, sensor_id)
);
SELECT create_hypertable('sensor_data', 'time');
```

## 基本 UPSERT

```sql
INSERT INTO sensor_data (time, sensor_id, temperature, humidity)
VALUES ('2024-01-15 10:00:00+08', 1, 23.5, 65.0)
ON CONFLICT (time, sensor_id) DO UPDATE
SET temperature = EXCLUDED.temperature, humidity = EXCLUDED.humidity;
```

## 条件更新

```sql
INSERT INTO sensor_data (time, sensor_id, temperature, humidity)
VALUES ('2024-01-15 10:00:00+08', 1, 23.5, 65.0)
ON CONFLICT (time, sensor_id) DO UPDATE
SET temperature = EXCLUDED.temperature
WHERE EXCLUDED.temperature > sensor_data.temperature;
```

## ON CONFLICT DO NOTHING（跳过冲突行）

```sql
INSERT INTO sensor_data (time, sensor_id, temperature)
VALUES ('2024-01-15 10:00:00+08', 1, 23.5)
ON CONFLICT (time, sensor_id) DO NOTHING;
```

## 批量 UPSERT

```sql
INSERT INTO sensor_data (time, sensor_id, temperature, humidity) VALUES
    ('2024-01-15 10:00:00+08', 1, 23.5, 65.0),
    ('2024-01-15 10:01:00+08', 1, 23.6, 64.8),
    ('2024-01-15 10:02:00+08', 2, 22.1, 70.2)
ON CONFLICT (time, sensor_id) DO UPDATE
SET temperature = EXCLUDED.temperature, humidity = EXCLUDED.humidity;
```

## ON CONFLICT 使用约束名

```sql
INSERT INTO sensor_data (time, sensor_id, temperature)
VALUES ('2024-01-15 10:00:00+08', 1, 23.5)
ON CONFLICT ON CONSTRAINT sensor_data_time_sensor_id_key DO UPDATE
SET temperature = EXCLUDED.temperature;
```

## RETURNING

```sql
INSERT INTO sensor_data (time, sensor_id, temperature)
VALUES ('2024-01-15 10:00:00+08', 1, 23.5)
ON CONFLICT (time, sensor_id) DO UPDATE
SET temperature = EXCLUDED.temperature
RETURNING *;
```

## MERGE（PostgreSQL 15+）


```sql
MERGE INTO sensor_data AS t
USING (VALUES ('2024-01-15 10:00:00+08'::TIMESTAMPTZ, 1, 23.5, 65.0))
    AS s(time, sensor_id, temperature, humidity)
ON t.time = s.time AND t.sensor_id = s.sensor_id
WHEN MATCHED THEN
    UPDATE SET temperature = s.temperature, humidity = s.humidity
WHEN NOT MATCHED THEN
    INSERT (time, sensor_id, temperature, humidity)
    VALUES (s.time, s.sensor_id, s.temperature, s.humidity);
```

注意：ON CONFLICT 是 TimescaleDB/PostgreSQL 最常用的 UPSERT 方式
注意：超级表的唯一约束必须包含时间列
注意：EXCLUDED 引用试图插入的新行
注意：压缩的 chunk 不能 UPSERT，需先解压
