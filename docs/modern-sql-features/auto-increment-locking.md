# 自增锁与序列并发 (Auto-Increment Locking and Sequence Concurrency)

一张高并发订单表每秒产生上万次 INSERT，瓶颈往往不在磁盘、不在网络、也不在索引——而在那个看似不起眼的 AUTO_INCREMENT 列上。自增 ID 的分配是 OLTP 数据库最经典的锁竞争点之一，也是分布式数据库设计者必须直面的第一道坎。

> 注：本文聚焦"并发与锁"维度。若关注自增/序列/IDENTITY 的语法对比、ID 生成策略、UUID/Snowflake/位反转等通用话题，请参阅同目录的 [`auto-increment-sequence-identity.md`](./auto-increment-sequence-identity.md)。

## 问题的本质：为什么自增是热点

考虑一个最朴素的 AUTO_INCREMENT 实现：

```sql
-- 伪代码：朴素自增分配
BEGIN;
  next_id := SELECT counter FROM meta WHERE table = 'orders' FOR UPDATE;
  UPDATE meta SET counter = next_id + 1 WHERE table = 'orders';
  INSERT INTO orders (id, ...) VALUES (next_id, ...);
COMMIT;
```

它的语义诉求看似简单——"给我下一个值"，但在并发场景下会同时遇到三类困难：

1. **唯一性**：所有事务必须看到不同的 next_id，不能重复
2. **持久性**：节点崩溃后，下一个 next_id 不能回退（否则会重复）
3. **顺序性**：用户经常希望 id 严格递增，且对应 INSERT 的提交顺序

这三者两两可调和但三者难以同时满足，加上"事务回滚是否归还序号"、"批量插入如何分配"、"分布式节点如何协调"等子问题，演化出了今天数据库世界中眼花缭乱的实现策略。

本文将自增/序列的并发特性拆成八个维度，逐一对比 50 个数据库引擎的取舍。

## 没有 SQL 标准

ANSI SQL:2003 引入了 `GENERATED ... AS IDENTITY` 和 `CREATE SEQUENCE` 的语法，但**对并发行为完全没有规定**：

- 没有规定是否允许 gap
- 没有规定是否需要严格递增
- 没有规定 cache 行为
- 没有规定回滚语义
- 没有规定多节点协调方式

标准只关心"语法"和"逻辑生成"，把"如何高效并发地生成"完全留给了实现者。这导致同样写 `GENERATED ALWAYS AS IDENTITY`，PostgreSQL、Oracle、DB2、SQL Server 的并发行为可能完全不同。

实现者必须独立做出八个核心决策：

1. 用什么锁机制保护 next_id
2. 是否允许预分配/缓存
3. cache 是 session 级还是 instance 级
4. INSERT 失败/事务回滚时是否归还编号
5. 批量 INSERT 如何分配
6. 多节点之间如何协调
7. 是否暴露 ORDER 选项让用户控制
8. 默认值如何选择（性能优先 vs 顺序优先）

## 支持矩阵

### 1. 自增锁模式

下表中的"锁模式"沿用 MySQL `innodb_autoinc_lock_mode` 的命名约定：

- **传统 (traditional, 0)**：每次 INSERT 持有表级 AUTO-INC 锁直到语句结束
- **连续 (consecutive, 1)**：单行 INSERT 立即释放锁，批量 INSERT 持有锁到结束（保证一个语句内分配的 ID 连续）
- **交错 (interleaved, 2)**：完全无锁，每行只在 mutex 内增计数器，不同语句的 ID 可交错
- **序列对象 (sequence)**：通过独立 SEQUENCE 对象的原子操作分配，无表锁
- **快照/无锁 (snapshot)**：基于全局时钟、时间戳或随机算法，无需任何序列锁

| 引擎 | 锁模式 | 默认行为 | 备注 |
|------|--------|---------|------|
| PostgreSQL | sequence | 序列原子分配 | nextval() 短临界区 |
| MySQL (InnoDB) | traditional/consecutive/interleaved | 8.0+ interleaved | 见 innodb_autoinc_lock_mode |
| MariaDB (InnoDB) | traditional/consecutive/interleaved | 默认 1 (consecutive) | 比 MySQL 保守 |
| SQLite | traditional | 单写者全局锁 | rowid 在 WAL 内单调 |
| Oracle | sequence | 序列对象 + cache | NOORDER 默认 |
| SQL Server | sequence/identity | identity 缓存 (1000/10000) | 见下文 |
| DB2 | sequence | 序列对象 + cache | ORDER/NOORDER 可选 |
| Snowflake | snapshot | 无锁分布式分配 | 不保证连续 |
| BigQuery | -- | 无原生自增 | 推荐 GENERATE_UUID |
| Redshift | sequence | IDENTITY 按节点切片 | 多 leader 切片 |
| DuckDB | sequence | 单进程序列 | 无并发问题 |
| ClickHouse | -- | 不支持 AUTO_INCREMENT | 推荐 UUID/snowflake |
| Trino | -- | 无写入引擎 | -- |
| Presto | -- | 无写入引擎 | -- |
| Spark SQL | snapshot | monotonically_increasing_id() | 分区+行内偏移 |
| Hive | -- | 无原生 | -- |
| Flink SQL | -- | 流处理无自增 | 推荐 PROCTIME/UUID |
| Databricks | sequence | Delta IDENTITY 列 | 内部按 batch 分配 |
| Teradata | sequence | IDENTITY 按 AMP 切片 | NO CYCLE 默认 |
| Greenplum | sequence | 按 segment 切片 | 段内连续段间不保证 |
| CockroachDB | snapshot | unique_rowid() 时间戳+节点 | 完全无锁 |
| TiDB | consecutive/AUTO_ID_CACHE | 默认按 region 分配 | 见详解 |
| OceanBase | traditional/consecutive | MySQL 兼容 | 类似 MySQL mode 1 |
| YugabyteDB | sequence | SEQUENCE CACHE 默认 100 | 见详解 |
| SingleStore | sequence | 按 partition 切片 | 每分区独立计数 |
| Vertica | sequence | 按节点切片 | 节点内连续 |
| Impala | -- | 无原生自增 | -- |
| StarRocks | -- | 不推荐 AUTO_INCREMENT | 3.1+ 实验性 |
| Doris | -- | 2.1+ 实验性 AUTO_INCREMENT | BE 节点缓存 |
| MonetDB | sequence | SERIAL/SEQUENCE | 单节点 |
| CrateDB | -- | 无原生自增 | 推荐 gen_random_text_uuid |
| TimescaleDB | sequence | 继承 PostgreSQL | -- |
| QuestDB | -- | 无原生自增 | 时间序列推荐 ts |
| Exasol | sequence | IDENTITY 列 | 节点本地缓存 |
| SAP HANA | sequence | SEQUENCE/IDENTITY | CACHE 可配 |
| Informix | sequence | SERIAL/SERIAL8 | 表级递增 |
| Firebird | sequence | GENERATOR/SEQUENCE | 原生支持 |
| H2 | sequence | IDENTITY/SEQUENCE | 内存级 |
| HSQLDB | sequence | IDENTITY/SEQUENCE | 内存级 |
| Derby | sequence | GENERATED IDENTITY | 表级锁 |
| Amazon Athena | -- | 无写入引擎 | -- |
| Azure Synapse | snapshot | IDENTITY 不保证连续 | 分布式切片 |
| Google Spanner | sequence | bit-reversed sequence | 见详解 |
| Materialize | -- | 无原生自增 | 流处理 |
| RisingWave | sequence | SERIAL（继承 PG） | 单节点 catalog |
| InfluxDB (SQL) | -- | 时间序列 | -- |
| Databend | snapshot | 雪花 ID | 分布式 |
| Yellowbrick | sequence | IDENTITY | 类 PG |
| Firebolt | -- | 无原生自增 | -- |

