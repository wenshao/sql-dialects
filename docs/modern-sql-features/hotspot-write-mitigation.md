# 热点写入缓解 (Write Hot-Spot Mitigation)

单调递增的自增主键是关系型数据库最自然的 ID 选择，但在分布式系统中，它会把所有写入推向同一个分片、同一个 region、同一条 B+ 树叶子页——形成写热点。热点会让集群的吞吐被一个节点的磁盘与 CPU 卡住，让扩容失效，让事务相互阻塞。不同的数据库给出了截然不同的应对方案：从 UUID v4 的完全随机，到 UUID v7 / Snowflake ID 的有序随机混合，从 TiDB AUTO_RANDOM 的分片位前缀，到 Spanner 的比特反转序列，再到 HBase 的哈希盐前缀——这些技术背后是同一个问题的多种权衡。

## 没有 SQL 标准：完全厂商特定

与 TABLESAMPLE、窗口函数等特性不同，"写热点缓解"本质上是分布式系统底层架构问题，**SQL 标准中没有任何相关规定**。每个引擎根据自己的存储模型（B+ 树、LSM-tree、分布式 KV）给出完全不同的答案：

- OLTP 单机引擎（MySQL、PostgreSQL）通常只提供 UUID 函数，由应用自行选择随机 ID 策略
- NewSQL 分布式引擎（TiDB、CockroachDB、Spanner）内置了专门的热点缓解机制
- 列存 / MPP 引擎（ClickHouse、Snowflake）由于批量写入模型通常没有此问题
- NoSQL（HBase、Cassandra）要求应用层设计 rowkey/partition key 来分散写入

## 支持矩阵（综合）

### 随机 ID 与有序 UUID

| 引擎 | 随机 UUID (v4) | 有序 UUID/ID (v6/v7/Snowflake/ULID) | 内置原生函数 | 版本 |
|------|---------------|-------------------------------------|------------|------|
| PostgreSQL | `gen_random_uuid()` | `uuidv7()` (v18) / 扩展 | 是 | 13+ / 18+ |
| MySQL | `UUID()` | `UUID_TO_BIN(UUID(), 1)` | 是（重排） | 8.0+ |
| MariaDB | `UUID()` | `UUID() v7` 自动有序 | 是 | 10.7+ |
| SQLite | `randomblob(16)` 模拟 | 扩展 | -- | -- |
| Oracle | `SYS_GUID()` | -- | -- | 9i+ |
| SQL Server | `NEWID()` | `NEWSEQUENTIALID()` | 是 | 2005+ |
| DB2 | `GENERATE_UNIQUE()` | -- | 部分 | 9.7+ |
| Snowflake | `UUID_STRING()` | -- | -- | GA |
| BigQuery | `GENERATE_UUID()` | -- | -- | GA |
| Redshift | `CAST(...)` 模拟 | -- | -- | -- |
| DuckDB | `uuid()` | `uuidv7()` | 是 | 1.1+ |
| ClickHouse | `generateUUIDv4()` | `generateUUIDv7()` | 是 | 24.5+ |
| Trino | `uuid()` | -- | -- | GA |
| Presto | `uuid()` | -- | -- | 0.145+ |
| Spark SQL | `uuid()` | -- | -- | 2.3+ |
| Hive | `reflect("java.util.UUID","randomUUID")` | -- | -- | -- |
| Flink SQL | `UUID()` | -- | -- | 1.11+ |
| Databricks | `uuid()` | -- | -- | GA |
| Teradata | -- | -- | -- | -- |
| Greenplum | `gen_random_uuid()` | -- | 继承 PG | -- |
| CockroachDB | `gen_random_uuid()` | `unique_rowid()` | 是 | GA |
| TiDB | `UUID()` | `AUTO_RANDOM` / Snowflake | 是 | 3.1+ |
| OceanBase | `UUID()` | `SEQUENCE + NOORDER` | 部分 | 2.2+ |
| YugabyteDB | `gen_random_uuid()` | 哈希分区 (HASH) | 是 | GA |
| SingleStore | -- | 分片键 | -- | -- |
| Vertica | `UUID_GENERATE()` | -- | -- | GA |
| Impala | `uuid()` | -- | -- | 2.5+ |
| StarRocks | `uuid()` | -- | -- | 2.4+ |
| Doris | `uuid()` | -- | -- | 1.2+ |
| MonetDB | `uuid()` | -- | -- | GA |
| CrateDB | 应用层 | 哈希分片 | -- | -- |
| TimescaleDB | `gen_random_uuid()` | 继承 PG | 继承 PG | -- |
| QuestDB | -- | `long_sequence()` | -- | -- |
| Exasol | -- | -- | -- | -- |
| SAP HANA | `SYSUUID` | -- | -- | GA |
| Informix | -- | -- | -- | -- |
| Firebird | `GEN_UUID()` | -- | -- | 2.5+ |
| H2 | `RANDOM_UUID()` | -- | -- | GA |
| HSQLDB | `UUID()` | -- | -- | GA |
| Derby | -- | -- | -- | -- |
| Amazon Athena | `uuid()` | -- | 继承 Trino | -- |
| Azure Synapse | `NEWID()` | -- | 继承 SQL Server | -- |
| Google Spanner | `GENERATE_UUID()` | 比特反转序列 | 是 | 2022+ |
| Materialize | `gen_random_uuid()` | -- | 继承 PG | -- |
| RisingWave | `gen_random_uuid()` | -- | 继承 PG | -- |
| InfluxDB (SQL) | -- | 时序自然有序 | -- | -- |
| DatabendDB | `uuid()` | -- | -- | GA |
| Yellowbrick | `uuid_generate_v4()` | -- | 继承 PG | -- |
| Firebolt | `gen_random_uuid()` | -- | -- | GA |

### 分布式热点缓解机制

