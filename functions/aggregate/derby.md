# Derby: 聚合函数

基本聚合

```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(email) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount) FROM orders;
SELECT AVG(amount) FROM orders;
SELECT MIN(amount) FROM orders;
SELECT MAX(amount) FROM orders;
```

## GROUP BY

```sql
SELECT city, COUNT(*), AVG(age) FROM users GROUP BY city;
```

## GROUP BY + HAVING

```sql
SELECT city, COUNT(*) AS cnt
FROM users GROUP BY city HAVING COUNT(*) > 10;
```

## 统计函数

```sql
SELECT STDDEV_POP(amount), STDDEV_SAMP(amount) FROM orders;
SELECT VAR_POP(amount), VAR_SAMP(amount) FROM orders;
```

## 不支持的聚合功能


不支持 GROUP_CONCAT / STRING_AGG / LISTAGG
不支持 ARRAY_AGG
不支持 JSON 聚合
不支持 PERCENTILE_CONT / PERCENTILE_DISC
不支持 GROUPING SETS / ROLLUP / CUBE
不支持 FILTER 子句
不支持 BOOL_AND / BOOL_OR
不支持 BIT_AND / BIT_OR / BIT_XOR

## 字符串聚合替代方案


## 使用 XMLSERIALIZE + XMLAGG 模拟字符串聚合

```sql
SELECT SUBSTR(
    XMLSERIALIZE(XMLAGG(XMLPARSE(CONTENT ',' || username PRESERVE WHITESPACE)) AS VARCHAR(1000)),
    2
) AS names
FROM users;
```

或在 Java 存储过程中实现
注意：Derby 聚合函数比较基础
注意：不支持高级聚合（GROUPING SETS, FILTER 等）
注意：不支持字符串聚合（需要 XMLAGG 变通）
注意：VAR_POP/VAR_SAMP 和 STDDEV_POP/STDDEV_SAMP 可用
