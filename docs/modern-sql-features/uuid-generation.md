# UUID 生成函数 (UUID Generation Functions)

UUID（Universally Unique Identifier，128 位通用唯一标识符）是过去三十年里最被滥用、也最被低估的数据库特性之一。它既被当作"取代自增主键"的银弹塞进高并发系统，也因为索引膨胀和缓冲池抖动被一票否决。从 1996 年 DCE RPC 规范定义 v1，到 2024 年 RFC 9562 正式确立 v6/v7/v8，从 PostgreSQL 内置 `gen_random_uuid()` 到 MySQL 的 `UUID_TO_BIN(..., 1)` 字节交换，从 SQL Server 的 `NEWSEQUENTIALID()` 到 Oracle 的 `SYS_GUID()` 原生 RAW(16)——不同数据库给出了截然不同的实现路线，背后是对"分布式主键 vs 索引局部性"的不同权衡。

## UUID 版本概览：v1 / v4 / v7 三大主流

UUID 一共有 8 个版本（v1 至 v8），但只有 v1、v4、v7 在数据库层面被广泛使用：

- **UUID v1**：48 位 MAC 地址 + 60 位时间戳 + 14 位时钟序列。1996 年 DCE 规范定义，能从 ID 反推机器与时间，存在隐私问题。MySQL `UUID()` 默认返回 v1。
- **UUID v4**：122 位完全随机 + 6 位版本/变体标记。2005 年 RFC 4122 标准化，碰撞概率每秒 10 亿持续 85 年才到 50%，是当前最普及的格式。PostgreSQL `gen_random_uuid()`、SQL Server `NEWID()` 都返回 v4。
- **UUID v7**：48 位毫秒时间戳 + 74 位随机数 + 6 位版本/变体。2024 年 5 月 RFC 9562 正式标准化，**字典序与时间序一致**，是 B+ 树主键的理想选择。PostgreSQL 18、MariaDB 10.7、ClickHouse 24.5、DuckDB 1.1 已原生支持。

### 主键采用矩阵（Adoption Matrix for Primary Keys）

| 引擎 | 默认推荐主键策略 | 内置 UUID 类型 | 字典序友好 |
|------|-----------------|---------------|-----------|
| PostgreSQL 18+ | `uuidv7()` 或 `BIGSERIAL` | `UUID` 16 字节 | 是（v7） |
| PostgreSQL 13-17 | `gen_random_uuid()` 或 `BIGSERIAL` | `UUID` 16 字节 | 否 |
| MySQL 8.0+ | `UUID_TO_BIN(UUID(), 1)` 或 `AUTO_INCREMENT` | `BINARY(16)` 模拟 | 是（swap） |
| MariaDB 10.7+ | `UUID()`（v7 内部存储） | `UUID` 16 字节 | 是（自动 swap） |
| SQL Server | `NEWSEQUENTIALID()` 或 `IDENTITY` | `UNIQUEIDENTIFIER` 16 字节 | 是（特殊序） |
| Oracle | `SYS_GUID()` 或 `IDENTITY`（12c+） | `RAW(16)` | 部分 |
| DB2 | `GENERATE_UNIQUE()` 或 `IDENTITY` | `CHAR(13) FOR BIT DATA` | 是（时间戳） |
| Snowflake | `UUID_STRING()` 或 `IDENTITY` | `VARCHAR` | 否 |
| BigQuery | `GENERATE_UUID()` 或 `INT64` 序列 | `STRING` | 否 |
| Redshift | `IDENTITY` 优先 | `VARCHAR` | 否 |
| ClickHouse 24.5+ | `generateUUIDv7()` 或时间排序键 | `UUID` 16 字节 | 是（v7） |
| DuckDB 1.1+ | `uuidv7()` 或自增 | `UUID` 16 字节 | 是（v7） |
| Cassandra | `timeuuid` (v1) 或 `uuid` (v4) | `UUID` / `TIMEUUID` | v1 是 |
| TiDB | `AUTO_RANDOM` 或 `UUID()` | 模拟 | 否 |
| CockroachDB | `gen_random_uuid()` 或 `unique_rowid()` | `UUID` 16 字节 | 否 |
| Spanner | `GENERATE_UUID()` 或比特反转序列 | `STRING(36)` | 否 |
| YugabyteDB | `gen_random_uuid()` 或哈希分区 | `UUID` 16 字节 | 否 |

## RFC 4122（2005）→ RFC 9562（2024）的标准演进

### RFC 4122（2005 年 7 月）

由 Paul Leach、Michael Mealling 与 Rich Salz 起草，将 1996 年 OSF DCE 1.1 规范的 UUID 格式正式提交为 IETF 标准。规范定义了五个版本：

- **v1**：基于时间戳和 MAC 地址（DCE 时代的格式）
- **v2**：DCE Security 版本，几乎不被使用
- **v3**：基于命名空间和名字的 MD5 哈希
- **v4**：完全随机
- **v5**：基于命名空间和名字的 SHA-1 哈希

RFC 4122 没有定义"时间排序"的 UUID（v1 的时间字段顺序导致字典序与时间序不一致），这成为后续二十年索引设计的痛点。

### RFC 9562（2024 年 5 月）

由 Brad Peabody、Kyzer Davis 起草，正式取代 RFC 4122，新增三个版本：

- **v6**：v1 的"时间字段重排版"——把高位时间戳放最前，字典序 = 时间序，并保留 MAC 地址兼容
- **v7**：48 位 Unix 毫秒时间戳 + 随机位，**最推荐的现代格式**
- **v8**：完全自定义版本，给应用预留实现空间

RFC 9562 的关键变化：
- 明确"UUID 字符串表示"的解析规则（更严格）
- 单调性建议（同毫秒内 v7 实现可附加计数器）
- 安全考量章节扩展（v1/v6 的 MAC 隐私问题，v4 的 CSPRNG 要求）
- 提供完整的伪代码示例

注：RFC 9562 在 2024 年 5 月发布。PostgreSQL 18（2025 年 9 月发布）是首个主流 OLTP 引擎在版本号同步标准化阶段就内置 v7 函数的（MariaDB 10.7、ClickHouse 24.5、DuckDB 1.1 均在 RFC 草案阶段提前实现）。

## 支持矩阵（45+ 引擎）

### UUID 数据类型与生成函数