| 引擎 | 哈希分区 | Region 自动分裂 | 比特反转 | AUTO_RANDOM | 分片位前缀 | 盐前缀 | 版本 |
|------|---------|---------------|---------|-------------|----------|--------|------|
| PostgreSQL | `HASH` 分区 | -- | -- | -- | -- | 手动 | 11+ |
| MySQL | `HASH` 分区 | -- | -- | -- | -- | 手动 | 5.5+ |
| MariaDB | `HASH` 分区 | -- | -- | -- | -- | 手动 | 5.5+ |
| Oracle | 哈希分区 | -- | `REVERSE` 索引 | -- | -- | 手动 | 8i+ |
| SQL Server | 哈希分区 | -- | -- | -- | -- | 手动 | GA |
| TiDB | -- | 是（基于 Region） | -- | `AUTO_RANDOM` | `SHARD_ROW_ID_BITS` | -- | 3.1+ |
| CockroachDB | `PARTITION BY HASH` | 是 | -- | `unique_rowid()` | -- | -- | 22.1+ |
| Spanner | `bit_reverse()` | 是 | `BIT_REVERSED_POSITIVE` | -- | -- | -- | 2022+ |
| YugabyteDB | `HASH` 默认分区 | 是 | -- | -- | -- | -- | GA |
| OceanBase | 哈希分区 | 是 | -- | -- | -- | -- | 2.0+ |
| SingleStore | 哈希分片 | 是 | -- | -- | -- | -- | GA |
| HBase | 手动 | 是（auto-split） | 手动 | -- | -- | 是（官方推荐） | 0.90+ |
| Cassandra | 分区键哈希 | -- | -- | -- | -- | 分桶策略 | GA |
| ScyllaDB | 分区键哈希 | -- | -- | -- | -- | 分桶策略 | GA |
| Snowflake | 微分区 | 自动 | -- | -- | -- | -- | GA |
| BigQuery | 聚簇 | -- | -- | -- | -- | -- | GA |
| ClickHouse | 分布式表分片键 | -- | -- | -- | -- | -- | GA |
| DB2 | `DISTRIBUTE BY HASH` | -- | -- | -- | -- | -- | DPF |
| Greenplum | `DISTRIBUTED BY` | -- | -- | -- | -- | -- | GA |
| Vertica | 段化投影 | -- | -- | -- | -- | -- | GA |
| Teradata | 哈希 AMP | -- | -- | -- | -- | -- | GA |
| Doris | `DISTRIBUTED BY HASH` | 是 | -- | -- | -- | -- | GA |
| StarRocks | `DISTRIBUTED BY HASH` | 是 | -- | -- | -- | -- | GA |

> 统计: 约 20 个引擎提供有序 UUID / 分布式 ID 原生能力, 约 15 个分布式引擎提供哈希分区或 region 自动分裂, 约 5 个引擎提供专门的"分片位"/"比特反转"机制 (TiDB, Spanner, Oracle, CockroachDB, YugabyteDB)。

## 为什么单调递增 ID 会造成写热点

### B+ 树聚簇索引的"最右边"问题

InnoDB 和大多数关系型数据库的聚簇索引基于 B+ 树，行数据按主键顺序物理存储：

```
B+ 树叶子层（按 id 升序）:
[id 1-100] → [id 101-200] → [id 201-300] → ... → [id 9001-9100]
                                                  ↑ 所有新插入都来这里
```

如果主键是自增序列 (1, 2, 3, ...)，所有新行都追加到索引的最右叶子页：

1. **缓冲池热点**：最右叶子页永远是热点，其他页的缓存被浪费
2. **行锁争用**：高并发插入时，多个事务竞争同一页的 X 锁
3. **SMO（Structure Modification Operation）风暴**：页分裂集中在一个位置
4. **checkpoint 压力**：脏页集中刷盘
5. **Purge 线程落后**：单页修改记录过多

### 分布式 KV 存储的 Region 热点

TiDB / CockroachDB / YugabyteDB 等分布式 SQL 引擎将数据切成 Region（默认 64MB - 96MB），每个 Region 由 Raft 组维护，只有 Leader 节点接收写入：

```
自增主键的 Region 分布:
Region 1 [id < 1000]   → Node A (leader) - 冷
Region 2 [id 1000-2000] → Node B (leader) - 冷
Region 3 [id 2000-3000] → Node C (leader) - 冷
...
Region N [id > 99000]   → Node X (leader) - 所有写入都来这里 (HOT!)
```

新插入集中在 Region N 的 Leader 上，导致：
- Node X 的 CPU 和磁盘 I/O 打满，其他节点闲置
- Raft 日志复制带宽集中在 Node X 的 follower
- Region 分裂后（例如 120MB 时），新 Region 又成为下一个热点
- 扩容新节点无法缓解——因为热点不会自动迁移到新节点

### LSM-tree 的写放大

RocksDB 等 LSM 存储虽然写入 MemTable 很快，但 compaction 阶段需要把 SST 文件合并排序：

- 顺序 Key 插入：compaction 效率高，但整个 level-0 只有一个文件是热的
- 随机 Key 插入：compaction 工作更均匀，但写放大更大（需要跨多个 SST 合并）

高吞吐场景下，RocksDB 的顺序写热点会让 LSM compaction 队列严重积压。

### HBase RegionServer 的"最后一个 Region"

HBase 的 RowKey 是字典序，新 Region 总是出现在最右边。默认配置下，一张新表只有一个 Region，所有写入都压到一个 RegionServer 直到分裂：

```
表刚创建:  [Region 1: (-∞, +∞)] → RegionServer A (100% 写)
运行一段时间:
  [Region 1: (-∞, row_5000)] → RegionServer A (冷)
  [Region 2: [row_5000, +∞)] → RegionServer B (100% 写)
```

新 Region 的字典序后缀永远是最大，热点永远跟着最右 Region 走。这就是 HBase 官方文档反复强调"RowKey 设计决定性能"的原因。

## UUID v4（完全随机 128 位）

### 原理

UUID v4 由 122 位随机数 + 6 位版本/变体标记组成，碰撞概率极低（每秒产生 10 亿个 UUID 持续 85 年才有 50% 概率出现一次碰撞）。

```sql
-- PostgreSQL (v13+, 之前需 pgcrypto)
SELECT gen_random_uuid();
-- 结果: 8f14e45f-ceea-467a-a5f7-4b0ab7c4dd3e

-- MySQL 8.0+
SELECT UUID();
-- 结果: ba5d2b71-8ea0-11ee-b9d1-0242ac120002 (注意这是 v1，基于时间戳)

-- SQL Server
SELECT NEWID();

-- Oracle
SELECT SYS_GUID() FROM DUAL;

-- ClickHouse
SELECT generateUUIDv4();
```

### 写入性能问题

UUID v4 解决了热点问题——每次插入随机命中 B+ 树的任意叶子页，但带来了新问题：

**1. 索引碎片化**：每次插入都可能触发任意位置的页分裂，SMO 频繁：
- 顺序插入 1000 万行：约 5 万次页分裂
- UUID v4 插入 1000 万行：约 500 万次页分裂（10 倍）

**2. 缓冲池污染**：UUID 分布广，热数据无法集中在缓冲池：
- 100GB 表、10GB 缓冲池：顺序主键命中率 > 95%
- 100GB 表、10GB 缓冲池：UUID v4 命中率 < 10%

**3. 索引体积膨胀**：
- BIGINT 主键：8 字节
- UUID（CHAR(36)）：36 字节
- UUID（BINARY(16)）：16 字节，仍比 BIGINT 大 2 倍

**4. JOIN 与缓存失效**：外键列也是 16 字节，索引和内存都 2 倍开销。

### 性能实测（InnoDB, 单机, 1000 万行插入）

| 主键类型 | 耗时 | IOPS | 主键索引大小 |
|---------|------|------|------------|
| BIGINT AUTO_INCREMENT | 120s | 83k | 280MB |
| UUID v4 (BINARY(16)) | 850s | 12k | 620MB |
| UUID v4 (CHAR(36)) | 1240s | 8k | 1.1GB |
| UUID v7 (BINARY(16)) | 180s | 56k | 310MB |

