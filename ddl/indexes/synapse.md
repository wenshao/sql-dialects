# Azure Synapse: 索引

> 参考资料:
> - [Synapse SQL Features](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)
> - [Synapse T-SQL Differences](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql/overview-features)


Synapse 专用 SQL 池支持列存储索引和行存储索引
默认使用聚集列存储索引（Clustered Columnstore Index, CCI）

## 聚集列存储索引（CCI）—— 默认，推荐用于分析查询


创建表时默认使用 CCI
```sql
CREATE TABLE orders (
    id         BIGINT IDENTITY(1, 1),
    user_id    BIGINT,
    amount     DECIMAL(10, 2),
    order_date DATE
)
WITH (
    DISTRIBUTION = HASH(user_id),
    CLUSTERED COLUMNSTORE INDEX               -- 默认值，可省略
);
```


有序 CCI（Ordered Clustered Columnstore Index）
数据按指定列排序存储，改善段消除效果
```sql
CREATE TABLE orders_ordered (
    id         BIGINT IDENTITY(1, 1),
    user_id    BIGINT,
    amount     DECIMAL(10, 2),
    order_date DATE
)
WITH (
    DISTRIBUTION = HASH(user_id),
    CLUSTERED COLUMNSTORE INDEX ORDER (order_date)
);
```


## 非聚集列存储索引（NCCI）

在行存储表上添加列存储索引实现混合查询

```sql
CREATE TABLE hybrid_table (
    id         INT NOT NULL,
    name       NVARCHAR(100),
    amount     DECIMAL(10, 2),
    created_at DATETIME2
)
WITH (
    DISTRIBUTION = HASH(id),
    CLUSTERED INDEX (id)                     -- 行存储聚集索引
);
```


添加非聚集列存储索引
```sql
CREATE NONCLUSTERED COLUMNSTORE INDEX ncci_hybrid
ON hybrid_table (name, amount, created_at);
```


## 行存储聚集索引（Clustered Index）

适合点查和频繁更新的表

```sql
CREATE TABLE lookup_table (
    id         INT NOT NULL,
    value      NVARCHAR(200)
)
WITH (
    DISTRIBUTION = REPLICATE,
    CLUSTERED INDEX (id)
);
```


## 非聚集索引（Nonclustered Index）

在行存储表上创建

```sql
CREATE NONCLUSTERED INDEX ix_lookup_value
ON lookup_table (value);
```


包含列
```sql
CREATE NONCLUSTERED INDEX ix_orders_date
ON orders_rowstore (order_date)
INCLUDE (amount, user_id);
```


## 堆表（HEAP）—— 无索引

适合暂存区和快速加载场景

```sql
CREATE TABLE staging_data (
    id         BIGINT,
    data       NVARCHAR(MAX)
)
WITH (
    DISTRIBUTION = ROUND_ROBIN,
    HEAP
);
```


## 索引维护


重建 CCI（改善段质量）
```sql
ALTER INDEX ALL ON orders REBUILD;
```


重组织 CCI（合并小行组）
```sql
ALTER INDEX ALL ON orders REORGANIZE;
```


删除索引
```sql
DROP INDEX ix_lookup_value ON lookup_table;
DROP INDEX ncci_hybrid ON hybrid_table;
```


## 分布（DISTRIBUTION）—— 优化 JOIN 的关键


HASH 分布（相同值在同一分布上）
```sql
CREATE TABLE users (id BIGINT, name NVARCHAR(100))
WITH (DISTRIBUTION = HASH(id));

CREATE TABLE orders (id BIGINT, user_id BIGINT)
WITH (DISTRIBUTION = HASH(user_id));
-- users.id 和 orders.user_id 分布对齐 → JOIN 无需数据移动
```


REPLICATE 分布（每个节点一份完整拷贝，小维度表）
```sql
CREATE TABLE countries (code CHAR(2), name NVARCHAR(100))
WITH (DISTRIBUTION = REPLICATE);
```


## 统计信息


```sql
CREATE STATISTICS stat_orders_date ON orders (order_date);
CREATE STATISTICS stat_orders_multi ON orders (order_date, user_id)
WITH FULLSCAN;

UPDATE STATISTICS orders;
```


查看统计信息
```sql
DBCC SHOW_STATISTICS ('orders', 'stat_orders_date');
```


## 段消除信息


查看列存储段信息
```sql
SELECT * FROM sys.column_store_segments
WHERE hobt_id IN (SELECT hobt_id FROM sys.partitions WHERE object_id = OBJECT_ID('orders'));
```


查看表分布信息
```sql
SELECT * FROM sys.dm_pdw_nodes_db_partition_stats
WHERE object_id = OBJECT_ID('orders');
```


注意：CCI 是默认且最推荐的索引类型（列式压缩 + 段消除）
注意：有序 CCI 显著改善特定列的过滤性能
注意：堆表适合 ETL 暂存（加载最快）
注意：行存储索引适合点查和高频更新场景
注意：60 个固定分布，HASH 分布键的选择至关重要
注意：Serverless 池不支持创建索引（只读查询外部数据）
