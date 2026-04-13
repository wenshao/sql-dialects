# 表与列压缩 (Table and Column Compression)

存储成本是数据库 TCO 中最大的单一项之一。一张 10 TB 的事实表，按 4:1 压缩比可以省下 7.5 TB 的 SSD、内存和网络带宽——压缩不只是省钱，它直接决定了一台机器能装下多大的工作集，也直接决定了 OLAP 查询的扫描速度上限。对于列式存储而言，压缩甚至不是优化项，而是基本架构假设：没有字典编码与位打包，列存的查询性能会瞬间退回到行存水平。

对 OLTP 引擎而言，压缩则是另一种博弈：用 CPU 解压换 I/O 减少，在 NVMe SSD 普及之后这个权衡愈发微妙。Oracle Advanced Compression、SQL Server PAGE 压缩、MySQL InnoDB Compressed Row Format 都属于这条技术路线。而对于云数仓（Snowflake、BigQuery、Redshift），压缩则是完全自动、对用户透明的——用户甚至看不到 codec 名字。

本文系统对比 49+ 个数据库引擎在表级、页级、列级压缩上的能力差异，深入剖析 PostgreSQL TOAST、MySQL InnoDB、Oracle 压缩分级、SQL Server Columnstore、ClickHouse CODEC DSL、DuckDB FSST 等代表性实现，并讨论压缩与加密（TDE）的交互、Parquet/ORC 的双重压缩模型，以及时序数据库共享的 Gorilla 算法谱系。

> 注: 压缩是完全 vendor-specific 的特性，SQL 标准（SQL:2023 之前）从未涉及压缩语法。所有 DDL 都来自厂商扩展。

## 支持矩阵（综合）

### 行级与页级压缩（行存引擎）

| 引擎 | 行级压缩 | 页/块级压缩 | 表级 DDL | 默认算法 | 备注 |
|------|---------|------------|---------|---------|------|
| PostgreSQL | TOAST | -- | `STORAGE` 子句 | PGLZ / LZ4 (14+) | TOAST 仅压缩超出阈值的行外字段 |
| MySQL | InnoDB Compressed | InnoDB Page Compression | `ROW_FORMAT=COMPRESSED` | zlib / LZ4 / ZSTD (8.0.16+) | 5.7+ 页压缩需稀疏文件支持 |
| MariaDB | 是 | InnoDB / MyRocks | `PAGE_COMPRESSED=1` | zlib / LZ4 / LZMA / Snappy / Bzip2 / LZO | 10.1+ 透明页压缩 |
| SQLite | -- | -- | -- | 无 | 需 ZIPVFS 商业扩展 |
| Oracle | OLTP / Basic | OLTP 行级 | `COMPRESS [FOR ...]` | LZO 类 | Advanced Compression 选件 |
| SQL Server | `DATA_COMPRESSION=ROW` | `DATA_COMPRESSION=PAGE` | `WITH (DATA_COMPRESSION=...)` | 字典+前缀+RLE | 2008+ |
| DB2 | Classic Row Compression | Adaptive Compression | `COMPRESS YES` | 字典 + 页字典 | 9.7+ Adaptive |
| Snowflake | -- | 自动 | -- | 自动多 codec | micropartition 透明压缩 |
| BigQuery | -- | 自动 | -- | Capacitor 自动 | 列式 + 物理字节计费 |
| Redshift | 列编码 | -- | `ENCODE` 子句 | AZ64 (默认) | 详见列存表 |
| DuckDB | 列编码 | -- | -- | 自动多 codec | 详见列存表 |
| ClickHouse | 列编码 | 部分级 | `CODEC(...)` | LZ4 | 详见列存表 |
| Trino | 文件格式决定 | -- | `WITH (...)` | 取决于 ORC/Parquet | 引擎层不压缩 |
| Presto | 文件格式决定 | -- | `WITH (...)` | 同 Trino | -- |
| Spark SQL | 文件格式决定 | -- | `OPTIONS(compression=...)` | Snappy (默认 Parquet) | -- |
| Hive | 文件格式决定 | -- | `TBLPROPERTIES` | Snappy / ZLIB | -- |
| Flink SQL | 文件格式决定 | -- | `WITH (...)` | 取决于 sink | -- |
| Databricks | Delta / Parquet | -- | `TBLPROPERTIES` | Snappy / ZSTD | Delta 默认 Snappy |
| Teradata | Multi-Value / Block-Level | Block-Level Compression | `BLOCKCOMPRESSION` | 字典 + ALC | 14.10+ |
| Greenplum | AO + 列编码 | -- | `WITH (compresstype=...)` | zlib / zstd / RLE_TYPE | AOCO 列存 |
| CockroachDB | 是 | RocksDB/Pebble SSTable | -- | Snappy → ZSTD | 22.1+ ZSTD 默认 |
| TiDB | TiKV RocksDB | SSTable | -- | LZ4 / ZSTD / Snappy | bottommost 默认 ZSTD |
| OceanBase | 是 | macro block | `COMPRESSION=...` | LZ4 / ZSTD / Snappy / zlib / none | -- |
| YugabyteDB | DocDB RocksDB | SSTable | -- | Snappy | 继承 RocksDB |
| SingleStore | 是 | columnstore segment | `WITH (...)` | LZ4 (rowstore) | 主存储为列存 |
| Vertica | -- | -- | `ENCODING` | 自动选择 | 详见列存表 |
| Impala | 文件格式决定 | -- | `STORED AS` | Snappy (Parquet 默认) | -- |
| StarRocks | 列编码 | segment | `PROPERTIES("compression"=...)` | LZ4_FRAME | 详见列存表 |
| Doris | 列编码 | segment | `PROPERTIES("compression"=...)` | LZ4 | 详见列存表 |
| MonetDB | -- | -- | -- | 无显式 | 列存内部编码 |
| CrateDB | 是 | Lucene segment | `INDEX OFF` 等 | LZ4 / DEFLATE | 继承 Lucene |
| TimescaleDB | 是（hypertable 列存转换） | -- | `compress_segmentby` | 多算法自动 | 详见列存表 |
| QuestDB | -- | -- | -- | 无（mmap 列文件） | 2024+ ZFS Parquet 实验 |
| Exasol | 自动 | block | -- | 专有 | 自动列编码 |
| SAP HANA | 行存无 | 列存 dictionary | `UNIQUE/SPARSE` | 字典 + RLE | 详见列存表 |
| Informix | -- | 是 | `COMPRESSED` | 字典 + 重复抑制 | 11.50+ |
| Firebird | -- | -- | -- | RLE 行级 | RLE 默认行级 |
| H2 | -- | -- | -- | 无 | 仅 LOB 压缩 |
| HSQLDB | -- | -- | -- | 无 | 仅 LOB 压缩 |
| Derby | -- | -- | -- | 无 | 不支持 |
| Amazon Athena | 文件格式决定 | -- | `WITH (...)` | 同 Trino | -- |
| Azure Synapse | `ROW` / `PAGE` / Columnstore | 是 | `DATA_COMPRESSION=...` | 同 SQL Server | -- |
| Google Spanner | -- | 自动 | -- | Snappy | Colossus 块级 |
| Materialize | -- | -- | -- | LZ4 (持久化) | 内部状态压缩 |
| RisingWave | -- | -- | -- | LZ4 / ZSTD | Hummock SST |
| InfluxDB | 是 | TSM block | -- | Snappy + 多专用 codec | 时序专用 |
| Databend | 列编码 | -- | -- | LZ4 / ZSTD / Snappy | Parquet 存储 |
| Yellowbrick | 列编码 | -- | -- | 自动 | 列存 |
| Firebolt | 列编码 | F3 segment | -- | 自动 | 列存 |

