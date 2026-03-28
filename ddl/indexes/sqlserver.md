# SQL Server: 索引

> 参考资料:
> - [SQL Server - Clustered and Nonclustered Indexes](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/clustered-and-nonclustered-indexes-described)
> - [SQL Server - Columnstore Indexes](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/columnstore-indexes-overview)

## 聚集索引: SQL Server 最核心的存储概念

聚集索引 = 表数据的物理排列顺序。每表有且只有一个。
没有聚集索引的表叫"堆表"(Heap)，数据无序存储。
```sql
CREATE CLUSTERED INDEX ix_id ON users (id);
```

主键默认创建聚集索引（可以覆盖为 NONCLUSTERED）
聚集索引键被所有非聚集索引的叶节点引用（类似 InnoDB 二级索引存主键值）

设计分析（对引擎开发者）:
  聚集索引的选择直接决定了:
  (1) 范围扫描效率（连续的聚集键 → 连续的磁盘 I/O）
  (2) 非聚集索引的大小（聚集键越宽，所有非聚集索引越大）
  (3) 插入性能（单调递增的键避免页分裂，UUID 键导致随机插入）

  最佳实践: 聚集索引键应该是 窄、唯一、递增、不变的（NUSI 原则）
  IDENTITY 列几乎完美满足所有条件。

横向对比:
  MySQL InnoDB: 主键 = 聚集索引（无法分离），无主键时用第一个 UNIQUE NOT NULL 索引
  PostgreSQL:   纯堆表 + 独立索引，无聚集索引概念（CLUSTER 命令是一次性排序）
  Oracle:       默认堆表，IOT 需显式 ORGANIZATION INDEX

对引擎开发者的启示:
  SQL Server 允许聚集索引不在主键上——这比 InnoDB 的强绑定灵活得多。
  但大部分用户从不利用这个能力，默认行为（PK=聚集）通常是对的。
  设计引擎时应考虑: 默认聚集在 PK，但允许用户覆盖。

## 非聚集索引

```sql
CREATE NONCLUSTERED INDEX ix_age ON users (age);
CREATE UNIQUE INDEX uk_email ON users (email);
CREATE INDEX ix_city_age ON users (city, age);
CREATE INDEX ix_age_desc ON users (age DESC);
```

## 包含列 (INCLUDE): SQL Server 2005+ 首创

INCLUDE 列存储在叶节点，不参与索引排序，但实现覆盖查询
```sql
CREATE INDEX ix_username ON users (username) INCLUDE (email, age);
```

设计分析:
  查询 SELECT email, age FROM users WHERE username = 'alice' 完全由索引满足，
  不需要回表（Key Lookup），这叫"覆盖索引"。
  INCLUDE 列不计入索引键的大小限制（900 字节/1700 字节），只受页大小限制。

横向对比:
  PostgreSQL: 11+ 支持 INCLUDE（比 SQL Server 晚了 12 年）
  MySQL:      不支持 INCLUDE（覆盖索引需要把列都放在索引键中）
  Oracle:     不支持 INCLUDE（直到 21c 的 INCLUDE 列）

对引擎开发者的启示:
  INCLUDE 是索引设计的重大创新——分离"查找键"和"覆盖列"。
  使索引既高效（窄键用于 B-tree 查找）又覆盖（宽叶节点避免回表）。
  每个现代引擎都应该支持这个特性。

## 过滤索引 (Filtered Index): SQL Server 2008+

只索引满足条件的行（类似 PostgreSQL 的 Partial Index）
```sql
CREATE INDEX ix_active ON users (username) WHERE status = 1;
```

典型场景: 大表中只有少量"活跃"行需要快速查找
优点: 索引更小 → 内存占用少 → 维护开销低
限制: WHERE 只支持简单谓词（不能用函数、不能用 OR、不能引用其他表）

对引擎开发者的启示:
  过滤索引的匹配需要查询优化器能够推导 WHERE 条件的包含关系。
  例如: 查询 WHERE status = 1 AND city = 'Beijing' 应该匹配 WHERE status = 1 的过滤索引。

## 列存储索引 (Columnstore): SQL Server 2012+ 核心特性

非聚集列存储索引（行存 + 部分列存）
```sql
CREATE COLUMNSTORE INDEX ix_cs ON orders (order_date, amount, quantity);
```