## UUID v7 / Snowflake ID / ULID（有序随机混合）

### 核心思想

`时间戳 | 随机数` 布局：高位保持时间递增（保留局部性），低位随机（分散热点）。

### UUID v7（IETF RFC 9562, 2024 标准化）

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

- 48 bit: 毫秒级 Unix 时间戳 (足够用到 10889 年)
- 4 bit:  版本号 (0b0111 = 7)
- 12 bit: rand_a (也可用作亚毫秒精度计数器)
- 2 bit:  变体标记
- 62 bit: rand_b (随机数)
```

特性：
- 128 位，与 UUID v4 同宽度
- 单调递增（毫秒级，同一毫秒内可能乱序）
- 字典序 = 时间序
- 可直接用于 B+ 树主键，避免随机 IO

### Snowflake ID（Twitter, 2010）

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|0|                    timestamp_ms                             |
|                    (41 bit)                  |   datacenter   |
|                                              |    (5 bit)     |
|  worker_id (5 bit)|       sequence (12 bit)                   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

总计 63 位（留出符号位，保证正数）:
- 1 bit:  保留位 (始终为 0)
- 41 bit: 毫秒时间戳 (约 69 年, 以 2010 为 epoch 到 2079)
- 10 bit: 机器 ID (5 bit 数据中心 + 5 bit worker, 共 1024 节点)
- 12 bit: 序列号 (同毫秒内同节点可产生 4096 个 ID)
```

特性：
- 64 位（BIGINT 兼容），仅 v4 的一半大小
- 全局单调递增（不同节点之间时钟同步时）
- 最大 QPS: 1024 节点 × 4096 seq × 1000 ms = 4096 亿/秒理论上限
- 依赖时钟不回拨（时钟回拨检测与等待是实现重点）

### ULID（Universally Unique Lexicographically Sortable Identifier）

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      32_bit_uint_time_high                    |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|     16_bit_uint_time_low      |       16_bit_uint_random      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       32_bit_uint_random                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       32_bit_uint_random                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

总计 128 位:
- 48 bit: 毫秒时间戳 (直到 10889 年)
- 80 bit: 随机数
字符串编码使用 Crockford Base32 (26 字符, URL 安全, 不含 I/L/O/U)
```

特性：
- 128 位，URL 友好编码（26 字符字符串）
- 字典序 = 时间序
- 同毫秒内用单调性保证严格递增（同一生成器内）
- 设计早于 UUID v7，但功能上被 v7 取代

### 三者对比

| 特性 | UUID v4 | UUID v7 | Snowflake ID | ULID |
|------|---------|---------|-------------|------|
| 位宽 | 128 bit | 128 bit | 64 bit | 128 bit |
| 时间戳 | 无 | 48 bit ms | 41 bit ms | 48 bit ms |
| 随机位 | 122 bit | 74 bit | 12 bit seq | 80 bit |
| 机器标识 | 无 | 无 | 10 bit | 无 |
| 时钟回拨敏感 | 不 | 不 | 敏感 | 不 |
| 字典序 = 时间序 | 不 | 是 | 是 | 是 |
| 需协调 | 不需 | 不需 | 需 Worker 分配 | 不需 |
| 标准化 | RFC 4122 | RFC 9562 (2024) | Twitter 开源 | 社区规范 |
| 数据库原生 | 多数支持 | PG 18, MariaDB 10.7, DuckDB, ClickHouse | TiDB, 美团 Leaf | 少数 |

### PostgreSQL 18 的 uuidv7()

```sql
-- PostgreSQL 18（2025 年 9 月发布）引入原生 uuidv7()
SELECT uuidv7();
-- 结果: 0197a3f1-9c42-7f8e-a9b2-1c3d4e5f6789

-- 作为主键（取代 BIGSERIAL）
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    customer_id BIGINT NOT NULL,
    total NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- UUID v7 保证按插入顺序创建，可按范围查询最近数据
SELECT * FROM orders
WHERE id > uuidv7_from_timestamp(NOW() - INTERVAL '1 hour')
ORDER BY id DESC LIMIT 100;
```

### MySQL 8.0 的 UUID_TO_BIN(uuid, swap_flag)

```sql
-- MySQL 默认 UUID() 是 v1（时间戳在低位，排序不友好）:
SELECT UUID();
-- ba5d2b71-8ea0-11ee-b9d1-0242ac120002
--    ↑time_low  ↑time_mid  ↑time_hi

-- 字节布局（36 字符 = 16 字节十六进制）:
--   time_low (4 bytes) | time_mid (2 bytes) | time_hi_version (2 bytes) | ...
--
-- 问题: time_low 在最前面, 每毫秒它变化最剧烈, 所以 UUID 看起来"乱"

-- UUID_TO_BIN(uuid, 1) 交换前三段字节顺序:
--   time_hi_version | time_mid | time_low | clock_seq | node
-- 结果: 高位时间戳在前, 字节序 = 时间序
SELECT UUID_TO_BIN(UUID(), 1);

-- 应用于主键设计:
CREATE TABLE orders (
    id BINARY(16) PRIMARY KEY DEFAULT (UUID_TO_BIN(UUID(), 1)),
    customer_id BIGINT NOT NULL,
    total DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 插入
INSERT INTO orders (customer_id, total) VALUES (1001, 99.99);

-- 查询时转回 UUID 字符串
SELECT BIN_TO_UUID(id, 1) AS order_id, customer_id, total FROM orders;

-- 对比 swap 前后的字典序:
SELECT HEX(UUID_TO_BIN('ba5d2b71-8ea0-11ee-b9d1-0242ac120002', 0));
-- BA5D2B718EA011EEB9D10242AC120002  (time_low 在前, 乱序)
SELECT HEX(UUID_TO_BIN('ba5d2b71-8ea0-11ee-b9d1-0242ac120002', 1));
-- 11EE8EA0BA5D2B71B9D10242AC120002  (time_hi 在前, 按时间排序)
```

### MariaDB 10.7 的 UUID v4/v7

```sql
-- MariaDB 10.7 引入 UUID 数据类型, 并默认使用 UUID v1 (时间戳) 保证单调性
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT UUID(),
    total DECIMAL(10,2)
);

-- UUID 类型内部按"时间序"字节排列（MariaDB 在存储时 swap byte order）
INSERT INTO orders (total) VALUES (99.99);
```

### DuckDB / ClickHouse

```sql
-- DuckDB 1.1+
SELECT uuidv7();

-- ClickHouse 24.5+
SELECT generateUUIDv7();

