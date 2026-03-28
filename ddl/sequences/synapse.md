# Azure Synapse Analytics: Sequences & Auto-Increment

> 参考资料:
> - [Microsoft Documentation - IDENTITY (Synapse)](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-tables-identity)
> - [Microsoft Documentation - CREATE SEQUENCE (Synapse)](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-sequence-transact-sql)
> - [Microsoft Documentation - Surrogate Keys](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-tables-overview)


## IDENTITY（Dedicated SQL Pool）

```sql
CREATE TABLE users (
    id       BIGINT IDENTITY(1, 1) NOT NULL,
    username NVARCHAR(64) NOT NULL,
    email    NVARCHAR(255) NOT NULL
)
WITH (
    DISTRIBUTION = HASH(id),
    CLUSTERED COLUMNSTORE INDEX
);
```


IDENTITY 在 Synapse 中的特殊行为：
1. 值不保证连续（MPP 架构，每个分布独立分配）
2. 值不保证唯一（需要自行确保）
3. 重启后可能有间隙

获取 IDENTITY 值
```sql
SELECT SCOPE_IDENTITY();
SELECT @@IDENTITY;
```


## SEQUENCE（Synapse 部分支持）

Serverless SQL Pool 不支持 SEQUENCE
Dedicated SQL Pool 支持:
```sql
CREATE SEQUENCE user_id_seq
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    CACHE 50;

SELECT NEXT VALUE FOR user_id_seq;
```


## ROW_NUMBER() 生成代理键

Synapse 推荐的方式
```sql
CREATE TABLE users_with_key
WITH (DISTRIBUTION = ROUND_ROBIN)
AS
SELECT
    ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS surrogate_key,
    username,
    email,
    created_at
FROM staging_users;
```


## UUID 生成

```sql
SELECT NEWID();

CREATE TABLE sessions (
    id         UNIQUEIDENTIFIER DEFAULT NEWID(),
    user_id    BIGINT,
    created_at DATETIME2 DEFAULT SYSDATETIME()
);
```


## 序列 vs 自增 权衡

1. IDENTITY：简单但在 MPP 中不保证唯一/连续
2. ROW_NUMBER()（推荐代理键）：确定性的序号
3. SEQUENCE：Dedicated Pool 支持，更可控
4. NEWID()：全局唯一
5. 数据仓库场景建议使用 ROW_NUMBER() 生成代理键

限制：
IDENTITY 在分布式架构下不保证唯一
Serverless Pool 不支持 SEQUENCE
不支持 SERIAL / BIGSERIAL
IDENTITY 不能与 CTAS 一起使用
