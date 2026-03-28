# TimescaleDB: 条件函数

## TimescaleDB 继承 PostgreSQL 全部条件函数

CASE WHEN

```sql
SELECT sensor_id, temperature,
    CASE
        WHEN temperature > 50 THEN 'critical'
        WHEN temperature > 30 THEN 'warning'
        ELSE 'normal'
    END AS status
FROM sensor_data;
```

## 简单 CASE

```sql
SELECT sensor_id,
    CASE sensor_id WHEN 1 THEN 'primary' WHEN 2 THEN 'backup' ELSE 'other' END
FROM sensor_data;
```

## COALESCE

```sql
SELECT COALESCE(humidity, temperature, 0) FROM sensor_data;
```

## NULLIF

```sql
SELECT NULLIF(temperature, 0) FROM sensor_data;
```

## GREATEST / LEAST

```sql
SELECT GREATEST(temperature, humidity) FROM sensor_data;
SELECT LEAST(temperature, humidity) FROM sensor_data;
```

## 类型转换

```sql
SELECT CAST('123' AS INTEGER);
SELECT '123'::INT;
SELECT CAST(temperature AS NUMERIC(10,2)) FROM sensor_data;
```

## 条件聚合

```sql
SELECT sensor_id,
    COUNT(*) FILTER (WHERE temperature > 30) AS hot_count,
    AVG(temperature) FILTER (WHERE humidity > 50) AS humid_avg
FROM sensor_data GROUP BY sensor_id;
```

## BOOL 表达式

```sql
SELECT sensor_id, temperature,
    temperature > 30 AS is_hot,
    temperature BETWEEN 20 AND 25 AS is_comfortable
FROM sensor_data;
```

注意：完全兼容 PostgreSQL 条件函数
注意：FILTER 子句很强大（条件聚合）
注意：支持 :: 类型转换语法