-- 作为主键
CREATE TABLE events (
    id UUID DEFAULT generateUUIDv7(),
    payload String
) ENGINE = MergeTree() ORDER BY id;
```

## 各数据库原生方案详解

### MySQL：UUID() 与 UUID_TO_BIN(uuid, 1)

MySQL 8.0 之前，UUID 性能是个历史痛点。8.0 引入 UUID_TO_BIN 的 swap_flag 后：

```sql
-- 推荐实践（MySQL 8.0+）
CREATE TABLE events (
    id BINARY(16) NOT NULL PRIMARY KEY DEFAULT (UUID_TO_BIN(UUID(), 1)),
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_created (created_at)
) ENGINE=InnoDB;

-- 应用层生成：
-- Java: UUID uuid = UUID.randomUUID(); bytes = toBinary(uuid, true);
-- Python: uuid6.uuid7().bytes

-- 常见反模式: CHAR(36) 存储 UUID
-- 索引大小膨胀 2 倍, JOIN 性能下降 50%
-- 应该: BINARY(16) + UUID_TO_BIN(uuid, 1)
```

### PostgreSQL：gen_random_uuid() 与 uuidv7()

```sql
-- PostgreSQL 13+ 内置 (来自 pgcrypto)
SELECT gen_random_uuid();

-- PostgreSQL 18+ 原生 v7
SELECT uuidv7();

-- 推荐表设计
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT uuidv7(),  -- PG 18+
    -- id UUID PRIMARY KEY DEFAULT gen_random_uuid(),  -- PG 13-17
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 利用 v7 的时间戳特性做时间范围查询
SELECT * FROM events
WHERE id >= '01930000-0000-7000-0000-000000000000'::uuid  -- 某个时间戳对应的 v7 最小值
  AND id <  '01940000-0000-7000-0000-000000000000'::uuid;

-- 扩展方案（PG 13-17）
CREATE EXTENSION "uuid-ossp";
SELECT uuid_generate_v4();  -- 等价于 gen_random_uuid()
SELECT uuid_generate_v1mc();  -- 带 MAC 随机化的 v1
```

### SQL Server：NEWID() vs NEWSEQUENTIALID()

```sql
-- NEWID(): 完全随机, 造成页分裂
CREATE TABLE orders_random (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    amount DECIMAL(10,2)
);

-- NEWSEQUENTIALID(): 每次调用返回比上一次"更大"的 GUID (按字典序)
-- 注意：仅在同一台机器上保证递增, 重启后可能跳跃
CREATE TABLE orders_seq (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWSEQUENTIALID(),
    amount DECIMAL(10,2)
);

-- 性能对比 (10M 行插入, SSD, SQL Server 2022):
--   NEWID():             约 180s, 页分裂次数 480 万
--   NEWSEQUENTIALID():   约 65s,  页分裂次数 45 万
--   IDENTITY (BIGINT):   约 40s,  页分裂次数 42 万

-- 限制：
-- - NEWSEQUENTIALID() 只能作为 DEFAULT 约束, 不能在 SELECT 中直接调用
-- - 重启服务或失败转移后, 序列起点会跳跃（防止可预测）
-- - 某些场景下仍有热点（最右叶子页）, 但比 NEWID() 好得多
```

### Oracle：SYS_GUID() 与反向键索引

```sql
-- SYS_GUID() 生成 16 字节 RAW
SELECT SYS_GUID() FROM DUAL;
-- 结果: A8B4D5E6F71A4B2C9D8E7F6A5B4C3D2E

CREATE TABLE orders (
    id RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    amount NUMBER(10,2)
);

-- Oracle 独有的反向键索引 (Reverse Key Index): 用于缓解递增主键热点
-- 原理: 存储时反转字节顺序, 让连续 ID 散布在 B+ 树各处
CREATE INDEX idx_orders_time ON orders (created_at) REVERSE;

-- 例如 created_at = 2024-01-01 10:00:00 的字节
--   原始:   0x07E80101100000
--   反转后: 0x0000001001E807
-- 连续的时间戳在反向索引中分散到不同叶子页

-- 注意: 反向索引不支持范围查询, 只能用于等值查询
```

### TiDB：AUTO_RANDOM（自 3.1 起）

TiDB 3.1（2019 年）引入 AUTO_RANDOM，专门解决分布式场景下自增主键的写热点问题。

```sql
-- 基本用法 (默认 5 shard bits)
CREATE TABLE orders (
    id BIGINT PRIMARY KEY AUTO_RANDOM,
    customer_id BIGINT,
    amount DECIMAL(10,2)
);

-- 显式指定 shard bits
CREATE TABLE orders (
    id BIGINT PRIMARY KEY AUTO_RANDOM(5),
    customer_id BIGINT,
    amount DECIMAL(10,2)
);

-- AUTO_RANDOM(S, R) 完整语法: S = shard bits, R = range bits (总位数)
CREATE TABLE orders (
    id BIGINT PRIMARY KEY AUTO_RANDOM(5, 54),
    customer_id BIGINT
);

-- 插入后查看生成的 ID
INSERT INTO orders (customer_id, amount) VALUES (1001, 99.99);
SELECT id FROM orders;
-- 结果: 3674937295934324737
-- 二进制: 0011 0011 | 0000 0000 0000 0000 ... 0000 0001
--          ↑shard=6  ↑sequence=1

-- 可以显式指定 id:
INSERT INTO orders (id, customer_id, amount) VALUES (100, 1002, 50.00);
```

**AUTO_RANDOM 的 Bit 布局**：

```
总 64 bit (BIGINT) = 1 sign bit + S shard bits + (63-S) sequence bits

默认 S=5:
 0  1-5       6-63
+-+---------+-----------+
|0|shard(5) |seq(58 bit)|
+-+---------+-----------+
    ↑
    随机生成 0-31, 把连续的 seq 打散到 32 个 region prefix

S=5 时:
  Region 分布: 2^5 = 32 个不同前缀
  最大 ID 数: 2^58 = 2.88 亿亿 (足够)
  
S=10 时 (高写负载):
  Region 分布: 2^10 = 1024 个不同前缀
  最大 ID 数: 2^53 = 9 千万亿
```

**AUTO_RANDOM 与 AUTO_INCREMENT 的关键区别**：

| 特性 | AUTO_INCREMENT | AUTO_RANDOM |
|------|---------------|-------------|
| 单调递增 | 是 | 否（高位随机，低位递增） |
| 可预测 | 是（知道 N 就知道 N+1） | 否 |
| 热点 | 严重（所有写入到最新 region） | 分散到 2^S 个 region |
| 支持 ALTER AUTO_INCREMENT | 是 | 否 |
| `LAST_INSERT_ID()` 可用 | 是 | 是 |
| 分布式友好 | 差 | 优秀 |

**启用 pre-split-region 进一步优化**：

```sql
-- 创建表时预分裂 region, 避免初始所有写都集中在第一个 region
CREATE TABLE orders (
    id BIGINT PRIMARY KEY AUTO_RANDOM(5),
    customer_id BIGINT
) PRE_SPLIT_REGIONS = 4;