> 统计：49 个引擎中，约 38 个提供某种形式的内置压缩；行存的 6 个老牌嵌入式数据库（SQLite/H2/HSQLDB/Derby/Firebird/QuestDB）几乎不提供原生压缩或仅有极弱支持。

### 列级压缩（列存引擎专用编码）

| 引擎 | 字典 | RLE | Delta | Bit-packing | 用法 |
|------|------|-----|-------|------------|------|
| PostgreSQL | -- | -- | -- | -- | 行存 |
| MySQL | -- | -- | -- | -- | 行存 |
| MariaDB | -- | -- | -- | -- | 行存 |
| SQLite | -- | -- | -- | -- | 行存 |
| Oracle (HCC) | 是 | 是 | 是 | 是 | Exadata Hybrid Columnar |
| SQL Server (Columnstore) | 是 | 是 | -- | 是 | `CLUSTERED COLUMNSTORE INDEX` |
| DB2 BLU | 是（频度排序） | 是 | -- | 是 | `ORGANIZE BY COLUMN` |
| Snowflake | 自动 | 自动 | 自动 | 自动 | 完全透明 |
| BigQuery | 自动 (Capacitor) | 自动 | 自动 | 自动 | 完全透明 |
| Redshift | 是 | 是 | 是 (DELTA/DELTA32K) | 是 | `ENCODE BYTEDICT/RUNLENGTH/...` |
| DuckDB | 是 | 是 | 是 | 是 | 自动 + FSST |
| ClickHouse | 是 (`LowCardinality`) | -- | 是 (`Delta`) | 是 (`T64`) | `CODEC()` 显式 |
| Trino | 取决于文件 | 取决于文件 | 取决于文件 | 取决于文件 | -- |
| Presto | 取决于文件 | 取决于文件 | 取决于文件 | 取决于文件 | -- |
| Spark SQL | 取决于文件 | 取决于文件 | 取决于文件 | 取决于文件 | -- |
| Hive | 取决于文件 | 取决于文件 | 取决于文件 | 取决于文件 | -- |
| Databricks | Delta + Parquet | 是 | 是 | 是 | -- |
| Teradata | MVC / ALC | 是 | -- | -- | -- |
| Greenplum AOCO | 是 | 是（RLE_TYPE） | 是 | 是 | `compresstype=` |
| CockroachDB | -- | -- | -- | -- | 行存 LSM |
| TiDB (TiFlash) | 是 | 是 | 是 | 是 | TiFlash 列副本 |
| OceanBase | 是 | 是 | 是 | 是 | HTAP 列存副本 |
| Vertica | 是 | 是 | 是 (DELTAVAL) | 是 | `ENCODING` 子句 |
| Impala | 取决于 Parquet | 取决于 | 取决于 | 取决于 | -- |
| StarRocks | 是 | 是 | 是 | 是 | 自动 |
| Doris | 是 | 是 | 是 | 是 | 自动 |
| Exasol | 自动 | 自动 | 自动 | 自动 | -- |
| SAP HANA | 是 | 是 | 是 (cluster) | 是 (sparse) | 自动 + `UNIQUE` 提示 |
| TimescaleDB | 是 | 是 (gorilla 派生) | 是 (delta-of-delta) | 是 | 自动 |
| MonetDB | 隐式 | 部分 | 部分 | -- | -- |
| InfluxDB | 是 (`TSI`) | 是 | 是 (delta-of-delta) | 是 | TSM engine |
| Databend | 取决于 Parquet | 取决于 | 取决于 | 取决于 | -- |
| Firebolt | 是 | 是 | 是 | 是 | 自动 |
| Yellowbrick | 是 | 是 | 是 | 是 | 自动 |
| SingleStore | 是 | 是 | 是 | 是 | columnstore 自动 |
| CrateDB | 是 (Lucene DocValues) | 是 | -- | 是 | -- |

### 通用块压缩 codec 支持