### 2. innodb_autoinc_lock_mode 取值

只有 MySQL/MariaDB/兼容引擎暴露这个参数：

| 引擎 | 0 (traditional) | 1 (consecutive) | 2 (interleaved) | 默认 |
|------|----------------|-----------------|-----------------|------|
| MySQL 5.6 | 是 | 是 | 是 | 1 |
| MySQL 5.7 | 是 | 是 | 是 | 1 |
| MySQL 8.0+ | 是 | 是 | 是 | **2** |
| MariaDB 10.x | 是 | 是 | 是 | 1 |
| MariaDB 11.x | 是 | 是 | 是 | 1 |
| Percona Server | 是 | 是 | 是 | 1 / 2 (随上游) |
| TiDB | 模拟 0 | 模拟 1 | 模拟 2 | AUTO_ID_CACHE |
| OceanBase MySQL | 是 | 是 | -- | 1 |
| Doris | -- | 类 1 | -- | 1 |

### 3. 序列缓存大小（CACHE）

| 引擎 | CACHE 子句 | 默认 cache 大小 | 缓存粒度 |
|------|-----------|----------------|---------|
| PostgreSQL | `CACHE n` | 1 | per session/backend |
| Oracle | `CACHE n` | 20 | per instance |
| SQL Server | `CACHE n` | 50 (varies) | instance |
| DB2 | `CACHE n` | 20 | instance |
| MariaDB SEQUENCE | `CACHE n` | 1000 | session |
| Snowflake | -- | 不暴露 | warehouse |
| Redshift | -- | 不暴露 | leader |
| Greenplum | `CACHE n` | 1 | per session |
| CockroachDB | `CACHE n` | 1 | node |
| TiDB SEQUENCE | `CACHE n` | 1000 | tidb-server |
| OceanBase | `CACHE n` | 20 (Oracle 模式) | observer |
| YugabyteDB | `CACHE n` | 100 (PG 模式默认) | per backend |
| SingleStore | -- | 不暴露 | partition |
| Vertica | `CACHE n` | 250000 | node |
| Exasol | `CACHE n` | 1000 | node |
| SAP HANA | `CACHE n` | 1 | indexserver |
| Informix | -- | 1 | 系统 |
| Firebird | -- | 1 | 引擎 |
| H2 | `CACHE n` | 32 | session |
| HSQLDB | -- | 1 | 引擎 |
| Derby | -- | 1 | 引擎 |
| Spanner | n/a | bit-reversed | -- |
| Google Spanner SEQUENCE | -- | n/a | bit-reversed kind |
| Databend | -- | 不暴露 | snowflake |
| Yellowbrick | `CACHE n` | 继承 PG | session |

### 4. Gap（空隙）容忍度

| 引擎 | 回滚产生 gap | 崩溃产生 gap | 节点切换产生 gap | 是否承诺无 gap |
|------|-------------|-------------|----------------|---------------|
| PostgreSQL | 是 | 是（cache 范围） | n/a | 否 |
| MySQL InnoDB | 是 | 8.0+ 持久化，仍有 gap | n/a | 否 |
| MariaDB InnoDB | 是 | 旧版本崩溃后回退 | n/a | 否 |
| SQLite (rowid) | 是 | 否 | n/a | 否 |
| SQLite (AUTOINCREMENT) | 是 | 否 | n/a | 单调（仍有 gap） |
| Oracle (NOCACHE NOORDER) | 是 | 否 | RAC 节点不同步 | 否 |
| Oracle (CACHE) | 是 | 是（cache 范围） | RAC 大段 gap | 否 |
| SQL Server IDENTITY | 是 | 是（cache 1000） | n/a | 否 |
| SQL Server SEQUENCE NOCACHE | 是 | 否 | n/a | 否 |
| DB2 | 是 | 是 | 是 | 否 |
| Snowflake | 是 | 是 | 是 | 否，仅承诺唯一 |
| Redshift IDENTITY | 是 | 是 | 是（按切片） | 否 |
| DuckDB | 是 | 是 | n/a | 否 |
| Greenplum | 是 | 是 | 是 | 否 |
| CockroachDB unique_rowid | n/a (非递增) | 否 | n/a | 不适用 |
| CockroachDB SEQUENCE | 是 | 是 | 是 | 否 |
| TiDB AUTO_INCREMENT | 是 | 是（cache 范围 30000） | 是 | 否 |
| TiDB AUTO_RANDOM | n/a | n/a | n/a | 不适用 |
| OceanBase | 是 | 是 | 是 | 否 |
| YugabyteDB | 是 | 是 | 是 | 否 |
| Vertica | 是 | 是 | 是 | 否 |
| SingleStore | 是 | 是 | 是 | 否 |
| Doris | 是 | 是 | 是 | 否 |
| Exasol | 是 | 是 | 是 | 否 |
| SAP HANA | 是 | 是 | 是 | 否 |
| Informix | 是 | 是 | n/a | 否 |
| Firebird | 是 | 否 | n/a | 否 |
| H2 | 是 | 是 | n/a | 否 |
| HSQLDB | 是 | 否 | n/a | 否 |
| Derby | 是 | 否 | n/a | 否 |
| Azure Synapse | 是 | 是 | 是 | 否 |
| Spanner bit-reversed | n/a | n/a | n/a | 不适用 |
| Databend | 是 | 是 | 是 | 否 |
| Firebolt | n/a | n/a | n/a | -- |

