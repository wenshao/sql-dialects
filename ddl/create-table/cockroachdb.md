# CockroachDB: CREATE TABLE

> 参考资料:
> - [CockroachDB - CREATE TABLE](https://www.cockroachlabs.com/docs/stable/create-table)
> - [CockroachDB - Multi-Region](https://www.cockroachlabs.com/docs/stable/multiregion-overview)
> - [CockroachDB - Architecture](https://www.cockroachlabs.com/docs/stable/architecture/overview)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## 基本语法

```sql
CREATE TABLE users (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    username   VARCHAR(100) NOT NULL,
    email      VARCHAR(255) NOT NULL UNIQUE,
    age        INT,
    balance    DECIMAL(10,2),
    bio        TEXT,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

```

## 语法设计分析（对 SQL 引擎开发者）


### UUID 主键: 分布式引擎的首选

CockroachDB 推荐 UUID 而非 SERIAL，这是分布式设计哲学的体现。

gen_random_uuid() 生成 V4 UUID (RFC 4122): 完全随机，无热点
unique_rowid() 生成 64 位整数: 时间戳 + 节点ID，时间有序但节点分散

SERIAL 在 CockroachDB 中的行为与 PostgreSQL 不同:
  PostgreSQL: SERIAL → 创建 SEQUENCE 对象 → nextval('seq')
  CockroachDB: SERIAL → unique_rowid()（不创建 SEQUENCE）
  这个差异是迁移时的常见陷阱: PostgreSQL 的 SERIAL 保证递增，CockroachDB 不保证

**对比:** 其他引擎的 ID 策略:
  TiDB:     AUTO_RANDOM（高位随机化，MySQL 语法兼容）
  Spanner:  GENERATE_UUID() 或 bit-reversed sequence（反转避免热点）
  OceanBase: AUTO_INCREMENT（依赖分区分散写入）
  MySQL:    AUTO_INCREMENT（单机递增，分布式无意义）

**对引擎开发者的启示:**
  SERIAL 的语义跨引擎不一致，是 PostgreSQL 兼容层的设计陷阱。
  如果兼容 PostgreSQL，必须文档明确 SERIAL 的实际行为，否则用户会踩坑。

```sql
CREATE TABLE orders (
    id         INT8 PRIMARY KEY DEFAULT unique_rowid(),  -- 等价于 SERIAL
    user_id    UUID NOT NULL REFERENCES users (id),
    amount     DECIMAL(10,2),
    order_date DATE NOT NULL DEFAULT CURRENT_DATE
);

```

### HASH-SHARDED INDEX: 解决顺序写入热点

单调递增的索引键（如时间戳）会导致写入集中在同一 Range。
Hash-sharded index 在键前添加 hash 前缀，分散写入到多个 Range。

实现原理:
  实际创建一个计算列 crdb_internal_ts_shard_N，值 = hash(ts) % N
  索引键变为 (shard_column, ts)，写入分散到 N 个 hash bucket

适用场景: 时序数据（按时间戳写入）、日志表
不适用: 需要按原始键范围扫描的场景（hash 打散了范围局部性）

```sql
CREATE TABLE events (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ts         TIMESTAMPTZ NOT NULL DEFAULT now(),
    event_type VARCHAR(50),
    data       JSONB,
    INDEX idx_events_ts (ts) USING HASH
);

```

**对比:** 其他引擎的热点规避:
  TiDB:     AUTO_RANDOM（ID 级别），SHARD_ROW_ID_BITS
  Spanner:  bit-reversed sequence（序列值反转）
  OceanBase: 分区策略（Hash/Key 分区）
  Redshift:  DISTKEY（分布键决定数据分片，但不是为了避免热点）

### Column Families: 列族存储优化（CockroachDB 独有）

将列分组到不同的 KV 存储家族，优化宽表场景。
常访问的列在一个 family，大字段在另一个 family → 减少 I/O。
```sql
CREATE TABLE wide_table (
    id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name  VARCHAR(100),
    data  BYTES,
    FAMILY f_main (id, name),
    FAMILY f_data (data)
);

```

**设计分析:**
  类似 HBase/Bigtable 的列族概念，但在 SQL 层暴露给用户。
  对比: Cassandra 也有类似概念；PostgreSQL/MySQL 无此功能。
  Spanner 自动管理列存储布局，不暴露此选项。

## 多区域表（Multi-Region，v21.1+）

CockroachDB 的多区域功能是其最重要的差异化特性。
三种模式，从粗到细: REGIONAL BY TABLE → GLOBAL → REGIONAL BY ROW

数据库级别设置区域（前提条件）
ALTER DATABASE mydb SET PRIMARY REGION 'us-east1';
ALTER DATABASE mydb ADD REGION 'us-west1';
ALTER DATABASE mydb ADD REGION 'eu-west1';

REGIONAL BY ROW: 行级区域控制（最灵活）
每行数据根据 crdb_region 列存储在对应区域，读写就近。
```sql
CREATE TABLE regional_users (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(100),
    region   crdb_internal_region NOT NULL DEFAULT gateway_region()::crdb_internal_region,
    email    VARCHAR(255)
) LOCALITY REGIONAL BY ROW;

```

GLOBAL: 全区域读优化（读多写少的参照表）
所有区域都有数据副本，读取零延迟；写入需要跨区域共识，延迟较高。
```sql
CREATE TABLE countries (
    code VARCHAR(2) PRIMARY KEY,
    name VARCHAR(100)
) LOCALITY GLOBAL;

```

REGIONAL BY TABLE: 表级区域绑定
```sql
CREATE TABLE us_orders (
    id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    amount DECIMAL(10,2)
) LOCALITY REGIONAL BY TABLE IN PRIMARY REGION;

```

**对比:** 其他引擎的多区域能力:
  Spanner:     Multi-region instances（Google 管理，用户选择区域配置）
  TiDB:        Placement Rules（策略级别，灵活但非行级）
  OceanBase:   LOCALITY + PRIMARY_ZONE（Zone 级别控制）
  Aurora:      Global Database（异步复制，非强一致）

## 计算列与高级特性

```sql
CREATE TABLE products (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    price    DECIMAL(10,2),
    tax_rate DECIMAL(5,4),
    total    DECIMAL(10,2) GENERATED ALWAYS AS (price * (1 + tax_rate)) STORED
);

```

ARRAY 和 JSONB（PostgreSQL 兼容）
```sql
CREATE TABLE profiles (
    id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tags     TEXT[],
    metadata JSONB
);

```

## CTAS 与实用语法

```sql
CREATE TABLE users_backup AS
SELECT * FROM users WHERE created_at > '2024-01-01';

CREATE TABLE IF NOT EXISTS audit_log (
    id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action  VARCHAR(50),
    details JSONB,
    ts      TIMESTAMPTZ DEFAULT now()
);

```

## 限制与注意事项

TEMPORARY 表: 支持（v22.1+），但行为与 PostgreSQL 有差异
UNLOGGED 表: 不支持（分布式引擎中"不记日志"无意义，Raft 日志是必需的）
表继承 (INHERITS): 不支持
表空间 (TABLESPACE): 不支持（存储是分布式的，用 LOCALITY 替代）
ENUM 类型: 支持（v20.2+）
外键: 完全支持且强制执行（跨 Range 的外键检查有额外延迟）
触发器: 不支持（用 CHANGEFEED 替代部分场景）
DDL 事务性: DDL 是事务性的！可以 BEGIN; CREATE TABLE; ROLLBACK;
            这与 PostgreSQL 一致，优于 MySQL/Oracle 的隐式提交

## 版本演进

v19.x: 核心分布式 SQL 能力成熟
v20.x: ENUM, IMPORT INTO, user-defined schemas
v21.1: 多区域（REGIONAL/GLOBAL），核心竞争力确立
v22.1: 行级 TTL, SQL 性能改进，临时表
v22.2: 只读事务性能优化
v23.1: READ COMMITTED 隔离级别（可选），Changefeeds 改进
v23.2: 物理集群复制(PCR)，声明式 schema 变更改进
v24.1: 物理集群复制 GA，Changefeed 性能大幅改进
v24.2: 增强的多租户能力，SQL 统计改进
v24.3: 逻辑数据复制(LDR) GA，虚拟集群增强

## 横向对比: CockroachDB vs 其他引擎

## 隔离级别:

   CockroachDB: 默认 SERIALIZABLE（最强，业界罕见）
   PostgreSQL:  默认 READ COMMITTED
   TiDB:        默认 REPEATABLE READ（实际是 Snapshot Isolation）
   OceanBase:   默认 READ COMMITTED（MySQL 模式）
   Spanner:     外部一致性（比 SERIALIZABLE 更强）

## 架构:

   CockroachDB: 存算一体（每个节点既做计算也做存储），无 Master 节点
   TiDB:        存算分离（TiDB Server + TiKV + PD）
   Spanner:     存算分离（Compute + Colossus）
   OceanBase:   共享无架构（每个 OBServer 相对独立）

## PostgreSQL 兼容性:

   CockroachDB: wire protocol 兼容，大部分 PostgreSQL 客户端可直接连接
   但差异显著: 无 PL/pgSQL 存储过程，SERIAL 行为不同，无扩展系统
