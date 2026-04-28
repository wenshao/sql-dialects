# 数据库克隆 (Database Cloning)

"我要克隆这个 50TB 的生产数据库给开发团队做回归测试，但既不能占用 50TB 额外存储，也不能让开发数据库花两小时 COPY 完才能用。" 这看似不可能的要求，正是**零拷贝克隆（Zero-Copy Clone）** 的核心价值。从 Snowflake 在 2017 年正式 GA `CLONE` 关键字开始，"瞬间创建一个独立可写的副本，仅在写入时按需复制底层数据" 就成了现代云数仓的标志性能力。Aurora 把这套机制下沉到存储引擎层，BigQuery 在 2022 年跟进，Databricks Delta Lake 提供 SHALLOW / DEEP 双模式克隆，Oracle 多租户从 12c 起支持 PDB 克隆。如今，零拷贝克隆已经成为数据科学环境隔离、CI/CD 测试、灾难演练、机器学习实验跟踪的基础原语。

姊妹文章：[快照导出 (Snapshot Export)](./snapshot-export.md) 关注 "把当前时刻冻结成可分发的快照标识"；[WAL 归档与 PITR](./wal-archiving.md) 关注 "崩溃恢复的物理日志流"；本文关注 "如何瞬间创建一个独立可写、共享底层存储的副本"。

## 为什么需要零拷贝克隆

设想一个常见场景：DBA 需要给数据科学家、QA 团队、ML 工程师各自提供一份生产数据的副本用于实验。如果用传统的 `pg_dump` + `pg_restore` 或 `BACKUP` + `RESTORE`：

- **存储成本**：每个副本 = 1 份完整数据。10 个团队 = 10 份完整 50TB 拷贝。
- **时间成本**：恢复 50TB 数据库需要数小时（取决于 I/O 带宽）。
- **新鲜度**：副本一旦创建就开始过时，每次需要新数据都要重新做一次 dump/restore。
- **维护负担**：DBA 需要管理多个独立的备份/恢复任务、配额、权限。

**零拷贝克隆**通过两个机制解决这些问题：

1. **元数据指针**：克隆只是创建新的元数据条目，指向原表的不可变数据块（micro-partition / Parquet file / data page）。无需拷贝实际数据。
2. **写时复制（Copy-on-Write, COW）**：克隆和原表共享存储，直到任一方修改某个数据块——此时才复制该块。修改 1% 的数据 = 仅产生 1% 的额外存储。

这把克隆的两大成本——存储和时间——都压到接近零。50TB 的克隆瞬间完成，只在被修改的部分才付出存储代价。

**典型用途**：

1. **开发/测试环境隔离**：每个开发者一个克隆，互不干扰，DBA 一键创建。
2. **CI/CD 数据测试**：每次 PR 自动从生产 clone 出测试库，测试完丢弃。
3. **机器学习实验跟踪**：每个实验运行前 clone 一份训练数据 + 模型表，结果与数据状态绑定。
4. **灾难恢复演练**：定期 clone 生产库到隔离环境，演练完整恢复流程。
5. **Schema 变更预演**：先在 clone 上运行 DDL/迁移脚本，验证无误后再在生产执行。
6. **审计/法务取证**：对可疑事件后的数据库瞬间 clone，保留现场供取证分析。
7. **A/B 测试**：clone 后修改 schema/索引，对比性能；不影响生产基线。
8. **数据归档**：业务时点（如月底结算）clone 一份只读副本，长期保留作为不可变快照。

## 没有 SQL 标准

SQL:2011 / SQL:2016 / SQL:2023 都不涉及数据库或表克隆。这是一个完全实现定义的能力，与底层存储格式紧密绑定：

- **Snowflake** 的 CLONE 基于 micro-partition 的不可变性 + 元数据指针。
- **Oracle Multi-tenant** 的 PDB CLONE 基于物理数据文件的 ASM/文件系统拷贝（非零拷贝），但提供逻辑上的隔离。
- **SQL Server** 的 `DBCC CLONEDATABASE` 是 schema-only 克隆（不含数据），用于性能问题诊断。
- **PostgreSQL** 没有原生克隆，需要 `pg_dump` + `pg_restore` 或基于文件系统/存储层的快照（ZFS/LVM/EBS）。
- **Aurora** 的 storage clone 在分布式存储层做 COW，跨整个集群瞬间生效。
- **BigQuery** 的 CLONE 基于 Capacitor 存储格式的不可变性。
- **Delta Lake / Iceberg** 的 SHALLOW CLONE 是元数据克隆（仅复制 transaction log），DEEP CLONE 是物理拷贝（复制所有 Parquet 文件）。

虽然没有标准，主流数据仓库 + 湖仓格式已经形成了 `CREATE TABLE/DATABASE ... CLONE source` 这一事实约定，且零拷贝是默认期待。

## 支持矩阵

### 1. CREATE TABLE LIKE（schema-only 克隆，不含数据）

最普遍的克隆变种：仅复制表结构（列、约束、可选索引），不复制数据。SQL:2003 把它放在 `<column_definition>` 的 `LIKE` 子句中，多数引擎实现了。

| 引擎 | 关键字 | 复制约束 | 复制索引 | 复制默认值 | 版本 |
|------|--------|---------|---------|---------|------|
| PostgreSQL | `CREATE TABLE x (LIKE src INCLUDING ALL)` | 是 | 是 | 是 | 8.0+ |
| MySQL | `CREATE TABLE x LIKE src` | 是 | 是 | 是 | 4.1+ |
| MariaDB | `CREATE TABLE x LIKE src` | 是 | 是 | 是 | 5.0+ |
| SQLite | `CREATE TABLE x AS SELECT * FROM src LIMIT 0` | 否 | 否 | 部分 | 3.x |
| Oracle | `CREATE TABLE x AS SELECT * FROM src WHERE 1=0` | 否 | 否 | 是 | 8i+ |
| SQL Server | `SELECT * INTO x FROM src WHERE 1=0` | 否 | 否 | 部分 | 7.0+ |
| DB2 | `CREATE TABLE x LIKE src` | 是 | 否 | 是 | 9.5+ |
| Snowflake | `CREATE TABLE x LIKE src` | 是 | 是 | 是 | GA |
| BigQuery | `CREATE TABLE x LIKE src` | 部分 | -- | 是 | GA |
| Redshift | `CREATE TABLE x (LIKE src INCLUDING DEFAULTS)` | 是 | 是 | 是 | GA |
| DuckDB | `CREATE TABLE x AS SELECT * FROM src LIMIT 0` | 否 | 否 | 部分 | GA |
| ClickHouse | `CREATE TABLE x AS src` | 是 | 是 | 是 | 早期 |
| Trino/Presto | `CREATE TABLE x (LIKE src INCLUDING PROPERTIES)` | 部分 | -- | 是 | 早期 |
| Spark SQL | `CREATE TABLE x LIKE src` | 是 | 否 | 是 | 2.0+ |
| Hive | `CREATE TABLE x LIKE src` | 是 | 否 | 是 | 0.10+ |
| Databricks | `CREATE TABLE x LIKE src` | 是 | 是 | 是 | GA |
| Teradata | `CREATE TABLE x AS src WITH NO DATA` | 是 | 是 | 是 | V2R5+ |
| Greenplum | `CREATE TABLE x (LIKE src INCLUDING ALL)` | 是 | 是 | 是 | 继承 PG |
| CockroachDB | `CREATE TABLE x (LIKE src)` | 是 | 是 | 是 | 19.1+ |
| TiDB | `CREATE TABLE x LIKE src` | 是 | 是 | 是 | 兼容 MySQL |
| OceanBase | `CREATE TABLE x LIKE src` | 是 | 是 | 是 | 兼容 MySQL |
| YugabyteDB | `CREATE TABLE x (LIKE src INCLUDING ALL)` | 是 | 是 | 是 | 继承 PG |
| SingleStore | `CREATE TABLE x LIKE src` | 是 | 是 | 是 | 兼容 MySQL |
| Vertica | `CREATE TABLE x LIKE src INCLUDING PROJECTIONS` | 是 | 是 | 是 | 9.0+ |
| Impala | `CREATE TABLE x LIKE src` | 是 | -- | 是 | 早期 |
| StarRocks | `CREATE TABLE x LIKE src` | 是 | 是 | 是 | 2.0+ |
| Doris | `CREATE TABLE x LIKE src` | 是 | 是 | 是 | 1.0+ |

`CREATE TABLE LIKE` 是 schema-only 克隆，不属于真正的"零拷贝克隆"——它本质上只是元数据复制。但它为后续 `INSERT INTO ... SELECT` 提供基础。

### 2. CLONE 语句（零拷贝表/数据库克隆）

真正的零拷贝克隆，复制元数据 + 共享底层不可变数据块 + COW 写入。

