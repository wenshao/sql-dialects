# Apache Doris: 聚合函数

 Apache Doris: 聚合函数

 参考资料:
   [1] Doris Documentation - Aggregate Functions
       https://doris.apache.org/docs/sql-manual/sql-functions/

## 1. 基本聚合 (MySQL 兼容)

```sql
SELECT COUNT(*) FROM users;
SELECT COUNT(email) FROM users;
SELECT COUNT(DISTINCT city) FROM users;
SELECT SUM(amount), AVG(amount), MIN(amount), MAX(amount) FROM orders;

```

GROUP BY

```sql
SELECT city, COUNT(*) AS cnt, AVG(age) AS avg_age
FROM users GROUP BY city;

SELECT city, COUNT(*) AS cnt FROM users
GROUP BY city HAVING cnt > 10;

```

GROUP BY 位置引用

```sql
SELECT city, COUNT(*) FROM users GROUP BY 1;

```

## 2. 多维聚合 (GROUPING SETS / ROLLUP / CUBE)

```sql
SELECT city, status, COUNT(*)
FROM users GROUP BY GROUPING SETS ((city), (status), (city, status), ());

SELECT city, status, COUNT(*)
FROM users GROUP BY ROLLUP (city, status);

SELECT city, status, COUNT(*)
FROM users GROUP BY CUBE (city, status);

```

## 3. 字符串聚合

```sql
SELECT GROUP_CONCAT(username ORDER BY username SEPARATOR ', ') FROM users;
SELECT GROUP_CONCAT(DISTINCT city SEPARATOR ', ') FROM users;

```

## 4. 近似聚合 (Doris/StarRocks 特色)

```sql
SELECT APPROX_COUNT_DISTINCT(user_id) FROM orders;
SELECT NDV(user_id) FROM orders;  -- APPROX_COUNT_DISTINCT 别名

```

BITMAP 精确去重 (Doris 独特聚合类型)

```sql
SELECT BITMAP_COUNT(BITMAP_UNION(TO_BITMAP(user_id))) FROM orders;
SELECT BITMAP_UNION_COUNT(TO_BITMAP(user_id)) FROM orders;

```

HLL 近似去重

```sql
SELECT HLL_UNION_AGG(HLL_HASH(user_id)) FROM orders;

```

 设计分析:
   BITMAP 和 HLL 是 Doris/StarRocks 的特色聚合类型:
     BITMAP: 精确去重(位图编码)，适合基数 < 数十亿
     HLL: 近似去重(HyperLogLog)，适合基数极大的场景
   对比 ClickHouse: uniq/uniqExact/uniqHLL12(类似但函数名不同)
   对比 BigQuery:  APPROX_COUNT_DISTINCT(内置 HLL++)

## 5. 百分位数

```sql
SELECT PERCENTILE(amount, 0.5) FROM orders;
SELECT PERCENTILE_APPROX(amount, 0.95) FROM orders;

```

## 6. 收集为数组

```sql
SELECT city, COLLECT_LIST(username) FROM users GROUP BY city;
SELECT city, COLLECT_SET(username) FROM users GROUP BY city;

```

## 7. 统计函数

```sql
SELECT STDDEV(amount), STDDEV_SAMP(amount) FROM orders;
SELECT VARIANCE(amount), VAR_SAMP(amount) FROM orders;

```

位运算聚合

```sql
SELECT BIT_AND(flags), BIT_OR(flags), BIT_XOR(flags) FROM settings;

```