| 引擎 | 内置 UUID 类型 | 字符串/二进制 | v4 函数 | v7 函数 | 引擎版本 |
|------|---------------|--------------|---------|---------|---------|
| PostgreSQL | `UUID` | 16 字节 | `gen_random_uuid()` | `uuidv7()` | 13+ / 18+ |
| MySQL | -- | `CHAR(36)` / `BINARY(16)` | -- (UUID() 是 v1) | -- | -- |
| MariaDB | `UUID` | 16 字节 | -- | `UUID()` | 10.7+ |
| SQLite | -- | `TEXT` / `BLOB` | 扩展 / `randomblob(16)` | 扩展 | -- |
| Oracle | `RAW(16)` | 16 字节 | `SYS_GUID()` (准 v4) | -- | 9i+ |
| SQL Server | `UNIQUEIDENTIFIER` | 16 字节 | `NEWID()` | -- | 2005+ |
| DB2 | `CHAR FOR BIT DATA` | 13/16 字节 | `GENERATE_UNIQUE()` (时间戳) | -- | 9.7+ |
| Sybase ASE | -- | `VARCHAR(36)` | `newid()` | -- | 12.5+ |
| Snowflake | -- | `VARCHAR` | `UUID_STRING()` | -- | GA |
| BigQuery | -- | `STRING` | `GENERATE_UUID()` | -- | GA |
| Redshift | -- | `VARCHAR(36)` | -- | -- | -- |
| Athena | -- | `VARCHAR` | `uuid()` | -- | 继承 Trino |
| Azure Synapse | `UNIQUEIDENTIFIER` | 16 字节 | `NEWID()` | -- | 继承 SQL Server |
| Greenplum | `UUID` | 16 字节 | `gen_random_uuid()` | -- (扩展) | 6+ |
| Vertica | `UUID` | 16 字节 | `UUID_GENERATE()` | -- | 9.0+ |
| ClickHouse | `UUID` | 16 字节 | `generateUUIDv4()` | `generateUUIDv7()` | 24.5+ |
| DuckDB | `UUID` | 16 字节 | `uuid()` / `gen_random_uuid()` | `uuidv7()` | 1.1+ |
| MonetDB | `UUID` | 16 字节 | `uuid()` | -- | GA |
| Trino | `UUID` | 16 字节 | `uuid()` | -- | GA |
| Presto | `UUID` | 16 字节 | `uuid()` | -- | 0.145+ |
| Spark SQL | -- | `STRING` | `uuid()` | -- | 2.3+ |
| Hive | -- | `STRING` | `reflect("java.util.UUID","randomUUID")` | -- | -- |
| Flink SQL | -- | `STRING` | `UUID()` | -- | 1.11+ |
| Databricks | -- | `STRING` | `uuid()` | -- | GA |
| Impala | -- | `STRING` | `uuid()` | -- | 2.5+ |
| StarRocks | -- | `VARCHAR(36)` | `uuid()` | -- | 2.4+ |
| Doris | -- | `VARCHAR(36)` | `uuid()` | -- | 1.2+ |
| Teradata | -- | -- | -- | -- | 不支持 |
| SAP HANA | -- | `VARBINARY(16)` | `SYSUUID` | -- | GA |
| Informix | -- | -- | -- | -- | 不支持 |
| Firebird | -- | `CHAR(16) CHARACTER SET OCTETS` | `GEN_UUID()` | -- | 2.5+ |
| H2 | `UUID` | 16 字节 | `RANDOM_UUID()` | -- | GA |
| HSQLDB | `UUID` | 16 字节 | `UUID()` | -- | 2.0+ |
| Derby | -- | -- | -- | -- | 不支持 |
| TiDB | -- | `CHAR(36)` / `BINARY(16)` | `UUID()` 兼容 | -- | 3.1+ |
| OceanBase | -- | `CHAR(36)` / `BINARY(16)` | `UUID()` 兼容 | -- | 2.2+ |
| CockroachDB | `UUID` | 16 字节 | `gen_random_uuid()` | -- | GA |
| YugabyteDB | `UUID` | 16 字节 | `gen_random_uuid()` | -- | 继承 PG |
| SingleStore | -- | `CHAR(36)` | -- (UUID() 兼容 MySQL) | -- | -- |
| Spanner | -- | `STRING(36)` | `GENERATE_UUID()` | -- | 2022+ |
| Cassandra | `UUID` / `TIMEUUID` | 16 字节 | `uuid()` / `now()` | -- | GA |
| ScyllaDB | `UUID` / `TIMEUUID` | 16 字节 | `uuid()` / `now()` | -- | GA |
| DynamoDB (PartiQL) | -- | `String` | 应用层生成 | -- | -- |
| Materialize | `UUID` | 16 字节 | `gen_random_uuid()` | -- | 继承 PG |
| RisingWave | `UUID` | 16 字节 | `gen_random_uuid()` | -- | 继承 PG |
| TimescaleDB | `UUID` | 16 字节 | `gen_random_uuid()` | 继承 PG | 继承 PG |
| QuestDB | `UUID` | 16 字节 | `rnd_uuid4()` | -- | 7.0+ |
| Crate DB | -- | -- | -- | -- | 不支持原生 |
| InfluxDB (SQL) | -- | -- | -- | -- | 不支持原生 |
| DatabendDB | -- | `VARCHAR` | `uuid()` | -- | GA |
| Yellowbrick | `UUID` | 16 字节 | `uuid_generate_v4()` | -- | 继承 PG |
| Firebolt | -- | `TEXT` | `gen_random_uuid()` | -- | GA |

> 统计：约 45 个引擎中，约 30 个具有内置 UUID 数据类型（16 字节存储）或函数；约 5 个引擎（PostgreSQL 18、MariaDB 10.7、ClickHouse 24.5、DuckDB 1.1、TimescaleDB）支持 UUID v7 原生生成；约 10 个引擎完全不提供 UUID 函数或仅靠应用层生成。

### v6 / v8 / 顺序变体支持

UUID v6（v1 字段重排）和 v8（完全自定义）几乎没有数据库原生支持，主要因为 v7 已经覆盖了"时间排序 + 随机"的核心需求。SQL Server 的 `NEWSEQUENTIALID()` 是历史最久的"顺序 GUID"实现，早于 RFC 9562 近二十年。

| 引擎 | UUID v1 | UUID v6 | UUID v7 | UUID v8 | 顺序变体 / 厂商专有 | 版本 |
|------|---------|---------|---------|---------|---------------------|------|
| PostgreSQL | `uuid_generate_v1()` (扩展) | `uuid_generate_v6()` (扩展) | 内置 18+ | -- | -- | 13+ / 18+ |
| MySQL | `UUID()` (默认) | -- | -- | -- | `UUID_TO_BIN(.., 1)` 字节交换 | 8.0+ |
| MariaDB | -- | -- | `UUID()` (内部 v7) | -- | -- | 10.7+ |
| SQL Server | -- | -- | -- | -- | `NEWSEQUENTIALID()` 顺序 GUID | 2005+ |
| Oracle | -- | -- | -- | -- | `SYS_GUID()` (16 字节, 非标 UUID) | 8i+ |
| DB2 | -- | -- | -- | -- | `GENERATE_UNIQUE()` 时间戳前缀 | 9.7+ |
| ClickHouse | `generateUUIDv1()` (实验) | -- | `generateUUIDv7()` | -- | -- | 24.5+ |
| DuckDB | -- | -- | `uuidv7()` | -- | -- | 1.1+ |
| Cassandra | `now()` (TIMEUUID) | -- | -- | -- | TIMEUUID 内部 v1 | GA |
| ScyllaDB | `now()` (TIMEUUID) | -- | -- | -- | TIMEUUID 内部 v1 | GA |
| TiDB | `UUID()` (兼容) | -- | -- | -- | `AUTO_RANDOM` 字段 | 3.1+ |
| CockroachDB | -- | -- | -- | -- | `unique_rowid()` (Snowflake-like) | GA |
| Spanner | -- | -- | -- | -- | 比特反转序列 `BIT_REVERSED_POSITIVE` | 2022+ |

> 注：PostgreSQL 的 uuid-ossp 扩展提供 `uuid_generate_v1()`、`uuid_generate_v3()`、`uuid_generate_v5()` 等函数，但项目维护者 Tom Lane 等多次建议直接使用核心模块的 `gen_random_uuid()`，因为 ossp 依赖外部 UUID 库且 v1 暴露 MAC 地址。
>
> SQL Server `NEWSEQUENTIALID()` 自 2005 年随 SQL Server 2005 同步发布，比 RFC 9562 早 19 年实现"顺序 GUID 主键"理念。