| 引擎 | LZ4 | ZSTD | Snappy | GZIP / zlib | LZO | Brotli |
|------|-----|------|--------|-------------|-----|--------|
| PostgreSQL | 14+ (TOAST) | -- | -- | -- | -- | -- |
| MySQL InnoDB | 8.0.16+ | 8.0.16+ | -- | 是 (默认) | -- | -- |
| MariaDB | 是 | 是 | 是 | 是 | 是 | -- |
| Oracle | -- | 23ai | -- | 是 (HCC ZLIB) | LZO 类 (BASIC) | -- |
| SQL Server | -- | 2022+ (Backup) | -- | 是 (Backup) | -- | -- |
| DB2 | -- | -- | -- | 是 | -- | -- |
| Snowflake | 是 | 是 | 是 | 是 | -- | 是 |
| BigQuery | -- | -- | -- | -- | -- | -- |
| Redshift | -- | ZSTD 是 | -- | -- | LZO (旧默认) | -- |
| DuckDB | -- | 是 | -- | 是 | -- | -- |
| ClickHouse | 是 (默认) | 是 | -- | 是 | -- | 是 |
| Trino (ORC/Parquet) | 是 | 是 | 是 | 是 | 是 | 是 |
| Spark SQL | 是 | 是 | 是 (默认 Parquet) | 是 | 是 | 是 |
| Hive | 是 | 是 | 是 | 是 | 是 | 是 |
| Flink SQL | 是 | 是 | 是 | 是 | -- | -- |
| Databricks | 是 | 是 | 是 (默认) | 是 | -- | -- |
| Teradata | -- | -- | -- | 是 (BLC) | -- | -- |
| Greenplum | 是 (AO) | 是 | -- | 是 (zlib) | -- | -- |
| CockroachDB | -- | 是 (默认) | 是 (旧) | -- | -- | -- |
| TiDB | 是 | 是 (默认 bottommost) | 是 | -- | -- | -- |
| OceanBase | 是 | 是 | 是 | 是 (zlib) | -- | -- |
| YugabyteDB | -- | -- | 是 | -- | -- | -- |
| SingleStore | 是 | -- | -- | -- | -- | -- |
| Vertica | -- | -- | -- | 是 (gzip 输出) | -- | -- |
| Impala | 是 | 是 | 是 | 是 | -- | -- |
| StarRocks | 是 (默认 LZ4_FRAME) | 是 | 是 | 是 | -- | -- |
| Doris | 是 | 是 | 是 | 是 | -- | -- |
| MonetDB | -- | -- | -- | -- | -- | -- |
| CrateDB | 是 (默认) | -- | -- | 是 (DEFLATE) | -- | -- |
| TimescaleDB | 14+ TOAST | -- | -- | -- | -- | -- |
| QuestDB | -- | 是 (Parquet 实验) | -- | -- | -- | -- |
| Exasol | 专有 | -- | -- | -- | -- | -- |
| SAP HANA | -- | -- | -- | -- | -- | -- |
| Informix | -- | -- | -- | 是 | -- | -- |
| Firebird | -- | -- | -- | RLE only | -- | -- |
| Athena | 是 | 是 | 是 | 是 | 是 | -- |
| Azure Synapse | -- | -- | -- | 是 | -- | -- |
| Spanner | -- | -- | 是 | -- | -- | -- |
| Materialize | 是 (Persist) | -- | -- | -- | -- | -- |
| RisingWave | 是 | 是 | -- | -- | -- | -- |
| InfluxDB | -- | -- | 是 | -- | -- | -- |
| Databend | 是 | 是 | 是 | -- | -- | -- |
| Yellowbrick | 自动 | 自动 | -- | -- | -- | -- |
| Firebolt | 自动 | 自动 | -- | -- | -- | -- |

### ORC / Parquet 文件级压缩支持

| 引擎 | ORC | ORC ZLIB | ORC SNAPPY | ORC ZSTD | ORC LZ4 | Parquet | Parquet 默认 |
|------|-----|----------|-----------|----------|---------|---------|--------------|
| Hive | 是 (原生) | 是 | 是 | 是 (1.6+) | 是 | 是 | Snappy |
| Trino | 是 | 是 | 是 | 是 | 是 | 是 | Snappy |
| Presto | 是 | 是 | 是 | 是 | 是 | 是 | Snappy |
| Spark SQL | 是 | 是 | 是 | 是 (3.0+) | 是 | 是 | Snappy |
| Impala | 是 (3.0+) | 是 | 是 | 是 | 是 | 是 | Snappy |
| Databricks | 是 | 是 | 是 | 是 | 是 | 是 (Delta) | Snappy |
| Athena | 是 | 是 | 是 | 是 | 是 | 是 | Snappy |
| BigQuery | 仅外部表 | 是 | 是 | 是 | -- | 是 | -- |
| Snowflake | 仅外部表 | 是 | 是 | 是 | -- | 是 | -- |
| ClickHouse | 是 (input format) | 是 | 是 | 是 | 是 | 是 | -- |
| DuckDB | 仅读取 | 是 | 是 | 是 | -- | 是 (读写) | Snappy |
| Doris | 是 | 是 | 是 | 是 | -- | 是 | Snappy |
| StarRocks | 是 | 是 | 是 | 是 | -- | 是 | LZ4 |
| Flink SQL | 是 | 是 | 是 | 是 | -- | 是 | Snappy |
| Databend | -- | -- | -- | -- | -- | 是 | ZSTD |
| Firebolt | -- | -- | -- | -- | -- | 是 | -- |

### 透明数据加密 (TDE) 与压缩交互

加密会破坏可压缩性（密文熵接近 1）。所有支持二者的引擎都强制 **先压缩后加密**：

| 引擎 | TDE | 压缩-加密顺序 | 备注 |
|------|-----|--------------|------|
| Oracle | 是 | 压缩→加密 | TDE Tablespace + Advanced Compression 兼容 |
| SQL Server | 是 (2008+) | 压缩→加密 | PAGE 压缩与 TDE 兼容 |
| MySQL InnoDB | 是 (5.7.11+) | 压缩→加密 | KEYRING + Page Compression |
| DB2 | 是 | 压缩→加密 | Native Encryption + Adaptive Compression |
| PostgreSQL | 仅扩展/文件系统 | -- | 核心无 TDE，依赖 LUKS / pg_tde |
| Snowflake | 强制 | 压缩→加密 | AES-256，对用户完全透明 |
| BigQuery | 强制 | 压缩→加密 | Google CMEK 透明 |
| Redshift | 是 | 压缩→加密 | 集群级 TDE |
| ClickHouse | 22.3+ | 压缩→加密 | `CODEC(LZ4, AES_128_GCM_SIV)` |
| TiDB | 是 (TiKV) | 压缩→加密 | RocksDB block 顺序 |
| CockroachDB | 是 (Enterprise) | 压缩→加密 | Pebble SSTable 顺序 |
| MariaDB | 是 (10.1+) | 压缩→加密 | InnoDB / Aria |
| Vertica | 是 | 压缩→加密 | -- |
| Greenplum | 是 (gpbackup TDE) | 压缩→加密 | -- |

> 关键点：如果先加密再压缩，压缩比会从 4:1 退化到 1.0:1。所有正确实现都遵循"压缩在内、加密在外"的层次。CockroachDB 和 ClickHouse 的代码里都有显式的 codec 顺序校验。

## PostgreSQL：TOAST 与 LZ4

PostgreSQL 不提供表级或行级压缩 DDL，唯一的压缩机制叫 **TOAST**（The Oversized-Attribute Storage Technique）。当一行的总大小超过约 2KB（页大小的 1/4）时，PostgreSQL 自动尝试压缩可变长度字段，仍然过大则把它移到独立的 TOAST 表（"out-of-line storage"）。

```sql
-- PostgreSQL 14+：选择 TOAST 压缩算法
ALTER TABLE documents ALTER COLUMN body SET COMPRESSION lz4;
ALTER TABLE documents ALTER COLUMN body SET COMPRESSION pglz;  -- 默认

-- 服务器级默认
SET default_toast_compression = 'lz4';

-- 查看实际使用的算法（按行可能不同）
SELECT pg_column_compression(body) FROM documents LIMIT 1;
```