-- 这会在创建表时立即分裂出 2^4 = 16 个 region
-- 刚创建的表就能承受高写入负载
```

### CockroachDB：unique_rowid()

CockroachDB 的 `unique_rowid()` 是内置伪主键生成器，专为分布式场景设计：

```sql
CREATE TABLE orders (
    id INT PRIMARY KEY DEFAULT unique_rowid(),
    customer_id INT,
    amount DECIMAL(10,2)
);

-- 查看生成的 ID
INSERT INTO orders (customer_id, amount) VALUES (1001, 99.99);
SELECT id FROM orders;
-- 结果: 891234567891234001
```

**unique_rowid() 的位布局**：

```
64 位 BIGINT:
  48 bit: HLC 时间戳 (Hybrid Logical Clock, 毫秒级)
  15 bit: 节点 ID (最多 32768 个节点)
   1 bit: 保留 (不用)

结果: 同一节点单调递增, 不同节点之间按时间顺序交错
关键: 节点 ID 在低位 → 连续调用 ID 的低 15 bit 变化大 → 分散写入
```

**与 AUTO_RANDOM 的对比**：

| 特性 | TiDB AUTO_RANDOM | CockroachDB unique_rowid() |
|------|-----------------|---------------------------|
| 位布局 | sign|shard|seq | HLC_time|node|reserved |
| 随机位位置 | 高位（影响 region 分布） | 低位（不影响分布，仅保证唯一） |
| 时间相关 | 否 | 是（HLC 时间戳） |
| 分散机制 | shard bits 打散 region | 本质是按节点分散 + HLC 保证唯一 |
| 支持用户指定 | 是 | 是 |

CockroachDB 也推荐 UUID v4 作为另一种主键选择，从官方文档看：
- `unique_rowid()`: 吞吐量高, 空间小 (8 字节), 但可能暴露节点数量
- `gen_random_uuid()`: 完全随机, 16 字节, 最佳的分布特性

### Spanner：比特反转序列（Bit-Reversed Sequence, 2022 起）

Google Spanner 在 2022 年正式支持比特反转序列，作为解决热点问题的一等特性：

```sql
-- 创建比特反转序列
CREATE SEQUENCE order_id_seq
    OPTIONS (sequence_kind = 'bit_reversed_positive');

-- 使用
CREATE TABLE orders (
    id INT64 DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE order_id_seq)),
    customer_id INT64,
    amount NUMERIC,
) PRIMARY KEY (id);

-- 或者带范围:
CREATE SEQUENCE order_id_seq
    OPTIONS (
        sequence_kind = 'bit_reversed_positive',
        skip_range_min = 1,
        skip_range_max = 1000000
    );

-- GoogleSQL 方言也提供直接函数
SELECT GET_INTERNAL_SEQUENCE_STATE(SEQUENCE order_id_seq);
```

**比特反转原理**：

```
普通序列: 1, 2, 3, 4, 5, 6, 7, 8, ...
二进制:   001, 010, 011, 100, 101, 110, 111, 1000, ...

比特反转（63 位）:
  原 1  = 0000...0001 → 反转 → 1000...0000 (巨大)
  原 2  = 0000...0010 → 反转 → 0100...0000
  原 3  = 0000...0011 → 反转 → 1100...0000
  原 4  = 0000...0100 → 反转 → 0010...0000

连续序列号反转后的值跨越整个 INT64 范围, 自然分散到不同 region
```

**Spanner 选型建议**（官方文档）：
- **表 < 100MB / < 100K rows**：单调 ID 也可以
- **表 100MB - 10GB**：建议比特反转序列
- **表 > 10GB 或高并发写**：必须比特反转序列或 UUID
- **全球分布 + 写多区域**：UUID v4 通常更好

### Oracle / DB2 的反向键索引（Reverse Key Index）

```sql
-- Oracle: 在索引上声明 REVERSE
CREATE INDEX idx_orders_id ON orders(id) REVERSE;

-- 每次查找/插入时, 引擎内部反转键的字节顺序
-- id=1001: 0x07E903000000 → 存储为 0x000000003 E907
-- id=1002: 0x07EA03000000 → 存储为 0x000000003 EA07
-- → 看起来连续的 ID 在索引树上相距很远
-- 
-- 副作用: 范围查询 BETWEEN 1000 AND 2000 不能用该索引!
-- 只能用于等值查询: WHERE id = 1001

-- DB2 也支持类似的 REVERSE SCANS
CREATE INDEX idx_orders_id ON orders(id) ALLOW REVERSE SCANS;
```

### HBase：Salting（盐前缀）

HBase 没有自动的热点缓解机制，完全依靠 RowKey 设计。官方推荐"盐前缀"方案：

```java
// Java 客户端代码
String originalKey = "20240423_user_12345";
int salt = Math.abs(MurmurHash3.hash32(originalKey.getBytes())) % 16;
String saltedKey = String.format("%02d_%s", salt, originalKey);
// saltedKey = "07_20240423_user_12345"
// 不同原始 key 的 salt 分布在 [00, 15] 之间, 写入分散到 16 个 region

Put put = new Put(Bytes.toBytes(saltedKey));
// ...
```

**Salting 的关键权衡**：

```
优点:
  - 写入分散到 N 个 region (N = salt 范围)
  - 实现简单, 不需引擎支持

缺点:
  - 范围 scan 失效: SCAN [start, end] 必须拆分成 N 次
  - 例如 SCAN ['20240101', '20240131'] 需要:
      SCAN ['00_20240101', '00_20240131']
      SCAN ['01_20240101', '01_20240131']
      ...
      SCAN ['15_20240101', '15_20240131']
  - 客户端合并 N 个结果
  - N 过大会降低读性能 (N 次 RPC)
  - N 过小热点仍存在
  - 推荐 N = RegionServer 数量的 2-4 倍
```

**HBase Pre-splitting（预分裂）**：

```bash
# 创建表时预先指定 split points, 避免从 1 个 region 开始扩展
hbase> create 'orders', 'cf', {SPLITS => ['01', '02', '03', ..., '15']}

# 或使用十六进制
hbase> create 'orders', 'cf', {NUMREGIONS => 16, SPLITALGO => 'HexStringSplit'}

# Hash-based:
hbase> create 'orders', 'cf', {NUMREGIONS => 16, SPLITALGO => 'UniformSplit'}
```

预分裂 + 盐前缀结合是 HBase 高写吞吐的标准方案。

### Cassandra / ScyllaDB：分区键设计

Cassandra 没有"热点缓解"的特殊语法，一切取决于分区键设计：

```cql
-- 反模式: 按时间分区, 所有写入集中到"今天的分区"
CREATE TABLE events_bad (
    day DATE,
    event_time TIMESTAMP,
    event_id UUID,
    payload TEXT,
    PRIMARY KEY (day, event_time, event_id)
);
-- 问题: 2024-04-23 的所有写入都到同一个 partition, 打爆一个节点

-- 推荐模式: 复合分区键, 加入 bucket
CREATE TABLE events_good (
    day DATE,
    bucket INT,  -- 0 到 N-1 的哈希桶
    event_time TIMESTAMP,
    event_id UUID,
    payload TEXT,
    PRIMARY KEY ((day, bucket), event_time, event_id)
);

