# Vertica: 临时表与临时存储

> 参考资料:
> - [Vertica Documentation - CREATE TABLE (Temporary)](https://www.vertica.com/docs/latest/HTML/Content/Authoring/SQLReferenceManual/Statements/CREATETABLE.htm)


## 本地临时表


```sql
CREATE LOCAL TEMPORARY TABLE temp_users (
    id INT, username VARCHAR(100), email VARCHAR(200)
) ON COMMIT PRESERVE ROWS;
```


从查询创建
```sql
CREATE LOCAL TEMP TABLE temp_stats ON COMMIT PRESERVE ROWS AS
SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id;
```


ON COMMIT 选项
```sql
CREATE LOCAL TEMP TABLE temp_tx (id INT, val INT)
ON COMMIT DELETE ROWS;
```


## 全局临时表


```sql
CREATE GLOBAL TEMPORARY TABLE gtt_results (
    id INT, value NUMERIC
) ON COMMIT PRESERVE ROWS;
```


## 使用和删除


```sql
INSERT INTO temp_users SELECT id, username, email FROM users WHERE status = 1;
SELECT * FROM temp_users;
```


临时表自动包含在 v_temp_schema 中
```sql
DROP TABLE IF EXISTS temp_users;
```


## CTE


```sql
WITH stats AS (
    SELECT user_id, SUM(amount) AS total FROM orders GROUP BY user_id
)
SELECT u.username, s.total FROM users u JOIN stats s ON u.id = s.user_id;
```


注意：Vertica 支持 LOCAL TEMPORARY 和 GLOBAL TEMPORARY
注意：临时表存在于 v_temp_schema 中
注意：Vertica 列存储架构下，临时表也是列式存储
注意：ON COMMIT 控制事务结束时的数据行为
