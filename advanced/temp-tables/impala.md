# Apache Impala: 临时表与临时存储

> 参考资料:
> - [Impala Documentation - CREATE TABLE](https://impala.apache.org/docs/build/html/topics/impala_create_table.html)


Impala 不支持 CREATE TEMPORARY TABLE
使用 CTE、内部表或外部表作为替代

## CTE（推荐方式）


```sql
WITH active_users AS (
    SELECT * FROM users WHERE status = 1
)
SELECT u.username, COUNT(o.id) AS order_count
FROM active_users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username;
```


## 创建临时表替代（普通内部表）


```sql
CREATE TABLE staging.temp_results
STORED AS PARQUET AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;
```


使用后删除
```sql
DROP TABLE staging.temp_results;
```


## INVALIDATE METADATA


如果外部修改了临时表数据，需要刷新元数据
```sql
INVALIDATE METADATA staging.temp_results;
REFRESH staging.temp_results;
```


注意：Impala 不支持临时表
注意：CTE 是最常用的临时数据组织方式
注意：可以使用普通内部表作为 Staging 表
注意：Impala 共享 Hive Metastore，表对所有会话可见
