# PolarDB: 日期函数

PolarDB-X (distributed, MySQL compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)
> - 当前日期时间

```sql
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT SYSDATE();
SELECT CURDATE();
SELECT CURTIME();
SELECT UTC_TIMESTAMP();
```

## 构造日期

```sql
SELECT MAKEDATE(2024, 100);                  -- 2024-04-09
SELECT MAKETIME(10, 30, 0);                  -- 10:30:00
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');
```

## 日期加减

```sql
SELECT DATE_ADD('2024-01-15', INTERVAL 1 DAY);
SELECT DATE_ADD('2024-01-15', INTERVAL 3 MONTH);
SELECT DATE_SUB('2024-01-15', INTERVAL 1 YEAR);
SELECT '2024-01-15' + INTERVAL 7 DAY;
```

## 日期差

```sql
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT TIMESTAMPDIFF(MONTH, '2024-01-01', '2024-06-15');
SELECT TIMEDIFF('12:00:00', '10:30:00');
```

## 提取

```sql
SELECT YEAR('2024-01-15');
SELECT MONTH('2024-01-15');
SELECT DAY('2024-01-15');
SELECT EXTRACT(YEAR FROM '2024-01-15');
SELECT DAYOFWEEK('2024-01-15');
SELECT DAYOFYEAR('2024-01-15');
```

## 格式化

```sql
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT DATE_FORMAT(NOW(), '%W, %M %d, %Y');
```

## 截断

```sql
SELECT DATE(NOW());
SELECT LAST_DAY('2024-02-15');
```

## Unix 时间戳

```sql
SELECT UNIX_TIMESTAMP();
SELECT FROM_UNIXTIME(1705276800);
```

注意事项：
日期函数与 MySQL 完全兼容
分布式环境下 NOW() 返回代理层的时间
SYSDATE() 返回实际执行时间