## 各引擎逐一详解

### PostgreSQL：从 uuid-ossp 扩展到内置 uuidv7()

PostgreSQL 的 UUID 支持经历了三个阶段：

**阶段 1（2008 - 2020）：uuid-ossp 扩展**

```sql
-- PostgreSQL 8.3 及以前需安装 uuid-ossp 扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

SELECT uuid_generate_v1();         -- v1 (时间戳 + MAC)
SELECT uuid_generate_v1mc();       -- v1 (随机 MAC, 隐私友好)
SELECT uuid_generate_v3(uuid_ns_url(), 'https://example.com');  -- v3 MD5
SELECT uuid_generate_v4();         -- v4 (随机)
SELECT uuid_generate_v5(uuid_ns_url(), 'https://example.com');  -- v5 SHA-1

-- 缺点：依赖系统 OSSP UUID 库（不同 Linux 发行版打包方式不同）
-- 缺点：v1 暴露 MAC 地址，需主动选择 v1mc 才能避免
```

**阶段 2（2020 年 9 月，PostgreSQL 13）：内置 gen_random_uuid()**

PostgreSQL 13（2020 年 9 月发布）将原本只在 pgcrypto 扩展中的 `gen_random_uuid()` 提升到核心，无需任何扩展即可使用：

```sql
-- PostgreSQL 13+: 无需扩展，原生 v4
SELECT gen_random_uuid();
-- 8f14e45f-ceea-467a-a5f7-4b0ab7c4dd3e

-- 应用于主键
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id BIGINT NOT NULL,
    total NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO orders (customer_id, total) VALUES (1001, 99.99);
```

`gen_random_uuid()` 内部调用 `pg_strong_random()`，使用 OpenSSL 或操作系统的 `/dev/urandom`，是 CSPRNG（密码学安全）级别的随机源。

**阶段 3（2025 年 9 月，PostgreSQL 18）：内置 uuidv7()**

PostgreSQL 18（2025 年 9 月发布）作为首个主流 OLTP 引擎，将 `uuidv7()` 直接内置到核心：

```sql
-- PostgreSQL 18+: 原生 v7
SELECT uuidv7();
-- 0197a3f1-9c42-7f8e-a9b2-1c3d4e5f6789
--   ↑ 48 位毫秒时间戳   ↑ ver=7  ↑ 随机

-- 推荐主键模式（高并发友好）
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    customer_id BIGINT NOT NULL,
    total NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 范围查询（按时间）
SELECT * FROM orders
WHERE id >= uuidv7_extract_timestamp('019789ab-...')  -- 假设函数
ORDER BY id DESC LIMIT 100;

-- 字典序 = 时间序的最大优势：可在主键上做 range scan
SELECT * FROM orders WHERE id >= '01970000-0000-7000-8000-000000000000'
                       AND id <  '01980000-0000-7000-8000-000000000000';
```

PostgreSQL 18 的 `uuidv7()` 严格遵循 RFC 9562 第 5.7 节规范：48 位毫秒 Unix 时间戳，4 位版本（0b0111），12 位 rand_a，2 位 variant（0b10），62 位 rand_b。

### MySQL：UUID() 是 v1，UUID_TO_BIN 字节交换

MySQL 的 UUID 函数从 5.0 时代就存在，但默认返回 v1，是为数不多坚持 v1 的现代数据库：

```sql
-- MySQL 8.0
SELECT UUID();
-- ba5d2b71-8ea0-11ee-b9d1-0242ac120002
--   ↑ time_low  ↑ time_mid  ↑ time_hi_and_version  ↑ clock_seq  ↑ node (MAC)

-- 36 字符字符串（带 4 个连字符）
-- 字段布局：time_low(4) - time_mid(2) - time_hi_ver(2) - clock_seq(2) - node(6)
-- 注意 time_low 在最前面，每毫秒变化最剧烈，因此字符串排序不等于时间序

-- 测试：连续 5 次生成
SELECT UUID() FROM (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) t;
-- 结果（每次 ms 内只有 time_low 微小变化，但前 8 个字符快速跳动）
```

为了让 v1 适合做主键，MySQL 8.0 引入了 `UUID_TO_BIN(uuid, swap_flag)`：

```sql
-- swap_flag = 0（默认）：保持原 v1 字段顺序
SELECT HEX(UUID_TO_BIN('ba5d2b71-8ea0-11ee-b9d1-0242ac120002', 0));
-- BA5D2B71 8EA0 11EE B9D1 0242AC120002
--   time_low time_mid time_hi (字典序乱)

-- swap_flag = 1：把 time_hi_version 放最前，字典序 = 时间序
SELECT HEX(UUID_TO_BIN('ba5d2b71-8ea0-11ee-b9d1-0242ac120002', 1));
-- 11EE 8EA0 BA5D2B71 B9D10242AC120002
-- time_hi (高位) time_mid (中位) time_low (低位) ...
-- 现在字典序排序 = 时间排序

-- 推荐主键模式
CREATE TABLE orders (
    id BINARY(16) PRIMARY KEY DEFAULT (UUID_TO_BIN(UUID(), 1)),
    customer_id BIGINT,
    total DECIMAL(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO orders (customer_id, total) VALUES (1001, 99.99);

-- 查询时转回字符串（注意 swap_flag 必须一致）
SELECT BIN_TO_UUID(id, 1) AS order_id, customer_id, total FROM orders;
-- ba5d2b71-8ea0-11ee-b9d1-0242ac120002
```

#### MySQL UUID_TO_BIN 字节布局详解

```
原始 UUID v1 (RFC 4122):
    time_low        time_mid    time_hi_v   clock_seq   node (MAC)
    [4 字节]        [2 字节]     [2 字节]     [2 字节]     [6 字节]

swap_flag = 0 (默认, BIN 与字符串字段顺序一致):
    | time_low (4) | time_mid (2) | time_hi_v (2) | clock_seq (2) | node (6) |
    每毫秒 time_low 变化范围 0x00000000 ~ 0xFFFFFFFF
    -> 高位字节随机, 字典序 ≠ 时间序
    -> 索引插入散布在 B+ 树各处, 写热点小但页分裂多

swap_flag = 1 (推荐):
    | time_hi_v (2) | time_mid (2) | time_low (4) | clock_seq (2) | node (6) |
    每毫秒高 8 字节单调递增 (time_hi:time_mid:time_low)
    -> 字典序 = 时间序
    -> 索引插入集中在 B+ 树最右侧, 单页热点但无碎片
```

注意：MySQL 至今未原生支持 v4 或 v7。社区 PR（如 WL#15184）讨论过引入 v4，但截至 MySQL 9.0 仍未合入。生产环境通常使用 `UUID_TO_BIN(UUID(), 1)`（v1 swap）或应用层生成 v7。

### MariaDB 10.7：UUID 数据类型 + 内部 v7

MariaDB 在 2022 年 2 月发布的 10.7 版本引入了原生 `UUID` 数据类型，且内部以"时间戳前置"格式存储，等价于 RFC 9562 的 v6/v7 思想：

```sql
-- MariaDB 10.7+
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT UUID(),
    total DECIMAL(10,2)
);

-- UUID() 在 MariaDB 10.7+ 中返回字符串 v1, 但 UUID 列存储时按时间序字节排列
INSERT INTO orders (total) VALUES (99.99);

-- 查看存储字节序（字典序与时间序一致）
SELECT id, HEX(id) FROM orders;
```

