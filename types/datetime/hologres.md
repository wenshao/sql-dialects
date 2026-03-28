# Hologres: 日期时间类型

Hologres 兼容 PostgreSQL 类型系统

> 参考资料:
> - [Hologres - Data Types](https://help.aliyun.com/zh/hologres/user-guide/data-types)
> - [Hologres - Date/Time Functions](https://help.aliyun.com/zh/hologres/user-guide/date-time-functions)


DATE: 日期，4713 BC ~ 5874897 AD
TIME: 时间（无时区）
TIMESTAMP: 日期时间（无时区），精度到微秒
TIMESTAMPTZ: 日期时间（带时区），精度到微秒
INTERVAL: 时间间隔

```sql
CREATE TABLE events (
    id           BIGSERIAL PRIMARY KEY,
    event_date   DATE,
    event_time   TIME,
    created_at   TIMESTAMP,               -- 无时区
    updated_at   TIMESTAMPTZ              -- 带时区（推荐）
);
```

TIMESTAMP vs TIMESTAMPTZ:
TIMESTAMP: 存什么就是什么，不做时区转换
TIMESTAMPTZ: 存入时转为 UTC，读取时转为会话时区
获取当前时间

```sql
SELECT NOW();                              -- TIMESTAMPTZ
SELECT CURRENT_TIMESTAMP;                -- TIMESTAMPTZ
SELECT CURRENT_DATE;                     -- DATE
SELECT CURRENT_TIME;                     -- TIME WITH TIME ZONE
```

## 构造日期时间（PostgreSQL 语法）

```sql
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
```

## 日期加减

```sql
SELECT DATE '2024-01-15' + INTERVAL '7 days';
SELECT NOW() + INTERVAL '3 months';
SELECT DATE '2024-01-15' + 7;             -- 加天数
```

## 日期差

```sql
SELECT DATE '2024-12-31' - DATE '2024-01-01';  -- 365（整数天数）
```

## 提取

```sql
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT EXTRACT(DAY FROM NOW());
SELECT EXTRACT(EPOCH FROM NOW());         -- Unix 时间戳
```

## 格式化

```sql
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
```

## 截断

```sql
SELECT DATE_TRUNC('month', NOW());        -- 月初
SELECT DATE_TRUNC('year', NOW());         -- 年初
```

## 时区转换

```sql
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
```

注意：与 PostgreSQL 基本一致
注意：不支持 MAKE_DATE / MAKE_TIMESTAMP 等构造函数
注意：不支持 generate_series 生成日期序列
注意：INTERVAL 支持但功能可能受限
注意：MaxCompute DATETIME -> TIMESTAMPTZ 映射
