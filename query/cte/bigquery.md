# BigQuery: CTE（公共表表达式）

> 参考资料:
> - [1] BigQuery SQL Reference - WITH Clause
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#with_clause


## 1. 基本 CTE


```sql
WITH active_users AS (
    SELECT id, username, email FROM myproject.mydataset.users WHERE status = 1
)
SELECT u.username, COUNT(*) AS order_count
FROM active_users u
JOIN myproject.mydataset.orders o ON u.id = o.user_id
GROUP BY u.username;

```

多个 CTE

```sql
WITH
    active AS (SELECT * FROM myproject.mydataset.users WHERE status = 1),
    recent AS (SELECT * FROM myproject.mydataset.orders WHERE order_date >= '2024-01-01')
SELECT a.username, SUM(r.amount) AS total
FROM active a JOIN recent r ON a.id = r.user_id
GROUP BY a.username;

```

## 2. 递归 CTE（BigQuery 支持，但有限制）


层级遍历

```sql
WITH RECURSIVE org_tree AS (
    SELECT id, name, manager_id, 0 AS depth
    FROM myproject.mydataset.employees WHERE manager_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.manager_id, t.depth + 1
    FROM myproject.mydataset.employees e
    JOIN org_tree t ON e.manager_id = t.id
)
SELECT * FROM org_tree;

```

数列生成

```sql
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 100
)
SELECT n FROM nums;

```

替代方案: GENERATE_ARRAY（更高效）

```sql
SELECT n FROM UNNEST(GENERATE_ARRAY(1, 100)) AS n;

```

日期序列

```sql
SELECT d FROM UNNEST(GENERATE_DATE_ARRAY('2024-01-01', '2024-01-31')) AS d;

```

 递归 CTE 的限制:
   最大递归深度: 500（默认），可通过 max_recursive_iterations 设置（最大 1000）
   性能: 递归 CTE 在分布式环境中效率较低

## 3. CTE 在 DML 中


CTE + INSERT

```sql
WITH new_data AS (SELECT 'alice' AS name, 25 AS age)
INSERT INTO myproject.mydataset.users (username, age) SELECT name, age FROM new_data;

```

CTE + UPDATE

```sql
WITH vip AS (SELECT user_id FROM myproject.mydataset.orders GROUP BY user_id HAVING SUM(amount) > 10000)
UPDATE myproject.mydataset.users SET status = 2 WHERE id IN (SELECT user_id FROM vip);

```

CTE + DELETE

```sql
WITH old AS (SELECT id FROM myproject.mydataset.users WHERE last_login < '2023-01-01')
DELETE FROM myproject.mydataset.users WHERE id IN (SELECT id FROM old);

```

CTE + MERGE

```sql
WITH new_users AS (SELECT * FROM myproject.mydataset.staging)
MERGE INTO myproject.mydataset.users t
USING new_users s ON t.id = s.id
WHEN MATCHED THEN UPDATE SET username = s.username
WHEN NOT MATCHED THEN INSERT ROW;

```

## 4. CTE 的成本优化


 BigQuery 按扫描量计费。CTE 引用多次时:
   (a) BigQuery 可能物化 CTE 结果（优化器决定）
   (b) 或者内联展开（每次引用重新扫描）
 大表的 CTE 被多次引用时，考虑使用临时表:
 CREATE TEMP TABLE tmp AS SELECT ...;
 SELECT ... FROM tmp; SELECT ... FROM tmp;

## 5. 对比与引擎开发者启示

BigQuery CTE 的设计:
(1) 完整的递归 CTE → 但有深度限制（500/1000）
(2) GENERATE_ARRAY / GENERATE_DATE_ARRAY → 序列生成的更好替代
(3) CTE 在所有 DML 中可用 → 包括 MERGE
(4) 成本影响 → CTE 引用次数影响扫描量

对引擎开发者的启示:
GENERATE_ARRAY 类的表函数是递归 CTE 的优秀替代。
CTE 物化策略应由优化器自动决定（BigQuery 的做法）。