**关键细节**：
- 14 之前唯一选项是 PGLZ（PostgreSQL 自研，类似 LZ77 的简化变体）。
- 14+ 增加 LZ4，速度 2-4 倍于 PGLZ，压缩比通常略低但接近。
- TOAST 仅压缩单字段，**不压缩整行**——窄行表 PostgreSQL 完全没有压缩。
- `STORAGE` 子句（`PLAIN` / `EXTERNAL` / `EXTENDED` / `MAIN`）控制是否允许压缩与外移。`EXTERNAL` 只外移不压缩，`MAIN` 优先压缩不外移，`EXTENDED` 是变长类型的默认（先压缩、过大再外移）。
- 行内 column 的压缩阈值由 `toast_tuple_threshold`（默认 2 KB）控制。
- TimescaleDB 通过将 hypertable 转为列式 chunk 实现真正的列压缩，可达 90%+ 比率（详见后文）。
- Citus、ZHEAP、OrioleDB 等扩展或分支都试图填补 PostgreSQL 在表压缩上的空白；社区曾提交过 cstore_fdw、Hydra 等列存扩展。

PostgreSQL 缺乏页级或行级压缩是其架构遗留问题：HEAP 页面格式与索引强耦合，引入页压缩需要侵入式改动 buffer manager。这也是 EnterpriseDB 与 Fujitsu Enterprise Postgres 商业版的差异化点之一。

## MySQL InnoDB：两种压缩模式

MySQL 提供两种互不兼容的压缩策略：

### Compressed Row Format（5.5+）

```sql
CREATE TABLE logs (
    id BIGINT PRIMARY KEY,
    payload TEXT
) ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8;
```

将 16KB 页压缩到 1/2/4/8KB，存储在缓冲池中既有压缩页又有解压页（双缓存）。算法为 zlib，性能开销显著，主要用于减少 SSD 占用。其内部使用一个 modification log 记录针对压缩页的修改，避免每次 DML 都重新压缩整页；当 mlog 满时才触发 recompression。这种设计对写密集型负载相当不友好。

### Transparent Page Compression（5.7+）

```sql
CREATE TABLE logs (
    id BIGINT PRIMARY KEY,
    payload TEXT
) COMPRESSION='zlib';   -- 或 'lz4', 'none'

ALTER TABLE logs COMPRESSION='lz4';
```

依赖文件系统的 **稀疏文件 + hole punching** 特性。InnoDB 写入时压缩 16KB 页，然后用 `fallocate(PUNCH_HOLE)` 释放尾部空闲扇区。优点：不改变 buffer pool 行为；缺点：需要 XFS/ext4 + 4KB 物理扇区，备份工具需理解稀疏文件，碎片化严重时性能崩溃。Percona 的工程实践经验表明，这一模式在云块存储（EBS、GP3）上往往得不偿失。

8.0.16+ 增加 LZ4 与 ZSTD codec。MariaDB 在此基础上继续扩展支持 LZMA、bzip2、Snappy、LZO，并把页压缩做得更稳定。MariaDB MyRocks 引擎则直接继承 RocksDB 的 LZ4/ZSTD 双层压缩模型。

## Oracle：分级压缩与 HCC

Oracle 是表压缩功能最丰富的传统数据库，分四档：

| 模式 | 语法 | 适用场景 | 许可 |
|------|------|---------|------|
| BASIC | `COMPRESS` 或 `COMPRESS BASIC` | 仅直接路径加载，DML 后失效 | 免费 |
| OLTP / Advanced Row | `COMPRESS FOR OLTP` | 普通 DML 表 | Advanced Compression Option |
| HCC QUERY LOW/HIGH | `COMPRESS FOR QUERY {LOW\|HIGH}` | DW 查询型 | Exadata / ZFS Storage 专属 |
| HCC ARCHIVE LOW/HIGH | `COMPRESS FOR ARCHIVE {LOW\|HIGH}` | 历史归档 | Exadata 专属 |

```sql
-- BASIC 压缩：只对 INSERT /*+ APPEND */ 生效，常规 DML 写出未压缩块
CREATE TABLE sales_basic (...) COMPRESS BASIC;

-- OLTP 行级压缩，正常 DML 都压缩
CREATE TABLE orders (...)
COMPRESS FOR OLTP;

-- HCC 查询型，10x 典型压缩比
ALTER TABLE sales MOVE COMPRESS FOR QUERY HIGH;
-- 内部使用 ZLIB

-- HCC 归档，30-50x 极致压缩比
ALTER TABLE sales_history MOVE COMPRESS FOR ARCHIVE HIGH;
-- 内部使用 BZIP2
```

**HCC（Hybrid Columnar Compression）** 把行组（Compression Unit, CU）按列重排后用通用 codec 压缩，是 Oracle 的列式杀手锏。一个 CU 通常包含 1000 到几万行，结构上仍是行存表（`ROWID` 仍可用），但物理布局是按列连续的。HCC 仅在 Exadata、ZFS Storage Appliance、Pillar Axiom 等 Oracle 自家存储上可用——这是商业策略而非技术限制（Oracle 12c+ 在云存储 OCI Block Volumes 上也开放了 HCC）。

Oracle 23ai 增加 ZSTD 作为新的 HCC 内部 codec，承诺 25% 的压缩比提升与更快的扫描。

OLTP 压缩本质上是 **页内字典 + 符号表**：在每个块的尾部维护一张小字典，行内重复字段被替换为字典 ID。这与 SQL Server PAGE 压缩、DB2 Adaptive Compression 思路完全一致。

## SQL Server：ROW / PAGE / Columnstore

SQL Server 的压缩策略是行存与列存共存，三种模式：

```sql
-- ROW 压缩：变长存储固定类型，节省类型开销
ALTER TABLE orders REBUILD WITH (DATA_COMPRESSION = ROW);

-- PAGE 压缩：ROW + 列前缀压缩 + 页字典
ALTER TABLE orders REBUILD WITH (DATA_COMPRESSION = PAGE);

-- 分区级
ALTER TABLE sales REBUILD PARTITION = 5
  WITH (DATA_COMPRESSION = PAGE);

-- 列式存储索引（2014+）
CREATE CLUSTERED COLUMNSTORE INDEX ccsi ON fact_sales;
-- 自动应用 VertiPaq：字典 + RLE + bit-packing
-- 可叠加 COLUMNSTORE_ARCHIVE
ALTER INDEX ccsi ON fact_sales REBUILD
  WITH (DATA_COMPRESSION = COLUMNSTORE_ARCHIVE);
```