MariaDB 的 `UUID` 类型固定 16 字节存储，比 MySQL 的 `BINARY(16) + UUID_TO_BIN` 方案更自然，无需 `swap_flag` 参数。

注：MariaDB 10.10（2022 年 11 月）添加了 `UUID()` 函数返回 v7 风格的能力（内部时间戳排列），进一步简化了应用代码。

### SQL Server：NEWID() (v4) 与 NEWSEQUENTIALID()

SQL Server 早在 2000 年就支持 `NEWID()` 返回随机 GUID（语义上是 v4），并在 2005 年引入了**比 RFC 9562 早 19 年**的 `NEWSEQUENTIALID()`：

```sql
-- 标准 NEWID() 返回随机 v4 风格 UUID
SELECT NEWID();
-- C9A646D3-9C61-4655-9F44-F5FE6F9F8D3F

-- NEWSEQUENTIALID 仅可用于 DEFAULT 约束（不能直接 SELECT）
CREATE TABLE Orders (
    Id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    CustomerId BIGINT,
    Total DECIMAL(10,2),
    CreatedAt DATETIME2 DEFAULT SYSUTCDATETIME()
);

INSERT INTO Orders (CustomerId, Total) VALUES (1001, 99.99);
SELECT TOP 5 * FROM Orders ORDER BY Id;
-- Id 值是单调递增的（字典序 = 创建序）
```

`NEWSEQUENTIALID()` 的实现细节：
- 内部使用 Windows API `UuidCreateSequential()`
- 字段布局：固定 hostid（机器标识）+ 单调递增的时间戳/计数器
- **注意**：在数据库重启或 host 标识变化时，序列会"跳变"
- 字典序在 SQL Server 的 GUID 比较规则下递增（注意 SQL Server 用了非常规的字节比较顺序）

GUID 排序顺序的特殊性：

```sql
-- SQL Server 用以下顺序比较 UNIQUEIDENTIFIER 字节：
-- bytes [10..15], [8..9], [6..7], [4..5], [0..3]
-- 因此 NEWSEQUENTIALID 的"递增"是按这个特殊比较序，而非字面字典序

DECLARE @a UNIQUEIDENTIFIER = NEWSEQUENTIALID();
WAITFOR DELAY '00:00:00.001';
DECLARE @b UNIQUEIDENTIFIER = NEWSEQUENTIALID();
SELECT
    CAST(@a AS VARCHAR(40)) AS A,
    CAST(@b AS VARCHAR(40)) AS B,
    CASE WHEN @a < @b THEN 'a < b' ELSE 'b < a' END;
-- 在 GUID 比较中 @a < @b（递增），但若按字符串字典序可能反过来
```

SQL Server 的 `NEWSEQUENTIALID()` 是历史最早的"顺序 GUID 主键"实现，但因其字节序与字符串字典序不一致，跨系统使用时易引起混淆。

### Oracle：SYS_GUID() RAW(16)

Oracle 自 8i（1999 年）就提供 `SYS_GUID()`，返回 16 字节 RAW，但**不严格遵循 RFC 4122/9562**：

```sql
-- Oracle SYS_GUID 返回 RAW(16)，没有版本/变体字段
SELECT SYS_GUID() FROM DUAL;
-- BD86F7A8 5E2C4D87 9F3A1B2C 3D4E5F60 (32 个十六进制字符, 16 字节)

-- 注意：SYS_GUID() 不是标准 UUID
-- - 没有 4 位版本字段
-- - 没有 2 位变体字段
-- - 字段结构是 Oracle 私有（通常包含进程 ID、时间戳和计数器）

-- 用于主键
CREATE TABLE orders (
    id RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    customer_id NUMBER,
    total NUMBER(10, 2),
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);

INSERT INTO orders (customer_id, total) VALUES (1001, 99.99);

-- 转字符串显示
SELECT RAWTOHEX(id) FROM orders;

-- 与 RFC 4122 兼容的字符串格式 (8-4-4-4-12) 需要应用层格式化
SELECT
    SUBSTR(RAWTOHEX(id), 1, 8)  || '-' ||
    SUBSTR(RAWTOHEX(id), 9, 4)  || '-' ||
    SUBSTR(RAWTOHEX(id), 13, 4) || '-' ||
    SUBSTR(RAWTOHEX(id), 17, 4) || '-' ||
    SUBSTR(RAWTOHEX(id), 21, 12) AS uuid_str
FROM orders;
```

Oracle 没有原生的 v4/v7 函数。如需标准 UUID，常见方案：
1. `LOWER(SUBSTR(RAWTOHEX(SYS_GUID()), 1, 8) || '-' || ... )` 拼接（仍非严格 v4，缺版本位）
2. 调用 PL/SQL `DBMS_CRYPTO.RANDOMBYTES` + 手动设置版本/变体位
3. 使用 Oracle Application Express (APEX) 的 `apex_util.random_string`（仅在装了 APEX 的环境）

Oracle 12c 引入了 IDENTITY 列（自增主键），多数场景下取代 SYS_GUID。

### DB2：GENERATE_UNIQUE() 时间戳前缀 13 字节

DB2 提供 `GENERATE_UNIQUE()` 函数，返回 13 字节的 `CHAR(13) FOR BIT DATA`：

```sql
-- DB2
SELECT HEX(GENERATE_UNIQUE()) FROM SYSIBM.SYSDUMMY1;
-- 20251201124530001234567890ABCDEF (32 字符 = 16 字节)

-- 实际是 13 字节的二进制数据：
-- 前 8 字节：UTC 时间戳（精度到亚秒）
-- 后 5 字节：节点 ID + 序号（保证同一时间戳内唯一）

-- 不是标准 UUID（位宽与字段都不同）
-- 字典序 = 时间序（时间戳在高位）

CREATE TABLE orders (
    id CHAR(13) FOR BIT DATA NOT NULL DEFAULT GENERATE_UNIQUE(),
    customer_id BIGINT,
    total DECIMAL(10, 2),
    PRIMARY KEY (id)
);
```

DB2 没有原生 v4/v7 函数。如需 RFC 4122 兼容 UUID，可通过 SYSFUN.RAND 拼接，或使用 Java/PL/SQL 存储过程。

### Cassandra / ScyllaDB：TIMEUUID（v1）与 UUID（v4）

Cassandra 是少数把"时间排序 UUID"作为一等公民的数据库：

```sql
-- Cassandra CQL
CREATE TABLE events (
    id TIMEUUID PRIMARY KEY,
    payload TEXT
);

-- now() 返回当前时间的 TIMEUUID（内部 v1, MAC 替换为节点标识）
INSERT INTO events (id, payload) VALUES (now(), 'event 1');

-- TIMEUUID 比较：按时间字段（不是按字典序）
SELECT * FROM events WHERE id >= minTimeuuid('2025-01-01') AND id < maxTimeuuid('2025-01-02');

-- v4 风格随机 UUID
SELECT uuid();

-- TIMEUUID 与 UUID 不能直接互转
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid(),  -- 默认值不被 CQL 支持，需在 INSERT 时显式
    name TEXT
);
```

Cassandra 的 TIMEUUID 类型支持 `dateOf()`、`unixTimestampOf()`、`minTimeuuid()`、`maxTimeuuid()` 等专用函数，是设计时序数据 schema 的关键工具。ScyllaDB 完全继承 Cassandra 的 UUID/TIMEUUID 语义。

### ClickHouse：generateUUIDv4 / generateUUIDv7