| 引擎 | 表级 CLONE | 数据库级 CLONE | Schema 级 CLONE | Time Travel 克隆 | 版本 |
|------|-----------|---------------|----------------|-----------------|------|
| Snowflake | `CREATE TABLE x CLONE src` | `CREATE DATABASE x CLONE src` | `CREATE SCHEMA x CLONE src` | 是 (`AT/BEFORE`) | 2017 GA |
| BigQuery | `CREATE TABLE x CLONE src` | -- | -- | 是 (`FOR SYSTEM_TIME AS OF`) | 2022 GA (4 月) |
| Databricks (Delta Lake) | `CREATE TABLE x SHALLOW/DEEP CLONE src` | -- | -- | 是 (`VERSION AS OF`) | 9.1 (2021-09) |
| Iceberg | -- | -- | -- | 通过 metadata copy | 早期 |
| Aurora MySQL | -- | DB Cluster Clone (控制台/API) | -- | 是 (任意时点) | 2017 |
| Aurora PostgreSQL | -- | DB Cluster Clone | -- | 是 | 2017 |
| Oracle Multi-tenant | -- | `CREATE PLUGGABLE DATABASE x FROM src` | -- | 是 (Hot Clone) | 12c (2013) |
| SQL Server | -- | `DBCC CLONEDATABASE`（仅 schema + stats） | -- | -- | 2014 SP2 (2016-07) / 2016 SP1 (2016-11) |
| PostgreSQL | -- | `CREATE DATABASE x TEMPLATE src` (block copy) | -- | -- | 早期 (非零拷贝) |
| MySQL | -- | -- | -- | -- | 不支持 |
| MariaDB | -- | -- | -- | -- | 不支持 |
| SQLite | -- | -- | -- | -- | 不支持 |
| DB2 | -- | `db2move` (非零拷贝) | -- | -- | 早期 |
| Redshift | -- | `CREATE DATABASE x WITH FROM SNAPSHOT` | -- | 是 (任意 snapshot) | RA3+ |
| DuckDB | -- | -- | -- | -- | 不支持 (单进程) |
| ClickHouse | -- | -- | -- | 通过 part 硬链接 backup | 22.x+ (有限) |
| Trino/Presto | -- | -- | -- | 通过 Iceberg/Delta 连接器 | 398+ |
| Spark SQL | (Delta) `SHALLOW/DEEP CLONE` | -- | -- | 是 | 3.3+ |
| Hive | -- | -- | -- | 通过 Iceberg | Hive 4 |
| Flink SQL | -- | -- | -- | -- | 不支持 |
| Teradata | -- | `COPY DATABASE` (非零拷贝) | -- | -- | 早期 |
| Greenplum | -- | -- | -- | -- | 不支持 (基于 PG) |
| CockroachDB | -- | -- | -- | -- | 不支持 (KV 引擎) |
| TiDB | -- | -- | -- | -- | 不支持 (KV 引擎) |
| OceanBase | -- | -- | -- | -- | 不支持 |
| YugabyteDB | -- | -- | -- | -- | 不支持 |
| SingleStore | -- | -- | -- | -- | 不支持 |
| Vertica | -- | -- | -- | -- | 不支持 |
| Impala | (Iceberg) `CLONE` | -- | -- | 是 | 通过 Iceberg |
| StarRocks | -- | -- | -- | -- | 不支持 |
| Doris | -- | -- | -- | -- | 不支持 |
| MonetDB | -- | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | -- | 不支持 |
| TimescaleDB | -- | -- | -- | -- | 不支持 (基于 PG) |
| QuestDB | -- | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | -- | 不支持 |
| SAP HANA | -- | `CREATE DATABASE FROM SYSTEM` (recovery-based) | -- | -- | 1.0+ |
| Informix | -- | -- | -- | -- | 不支持 |
| Firebird | -- | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | 不支持 |
| Amazon Athena | -- | -- | -- | 通过 Iceberg | GA |
| Azure Synapse (Dedicated) | -- | `CREATE DATABASE x AS COPY OF src` | -- | -- | GA (CTAS 风格) |
| Azure SQL DB | -- | `CREATE DATABASE x AS COPY OF src` | -- | -- | GA |
| Google Spanner | -- | -- | -- | 通过 backup + restore | GA |
| Materialize | -- | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | -- | 不支持 |
| InfluxDB (SQL) | -- | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | 是 (基于对象存储) | GA |
| Yellowbrick | -- | -- | -- | -- | 基于 PG |
| Firebolt | -- | -- | -- | -- | 不支持 |
| MaxCompute | -- | -- | -- | 通过 Time Travel | GA |
| Pinot | -- | -- | -- | -- | 不支持 |
| Druid | -- | -- | -- | -- | 不支持 |

> 统计：约 8 个引擎提供原生零拷贝表/数据库克隆（Snowflake、BigQuery、Databricks、Aurora、Oracle Multi-tenant、Delta Lake、Iceberg、Spark SQL on Delta），约 4 个提供 schema-only 克隆，其余均不支持或仅有间接方案。

### 3. CTAS（CREATE TABLE AS SELECT）—— 与零拷贝不同

`CTAS` 是数据复制，**不是零拷贝**。它执行 SELECT 后把结果写入新表，付出全量 I/O 和存储代价。但语义灵活，可加 WHERE/JOIN/聚合。

| 引擎 | CTAS 语法 | 复制数据 | 复制约束 | 复制索引 | 备注 |
|------|----------|---------|---------|---------|------|
| PostgreSQL | `CREATE TABLE x AS SELECT * FROM src` | 是 | 否 | 否 | 仅 NOT NULL 保留 |
| MySQL | `CREATE TABLE x AS SELECT * FROM src` | 是 | 部分 | 否 | 主键不复制 |
| Oracle | `CREATE TABLE x AS SELECT * FROM src` | 是 | 部分 | 否 | NOT NULL 保留 |
| SQL Server | `SELECT * INTO x FROM src` | 是 | 部分 | 否 | NOT NULL + IDENTITY |
| Snowflake | `CREATE TABLE x AS SELECT * FROM src` | 是 (物理) | 部分 | -- | 与 CLONE 不同！ |
| BigQuery | `CREATE TABLE x AS SELECT * FROM src` | 是 | 部分 | -- | 与 CLONE 不同！ |
| Databricks | `CREATE TABLE x AS SELECT * FROM src` | 是 | 部分 | -- | 与 SHALLOW/DEEP CLONE 不同 |
| Trino | `CREATE TABLE x AS SELECT * FROM src` | 是 | -- | -- | 连接器相关 |
| Spark SQL | `CREATE TABLE x AS SELECT * FROM src` | 是 | -- | -- | 物理写入 |
| ClickHouse | `CREATE TABLE x AS src` (无 SELECT) | 否 (schema only) | 是 | -- | 注意：CH 的 AS 是 schema 复制 |
| ClickHouse | `INSERT INTO x SELECT * FROM src` | 是 | -- | -- | 真正的数据复制 |
| DuckDB | `CREATE TABLE x AS SELECT * FROM src` | 是 | 部分 | -- | NOT NULL 保留 |

**CTAS vs CLONE 的核心差异**：

| 维度 | CTAS | 零拷贝 CLONE |
|------|------|-------------|
| 数据移动 | 全量物理写入 | 0 字节（仅元数据） |
| 时间复杂度 | O(N) | O(1) |
| 存储成本 | 100% 数据大小 | 0%（写入前） |
| 灵活性 | 可加 WHERE / JOIN / 聚合 | 仅整表/库克隆 |
| 后续查询性能 | 与原表无差异 | 共享存储，可能影响缓存 |
| 适用场景 | 子集复制、变换 | 测试环境隔离、全量副本 |

### 4. 存储/EBS 快照集成（基础设施级克隆）

云原生数据库往往依赖底层存储的快照能力。

| 引擎 | EBS/Storage 快照 | 一致性保证 | 自动化 | 备注 |
|------|----------------|-----------|--------|------|
| Aurora MySQL/PG | 是 | crash-consistent | 是 (托管) | DB Cluster Snapshot + Clone |
| RDS MySQL/PG | 是 | crash-consistent | 是 (托管) | RDS Snapshot |
| Cloud SQL (GCP) | 是 | crash-consistent | 是 (托管) | -- |
| Azure SQL DB | 是 | application-consistent | 是 (托管) | Geo-Redundant |
| Snowflake | 内建 | 透明 | 是 | 不暴露底层快照 |
| BigQuery | 内建 | 透明 | 是 | 不暴露底层快照 |
| Spanner | 内建 | 透明 | 是 | 不暴露底层快照 |
| Self-managed PostgreSQL on EBS | 是 | crash-consistent | 否 | 需 `pg_start_backup()` 标记 |
| Self-managed MySQL on EBS | 是 | crash-consistent | 否 | 需 FTWRL 标记 |
| Oracle on ASM | 是 | physical-consistent | 否 | RMAN level + storage snapshot |
| MongoDB on EBS | 是 | application-consistent | 否 | 需 `db.fsyncLock()` |
| ClickHouse | 是 | physical-consistent | 否 | parts 不可变 |
| Elasticsearch | 是 | application-consistent | 是 | snapshot repository |

**EBS snapshot + Aurora storage clone 的本质区别**：EBS snapshot 是块设备级 COW，但需要恢复（detach + attach + start engine）；Aurora storage clone 直接在分布式存储引擎里改元数据指针，挂载新集群即可，秒级生效。

### 5. 克隆元数据 vs 数据

不同引擎对"克隆"的语义解释差异很大：

| 引擎 | CLONE 复制元数据 | CLONE 复制数据 | 成本模型 |
|------|---------------|---------------|---------|
| Snowflake | 是 | 共享 (COW) | 0 存储增长直到写入 |
| BigQuery | 是 | 共享 (COW) | 0 存储增长直到写入 |
| Aurora | 是 | 共享 (COW) | 0 存储增长直到写入 |
| Delta Lake SHALLOW CLONE | 是 (transaction log copy) | 共享 (COW) | 0 数据存储增长 |
| Delta Lake DEEP CLONE | 是 | 完整复制 | 100% 存储成本 |
| Oracle PDB CLONE (Hot) | 是 | 完整复制（默认）/ COW (sparse) | 100% (默认) / COW (12.2+) |
| SQL Server DBCC CLONEDATABASE | 是 (schema + stats) | 否 | 仅 schema 大小 |
| PostgreSQL CREATE DATABASE TEMPLATE | 是 | 块级物理拷贝 | 100% 存储成本 |
| Iceberg CLONE | 是 (manifest copy) | 共享 (COW) | 0 数据存储增长 |

