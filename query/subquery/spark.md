# Spark SQL: 子查询 (Subqueries)

> 参考资料:
> - [1] Spark SQL - Subqueries
>   https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-subqueries.html


## 1. 标量子查询（SELECT 子句中）

```sql
SELECT username,
    (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

SELECT username,
    (SELECT MAX(amount) FROM orders WHERE user_id = users.id) AS max_order
FROM users;

```

## 2. WHERE 子句子查询

```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);

```

EXISTS / NOT EXISTS

```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

相关子查询

```sql
SELECT * FROM users u
WHERE (SELECT SUM(amount) FROM orders WHERE user_id = u.id) > 1000;

```

## 3. FROM 子句子查询（派生表）

```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

```

JOIN 中的子查询

```sql
SELECT u.username, o.total
FROM users u
JOIN (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id
) o ON u.id = o.user_id;

```

## 4. HAVING 子句子查询

```sql
SELECT city, COUNT(*) AS cnt
FROM users
GROUP BY city
HAVING COUNT(*) > (
    SELECT AVG(cnt) FROM (SELECT COUNT(*) AS cnt FROM users GROUP BY city)
);

```

## 5. 多列 IN 子查询（Spark 2.4+）

```sql
SELECT * FROM users
WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

```

## 6. LATERAL 子查询（Spark 3.4+）

```sql
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

```

 LATERAL 子查询允许在 FROM 子句中引用外层查询的列
 等价于相关子查询，但语法更清晰
 对比:
   PostgreSQL: LATERAL JOIN 从 9.3 开始支持
   MySQL:      LATERAL 从 8.0.14 开始支持
   SQL Server: CROSS APPLY / OUTER APPLY
   Oracle:     LATERAL 从 12c 开始支持

## 7. LEFT SEMI/ANTI JOIN（子查询的高效替代）


LEFT SEMI JOIN = EXISTS 子查询（通常更高效）

```sql
SELECT * FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;

```

LEFT ANTI JOIN = NOT EXISTS 子查询（通常更高效）

```sql
SELECT * FROM users u
LEFT ANTI JOIN orders o ON u.id = o.user_id;

```

 性能对比:
   EXISTS 子查询: Catalyst 会尝试解关联（de-correlate）为 Semi Join
   LEFT SEMI JOIN: 直接使用 Semi Join，跳过解关联步骤
   在大多数情况下性能相同（优化器足够智能），但 SEMI JOIN 语法更明确

## 8. 嵌套子查询

```sql
SELECT * FROM users
WHERE city IN (
    SELECT city FROM users
    GROUP BY city
    HAVING AVG(age) > (SELECT AVG(age) FROM users)
);

```

## 9. 设计分析: 子查询的优化挑战


 Spark 的 Catalyst 优化器对子查询的处理:
1. 解关联（De-correlation）: 将相关子查询转换为 JOIN

2. 子查询展平（Flattening）: 将嵌套子查询提升为同级 JOIN

3. 广播优化: 小的子查询结果可以被广播到所有 Executor


 深层嵌套的相关子查询可能导致性能问题:
   每层嵌套可能产生额外的 Shuffle
   解关联失败时，退化为逐行执行（外层每行执行一次内层查询）
   推荐: 将复杂子查询重写为 CTE + JOIN

## 10. 版本演进

Spark 2.0: 标量子查询, IN, EXISTS
Spark 2.1: 相关子查询改进
Spark 2.4: 多列 IN 子查询
Spark 3.0: 子查询优化增强（更好的解关联）
Spark 3.4: LATERAL 子查询

限制:
ALL/ANY/SOME 子查询操作符支持有限
深层嵌套相关子查询可能性能差
不支持子查询在 SELECT 列表中返回多行/多列
LEFT SEMI/ANTI JOIN 通常比 EXISTS 子查询更高效（推荐使用）