**ROW 压缩**：把固定长度类型按实际有效字节存储——`INT 5` 只占 1 字节，`DATETIME '2026-04-13'` 仅存日期分量，`CHAR(10) 'AB'` 删除尾部空格。

**PAGE 压缩**：在 ROW 基础上叠加两层 (a) **column-prefix compression**（同列内同前缀只存一次），(b) **page-level dictionary**（整页内重复值用 1 字节 ID 替换）。这是 OLTP 表压缩的事实标准做法，被 DB2、Oracle OLTP、PG 商业分支广泛模仿。

**Columnstore**：基于 VertiPaq（来自 Power Pivot/SSAS）的列式索引引擎。每 ~1M 行打成一个 row group，每列 segment 内做字典编码 + bit-packing + RLE。2012 引入但只读，2014 起支持可更新聚集列存（CCI）。COLUMNSTORE_ARCHIVE 在标准列存基础上额外应用 LZ77（XPRESS9），通常再省 30-50% 空间，代价是查询时 CPU 翻倍。

`sp_estimate_data_compression_savings` 可在不实际压缩的情况下估算节省量——这对生产决策非常重要。

## DB2：Classic 与 Adaptive 压缩

DB2 9.5 引入 Classic Row Compression（基于表级字典），9.7 引入 Adaptive Compression（页级字典 + 表级字典两层）。10.5 引入 BLU Acceleration 列存。

```sql
-- 经典行压缩：建立表级字典
ALTER TABLE sales COMPRESS YES;
REORG TABLE sales RESETDICTIONARY;

-- 自适应压缩：表级 + 页级双字典
ALTER TABLE sales COMPRESS YES ADAPTIVE;

-- BLU 列式：自动 frequency-based 编码 + SIMD 谓词
CREATE TABLE fact_sales (...)
ORGANIZE BY COLUMN;
```

DB2 BLU 的核心创新是 **频度排序字典编码**：高频值用短码字、低频用长码字，整张表编码后可以在压缩域上直接执行 SIMD 谓词（不解压即可比较）。这与 Snowflake / Vectorwise / SAP HANA 的做法本质一致。BLU 表自动决定 segment 大小、自动选择编码、自动执行 reorg——是 DB2 团队"少调优"哲学的最高体现。

## ClickHouse：Codec DSL 深入

ClickHouse 是唯一允许用户在 DDL 中**显式组合多个 codec** 的引擎，语法形如 `CODEC(c1, c2, c3)`，应用顺序从左到右——通常前面是专用编码（Delta/T64/Gorilla），后面跟通用块压缩（LZ4/ZSTD）。

```sql
CREATE TABLE metrics (
    ts        DateTime CODEC(DoubleDelta, ZSTD(1)),
    host_id   UInt32   CODEC(T64, LZ4),
    cpu_pct   Float64  CODEC(Gorilla, LZ4),
    msg       String   CODEC(ZSTD(3))
)
ENGINE = MergeTree
ORDER BY (host_id, ts);
```

### 专用 codec

| Codec | 适用类型 | 原理 |
|-------|---------|------|
| `Delta(N)` | 整数、时间 | 存差分而非原值，N=delta 字节宽度 |
| `DoubleDelta` | 单调时间戳 | delta-of-delta，时序最优 |
| `Gorilla` | 浮点 | Facebook Gorilla XOR 编码，几乎为 0 字节存储缓变浮点 |
| `T64` | UInt8-64 / Int8-64 / DateTime | 转置 64 行 × 64 列 bit 矩阵后剥除高位 0 |
| `FPC` | Float | 双流预测 + leading-zero 编码 |
| `GCD` | 整数 | 提取最大公约数，余数压缩 |

### 通用 codec

| Codec | 默认级别 | 速度 | 压缩比 |
|-------|----------|------|--------|
| `NONE` | -- | 最快 | 1.0 |
| `LZ4` | 默认 | 快 | 中 |
| `LZ4HC(level)` | 9 | 中 | 较高 |
| `ZSTD(level)` | 1 | 中 | 高 |
| `Deflate_qpl` | -- | (Intel QPL 硬件加速) | -- |

### 加密 codec

```sql
CREATE TABLE secrets (
    id UInt64,
    payload String CODEC(ZSTD(3), AES_128_GCM_SIV)
) ENGINE = MergeTree ORDER BY id;
```

> ClickHouse 严格执行 "压缩在前、加密在后"：试图反向写 `CODEC(AES_128_GCM_SIV, ZSTD(3))` 会被拒绝。源代码中 `CompressionCodecEncrypted::isCompression()` 返回 false，编码器栈在校验时显式检查。

### 服务器默认

```xml
<compression>
  <case>
    <method>zstd</method>
    <level>3</level>
    <min_part_size>10000000000</min_part_size>
  </case>
</compression>
```

可按 part 大小阈值动态选择 codec：小 part 用 LZ4（解压快、merge 频繁），大 part 用 ZSTD（merge 不频繁、追求最小占用）。

### 何时手工指定 CODEC？

ClickHouse 默认 LZ4 已经能覆盖大部分场景。手工 CODEC 的典型收益场景：

1. **时间戳列**：`CODEC(DoubleDelta, ZSTD(1))` 通常把 8 字节时间戳压到 < 1 字节/行。
2. **缓变浮点指标**：`CODEC(Gorilla, LZ4)` 对 CPU/Memory/Latency 等指标常见 8-15x 压缩比。
3. **窄整数**：`CODEC(T64, LZ4)` 对 ID、计数器列把 8 字节整数压到 1-2 字节。
4. **超长低基数字符串**：用 `LowCardinality(String)` 类型（不在 CODEC 中），转为字典编码列。
5. **冷归档**：`CODEC(ZSTD(22))` 极致压缩，扫描 CPU 翻 5 倍但空间节省 30%+。

## DuckDB：自动列压缩与 FSST

DuckDB 列存储自动为每列选择最优编码，不暴露 DDL 选择 codec：

| 编码 | 适用 |
|------|------|
| `Uncompressed` | fallback |
| `Constant` | 整列同值 |
| `RLE` | 运行长度 |
| `Bit-packing` | 整数 |
| `Dictionary` | 低基数字符串 |
| `FOR` (Frame of Reference) | 整数偏移 |
| `Delta` | 排序整数 |
| `Chimp / Patas` | 浮点 |
| `FSST` | 长字符串 |