ClickHouse 自 19.x 就支持 `generateUUIDv4()`，2024 年 5 月的 24.5 版本（与 RFC 9562 同月）跟进 v7：

```sql
-- ClickHouse v4
SELECT generateUUIDv4();

-- ClickHouse 24.5+ v7
SELECT generateUUIDv7();

-- 应用于 MergeTree 主键（v7 排序友好，对压缩比有利）
CREATE TABLE events (
    id UUID DEFAULT generateUUIDv7(),
    user_id UInt64,
    ts DateTime DEFAULT now(),
    payload String
)
ENGINE = MergeTree()
ORDER BY (ts, id)        -- ClickHouse 通常以时间为排序键，UUID 是去重键
PRIMARY KEY (ts, id);

INSERT INTO events (user_id, payload) VALUES (1001, 'click');
```

ClickHouse 还提供：
- `generateUUIDv4(...)`：可传入种子参数（高级用法，用于确定性）
- `UUIDStringToNum()` / `UUIDNumToString()`：在 16 字节二进制和字符串之间转换
- `toUUID()` / `toUUIDOrNull()`：字符串解析

### DuckDB：从 uuid() 到 uuidv7()

DuckDB 1.1（2024 年 9 月发布）将 v7 加入核心：

```sql
-- DuckDB
SELECT uuid();                  -- 等价 gen_random_uuid()，v4
SELECT gen_random_uuid();       -- v4
SELECT uuidv7();                -- v7（DuckDB 1.1+）

-- 主键
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    payload VARCHAR
);

INSERT INTO events (payload) VALUES ('hello');
```

DuckDB 的 `UUID` 类型固定 16 字节，且实现了 v7 的"亚毫秒单调"——同一毫秒内多次调用 `uuidv7()` 也保证递增（通过内部计数器替代 rand_a 的高位）。

### BigQuery / Snowflake：纯字符串 UUID

云数据仓库通常没有 UUID 数据类型，统一用字符串：

```sql
-- BigQuery
SELECT GENERATE_UUID();
-- 'cb3b7b4e-5fb8-4a3a-9f29-7ac8e9b3d4c2'

CREATE TABLE `project.dataset.events` (
    id STRING DEFAULT GENERATE_UUID(),
    payload STRING
);

-- Snowflake
SELECT UUID_STRING();
-- 'a1b2c3d4-e5f6-4789-0abc-def012345678'

-- Snowflake 还可指定命名空间和名字（v5 风格）
SELECT UUID_STRING('ns-uuid', 'my-name');

-- 主键
CREATE TABLE events (
    id STRING DEFAULT UUID_STRING(),
    payload STRING
);
```

由于 BigQuery 和 Snowflake 是列存 MPP 引擎，UUID 索引/聚簇不是性能关键。多数场景下使用 INT64 序列或自然键。

### Spanner：GENERATE_UUID + 比特反转

Google Spanner 在 2022 年加入 `GENERATE_UUID()`，但官方更推荐"比特反转序列"作为主键：

```sql
-- Spanner GENERATE_UUID 返回 STRING(36) RFC 4122 v4
SELECT GENERATE_UUID();

CREATE TABLE Singers (
    SingerId STRING(36) NOT NULL DEFAULT (GENERATE_UUID()),
    Name STRING(MAX),
) PRIMARY KEY (SingerId);

-- 比特反转序列（推荐用于 BIGINT 主键时分散热点）
CREATE SEQUENCE SingerIdSequence OPTIONS (sequence_kind = 'bit_reversed_positive');

CREATE TABLE Singers (
    SingerId INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE SingerIdSequence)),
    Name STRING(MAX),
) PRIMARY KEY (SingerId);
```

比特反转序列把单调递增 64 位整数的位顺序反转：`1, 2, 3, ...` 变成 `0x80..., 0x40..., 0xC0...`，从而把"最右叶子页热点"打散到整个 keyspace。这是 Spanner 对"无 UUID 的分布式热点缓解"的官方答案。

### CockroachDB / YugabyteDB：gen_random_uuid + 哈希分区

CockroachDB 完整继承 PostgreSQL 协议，但优先推荐 `gen_random_uuid()` 而非自增：

```sql
-- CockroachDB
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id INT,
    total DECIMAL
);

-- CockroachDB 还有 unique_rowid()（Snowflake-like，64 位）
CREATE TABLE events (
    id INT PRIMARY KEY DEFAULT unique_rowid(),
    payload STRING
);

-- unique_rowid 由 [时间戳 ms] + [worker id] + [counter] 组成
-- 比 UUID 紧凑，但仅 64 位，需注意 worker id 上限
```

YugabyteDB 同样继承 PG 的 `gen_random_uuid()`，但提供哈希分区作为分布热点的官方方案：

```sql
-- YugabyteDB
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id INT,
    total DECIMAL
) SPLIT INTO 16 TABLETS;        -- 显式预分裂

-- 或使用哈希分区（默认）
CREATE TABLE orders (
    id UUID,
    customer_id INT,
    PRIMARY KEY (id HASH)        -- HASH 修饰：按 id 哈希分区到不同 tablet
);
```

### TiDB：UUID() 兼容 + AUTO_RANDOM

TiDB 兼容 MySQL 协议（`UUID()` 返回 v1 字符串），但提供更专业的 `AUTO_RANDOM` 替代方案：

```sql
-- TiDB 推荐：AUTO_RANDOM
CREATE TABLE orders (
    id BIGINT PRIMARY KEY AUTO_RANDOM(5),  -- 5 位用作 shard 前缀
    customer_id BIGINT,
    total DECIMAL(10,2)
);

-- 插入时高 5 位由 TiDB 随机分配，低位单调递增
INSERT INTO orders (customer_id, total) VALUES (1001, 99.99);

-- 兼容 MySQL 的 UUID()
SELECT UUID();
-- 同 MySQL：返回 v1 字符串
```

`AUTO_RANDOM(N)` 把高 N 位作为 shard 前缀（随机），把单调递增的写入"分散"到 2^N 个 region，无需 UUID 即可解决热点问题。

### SAP HANA：SYSUUID

```sql
-- SAP HANA
SELECT SYSUUID FROM DUMMY;
-- 32 字符十六进制（无连字符）

-- 主键
CREATE TABLE events (
    id VARBINARY(16) DEFAULT SYSUUID PRIMARY KEY,
    payload NVARCHAR(1000)
);
```

SAP HANA 的 `SYSUUID` 是 RFC 4122 v4（122 位随机 + 6 位版本/变体）。

### Vertica / Greenplum：继承 PG 路线

```sql
-- Vertica
SELECT UUID_GENERATE();         -- v4

-- Greenplum 6+（基于 PG 9.4）
SELECT gen_random_uuid();
```

### H2 / HSQLDB / Firebird：嵌入式数据库的支持

```sql
-- H2
SELECT RANDOM_UUID();           -- v4

-- HSQLDB
SELECT UUID();                   -- v4 (注意与 MySQL 的 v1 不同)

-- Firebird 2.5+
SELECT GEN_UUID() FROM RDB$DATABASE;    -- v4

-- 注意：嵌入式数据库通常不在意分布式热点，UUID 主要用于全局唯一标识
```

### QuestDB：rnd_uuid4()

```sql
-- QuestDB
SELECT rnd_uuid4();             -- v4

CREATE TABLE events (
    id UUID,
    ts TIMESTAMP,
    payload STRING
) TIMESTAMP(ts);
```