-- 写入时根据 event_id 哈希到 bucket:
-- INSERT INTO events_good (day, bucket, event_time, event_id, payload)
--   VALUES (CURRENT_DATE, hash(event_id) % 16, NOW(), uuid(), 'data');

-- 查询单日需要并行查询 N 个 bucket:
-- SELECT * FROM events_good WHERE day = '2024-04-23' AND bucket IN (0,1,2,...,15)
--   AND event_time >= '2024-04-23 10:00:00';
```

**时间序列的"时间窗口分桶"模式**：

```cql
CREATE TABLE metrics (
    metric_name TEXT,
    time_bucket TIMESTAMP,  -- 按小时取整: date_trunc('hour', event_time)
    event_time TIMESTAMP,
    value DOUBLE,
    PRIMARY KEY ((metric_name, time_bucket), event_time)
);

-- 同一指标同一小时的数据进入同一 partition
-- 下一小时自动换 partition, 避免一个 partition 无限增长
```

### YugabyteDB：HASH 分区（默认行为）

YugabyteDB 默认使用 HASH 分区，与 PostgreSQL 的 ASC 分区不同：

```sql
-- 创建表时, 第一列主键默认 HASH
CREATE TABLE orders (
    id UUID PRIMARY KEY,
    customer_id BIGINT
);
-- 等价于: PRIMARY KEY (id HASH)
-- 数据根据 id 的哈希值分布到所有 tablet, 天然避免热点

-- 显式 ASC（类似 PostgreSQL 行为, 会产生热点）
CREATE TABLE orders_sorted (
    id UUID,
    customer_id BIGINT,
    PRIMARY KEY (id ASC)  -- 注意: 必须显式声明 ASC
);

-- 二级索引也默认 HASH
CREATE INDEX idx_orders_customer ON orders(customer_id);
-- 等价: CREATE INDEX idx_orders_customer ON orders(customer_id HASH);
```

### OceanBase：SEQUENCE 与分区

```sql
-- OceanBase 的 SEQUENCE 支持 NOORDER (不保证全局单调)
CREATE SEQUENCE ob_order_seq
    START WITH 1 INCREMENT BY 1 CACHE 10000 NOORDER;

-- NOORDER 意味着不同 OBServer 节点有独立的号段, 不保证跨节点单调
-- 但保证全局唯一 - 这就是热点缓解

CREATE TABLE orders (
    id BIGINT DEFAULT ob_order_seq.NEXTVAL PRIMARY KEY,
    customer_id BIGINT
);

-- 哈希分区作为另一层保障
CREATE TABLE orders_p (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT
) PARTITION BY HASH(id) PARTITIONS 16;
```

### ClickHouse：不适用（批量写入模型）

ClickHouse 的 MergeTree 引擎专为批量写入优化，对单行 INSERT 有严格的 "不要做" 建议：

```
ClickHouse 推荐的写入模式:
  - 批量 INSERT (每批 >= 10,000 行)
  - 写入频率 < 1 QPS (每批之间间隔 1 秒+)
  - 不需要避免"热点", 因为写入不是行级并发

如果确实需要每行一个 ID:
  SELECT generateUUIDv4() FROM numbers(1);
  SELECT generateUUIDv7() FROM numbers(1);  -- 24.5+

如果需要分布式唯一序列:
  CREATE TABLE orders (
      id UInt64 MATERIALIZED toUInt64(generateUUIDv4()),
      payload String
  ) ENGINE = MergeTree() ORDER BY id;
```

### Snowflake / BigQuery / Redshift：微分区透明

云数仓的存储层完全托管（Snowflake 的微分区、BigQuery 的 Capacitor、Redshift 的 block），写入是批量的，没有 B+ 树意义上的"最右热点"。但仍然推荐使用 UUID 作为业务主键：

```sql
-- Snowflake
CREATE TABLE orders (
    id STRING DEFAULT UUID_STRING() PRIMARY KEY,
    customer_id BIGINT,
    amount NUMBER(10,2)
);

-- BigQuery
CREATE TABLE orders (
    id STRING DEFAULT GENERATE_UUID(),
    customer_id INT64,
    amount NUMERIC
);

-- Redshift (Redshift 没有原生 UUID 函数, 需要辅助)
CREATE TABLE orders (
    id VARCHAR(36) NOT NULL,
    customer_id BIGINT,
    amount DECIMAL(10,2)
);
-- 应用层生成 UUID 后 INSERT
```

## TiDB AUTO_RANDOM 深度解析

AUTO_RANDOM 是 TiDB 独有且文档最详尽的热点缓解机制，值得深入分析。

### 架构原理

TiDB 的数据存储在 TiKV 上，每个 Region 大约 96MB。表的行数据按 rowID 顺序存入 RocksDB：

```
Table t (id BIGINT PRIMARY KEY AUTO_INCREMENT):
  Region 1: rowID [0, 60000)
  Region 2: rowID [60000, 120000)
  ...
  Region N: rowID [high, +∞)  ← 新写入都到这里
```

切换为 AUTO_RANDOM 后：

```
Table t (id BIGINT PRIMARY KEY AUTO_RANDOM(5)):
  Region prefix 0 (00000): id [0x0000..., 0x0000...]
  Region prefix 1 (00001): id [0x0800..., 0x0800...]
  Region prefix 2 (00010): id [0x1000..., 0x1000...]
  ...
  Region prefix 31 (11111): id [0xF800..., 0xFFFF...]

每次插入时, AUTO_RANDOM 随机选一个 shard prefix, 把 ID 分散到 32 个 region
```

### Shard Bits 选择

| Shard Bits | Region Prefix 数 | 适用场景 | 代价 |
|-----------|-----------------|---------|------|
| 3 | 8 | 低并发 (< 1k QPS) | ID 最大值 2^60 |
| 5（默认） | 32 | 中等 (1k - 10k QPS) | ID 最大值 2^58 |
| 8 | 256 | 高并发 (10k - 100k QPS) | ID 最大值 2^55 |
| 10 | 1024 | 极高 (> 100k QPS) | ID 最大值 2^53 |
| 15 | 32768 | 特殊场景 | ID 最大值 2^48 |

实际选择建议：Shard Bits = log2(TiKV 节点数 × 10) 为起点。

### 与 PRE_SPLIT_REGIONS 配合

```sql
CREATE TABLE orders (
    id BIGINT PRIMARY KEY AUTO_RANDOM(5),
    customer_id BIGINT
) PRE_SPLIT_REGIONS = 4;

-- AUTO_RANDOM(5) 提供 2^5 = 32 个 shard
-- PRE_SPLIT_REGIONS = 4 让表初始就有 2^4 = 16 个 region
-- 两者配合: 一旦表创建完成, 立即有 16 个 region 可承载写入

