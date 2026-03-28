# openGauss/GaussDB: 日期函数

PostgreSQL compatible syntax.

> 参考资料:
> - [openGauss SQL Reference](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html)
> - [GaussDB Documentation](https://support.huaweicloud.com/gaussdb/index.html)
> - 当前日期时间

```sql
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CLOCK_TIMESTAMP();
SELECT CURRENT_DATE;
SELECT LOCALTIME;
SELECT LOCALTIMESTAMP;
```

## 构造日期

```sql
SELECT MAKE_DATE(2024, 1, 15);
SELECT MAKE_TIME(10, 30, 0);
SELECT MAKE_TIMESTAMP(2024, 1, 15, 10, 30, 0);
SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD');
SELECT TO_TIMESTAMP('2024-01-15 10:30:00', 'YYYY-MM-DD HH24:MI:SS');
```

## 日期加减

```sql
SELECT '2024-01-15'::DATE + INTERVAL '1 day';
SELECT '2024-01-15'::DATE + INTERVAL '3 months';
SELECT '2024-01-15'::DATE + 7;
SELECT NOW() - INTERVAL '2 hours 30 minutes';
```

## 日期差

```sql
SELECT '2024-12-31'::DATE - '2024-01-01'::DATE;
SELECT AGE('2024-12-31', '2024-01-01');
SELECT AGE(CURRENT_DATE);
```

## 提取

```sql
SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(MONTH FROM NOW());
SELECT EXTRACT(DOW FROM NOW());
SELECT EXTRACT(EPOCH FROM NOW());
SELECT DATE_PART('year', NOW());
```

## 格式化

```sql
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(NOW(), 'Day, Month DD, YYYY');
```

## 截断

```sql
SELECT DATE_TRUNC('month', NOW());
SELECT DATE_TRUNC('year', NOW());
SELECT DATE_TRUNC('hour', NOW());
```

## 时区转换

```sql
SELECT NOW() AT TIME ZONE 'Asia/Shanghai';
SELECT NOW() AT TIME ZONE 'UTC';
```

## 生成日期序列

```sql
SELECT generate_series('2024-01-01'::DATE, '2024-01-31'::DATE, '1 day'::INTERVAL);
```

注意事项：
日期函数与 PostgreSQL 兼容
支持 INTERVAL 算术运算
支持 DATE_TRUNC 截断
支持 generate_series 生成日期序列