> **没有任何主流数据库承诺"无 gap"自增**。即使最严格的实现，也无法在不大幅牺牲并发性能的前提下保证序号连续。Firebird 和早期 PostgreSQL 文档明确警告：序列不应被用于"分配业务上必须连续的编号"（如发票号），那应当用应用层 `MAX(id)+1 + 锁表` 实现。

### 5. 单调性（monotonicity）保证

定义：在单节点单实例内，先开始的 INSERT 是否一定拿到比后开始的 INSERT 更小的 ID。

| 引擎 | 单调（单节点） | 单调（提交顺序） | 单调（多节点） |
|------|---------------|-----------------|---------------|
| PostgreSQL | 是 | 否 | n/a |
| MySQL mode 0 | 是 | 是 | n/a |
| MySQL mode 1 | 是 | 否 | n/a |
| MySQL mode 2 | 是 | 否 | n/a |
| MariaDB mode 1 | 是 | 否 | n/a |
| SQLite | 是 | 是 | n/a |
| Oracle NOORDER | 是 | 否 | 否 |
| Oracle ORDER | 是 | 是 | 是 (RAC 慢) |
| SQL Server | 是 | 否 | n/a |
| DB2 NOORDER | 是 | 否 | -- |
| DB2 ORDER | 是 | 是 | 是 |
| Snowflake | 否 | 否 | 否 |
| Redshift | 切片内是 | 否 | 否 |
| CockroachDB unique_rowid | 否 | 否 | 否 |
| TiDB AUTO_INCREMENT | 单 tidb-server 是 | 否 | 否 |
| TiDB AUTO_RANDOM | 否 | 否 | 否 |
| YugabyteDB | 是 | 否 | 否 |
| Vertica | 节点内是 | 否 | 否 |
| Spanner bit-reversed | 否 | 否 | 否 |
| Databend snowflake | 节点+时间内是 | 否 | 否 |
| 其他大多数引擎 | 是 | 否 | -- |

### 6. ORDER 子句（Oracle 风格）

| 引擎 | ORDER/NOORDER | 默认 | 含义 |
|------|---------------|------|------|
| Oracle | 是 | NOORDER | ORDER 强制 RAC 全局顺序 |
| DB2 | 是 | NOORDER | ORDER 串行化分配 |
| OceanBase Oracle 模式 | 是 | NOORDER | 兼容 Oracle |
| Informix | 否 | -- | -- |
| PostgreSQL | 否 | -- | 无此概念 |
| MySQL | 否 | -- | -- |
| SQL Server | 否 | -- | -- |
| Snowflake | 否 | -- | -- |
| 其他大多数 | 否 | -- | -- |

### 7. 事务回滚归还编号？

| 引擎 | 回滚归还 | 备注 |
|------|---------|------|
| PostgreSQL | 否 | nextval 立即推进 |
| MySQL InnoDB | 否 | 已分配即不归还 |
| MariaDB | 否 | 同 MySQL |
| SQLite (rowid) | 否 (默认) | rowid 重用空槽 |
| SQLite AUTOINCREMENT | 否 | 严格单调 |
| Oracle | 否 | -- |
| SQL Server IDENTITY | 否 | 即使语句失败也消耗 |
| SQL Server SEQUENCE | 否 | -- |
| DB2 | 否 | -- |
| Snowflake | 否 | -- |
| Redshift | 否 | -- |
| DuckDB | 否 | -- |
| CockroachDB | 否 | -- |
| TiDB | 否 | -- |
| YugabyteDB | 否 | -- |
| OceanBase | 否 | -- |
| Vertica | 否 | -- |
| 其他全部 | 否 | -- |

> **没有任何数据库会因事务回滚而归还序号**。这是上述"没有无 gap 保证"的根本原因。归还序号需要分布式回滚或全局协调，代价远超不归还。

### 8. 分布式全局唯一性

| 引擎 | 分布式唯一保证 | 实现机制 |
|------|---------------|---------|
| PostgreSQL | 单节点 | 序列对象 |
| MySQL InnoDB | 单节点 | AUTO-INC 锁 |
| MariaDB Galera | 节点偏移 | auto_increment_offset/increment |
| SQLite | 单文件 | 文件锁 |
| Oracle RAC | 全局 | NOORDER 各节点 cache，ORDER 全局协调 |
| SQL Server AG | 单主 | 副本只读 |
| DB2 pureScale | 全局 | 分布式锁管理 |
| Snowflake | 全局 | 服务化 ID 分配器 |
| BigQuery | 不支持 | 用 UUID |
| Redshift | 全局 | 切片偏移 |
| CockroachDB | 全局 | unique_rowid (timestamp + node + counter) |
| TiDB | 全局 | tidb-server cache (默认 30000) |
| OceanBase | 全局 | RootService 分配 |
| YugabyteDB | 全局 | catalog tablet 序列 |
| SingleStore | 全局 | partition_id + 本地计数器 |
| Vertica | 全局 | 节点 ID + 本地计数器 |
| Greenplum | 全局 | segment_id + 本地计数器 |
| Doris | BE 节点 | BE 缓存批 |
| StarRocks | -- | 不推荐 |
| Spanner | 全局 | bit-reversed sequence |
| Azure Synapse | 全局 | 切片偏移 |
| Databend | 全局 | snowflake-like |
| 其他单机引擎 | n/a | -- |

## 各引擎详解

### MySQL InnoDB：三种锁模式的演进

MySQL 是这一话题的核心样本，因为它把"自增锁模式"作为可调参数显式暴露给了用户，而且这个参数的默认值在 8.0 版本改了。

```sql
-- 查看当前模式
SHOW VARIABLES LIKE 'innodb_autoinc_lock_mode';

-- 修改（需重启）
SET GLOBAL innodb_autoinc_lock_mode = 2;
```

#### Mode 0：traditional（传统）

```text
INSERT INTO t (data) VALUES ('a'), ('b'), ('c');
  ↓
持有 AUTO-INC 表锁
  分配 1, 2, 3
  写入行
释放 AUTO-INC 表锁
```

行为：每条 INSERT 语句开始时获取 AUTO-INC 表锁，语句结束才释放。任意两条 INSERT 完全串行。

特点：
- 完全保证一个语句内分配的 ID 连续
- 完全保证语句间按开始顺序分配
- 完全无并发，吞吐 = 单线程吞吐
- 兼容 statement-based replication（SBR）

