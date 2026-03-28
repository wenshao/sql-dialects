# Azure Synapse: ALTER TABLE

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


添加列
```sql
ALTER TABLE users ADD phone NVARCHAR(20);
ALTER TABLE users ADD status INT DEFAULT 1;
-- 注意：多列添加需要分开执行
```


删除列
```sql
ALTER TABLE users DROP COLUMN phone;
-- 注意：不支持 IF EXISTS
```


修改列类型（非常有限）
Synapse 专用池不支持直接修改列类型
需要通过 CTAS 重建表

CTAS 重建表（修改列类型的推荐方式）
```sql
CREATE TABLE users_new
WITH (
    DISTRIBUTION = HASH(id),
    CLUSTERED COLUMNSTORE INDEX
)
AS
SELECT
    id,
    username,
    CAST(email AS NVARCHAR(500)) AS email,   -- 扩展列类型
    age,
    created_at
FROM users;

RENAME OBJECT users TO users_old;
RENAME OBJECT users_new TO users;
DROP TABLE users_old;
```


重命名表
```sql
RENAME OBJECT users TO members;
RENAME OBJECT dbo.users TO members;
```


重命名列（不支持）
需要通过 CTAS 重建表：
CREATE TABLE t_new WITH (...) AS SELECT col1 AS new_name FROM t;

修改分布（通过 CTAS）
```sql
CREATE TABLE orders_redistributed
WITH (
    DISTRIBUTION = HASH(user_id),           -- 修改分布键
    CLUSTERED COLUMNSTORE INDEX
)
AS SELECT * FROM orders;

RENAME OBJECT orders TO orders_old;
RENAME OBJECT orders_redistributed TO orders;
```


切换分区
```sql
ALTER TABLE orders SWITCH PARTITION 1 TO orders_archive PARTITION 1;
```


分割分区
```sql
ALTER TABLE orders SPLIT RANGE ('2025-01-01');
```


合并分区
```sql
ALTER TABLE orders MERGE RANGE ('2024-01-01');
```


添加约束（仅 NOT NULL 强制执行）
需要通过 CTAS 重建表来添加或移除 NOT NULL

修改表属性（通过 CTAS 重建）
例如更改索引类型：
```sql
CREATE TABLE users_heap
WITH (
    DISTRIBUTION = HASH(id),
    HEAP                                    -- 改为堆表
)
AS SELECT * FROM users;
```


修改统计信息
```sql
CREATE STATISTICS stat_users_age ON users (age);
UPDATE STATISTICS users;
```


注意：Synapse 专用池的 ALTER TABLE 功能非常有限
注意：大多数表结构修改需要通过 CTAS + RENAME 模式
注意：不支持 ALTER COLUMN（修改类型、NULL 约束等）
注意：不支持 RENAME COLUMN
注意：分区操作是 ALTER TABLE 的主要用途之一
注意：IDENTITY 列在 CTAS 重建后可能不保留原始值
注意：Serverless 池有不同的限制（只读外部表）
