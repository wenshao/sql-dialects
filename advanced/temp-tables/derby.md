# Apache Derby: 临时表与临时存储

> 参考资料:
> - [Derby Documentation - DECLARE GLOBAL TEMPORARY TABLE](https://db.apache.org/derby/docs/10.16/ref/rrefdeclaretemptable.html)


## DECLARE GLOBAL TEMPORARY TABLE


```sql
DECLARE GLOBAL TEMPORARY TABLE temp_users (
    id BIGINT,
    username VARCHAR(100),
    email VARCHAR(200)
) ON COMMIT PRESERVE ROWS
  NOT LOGGED;
```

ON COMMIT 选项：
ON COMMIT DELETE ROWS     事务提交时清空
ON COMMIT PRESERVE ROWS   事务提交时保留

## 使用临时表


## 临时表在 SESSION schema 中

```sql
INSERT INTO SESSION.temp_users
SELECT id, username, email FROM users WHERE status = 1;

SELECT * FROM SESSION.temp_users;
```

## 连接结束时自动删除

## 从定义创建


```sql
DECLARE GLOBAL TEMPORARY TABLE temp_orders (
    user_id BIGINT,
    total DECIMAL(10,2)
) ON COMMIT PRESERVE ROWS NOT LOGGED;

INSERT INTO SESSION.temp_orders
SELECT user_id, SUM(amount) FROM orders GROUP BY user_id;
```

## CTE（10.14+，有限支持）


Derby 对 CTE 的支持有限
基本 WITH 查询：
WITH stats AS (
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT * FROM stats WHERE total > 1000;
注意：Derby 使用 DECLARE GLOBAL TEMPORARY TABLE 语法
注意：临时表通过 SESSION schema 访问
注意：NOT LOGGED 提高性能
注意：连接结束时临时表自动删除
注意：Derby 对 CTE 的支持有限
