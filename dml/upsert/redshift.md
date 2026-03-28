# Redshift: UPSERT

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


Redshift 没有原生 UPSERT / ON CONFLICT 语法
使用 MERGE（2023+ 支持）或传统的 DELETE + INSERT / Staging 模式

## 方式一: MERGE（Redshift 2023+ 支持）


```sql
MERGE INTO users AS t
USING (SELECT 'alice' AS username, 'alice@example.com' AS email, 25 AS age) AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```


MERGE 批量操作
```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED THEN
    UPDATE SET email = s.email, age = s.age, updated_at = GETDATE()
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```


MERGE 带条件
```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN MATCHED AND s.age > t.age THEN
    UPDATE SET age = s.age
WHEN MATCHED AND s.status = 'delete' THEN
    DELETE
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```


仅插入不存在的行
```sql
MERGE INTO users AS t
USING staging_users AS s
ON t.username = s.username
WHEN NOT MATCHED THEN
    INSERT (username, email, age) VALUES (s.username, s.email, s.age);
```


## 方式二: DELETE + INSERT（传统方式，所有版本）


```sql
BEGIN;
-- 先删除匹配行
DELETE FROM users
USING staging_users s
WHERE users.username = s.username;
-- 再插入所有暂存行
INSERT INTO users (username, email, age)
SELECT username, email, age FROM staging_users;
COMMIT;
```


## 方式三: Staging Table 模式（推荐的 ETL 模式）


1. 创建暂存表
```sql
CREATE TEMP TABLE staging (LIKE users);
```


2. 用 COPY 加载数据到暂存表
```sql
COPY staging FROM 's3://my-bucket/data/updates.csv'
IAM_ROLE 'arn:aws:iam::123456789012:role/MyRedshiftRole'
CSV IGNOREHEADER 1;
```


3. 在事务中执行 DELETE + INSERT
```sql
BEGIN;
DELETE FROM users
USING staging
WHERE users.id = staging.id;

INSERT INTO users
SELECT * FROM staging;
COMMIT;
```


4. 清理暂存表
```sql
DROP TABLE staging;
```


## 方式四: CTAS 替换（全量刷新场景）


```sql
CREATE TABLE users_new AS
SELECT COALESCE(s.username, u.username) AS username,
       COALESCE(s.email, u.email) AS email,
       COALESCE(s.age, u.age) AS age
FROM users u
FULL OUTER JOIN staging_users s ON u.username = s.username;

DROP TABLE users;
ALTER TABLE users_new RENAME TO users;
```


注意：MERGE 是 Redshift 2023+ 的新功能，推荐使用
注意：早期版本使用 DELETE + INSERT 或 Staging Table 模式
注意：Staging Table 模式适合大批量数据加载
注意：DELETE + INSERT 需要在事务中执行以保证原子性
注意：MERGE 比 DELETE + INSERT 更高效（只做一次表扫描）
