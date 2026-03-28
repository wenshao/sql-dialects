# Snowflake: 子查询

> 参考资料:
> - [1] Snowflake SQL Reference - Subqueries
>   https://docs.snowflake.com/en/sql-reference/operators-subquery


## 1. 基本语法


标量子查询

```sql
SELECT username, (SELECT COUNT(*) FROM orders WHERE user_id = users.id) AS order_count
FROM users;

```

WHERE 子查询

```sql
SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE amount > 100);
SELECT * FROM users WHERE id NOT IN (SELECT user_id FROM blacklist);

```

EXISTS / NOT EXISTS

```sql
SELECT * FROM users u
WHERE EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
SELECT * FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

```

比较运算符 + ALL / ANY

```sql
SELECT * FROM users WHERE age > (SELECT AVG(age) FROM users);
SELECT * FROM users WHERE age >= ALL (SELECT age FROM users WHERE city = 'Beijing');
SELECT * FROM users WHERE age > ANY (SELECT age FROM users WHERE city = 'Beijing');

```

FROM 子查询（派生表）

```sql
SELECT t.city, t.cnt FROM (
    SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
) t WHERE t.cnt > 10;

```

行子查询

```sql
SELECT * FROM users WHERE (city, age) IN (SELECT city, MIN(age) FROM users GROUP BY city);

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 LATERAL 子查询: 关联执行的显式声明

```sql
SELECT u.username, t.total
FROM users u,
LATERAL (SELECT SUM(amount) AS total FROM orders WHERE user_id = u.id) t;

```

 LATERAL 允许子查询引用外部表的列。
 没有 LATERAL 的 FROM 子查询不能引用外部列（非关联子查询）。
 LATERAL 关键字显式声明关联性，有助于优化器选择执行策略。

 对比:
   PostgreSQL: 支持 LATERAL（与 Snowflake 语法一致）
   MySQL:      8.0.14+ 支持 LATERAL（较晚）
   Oracle:     LATERAL (12c+)
   BigQuery:   不支持 LATERAL（需要用 CROSS JOIN UNNEST 或关联子查询）

### 2.2 QUALIFY 替代子查询: 减少嵌套

传统方式（需要 FROM 子查询）:

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) AS rn
    FROM users
) WHERE rn = 1;

```

QUALIFY 方式（无需子查询）:

```sql
SELECT * FROM users
QUALIFY ROW_NUMBER() OVER (PARTITION BY city ORDER BY age) = 1;

```

 QUALIFY 消除了窗口函数过滤中最常见的子查询场景。
对比: BigQuery 也支持 QUALIFY | PostgreSQL/MySQL 不支持

### 2.3 FLATTEN 子查询（半结构化数据展开）

```sql
SELECT u.username, f.value::STRING AS tag
FROM users u,
LATERAL FLATTEN(input => u.tags) f
WHERE f.value::STRING IN (SELECT tag_name FROM popular_tags);

```

## 3. 关联子查询


```sql
SELECT u.username,
    (SELECT MAX(amount) FROM orders o WHERE o.user_id = u.id) AS max_order
FROM users u;

```

 关联子查询的优化:
   Snowflake 优化器通常将关联子查询转换为 JOIN:
   上面的查询等价于: SELECT u.username, MAX(o.amount) FROM users u LEFT JOIN orders o ...
   但不是所有关联子查询都能转换（如有 LIMIT 的关联子查询）

## 4. 嵌套子查询


```sql
SELECT * FROM users
WHERE city IN (
    SELECT city FROM (
        SELECT city, COUNT(*) AS cnt FROM users GROUP BY city
    ) WHERE cnt > 100
);

```

## 横向对比: 子查询能力矩阵

| 能力          | Snowflake  | BigQuery  | PostgreSQL | MySQL |
|------|------|------|------|------|
| 标量子查询    | 支持       | 支持      | 支持       | 支持 |
| IN / NOT IN   | 支持       | 支持      | 支持       | 支持 |
| EXISTS        | 支持       | 支持      | 支持       | 支持 |
| ALL / ANY     | 支持       | 支持      | 支持       | 支持 |
| LATERAL       | 支持       | 不支持    | 支持       | 8.0.14+ |
| QUALIFY       | 支持       | 支持      | 不支持     | 不支持 |
| FLATTEN       | 独有       | UNNEST    | unnest     | JSON_TABLE |

