# Redshift: CTE（公共表表达式）

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


基本 CTE
```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT * FROM active_users WHERE age > 25;
```


多个 CTE
```sql
WITH
active_users AS (
    SELECT * FROM users WHERE status = 1
),
user_orders AS (
    SELECT user_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT u.username, o.cnt, o.total
FROM active_users u
JOIN user_orders o ON u.id = o.user_id;
```


CTE 引用前面的 CTE
```sql
WITH
base AS (SELECT * FROM users WHERE status = 1),
enriched AS (
    SELECT b.*, COUNT(o.id) AS order_count
    FROM base b LEFT JOIN orders o ON b.id = o.user_id
    GROUP BY b.id, b.username, b.status, b.age, b.city
)
SELECT * FROM enriched WHERE order_count > 5;
```


递归 CTE
```sql
WITH RECURSIVE nums AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM nums WHERE n < 10
)
SELECT n FROM nums;
```


递归：层级结构
```sql
WITH RECURSIVE org_tree AS (
    SELECT id, username, manager_id, 0 AS level,
           username AS path
    FROM users WHERE manager_id IS NULL
    UNION ALL
    SELECT u.id, u.username, u.manager_id, t.level + 1,
           t.path || ' > ' || u.username
    FROM users u JOIN org_tree t ON u.manager_id = t.id
)
SELECT * FROM org_tree;
```


CTE + DML（CREATE TABLE AS）
```sql
CREATE TABLE users_archive AS
WITH inactive AS (
    SELECT * FROM users WHERE last_login < '2023-01-01'
)
SELECT * FROM inactive;
```


CTE + INSERT
```sql
WITH new_data AS (
    SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age
)
INSERT INTO users (username, email, age)
SELECT username, email, age FROM new_data;
```


CTE + DELETE
```sql
WITH inactive AS (
    SELECT id FROM users WHERE last_login < '2023-01-01'
)
DELETE FROM users WHERE id IN (SELECT id FROM inactive);
```


CTE + UPDATE
```sql
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2
FROM vip WHERE users.id = vip.user_id;
```


CTE + SUPER 类型查询
```sql
WITH parsed_events AS (
    SELECT id,
           JSON_EXTRACT_PATH_TEXT(data, 'type') AS event_type,
           JSON_EXTRACT_PATH_TEXT(data, 'user') AS user_name
    FROM events
)
SELECT event_type, COUNT(*) AS cnt
FROM parsed_events
GROUP BY event_type;
```


注意：Redshift 支持递归 CTE（RECURSIVE 关键字必须）
注意：递归 CTE 有默认最大递归次数限制
注意：CTE 是内联的（每次引用都会重新计算）
注意：不支持 MATERIALIZED / NOT MATERIALIZED 提示
注意：CTE 可以与 INSERT / UPDATE / DELETE / CREATE TABLE AS 一起使用
