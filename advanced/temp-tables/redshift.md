# Amazon Redshift: 临时表与临时存储

> 参考资料:
> - [AWS Documentation - Temporary Tables](https://docs.aws.amazon.com/redshift/latest/dg/r_CREATE_TABLE_NEW.html)
> - [AWS Documentation - WITH Clause](https://docs.aws.amazon.com/redshift/latest/dg/r_WITH_clause.html)


## CREATE TEMPORARY TABLE


```sql
CREATE TEMPORARY TABLE temp_users (
    id BIGINT,
    username VARCHAR(100),
    email VARCHAR(200)
);

CREATE TEMP TABLE temp_orders AS
SELECT user_id, SUM(amount) AS total
FROM orders GROUP BY user_id;
```


在当前会话结束时或事务结束时删除
```sql
CREATE TEMP TABLE temp_session (id INT, val INT);  -- 默认会话级
```


## 临时表与分布键


指定分布键（减少数据重分布）
```sql
CREATE TEMP TABLE temp_data (
    user_id BIGINT DISTKEY,
    amount DECIMAL(10,2)
) SORTKEY (user_id);
```


使用 DISTSTYLE
```sql
CREATE TEMP TABLE temp_small (
    id INT, name VARCHAR(100)
) DISTSTYLE ALL;  -- 小表广播到所有节点
```


## SELECT INTO 创建临时表


```sql
SELECT user_id, SUM(amount) AS total
INTO TEMP TABLE temp_totals
FROM orders
GROUP BY user_id;
```


## CTE


```sql
WITH monthly_stats AS (
    SELECT user_id, DATE_TRUNC('month', order_date) AS month,
           SUM(amount) AS total
    FROM orders GROUP BY user_id, DATE_TRUNC('month', order_date)
)
SELECT u.username, m.month, m.total
FROM users u JOIN monthly_stats m ON u.id = m.user_id
WHERE m.total > 1000;
```


递归 CTE（不支持）
Redshift 不支持递归 CTE

## 临时表 vs 标准表


临时表只在当前会话中可见
临时表在 pg_temp_N schema 中
临时表不需要 VACUUM（会话结束时删除）
临时表可以有分布键和排序键

注意：Redshift 临时表支持分布键和排序键
注意：临时表在会话结束时自动删除
注意：Redshift 不支持递归 CTE
注意：使用 DISTSTYLE ALL 对小型临时表可以避免数据重分布
注意：SELECT INTO TEMP TABLE 是创建临时表的快捷方式
