# TimescaleDB: ALTER TABLE

> 参考资料:
> - [TimescaleDB API Reference](https://docs.timescale.com/api/latest/)
> - [TimescaleDB Hyperfunctions](https://docs.timescale.com/api/latest/hyperfunctions/)


TimescaleDB 继承 PostgreSQL 全部 ALTER TABLE 语法
额外提供超级表（hypertable）相关配置
添加列

```sql
ALTER TABLE sensor_data ADD COLUMN pressure DOUBLE PRECISION;
ALTER TABLE sensor_data ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';
```

## 删除列

```sql
ALTER TABLE sensor_data DROP COLUMN pressure;
ALTER TABLE sensor_data DROP COLUMN IF EXISTS pressure;
```

## 修改列类型

```sql
ALTER TABLE sensor_data ALTER COLUMN temperature TYPE NUMERIC(10,2);
```

## 修改默认值

```sql
ALTER TABLE sensor_data ALTER COLUMN humidity SET DEFAULT 0.0;
ALTER TABLE sensor_data ALTER COLUMN humidity DROP DEFAULT;
```

## 修改 NOT NULL

```sql
ALTER TABLE sensor_data ALTER COLUMN location SET NOT NULL;
ALTER TABLE sensor_data ALTER COLUMN location DROP NOT NULL;
```

## 重命名列

```sql
ALTER TABLE sensor_data RENAME COLUMN location TO site_name;
```

## 重命名表

```sql
ALTER TABLE sensor_data RENAME TO device_readings;
```

## 添加约束

```sql
ALTER TABLE sensor_data ADD CONSTRAINT chk_temp CHECK (temperature BETWEEN -100 AND 100);
ALTER TABLE sensor_data ADD CONSTRAINT uq_sensor UNIQUE (time, sensor_id);
```

## 删除约束

```sql
ALTER TABLE sensor_data DROP CONSTRAINT chk_temp;
```

## TimescaleDB 特有：超级表配置


## 修改 chunk 时间间隔

```sql
SELECT set_chunk_time_interval('sensor_data', INTERVAL '1 day');
```

## 添加压缩策略

```sql
ALTER TABLE sensor_data SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'sensor_id',
    timescaledb.compress_orderby = 'time DESC'
);
```

## 启用压缩策略（自动压缩超过指定时间的 chunk）

```sql
SELECT add_compression_policy('sensor_data', INTERVAL '7 days');
```

## 移除压缩策略

```sql
SELECT remove_compression_policy('sensor_data');
```

## 添加数据保留策略

```sql
SELECT add_retention_policy('sensor_data', INTERVAL '90 days');
```

## 移除数据保留策略

```sql
SELECT remove_retention_policy('sensor_data');
```

## 手动压缩指定 chunk

```sql
SELECT compress_chunk(c) FROM show_chunks('sensor_data', older_than => INTERVAL '7 days') c;
```

## 手动解压 chunk

```sql
SELECT decompress_chunk(c) FROM show_chunks('sensor_data', older_than => INTERVAL '7 days') c;
```

注意：ALTER TABLE 完全兼容 PostgreSQL 语法
注意：超级表的分区列和时间列不能删除
注意：压缩和保留策略是 TimescaleDB 的核心功能
注意：压缩后的 chunk 不能直接 INSERT/UPDATE/DELETE，需先解压