**这张表是理解克隆能力的关键**：很多引擎号称支持"CLONE"，但只有少数（Snowflake、BigQuery、Aurora、Delta Lake SHALLOW、Iceberg）真正做到 0 存储成本。

## Snowflake 零拷贝克隆深度剖析

Snowflake 在 2017 年正式 GA `CLONE` 关键字，至今仍是行业标杆。理解 Snowflake CLONE 有助于理解所有现代云数仓的克隆模型。

### 1. 基础语法

```sql
-- 表克隆
CREATE TABLE customers_clone CLONE customers;

-- Schema 克隆（一次克隆 schema 下所有表 + view + procedure）
CREATE SCHEMA prod_clone CLONE production;

-- 数据库克隆（一次克隆整个数据库）
CREATE DATABASE staging CLONE production;

-- Time Travel 克隆（克隆某个历史时点的状态）
CREATE TABLE orders_yesterday CLONE orders AT(OFFSET => -86400);
CREATE TABLE orders_q1_end CLONE orders AT(TIMESTAMP => '2024-03-31 23:59:59'::TIMESTAMP);
CREATE TABLE orders_before_disaster CLONE orders BEFORE(STATEMENT => '01a5e1b7-0000-...');

-- 数据库 + Time Travel
CREATE DATABASE production_yesterday CLONE production AT(OFFSET => -86400);
```

### 2. micro-partition 不可变性是基础

Snowflake 的存储模型把表分成大量 **micro-partition**（约 50-500MB 压缩列存）。每个 micro-partition 一旦写入就**永久不可变**：

- INSERT 创建新 micro-partition
- UPDATE = 创建新 micro-partition（含修改后的行）+ 把旧 partition 标记为 inactive
- DELETE = 把 partition 中的特定行标记为已删除（通过 metadata），或重写 partition

由于 micro-partition 不可变，多个表可以**安全地共享同一份物理 partition**，只要各自的元数据正确记录了"我引用了哪些 partition"。

### 3. CLONE 的实现原理

```
CREATE TABLE clone_a CLONE original;

实际操作：
1. 在元数据服务（FoundationDB 类的 KV）中创建 clone_a 表条目
2. 把 original 当前的 micro-partition 引用列表完整复制给 clone_a
3. 标记 clone_a 的 partition 为"shared with original"
4. 完成（耗时 ~毫秒，与表大小无关）
```

**关键观察**：

- 创建 1TB 表的 clone 和创建 1KB 表的 clone 耗时几乎相同。
- clone 创建后，**实际存储未增加任何字节**（相比克隆前）。
- clone_a 和 original 是两个独立的逻辑表：可独立 SELECT、INSERT、UPDATE、DELETE，互不干扰。

### 4. Copy-on-Write 写入机制

```sql
-- 假设 original 有 100 个 micro-partition (M1, M2, ..., M100)
CREATE TABLE clone_a CLONE original;
-- 此时 clone_a 也引用 M1..M100

-- 在 clone_a 上 UPDATE 1 行（恰好命中 M50）
UPDATE clone_a SET status = 'X' WHERE order_id = 12345;
-- 内部行为：
--   1. 读取 M50 的内容
--   2. 在内存中修改 order_id=12345 的行
--   3. 写出新的 micro-partition M50' （包含修改后的 M50 内容）
--   4. clone_a 的元数据更新：M50 → M50'
--   5. clone_a 现在引用 M1..M49, M50', M51..M100
--   6. original 仍然引用 M1..M100（不受影响）

-- 此时存储增加：仅 M50' 的大小（约 1 个 partition，可能几十 MB）
-- 原始 100 个 partition 仍然是共享的
```

**写入成本随修改量按比例增长**：

- 修改 1% 数据 → 增加约 1% 存储
- 修改 50% 数据 → 增加约 50% 存储
- 全表覆盖 → 增加 100% 存储（等同于完整复制）

### 5. 克隆的链式结构

```sql
-- 克隆可以再被克隆
CREATE DATABASE prod CLONE production;
CREATE DATABASE dev CLONE prod;
CREATE DATABASE feature_xyz CLONE dev;

-- 内部形成 partition 引用的"森林"结构
-- 每个 partition 可能被多个数据库共享引用
-- Snowflake 用引用计数 + 元数据回收机制管理生命周期
```

链式克隆有几个细节：

- **删除原始表**：如果删除了 `production`，但 `prod` / `dev` / `feature_xyz` 还在，underlying partition 不会被删除（引用计数 > 0）。
- **Time Travel 与克隆叠加**：可以从 prod 的某个历史时点克隆出新数据库。
- **存储分摊**：底层 micro-partition 的存储成本由所有引用它的表分摊（按 Snowflake 计费规则）。

### 6. 不被克隆的对象

Snowflake CLONE 不包括：

- **临时表（Temporary tables）**：会话级生命周期，不可克隆。
- **外部表（External tables）**：指向外部对象存储，无 micro-partition。
- **Stage / Pipe / Stream / Task**：管道对象有运行时状态，不可克隆。
- **私有 stage 中的文件**：不属于表数据。

但被克隆：表、视图、序列、文件格式、masking policy、row access policy 等元数据对象。

### 7. 克隆与 Time Travel 的协同

```sql
-- "回滚" 一张被误操作的表（业务级 PITR）
-- 步骤 1: 克隆 24 小时前的状态
CREATE TABLE customers_safe CLONE customers AT(OFFSET => -86400);

-- 步骤 2: 验证数据是否正确
SELECT COUNT(*) FROM customers_safe WHERE created_at > '2024-01-01';

-- 步骤 3: 切换（用 SWAP，原子化）
ALTER TABLE customers SWAP WITH customers_safe;

-- 步骤 4: 删除旧表（实际是被换走的"坏"版本）
DROP TABLE customers_safe;

-- 整个流程 + 大表（TB 级）耗时仍是秒级
```

这套"clone + swap" 模式比传统的 RESTORE 快几个数量级，是 Snowflake 用户处理数据事故的标准做法。

### 8. 克隆的限制与陷阱

```sql
-- 1. 克隆不复制 GRANT（默认）
CREATE DATABASE staging CLONE production;
-- staging 上的权限完全继承自创建者，不复制 production 的 GRANT
-- 需要 COPY GRANTS 才能复制权限：
CREATE TABLE x CLONE source COPY GRANTS;

-- 2. CLONE 是 DDL，会立即生效（无事务）
-- 不能 BEGIN; CREATE TABLE x CLONE src; ROLLBACK;

-- 3. Time Travel 窗口外的 OFFSET 会失败
CREATE TABLE old CLONE src AT(OFFSET => -90 * 86400);  -- 仅 Enterprise 90 天

-- 4. 跨账户 / 跨 region 无法直接 CLONE
-- 需要先 SHARE 再 CLONE，或用 Replication
```

## Aurora Storage Cloning 架构

Amazon Aurora 在 2017 年推出 **DB Cluster Cloning**，把零拷贝克隆下沉到分布式存储层。这是云原生数据库存储引擎层创新的代表。

### 1. Aurora 存储架构回顾

Aurora 的核心架构特征：

- 计算节点（DB Instance）和存储节点（Storage）分离
- 存储数据切成 **10GB segment**，每个 segment 有 6 副本（跨 3 AZ）
- 计算只发送 redo log 到存储，存储自己 apply log 重建 page
- 这个架构使得"页级 COW" 成为存储原生能力

### 2. DB Cluster Clone 的本质

```
原始 Aurora 集群:
  Cluster A → Segment 集合 {S1, S2, ..., Sn}
              每个 Segment 内部有版本链表

Clone 集群:
  Cluster B → 元数据指针，指向相同 {S1, S2, ..., Sn}
              但 Cluster B 启动后任何写入都产生新版本
              新版本对 Cluster A 不可见

物理上:
  - Segment 没有被复制
  - 元数据多了一份"我也指向这些 segment"的引用
  - 后续任何 Cluster B 的写入都创建该 page 的新版本
  - Cluster A 的 page 版本链不受影响
```

### 3. AWS 控制台 / API 操作

```bash
# 通过 AWS CLI 创建 clone
aws rds restore-db-cluster-to-point-in-time \
    --source-db-cluster-identifier prod-cluster \
    --db-cluster-identifier dev-clone-2024-01-15 \
    --restore-type copy-on-write \
    --use-latest-restorable-time

# 关键参数：
#   --restore-type copy-on-write   <-- 这是 clone 模式
#   --restore-type full-copy       <-- 这是传统恢复（全量复制）
```

```sql
-- Clone 后的集群是一个独立的 Aurora Cluster
-- 拥有独立的 endpoint、独立的计算节点、独立的写入点
-- 可以在 clone 上做任何 DDL/DML，不影响原始集群
```

### 4. 与 Snowflake CLONE 的对比

