# TimescaleDB: 触发器

## TimescaleDB 继承 PostgreSQL 全部触发器功能

BEFORE INSERT

```sql
CREATE OR REPLACE FUNCTION trg_sensor_before_insert()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.temperature IS NULL THEN
        NEW.temperature := 0;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sensor_bi
BEFORE INSERT ON sensor_data
FOR EACH ROW
EXECUTE FUNCTION trg_sensor_before_insert();
```

## AFTER INSERT

```sql
CREATE OR REPLACE FUNCTION trg_sensor_after_insert()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.temperature > 100 THEN
        INSERT INTO alerts (time, sensor_id, message)
        VALUES (NEW.time, NEW.sensor_id, 'High temperature: ' || NEW.temperature);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sensor_ai
AFTER INSERT ON sensor_data
FOR EACH ROW
EXECUTE FUNCTION trg_sensor_after_insert();
```

## 语句级触发器

```sql
CREATE OR REPLACE FUNCTION trg_sensor_after_stmt()
RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'Batch insert completed on sensor_data';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sensor_stmt
AFTER INSERT ON sensor_data
FOR EACH STATEMENT
EXECUTE FUNCTION trg_sensor_after_stmt();
```

## 条件触发器

```sql
CREATE TRIGGER trg_critical_temp
AFTER INSERT ON sensor_data
FOR EACH ROW
WHEN (NEW.temperature > 100)
EXECUTE FUNCTION trg_sensor_after_insert();
```

## 删除触发器

```sql
DROP TRIGGER IF EXISTS trg_sensor_bi ON sensor_data;
```

## 查看触发器

```sql
SELECT * FROM information_schema.triggers WHERE event_object_table = 'sensor_data';
```

## TimescaleDB 特有：连续聚合替代触发器


## 连续聚合自动维护，无需触发器

```sql
CREATE MATERIALIZED VIEW hourly_alerts
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', time) AS bucket,
       sensor_id,
       MAX(temperature) AS max_temp,
       COUNT(*) FILTER (WHERE temperature > 100) AS alert_count
FROM sensor_data
GROUP BY bucket, sensor_id;
```

注意：触发器在超级表的每个 chunk 上独立执行
注意：大批量插入时触发器可能影响性能
注意：连续聚合通常比触发器更适合时序分析
注意：完全兼容 PostgreSQL 触发器语法
