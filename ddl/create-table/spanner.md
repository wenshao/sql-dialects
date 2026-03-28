# Spanner: CREATE TABLE

> 参考资料:
> - [Spanner DDL Reference](https://cloud.google.com/spanner/docs/reference/standard-sql/data-definition-language)
> - [Spanner Schema Design Best Practices](https://cloud.google.com/spanner/docs/schema-design)
> - [Spanner - TrueTime and External Consistency](https://cloud.google.com/spanner/docs/true-time-external-consistency)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## 基本语法

```sql
CREATE TABLE Users (
    UserId     INT64 NOT NULL,
    Username   STRING(100) NOT NULL,
    Email      STRING(255) NOT NULL,
    Age        INT64,
    Balance    NUMERIC,
    Bio        STRING(MAX),
    CreatedAt  TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
    UpdatedAt  TIMESTAMP
) PRIMARY KEY (UserId);

```

## 语法设计分析（对 SQL 引擎开发者）


### PRIMARY KEY 在表级定义: Spanner 最显著的语法差异

其他所有 SQL 引擎都允许在列定义中写 PRIMARY KEY，
Spanner 强制在表定义末尾单独声明: ) PRIMARY KEY (col1, col2);

**设计理由:**
  Spanner 的主键决定数据的物理分布（类似 Bigtable 的 row key）。
  复合主键的列顺序决定了数据排列和 Split 边界。
  在表级显式声明，强调主键设计的重要性（不应是事后想法）。

**对比:**
  MySQL/PostgreSQL/SQL Server: PRIMARY KEY 可在列级或表级声明
  CockroachDB: 可在列级声明（PostgreSQL 兼容），但主键同样决定物理布局
  OceanBase:   可在列级或表级声明（MySQL/Oracle 模式兼容）

**对引擎开发者的启示:**
  如果主键决定物理布局（聚集索引），在语法上强调它是一个好的设计选择。
  但这会降低其他 SQL 方言的迁移兼容性。

### 无自增: 分布式引擎的设计哲学

Spanner 不支持 AUTO_INCREMENT / SERIAL / IDENTITY — 这是刻意的设计。

理由: 单调递增的主键导致所有写入路由到同一个 Split（热点），
      在全球分布的系统中，这是不可接受的性能瓶颈。

替代方案 1: UUID
```sql
CREATE TABLE Products (
    ProductId  STRING(36) NOT NULL DEFAULT (GENERATE_UUID()),
    Name       STRING(255) NOT NULL,
    Price      NUMERIC,
    Category   STRING(50)
) PRIMARY KEY (ProductId);

```

替代方案 2: Bit-reversed Sequence（2023+）
序列值的位反转确保连续值在键空间中均匀分布。
例: 1→huge_number, 2→another_huge_number（反转后不相邻）
```sql
CREATE SEQUENCE OrderSeq OPTIONS (sequence_kind = 'bit_reversed_positive');
CREATE TABLE Orders (
    OrderId   INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE OrderSeq)),
    UserId    INT64 NOT NULL,
    Amount    NUMERIC,
    OrderDate DATE NOT NULL
) PRIMARY KEY (OrderId);

```

**对比:** 其他引擎的自增替代:
  TiDB:        AUTO_RANDOM（高位随机化，依然看起来像整数ID）
  CockroachDB: unique_rowid()（时间戳+节点ID，64位整数）
  OceanBase:   AUTO_INCREMENT（通过分区分散热点）
  Snowflake:   AUTOINCREMENT（不保证连续，但保证递增）

### INTERLEAVE IN PARENT: 物理共置的层次存储

Spanner 最独特且最重要的建表特性，源自 Bigtable 的设计遗产。

原理: 子表的行物理存储在父表行的旁边（按主键前缀共置）。
      父行 Key: /Users/123
      子行 Key: /Users/123/Orders/456（紧挨父行存储）
效果: 查询父行及其所有子行只需要一次磁盘 I/O（而非跨 Split JOIN）。

**限制:**
  子表主键必须以父表主键为前缀
  最多 7 层嵌套
  DELETE 行为由 ON DELETE CASCADE/NO ACTION 控制

```sql
CREATE TABLE OrderItems (
    OrderId   INT64 NOT NULL,
    ItemId    INT64 NOT NULL,
    ProductId STRING(36) NOT NULL,
    Quantity  INT64,
    Price     NUMERIC
) PRIMARY KEY (OrderId, ItemId),
  INTERLEAVE IN PARENT Orders ON DELETE CASCADE;

```

**对比:** 其他引擎的共置机制:
  OceanBase:   TABLEGROUP（表组级共置，粒度更粗）
  CockroachDB: 无显式共置（依赖 Range 自动管理）
  TiDB:        无显式共置（依赖 TiKV Region 调度）
  Cassandra:   Clustering Key（类似概念但不同实现）

## 数据类型设计

Spanner 的类型系统精简且与其他引擎差异显著:
  INT64:      唯一的整数类型（无 INT/SMALLINT/BIGINT 区分）
  FLOAT32:    单精度浮点
  FLOAT64:    双精度浮点
  NUMERIC:    定点数（29位整数 + 9位小数，与 BigQuery 一致）
  STRING(N):  必须指定最大长度，STRING(MAX) ≈ 2.5MB
  BYTES(N):   二进制数据
  BOOL:       布尔
  DATE:       日期
  TIMESTAMP:  带纳秒精度的时间戳（始终 UTC）
  JSON:       JSON 类型（2022+）
  ARRAY<T>:   数组（不支持嵌套 ARRAY）

**设计分析:**
  STRING(N) 要求显式长度是为了存储优化（Colossus 按声明长度分配空间）。
  无 VARCHAR/TEXT/CHAR 区分 — 统一为 STRING，简化了类型系统。
  TIMESTAMP 始终 UTC — 避免了时区混乱（MySQL DATETIME vs TIMESTAMP 的教训）。

## 提交时间戳与 TTL

OPTIONS (allow_commit_timestamp = true): 列可以存储精确的提交时间。
这利用了 TrueTime API — Spanner 独有的全球时钟同步技术。
```sql
CREATE TABLE AuditLog (
    LogId    INT64 NOT NULL,
    Action   STRING(50),
    CommitTs TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true)
) PRIMARY KEY (LogId);

```

ROW DELETION POLICY (TTL):
自动删除过期行，适合日志/事件类场景。
```sql
CREATE TABLE Events (
    EventId   INT64 NOT NULL,
    EventTime TIMESTAMP NOT NULL,
    Data      JSON
) PRIMARY KEY (EventId),
  ROW DELETION POLICY (OLDER_THAN(EventTime, INTERVAL 90 DAY));

```

**对比:** 其他引擎的 TTL:
  CockroachDB: gc.ttlseconds（行级 TTL, v22.1+）
  TiDB:        TTL（8.0+，表级 TTL 策略）
  Cassandra:   TTL（每行或每列级别，最灵活）
  DynamoDB:    TTL（按指定时间戳列自动过期）

## 外键（非交错）与 ARRAY 列

```sql
CREATE TABLE Reviews (
    ReviewId  INT64 NOT NULL,
    ProductId STRING(36) NOT NULL,
    Rating    INT64,
    Content   STRING(MAX),
    CONSTRAINT fk_product FOREIGN KEY (ProductId) REFERENCES Products (ProductId)
) PRIMARY KEY (ReviewId);

CREATE TABLE Profiles (
    UserId INT64 NOT NULL,
    Tags   ARRAY<STRING(50)>,
    Scores ARRAY<FLOAT64>
) PRIMARY KEY (UserId);

```

## 限制与注意事项

无 CTAS (CREATE TABLE AS SELECT)
无 TEMPORARY 表
无 ENUM / 用户自定义类型
无表继承
无触发器（用 Cloud Functions + Pub/Sub 替代）
无存储过程（用应用层或 Cloud Functions）
DDL 不是事务性的: CREATE TABLE 是 schema update，可能需要几分钟
Schema 变更是长事务: 后台滚动更新，不锁表但需要时间

## 版本演进

- **2012**: Spanner 论文发表（Google 内部已使用多年）
- **2017**: Cloud Spanner GA（对外公开服务）
- **2020**: JSON 类型支持
- **2021**: PostgreSQL 接口（预览），NUMERIC 类型
- **2022**: JSON 增强，细粒度 IAM
- **2023**: Bit-reversed sequences, THEN RETURN (DML 返回结果)
- **2024**: Sequence 增强, Graph 查询（预览），向量搜索（预览）
- **2025**: PostgreSQL 接口 GA，性能改进

## 横向对比: Spanner vs 其他引擎

## 一致性模型:

   Spanner:     外部一致性（比 SERIALIZABLE 更强，依赖 TrueTime）
   CockroachDB: SERIALIZABLE（软件时钟，无硬件依赖）
   TiDB:        Snapshot Isolation（TSO 全局时间戳）
   OceanBase:   RC/SI（取决于模式）

## 全球分布:

   Spanner:     原生全球部署（自动处理跨区域一致性），TrueTime 保证全球有序
   CockroachDB: 多区域（需要用户配置 LOCALITY），使用 HLC 混合逻辑时钟
   TiDB:        主要单区域（跨区域需要 TiCDC 复制）
   OceanBase:   主要单区域（OMS 支持跨区域同步）

## SQL 方言:

   Spanner:     GoogleSQL（独立方言，最少兼容历史包袱）
   CockroachDB: PostgreSQL 兼容
   TiDB:        MySQL 兼容
   OceanBase:   MySQL/Oracle 双模式