| 维度 | Aurora Storage Clone | Snowflake CLONE |
|------|---------------------|-----------------|
| 粒度 | 整个 Cluster | 表/Schema/Database |
| 接口 | AWS API / 控制台 | SQL DDL |
| 启动时间 | 几分钟（启动新计算节点） | 毫秒（仅元数据） |
| 计费 | 计算独立计费，存储 COW 计费 | 计算独立计费，存储 COW 计费 |
| Time Travel | 任意 PITR 时点 | 1-90 天 Time Travel 窗口 |
| 跨 region | 部分支持（需 Global Database） | 需 Replication |
| 单表克隆 | 否（只能整集群） | 是 |
| 透明性 | 用户感知存储层 | 完全透明 |

**Aurora 的优势**：基于现有数据库引擎（MySQL/PostgreSQL），SQL 兼容性 100%。

**Snowflake 的优势**：粒度细，可以单表克隆；克隆是 SQL DDL，可脚本化、可与 CI/CD 流水线集成。

### 5. Aurora Clone 的应用场景

```
1. CI/CD：每次 PR 触发 clone → 跑测试 → 自动销毁
2. 数据分析：从 prod clone 出来给 BI 团队，不影响 OLTP 性能
3. 大型 schema 变更：在 clone 上演练 ALTER TABLE，验证耗时和锁影响
4. 灾难演练：定期 clone 全量数据库，演练恢复流程
5. 分支开发：每个开发分支一个 clone，feature 完成后销毁
```

## Delta Lake SHALLOW CLONE vs DEEP CLONE

Databricks 在 2021 年 9 月（DBR 9.1）正式发布 Delta Lake CLONE 命令，提供 SHALLOW 和 DEEP 两种模式。这两种模式的差异是理解"克隆" 概念光谱的最佳例子。

### 1. SHALLOW CLONE（浅克隆，零拷贝）

```sql
-- 创建浅克隆
CREATE TABLE shallow_clone SHALLOW CLONE source_table;

-- Time Travel 浅克隆
CREATE TABLE shallow_clone_v5 SHALLOW CLONE source_table VERSION AS OF 5;
CREATE TABLE shallow_clone_yesterday SHALLOW CLONE source_table TIMESTAMP AS OF '2024-01-15 00:00:00';
```

**SHALLOW CLONE 的本质**：

- **复制 transaction log（_delta_log）的当前快照**：把 `_delta_log/00000000000000000123.json` 这种文件复制到目标表的 `_delta_log/`。
- **不复制 Parquet 数据文件**：transaction log 中的 `add` 条目仍然指向源表的 Parquet 路径。
- **零数据存储成本**：只增加一个新的 `_delta_log/` 目录及其元数据 JSON。

**写时复制**：

```sql
-- 在 shallow_clone 上 INSERT
INSERT INTO shallow_clone VALUES (...);
-- 行为：
--   1. 写入新的 Parquet 文件到 shallow_clone 的目录下
--   2. 在 shallow_clone 的 _delta_log 中追加 commit (含新 add 条目)
--   3. 源表 source_table 完全不受影响

-- 在 shallow_clone 上 DELETE
DELETE FROM shallow_clone WHERE x = 1;
-- 行为：
--   1. 在 shallow_clone 的 _delta_log 追加 commit (含 remove 条目)
--   2. remove 条目指向源表的某个 Parquet 文件
--   3. 源表的 Parquet 文件没有被物理删除（其他读者可能还在用）
```

### 2. DEEP CLONE（深克隆，物理复制）

```sql
-- 创建深克隆
CREATE TABLE deep_clone DEEP CLONE source_table;

-- Time Travel 深克隆
CREATE TABLE deep_clone_v5 DEEP CLONE source_table VERSION AS OF 5;
```

**DEEP CLONE 的本质**：

- **物理复制所有 Parquet 数据文件**：把源表 `add` 条目指向的所有 Parquet 文件复制到目标表的目录。
- **复制 transaction log**：但其中的 `add` 条目指向新位置（目标表的 Parquet 副本）。
- **完全独立**：删除源表也不影响 deep clone。

**适用场景**：

- 跨集群/跨 region 迁移：需要数据物理在目标位置
- 长期归档：源表可能被删除/清理
- 满足合规要求：监管要求数据物理隔离

### 3. SHALLOW vs DEEP 对比

| 维度 | SHALLOW CLONE | DEEP CLONE |
|------|--------------|------------|
| 数据复制 | 否 | 是（全部 Parquet） |
| 元数据复制 | 是 (_delta_log 当前 snapshot) | 是 |
| 时间 | 秒级（与表大小无关） | O(N)（按数据量） |
| 存储成本 | 0 (写入前) | 100% |
| 删除源表的影响 | 浅克隆失效 | 深克隆完全独立 |
| 跨存储位置 | 否（共享底层路径） | 是（可写到任意位置） |
| 写入隔离 | 独立 transaction log | 独立 transaction log |
| 适用场景 | 测试、CI/CD、短期实验 | 迁移、归档、长期独立副本 |

### 4. CLONE 与 CTAS 的对比

```sql
-- CTAS: 物理写入（每行都重写）
CREATE TABLE ctas_table AS SELECT * FROM source_table;
-- 等价于：DEEP CLONE，但不保留 transaction log 历史

-- DEEP CLONE: 物理写入 + 保留版本历史
CREATE TABLE deep_clone_table DEEP CLONE source_table;
-- 与 CTAS 不同：保留了源表的所有 transaction log

-- SHALLOW CLONE: 仅元数据
CREATE TABLE shallow_clone_table SHALLOW CLONE source_table;
-- 与 CTAS 完全不同：0 数据写入
```

### 5. 增量 CLONE（Incremental Clone）

Delta Lake 支持对已有 clone 做增量更新（CLONE 命令幂等）：

```sql
-- 第一次 clone
CREATE TABLE my_clone SHALLOW CLONE source_table;
-- 后续源表有更新

-- 重新执行 CLONE，会增量更新 my_clone
CREATE OR REPLACE TABLE my_clone SHALLOW CLONE source_table;
-- 行为：
--   1. 比较两个 _delta_log 的版本差
--   2. 把源表新增的 commit 应用到 my_clone
--   3. 期间 my_clone 的写入会冲突（需要协调）
```

这一能力让 SHALLOW CLONE 成为"低延迟同步"的工具：源表每小时更新，clone 每小时增量同步，存储成本仍然接近 0。

### 6. CLONE 在 Iceberg / Hudi 中的对应能力

| 格式 | SHALLOW 等价 | DEEP 等价 | 备注 |
|------|-------------|----------|------|
| Iceberg | 通过 metadata file copy | 通过 `CTAS + REWRITE` | 没有专门的 CLONE 命令 |
| Hudi | 通过 metadata copy | 通过 BulkInsert | 较少使用 |
| Delta Lake | `SHALLOW CLONE` | `DEEP CLONE` | 命令最完整 |

## Oracle Multi-tenant PDB Clone

Oracle 12c (2013) 引入多租户架构（CDB + PDB），同时支持 PDB 克隆。这是传统商业数据库对零拷贝克隆的早期尝试。

### 1. PDB Clone 基础语法

```sql
-- 在同一个 CDB 中克隆 PDB
CREATE PLUGGABLE DATABASE pdb_clone FROM pdb_source;

-- Hot clone（源 PDB 处于 OPEN READ WRITE 状态时克隆）
ALTER SESSION SET CONTAINER = CDB$ROOT;
CREATE PLUGGABLE DATABASE pdb_clone FROM pdb_source;
ALTER PLUGGABLE DATABASE pdb_clone OPEN;

-- 跨 CDB 克隆（远程克隆）
CREATE PLUGGABLE DATABASE pdb_clone
FROM pdb_source@dblink_to_remote_cdb;
```

### 2. 三种 Clone 模式

| 模式 | 数据复制 | 存储成本 | 启动时间 | 版本要求 |
|------|---------|---------|---------|---------|
| Cold Clone | 完整复制 | 100% | O(N) | 12.1+ |
| Hot Clone | 完整复制 + 在线 | 100% | O(N) | 12.2+ |
| Snapshot Copy (sparse) | COW (基于 ASM/CFS) | 接近 0 (写入前) | O(1) | 12.1+ (需特定存储) |

```sql
-- Snapshot Copy 模式（接近零拷贝，依赖底层存储能力）
CREATE PLUGGABLE DATABASE pdb_clone FROM pdb_source
SNAPSHOT COPY;
-- 要求：
--   1. 数据文件存储在 ACFS（Oracle ASM Cluster File System）或
--      支持 sparse clone 的文件系统（Direct NFS、ZFS 等）
--   2. 源 PDB 必须 OPEN READ ONLY（早期版本）或 READ WRITE（12.2+）
```

### 3. 与 Snowflake CLONE 的对比

```
Snowflake CLONE:
  - 不依赖底层文件系统
  - 任意环境（云）都能用
  - 真正零拷贝（micro-partition 共享）

Oracle PDB SNAPSHOT COPY:
  - 依赖 ACFS / sparse-capable filesystem
  - 受存储类型限制
  - 使用 sparse file 实现零拷贝（OS 层）
```

### 4. PDB Clone 的局限

- **TDE 加密**：源 PDB 用 TDE 时，clone 需要 transport key
- **跨 CDB 克隆**：需要 dblink 和 transport tablespace
- **Hot Clone 的额外成本**：12.2 之前 Hot Clone 仍是物理复制，开销与 Cold Clone 相同
- **生产案例**：Snapshot Copy 在生产环境部署较少（要求高，文档有限）

## SQL Server DBCC CLONEDATABASE

SQL Server 在 2014 SP2 (2016-07) / 2016 SP1 (2016-11) 引入 `DBCC CLONEDATABASE`，但它是一个**特殊用途**的克隆命令——不是给业务用的"零拷贝克隆"，而是给 Microsoft 工程师/DBA 用的"性能问题诊断工具"。

