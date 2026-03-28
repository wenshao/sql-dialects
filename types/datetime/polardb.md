# PolarDB: 日期时间类型

PolarDB-X (distributed, MySQL compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)


DATE: 'YYYY-MM-DD'
TIME: 'HH:MM:SS'
DATETIME: 'YYYY-MM-DD HH:MM:SS'，范围 1000-01-01 ~ 9999-12-31
TIMESTAMP: 存储为 UTC，自动转时区，范围 1970-01-01 ~ 2038-01-19
YEAR: 1901 ~ 2155

```sql
CREATE TABLE events (
    id         BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    event_date DATE,
    event_time TIME(3),
    created_at DATETIME(6),
    updated_at TIMESTAMP(6)
);
```

DATETIME vs TIMESTAMP:
DATETIME: 8 字节，不受时区影响
TIMESTAMP: 4 字节，自动转时区，2038 年问题
获取当前时间

```sql
SELECT NOW();
SELECT CURRENT_TIMESTAMP;
SELECT CURDATE();
SELECT CURTIME();
SELECT UTC_TIMESTAMP();
```

## 日期运算

```sql
SELECT DATE_ADD(NOW(), INTERVAL 1 DAY);
SELECT DATE_SUB(NOW(), INTERVAL 1 HOUR);
SELECT DATEDIFF('2024-12-31', '2024-01-01');
SELECT TIMESTAMPDIFF(HOUR, '2024-01-01', NOW());
```

## 格式化

```sql
SELECT DATE_FORMAT(NOW(), '%Y-%m-%d %H:%i:%s');
SELECT STR_TO_DATE('2024-01-15', '%Y-%m-%d');
```

## 提取部分

```sql
SELECT YEAR(NOW()), MONTH(NOW()), DAY(NOW());
SELECT EXTRACT(YEAR FROM NOW());
```

注意事项：
日期时间类型与 MySQL 完全兼容
分布式环境下各节点时区应保持一致
TIMESTAMP 类型有 2038 年问题