`PRAGMA storage_info('table')` 可查看每列实际选择的编码。DuckDB 在 row group 写入时按 vector（默认 2048 行）粒度尝试每种 codec，选择压缩比最佳者。

**FSST**（Fast Static Symbol Table，CWI 2020 论文 Boncz et al.）是 DuckDB 字符串压缩的核心创新：训练一个最多 255 项的符号表，把高频子串替换为 1 字节 token，剩余字节直接保留。

优点：
- 解压可逐 token 进行（不像 LZ4 必须解压整块），允许列上的局部访问与谓词下推。
- 压缩比接近 LZ4，对 URL、UUID、JSON path 这类结构化字符串尤其有效。
- 编码本身就保序——可在压缩域做 `LIKE 'prefix%'` 谓词。

DuckDB 0.6+ 默认对所有 VARCHAR 列尝试 FSST，0.10+ 进一步加入 `Chimp` 与 `Patas` 浮点编码（基于学术论文，对应 Gorilla 的改良版）。

## Snowflake / BigQuery：完全透明的列压缩

Snowflake 把表按 **micropartition**（约 50-500 MB 未压缩，对应 16 MB 压缩）切分，每个 micropartition 内对每列独立做：自动 codec 选择 + 字典 + RLE + 通用块压缩。用户没有任何 DDL 控制点，连 codec 名称都不公开。

```sql
-- Snowflake：完全无压缩 DDL
CREATE TABLE sales (
    sale_id BIGINT,
    sale_date DATE,
    region STRING,
    amount NUMBER(18,2)
);
-- 加载后自动应用所有压缩，用户透明
```

优点是消除了所有调优工作；缺点是无法针对特殊数据形态做手工优化。Snowflake 的设计哲学：用户应该思考业务逻辑，不应该思考 codec。

BigQuery 的 **Capacitor** 格式同样完全自动，并在加载时执行 record reordering（启发式行排序）以最大化每列的 RLE 命中率——这是 Snowflake 也用的技巧。BigQuery 的物理字节计费基于压缩后大小，使得用户对压缩比有天然优化动机：表越小，存储成本越低、扫描成本也越低。

```sql
-- BigQuery：仅可选择存储计费模式（影响是否按物理字节计费）
ALTER TABLE dataset.fact_sales
SET OPTIONS (storage_billing_model = 'PHYSICAL');
```

两者都不允许用户指定算法。两者都对加密/压缩顺序透明。

## Redshift：列编码 + ANALYZE COMPRESSION

Redshift 是列式 MPP，每列有独立 `ENCODE`：

```sql
CREATE TABLE sales (
    sale_id   BIGINT     ENCODE az64,
    sale_date DATE       ENCODE az64,
    region    VARCHAR(2) ENCODE bytedict,
    amount    DECIMAL(18,2) ENCODE az64,
    notes     VARCHAR(500)  ENCODE zstd
)
DISTKEY(sale_id) SORTKEY(sale_date);
```

| 编码 | 适用 |
|------|------|
| `RAW` | 不压缩（SORTKEY 列默认） |
| `AZ64` | Amazon 自研整数/日期/decimal，2019 起为大多数类型默认 |
| `ZSTD` | 通用，字符串首选 |
| `LZO` | 早期默认（已弃用） |
| `BYTEDICT` | 1 字节字典，最多 256 distinct |
| `DELTA` / `DELTA32K` | 整数偏移 |
| `MOSTLY8/16/32` | 大多数小值 + 异常值 |
| `RUNLENGTH` | 长游程列（如低基数） |
| `TEXT255 / TEXT32K` | 字符串字典 |

```sql
-- 让 Redshift 推荐编码
ANALYZE COMPRESSION sales;
-- 输出每列推荐 ENCODE 与节省百分比

-- COPY 时自动选择
COPY sales FROM 's3://...' COMPUPDATE ON;
```

ANALYZE COMPRESSION 是 Redshift 用户最常用的命令之一：它在新表加载完一批样本数据后建议每列编码，避免人工猜测。AZ64 是 Amazon 在 2019 年自研发布的整数/日期/数字编码，针对窄类型的扫描性能比 ZSTD 快 70%，压缩比相当。

## Vertica：自动选择编码

Vertica 与 Redshift 类似，但更激进：projection 创建时若未指定 `ENCODING`，Vertica 在数据加载后自动重写 projection 选择编码。

```sql
CREATE TABLE web_sessions (
    user_id INT ENCODING DELTAVAL,
    ts      TIMESTAMP ENCODING DELTAVAL,
    url     VARCHAR(1024) ENCODING ZSTD_FAST_COMP,
    bytes   INT ENCODING COMMONDELTA_COMP
);
```

支持的编码包括 `AUTO`、`RLE`、`DELTAVAL`、`DELTARANGE_COMP`、`COMMONDELTA_COMP`、`BLOCK_DICT`、`BLOCKDICT_COMP`、`BZIP_COMP`、`GCDDELTA`、`GZIP_COMP`、`ZSTD_COMP/FAST/HIGH`。Vertica 是少数承认 GCD 编码的引擎——这一编码对类似订单金额（常常是 100 的倍数）这种数据非常有效。

Vertica 的 Database Designer 工具能根据样本查询负载自动建议编码组合，是商业列存数据库中调优自动化做得最早最完善的。

## Greenplum：AOCO 与 compresstype

```sql
-- Append-Only Column-Oriented
CREATE TABLE fact_sales (
    sale_id bigint,
    sale_date date,
    amount numeric(18,2)
)
WITH (
    appendoptimized = true,
    orientation = column,
    compresstype = zstd,
    compresslevel = 5,
    blocksize = 32768
)
DISTRIBUTED BY (sale_id);

-- 单列覆盖
ALTER TABLE fact_sales
  ALTER COLUMN amount
  SET ENCODING (compresstype=rle_type, compresslevel=1);
```

`rle_type` 是 Greenplum 专用的列级 RLE 编码，可与 zlib/zstd 叠加。AO（Append-Only）表只允许 INSERT 与块级 DELETE，禁止 UPDATE——这一限制使得列式压缩可以非常激进。AOCO（AO Column Oriented）是 Greenplum 的默认 DW 选择。

## Parquet 与 ORC 文件格式

对于大量 Lakehouse 与查询引擎（Trino/Spark/Hive/Impala/Athena/BigQuery 外部表/Snowflake 外部表），表的物理压缩完全由文件格式决定。

### Parquet