-- 查看 region 分布
SHOW TABLE orders REGIONS;
```

### 局限与注意事项

1. **不支持联合主键中的其他列**：只能作为 `PRIMARY KEY AUTO_RANDOM` 独立列
2. **不支持非聚簇表**：表必须是 `CLUSTERED`（即主键就是行数据的存储顺序）
3. **不能同时使用 AUTO_INCREMENT**：二选一
4. **LAST_INSERT_ID() 返回生成的 AUTO_RANDOM 值**：兼容 MySQL 客户端
5. **ALTER TABLE 修改 AUTO_RANDOM**：支持，但通常需要数据迁移

### 性能实测

TiDB 官方测试（5 节点 TiKV 集群，单表 sysbench oltp_insert）：

| 主键模式 | QPS | P99 延迟 | 最热节点 CPU |
|---------|-----|---------|------------|
| BIGINT AUTO_INCREMENT | 12,500 | 85ms | 95% |
| BIGINT AUTO_RANDOM(5) | 38,000 | 25ms | 45% |
| BIGINT AUTO_RANDOM(5) + PRE_SPLIT_REGIONS(6) | 52,000 | 18ms | 42% |

AUTO_RANDOM 让吞吐量提升 3-4 倍，延迟降低到原来的 1/3。

## 比特反转序列深度解析（Spanner 模式）

### 为什么比特反转而不是哈希？

用户可能会想：既然目的是打散 ID，为什么不直接用 `hash(seq)` 呢？

关键原因：**保持单调性需要反转而非哈希**。

```
普通序列 seq: 1, 2, 3, 4, 5, 6, ...

选项 A - 比特反转:
  reverse(1) = 1 << 62 = 大数
  reverse(2) = 1 << 61 = 中等数
  reverse(3) = reverse(1) | reverse(2) = 更大
  性质: 相邻 seq 的反转值相距 2^(n/2), 但同一时间段的所有反转值仍然有时间相关性
  优点: 反转函数是确定的, 可以在只知道 seq 的情况下重新计算反转值

选项 B - 哈希:
  hash(1), hash(2), hash(3) 完全随机分布
  问题: 无法按时间范围查询, 因为 hash 没有时间特性

选项 C - 随机数 (UUID v4):
  也能分散, 但完全失去"插入顺序"信息
```

### Spanner 的实现细节

```go
// 伪代码 (基于 Spanner 文档)
func bitReverse(x int64) int64 {
    // 反转 63 位 (保留符号位为 0)
    y := int64(0)
    for i := 0; i < 63; i++ {
        if x & (1 << i) != 0 {
            y |= 1 << (62 - i)
        }
    }
    return y
}

// 用法:
//   序列号: 1, 2, 3, 4, ...
//   ID:     reverse(1), reverse(2), reverse(3), ...
```

### 比特反转的问题

1. **丢失排序**：不能用 `ORDER BY id DESC LIMIT 100` 获取"最新 100 条"（需要同时保存 created_at）
2. **索引扫描**：范围扫描效率降低，适合点查询
3. **回填旧数据**：反转后的序列号看起来是随机的，如果需要按 seq 原始顺序处理，需要反向查

### Spanner 官方建议

```sql
-- 推荐模式: 主键是反转序列, 二级索引按时间
CREATE TABLE orders (
    id INT64 DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE order_seq)),
    customer_id INT64,
    created_at TIMESTAMP OPTIONS (allow_commit_timestamp = true),
    amount NUMERIC,
) PRIMARY KEY (id);

CREATE INDEX orders_by_time ON orders(created_at);

-- 查询最新订单用二级索引:
-- SELECT * FROM orders
-- WHERE created_at > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
-- ORDER BY created_at DESC LIMIT 100;
```

## HBase Salt-Prefix 深度解析

HBase 是"非 SQL 但高度相关"的代表，它的 RowKey 设计哲学影响了很多分布式 SQL 系统。

### 三种 Salting 方案对比

```
方案 1: 固定字符串前缀
  key = String.format("%02d", hash(x) % 16) + "_" + x
  例: "03_user_12345"
  
  优点: 人类可读, 调试友好
  缺点: 占用空间大, 某些客户端 parse 成本高

方案 2: 单字节前缀
  key = bytes[hash(x) % 256] + bytes(x)
  例: [0x03, 0x75, 0x73, 0x65, 0x72, ...]  // 二进制 0x03 + "user..."
  
  优点: 空间小, 最多 256 个 region prefix
  缺点: 不可读

方案 3: 高位嵌入
  key = (hash(x) & 0xFF00) | (x >> 56) | ... 
  比特级操作, 把原 key 的一部分与 salt 交织
  
  优点: 保留原 key 的部分排序
  缺点: 复杂, 难以维护
```

### HBase 读写放大

```
写入 (无 salt): 1 次 RPC → 1 个 RegionServer
写入 (有 salt, N=16): 1 次 RPC → 1 个 RegionServer (salt 分散到不同 RS)
  写入性能: 几乎无影响 (随机 RS, 负载均衡)

读取 (单点 GET, 无 salt): 1 次 RPC → 1 个 RS
读取 (单点 GET, 有 salt, N=16): 
  - 如果知道 salt: 1 次 RPC
  - 如果只知道原 key: 最坏 16 次 RPC (尝试所有 salt prefix)
  通常做法: salt = hash(原 key) → 应用层能复算 salt

扫描 (范围 SCAN): 
  - 无 salt: 1 次 RPC (范围在 1-2 个相邻 Region)
  - 有 salt, N=16: 16 次并行 RPC, 每个 RS 扫描一个 prefix
  总开销 = N 倍, 但可以并行减少延迟
```

### Cassandra / ScyllaDB 的等价模式

Cassandra 本身就是哈希分区，不需要显式 salting，但"单个 partition 过大"是常见问题：

```cql
-- 反模式: user_id 作为分区键, 活跃用户的 partition 无限增长
CREATE TABLE user_events_bad (
    user_id UUID,
    event_time TIMESTAMP,
    event_id UUID,
    payload TEXT,
    PRIMARY KEY (user_id, event_time, event_id)
);

-- 正确模式: user_id + time_bucket 作为复合分区键
CREATE TABLE user_events_good (
    user_id UUID,
    time_bucket DATE,   -- 按天分桶, 热点活跃用户每天一个 partition
    event_time TIMESTAMP,
    event_id UUID,
    payload TEXT,
    PRIMARY KEY ((user_id, time_bucket), event_time, event_id)
);
```

## Snowflake ID / ULID / UUID v7 选型建议

### 位宽对比

```
UUID v4:  128 bit (16 bytes) - 随机
UUID v7:  128 bit (16 bytes) - 48 bit time + 74 bit rand + 6 bit meta
ULID:     128 bit (16 bytes) - 48 bit time + 80 bit rand
Snowflake: 64 bit (8 bytes) - 41 bit time + 10 bit node + 12 bit seq
```

存储与索引影响：
- BIGINT 列用 Snowflake: 8 字节，与 AUTO_INCREMENT 相同
- UUID 列（BINARY(16)）: 16 字节
- UUID 列（CHAR(36)）: 36 字节（强烈不推荐）

### 分布式一致性需求

```
UUID v4: 
  需要: 无
  碰撞概率: 10^-37 (可忽略)
  适合: 任何场景