### 1. 基础用法

```sql
-- 克隆数据库（schema + 统计信息，不含数据）
DBCC CLONEDATABASE ('production', 'production_clone');

-- 克隆后默认是 read-only 状态
-- 用 SQL Server Profiler / Extended Events 在 clone 上重放生产工作负载
-- 验证查询计划是否相同（用于复现性能问题）
```

### 2. CLONEDATABASE 复制了什么

| 对象类型 | 是否复制 | 备注 |
|---------|---------|------|
| 表结构 | 是 | DDL 完整复制 |
| 索引 | 是 | 包括索引统计 |
| 视图 | 是 | -- |
| 存储过程 | 是 | -- |
| 触发器 | 是 | -- |
| 约束 | 是 | -- |
| **统计信息** | 是 | 关键！用于复现优化器选择 |
| **表数据** | **否** | 这就是为什么仅用于诊断 |
| 用户/权限 | 部分 | 仅 schema-bound 对象 |
| 文件组结构 | 是 | -- |

### 3. 真正用途：复现性能问题

```
DBA 场景：
  生产环境的某个查询变慢了，但生产数据 100GB 不能下载到测试机。
  解决方案：
  1. DBCC CLONEDATABASE 创建 schema-only + stats 副本
  2. 备份 clone 数据库（仅几十 MB）
  3. 在测试机恢复
  4. 在测试机上 EXPLAIN 该慢查询
  5. 由于统计信息相同，优化器会选择相同的执行计划
  6. 在测试机调试索引、提示等
  7. 不需要传输生产数据
```

这是 SQL Server 独有的"诊断模式" 克隆，**不是零拷贝克隆**，也不能用于业务环境隔离。

### 4. SQL Server 真正的"克隆"是什么

| SQL Server 功能 | 类型 | 数据 | 零拷贝 |
|---------------|------|------|--------|
| `DBCC CLONEDATABASE` | 诊断 | 否 (schema only + stats) | n/a |
| Database Snapshot (`CREATE DATABASE x AS SNAPSHOT OF y`) | 只读 | 是 (sparse file COW) | 是 (源不变) |
| BACUP/RESTORE | 完整复制 | 是 | 否 |
| Always On secondary | 同步副本 | 是 | 否 (流复制) |
| Azure SQL `CREATE DATABASE x AS COPY OF y` | 异步 copy | 是 | 否 (CTAS 风格) |

**SQL Server 没有真正的 SQL DDL 形式的零拷贝克隆**。Database Snapshot 接近零拷贝（sparse file），但是只读的，不能写入。

### 5. Database Snapshot（与 CLONEDATABASE 不同）

```sql
-- 创建只读 snapshot（基于 NTFS sparse file）
CREATE DATABASE production_snapshot ON
    (NAME = production_data, FILENAME = 'C:\Snapshots\production_snap.ss')
AS SNAPSHOT OF production;

-- 此时 production_snapshot 是只读的
-- 物理上是 sparse file（仅记录与 source 不同的页）
-- 当 production 修改某 page 时，先复制原 page 到 snapshot 文件，再修改 production
-- 这是经典的 "redirect on write" 而非 "copy on write"

-- 用途：作为时间点的只读副本，用于报表查询、误操作恢复
SELECT * FROM production_snapshot.dbo.orders WHERE order_id = 123;

-- 误操作恢复
RESTORE DATABASE production FROM DATABASE_SNAPSHOT = 'production_snapshot';
```

Database Snapshot 是 SQL Server 在 2005 引入的，技术上是**写时复制**（向源写入时把原页复制到 snapshot 文件），但 snapshot 本身**只读**。这与"可读写的零拷贝克隆"是不同的概念。

## BigQuery Table Clone

BigQuery 在 2022 年 4 月 GA `CREATE TABLE ... CLONE` 命令，对标 Snowflake 的能力。

### 1. 基础语法

```sql
-- 表克隆
CREATE TABLE my_dataset.customers_clone CLONE my_dataset.customers;

-- Time Travel 克隆（7 天内任意时点）
CREATE TABLE my_dataset.customers_yesterday
CLONE my_dataset.customers
FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY);
```

### 2. BigQuery CLONE 的存储模型

```
原始表 customers:
  存储为 Capacitor 列式格式的不可变 block
  block 集合: {B1, B2, ..., Bn}

CLONE customers → customers_clone:
  仅创建表元数据，引用相同的 block 集合
  block 不复制
  metadata 维护引用关系

写入 customers_clone:
  生成新 block，仅 customers_clone 引用
  原始 block 仍由 customers 引用
```

### 3. 计费模型

BigQuery 对 clone 的计费有特殊规则：

- **存储**：clone 创建时不增加任何存储费用（共享底层 block）
- **写入后**：clone 修改产生的新 block，按 clone 表自己的存储费用计算
- **Long-term storage**：90 天未修改的表自动降级到 long-term storage（半价）。clone 与源各自独立计算 long-term 时间。
- **Time Travel 窗口**：clone 自身有独立的 7 天 Time Travel 窗口

### 4. 与 BigQuery TABLE SNAPSHOT 的区别

```sql
-- TABLE SNAPSHOT：只读副本（早 2 年发布）
CREATE SNAPSHOT TABLE my_dataset.customers_snap
CLONE my_dataset.customers;
-- 不可写，类似 SQL Server Database Snapshot

-- TABLE CLONE：可读写副本
CREATE TABLE my_dataset.customers_clone
CLONE my_dataset.customers;
-- 可写，类似 Snowflake CLONE
```

| 特性 | TABLE SNAPSHOT | TABLE CLONE |
|------|---------------|-------------|
| 可写 | 否 | 是 |
| 存储 | 仅 delta（基线指针） | 仅 delta（基线指针） |
| Time Travel | 是 | 是 |
| GA 时间 | 2021 | 2022 (4 月) |
| 用途 | 归档、合规、审计 | 测试、CI/CD、实验 |

### 5. BigQuery 的限制

- 仅支持表级 CLONE，不支持 dataset 或 project 级
- View / materialized view / external table 不可 CLONE
- CLONE 后的表可以再被 CLONE，但有"克隆深度"限制（实际通常足够）
- 跨 region CLONE 需要先 EXPORT/IMPORT，不能直接 CLONE

## PostgreSQL：缺失的 CLONE 与替代方案

PostgreSQL 至今（17）没有原生的零拷贝 `CLONE` 命令。常见替代方案：

### 1. CREATE DATABASE TEMPLATE（块级物理拷贝）

```sql
-- 基于现有数据库创建副本（块级物理拷贝，非零拷贝）
CREATE DATABASE staging TEMPLATE production;
-- 内部行为：
--   1. 锁定 production 数据库（拒绝新连接）
--   2. 把所有 page 从 production 物理拷贝到 staging
--   3. 修改 pg_database 元数据
--   4. 释放锁

-- 限制：
--   1. 源数据库必须没有活动连接（除超级用户外）
--   2. 复制时间 = O(数据库大小)
--   3. 存储成本 = 100% 数据库大小
--   4. 无 Time Travel
```

### 2. pg_dump + pg_restore

```bash
# 逻辑导出 + 导入
pg_dump -d production --jobs=8 --format=directory -f /tmp/dump
psql -d staging -c "DROP DATABASE IF EXISTS staging_new;"
psql -d staging -c "CREATE DATABASE staging_new;"
pg_restore -d staging_new --jobs=8 /tmp/dump

# 优点: 平台无关、可选择性导出
# 缺点: 速度慢、需要双倍存储中转
```

### 3. 文件系统/存储层快照（间接零拷贝）

```bash
# ZFS snapshot + clone
zfs snapshot tank/pgdata@snap1
zfs clone tank/pgdata@snap1 tank/pgdata-clone
# 启动新 PostgreSQL 实例指向 tank/pgdata-clone
# 修改 postgresql.conf 中的 port 避免冲突

# LVM snapshot + 启动新实例
lvcreate --snapshot --name pgdata_snap --size 10G /dev/vg/pgdata
# 在 snap 上启动新 PG 实例

# AWS EBS snapshot + 创建新 volume
aws ec2 create-snapshot --volume-id vol-xxx
aws ec2 create-volume --snapshot-id snap-yyy
# attach 到新 EC2 启动 PG
```

存储层快照实现了"零拷贝"，但需要 OS/云基础设施配合，不是 SQL 原生能力。

### 4. PostgreSQL 17 引入的 pg_createsubscriber

```bash
# PG 17 (2024) 引入：把 streaming replica 转换为独立 cluster
pg_createsubscriber -d mydb -D /var/lib/postgresql/replica
# 这不是真正的零拷贝克隆，但可以快速创建一个独立可写的副本
```

### 5. Aurora PostgreSQL 的 storage clone

如前所述，Aurora PG 在存储层支持零拷贝集群克隆，是云上 PostgreSQL 用户的最佳方案。

### 6. Supabase / Neon 的"分支" 概念

新一代 Postgres 即服务（Neon、Supabase）借鉴 Snowflake/Aurora 的思想：

```bash
# Neon CLI 创建分支（基于 PG 的存储层 COW）
neon branch create --name dev-branch --parent main
# 几秒内创建一个完整的 PG 数据库副本
# 共享底层 page，写入时 COW

# 类似 git branch 模型，每个开发者一个分支
```

这是 Postgres 生态对"零拷贝克隆"需求的最新回应。