适用：低并发、强顺序需求的老系统。

#### Mode 1：consecutive（连续，5.7 默认）

```text
单行 INSERT INTO t VALUES ('a'):
  在 mutex 内 ++counter, 立即释放
  → 高并发

INSERT INTO t (data) VALUES ('a'),('b'),('c'):
  持有 AUTO-INC 表锁直到分配完所有 3 个
  → 保证一个语句内 ID 连续
  → 但两条同时跑的 multi-row INSERT 会互相阻塞

INSERT INTO t SELECT * FROM s:
  按 mode 0 处理（因为分配数未知）
  → 与其他 INSERT 互相阻塞
```

行为：
- 单行简单 INSERT：mutex 内分配，立即释放，类似无锁
- 已知行数的多行 INSERT (`INSERT VALUES (...),(...)`)：持表锁直到分配完所有行
- 未知行数的 INSERT (`INSERT...SELECT`, `LOAD DATA`, `REPLACE...SELECT`)：退化为 mode 0 全语句锁

折衷点：单行 INSERT 高并发，但批量 INSERT 仍有阻塞；语句内 ID 一定连续，跨语句不保证。

兼容 SBR：是。这是 5.x 时代的默认值。

#### Mode 2：interleaved（交错，8.0 默认）

```text
INSERT INTO t (data) VALUES ('a'),('b'),('c');
INSERT INTO t (data) VALUES ('x'),('y');
  ↓ 并行执行
  事务 1: 分配 1
  事务 2: 分配 2
  事务 1: 分配 3
  事务 2: 分配 4
  事务 1: 分配 5
  → 一个语句内的 ID 也可能不连续！
```

行为：完全无表锁。每行 INSERT 单独通过 mutex 分配 ID。最大并发，但同一条多行 INSERT 中各行的 ID 可能不连续（被其他事务的 INSERT "插入"）。

为什么 8.0 改默认值：
1. **行级复制（RBR）成为默认**：mode 2 与 SBR 不兼容（因为重放时无法保证 ID 顺序），但与 RBR 完全兼容。8.0 默认 binlog 格式是 ROW，所以约束被解除。
2. **OLTP 高并发场景普遍**：现代应用对自增连续性几乎无依赖（用 LAST_INSERT_ID() 取自己的），更需要吞吐。
3. **批量 ETL 不再阻塞**：mode 1 下 `INSERT...SELECT` 会阻塞所有其他 INSERT，mode 2 下完全并行。

#### LAST_INSERT_ID() 的语义

```sql
INSERT INTO t (data) VALUES ('a'),('b'),('c');
SELECT LAST_INSERT_ID();  -- 返回第一行的 ID
```

无论哪种模式，`LAST_INSERT_ID()` 返回**当前连接最后一条 INSERT 的第一行 ID**。Mode 2 下，这个值仍然是该语句获得的最小 ID，但不能假设 first_id+1 是第二行（可能被别的事务"插队"）。

#### 崩溃后的行为

8.0 之前：AUTO_INCREMENT 计数器存在内存中，启动时通过 `SELECT MAX(id) FROM t` 重建。这意味着 MAX 之后产生的 cache 范围内的值会被"忘记"，重启后重新分配，可能与已删除行的 ID 重复（如果之前有 DELETE）。

8.0+：计数器持久化到 redo log，崩溃后不会回退。但 DELETE 后重启再 INSERT 仍然不会复用编号。

### MariaDB：保守的 mode 1 默认

MariaDB 的 InnoDB 至今（11.x）默认值仍是 mode 1。理由是：
- MariaDB 用户群对 mode 2 的"语句内不连续"反感更强烈
- Galera 集群默认依赖 SBR，mode 2 不兼容
- MariaDB 还提供独立的 SEQUENCE 引擎（`CREATE SEQUENCE`），重并发场景推荐用 SEQUENCE 而非 AUTO_INCREMENT

```sql
-- MariaDB 独立的 SEQUENCE 引擎
CREATE SEQUENCE s START WITH 1 INCREMENT BY 1 CACHE 1000;
SELECT NEXTVAL(s);
```

MariaDB SEQUENCE 是表存储引擎实现，允许更细粒度的 cache 控制，避免 AUTO_INCREMENT 的所有限制。

### PostgreSQL：序列对象与 backend 级 CACHE

PostgreSQL 没有"自增锁"概念。它的所有自增机制（SERIAL、IDENTITY、SEQUENCE）背后都是同一种实现：**SEQUENCE 对象**。

```sql
CREATE SEQUENCE s
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9223372036854775807
    START WITH 1
    CACHE 1
    NO CYCLE;

SELECT nextval('s');
```

`nextval()` 的并发实现：

```text
nextval('s'):
  if cache 还有未用值:
    return cache 中下一个
  else:
    LWLock 锁定 sequence buffer
    fetch_count := CACHE  -- 默认 1
    sequence.last_value += fetch_count
    WAL 日志（持久化）
    释放 LWLock
    本地 cache 填充 [old_last+1, old_last+CACHE]
    return cache[0]
```

关键性质：

1. **CACHE 是 per backend（连接）的**：意味着如果 CACHE=100、有 50 个连接，每个连接预分配 100 个，**总共预分配 5000 个**，而非全局 100。
2. **大 CACHE = 大 gap**：连接 A 拿到 [1..100]，连接 B 拿到 [101..200]，连接 A 只用了 5 个就断开 → [6..100] 永久浪费。
3. **WAL 写入按 32 个值一批**：即使 CACHE=1，也不是每个 nextval 都 WAL fsync——内部有"32 计数器"机制，崩溃后最多丢失 32 个号（产生 gap）。
4. **完全无表锁**：nextval 与 INSERT 解耦，nextval 是独立的 catalog 操作。
5. **回滚不归还**：nextval 不在事务范围内，回滚的事务消耗的号永久丢失。

```sql
-- 演示 cache 导致的乱序
-- 会话 A
SELECT nextval('s');  -- 1（cache 1..100）
-- 会话 B
SELECT nextval('s');  -- 101（cache 101..200）
-- 会话 A
SELECT nextval('s');  -- 2
```

PostgreSQL 文档明确警告：CACHE > 1 会造成 ID 不严格递增，应用如果对此敏感请保持 CACHE=1。

### Oracle：CACHE、ORDER 与 RAC 困境

```sql
CREATE SEQUENCE s
    START WITH 1
    INCREMENT BY 1
    CACHE 20      -- 默认值
    NOORDER       -- 默认值
    NOCYCLE;
```