聚集列存储索引（整表列存，2014+）
```sql
CREATE CLUSTERED COLUMNSTORE INDEX ix_cci ON fact_sales;
```

2016+: 聚集列存储 + 非聚集行存索引（可共存）
这是 SQL Server 的 HTAP 方案: 分析查询走列存，点查走行存
```sql
CREATE CLUSTERED COLUMNSTORE INDEX ix_cci ON orders;
CREATE NONCLUSTERED INDEX ix_order_id ON orders (order_id);
```

设计分析（对引擎开发者）:
  列存储的核心优势: 压缩比高（10x）、向量化执行、批处理模式
  SQL Server 的实现:
  (1) 数据按约 100 万行分组为 Rowgroup
  (2) 每列独立压缩存储
  (3) 支持 Deltastore（行存缓冲区，批量插入后转为列存）
  (4) 2016+ 支持 Batch Mode on Rowstore（列存执行引擎处理行存数据）

横向对比:
  PostgreSQL: 无原生列存（需要 cstore_fdw 或 Citus Columnar 扩展）
  MySQL:      无原生列存（HeatWave 是 Oracle 云服务加速器）
  Oracle:     12c+ 有 In-Memory Column Store（纯内存列存，非持久化）
  ClickHouse: 纯列存引擎（MergeTree），列存是其唯一存储方式

对引擎开发者的启示:
  行列混合存储（HTAP）是现代数据库的重要方向。
  SQL Server 通过列存索引 + 行存索引共存实现，不需要数据复制。
  TiDB 通过 TiKV(行存) + TiFlash(列存) 实现类似效果但数据有副本。

## 在线索引操作（Enterprise 版）

```sql
CREATE INDEX ix_age ON users (age) WITH (ONLINE = ON);
```

填充因子（控制叶页面预留空间）
```sql
CREATE INDEX ix_age ON users (age) WITH (FILLFACTOR = 80);
```

2019+: 可恢复索引创建（中断后可继续）
```sql
CREATE INDEX ix_age ON users (age) WITH (ONLINE = ON, RESUMABLE = ON);
ALTER INDEX ix_age ON users RESUME;  -- 从中断处继续
ALTER INDEX ix_age ON users ABORT;   -- 放弃
```

索引重建
```sql
ALTER INDEX ix_age ON users REBUILD;
ALTER INDEX ix_age ON users REBUILD WITH (ONLINE = ON);
ALTER INDEX ALL ON users REBUILD;
```

禁用索引（保留定义，不再维护——任何引用都会报错）
```sql
ALTER INDEX ix_age ON users DISABLE;
ALTER INDEX ix_age ON users REBUILD;  -- 唯一的"启用"方式
```

删除索引（注意语法: DROP INDEX 索引名 ON 表名）
```sql
DROP INDEX ix_age ON users;
DROP INDEX IF EXISTS ix_age ON users;  -- 2016+
```

## 锁升级与索引

SQL Server 的锁升级: 行锁 → 页锁 → 表锁
当单个事务持有超过约 5000 个行锁时，自动升级为表锁
这会严重影响并发

控制锁升级行为
```sql
ALTER TABLE orders SET (LOCK_ESCALATION = TABLE);    -- 默认
ALTER TABLE orders SET (LOCK_ESCALATION = DISABLE);  -- 禁用
ALTER TABLE orders SET (LOCK_ESCALATION = AUTO);     -- 分区表逐分区升级

-- 对引擎开发者的启示:
--   锁升级是 SQL Server 的独特机制（其他数据库不这么做）。
--   PostgreSQL/MySQL 不会将行锁升级为表锁。
--   锁升级的目的是减少锁管理器的内存开销，但副作用是并发性降低。
```

## 查看索引

```sql
EXEC sp_helpindex 'users';
SELECT name, type_desc, is_unique, is_primary_key, fill_factor
FROM sys.indexes WHERE object_id = OBJECT_ID('users');
```

索引使用统计（DBA 核心 DMV）
```sql
SELECT OBJECT_NAME(s.object_id) AS table_name,
       i.name AS index_name,
       s.user_seeks, s.user_scans, s.user_lookups, s.user_updates
FROM sys.dm_db_index_usage_stats s
JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE s.database_id = DB_ID();
```