Parquet 使用 **列分页（column chunk → page）** 模型，每个 page 内部先做编码（`PLAIN` / `DICTIONARY` / `RLE_DICTIONARY` / `DELTA_BINARY_PACKED` / `DELTA_LENGTH_BYTE_ARRAY` / `DELTA_BYTE_ARRAY` / `BYTE_STREAM_SPLIT`），然后整页通过通用 codec 压缩：

| codec | Spark 默认 | Hive 默认 | Impala 默认 |
|-------|-----------|----------|-------------|
| `SNAPPY` | 是 | 是 | 是 |
| `GZIP` | -- | -- | -- |
| `LZ4_RAW` | -- | -- | -- |
| `ZSTD` | -- | -- | -- |
| `BROTLI` | -- | -- | -- |
| `LZO` | -- | -- | -- |

```sql
-- Spark
CREATE TABLE events USING parquet OPTIONS('compression'='zstd') AS ...

-- Trino / Hive
CREATE TABLE events
WITH (format='PARQUET', parquet_compression='ZSTD') AS ...

-- Iceberg 表属性
ALTER TABLE catalog.db.events SET TBLPROPERTIES (
    'write.parquet.compression-codec'='zstd',
    'write.parquet.compression-level'='3'
);
```

Parquet 的 "双重压缩" 是其性能秘诀：编码层（Dictionary/RLE/Delta）做语义压缩，codec 层（Snappy/ZSTD）做熵压缩。两者合用通常能达到 5-10x 的压缩比。

### ORC

ORC 的 stripe → row group → stream 模型类似，编码包括 `RLE v1/v2`、`DICTIONARY`、`DELTA`、`PATCHED_BASE`。Stream 级 codec 选项：`NONE / ZLIB / SNAPPY / LZO / LZ4 / ZSTD（1.6+）`。Hive 默认 ZLIB，Spark 改为 SNAPPY。

```sql
CREATE TABLE events
STORED AS ORC
TBLPROPERTIES ("orc.compress"="ZSTD", "orc.compress.size"="262144");
```

ORC 与 Parquet 在压缩能力上无本质差异；ORC 在 ACID 事务（Hive ACID v2）和 predicate pushdown 元数据上略胜，Parquet 在生态广度（Spark / Pandas / Polars / Trino / DuckDB）上完全胜出。

## SAP HANA：列存的字典编码极致

SAP HANA 列存默认行为：
1. 每列建一个 **value-id dictionary**（按字典序或频率序）。
2. 用 **N-bit 编码** 存 value-id（N = ceil(log2(distinct count))）。
3. 对 value-id 序列再做 **prefix / cluster / sparse / indirect / RLE** 五选一压缩。
4. 主存储分 **delta（写优化）** 与 **main（读优化）** 两层，定期 merge。

```sql
-- 建议唯一性以选择 prefix/sparse 压缩
ALTER TABLE customers ALTER (customer_id INT NOT NULL UNIQUE);

-- 强制重新选择压缩
UPDATE customers WITH PARAMETERS('OPTIMIZE_COMPRESSION'='FORCE');
```

HANA 在压缩域上的 SIMD 谓词执行是它能在内存中高效处理 TB 级数据的核心。"all data in memory" 听起来很奢侈，但加上 5-10x 的字典压缩，单服务器 6 TB 内存可以覆盖 30-60 TB 原始数据。

## InfluxDB：时序专用编码

InfluxDB TSM 引擎按列类型选择不同 codec：

| 类型 | 编码 |
|------|------|
| 时间戳 | RLE → 简单8b → delta-of-delta |
| float64 | Gorilla XOR |
| int64 | ZigZag + Simple8b → RLE |
| bool | bit-packing |
| string | Snappy |

时间戳列是关键：单调递增、间隔固定的指标可以被压缩到 **每点 < 1 bit**——这是时序数据库相对通用 OLAP 的核心成本优势。

InfluxDB 3.0（IOx 引擎）放弃自研 TSM，直接采用 Apache Parquet + DataFusion，把压缩交给 Parquet 标准编码。这一转向是时序数据库工程史上的一次重要事件，标志着 Parquet 的列式编码已经强到不需要专用时序 codec。

## TimescaleDB：列式 hypertable 压缩

```sql
ALTER TABLE conditions SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'device_id',
    timescaledb.compress_orderby = 'time DESC'
);

SELECT add_compression_policy('conditions', INTERVAL '7 days');
```

老 chunk 被转换为列式存储：每个 segmentby 值 + 1000 行打包成一个数组列，整体应用 dictionary、delta-of-delta（时间）、Gorilla（浮点）、RLE。典型压缩比 90-95%。

TimescaleDB 的精明之处在于：它在 PostgreSQL 之上实现了真正的列式压缩，而完全没有改动 PG 内核。压缩 chunk 实际上是一张特殊的 PG 表，每行保存原表 1000 行的"压缩数组"。SELECT 时通过自定义函数解压。这种 "zero core change" 思路使它能跟随上游 PG 主线。

## TiDB / CockroachDB / YugabyteDB：RocksDB SSTable

NewSQL 三家底层都是 LSM 引擎（RocksDB 或派生 Pebble），压缩在 SSTable 块级别：

| 引擎 | L0-Ln-1 默认 | Bottommost 默认 |
|------|-------------|------------------|
| TiDB (TiKV) | LZ4 | ZSTD |
| CockroachDB (Pebble) | Snappy → ZSTD (22.1+) | ZSTD |
| YugabyteDB (DocDB) | Snappy | Snappy |

通常上层用快速 codec（LZ4/Snappy）减少 compaction CPU，最底层用 ZSTD 最大化空间节省——这是 LSM 引擎的通用优化模式。CockroachDB 在 22.1 把默认从 Snappy 改为 ZSTD，单次升级就在生产集群上节省了 ~20% 的空间。

TiDB 的列存副本 **TiFlash** 走完全不同的路线：它是基于 ClickHouse fork 的列存引擎，自动维护 Raft Learner 副本，行存 TiKV 与列存 TiFlash 通过 Raft 同步。同一个查询可以智能选择两种存储——HTAP 设计的范式。

## OceanBase：表级 compression 子句

```sql
CREATE TABLE orders (...)
COMPRESSION 'zstd_1.3.8';

-- 支持
-- 'none', 'lz4_1.0', 'snappy_1.0', 'zlib_1.0',
-- 'zstd_1.0', 'zstd_1.3.8', 'lzo_1.0'
```

OceanBase 是少数允许在 DDL 中精确指定 codec 版本号的引擎，便于多版本集群滚动升级时锁定行为——同一份 SSTable 在不同版本的 zstd 库下可能产生不同字节，对一致性校验不友好。OceanBase 4.x 的列存模式（HTAP 列副本）则采用了与 TiFlash 类似的设计。