#### NOCACHE / CACHE / ORDER 的笛卡尔积

| 配置 | 单节点性能 | RAC 性能 | gap 风险 | 严格全局顺序 |
|------|-----------|---------|---------|------------|
| `NOCACHE NOORDER` | 慢（每次写盘） | 慢（每次写盘） | 仅回滚/崩溃 | 单节点是 |
| `NOCACHE ORDER` | 慢 | 极慢（全局锁） | 仅回滚/崩溃 | 是 |
| `CACHE 20 NOORDER` | 快 | **极快** | 中等（cache + RAC 切换） | 否 |
| `CACHE 20 ORDER` | 快 | **极慢**（每节点同步） | 较少 | 是 |
| `CACHE 1000 NOORDER` | 极快 | 极快 | 大 gap | 否 |

#### RAC 上的核心矛盾

Oracle RAC 是"共享磁盘+多实例"。当多个实例同时分配序列号时：

- **NOORDER**：每个实例独立从全局 sequence 一次取 CACHE 个值放进本地 cache。两个实例的并发 nextval 完全无锁。代价：实例 1 拿 [1..20]，实例 2 拿 [21..40]，跨实例顺序完全不可预测。如果实例 1 故障，[未使用的部分] 永久丢失。
- **ORDER**：每次 nextval 都要走 RAC 全局缓存协调（GES），相当于全局加锁。所有实例完全串行，吞吐与单实例一致甚至更差。

Oracle 官方建议：**在 RAC 上几乎不要使用 ORDER**。如果业务需要全局顺序，应该用 SCN 或 SYSTIMESTAMP，而非 sequence。

```sql
-- RAC 高并发推荐配置
CREATE SEQUENCE order_seq CACHE 1000 NOORDER NOCYCLE;
```

CACHE 越大，单实例越能减少 catalog 访问，但 gap 也越大。20 是 Oracle 在"性能"和"gap 容忍"之间的折中默认值，而高并发 OLTP 通常会调整到 1000+。

### SQL Server：IDENTITY 缓存与 -t272

SQL Server 的 IDENTITY 列在 2012 版本之后引入了"identity cache"机制：

```sql
CREATE TABLE t (
    id INT IDENTITY(1,1) PRIMARY KEY,
    data NVARCHAR(100)
);
```

SQL Server 默认会一次性预分配一批 ID 值（int 通常 1000，bigint 通常 10000）放在内存中。崩溃或服务重启时，这批未使用的 ID 全部丢失——**这是 SQL Server 著名的"重启后 ID 跳号"问题**。

```sql
-- 关闭 identity cache（trace flag 272）
DBCC TRACEON(272, -1);

-- 或在 2017+ 用数据库范围配置
ALTER DATABASE SCOPED CONFIGURATION SET IDENTITY_CACHE = OFF;
```

`IDENTITY_CACHE = OFF` 后，每个 IDENTITY 值都立即写盘，崩溃不丢号但失去并发性能。

#### SEQUENCE 对象（2012+）

```sql
CREATE SEQUENCE s
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    CACHE 100;        -- 显式指定，默认 50

SELECT NEXT VALUE FOR s;
```

SEQUENCE 对象提供了更细的控制：可以 NOCACHE，可以 CYCLE，可以与多个表共享。比 IDENTITY 灵活但语法更繁琐。

#### DBCC CHECKIDENT

```sql
-- 重置 IDENTITY 计数器
DBCC CHECKIDENT ('t', RESEED, 0);
-- 同步 IDENTITY 到当前 MAX
DBCC CHECKIDENT ('t', RESEED);
```

### DB2：ORDER 与 NOORDER

```sql
CREATE SEQUENCE s
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    CACHE 20
    NO ORDER       -- 默认
    NO CYCLE;
```

DB2 在 pureScale（多实例集群）环境下与 Oracle RAC 类似，ORDER 强制全局协调，NO ORDER 允许实例本地 cache。DB2 的 CACHE 默认 20，与 Oracle 一致。

```sql
-- DB2 的 IDENTITY 列实际上就是隐式的 SEQUENCE
CREATE TABLE t (
    id BIGINT GENERATED ALWAYS AS IDENTITY
        (START WITH 1 INCREMENT BY 1 CACHE 100 NO ORDER),
    data VARCHAR(100)
);
```

### CockroachDB：unique_rowid() 的去顺序化设计

CockroachDB 故意不使用传统序列作为默认 ID 生成方式。它的 `SERIAL` 类型默认映射到 `unique_rowid()`：

```sql
-- 在 CockroachDB 中
CREATE TABLE t (
    id SERIAL PRIMARY KEY,    -- 实际是 INT8 DEFAULT unique_rowid()
    data STRING
);
```

`unique_rowid()` 的内部结构（80 bit）：

```text
| 64-bit timestamp (微秒) | 16-bit node-id |
```

但实际上低 14 bit 用作"同一微秒内的随机后缀"，避免同节点同微秒的多次调用冲突。

设计目标：
- **完全无锁**：不需要任何全局协调
- **避免 range 热点**：纯单调递增的主键会让所有写入集中到 KV 范围的最后一个 range 上，CockroachDB 通过随机 bit 分散写入
- **大致按时间排序**：高位是时间戳，整体是"时间近似单调"的，便于范围查询
- **不可预测连续值**：无法预测下一个 ID

代价：ID 是非连续的大整数（typically 18 位十进制），不利于人工调试。

CockroachDB 也支持 `CREATE SEQUENCE` 真正的序列对象，但官方文档明确建议**不要将单调 SEQUENCE 用作分布式表的主键**，会形成写热点。

### YugabyteDB：继承 PG 但 cache 默认更大

YugabyteDB 的序列实现继承自 PostgreSQL（YSQL），但因为是分布式架构，对 cache 默认值做了不同选择：

```sql
CREATE SEQUENCE s START WITH 1 INCREMENT BY 1 CACHE 100;  -- 注意默认 100
```

为什么不是 PG 的默认 1：每次 nextval 都需要走分布式 catalog raft consensus（写到 sequence 元数据 tablet），延迟约 1ms+。如果 CACHE=1，每个新 ID 都要 1ms，吞吐被限制在 1k/s 左右。CACHE=100 后，每 100 个 ID 才走一次 consensus，吞吐升至 100k/s。

```sql
-- YugabyteDB 集群级配置
SET yb_sequence_cache_minval = 1000;
```

代价：每个 backend 拿走一批，gap 风险大。