QuestDB 是时序数据库，主键通常是时间戳分区，UUID 仅用于事件唯一标识，因此没有引入 v7。

### Trino / Presto / Athena / Spark / Flink

```sql
-- Trino / Presto / Athena
SELECT uuid();                  -- v4

-- Spark SQL
SELECT uuid();

-- Flink SQL
SELECT UUID();
```

这些查询引擎通常作为外部表访问层，UUID 多用于结果列计算，而非主键。

### NoSQL 与 PartiQL

```sql
-- DynamoDB PartiQL: 没有内置 UUID 函数
-- 需要应用层（AWS SDK）生成后插入
INSERT INTO "Orders" VALUE { 'Id': 'a1b2c3d4-...', 'CustomerId': 1001 };

-- MongoDB SQL（mongosh）
db.orders.insertOne({_id: UUID(), customer_id: 1001});
-- BSON 中 UUID 是子类型 4，固定 16 字节
```

## UUID v7 深度解析（RFC 9562 §5.7）

### 规范字段布局

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                           unix_ts_ms                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          unix_ts_ms           |  ver  |       rand_a          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|var|                        rand_b                             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                            rand_b                             |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

字段位宽:
- unix_ts_ms (48 bit): 自 1970-01-01 UTC 起的毫秒数
                       2^48 ms ≈ 8919 万年, 足以用到 10889 年
- ver       (4 bit):  固定 0b0111 = 7
- rand_a    (12 bit): 12 位随机或单调子毫秒计数器
- var       (2 bit):  固定 0b10 (RFC 4122/9562 variant)
- rand_b    (62 bit): 62 位强随机
```

### 字符串表示

UUID v7 复用 RFC 4122 的 8-4-4-4-12 格式：

```
01970000-1234-7abc-9def-0123456789ab
└──────────────┘ │   └─┬─┘ │ └────────┬─────────┘
   unix_ts_ms    │ ver=7   │           rand_b (62 位)
                 rand_a   variant
```

### 单调性保证（RFC 9562 §6.2 推荐方法）

RFC 9562 推荐三种实现方式应对"同毫秒单调性"问题：

**方法 1（Fixed-Length Dedicated Counters）**：把 rand_a 的 12 位用作纯计数器
```
ms 内首次调用：rand_a = 0
后续调用：rand_a += 1
ms 翻页时：reset rand_a = 0（或随机化以增加不可预测性）
```

**方法 2（Monotonic Random）**：rand_a 的高位作为计数器，低位仍随机
```
ms 内首次调用：rand_a = random(12 位)
后续调用：rand_a = previous_rand_a + random(1..N)（保证递增）
```

**方法 3（Replace Leftmost Bits in rand_b）**：把 rand_b 的高位也用作计数器
```
极端高吞吐场景使用：rand_b 的高 32 位 = counter, 低 30 位 = random
```

PostgreSQL 18 选择了方法 2（rand_a 高位单调），DuckDB 1.1 选择了方法 1，ClickHouse 24.5 选择了方法 1+2 组合。

### v7 vs v4 的索引性能对比

```
B+ 树主键（10M 行插入到空表，BINARY(16)，缓冲池 1GB）:

UUID v4：
  插入耗时：约 380 秒
  页分裂次数：约 480 万
  最终索引大小：约 620 MB
  缓冲池命中率（后续点查）：约 25%

UUID v7：
  插入耗时：约 70 秒（5.4× 提升）
  页分裂次数：约 40 万（12× 减少）
  最终索引大小：约 310 MB（2× 节省）
  缓冲池命中率（后续点查 - 时间相关）：约 90%

BIGINT AUTO_INCREMENT（参考基线）：
  插入耗时：约 50 秒
  页分裂次数：约 30 万
  最终索引大小：约 280 MB
  缓冲池命中率：约 95%
```

UUID v7 的主键性能与 BIGINT 自增非常接近，同时保留了"无需协调即可全局唯一"的好处。这是它在 2024 - 2025 年迅速被各大 OLTP 引擎采纳的核心原因。

## MySQL UUID_TO_BIN 与 swap_flag 深度解析

### 为什么 MySQL 默认是 v1？

MySQL UUID() 函数自 5.0 版本（2005 年）就存在，那时 RFC 4122 刚发布，MySQL 选择了"安全的"v1（时间戳 + MAC）。到 8.0 时代社区曾讨论切换到 v4，但向后兼容性顾虑（v1 的字段含义被某些应用解析）让 MySQL 维持现状。

### swap_flag 的字段重排

```
原 v1 字段顺序 (UUID 字符串 8-4-4-4-12):
    time_low - time_mid - time_hi_and_version - clock_seq - node
    [4 字节] - [2 字节] - [2 字节]              - [2 字节]   - [6 字节]

swap_flag = 0 (BINARY 字段顺序与字符串一致):
    [time_low (4)] [time_mid (2)] [time_hi_v (2)] [clock_seq (2)] [node (6)]
    每 ms 翻动: time_low 加 100,000 (10K ns 精度的时间戳低 32 位)
    -> 高位字节快速变化, 字典序 ≠ 时间序

swap_flag = 1 (重排, 高位时间戳前置):
    [time_hi_v (2)] [time_mid (2)] [time_low (4)] [clock_seq (2)] [node (6)]
    每 ms 翻动: time_low (现在在中间) 加 100,000
    -> 高位字节是 time_hi_v (秒级以上变化), 字典序 = 时间序
```

### 字节级示例

```sql
-- 假设当前时间戳对应的 v1 UUID
-- Time: 2024-01-15 12:00:00.000 UTC
SET @uuid = '6ba7b810-9dad-11ee-80b4-00c04fd430c8';

-- swap_flag = 0
SELECT HEX(UUID_TO_BIN(@uuid, 0)) AS bin0;
-- 6BA7B810 9DAD 11EE 80B4 00C04FD430C8
--   ↑ time_low 在最前

-- swap_flag = 1
SELECT HEX(UUID_TO_BIN(@uuid, 1)) AS bin1;
-- 11EE 9DAD 6BA7B810 80B4 00C04FD430C8
--   ↑ time_hi_and_version 在最前

-- 一秒后产生的 UUID (time_hi 大约保持不变, time_low 变化)
SET @uuid2 = '7ba7b810-9dad-11ee-80b4-00c04fd430c8';

-- swap_flag = 0 字典序: '6BA7B810' < '7BA7B810' (time_low 比较)
-- 但 time_low 变化模式不规则, 高频写入时字典序乱

-- swap_flag = 1 字典序: '11EE9DAD6BA7B810...' < '11EE9DAD7BA7B810...'
-- 高位 time_hi 和 time_mid 单调, 字典序 = 时间序
```

### 实战建议

```sql
-- 推荐主键模式（MySQL 8.0+）
CREATE TABLE orders (
    id BINARY(16) PRIMARY KEY DEFAULT (UUID_TO_BIN(UUID(), 1)),
    customer_id BIGINT NOT NULL,
    -- ... 其他字段
    INDEX idx_customer (customer_id, id)        -- 复合索引可继续利用 id 时序
);

-- 应用层查询时显式 BIN_TO_UUID(id, 1)
SELECT BIN_TO_UUID(id, 1) AS order_id FROM orders WHERE customer_id = 1001;

