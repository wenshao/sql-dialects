# Azure Synapse Analytics: 缓慢变化维度 (Slowly Changing Dimension)

> 参考资料:
> - [Azure Synapse Analytics - Dedicated SQL Pool T-SQL](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Azure Synapse - CTAS (CREATE TABLE AS SELECT)](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-as-select-azure-synapse-analytics)
> - [Azure Synapse - MERGE limitations](https://learn.microsoft.com/en-us/sql/t-sql/statements/merge-transact-sql#limitations-and-restrictions)
> - [Kimball Group - SCD Types](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/)


## 1. 维度表结构


Dedicated SQL Pool 表定义（指定分布方式）
```sql
CREATE TABLE dim_customer (
    customer_key   INT IDENTITY(1,1) PRIMARY KEY,
    customer_id    VARCHAR(20) NOT NULL,
    name           VARCHAR(100),
    city           VARCHAR(100),
    tier           VARCHAR(20),
    effective_date DATE NOT NULL DEFAULT CONVERT(DATE, GETDATE()),
    expiry_date    DATE NOT NULL DEFAULT '9999-12-31',
    is_current     BIT NOT NULL DEFAULT 1,
    updated_at     DATETIME2 DEFAULT SYSDATETIME()
)
WITH (DISTRIBUTION = HASH(customer_id), CLUSTERED COLUMNSTORE INDEX);
```


源数据临时表
```sql
CREATE TABLE stg_customer (
    customer_id VARCHAR(20),
    name        VARCHAR(100),
    city        VARCHAR(100),
    tier        VARCHAR(20)
)
WITH (DISTRIBUTION = ROUND_ROBIN, HEAP);
```


## 2. 插入样本数据


```sql
INSERT INTO stg_customer (customer_id, name, city, tier) VALUES
    ('C001', 'Alice', 'Shanghai', 'Gold'),
    ('C002', 'Bob', 'Beijing', 'Silver'),
    ('C003', 'Charlie', 'Shenzhen', 'Bronze');
```


## 3. SCD Type 1: CTAS 模式（Synapse 推荐）


Dedicated SQL Pool 推荐使用 CTAS 而非 MERGE
CTAS 利用了 MPP 架构的并行处理能力
```sql
CREATE TABLE dim_customer_new
WITH (DISTRIBUTION = HASH(customer_id), CLUSTERED COLUMNSTORE INDEX)
AS
SELECT COALESCE(s.customer_id, d.customer_id) AS customer_id,
       COALESCE(s.name, d.name)               AS name,
       COALESCE(s.city, d.city)               AS city,
       COALESCE(s.tier, d.tier)               AS tier
FROM   dim_customer d
FULL   OUTER JOIN stg_customer s ON d.customer_id = s.customer_id;
```


原子替换（在事务中执行）
```sql
BEGIN TRANSACTION;
RENAME OBJECT dim_customer  TO dim_customer_old;
RENAME OBJECT dim_customer_new TO dim_customer;
COMMIT TRANSACTION;
DROP TABLE dim_customer_old;
```


Serverless SQL Pool 可以使用标准 T-SQL MERGE
```sql
MERGE INTO dim_customer AS t
USING stg_customer AS s
ON t.customer_id = s.customer_id AND t.is_current = 1
WHEN MATCHED AND (t.name <> s.name OR t.city <> s.city OR t.tier <> s.tier)
    THEN UPDATE SET name = s.name, city = s.city, tier = s.tier, updated_at = SYSDATETIME()
WHEN NOT MATCHED
    THEN INSERT (customer_id, name, city, tier)
         VALUES (s.customer_id, s.name, s.city, s.tier);
```


## 4. SCD Type 2: CTAS 模式（保留历史版本）


步骤 1: 标记已变化的记录为过期
```sql
UPDATE dim_customer
SET    expiry_date = DATEADD(DAY, -1, CONVERT(DATE, GETDATE())),
       is_current  = 0
WHERE  is_current = 1
  AND  customer_id IN (
    SELECT s.customer_id FROM stg_customer s
    JOIN   dim_customer d ON s.customer_id = d.customer_id
    WHERE  d.is_current = 1
      AND  (s.name <> d.name OR s.city <> d.city OR s.tier <> d.tier)
);
```


步骤 2: 插入新版本（变化的 + 新增的）
```sql
INSERT INTO dim_customer (customer_id, name, city, tier, effective_date, expiry_date, is_current)
SELECT s.customer_id, s.name, s.city, s.tier,
       CONVERT(DATE, GETDATE()), '9999-12-31', 1
FROM   stg_customer s
WHERE  EXISTS (
    SELECT 1 FROM dim_customer d
    WHERE  d.customer_id = s.customer_id AND d.is_current = 0
      AND  d.expiry_date = DATEADD(DAY, -1, CONVERT(DATE, GETDATE()))
)
   OR NOT EXISTS (
    SELECT 1 FROM dim_customer d WHERE d.customer_id = s.customer_id
);
```


## 5. 验证查询


查看当前活跃维度记录
```sql
SELECT customer_key, customer_id, name, city, tier, effective_date, is_current
FROM   dim_customer
WHERE  is_current = 1
ORDER  BY customer_id;
```


查看某个客户的历史版本
```sql
SELECT customer_key, customer_id, name, city, tier, effective_date, expiry_date
FROM   dim_customer
WHERE  customer_id = 'C001'
ORDER  BY effective_date;
```


## 6. Synapse 注意事项与最佳实践


1. Dedicated SQL Pool 的 MERGE 有限制:
- 不支持匹配时 DELETE
- 源表不能有重复键
- 推荐 CTAS 模式以获得最佳性能
2. CTAS 利用了 Synapse 的 MPP 并行架构，适合大规模维度表
3. 选择 HASH(customer_id) 分布策略可避免数据倾斜
4. CLUSTERED COLUMNSTORE INDEX 提供高压缩比和查询性能
5. 使用 RENAME OBJECT 实现原子表切换，避免长时间锁表
6. Serverless SQL Pool 支持标准 T-SQL MERGE，但只支持查询不能修改数据