### TiDB：三种自增模式与 AUTO_RANDOM

TiDB 是 MySQL 兼容引擎，但底层是分布式 KV，自增的实现完全不同。

#### AUTO_INCREMENT 的三种模式

TiDB 通过 `AUTO_ID_CACHE` 表选项控制行为：

```sql
-- 模式 1：默认（TiDB 4.0 之前）
-- 每个 tidb-server 缓存一段（默认 30000）
CREATE TABLE t (id BIGINT AUTO_INCREMENT PRIMARY KEY) AUTO_ID_CACHE 30000;

-- 模式 2：MySQL 兼容模式（连续自增）
-- TiDB 6.4+，全局连续，性能下降
CREATE TABLE t (id BIGINT AUTO_INCREMENT PRIMARY KEY) AUTO_ID_CACHE 1;

-- 模式 3：自适应缓存
CREATE TABLE t (id BIGINT AUTO_INCREMENT PRIMARY KEY);
-- TiDB 7.5+ 默认根据负载动态调整 cache 大小
```

模式 1 的实质：每个 tidb-server 节点像一个独立的 MySQL，从全局 catalog 一次拿 30000 个 ID 放在内存中，本地用完了再去全局申请。三个 tidb-server 节点的 ID 完全不连续：节点 A 拿 [1..30000]，节点 B 拿 [30001..60000]，节点 C 拿 [60001..90000]。同一时刻三个节点的 INSERT 拿到的 ID 跨度可达 60000。重启 tidb-server 后未使用的部分丢失。

模式 2 的代价：每个 INSERT 都走全局 catalog，延迟约 1ms+，吞吐受限。仅在严格需要 MySQL 兼容性的迁移场景使用。

#### AUTO_RANDOM：避免单调主键热点

```sql
CREATE TABLE t (
    id BIGINT AUTO_RANDOM(5) PRIMARY KEY,
    data VARCHAR(100)
);
```

TiDB 的核心痛点：底层 TiKV 是按主键 range 分片的，单调递增的 BIGINT 主键会让所有最新写入集中到最后一个 region，造成单 region 写热点。CockroachDB 用 `unique_rowid()` 解决，TiDB 用 `AUTO_RANDOM`。

`AUTO_RANDOM(5)` 的 ID 结构：

```text
| 1 bit 符号位（恒 0） | 5 bit shard | 58 bit 自增计数器 |
```

shard bits 从 5 个事务相关的 hash 派生，使插入的主键在 32 个 region 间均匀分散。58 bit 是真正的自增部分，每个 shard 内部仍然单调。

效果：
- 完全分散写入，不再有热点 region
- ID 仍然全局唯一
- 失去了"按 ID 排序就是按时间排序"的特性
- 语义上等价于"32 个独立的 AUTO_INCREMENT 分桶"

CACHE 行为：每个 tidb-server 仍然按 shard 分批 cache，每个 shard 有自己的本地 buffer。

### Greenplum / Vertica / SingleStore：节点切片模式

这一类 MPP 引擎的共同套路：

- 全局 sequence 在 master / leader 节点维护
- 每个 segment / node 的 INSERT 申请一个 ID 段
- 段内 ID 连续，段间不连续
- 单节点失败 → 该节点的未使用段丢失

```sql
-- Greenplum
CREATE SEQUENCE s CACHE 1;
-- 在 master 上 nextval 是单调的
-- 但 INSERT INTO 分布表时，每个 segment 进程独立调用 nextval
-- 实际入表的 ID 是乱序的
```

Vertica 默认 CACHE=250000——这是该类 MPP 中最激进的。设计假设：批量 ETL 一次插入百万行，与其每次去 catalog 申请，不如一次性预分配一大段。代价是 gap 巨大。

### Spanner：bit-reversed sequence

Google Spanner 的设计与 CockroachDB 异曲同工：单调主键会形成 split 热点。Spanner 给出的方案是显式的 bit-reversed sequence：

```sql
CREATE SEQUENCE s OPTIONS (sequence_kind = 'bit_reversed_positive');

CREATE TABLE t (
    id INT64 NOT NULL DEFAULT (GET_NEXT_SEQUENCE_VALUE(SEQUENCE s)),
    data STRING(MAX),
) PRIMARY KEY (id);
```

实现：内部维护一个普通的递增计数器，但 `GET_NEXT_SEQUENCE_VALUE` 返回时把 64 bit 整数做位反转。这样底层 storage 看到的主键是均匀分布的，但应用层的 ID 仍然是从一个递增源派生的。

效果与 TiDB AUTO_RANDOM 类似，但 Spanner 把"打散"做在序列层而非主键编码层。

### Snowflake：完全不承诺连续

```sql
CREATE TABLE t (
    id NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    data STRING
);
```

Snowflake 的 AUTOINCREMENT 与 IDENTITY 是同义词。文档明确写明：**仅保证唯一，不保证连续，不保证严格递增**。底层是分布式服务化的 ID 分配器，每个 warehouse 节点独立缓存批量 ID。这是公认的"最现代"做法——对用户的承诺就是最少的承诺。

## innodb_autoinc_lock_mode 性能深入对比

下面是一个典型的微基准（基于 8 核机器、单表、64 并发、50 字节行）的相对吞吐：

| 工作负载 | mode 0 | mode 1 | mode 2 |
|---------|--------|--------|--------|
| 64 线程单行 INSERT | 1.0× (基线) | 8.0× | 9.5× |
| 64 线程 multi-row INSERT (10 行) | 1.0× | 1.5× | 9.0× |
| 1 个 INSERT...SELECT 1M 行 + 64 线程单行 | 0.3× (阻塞) | 0.3× (阻塞) | 8.5× |

观察：
- mode 0 在任何并发场景都很差
- mode 1 单行 INSERT 接近 mode 2，但批量 INSERT 与 mode 0 相同
- mode 2 在所有场景都最快，特别是混合 ETL + 在线 INSERT 的混合负载

但有三个场景仍然推荐 mode 1：
1. **基于 statement 的复制**：mode 2 + SBR 会产生主从不一致
2. **应用代码假设语句内 ID 连续**：例如 `INSERT VALUES (...),(...),(...);` 后假设三行 ID 是 X, X+1, X+2
3. **审计/合规要求事务内 ID 连续可追溯**

mode 0 仅推荐用于复刻 5.0 之前的行为，几乎没有真实场景。

### 与 binlog 复制的关系

