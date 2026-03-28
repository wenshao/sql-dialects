# Materialize: 日期时间类型

> 参考资料:
> - [Materialize SQL Reference](https://materialize.com/docs/sql/)
> - [Materialize SQL Functions](https://materialize.com/docs/sql/functions/)


## Materialize 兼容 PostgreSQL 日期时间类型

DATE, TIME, TIMESTAMP, TIMESTAMPTZ, INTERVAL

```sql
CREATE TABLE events (
    id         INT,
    event_date DATE,
    event_time TIME,
    created_at TIMESTAMP,
    updated_at TIMESTAMPTZ                   -- 推荐
);
```

## 获取当前时间

```sql
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CURRENT_DATE;
SELECT CURRENT_TIME;
```

## 日期运算

```sql
SELECT NOW() + INTERVAL '1 day';
SELECT NOW() - INTERVAL '3 hours';
SELECT INTERVAL '1 year 2 months 3 days';
```

## 日期差

```sql
SELECT AGE(NOW(), '2024-01-01'::TIMESTAMPTZ);
```

## 提取

```sql
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT EXTRACT(DOW FROM NOW());
SELECT DATE_PART('hour', NOW());
```

## 截断

```sql
SELECT DATE_TRUNC('hour', NOW());
SELECT DATE_TRUNC('day', NOW());
SELECT DATE_TRUNC('month', NOW());
```

## 格式化

```sql
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
```

## 时区转换

```sql
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
SELECT NOW() AT TIME ZONE 'UTC';
```

## mz_now()（Materialize 特有，系统时钟）

```sql
SELECT mz_now();
```

## 时间过滤（物化视图中）


## AS OF（时间旅行查询）

```sql
SELECT * FROM users AS OF AT LEAST NOW() - INTERVAL '1 hour';
```

## 时间过滤物化视图

```sql
CREATE MATERIALIZED VIEW recent_events AS
SELECT * FROM events
WHERE created_at > NOW() - INTERVAL '24 hours';
```

注意：兼容 PostgreSQL 的日期时间类型和函数
注意：TIMESTAMPTZ 是推荐类型
注意：mz_now() 是 Materialize 特有函数
注意：AS OF 支持时间旅行查询