## StarRocks / Doris：列存 OLAP 双子星

```sql
-- StarRocks
CREATE TABLE fact_sales (
    sale_id BIGINT,
    sale_date DATE,
    amount DECIMAL(18, 2)
)
DUPLICATE KEY(sale_id)
DISTRIBUTED BY HASH(sale_id)
PROPERTIES (
    "compression" = "LZ4_FRAME",
    "storage_format" = "DEFAULT"
);

-- Doris
CREATE TABLE fact_sales (...)
PROPERTIES (
    "compression" = "LZ4"
);
```

二者均自动对每列选择字典/RLE/delta/bit-packing 编码后再用块级 codec。StarRocks 默认 `LZ4_FRAME`（带帧头的 LZ4 变体，可逐块解压），Doris 默认 `LZ4`，二者都支持切换 ZSTD。冷数据可设置 `"compression" = "ZSTD"` 节省存储。

## SingleStore：行存 + 列存共存

```sql
-- 行存表（默认 LZ4）
CREATE ROWSTORE TABLE hot_orders (...);

-- 列存表
CREATE TABLE fact_sales (...) USING COLUMNSTORE;
```

SingleStore 列存 segment 内部应用字典 + RLE + bit-packing + LZ4 整段压缩。其 universal storage（HTAP）特性使得同一张表可以同时拥有行存索引与列存主存。

## CockroachDB / Pebble 内幕

```
Pebble SSTable layout (compressed):
+--------------------+
| Data Block 1 (ZSTD)|
+--------------------+
| Data Block 2 (ZSTD)|
+--------------------+
| ... |
+--------------------+
| Index Block        |
| Filter Block       |
| Meta Index Block   |
| Footer (32 bytes)  |
+--------------------+
```

Pebble 与 RocksDB 一致：每 4 KB-32 KB data block 独立压缩，方便点查时只解压所需 block。这一设计是所有 LSM 引擎的标准。

## 关键发现

1. **没有 SQL 标准**：直到 SQL:2023，标准都未涉及压缩 DDL。所有语法都是厂商扩展。压缩注定是数据库厂商竞争的"非标准化前线"。
2. **行存与列存的鸿沟**：行存数据库只能压缩到约 2-3:1（页字典 + 通用 codec）；列存数据库通过 dictionary + RLE + bit-packing 可以达到 10-30:1，HCC ARCHIVE HIGH 极端可达 50:1。
3. **PostgreSQL 是异类**：作为顶级开源 OLTP，它在表级压缩上一片空白。LZ4 (14+) 仅压缩 TOAST 字段，对窄表完全无效。这是 TimescaleDB、Citus、Greenplum、Hydra 等基于 PG 的产品的共同切入点。
4. **Oracle 是功能最丰富的**：BASIC / OLTP / HCC QUERY / HCC ARCHIVE 四档加上 TDE 集成，是 35 年技术沉淀。但 HCC 锁定 Exadata 是商业策略。
5. **云数仓全部"零旋钮"**：Snowflake / BigQuery 完全不暴露 codec 选择，连算法名都不公开。设计哲学：用户不应该懂压缩。
6. **Redshift / Vertica 走中间路线**：暴露 ENCODE 但提供 `ANALYZE COMPRESSION` / 自动重写帮用户选。这是"专家旋钮 + 默认自动"的折中。
7. **ClickHouse 是 codec DSL 的孤例**：唯一允许多 codec 显式组合（`CODEC(Delta, T64, ZSTD(3))`）的引擎，给了高级用户完整控制权——代价是新手会被各种专用 codec 名字劝退。
8. **DuckDB FSST 是新一代字符串压缩代表**：可在不解压的情况下做谓词与切片，预示嵌入式分析未来都会跟进。Polars / Lance / Arrow 社区都在评估或集成 FSST。
9. **时序数据库共享一个秘密**：DoubleDelta / Gorilla 几乎成为时序压缩的事实标准——ClickHouse、InfluxDB、TimescaleDB、QuestDB 都用同一族算法。Facebook 2015 年的 Gorilla 论文影响了整个时序生态。
10. **加密永远在压缩之外**：所有正确实现都是"先压缩再加密"。试图反过来（如 ClickHouse `CODEC(AES, ZSTD)`）会被显式拒绝。
11. **LSM 引擎统一选用 LZ4 + ZSTD 双层**：TiDB / CockroachDB 都让顶层 LZ4 减少 compaction 开销，底层 ZSTD 节省空间——这已成 LSM 实践共识。
12. **MySQL 的两种压缩方案彼此不兼容**：传统 `ROW_FORMAT=COMPRESSED` 影响 buffer pool 行为（双缓存），新的 Page Compression 依赖文件系统 hole punching——后者透明性更好但生产部署更受限。
13. **行级 RLE 的"只读"陷阱**：Oracle BASIC 与 SQL Server COLUMNSTORE_ARCHIVE 都对 DML 不友好，DELETE/UPDATE 后必须重建。生产中通常只用于历史分区。
14. **嵌入式数据库基本放弃了压缩**：SQLite、H2、HSQLDB、Derby、Firebird 都没有真正的页/列压缩——这反映了嵌入式场景重点在于轻量级与单文件，而非空间。SQLite 的 ZIPVFS 是商业选件。
15. **Parquet 的"双重压缩"**：Parquet 文件内每列先做 RLE/DICTIONARY/DELTA 编码，再用 SNAPPY/ZSTD 整页压缩。Snappy 之所以是默认，是因为它在解压速度上对扫描密集型查询最友好；ZSTD 在 Spark 3+ 与 Iceberg 中正在成为新默认。
16. **HTAP 引擎用列副本绕过单存储压缩限制**：TiDB TiFlash、OceanBase 列副本、SingleStore Universal Storage 都把行存与列存视为同一逻辑表的两种物理表示，分别用各自最优的压缩策略。这是 HTAP 时代最重要的存储分层模式。
17. **ZSTD 正在统一江湖**：Facebook 2016 年发布的 ZSTD 因为兼具高压缩比与可调速度，已经成为 PostgreSQL 14、Oracle 23ai、SQL Server 2022、CockroachDB、TiDB、Iceberg、Parquet 的新默认或推荐选项。这是 21 世纪 20 年代最重要的存储引擎技术收敛。
18. **InfluxDB 3.0 的转向意义重大**：放弃自研 TSM 改用 Parquet，承认了通用列式格式已经追平时序专用编码——这一信号将影响整个时序生态的演进方向。
