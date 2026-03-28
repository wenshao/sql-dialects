# KingbaseES (人大金仓): 日期时间类型

PostgreSQL compatible types.

> 参考资料:
> - [KingbaseES SQL Reference](https://help.kingbase.com.cn/v8/index.html)
> - [KingbaseES Documentation](https://help.kingbase.com.cn/v8/index.html)
> - DATE: 日期
> - TIME: 时间
> - TIME WITH TIME ZONE: 带时区的时间
> - TIMESTAMP: 日期时间
> - TIMESTAMP WITH TIME ZONE (TIMESTAMPTZ): 带时区
> - INTERVAL: 时间间隔

```sql
CREATE TABLE events (
    id         BIGSERIAL PRIMARY KEY,
    event_date DATE,
    event_time TIME,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ
);
```

## 获取当前时间

```sql
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CLOCK_TIMESTAMP();
SELECT CURRENT_DATE;
SELECT LOCALTIMESTAMP;
```

## 构造日期

```sql
SELECT MAKE_DATE(2024, 1, 15);
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
```

## 日期加减

```sql
SELECT '2024-01-15'::DATE + INTERVAL '1 day';
SELECT '2024-01-15'::DATE + INTERVAL '3 months';
SELECT NOW() - INTERVAL '2 hours 30 minutes';
```

## 日期差

```sql
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE;
SELECT AGE('2024-12-31', '2024-01-01');
```

## 提取

```sql
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT DATE_PART('year', NOW());
```

## 格式化

```sql
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
```

## 截断

```sql
SELECT DATE_TRUNC('month', NOW());
SELECT DATE_TRUNC('year', NOW());
```

## 时区转换

```sql
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
```

## 生成日期序列

```sql
SELECT generate_series('2024-01-01'::DATE, '2024-01-31'::DATE, '1 day'::INTERVAL);
```

注意事项：
日期时间类型与 PostgreSQL 完全兼容
Oracle 兼容模式下 DATE 类型包含时分秒