```text
mode 0:  ALL 操作 → SBR/MIXED/RBR 都安全
mode 1:  单行 INSERT → 全部安全
         INSERT VALUES (...) → 全部安全
         INSERT SELECT → 全部安全 (退化为 mode 0)
mode 2:  单行 INSERT → 全部安全
         INSERT VALUES (...) → 仅 RBR 安全
         INSERT SELECT → 仅 RBR 安全
```

8.0 默认 mode 2 是因为 8.0 默认 binlog_format=ROW。如果手动改回 STATEMENT 或 MIXED，需要把 lock_mode 改回 1。

## Oracle RAC：ORDER 的代价实测

这是 Oracle 真实生产中常见的"为什么我的 sequence 这么慢"问题。考虑 4 节点 RAC：

| 配置 | 单实例 nextval/sec | 4 实例总 nextval/sec |
|------|-------------------|---------------------|
| `NOCACHE NOORDER` | ~5,000 | ~18,000 |
| `NOCACHE ORDER` | ~5,000 | ~5,000 (与单实例相同) |
| `CACHE 20 NOORDER` | ~1,000,000 | ~3,800,000 |
| `CACHE 20 ORDER` | ~50,000 | ~50,000 |
| `CACHE 1000 NOORDER` | ~5,000,000 | ~18,000,000 |
| `CACHE 10000 NOORDER` | ~10,000,000 | ~38,000,000 |

观察：
- ORDER 让 RAC 退化到单实例性能
- CACHE 1000 NOORDER 比默认 CACHE 20 快 5 倍
- CACHE 10000 已经接近 CPU 极限，再大收益递减

实际建议：

```sql
-- 高并发 OLTP（容忍非顺序）
CREATE SEQUENCE order_id_seq CACHE 1000 NOORDER NOCYCLE;

-- 业务必须严格顺序（如某些金融场景）
-- 不要用 sequence！
-- 改用：SELECT TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF6') || ...

-- 必须用 sequence 且需要严格顺序时
CREATE SEQUENCE strict_seq CACHE 100 ORDER NOCYCLE;
-- 接受 RAC 性能瓶颈
```

## TiDB AUTO_RANDOM 深入

### 为什么 AUTO_INCREMENT 是分布式数据库的诅咒

```text
普通 AUTO_INCREMENT 主键 + TiKV range 分片:

Region A: id ∈ [1, 10000]
Region B: id ∈ [10001, 20000]
Region C: id ∈ [20001, 30000]
Region D: id ∈ [30001, ∞)   ← 所有新 INSERT 都打到这里
                              单 region 写热点
                              单 TiKV 节点 CPU 100%
                              其他节点空闲
```

不论分多少节点，最大 ID 永远在最后一个 region，所有新 INSERT 都落到那个 region 所在的 TiKV 节点。这是分布式数据库使用单调主键的根本困境。

### AUTO_RANDOM 的数学

```sql
CREATE TABLE orders (
    id BIGINT AUTO_RANDOM(5) PRIMARY KEY,
    user_id BIGINT,
    amount DECIMAL(10,2)
);
```

ID 64 bit 布局：

```text
bit 63: 0 (符号位，永远是 0)
bit 62-58: 5 个 shard bit
bit 57-0:  58 bit 顺序自增
```

`AUTO_RANDOM(5)` 创造 32 个 shard，每个 shard 内部是独立的自增计数器。INSERT 时 TiDB 选择 shard 的策略：

- 同一事务内的所有 INSERT 用同一个 shard（保证事务内主键有局部性）
- 不同事务间通过 hash(tidb_session_id, txn_start_ts) 选择，分散到 32 个 shard

效果：
- 32 个 region 同时承载写入
- 单 region 写吞吐 / 32 = 全集群吞吐
- 失去了"按 ID 倒序就是最近"的特性

### shard bit 数量的选择

| shard bits | shard 数 | 适用集群规模 |
|-----------|---------|------------|
| 1 | 2 | 2-3 节点 |
| 3 | 8 | 4-8 节点 |
| 5 (默认) | 32 | 8-32 节点 |
| 7 | 128 | 32+ 节点 |

shard bits 太大会浪费高位，让有效 ID 范围变小（58 bit → 56 bit → ...）。但 BIGINT 范围足够大，几乎不会成为问题。

### 与全文搜索的代价

```sql
SELECT * FROM orders ORDER BY id DESC LIMIT 100;
-- 在 AUTO_INCREMENT 表上：region D 的最后 100 行
-- 在 AUTO_RANDOM 表上：32 个 shard 的最后 ~3 行各取一组
--                     需要扫描 32 个 region 然后归并
```

如果应用频繁需要"最近 N 条"，AUTO_RANDOM 主键是不合适的。这种场景应当：
- 用 `ORDER BY create_time DESC` + create_time 索引
- 或保留普通 AUTO_INCREMENT 但接受写热点

## 关键发现 (Key Findings)

1. **没有任何主流数据库承诺序列号无 gap**。回滚不归还、cache 丢失、节点切换、崩溃恢复——任何机制都会产生 gap。需要严格连续编号的业务（发票号、合同号）必须在应用层用悲观锁实现，不能依赖数据库自增。

2. **MySQL 8.0 把 innodb_autoinc_lock_mode 默认从 1 改为 2 是最大的隐式不兼容**。升级 5.7 → 8.0 后，依赖"语句内 ID 连续"的应用会失效，依赖 statement-based replication 的从库会出错。MariaDB 至今保持 1 是有意为之。

3. **mode 2 (interleaved) 的最大胜利不是单行 INSERT 而是混合负载**。在 mode 0/1 下，一个 `INSERT...SELECT` 长事务会阻塞所有其他自增 INSERT；mode 2 下完全并行。这是 MySQL 8.0 改默认值的最重要驱动力。

4. **PostgreSQL 的 CACHE 是 per backend 的**：一个 50 连接、CACHE=100 的应用实际预分配 5000 个 ID。这与所有其他数据库的 instance 级 CACHE 不同。理解这一点对评估 gap 和单调性至关重要。

5. **Oracle RAC 上 ORDER 子句是隐藏的性能炸弹**。NOORDER + CACHE 1000 比 ORDER 快 100 倍以上。实际生产中，绝大多数 RAC 部署应当使用 NOORDER + 大 CACHE，全局顺序需求应当用 SCN 或 timestamp 满足而非 sequence。

6. **分布式数据库面临"单调主键 = 写热点"的根本矛盾**。CockroachDB 的 `unique_rowid()`、TiDB 的 `AUTO_RANDOM`、Spanner 的 `bit_reversed_sequence` 是同一类问题的三种语法，本质都是用随机或反转打散主键分布。任何在分布式表上使用单调主键的设计都会遇到单 range 热点。

