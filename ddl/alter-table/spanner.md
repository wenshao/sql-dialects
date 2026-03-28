# Spanner: ALTER TABLE

> 参考资料:
> - [Spanner ALTER TABLE](https://cloud.google.com/spanner/docs/reference/standard-sql/data-definition-language#alter_table)
> - [Spanner Schema Updates](https://cloud.google.com/spanner/docs/schema-updates)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## 基本语法

```sql
ALTER TABLE Users ADD COLUMN Phone STRING(20);
ALTER TABLE Users ADD COLUMN IF NOT EXISTS Phone STRING(20);
ALTER TABLE Users ADD COLUMN Status INT64 NOT NULL DEFAULT (0);
ALTER TABLE Users ADD COLUMN UpdatedAt TIMESTAMP DEFAULT (CURRENT_TIMESTAMP());
ALTER TABLE Users ALTER COLUMN Bio STRING(MAX);
ALTER TABLE Users DROP COLUMN Phone;

```

## 语法设计分析（对 SQL 引擎开发者）


### Schema Update 作为长事务

Spanner 的 ALTER TABLE 不是瞬间完成的——它是一个后台 schema update 操作。
大型表的 schema 变更可能需要数分钟到数小时。

实现机制:
  Schema 变更通过 Spanner 的内部 schema version 系统管理。
  变更在所有 Split 上滚动执行，保证全局一致性。
  变更期间读写不受阻塞（新写入按新/旧 schema 写入，后台适配）。

关键限制: 每个数据库最多 1 个活跃 schema update（后续的排队等待）。
这是全球分布式一致性的代价——同时变更多个 schema 可能导致不一致。

**对比:**
  MySQL:      INSTANT/INPLACE（秒级到分钟级）
  PostgreSQL: 大部分即时（ADD COLUMN + DEFAULT 11+）
  TiDB:       F1 协议（分钟级，可并发不同表的 DDL）
  CockroachDB: 异步 schema 变更（分钟级，事务性 DDL）
  OceanBase:  Online DDL（LSM-Tree 友好）

### 列类型修改的严格限制

Spanner 只允许非常有限的列类型修改:
  允许: STRING(100) → STRING(200)（增大长度）
  允许: BYTES(100) → BYTES(MAX)
  不允许: STRING → INT64（不同类型族的转换）
  不允许: STRING(200) → STRING(100)（缩小长度）
类型变更意味着所有数据块需要重写，对全球分布的数据来说代价极高。

## Spanner 特有操作


### 提交时间戳选项

```sql
ALTER TABLE AuditLog ADD COLUMN UpdatedAt TIMESTAMP
    OPTIONS (allow_commit_timestamp = true);
ALTER TABLE Users ALTER COLUMN UpdatedAt SET OPTIONS (allow_commit_timestamp = true);

```

### 行删除策略 (TTL)

```sql
ALTER TABLE Events ADD ROW DELETION POLICY (OLDER_THAN(EventTime, INTERVAL 90 DAY));
ALTER TABLE Events DROP ROW DELETION POLICY;
ALTER TABLE Events REPLACE ROW DELETION POLICY (OLDER_THAN(EventTime, INTERVAL 30 DAY));

```

### INTERLEAVE 删除行为修改

```sql
ALTER TABLE OrderItems SET ON DELETE CASCADE;
ALTER TABLE OrderItems SET ON DELETE NO ACTION;

```

### 约束管理

```sql
ALTER TABLE Orders ADD CONSTRAINT fk_user
    FOREIGN KEY (UserId) REFERENCES Users (UserId);
ALTER TABLE Orders DROP CONSTRAINT fk_user;
ALTER TABLE Users ADD CONSTRAINT chk_age CHECK (Age >= 0 AND Age <= 150);

```

### 生成列（Stored）

```sql
ALTER TABLE Products ADD COLUMN TotalPrice NUMERIC
    AS (Price * Quantity) STORED;

```

### 列选项

```sql
ALTER TABLE Users ALTER COLUMN Email SET OPTIONS (allow_commit_timestamp = false);

```

### NOT NULL 修改

```sql
ALTER TABLE Users ALTER COLUMN Phone STRING(20) NOT NULL;  -- 添加 NOT NULL
ALTER TABLE Users ALTER COLUMN Phone STRING(20);           -- 移除 NOT NULL

```

## 索引管理（独立语句）

```sql
CREATE INDEX idx_users_email ON Users (Email);
CREATE UNIQUE INDEX idx_users_email_uniq ON Users (Email);
CREATE NULL_FILTERED INDEX idx_users_phone ON Users (Phone);
CREATE INDEX idx_users_email_full ON Users (Email) STORING (Username, CreatedAt);
CREATE INDEX idx_items_product ON OrderItems (ProductId), INTERLEAVE IN Orders;
DROP INDEX idx_users_email;

```

## 限制与注意事项

不能修改主键（主键决定物理分布，修改需要重建表）
不能 RENAME TABLE 或 RENAME COLUMN
每个数据库同时只能有一个活跃 schema update
不能修改 INTERLEAVE 关系（不能把非交错表变成交错表）
类型变更仅限于增大 STRING/BYTES 长度
添加 NOT NULL 列需要 DEFAULT 值
DDL 不在用户事务中执行（独立的 schema update 操作）

## 横向对比

## 列类型修改灵活度:

   PostgreSQL:  最灵活（支持 USING 表达式自定义转换）
   MySQL:       较灵活（大部分类型转换支持）
   CockroachDB: 中等（支持部分类型转换）
   OceanBase:   中等
   TiDB:        中等（部分类型转换需要重写）
   Spanner:     最严格（只能增大 STRING/BYTES 长度）

## RENAME 支持:

   大多数引擎: 支持 RENAME TABLE / RENAME COLUMN
   Spanner:    不支持（schema 变更的简化设计）

## 并发 DDL:

   Spanner:    同时最多 1 个 schema update（最严格）
   TiDB:       不同表可并发 DDL
   CockroachDB: 不同表可并发 DDL
   MySQL:      同一表串行，不同表可并行