## CockroachDB / TiDB / ClickHouse：分布式与列存引擎的克隆挑战

CockroachDB 和 TiDB 都没有原生 CLONE 命令。它们的存储模型——数据分散在多个 range/region 上、每个 range 跨 3 副本、数据是 KV 形式（没有"micro-partition"或"data file"概念）、所有写入通过 Raft 协议同步——使得零拷贝克隆所要求的"不可变数据块 + 元数据指针"不再天然成立：KV 数据不是不可变（虽然 RocksDB 的 SST 是不可变的），跨 range 的克隆需要协调多个 Raft group，元数据共享会破坏副本独立性。

替代方案是 BACKUP + RESTORE：

```sql
-- CockroachDB
BACKUP DATABASE production INTO 's3://my-bucket/backup' AS OF SYSTEM TIME '-10s';
RESTORE DATABASE production FROM LATEST IN 's3://my-bucket/backup';

-- TiDB BR (Backup & Restore)
br backup db --pd "pd-host:2379" --db "production" --storage "s3://bucket/backup"
br restore db --pd "pd-host:2379" --db "production" --storage "s3://bucket/backup"
```

这是物理拷贝，不是零拷贝；但 BR 支持增量备份，可以高效更新。TiDB BR 工作流通过 PD 获取全局一致 TSO，各 TiKV 节点并行 export SST 到 S3，速度可达 TB/小时级别，但仍然是 O(N) 数据量的复制。CockroachDB 的 PITR 能力强，但仍然依赖 BACKUP。学术界探讨过基于 LSM-tree 的零拷贝克隆方案（共享 SST + COW MemTable），CockroachDB 团队曾在博客讨论过类似设计，但工业界尚未广泛采纳。

ClickHouse 的 MergeTree 中 **part** 是不可变的，理论上具备零拷贝克隆的基础。22.x 引入的 BACKUP / RESTORE 命令内部使用 hard link，几乎是零拷贝，但只是文件系统层的 link，不是 SQL 级别的"可写克隆"。最接近的"克隆"操作是 `ALTER TABLE dst ATTACH PARTITION '202401' FROM src` 或 `ATTACH PART`，但这些是物理移动而非复制，需要文件系统级操作，不是用户友好的 SQL DDL。ClickHouse 缺少统一的 transaction log（22.3 引入 KeeperMap、Coordination/ZooKeeper 协调，但仍非完整事务日志）、元数据-only 复制原语（CLONE TABLE 命令）以及 Time Travel 查询能力。社区有 issue 讨论引入 CLONE 命令，截至 2024 年仍未实现。

## 各引擎语法详解

### Snowflake

```sql
-- 基本表克隆
CREATE TABLE customers_dev CLONE production.public.customers;

-- 创建并复制权限
CREATE TABLE customers_dev CLONE production.public.customers
COPY GRANTS;

-- Time Travel 克隆
CREATE TABLE customers_yesterday
CLONE production.public.customers
AT(OFFSET => -86400);

-- 数据库克隆
CREATE DATABASE prod_clone CLONE production;

-- Schema 克隆
CREATE SCHEMA dev_schema CLONE production.public;

-- 临时克隆（会话结束后销毁）
CREATE TEMPORARY TABLE customers_test CLONE customers;

-- 用替换语法在 clone 上做"逻辑回滚"
CREATE OR REPLACE TABLE customers
CLONE customers_archive AT(OFFSET => -3600);
```

### BigQuery

```sql
-- 基本表克隆
CREATE TABLE my_project.dataset.customers_clone
CLONE my_project.dataset.customers;

-- Time Travel 克隆（最多 7 天）
CREATE TABLE my_project.dataset.customers_yesterday
CLONE my_project.dataset.customers
FOR SYSTEM_TIME AS OF TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY);

-- 跨 dataset 克隆
CREATE TABLE my_project.dev_dataset.customers
CLONE my_project.prod_dataset.customers;

-- 注意：没有 DATABASE/SCHEMA 级 CLONE
-- 需要手动逐表 CLONE
```

### Databricks / Spark SQL (Delta Lake)

```sql
-- SHALLOW CLONE（零拷贝）
CREATE TABLE dev_db.customers SHALLOW CLONE prod_db.customers;

-- DEEP CLONE（物理复制）
CREATE TABLE archive_db.customers_2024_q1 DEEP CLONE prod_db.customers;

-- Time Travel CLONE
CREATE TABLE customers_v100
SHALLOW CLONE prod_db.customers VERSION AS OF 100;

CREATE TABLE customers_yesterday
SHALLOW CLONE prod_db.customers TIMESTAMP AS OF '2024-01-15 00:00:00';

-- 增量更新已存在的 clone
CREATE OR REPLACE TABLE my_clone SHALLOW CLONE source_table;

-- 在 SHALLOW CLONE 上写入
INSERT INTO dev_db.customers VALUES ('new', 'customer');
-- 写入只影响 clone，源表不变
```

### Oracle

```sql
-- 在同一 CDB 中 Cold Clone
ALTER PLUGGABLE DATABASE pdb_source CLOSE;
ALTER PLUGGABLE DATABASE pdb_source OPEN READ ONLY;
CREATE PLUGGABLE DATABASE pdb_clone FROM pdb_source;
ALTER PLUGGABLE DATABASE pdb_clone OPEN;
ALTER PLUGGABLE DATABASE pdb_source OPEN READ WRITE;

-- Hot Clone (12.2+)
CREATE PLUGGABLE DATABASE pdb_clone FROM pdb_source;
-- 自动 hot clone（源仍然 OPEN READ WRITE）

-- Snapshot Copy（接近零拷贝，需 ACFS / sparse FS）
CREATE PLUGGABLE DATABASE pdb_clone FROM pdb_source
SNAPSHOT COPY;

-- 跨 CDB 远程克隆
CREATE PLUGGABLE DATABASE pdb_clone FROM pdb_source@remote_cdb;
```

### SQL Server

```sql
-- DBCC CLONEDATABASE（schema + 统计，不含数据）
DBCC CLONEDATABASE ('production', 'production_diag_clone');

-- Database Snapshot（只读，sparse file COW）
CREATE DATABASE production_snap ON
    (NAME = production_data,
     FILENAME = 'C:\Snapshots\production_snap.ss')
AS SNAPSHOT OF production;

-- 注意：CLONEDATABASE 默认 read-only
-- 需要修改：
ALTER DATABASE production_diag_clone SET READ_WRITE;
```

### Azure SQL Database

```sql
-- AS COPY OF（异步全量复制，非零拷贝）
CREATE DATABASE customers_dev AS COPY OF customers_prod;

-- 这是后台拷贝，需要等待完成
SELECT * FROM sys.dm_database_copies;
```

### Aurora（CLI 而非 SQL）

```bash
# Aurora MySQL/PostgreSQL clone
aws rds restore-db-cluster-to-point-in-time \
    --source-db-cluster-identifier prod-cluster \
    --db-cluster-identifier dev-clone \
    --restore-type copy-on-write \
    --use-latest-restorable-time

# 启动 clone 集群的实例
aws rds create-db-instance \
    --db-instance-identifier dev-clone-instance-1 \
    --db-cluster-identifier dev-clone \
    --engine aurora-mysql \
    --db-instance-class db.r5.large
```

### PostgreSQL

```sql
-- 块级物理拷贝（非零拷贝）
CREATE DATABASE staging TEMPLATE production;

-- 注意：production 必须没有其他活动连接
-- 时间 = O(数据库大小)
```

```bash
# 替代：pg_dump + pg_restore
pg_dump -d production --jobs=8 --format=directory -f /tmp/dump
createdb staging
pg_restore -d staging --jobs=8 /tmp/dump
```

### Iceberg

```sql
-- Iceberg 没有专门的 CLONE 命令
-- 通过元数据复制（manifest copy）模拟

-- Spark on Iceberg
CALL system.create_clone(
    source_table => 'prod.db.customers',
    target_table => 'dev.db.customers'
);

-- 或用 CTAS 风格（物理复制）
CREATE TABLE dev.db.customers AS
SELECT * FROM prod.db.customers;
```

## 常见使用模式

### 模式 1: CI/CD 自动化测试环境

```yaml
# GitHub Actions 示例 (Snowflake)
name: Database Test
on: [pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Create database clone
        run: |
          snowsql -q "CREATE DATABASE pr_${{ github.event.pull_request.number }} \
                     CLONE PRODUCTION;"
      - name: Run migrations
        run: |
          snowsql -d pr_${{ github.event.pull_request.number }} \
                  -f migrations/up.sql
      - name: Run tests
        run: pytest tests/
      - name: Cleanup
        if: always()
        run: |
          snowsql -q "DROP DATABASE pr_${{ github.event.pull_request.number }};"
```

### 模式 2: 数据工程师沙箱

```sql
-- 给每个数据工程师提供一个 clone
CREATE DATABASE alice_sandbox CLONE production;
GRANT ALL ON DATABASE alice_sandbox TO ROLE alice;

CREATE DATABASE bob_sandbox CLONE production;
GRANT ALL ON DATABASE bob_sandbox TO ROLE bob;

-- 各自实验，存储仅在写入时增加
-- 每周/每月刷新一次
DROP DATABASE alice_sandbox;
CREATE DATABASE alice_sandbox CLONE production;
```

### 模式 3: 误操作恢复

```sql
-- 假设误删了 customers 表
DROP TABLE customers;

-- 用 Time Travel CLONE 恢复
CREATE TABLE customers CLONE production.public.customers AT(OFFSET => -300);
-- 5 分钟前的状态

-- 比 RESTORE FROM BACKUP 快几个数量级
```