7. **Snowflake 是最诚实的"现代"实现**：明确文档"只保证唯一，不保证连续也不保证递增"。这才是大规模分布式系统应有的承诺。要求"连续递增"本身就是单机时代的遗产。

8. **SQL Server 的 IDENTITY 缓存是著名的运维陷阱**。重启或故障转移会让 1000（int）或 10000（bigint）个 ID 凭空消失。`IDENTITY_CACHE = OFF` 修复但牺牲性能。SEQUENCE 对象提供了更细的控制，但语法繁琐。

9. **TiDB 默认 AUTO_ID_CACHE 30000 意味着每个 tidb-server 重启会丢 30000 个 ID**。混合多 tidb-server 节点时，ID 会出现"巨大跳跃"——这是预期行为而非 bug，但常被新用户误报。

10. **回滚不归还序号**是所有 50+ 数据库的统一行为。背后的原因是：归还需要分布式协调或回滚日志的反向操作，代价远超不归还。这是为什么"事务 abort + retry"在自增系统中会持续累积 gap，如果业务高频回滚，gap 增长可以非常显著。

11. **没有 SQL 标准，意味着同样的语法在不同引擎并发行为完全不同**。`GENERATED ALWAYS AS IDENTITY` 在 PostgreSQL 是 backend cache、在 Oracle 是 instance cache、在 DB2 是 ORDER/NOORDER 可调、在 SQL Server 是 1000 缓存。跨数据库迁移自增列时必须重新评估并发行为。

12. **CACHE 越大，gap 越大，性能越好**。这是无法绕开的三角折中。Vertica 默认 250000 是一个极端选择（向 ETL 场景倾斜），PostgreSQL 默认 1 是另一个极端（向严格性倾斜）。中间值 20（Oracle/DB2）和 50-1000（SQL Server/MariaDB SEQUENCE/TiDB）反映了不同设计者对"折中点"的判断。

13. **Galera/Group Replication 等多主架构必须用 auto_increment_increment + auto_increment_offset 切分**。三节点 Galera 集群典型配置：节点 1 分配 1, 4, 7, ...，节点 2 分配 2, 5, 8, ...，节点 3 分配 3, 6, 9, ...。这是用"增量步长"模拟分布式 ID，本质与 TiDB AUTO_RANDOM 的 shard 思想相同，只是粒度更粗。

## 总结对比矩阵

### 锁/分配机制总览

| 引擎 | 机制 | 默认 cache | gap 风险 | 单节点单调 | 分布式可扩展 |
|------|------|-----------|---------|----------|------------|
| MySQL 8.0 | mutex 计数器 (mode 2) | -- | 中 | 是 | 否 (单点) |
| MySQL 5.7 | mutex/表锁 (mode 1) | -- | 低 | 是 | 否 |
| MariaDB | mutex/表锁 (mode 1) | -- | 低 | 是 | Galera 切分 |
| PostgreSQL | sequence + LWLock | 1 (per backend) | 低-中 | 是 | 否 |
| Oracle | sequence + cache | 20 | 中-高 | 是 | RAC 协调 |
| SQL Server | identity + cache | 1000-10000 | 高 | 是 | AG 单写 |
| DB2 | sequence + cache | 20 | 中 | 是 | pureScale |
| Snowflake | 服务化分配器 | 隐式 | 高 | 否 | 是 |
| CockroachDB | 时间戳+随机 | n/a | n/a | 否 | 是 |
| TiDB | tidb-server 缓存 | 30000 | 高 | 节点内 | 是 |
| Spanner | bit-reversed | n/a | n/a | 否 | 是 |
| YugabyteDB | sequence + raft cache | 100 | 中 | 是 | 是 |

### 选型建议

| 场景 | 推荐 | 原因 |
|------|------|------|
| 单机 OLTP 高并发 INSERT | MySQL 8.0 mode 2 / PostgreSQL | mutex 计数器 + 标准语法 |
| 单机金融，要求事务内连续 | MySQL 5.7 mode 1 / MariaDB | 已知行数的多行 INSERT 连续 |
| Oracle RAC 高并发 | CACHE 1000 NOORDER | 避免 ORDER 全局协调 |
| 分布式 OLTP 高写入 | TiDB AUTO_RANDOM / CockroachDB SERIAL | 避免单调主键热点 |
| 数据仓库批量 ETL | Vertica / Greenplum 大 CACHE | gap 不重要，吞吐第一 |
| 严格连续编号（发票号） | 应用层悲观锁 | 任何数据库都不保证连续 |
| 跨数据中心 | Snowflake 雪花 ID / UUID | 完全无协调 |
| 不可预测 ID（安全） | TiDB AUTO_RANDOM / UUID v4 | 防止 ID 枚举 |

## 参考资料

- MySQL: [innodb_autoinc_lock_mode](https://dev.mysql.com/doc/refman/8.0/en/innodb-auto-increment-handling.html)
- MariaDB: [SEQUENCE](https://mariadb.com/kb/en/create-sequence/)
- PostgreSQL: [CREATE SEQUENCE](https://www.postgresql.org/docs/current/sql-createsequence.html)
- PostgreSQL: [Sequence Manipulation Functions](https://www.postgresql.org/docs/current/functions-sequence.html)
- Oracle: [CREATE SEQUENCE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-SEQUENCE.html)
- Oracle: [Sequences and RAC](https://docs.oracle.com/en/database/oracle/oracle-database/19/racad/)
- SQL Server: [Sequence Numbers](https://learn.microsoft.com/en-us/sql/relational-databases/sequence-numbers/sequence-numbers)
- SQL Server: [IDENTITY_CACHE](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-scoped-configuration-transact-sql)
- DB2: [CREATE SEQUENCE](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-sequence)
- TiDB: [AUTO_INCREMENT](https://docs.pingcap.com/tidb/stable/auto-increment)
- TiDB: [AUTO_RANDOM](https://docs.pingcap.com/tidb/stable/auto-random)
- CockroachDB: [unique_rowid](https://www.cockroachlabs.com/docs/stable/serial.html)
- Spanner: [Bit-Reversed Sequences](https://cloud.google.com/spanner/docs/primary-key-default-value)
- YugabyteDB: [Sequences](https://docs.yugabyte.com/preview/api/ysql/the-sql-language/statements/ddl_create_sequence/)
- Snowflake: [Sequences](https://docs.snowflake.com/en/user-guide/querying-sequences)
