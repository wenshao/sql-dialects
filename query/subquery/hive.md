# Hive: 子查询

> 参考资料:
> - [1] Apache Hive Language Manual - SubQueries
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+SubQueries
> - [2] Apache Hive Language Manual - SELECT
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Select


## 1. FROM 子查询 (所有版本支持)

FROM 子查询是 Hive 最早支持的子查询形式

```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

```

嵌套 FROM 子查询

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) ranked WHERE rn <= 3;

```

FROM 子查询 + LATERAL VIEW

```sql
SELECT u.username, tag FROM (
    SELECT * FROM users WHERE status = 1
) u LATERAL VIEW EXPLODE(u.tags) t AS tag;

```

## 2. WHERE 子查询 (0.13+)

IN 子查询

```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);

```

NOT IN

```sql
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

```

EXISTS

```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

NOT EXISTS

```sql
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

 设计分析: 0.13 之前的 WHERE 子查询限制
### 0.13 之前 Hive 不支持 WHERE IN/EXISTS 子查询。

 替代方案: 将子查询改写为 JOIN
 SELECT * FROM users WHERE id IN (SELECT user_id FROM orders)
 → SELECT u.* FROM users u LEFT SEMI JOIN orders o ON u.id = o.user_id

## 3. 标量子查询 (0.13+ 非关联, 2.0+ 关联)

非关联标量子查询 (0.13+)

```sql
SELECT username, age, (SELECT AVG(age) FROM users) AS avg_age FROM users;

```

关联标量子查询 (2.0+)

```sql
SELECT u.username,
    (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) AS order_count,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

```

 关联标量子查询的执行: 优化器通常将其转换为 LEFT JOIN + 聚合

## 4. LEFT SEMI JOIN: 子查询的高效替代

LEFT SEMI JOIN 等价于 IN/EXISTS 子查询，但在 Hive 中通常更高效

```sql
SELECT u.* FROM users u
LEFT SEMI JOIN orders o ON u.id = o.user_id;
```

 等价于: SELECT * FROM users WHERE id IN (SELECT user_id FROM orders)

 SEMI JOIN 的优化: 只需找到第一个匹配行就停止扫描右表
 对比 INNER JOIN: 会返回所有匹配行（可能重复）

## 5. 已知限制

### 1. 不支持 ALL / ANY / SOME 运算符:

    WHERE col > ALL (SELECT ...) 不可用
### 2. 不支持标准 LATERAL 子查询:

    SELECT * FROM t, LATERAL (SELECT ...) 不可用（用 LATERAL VIEW 替代）
### 3. WHERE 子查询 0.13 之前不支持: 必须改写为 JOIN

### 4. 关联标量子查询 2.0 之前不支持

### 5. NOT IN + NULL 陷阱: 如果子查询结果包含 NULL，NOT IN 可能返回空集

    （SQL 标准行为，但经常导致困惑）

## 6. 跨引擎对比: 子查询能力

 引擎          FROM子查询  IN/EXISTS  关联子查询  LATERAL  ALL/ANY
 MySQL         支持        支持       支持        8.0.14+  支持
 PostgreSQL    支持        支持       支持        支持     支持
 Oracle        支持        支持       支持        12c+     支持
 Hive          支持        0.13+      2.0+        不支持   不支持
 Spark SQL     支持        支持       支持        不支持   不支持
 BigQuery      支持        支持       支持        不支持   不支持
 Trino         支持        支持       支持        不支持   部分支持

## 7. 对引擎开发者的启示

### 1. 子查询去关联化是优化器的核心能力:

    关联子查询性能差（逐行执行子查询），优化器应将其转换为 JOIN
### 2. LEFT SEMI JOIN 应该是一等公民:

    EXISTS 语义在大数据引擎中比 INNER JOIN 更高效（提前终止）
### 3. NOT IN + NULL 的语义需要在文档中明确:

    这是 SQL 中最常见的陷阱之一，引擎应该提供友好的警告
### 4. FROM 子查询是最基础的: 它的实现只需要在查询计划中嵌套子树