### 模式 4: A/B Schema 测试

```sql
-- 当前 schema 的 baseline
CREATE TABLE orders_baseline CLONE orders;

-- 试验新 schema：添加索引
CREATE TABLE orders_v2 CLONE orders;
ALTER TABLE orders_v2 ADD CONSTRAINT idx_status_idx
    UNIQUE (status, created_at);

-- 对比两表性能
EXPLAIN SELECT * FROM orders_baseline WHERE status = 'pending';
EXPLAIN SELECT * FROM orders_v2 WHERE status = 'pending';

-- 验证后销毁/采用
DROP TABLE orders_baseline;
ALTER TABLE orders RENAME TO orders_old;
ALTER TABLE orders_v2 RENAME TO orders;
DROP TABLE orders_old;
```

### 模式 5: 数据分发到下游环境

```sql
-- 把生产快照分发到测试 / staging / dev 环境（同一 Snowflake 账户）
CREATE DATABASE staging CLONE production;
CREATE DATABASE qa CLONE production;
CREATE DATABASE dev CLONE production;
-- 三个环境独立可写，但底层共享存储
-- 任一环境的写入仅影响自己

-- 跨账户分发：需要先 SHARE 再 CLONE
CREATE SHARE production_share;
GRANT USAGE ON DATABASE production TO SHARE production_share;
ALTER SHARE production_share ADD ACCOUNTS = ('downstream_account');

-- 在 downstream_account 中
CREATE DATABASE prod_local FROM SHARE source_account.production_share;
CREATE DATABASE staging CLONE prod_local;
```

### 模式 6: 演练灾难恢复

```sql
-- 月度灾难恢复演练（Snowflake）
-- 1. 克隆生产库
CREATE DATABASE dr_drill CLONE production;

-- 2. 模拟"误删除关键表"
DROP TABLE dr_drill.public.orders;

-- 3. 演练恢复流程
CREATE TABLE dr_drill.public.orders
CLONE production.public.orders AT(OFFSET => -86400);

-- 4. 验证数据完整性
SELECT COUNT(*) FROM dr_drill.public.orders;

-- 5. 销毁演练环境
DROP DATABASE dr_drill;
```

## 性能对比矩阵

### 创建克隆的时间复杂度

| 引擎 | 时间复杂度 | 100GB 库实测 | 10TB 库实测 |
|------|---------|-------------|-------------|
| Snowflake CLONE | O(1) | <1 秒 | <1 秒 |
| BigQuery CLONE | O(1) | <1 秒 | <1 秒 |
| Aurora Storage Clone | O(1) (元数据) + 几分钟（启动计算） | ~5 分钟 | ~5 分钟 |
| Delta Lake SHALLOW CLONE | O(1) | <1 秒 | <1 秒 |
| Delta Lake DEEP CLONE | O(N) | 取决于 I/O | 几小时 |
| Oracle PDB Cold Clone | O(N) | 几分钟 | 几小时 |
| Oracle PDB Snapshot Copy | O(1) (需 ACFS) | <1 秒 | <1 秒 |
| SQL Server DBCC CLONEDATABASE | O(schema 大小) | <1 秒 | <1 秒（schema only） |
| SQL Server Database Snapshot | O(1) | <1 秒 | <1 秒 |
| Azure SQL AS COPY OF | O(N) (异步) | ~10 分钟 | 几小时 |
| PostgreSQL CREATE DATABASE TEMPLATE | O(N) | ~5 分钟 | 几小时 |
| pg_dump + pg_restore | O(N) | ~10 分钟 | ~24 小时 |
| ZFS clone | O(1) | <1 秒 | <1 秒 |
| EBS snapshot + restore | O(1) (snapshot) + O(N) lazy load | <1 秒 (snapshot) | <1 秒 (snapshot) |

### 存储成本（写入前）

| 引擎 | 存储增长 |
|------|---------|
| Snowflake CLONE | 0% |
| BigQuery CLONE | 0% |
| Aurora Storage Clone | 0% |
| Delta Lake SHALLOW CLONE | 0% (仅 _delta_log 几 KB) |
| Delta Lake DEEP CLONE | 100% |
| Oracle PDB Snapshot Copy | 接近 0% |
| Oracle PDB Cold/Hot Clone | 100% |
| SQL Server DBCC CLONEDATABASE | <1% (仅 schema + stats) |
| SQL Server Database Snapshot | 0% (写入源表后才增长) |
| PostgreSQL CREATE DATABASE TEMPLATE | 100% |

## 设计争议

### 1. 克隆 vs Time Travel：能力重叠

```
Time Travel 查询:
  SELECT * FROM customers AT(OFFSET => -3600);
  -- 只读，访问历史时点

零拷贝 CLONE:
  CREATE TABLE customers_old CLONE customers AT(OFFSET => -3600);
  -- 创建独立可写副本
```

两者技术基础相同（不可变数据 + 元数据时间戳），但语义不同：

- Time Travel 适合"查询历史"
- CLONE 适合"创建独立环境继续操作"

### 2. SHALLOW vs DEEP：默认应该是哪种？

Databricks 强制要求显式 SHALLOW / DEEP 关键字，避免歧义。Snowflake / BigQuery 默认就是 SHALLOW（零拷贝），用户对底层不感知。

各有道理：

- **强制显式**（Databricks）：用户清楚知道是 metadata only 还是 物理复制，避免长期维护时困惑
- **默认 SHALLOW**（Snowflake）：常见用例都是测试环境，用户期待"快"和"便宜"

### 3. CLONE 是 DDL 还是 DML？

CLONE 在所有引擎中都是 DDL（即时生效，不可回滚）。这意味着：

```sql
BEGIN;
CREATE TABLE x CLONE source;
ROLLBACK;  -- 在某些引擎中无效，CLONE 已经持久化
```

引擎设计争议：CLONE 应该参与事务吗？大部分引擎为了实现简单选择"CLONE 不参与事务"，但这意味着无法实现"复杂的多步原子化操作"。

### 4. 跨账户 / 跨 region CLONE

主流引擎都不直接支持跨账户/跨 region 的 CLONE：

- Snowflake: 需要先 SHARE
- BigQuery: 需要 EXPORT/IMPORT
- Aurora: 需要 Global Database

跨地域的"零拷贝" 需要跨地域的存储复制，物理上不成立。这是合理的限制。

### 5. CLONE 后的孤儿 partition 问题

```sql
-- 假设
CREATE TABLE clone_a CLONE source;
CREATE TABLE clone_b CLONE source;

-- 在 source 上做大量 UPDATE，原始 partition M1..M100 都被新版本替换
UPDATE source SET ... WHERE ...;

-- 此时 source 引用 M1'..M100'
-- 但 clone_a 和 clone_b 仍引用 M1..M100
-- M1..M100 不能被回收（还有引用）

-- 即使 DROP TABLE source，M1..M100 仍然存在
-- 直到 clone_a 和 clone_b 都被 DROP

-- 这导致存储成本可能比直觉预期高
```

引擎需要做精确的引用计数 + 周期性的孤儿数据回收，这是 CLONE 实现的核心难点。

## 关键发现 / Key Findings

### 1. 零拷贝克隆是云数仓的差异化能力

Snowflake CLONE 在 2017 年 GA，定义了行业标杆。BigQuery / Databricks / Aurora 在随后 5 年陆续跟进。这一波创新的共同基础是 **存储与计算分离 + 不可变数据格式**：

- Snowflake: micro-partition (Capacitor)
- BigQuery: Capacitor 列式 block
- Databricks: Parquet + Delta transaction log
- Aurora: 分布式 page 存储 + 元数据指针
- Iceberg / Hudi: Parquet + manifest

**传统单机数据库（PostgreSQL / MySQL / SQL Server）的存储模型与零拷贝克隆不兼容**——B+ tree 的 page 是可变的，无法多个表安全共享同一个 page。这就是为什么这些引擎只能通过文件系统快照或物理复制来"模拟" 克隆。

### 2. CLONE 与 CTAS 是不同概念

`CREATE TABLE AS SELECT` 是物理复制，O(N) 时间和 O(N) 存储。`CREATE TABLE CLONE` 是元数据复制，O(1) 时间和 O(0) 存储。两者经常被混淆，但代价模型完全不同。引擎应该在文档中明确区分这两个概念，避免用户错误估算成本。

### 3. SHALLOW vs DEEP：Delta Lake 的清晰命名是行业最佳实践

Delta Lake 强制 SHALLOW / DEEP 关键字，是对开发者最友好的设计：用户阅读 SQL 就知道开销和影响。Snowflake / BigQuery 把 SHALLOW 作为默认，对新手友好但容易隐藏成本陷阱（例如长期持有的 clone 会延长存储引用周期）。

未来 SQL 标准化（如果发生）应当采用 Delta Lake 的命名约定。

### 4. SQL Server DBCC CLONEDATABASE 是"非典型克隆"

DBCC CLONEDATABASE 不是给业务用的，而是给 DBA 用来诊断性能问题的"统计信息复制"工具。许多文章混淆这一点，把它当作 SQL Server 的"克隆 SQL Server 数据库"功能。但它**不复制数据**，对业务环境隔离没有用。

SQL Server 真正的"零拷贝" 副本是 Database Snapshot（只读 sparse file），但是只读。SQL Server 没有 SQL 层的"可写零拷贝克隆"——这是其相对 Snowflake 的功能差距。

### 5. Aurora 的存储层创新影响深远