UUID v7: 
  需要: 本地时钟 (同一毫秒内可能乱序, 但有 74 位随机保证唯一)
  碰撞概率: 同毫秒同节点 74 位随机碰撞 (极低)
  适合: 需要时序 + 分布式生成

ULID:
  需要: 本地时钟 + 单调计数器 (同一毫秒内严格递增)
  碰撞概率: 80 位随机 (极低)
  适合: 需要字符串 ID + 时序 + 人类可读

Snowflake:
  需要: 中心化 Worker ID 分配 + 时钟不回拨
  碰撞概率: 0 (设计保证)
  适合: 集中式 ID 生成服务, 高吞吐 (每节点 4M/秒)
```

### 实际选型决策树

```
需要时间顺序吗？
├── 否 → UUID v4 (最简单)
└── 是 → 需要 8 字节存储吗？
         ├── 是 → Snowflake ID (需 Worker ID 服务)
         └── 否 → 需要字符串表示吗？
                  ├── 是 → ULID (URL 友好)
                  └── 否 → UUID v7 (标准化, 跨语言)
```

## 关键发现（Key Findings）

1. **没有 SQL 标准**：所有热点缓解机制都是厂商扩展，分布式 SQL 引擎差异极大
2. **UUID v4 并非免费午餐**：虽然分散写入，但带来 2-10 倍的索引碎片化、缓冲池失效和空间膨胀
3. **UUID v7 是 2024 年后的新默认**：IETF RFC 9562 正式标准化，PostgreSQL 18、MariaDB 10.7+、DuckDB 1.1+、ClickHouse 24.5+ 都已原生支持
4. **MySQL 的 UUID_TO_BIN(uuid, 1) 是历史补丁**：swap_flag=1 把 time_hi 挪到高位，让字典序 = 时间序（但底层还是 v1 UUID）
5. **TiDB AUTO_RANDOM 是最成熟的引擎级方案**：5 bit shard + PRE_SPLIT_REGIONS 能让 TiDB 吞吐提升 3-4 倍，延迟降低 2/3
6. **CockroachDB unique_rowid() 与 AUTO_RANDOM 的设计哲学不同**：前者把"分散因子"（节点 ID）放在低位保证单调，后者放在高位保证 region 分散
7. **Spanner 比特反转序列**：2022 年后的官方推荐，适用于 >10GB 的高写表
8. **HBase Salting 是手动模式**：引擎不提供任何自动化，完全依赖应用层 RowKey 设计 + Pre-splitting
9. **Cassandra 的"分区键设计"就是热点缓解**：加 bucket 或 time_bucket 到 partition key 是标准范式
10. **YugabyteDB 默认 HASH 分区**：与 PostgreSQL 的主键默认 ASC 不同，天然避免热点
11. **Oracle / DB2 反向键索引是古董方案**：用于老式 OLTP，反向后丧失范围查询能力
12. **云数仓（Snowflake / BigQuery / Redshift）几乎不需要考虑**：批量写入模型 + 微分区自动管理
13. **ClickHouse 的场景不适用**：列存 + 批量插入要求 QPS < 1 每批次，没有行级热点
14. **SQL Server NEWSEQUENTIALID() 只在机器内单调**：重启后跳跃，防止可预测
15. **性能差距巨大**：TiDB AUTO_RANDOM vs AUTO_INCREMENT QPS 差 3-4 倍，MySQL UUID v7 vs UUID v4 插入速度差 5 倍以上
16. **位宽选择是真金白银**：128 位 UUID vs 64 位 Snowflake，每 100 亿行索引差 80GB
17. **时钟回拨是 Snowflake ID 的阿喀琉斯之踵**：NTP 调整、虚拟机挂起都可能导致 ID 重复，生产必须加检测与等待逻辑
18. **RocksDB compaction 与热点的关系**：LSM 存储本身写入不怕热点（都先进 MemTable），但后台 compaction 的写放大会因单调键显著上升
19. **预分裂（PRE_SPLIT_REGIONS）是免费的加速器**：TiDB、HBase、CockroachDB 都支持，新表立即有 N 个 region 承载写入
20. **读写权衡的必然存在**：任何热点缓解方案都以牺牲局部性为代价，范围查询、"最新 N 条"、按 ID 聚合都会变慢

## 参考资料

- IETF RFC 9562 (2024): [Universally Unique IDentifiers (UUIDs)](https://www.rfc-editor.org/rfc/rfc9562)
- PostgreSQL 13: [gen_random_uuid()](https://www.postgresql.org/docs/13/functions-uuid.html)
- PostgreSQL 18: [uuidv7()](https://www.postgresql.org/docs/18/functions-uuid.html)
- MySQL 8.0: [UUID_TO_BIN(uuid, swap_flag)](https://dev.mysql.com/doc/refman/8.0/en/miscellaneous-functions.html#function_uuid-to-bin)
- MariaDB 10.7: [UUID Data Type](https://mariadb.com/kb/en/uuid-data-type/)
- SQL Server: [NEWSEQUENTIALID](https://learn.microsoft.com/en-us/sql/t-sql/functions/newsequentialid-transact-sql)
- Oracle: [REVERSE key index](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-INDEX.html)
- TiDB: [AUTO_RANDOM](https://docs.pingcap.com/tidb/stable/auto-random)
- TiDB: [Split Region](https://docs.pingcap.com/tidb/stable/sql-statement-split-region)
- CockroachDB: [unique_rowid()](https://www.cockroachlabs.com/docs/stable/functions-and-operators#id-generation-functions)
- CockroachDB: [Hash-sharded Indexes](https://www.cockroachlabs.com/docs/stable/hash-sharded-indexes)
- Google Spanner: [Bit-reversed Sequence](https://cloud.google.com/spanner/docs/schema-design#bit_reverse_sequential_values)
- YugabyteDB: [HASH vs ASC primary keys](https://docs.yugabyte.com/stable/develop/common-patterns/timeseries/)
- HBase: [Rowkey Design](https://hbase.apache.org/book.html#rowkey.design)
- Cassandra: [Data Modeling](https://cassandra.apache.org/doc/latest/cassandra/data_modeling/index.html)
- Twitter Snowflake: [Announcing Snowflake (2010)](https://blog.twitter.com/engineering/en_us/a/2010/announcing-snowflake)
- ULID Spec: [github.com/ulid/spec](https://github.com/ulid/spec)
- DuckDB: [uuidv7() (1.1+)](https://duckdb.org/docs/sql/functions/uuid)
- ClickHouse: [generateUUIDv7() (24.5+)](https://clickhouse.com/docs/en/sql-reference/functions/uuid-functions)