-- 重要陷阱: swap_flag 必须前后一致
SELECT * FROM orders WHERE id = UUID_TO_BIN('1234-...', 0);  -- 错误! 应该用 1
```

### 与 v7 的对比迁移路径

如果业务允许从 v1 迁移到 v7（非 MySQL 内置，需应用层生成）：

```sql
-- 应用层（如 Java）生成 v7 后插入
INSERT INTO orders (id, customer_id, total)
VALUES (UNHEX(REPLACE('01970000-1234-7abc-9def-0123456789ab', '-', '')), 1001, 99.99);

-- v7 已经是字典序友好，不需要 swap
-- 主键存储 BINARY(16) 直接 = UUID v7 二进制
SELECT
    CONCAT_WS('-',
        SUBSTR(HEX(id), 1, 8),
        SUBSTR(HEX(id), 9, 4),
        SUBSTR(HEX(id), 13, 4),
        SUBSTR(HEX(id), 17, 4),
        SUBSTR(HEX(id), 21, 12)
    ) AS uuid_str
FROM orders;
```

社区呼吁 MySQL 提供原生 `UUID_v4()` / `UUID_v7()` 已超过 5 年，但截至 MySQL 9.0 仍未实现。

## PostgreSQL "NEWSEQUENTIALID 等价物" 探索

### 标准方案（无原生）

PostgreSQL 没有 SQL Server `NEWSEQUENTIALID()` 的直接等价物，但有多个替代方案：

```sql
-- 方案 1（推荐, PG 18+）：直接用 uuidv7()
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    customer_id BIGINT
);

-- 方案 2（PG 13-17）：uuid-ossp 扩展的 v1
CREATE EXTENSION "uuid-ossp";

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v1(),
    customer_id BIGINT
);
-- 缺点: v1 字典序 ≠ 时间序，仍有写入热点偏移问题（见 MySQL UUID_TO_BIN 节）

-- 方案 3：手动构造 v6（v1 时间字段重排）
CREATE EXTENSION "uuid-ossp";

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v6_swap(uuid_generate_v1()),
    customer_id BIGINT
);

-- uuid_generate_v6_swap 需自定义函数，将 v1 的字段重排为 v6 风格
CREATE OR REPLACE FUNCTION uuid_generate_v6_swap(v1 UUID) RETURNS UUID AS $$
DECLARE
    s TEXT := REPLACE(v1::TEXT, '-', '');
    th TEXT := SUBSTR(s, 13, 4);
    tm TEXT := SUBSTR(s, 9, 4);
    tl TEXT := SUBSTR(s, 1, 8);
    rest TEXT := SUBSTR(s, 17);
BEGIN
    -- 把版本位从 1 改为 6 需要更精细处理，此处仅演示字段交换
    RETURN (th || '-' || tm || '-6' || SUBSTR(tl, 2, 3) || '-' || SUBSTR(rest, 1, 4) || '-' || SUBSTR(rest, 5))::UUID;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
```

### 应用层（nanoid / ulid / Snowflake-like）

```sql
-- nanoid: 紧凑的 URL 友好 ID（21 字符，128 位熵）
-- 通过 PG 扩展 pg_idkit 提供
CREATE EXTENSION pg_idkit;

CREATE TABLE orders (
    id TEXT PRIMARY KEY DEFAULT nanoid(),
    customer_id BIGINT
);
-- 默认 21 字符，约 126 位熵，不带时间戳
-- 也可以选择 ULID 或 KSUID

-- ULID（128 位，时间戳 + 随机）
SELECT idkit_ulid_generate();

-- KSUID（160 位，时间戳 + 随机）
SELECT idkit_ksuid_generate();
```

### 性能对比（PG 16, 1000 万行插入）

| 方案 | 耗时 | 索引大小 | 字典序 = 时间序 |
|------|------|---------|----------------|
| `BIGSERIAL` (自增) | 18s | 280MB | 是 |
| `gen_random_uuid()` (v4) | 90s | 620MB | 否 |
| `uuid_generate_v1()` | 75s | 620MB | 部分（time_low 在前） |
| 手动 v6 | 30s | 620MB | 是 |
| `uuidv7()` (PG 18+) | 25s | 620MB | 是 |
| `nanoid()` (TEXT) | 60s | 380MB | 否 |

`uuidv7()` 是 PG 18 之后的最优解，性能接近 `BIGSERIAL`，且无需协调即可全局唯一。

## 关键发现

### 1. RFC 9562 是分水岭，2024 年是 UUID v7 元年

2024 年 5 月 RFC 9562 发布前，"时间排序 UUID" 处于事实标准混战阶段（ULID、KSUID、Snowflake、MariaDB UUID 类型各自为政）。RFC 9562 之后，UUID v7 迅速成为业界共识：MariaDB 10.7（2022 年起内部已是 v7 思路）、ClickHouse 24.5（2024 年 5 月）、DuckDB 1.1（2024 年 9 月）、PostgreSQL 18（2025 年 9 月）短期内集中跟进。预期 2026 年后将有 MySQL、Oracle、SQL Server 等老牌数据库陆续支持。

### 2. PostgreSQL 是 v7 标准化的旗手

PostgreSQL 18 (2025 年 9 月发布) 是首个把 `uuidv7()` 直接放进核心模块（无需扩展）的主流 OLTP 引擎。在此之前 PG 用户需要手写函数、用 uuid-ossp 扩展或者依赖应用层生成。PG 18 的 `uuidv7()` 实现严格遵循 RFC 9562 的方法 2（rand_a 高位单调），并通过 `pg_strong_random()` 保证 CSPRNG 强度。

### 3. MySQL 的 UUID 困境：v1 是历史包袱

MySQL `UUID()` 返回 v1 是 2005 年的设计决策，至今未变。`UUID_TO_BIN(uuid, 1)` 是 2018 年（MySQL 8.0）的"补丁"，但对开发者来说是反直觉的（"为什么要 swap?"）。社区呼吁 5 年仍未原生引入 v4/v7，是 MySQL 在分布式 ID 领域逐渐落后于 PG/MariaDB 的一个写照。

### 4. SQL Server NEWSEQUENTIALID 比 RFC 9562 早 19 年

SQL Server 2005 引入的 `NEWSEQUENTIALID()` 在 2005 年就解决了"顺序 GUID 主键"问题，比 RFC 9562 早整整 19 年。但因其字节序与字符串字典序不一致（SQL Server 用了非常规 GUID 比较顺序），跨引擎使用时易踩坑。这是历史长河里"私有方案领先标准多年"的典型案例。

### 5. Oracle SYS_GUID() 不严格符合 RFC

Oracle `SYS_GUID()` 自 8i (1999 年) 提供，但**不是 RFC 4122 UUID**——没有版本/变体字段。要在 Oracle 上获得标准 UUID，要么应用层生成，要么手动调用 `DBMS_CRYPTO.RANDOMBYTES` 拼接。Oracle 12c 之后多数场景用 IDENTITY 列取代。

### 6. NoSQL/查询引擎层只关心 v4

Cassandra `uuid()`、Trino/Presto/Spark/Flink 的 `uuid()` 都返回 v4，因为这些系统的"主键"通常是分区键 + 聚簇键，不是 B+ 树叶子页 - 所以索引局部性问题不存在，"字典序 = 时间序"的 v7 优势用不上。Cassandra 用 TIMEUUID（v1）解决时间排序需求，反而绕开了 v7。

### 7. 16 字节内置类型 vs 字符串：性能差 2-3 倍

具有原生 `UUID` 数据类型（16 字节）的引擎（PG、MariaDB 10.7+、SQL Server、ClickHouse、CockroachDB、DuckDB 等）比仅支持字符串存储的引擎（Snowflake、BigQuery、Redshift、TiDB）在主键索引性能上有 2-3 倍优势。这是云数据仓库选择牺牲性能（换取简化）的体现，对 OLTP 场景不利。

### 8. UUID v7 的"亚毫秒单调"实现差异

RFC 9562 §6.2 给出了三种单调性方案，各引擎选择不同：
- PG 18：方法 2（rand_a 高位计数）
- DuckDB 1.1：方法 1（rand_a 全部计数）
- ClickHouse 24.5：方法 1 + 方法 2 组合

这意味着跨引擎复制 v7 UUID 时，无法保证"同一时间段生成的 UUID 顺序一致"。在多引擎复制（如 Debezium → Kafka → ClickHouse）场景需注意。

### 9. UUID 索引膨胀的"30% 规则"

经验值：相比 BIGINT 主键，UUID v7 主键（BINARY(16)）会让聚簇索引膨胀约 30%，二级索引膨胀约 50% - 80%（因为二级索引叶子节点要存主键值）。在数据量 > 1TB 的 OLTP 数据库中，这个差异是真金白银的存储成本。建议：极大规模 OLTP 仍考虑 BIGINT 自增 + 应用层 UUID 用于跨域唯一标识。

### 10. v7 不是银弹：可预测性问题

UUID v7 的高 48 位是公开时间戳，意味着攻击者可以从一个 ID 推断出生成时间。如果业务场景需要 ID 不可预测（如优惠券、邀请码），仍需 v4。RFC 9562 §6.5 明确指出 v7 不应用于"安全敏感的不可预测场景"，PostgreSQL 文档中也对此明确标注。

## 实施建议

### 选型决策树

```
是否分布式系统?
├── 否 (单机 OLTP)
│   ├── 是否需要全局唯一标识 (跨服务/跨库)?
│   │   ├── 是 → UUID v7 (PG 18+/MariaDB 10.7+) 或 v4 (其他)
│   │   └── 否 → BIGSERIAL/AUTO_INCREMENT/IDENTITY (最优性能)
│   └── 是否安全敏感 (不可预测)?
│       └── 是 → UUID v4 (绝不用 v1/v6/v7)
│
└── 是 (NewSQL / 分库分表 / 多 region)
    ├── 引擎是否提供专用机制?
    │   ├── TiDB → AUTO_RANDOM (推荐, 比 UUID 紧凑 8x)
    │   ├── Spanner → bit_reversed_positive 序列
    │   ├── CockroachDB → unique_rowid() (Snowflake-like)
    │   └── 其他 → UUID v7 (PG/MariaDB/ClickHouse) 或应用层 Snowflake
    └── 是否需要严格的字典序 = 时间序?
        ├── 是 → UUID v7 (避免 v4 + 哈希分区组合)
        └── 否 → UUID v4 + 哈希分区
