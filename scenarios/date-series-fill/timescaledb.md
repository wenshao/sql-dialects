# TimescaleDB: 日期序列生成与间隙填充 (Date Series Fill)

> 参考资料:
> - [TimescaleDB Documentation - time_bucket_gapfill](https://docs.timescale.com/api/latest/hyperfunctions/gapfilling/time_bucket_gapfill/)
> - [TimescaleDB Documentation - locf / interpolate](https://docs.timescale.com/api/latest/hyperfunctions/gapfilling/locf/)
> - [PostgreSQL Documentation - generate_series](https://www.postgresql.org/docs/current/functions-srf.html)
> - ============================================================
> - 准备数据
> - ============================================================

```sql
CREATE TABLE daily_sales (sale_date DATE PRIMARY KEY, amount NUMERIC(10,2));
INSERT INTO daily_sales VALUES
    ('2024-01-01',100),('2024-01-02',150),('2024-01-04',200),
    ('2024-01-05',120),('2024-01-08',300),('2024-01-09',250),('2024-01-10',180);
```

## 创建超表（TimescaleDB 特有）

```sql
CREATE TABLE sensor_data (
    ts    TIMESTAMPTZ NOT NULL,
    value DOUBLE PRECISION
);
SELECT create_hypertable('sensor_data', 'ts');
INSERT INTO sensor_data VALUES
    ('2024-01-01 00:00:00', 10.5),
    ('2024-01-01 02:00:00', 11.2),
    ('2024-01-01 05:00:00', 12.1),
    ('2024-01-01 06:00:00', 9.8);
```

## generate_series（PostgreSQL 标准方法）


```sql
SELECT d::DATE FROM generate_series(
    '2024-01-01'::DATE, '2024-01-10'::DATE, INTERVAL '1 day'
) AS t(d);
```

## time_bucket_gapfill（TimescaleDB 特有）


## 自动填充时间间隙，用 0 填充

```sql
SELECT
    time_bucket_gapfill('1 day', sale_date) AS bucket,
    COALESCE(SUM(amount), 0)                AS amount
FROM daily_sales
WHERE sale_date >= '2024-01-01' AND sale_date <= '2024-01-10'
GROUP BY bucket
ORDER BY bucket;
```

## 按小时填充传感器数据

```sql
SELECT
    time_bucket_gapfill('1 hour', ts) AS bucket,
    AVG(value)                        AS avg_value
FROM sensor_data
WHERE ts >= '2024-01-01' AND ts < '2024-01-02'
GROUP BY bucket
ORDER BY bucket;
```

## locf —— 用最近已知值填充（Last Observation Carried Forward）


```sql
SELECT
    time_bucket_gapfill('1 day', sale_date) AS bucket,
    locf(AVG(amount))                       AS filled_amount
FROM daily_sales
WHERE sale_date >= '2024-01-01' AND sale_date <= '2024-01-10'
GROUP BY bucket
ORDER BY bucket;
```

## 带默认值的 locf

```sql
SELECT
    time_bucket_gapfill('1 hour', ts)  AS bucket,
    locf(AVG(value), treat_null_as_missing => true) AS filled_value
FROM sensor_data
WHERE ts >= '2024-01-01' AND ts < '2024-01-02'
GROUP BY bucket
ORDER BY bucket;
```

## interpolate —— 线性插值填充


```sql
SELECT
    time_bucket_gapfill('1 hour', ts) AS bucket,
    interpolate(AVG(value))           AS interpolated_value
FROM sensor_data
WHERE ts >= '2024-01-01' AND ts < '2024-01-02'
GROUP BY bucket
ORDER BY bucket;
```

## LEFT JOIN 标准方法（PostgreSQL 兼容）


```sql
SELECT d::DATE AS date, COALESCE(ds.amount, 0) AS amount
FROM generate_series('2024-01-01'::DATE, '2024-01-10'::DATE, INTERVAL '1 day') AS t(d)
LEFT JOIN daily_sales ds ON ds.sale_date = t.d::DATE
ORDER BY d;
```

## 带连续聚合的间隙填充


创建连续聚合（自动刷新的物化视图）
CREATE MATERIALIZED VIEW hourly_avg
WITH (timescaledb.continuous) AS
SELECT time_bucket('1 hour', ts) AS bucket,
AVG(value) AS avg_val
FROM sensor_data
GROUP BY bucket;
查询连续聚合并填充间隙
SELECT time_bucket_gapfill('1 hour', bucket) AS filled_bucket,
locf(AVG(avg_val)) AS filled_value
FROM hourly_avg
WHERE bucket >= '2024-01-01' AND bucket < '2024-01-02'
GROUP BY filled_bucket ORDER BY filled_bucket;
注意：time_bucket_gapfill 是 TimescaleDB 特有函数
注意：locf = Last Observation Carried Forward（前值填充）
注意：interpolate 执行线性插值
注意：time_bucket_gapfill 必须配合 WHERE 子句指定时间范围
注意：TimescaleDB 完全兼容 PostgreSQL 的 generate_series