Aurora 把"零拷贝克隆"下沉到分布式存储引擎，让 MySQL 和 PostgreSQL 这两个传统单机引擎获得了云数仓级的克隆能力。这一思路被后来者（Neon、Supabase、Aiven）大量借鉴，形成了"PostgreSQL + 云原生存储 = 现代 PG"的新范式。

Aurora Storage Clone 的局限是**只能整集群克隆**，不能单表克隆——粒度比 Snowflake 粗。但兼容性优势（100% MySQL/PG 兼容）让它在传统应用场景中无可替代。

### 6. PostgreSQL 生态的克隆缺失正在被填补

PostgreSQL 至今没有原生 CLONE 命令，是其相对其他 DBMS 的一个明显短板。但生态正在补救：

- **Neon**：基于自研存储层提供 git-like 分支
- **Supabase**：通过 Neon 集成提供分支能力
- **Aurora PostgreSQL**：AWS 托管层支持
- **PostgreSQL 17 pg_createsubscriber**：把 standby 转为独立可写

PostgreSQL 主版本可能在未来引入存储层 COW 改造（社区有讨论），但短期内仍依赖外部生态。

### 7. 分布式 KV 引擎的克隆是开放问题

CockroachDB / TiDB / YugabyteDB 等基于 Raft + KV 的分布式数据库都不支持零拷贝克隆。挑战在于：

- KV 数据非天然不可变
- 跨 range 的协调成本高
- 副本独立性 vs 共享存储的权衡

这是分布式数据库领域的开放研究问题。学术界提出过基于 LSM-tree SST 的方案，但工业落地有限。

### 8. CLONE 与 Time Travel 的协同是新范式

Snowflake 的 `CLONE source AT(OFFSET => -X)` 把"瞬间创建历史时点的可写副本"变成单条 SQL，这一能力对业务级 PITR、审计、A/B 测试都极有价值。BigQuery 在 2022 年跟进。

未来这套范式可能会被更多引擎采用——只要有不可变数据格式和 Time Travel 能力，CLONE AT 就是自然延伸。

### 9. 克隆的存储计费透明度仍是难题

零拷贝克隆"瞬间完成"，但存储成本不是真的零：

- 写入越多，存储越多（COW）
- 长期持有 clone 会延长底层 partition 的引用生命周期
- 删除源表也不会回收底层 partition（如果有 clone 引用）

各家引擎的计费透明度参差不齐：

- Snowflake: 提供 STORAGE_USAGE 视图，可以查询每个表的 active/time-travel/fail-safe 字节
- BigQuery: 通过 `__TABLES__` 系统视图查询表大小
- Delta Lake: VACUUM 命令清理孤儿 Parquet
- Aurora: 通过 CloudWatch metrics 监控

DBA 必须主动监控 clone 数量和孤儿数据，否则成本会无声膨胀。

### 10. 对 SQL 标准化的呼声

虽然 SQL:2023 仍未涉及 CLONE，但事实标准已经形成：

- `CREATE TABLE x CLONE source` 是 Snowflake / BigQuery / Databricks / Iceberg 的共同语法
- `CREATE TABLE x SHALLOW CLONE source` / `DEEP CLONE` 是 Databricks 的明确区分
- `AT(OFFSET / TIMESTAMP / VERSION)` 是 Time Travel CLONE 的通用扩展

未来 SQL 标准很可能借鉴这些约定，定义 `CREATE TABLE / DATABASE / SCHEMA ... CLONE source [SHALLOW | DEEP] [AT TIMESTAMP / VERSION]` 标准语法。这将极大促进多引擎工具（如 dbt、Airflow、Liquibase）的统一支持。

### 11. 对引擎开发者的实现建议

- **存储格式优先**：如果你正在设计新数据库，把"不可变数据块 + 元数据指针"作为存储模型一等公民。这是零拷贝克隆的基础。
- **元数据服务高可用**：CLONE 操作集中在元数据层（FoundationDB、ZooKeeper、KV），元数据服务的可用性和性能直接决定 CLONE 体验。
- **引用计数与孤儿回收**：仔细设计 partition/file 的引用计数 + 周期性回收机制。这是 CLONE 实现的核心难点。
- **明确区分 SHALLOW / DEEP**：哪怕默认是 SHALLOW，也应该提供 DEEP 关键字让用户显式选择。
- **CLONE + Time Travel 一体化**：CLONE AT(TIMESTAMP / VERSION) 是高价值能力，应该一并设计。
- **可观测性**：暴露 STORAGE_USAGE / clone metadata view，让 DBA 监控孤儿数据、存储引用、CLONE 链。
- **CI/CD 友好**：CLONE 应该是 SQL DDL，可脚本化、幂等、可与 dbt / Airflow 等工具集成。
- **跨账户 SHARE + CLONE**：明确 SHARE（跨账户共享只读视图）和 CLONE（账户内创建可写副本）的边界，文档要清晰。

## 总结对比矩阵

### 零拷贝克隆能力总览

| 能力 | Snowflake | BigQuery | Databricks (Delta) | Aurora | Oracle PDB | SQL Server | PostgreSQL | TiDB/CockroachDB |
|------|-----------|----------|-------------------|--------|------------|------------|------------|-----------------|
| 零拷贝表 CLONE | 是 | 是 | 是 (SHALLOW) | -- | -- | 部分 (DB Snapshot) | -- | -- |
| 零拷贝数据库 CLONE | 是 | -- | -- | 是 | 部分 (Snapshot Copy) | -- | -- | -- |
| Time Travel CLONE | 是 | 是 | 是 | 是 (PITR) | -- | -- | -- | -- |
| Schema 级 CLONE | 是 | -- | -- | -- | -- | -- | -- | -- |
| 物理复制 CLONE | -- | -- | DEEP CLONE | -- | Cold/Hot Clone | -- | TEMPLATE | BACKUP/RESTORE |
| 跨账户 CLONE | SHARE 后 | EXPORT 后 | SHARE | Global DB | dblink | -- | -- | -- |
| 写入 CLONE 影响源 | 否 | 否 | 否 | 否 | 否 | 否 | 否 | 否 |
| GA 时间 | 2017 | 2022 | 2021 (DBR 9.1) | 2017 | 12c (2013) | 2014 SP2 (2016-07) / 2016 SP1 (2016-11) | -- | -- |

### 引擎选型建议

| 场景 | 推荐引擎/方法 | 原因 |
|------|-------------|------|
| 大型数仓 CI/CD 测试 | Snowflake CLONE | 秒级、零成本、SQL 友好 |
| 数据科学家沙箱 | Snowflake / Databricks SHALLOW CLONE | 每人一个副本，存储分摊 |
| 关系型 OLTP 测试环境 | Aurora Storage Clone | 100% MySQL/PG 兼容，秒级 |
| 性能问题诊断 | SQL Server DBCC CLONEDATABASE | schema + stats，无数据 |
| 长期独立归档 | Databricks DEEP CLONE | 完全独立，可跨存储位置 |
| Postgres 自管 + 测试 | ZFS snapshot + clone | 文件系统级 COW |
| Postgres 云上 + 分支 | Neon / Supabase | git-like branching |
| 跨 region 副本 | Replication / Global Database | CLONE 不能跨 region |
| 误操作恢复 | Snowflake CLONE AT(OFFSET) | 比 RESTORE 快几个数量级 |

## 参考资料

- Snowflake: [CREATE CLONE](https://docs.snowflake.com/en/sql-reference/sql/create-clone)
- Snowflake: [Cloning Considerations](https://docs.snowflake.com/en/user-guide/object-clone)
- BigQuery: [Table Clones Introduction](https://cloud.google.com/bigquery/docs/table-clones-intro)
- BigQuery: [CREATE TABLE CLONE](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#create_table_clone_statement)
- Databricks: [CLONE Command](https://docs.databricks.com/en/sql/language-manual/delta-clone.html)
- Delta Lake: [Clone](https://docs.delta.io/latest/delta-utility.html#clone-a-table)
- Aurora: [DB Cluster Cloning](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Managing.Clone.html)
- Oracle: [CREATE PLUGGABLE DATABASE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-PLUGGABLE-DATABASE.html)
- Oracle: [Hot Cloning of PDBs](https://docs.oracle.com/en/database/oracle/oracle-database/19/multi/cloning-a-pdb.html)
- SQL Server: [DBCC CLONEDATABASE](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-clonedatabase-transact-sql)
- SQL Server: [Database Snapshots](https://learn.microsoft.com/en-us/sql/relational-databases/databases/database-snapshots-sql-server)
- PostgreSQL: [CREATE DATABASE](https://www.postgresql.org/docs/current/sql-createdatabase.html)
- Neon: [Database Branching](https://neon.tech/docs/introduction/branching)
- Iceberg: [Maintenance and Cloning](https://iceberg.apache.org/docs/latest/maintenance/)
- ClickHouse: [BACKUP and RESTORE](https://clickhouse.com/docs/en/operations/backup)
- Azure SQL: [Database Copy](https://learn.microsoft.com/en-us/azure/azure-sql/database/database-copy)
- ZFS: [Clones and Snapshots](https://openzfs.github.io/openzfs-docs/man/8/zfs-clone.8.html)
- "Service-Oriented Database Architecture" (Snowflake VLDB 2016)
- "Amazon Aurora: Design Considerations for High Throughput Cloud-Native Relational Databases" (SIGMOD 2017)
- "Delta Lake: High-Performance ACID Table Storage over Cloud Object Stores" (VLDB 2020)