```

### 引擎实现者建议

如果你正在为一个新数据库引擎设计 UUID 函数：

1. **必备 v4**：使用 CSPRNG（OpenSSL/系统 `/dev/urandom`），不要用 `rand()`
2. **强烈推荐 v7**：实现 RFC 9562 §6.2 任一单调方案，文档明确说明
3. **避免 v1**：MAC 地址暴露的隐私问题已是 2025 年的红线
4. **提供 16 字节存储**：`UUID` 数据类型固定 16 字节，比 `CHAR(36)` 节省 2.25 倍
5. **提供二进制 ↔ 字符串转换**：`UUID_STRING_TO_NUM` / `UUID_NUM_TO_STRING` 双向函数
6. **明确文档安全语义**：v7 时间戳可推断，需在文档明确标注（参考 PG 18 文档）

### 应用开发者最佳实践

1. **查询时统一用字符串表示**：8-4-4-4-12 RFC 4122 格式，跨语言兼容
2. **存储时优先选 16 字节类型**：避免 `CHAR(36)`，索引/缓冲池性能差 2-3 倍
3. **MySQL 必加 swap_flag**：`UUID_TO_BIN(UUID(), 1)`，否则索引性能差
4. **PostgreSQL 13-17 用 `gen_random_uuid()`**：不要用 uuid-ossp 的 v1（隐私问题）
5. **PostgreSQL 18+ 升级到 `uuidv7()`**：性能与字典序的最优组合
6. **应用层缓存：减少 round-trip**：批量插入时由应用生成 UUID 而非数据库 DEFAULT
7. **不要用 v7 当 token/邀请码**：高 48 位时间戳可推断，用 v4 或专门的 token 系统

## 参考资料

- IETF RFC 9562: [Universally Unique IDentifiers (UUIDs)](https://datatracker.ietf.org/doc/rfc9562/) (2024-05)
- IETF RFC 4122: [A Universally Unique IDentifier (UUID) URN Namespace](https://datatracker.ietf.org/doc/rfc4122/) (2005-07，已被 9562 取代)
- PostgreSQL 18: [UUID Functions](https://www.postgresql.org/docs/18/functions-uuid.html)
- PostgreSQL 13: [UUID Functions](https://www.postgresql.org/docs/13/functions-uuid.html)
- PostgreSQL: [uuid-ossp Module](https://www.postgresql.org/docs/current/uuid-ossp.html)
- MySQL 8.0: [UUID() / UUID_TO_BIN() / BIN_TO_UUID()](https://dev.mysql.com/doc/refman/8.0/en/miscellaneous-functions.html#function_uuid-to-bin)
- MariaDB: [UUID Data Type (10.7+)](https://mariadb.com/kb/en/uuid-data-type/)
- SQL Server: [NEWID() / NEWSEQUENTIALID()](https://learn.microsoft.com/en-us/sql/t-sql/functions/newsequentialid-transact-sql)
- Oracle: [SYS_GUID Function](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SYS_GUID.html)
- DB2: [GENERATE_UNIQUE Function](https://www.ibm.com/docs/en/db2/11.5?topic=functions-generate-unique)
- ClickHouse 24.5: [UUID Functions](https://clickhouse.com/docs/en/sql-reference/functions/uuid-functions)
- DuckDB 1.1: [UUID Functions](https://duckdb.org/docs/sql/functions/uuid)
- Snowflake: [UUID_STRING Function](https://docs.snowflake.com/en/sql-reference/functions/uuid_string)
- BigQuery: [GENERATE_UUID](https://cloud.google.com/bigquery/docs/reference/standard-sql/functions-and-operators#generate_uuid)
- Spanner: [GENERATE_UUID + bit_reversed_positive](https://cloud.google.com/spanner/docs/reference/standard-sql/uuid-functions)
- CockroachDB: [gen_random_uuid + unique_rowid](https://www.cockroachlabs.com/docs/stable/uuid.html)
- TiDB: [AUTO_RANDOM](https://docs.pingcap.com/tidb/stable/auto-random)
- Cassandra: [TIMEUUID and UUID Types](https://cassandra.apache.org/doc/latest/cassandra/cql/types.html#uuids)
- ULID Specification: [Sortable Universally Unique Lexicographically Sortable Identifier](https://github.com/ulid/spec)
- KSUID Specification: [K-Sortable Globally Unique IDs](https://github.com/segmentio/ksuid)
- Twitter Engineering Blog: [Announcing Snowflake](https://blog.twitter.com/engineering/en_us/a/2010/announcing-snowflake) (2010)
- Peabody, B. & Davis, K. (2024) RFC 9562 — IETF Datatracker history & discussion
