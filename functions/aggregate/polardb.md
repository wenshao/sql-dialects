# PolarDB: 聚合函数

PolarDB-X (distributed, MySQL compatible).

> 参考资料:
> - [PolarDB-X SQL Reference](https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/)
> - [PolarDB MySQL Documentation](https://help.aliyun.com/zh/polardb/polardb-for-mysql/)
> - 基本聚合

```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;
```

## GROUP BY

```sql
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users
GROUP BY city;
```

## GROUP BY + HAVING

```sql
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING cnt > 10;
```

## WITH ROLLUP

```sql
SELECT city, COUNT(*) FROM users GROUP BY city WITH ROLLUP;
```

## 字符串聚合

```sql
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;
SELECT GROUP_CONCAT(DISTINCT city SEPARATOR ', ') FROM users;
```

## JSON 聚合

```sql
SELECT JSON_ARRAYAGG(username) FROM users;
SELECT JSON_OBJECTAGG(username, age) FROM users;
```

## 统计函数

```sql
SELECT STD(amount) FROM orders;
SELECT STDDEV(amount) FROM orders;
SELECT VARIANCE(amount) FROM orders;
```

## BIT 聚合

```sql
SELECT BIT_AND(flags) FROM settings;
SELECT BIT_OR(flags) FROM settings;
SELECT BIT_XOR(flags) FROM settings;
```

注意事项：
聚合函数在分布式环境下需要合并各分片的中间结果
COUNT(DISTINCT) 在分布式环境下需要全局去重
GROUP BY 如果对齐分区键则性能更好
GROUP_CONCAT 的结果在各分片上拼接后再合并
