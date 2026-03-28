# Apache Impala: CTE（公共表表达式）

> 参考资料:
> - [Impala SQL Reference](https://impala.apache.org/docs/build/html/topics/impala_langref.html)
> - [Impala Built-in Functions](https://impala.apache.org/docs/build/html/topics/impala_functions.html)


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


CTE + 聚合
```sql
WITH monthly_sales AS (
    SELECT YEAR(order_date) AS yr, MONTH(order_date) AS mn,
           SUM(amount) AS total
    FROM orders
    GROUP BY YEAR(order_date), MONTH(order_date)
)
SELECT yr, mn, total,
    total - LAG(total) OVER (ORDER BY yr, mn) AS growth
FROM monthly_sales;
```


CTE + JOIN
```sql
WITH vip_users AS (
    SELECT user_id, SUM(amount) AS total
    FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
SELECT u.username, v.total
FROM users u JOIN vip_users v ON u.id = v.user_id;
```


CTE 多次引用
```sql
WITH user_stats AS (
    SELECT user_id, COUNT(*) AS order_count, SUM(amount) AS total
    FROM orders GROUP BY user_id
)
SELECT
    (SELECT COUNT(*) FROM user_stats WHERE order_count > 10) AS frequent_buyers,
    (SELECT COUNT(*) FROM user_stats WHERE total > 10000) AS high_value_buyers;
```


CTE + INSERT（部分版本支持）
INSERT INTO users_archive
WITH inactive AS (
SELECT * FROM users WHERE last_login < '2023-01-01'
)
SELECT * FROM inactive;

CTE + UPSERT（Kudu 表）
UPSERT INTO users_kudu
WITH updated AS (
SELECT id, username, email, age FROM staging_users
)
SELECT * FROM updated;

注意：Impala 支持 CTE（WITH 子句）
注意：不支持递归 CTE（WITH RECURSIVE）
注意：CTE 不能与 INSERT / UPDATE / DELETE 结合（部分版本限制）
注意：CTE 默认内联展开
