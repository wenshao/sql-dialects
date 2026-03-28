# TimescaleDB: 索引

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)
> - TimescaleDB 继承 PostgreSQL 全部索引功能
> - 额外自动为超级表的每个 chunk 创建索引
> - ============================================================
> - 标准索引（自动在每个 chunk 上创建）
> - ============================================================
> - B-tree 索引（默认）

```sql
CREATE INDEX idx_sensor_id ON sensor_data (sensor_id);
```

## 复合索引

```sql
CREATE INDEX idx_sensor_time ON sensor_data (sensor_id, time DESC);
```

## 唯一索引（必须包含时间列）

```sql
CREATE UNIQUE INDEX idx_unique_reading ON sensor_data (time, sensor_id);
```

## IF NOT EXISTS

```sql
CREATE INDEX IF NOT EXISTS idx_location ON sensor_data (location);
```

## PostgreSQL 索引类型


## Hash 索引

```sql
CREATE INDEX idx_device_hash ON metrics USING HASH (device_id);
```

## GIN 索引（JSONB）

```sql
CREATE INDEX idx_payload ON events USING GIN (payload);
```

## GiST 索引（范围查询、地理数据）

```sql
CREATE INDEX idx_location_gist ON readings USING GIST (location);
```

## BRIN 索引（块范围索引，适合时序数据的非时间列）

```sql
CREATE INDEX idx_value_brin ON readings USING BRIN (value);
```

## 部分索引

```sql
CREATE INDEX idx_high_temp ON sensor_data (temperature)
WHERE temperature > 100;
```

## 表达式索引

```sql
CREATE INDEX idx_lower_loc ON sensor_data (LOWER(location));
```

## TimescaleDB 特有：自动索引管理


## 超级表创建时自动创建时间索引

create_hypertable 默认在 (time DESC) 上创建索引

```sql
SELECT create_hypertable('sensor_data', 'time',
    create_default_indexes => TRUE     -- 默认为 TRUE
);
```

## 禁用默认索引

```sql
SELECT create_hypertable('readings', 'time',
    create_default_indexes => FALSE
);
```

## 查看 chunk 上的索引

```sql
SELECT * FROM timescaledb_information.chunks
WHERE hypertable_name = 'sensor_data';
```

## 删除索引


```sql
DROP INDEX idx_sensor_id;
DROP INDEX IF EXISTS idx_sensor_id;
```

## 重建索引

```sql
REINDEX INDEX idx_sensor_id;
REINDEX TABLE sensor_data;
```

注意：超级表的唯一索引/主键必须包含时间列
注意：索引自动在所有 chunk（包括未来的）上创建
注意：BRIN 索引特别适合 TimescaleDB 的时间列以外的列
注意：TimescaleDB 继承 PostgreSQL 的所有索引类型和功能
