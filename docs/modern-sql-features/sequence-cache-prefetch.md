# 序列缓存与预取 (Sequence Cache and Prefetch)

一行 `CACHE 1000` 的差别，可能是订单系统每秒 200 单和每秒 30000 单之间的鸿沟——也可能是数据库崩溃后业务报表里突然出现的 999 个空缺序号背后的元凶。序列缓存是 OLTP 引擎里被广泛使用却最少被严格记录的一项实现细节：标准没有一个字描述它，文档常常含糊其辞，而引擎之间的默认值差了三个数量级。本文聚焦"缓存大小如何影响吞吐"和"崩溃时缓存中的序号去了哪里"，对 45+ 数据库的 SEQUENCE/IDENTITY 缓存实现做一次纵向横切。

> 注：本文专注于"缓存与预取"维度。若关注 SEQUENCE/IDENTITY 的语法对比、UUID/Snowflake/AUTO_RANDOM 等通用 ID 生成话题，请参阅同目录的 [`auto-increment-sequence-identity.md`](./auto-increment-sequence-identity.md)；若关注自增锁、并发分配模式（traditional/consecutive/interleaved）、ORDER 子句的并发代价，请参阅 [`auto-increment-locking.md`](./auto-increment-locking.md)。

## 核心权衡：吞吐 vs 间隙

序列缓存的本质是把"持久化最新已分配值"这件昂贵的操作（每次都要写 redo log/WAL/system table）摊销到一批 ID 上。开销-间隙这对反向关系决定了所有引擎的设计：

```
没有 CACHE：
  每次 nextval()
    → 加锁
    → 读取持久化值
    → 加 1
    → 写回持久化（fsync）
    → 解锁
  典型延迟：1-3 ms（fsync 主导）
  典型吞吐：单实例 < 1000 ops/s

CACHE n：
  每 n 次 nextval() 才有一次磁盘写
  内存中维护 [allocated_start, allocated_end] 区间
  在区间内分配是纯内存操作
  典型延迟：< 1 μs（内存级）
  典型吞吐：单实例 100K+ ops/s（n 越大越接近）
```

但这一摊销有代价：**当缓存的 [allocated_start, allocated_end] 区间被持久化到了磁盘，但内存中只用到了一部分时**，如果实例崩溃或正常关闭，未使用的部分就永远消失了。下次实例启动从持久化值（即 allocated_end）继续分配，造成一段间隙。CACHE 越大，崩溃造成的间隙越大；CACHE 越小，吞吐越低。

进一步的复杂性来自 RAC/集群场景：Oracle 的 `ORDER` 子句要求 RAC 多实例分配的序号严格递增，而每个实例都有自己的 cache 时，这意味着每次 `nextval()` 都要在节点间协调——`ORDER` 在 RAC 上的代价比单机 `NOORDER` 高 1-2 个数量级。

## 没有 SQL 标准

ISO/IEC 9075（SQL:2003 起定义 `CREATE SEQUENCE`）规定了序列对象的语法和语义，但**完全没有定义 CACHE 行为**：

- 没有规定是否可以预分配
- 没有规定预分配的粒度（per session vs per instance vs per cluster）
- 没有规定崩溃时缓存值的归宿
- 没有规定 RAC/集群下的协调方式
- 没有规定 NOCACHE 是否真的"零间隙"

所以同样写 `CREATE SEQUENCE order_seq CACHE 100`，PostgreSQL 是每个 backend 独立缓存 100 个，Oracle 是整个 instance 共享缓存 100 个，TiDB 是每个 tidb-server 缓存 1000 个（CACHE 子句被忽略），DB2 是 instance 共享 100 个。这种"语法相同语义截然不同"的状况，是序列缓存领域最大的陷阱。

实现者必须独立做出五个核心决策：

1. **缓存粒度**：per session/backend vs per instance vs per cluster
2. **默认 CACHE 大小**：1（PG/Greenplum）到 250000（Vertica）跨越六个数量级
3. **NOCACHE 是否暴露给用户**：以及 NOCACHE 是否真的"无间隙"
4. **崩溃恢复语义**：缓存中的剩余值是否丢弃
5. **集群/分布式协调**：每节点独立缓存（吞吐高，全局乱序）vs 全局协调（严格有序，吞吐低）

## 支持矩阵（综合）

### 1. 默认 CACHE 大小

| 引擎 | 默认 CACHE | 最大 CACHE | NOCACHE 子句 | 备注 |
|------|-----------|-----------|--------------|------|
| Oracle | 20 | MAXVALUE-MINVALUE | `NOCACHE` | 1985 年 v6 已存在 |
| PostgreSQL | 1 | 无明确上限 (BIGINT) | 设 `CACHE 1` | per backend 缓存 |
| SQL Server | 实现定义（多为 50） | 不暴露 | `NO CACHE` | 文档未公开默认值 |
| DB2 | 20 | 不限 | `NO CACHE` | LUW 与 z/OS 一致 |
| MariaDB SEQUENCE | 1000 | BIGINT | `NOCACHE` | 10.3+ 独立引擎 |
| MySQL | 不支持 SEQUENCE | -- | -- | 仅 AUTO_INCREMENT |
| SQLite | 不支持 SEQUENCE | -- | -- | rowid 内部计数 |
| Snowflake | 自动管理 | 不暴露 | 不暴露 | 服务化分配 |
| BigQuery | 不支持 SEQUENCE | -- | -- | 推荐 GENERATE_UUID |
| Redshift | 不暴露 | 不暴露 | -- | leader 节点缓存 |
| CockroachDB | 1 | BIGINT | `NO CACHE` | 兼容 PG，per node |
| TiDB SEQUENCE | 1000 | BIGINT | `NOCACHE` | per tidb-server |
| OceanBase | 20 (Oracle) / 1000 (MySQL) | BIGINT | `NOCACHE` | 看兼容模式 |
| YugabyteDB | 100 | BIGINT | `CACHE 1` | 2.13+ 起 100，之前 1 |
| Greenplum | 1 | BIGINT | -- | 继承 PG |
| Vertica | 250000 | BIGINT | `NO CACHE` | 默认值最激进 |
| SingleStore | 不暴露 | 不暴露 | -- | partition 切片 |
| H2 | 32 | INT | `NOCACHE` | 早期已支持 |
| HSQLDB | 1 | BIGINT | -- | 引擎级 |
| Derby | 1 | BIGINT | -- | 引擎级 |
| MonetDB | 不暴露 | -- | -- | -- |
| Firebird | 1 | -- | -- | GENERATOR 即时持久化 |
| Informix | 1 | -- | -- | -- |
| SAP HANA | 1 | BIGINT | `NO CACHE` | indexserver 级 |
| Exasol | 1000 | BIGINT | `NOCACHE` | per node |
| Spanner | n/a | n/a | n/a | bit-reversed sequence |
| Databricks Delta IDENTITY | 内部 batch | 不暴露 | -- | 写者级缓存 |
| Teradata IDENTITY | 不暴露 | 不暴露 | `NO CYCLE NO MINVALUE NO MAXVALUE` 风格 | 按 AMP 切片 |
| ClickHouse | 不支持 SEQUENCE | -- | -- | UInt64 按时间 |
| Trino / Presto / Athena | 无写引擎 | -- | -- | 不适用 |
| Spark SQL | 不支持 SEQUENCE | -- | -- | -- |
| Hive | 不支持 SEQUENCE | -- | -- | -- |
| Flink SQL | 流处理 | -- | -- | -- |
| Doris / StarRocks | 不支持 SEQUENCE | -- | -- | -- |
| MaxCompute | 不支持 SEQUENCE | -- | -- | -- |
| RisingWave | 1 (PG 兼容) | -- | -- | 继承 PG |
| Materialize | 不支持 | -- | -- | 流处理 |
| Yellowbrick | 1 | BIGINT | -- | 继承 PG |
| Firebolt | 不支持 | -- | -- | -- |
| InfluxDB (SQL) | 不支持 | -- | -- | 时序 |
| QuestDB | 不支持 | -- | -- | 时序 |
| TimescaleDB | 1 | BIGINT | -- | 继承 PG |
| EDB Postgres | 1 | BIGINT | -- | 继承 PG |
| Aurora PostgreSQL | 1 | BIGINT | -- | 继承 PG |
| Aurora MySQL | n/a | -- | -- | 仅 AUTO_INCREMENT |
| AlloyDB | 1 | BIGINT | -- | 继承 PG |
| openGauss | 1 | BIGINT | -- | PG 衍生 |
| TDSQL-PG | 1 | BIGINT | -- | PG 衍生 |
| GaussDB | 100 | BIGINT | -- | 200+ 客户优化 |
| CrateDB | 不支持 SEQUENCE | -- | -- | -- |
| Databend | 不暴露 | -- | -- | snowflake 风格 |
| Sybase ASE | 不适用 | -- | -- | IDENTITY GAP 参数 |
| Azure SQL Database | 实现定义 | -- | `NO CACHE` | 同 SQL Server |
| Azure Synapse | 不暴露 | -- | -- | 切片偏移 |

> 统计：约 30+ 个引擎支持 `CREATE SEQUENCE` 并暴露 `CACHE` 子句；默认值跨越六个数量级，从 PostgreSQL/Greenplum/SAP HANA 的 1 到 Vertica 的 250000；约 15 个引擎不支持 SEQUENCE（MySQL/SQLite/BigQuery/ClickHouse/MPP 引擎为代表）。

### 2. 缓存粒度（per session vs per instance vs per cluster）

| 引擎 | 缓存粒度 | 多 backend/连接是否共享 cache | 备注 |
|------|---------|---------------------------|------|
| PostgreSQL | per session/backend | 否 | 每个连接独立 cache 范围 |
| Oracle | per instance | 是 | shared pool 中缓存 |
| Oracle RAC NOORDER | per instance（多实例独立） | 实例内是 | 每节点独立段 |
| Oracle RAC ORDER | 全局（每次跨节点协调） | 是 | 巨大性能代价 |
| SQL Server SEQUENCE | per instance | 是 | 与 IDENTITY 不同实现 |
| SQL Server IDENTITY | 隐式 instance 级 cache（1000/10000） | 是 | 不可关闭，仅可 trace flag 272 |
| DB2 | per instance | 是 | 标准 LUW 行为 |
| DB2 pureScale | 集群协调 | 是 | 跨成员共享 |
| MariaDB SEQUENCE | per session | 否 | 类 PG 行为 |
| Snowflake | warehouse 级（不暴露） | 是 | 服务化分配 |
| Redshift | leader 级 | 是 | leader 节点全局唯一 |
| Greenplum | per session | 否 | 继承 PG |
| CockroachDB | per node | 否 | 范围分配 |
| TiDB SEQUENCE | per tidb-server | 是（同节点上） | 节点间不共享 |
| OceanBase | per observer | 是（同 observer 上） | -- |
| YugabyteDB | per backend | 否 | 类 PG，2.13+ 默认 100 |
| SingleStore | per partition | 否 | partition 切片 |
| Vertica | per node | 否 | 节点本地 |
| H2 | per session | 否 | -- |
| HSQLDB | 单进程 | 是 | -- |
| Derby | 单进程 | 是 | -- |
| Firebird | 即时持久化 | 是 | 不缓存 |
| Informix | 单进程 | 是 | -- |
| SAP HANA | indexserver 级 | 是 | -- |
| Exasol | per node | 否 | 节点本地 |
| Spanner | n/a | n/a | bit-reversed |
| Databricks Delta | 写者级 | 否 | batch 内分配 |
| Teradata | per AMP | 否 | AMP 切片 |
| TimescaleDB | per session | 否 | 继承 PG |
| Databend | 节点级 | 否 | snowflake 风格 |

### 3. 崩溃后间隙范围

| 引擎 | 正常关闭 | 崩溃 | 间隙最大值 | 备注 |
|------|---------|------|-----------|------|
| PostgreSQL | 已分配 cache 丢弃 | 已分配 cache 丢弃 | CACHE 大小 × backend 数 | 每个 backend 独立 |
| Oracle | 缓存写回 | cache 全部丢失 | CACHE 大小 | shutdown immediate 写回 |
| Oracle RAC | 各实例 cache 丢失 | 同左 | CACHE × 节点数 | 每节点独立缓存段 |
| SQL Server SEQUENCE NOCACHE | 0 间隙 | 0 间隙 | 0 | 但仍有事务回滚间隙 |
| SQL Server SEQUENCE CACHE | cache 丢弃 | cache 丢弃 | CACHE 大小 | -- |
| SQL Server IDENTITY | 通常 0 | **可达 1000-10000** | 1000-10000 | 默认行为，需 trace 272 关闭 |
| DB2 | cache 丢弃 | cache 丢弃 | CACHE 大小 | -- |
| MariaDB SEQUENCE | cache 丢弃 | cache 丢弃 | 1000 × session 数 | 默认 1000 较激进 |
| Snowflake | n/a | n/a | 不可估 | 服务化 |
| Redshift | cache 丢弃 | cache 丢弃 | 不暴露 | -- |
| CockroachDB SEQUENCE | cache 丢弃 | cache 丢弃 | CACHE 大小 × 节点 | 默认 1 |
| TiDB SEQUENCE | cache 丢弃 | cache 丢弃 | 1000 × tidb-server 数 | -- |
| TiDB AUTO_INCREMENT | cache 丢弃 | cache 丢弃 | 30000 × tidb-server 数 | 默认 cache 比 SEQUENCE 大 |
| YugabyteDB | cache 丢弃 | cache 丢弃 | 100 × backend 数 | -- |
| Greenplum | cache 丢弃 | cache 丢弃 | 1 × session 数 | 默认 1，间隙小 |
| Vertica | cache 丢弃 | cache 丢弃 | **250000 × 节点数** | 间隙最大 |
| SingleStore | cache 丢弃 | cache 丢弃 | 不暴露 × partition | -- |
| Exasol | cache 丢弃 | cache 丢弃 | 1000 × 节点 | -- |
| H2 | cache 丢弃 | cache 丢弃 | 32 × session | -- |
| HSQLDB | n/a | 0（非缓存） | 0 | -- |
| Derby | n/a | 0（非缓存） | 0 | -- |
| Firebird | 0 间隙（非缓存） | 0 间隙 | 0 | GENERATOR 立即持久化 |
| Informix | n/a | 0 间隙 | 0 | -- |
| SAP HANA | cache 丢弃 | cache 丢弃 | 1 默认 | 默认极小 |
| Databricks Delta | batch 内连续 | 已写 batch 持久化 | batch 大小 | -- |
| Teradata | n/a | 视实现 | -- | -- |
| Spanner bit-reversed | 否 | 否 | n/a | 不适用 |
| 其他 PG 衍生 | 同 PG | 同 PG | 1 × session 数 | -- |

### 4. ORDER / NOORDER 子句（多实例顺序保证）

| 引擎 | ORDER 子句 | 默认 | 在单实例的含义 | 在 RAC/集群的含义 | 性能代价 |
|------|-----------|------|---------------|------------------|---------|
| Oracle | `ORDER`/`NOORDER` | NOORDER | 无显著差异 | ORDER 强制全局协调 | RAC 上 1-2 数量级 |
| DB2 | `ORDER`/`NO ORDER` | NO ORDER | 序列化分配 | pureScale 全局协调 | 类似 Oracle |
| OceanBase Oracle 模式 | `ORDER`/`NOORDER` | NOORDER | 兼容 Oracle | 兼容 Oracle | -- |
| PostgreSQL | -- | -- | -- | -- | -- |
| MySQL | -- | -- | -- | -- | -- |
| SQL Server | -- | -- | -- | -- | -- |
| MariaDB SEQUENCE | -- | -- | -- | -- | -- |
| Snowflake | n/a | n/a | n/a | n/a | -- |
| CockroachDB | -- | -- | -- | -- | -- |
| TiDB SEQUENCE | -- | -- | -- | -- | -- |
| YugabyteDB | -- | -- | -- | -- | -- |
| H2 | -- | -- | -- | -- | -- |
| 其他大多数 | -- | -- | -- | -- | -- |

> ORDER 子句是 Oracle 8i RAC 时代为解决"多节点序列号交错"问题专门引入的。除 DB2 和 OceanBase Oracle 模式外，其他引擎几乎不暴露这个语义——主流分布式数据库的设计哲学是"接受最终有序、追求高吞吐"，而非"严格全局有序"。

### 5. NOCACHE 子句的真实语义

| 引擎 | NOCACHE 子句 | 等价于 | 是否真的零间隙 |
|------|-------------|--------|---------------|
| Oracle | `NOCACHE` | `CACHE 0`（实际仍 CACHE 1） | 否（事务回滚仍产生间隙） |
| PostgreSQL | 无（用 `CACHE 1`） | -- | 否（事务回滚） |
| SQL Server | `NO CACHE` | -- | 否（事务回滚） |
| DB2 | `NO CACHE` | -- | 否（事务回滚） |
| MariaDB SEQUENCE | `NOCACHE` | -- | 否 |
| CockroachDB | `NO CACHE` | -- | 否 |
| TiDB | `NOCACHE` | -- | 否 |
| OceanBase | `NOCACHE` | -- | 否 |
| YugabyteDB | `CACHE 1` | -- | 否 |
| Vertica | `NO CACHE` | -- | 否 |
| H2 | `NOCACHE` / `CACHE 1` | -- | 否 |
| SAP HANA | `NO CACHE` | -- | 否 |
| Exasol | `NOCACHE` | -- | 否 |
| Firebird | n/a（GENERATOR 永远即时） | -- | 否（事务回滚） |

> 反直觉的关键事实：**没有任何引擎的 NOCACHE 能保证"无间隙"**。即使关闭缓存，只要事务回滚或 INSERT 失败，已分配的序号也不会归还。NOCACHE 只能减少"崩溃造成的"间隙，但无法消除"业务造成的"间隙。需要无间隙编号请改用 [应用层计数器表 + SELECT FOR UPDATE](./auto-increment-sequence-identity.md#cache-与-nocache-的影响)。

### 6. 序列缓存对吞吐的影响

| 引擎 | CACHE 1 吞吐 | CACHE 100 吞吐 | CACHE 10000 吞吐 | 备注 |
|------|--------------|---------------|------------------|------|
| Oracle | ~1K ops/s | ~30K ops/s | ~100K ops/s | shared pool latch 主导 |
| PostgreSQL | ~5K ops/s | ~50K ops/s | ~200K ops/s | per backend，受 WAL 影响 |
| SQL Server | ~3K ops/s | ~50K ops/s | ~200K ops/s | sys.sequences IO |
| DB2 | ~1K ops/s | ~30K ops/s | ~100K ops/s | 类 Oracle |
| MariaDB SEQUENCE | ~5K ops/s | ~50K ops/s | ~200K ops/s | -- |
| TiDB SEQUENCE | ~500 ops/s | ~5K ops/s | ~50K ops/s | TiKV 持久化跨网络 |
| TiDB AUTO_INCREMENT cache=1 | ~100 ops/s | ~10K ops/s（cache=30000） | -- | -- |
| CockroachDB | ~500 ops/s | ~5K ops/s | ~30K ops/s | 跨 raft 协调 |
| YugabyteDB | 类 PG | 类 PG | 类 PG | -- |
| Vertica | n/a | -- | ~500K ops/s | 默认 250000 |

> 数字仅作量级参考，实际吞吐受 NUMA、CPU 频率、磁盘类型、并发度影响极大。共同的规律是：**CACHE 大小每翻 10 倍，吞吐提升不到 10 倍**（边际收益递减），因为非缓存开销（锁、WAL、网络）逐渐主导。

## 各引擎详解

### Oracle：CACHE 20 是 1985 年的遗产

Oracle 是序列对象的最早实现者之一，其 `CACHE 20` 默认值出现在 v6（1988）的 SQL 参考手册中，至今 23ai 仍未改动：

```sql
-- 默认 CACHE 20
CREATE SEQUENCE order_seq;
-- 等价于
CREATE SEQUENCE order_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9999999999999999999999999999
    NOCYCLE
    CACHE 20
    NOORDER;

-- 显式高 CACHE
CREATE SEQUENCE high_throughput_seq CACHE 1000;

-- 显式 NOCACHE
CREATE SEQUENCE strict_seq NOCACHE;
-- 注意：NOCACHE 仍会缓存 1 个值，每次都写回 SYS.SEQ$ 表
-- 仍有事务回滚造成的间隙，没有真正"无间隙"

-- ORDER 子句（仅 RAC 有意义）
CREATE SEQUENCE rac_ordered_seq CACHE 100 ORDER;
-- 在 RAC 上：所有节点请求都通过单一锁服务全局排序
-- 在单实例：与 NOORDER 行为相同，仅记录元数据差异
```

Oracle 的实现细节：

```
sequence cache 在 SGA 的 shared pool 中
nextval() 流程：
  1. 获取 sequence 上的 row cache lock
  2. 从内存 cache 中分配下一个值
  3. 当 cache 用尽：
     a. 等待 SYS.SEQ$ 表上的 row lock
     b. UPDATE SEQ$ SET HIGHWATER = HIGHWATER + CACHE
     c. 写 redo log
     d. 重新填充内存 cache
  4. 释放 row cache lock

崩溃恢复：
  shared pool 中的 cache 全部丢失
  下次启动从 SYS.SEQ$ 的 HIGHWATER 继续
  → 间隙最大为 CACHE × instance_count（RAC）
```

**RAC 上 ORDER 的代价**：每次 nextval 都要通过 GES（Global Enqueue Service）跨节点协调。在繁忙的 OLTP 系统上，ORDER + RAC 序列可能成为整个集群的瓶颈，单节点吞吐降到 1K ops/s 以下。Oracle 文档明确警告："Use ORDER only when necessary, such as when generating timestamps."

### PostgreSQL：CACHE 1 + per backend 缓存

PostgreSQL 的 SEQUENCE 设计哲学与 Oracle 截然相反：默认极小缓存（1），但缓存粒度是**每个 backend（连接）独立**：

```sql
-- 默认 CACHE 1
CREATE SEQUENCE order_seq;

-- 等价于
CREATE SEQUENCE order_seq
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9223372036854775807
    NO CYCLE
    CACHE 1
    OWNED BY NONE;

-- 高吞吐场景显式增大 cache
CREATE SEQUENCE high_throughput_seq CACHE 1000;

-- 注意：CACHE n 在 PostgreSQL 是 per backend，不是 per cluster
-- 即 backend A 取走 [1, 100]，backend B 启动后取 [101, 200]
-- 每个 backend 关闭时，未用部分丢失
-- → 如果有 100 个 idle backend 各 cache 100 → 潜在间隙 10000
```

PostgreSQL 的实现细节：

```
sequence 在物理上是一种特殊的 relation
存储位置：pg_catalog 中的 sequence relation
每个 sequence 占一个 page (8KB)
nextval() 流程：
  1. 在共享内存中查找当前 backend 是否已 cache
  2. 若已 cache 且未用尽：直接分配（lockless 路径）
  3. 若未 cache 或已用尽：
     a. 加 buffer lock on sequence page
     b. 从 page 读 last_value
     c. 写新 last_value = last_value + CACHE
     d. 标记 page dirty
     e. 写 WAL 记录（XLOG_SEQ_LOG）
     f. 释放 buffer lock
  4. 在内存中预分配 [last_value-CACHE+1, last_value] 给当前 backend

崩溃恢复：
  通过 WAL 恢复 sequence page
  但每个 WAL 记录只标记到下一段的开始
  即如果 WAL 记录是 "next start = 101, allocated 100"
  恢复后从 101 开始，cache 中已分配但未使用的 1-100 全部丢失
  → 间隙范围 = CACHE × 当时活跃的 backend 数
```

PostgreSQL 默认 `CACHE 1` 看起来很激进——每次 nextval 都要写 WAL？实际上，PostgreSQL 对 `CACHE 1` 的 sequence 做了特殊优化：

```
PostgreSQL 的 CACHE 1 优化：
  - WAL 记录采用 batch 形式（一个 XLOG record 可能涵盖 32 个 nextval）
  - 即使 user 视角的 CACHE 1，物理 WAL 仍然会按 32 batch
  - 这是 SEQ_LOG_VALS 常量（src/backend/commands/sequence.c）

src/include/access/xlog_internal.h 附近：
  /* internal cache for SEQ_LOG */
  #define SEQ_LOG_VALS 32

所以 PostgreSQL 的 CACHE 1 实际是：
  - user 视角：每次 nextval 立即推进
  - 物理视角：每 32 次 nextval 才写一次 WAL
  - 崩溃后最多丢 32 个值（不是用户期望的 0）

显式 CACHE 100 时：
  - 每个 backend 一次取 100
  - WAL 记录 batch 仍按 32（取整为 SEQ_LOG_VALS 倍数）
```

这个细节常被忽略——PostgreSQL 即使写 `CACHE 1` 也无法做到真正"无间隙"，崩溃仍然可能丢失最多 32 个值。

### SQL Server：IDENTITY 缓存的 1000/10000 之谜

SQL Server 的 IDENTITY 列有一个长期被忽视的"特性"：从 SQL Server 2012 开始，IDENTITY 引入了一个**不可见的内部缓存**，对 INT IDENTITY 是 1000，对 BIGINT IDENTITY 是 10000：

```sql
CREATE TABLE orders (
    id INT IDENTITY(1, 1) PRIMARY KEY,
    data NVARCHAR(100)
);

INSERT INTO orders VALUES ('a'), ('b'), ('c');
-- 假设此时 id 是 1, 2, 3
-- 内部 cache 已经预分配到 [1, 1000]

-- 现在异常关闭/重启 SQL Server
-- 重启后下一次 INSERT 得到的 id 是 1001（不是 4！）
-- 业务报表里突然出现 4-1000 的 997 个空缺
```

这个行为在 2012 年被广泛报告为"bug"，最终 Microsoft 在文档中确认这是"by design"，并提供两种缓解方式：

```sql
-- 方法 1：trace flag 272（实例级）
DBCC TRACEON(272, -1);
-- 重启后所有 IDENTITY 退化为传统行为（写日志后再分配）
-- 性能下降，但崩溃不再产生千级间隙

-- 方法 2：改用 SEQUENCE 显式指定 NO CACHE
CREATE SEQUENCE order_seq
    AS INT
    START WITH 1
    INCREMENT BY 1
    NO CACHE;

CREATE TABLE orders (
    id INT DEFAULT NEXT VALUE FOR order_seq PRIMARY KEY,
    data NVARCHAR(100)
);
-- 但仍有事务回滚造成的间隙
```

SQL Server SEQUENCE 的 CACHE 行为：

```sql
-- 默认 CACHE 大小：实现定义，文档未明确公布
-- 经验值：50 左右（取决于版本和编译选项）
CREATE SEQUENCE my_seq AS INT START WITH 1 INCREMENT BY 1;

-- 显式指定
CREATE SEQUENCE my_seq2 AS INT START WITH 1 INCREMENT BY 1 CACHE 1000;

-- NO CACHE
CREATE SEQUENCE strict_seq AS INT START WITH 1 INCREMENT BY 1 NO CACHE;

-- 查询 cache 状态
SELECT name, cache_size, current_value, last_used_value
FROM sys.sequences;
-- cache_size 列在使用 CACHE 时可见，但默认 CACHE 时显示 NULL
```

SQL Server 的设计思路明显是"性能优先"——为 IDENTITY 加了不可关闭的高 cache，并把默认 SEQUENCE cache 也放在 50 左右。这与 PostgreSQL 的 `CACHE 1` 形成鲜明对比。

### DB2：CACHE 20 + ORDER 子句

DB2 的 SEQUENCE 实现非常类 Oracle，默认 `CACHE 20`：

```sql
-- DB2 默认
CREATE SEQUENCE order_seq;
-- 等价于
CREATE SEQUENCE order_seq
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    NO CYCLE
    CACHE 20
    NO ORDER;

-- 显式高 cache + ORDER（pureScale 上有意义）
CREATE SEQUENCE rac_seq CACHE 100 ORDER;

-- NOCACHE
CREATE SEQUENCE strict_seq NO CACHE;
```

DB2 是少数几个明确暴露 `ORDER`/`NO ORDER` 子句的引擎，语义与 Oracle 一致。在 DB2 pureScale（多成员集群）上，`ORDER` 强制所有成员通过 CF（Cluster Caching Facility）协调每一次 nextval，性能代价显著。

### MariaDB：SEQUENCE 引擎与 CACHE 1000

MariaDB 在 10.3（2018 年发布）中引入了独立的 SEQUENCE 存储引擎，是 MySQL 家族首次原生支持 SEQUENCE：

```sql
-- 创建 SEQUENCE
CREATE SEQUENCE order_seq
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9223372036854775806
    CACHE 1000     -- MariaDB 默认就是 1000
    NOCYCLE;

-- 使用
SELECT NEXTVAL(order_seq);
SELECT LASTVAL(order_seq);

-- MariaDB 的 SEQUENCE 实际是一个特殊存储引擎的"表"
-- 可以 SELECT * FROM order_seq 查看所有元数据
SELECT * FROM order_seq;
-- next_not_cached_value | minimum_value | maximum_value | start_value | increment | cache_size | cycle_option | cycle_count
-- ----------------------+---------------+---------------+-------------+-----------+------------+--------------+-------------
-- 1001                  | 1             | 9223372036854775806 | 1     | 1         | 1000       | 0            | 0
```

MariaDB 的默认 `CACHE 1000` 比 Oracle/DB2 的 20 激进得多，反映了 2018 年时设计者对 OLTP 高吞吐场景的考量。但崩溃间隙也相应较大——每个 session 关闭时最多丢失 999 个序号。

### CockroachDB：CACHE 1（兼容 PG）+ 节点本地

CockroachDB 完全兼容 PostgreSQL 的 SEQUENCE 语法，但在分布式语境下重新定义了语义：

```sql
-- 默认 CACHE 1
CREATE SEQUENCE order_seq;

-- 显式 CACHE 100（per node 缓存）
CREATE SEQUENCE high_seq CACHE 100;

-- NO CACHE
CREATE SEQUENCE strict_seq NO CACHE;
```

CockroachDB 的实现：

```
SEQUENCE 在 CockroachDB 中是一个全局对象，但 cache 是 per node：
  - 节点 A 的 backend 请求 nextval(seq)
  - 节点 A 检查本地 cache：
    - 若有：直接分配
    - 若无：发 KV 操作 INC seq_descriptor.last_value BY cache_size
      （这是一个 raft consensus 操作，需要写到 quorum）
    - 收到结果后，缓存到节点 A 本地 [start, start+cache-1]
  - 后续 nextval 在 cache 范围内是纯内存

性能代价：
  CACHE 1：每次 nextval 都触发一次 raft consensus（数 ms 延迟）
  CACHE 100：每 100 次 nextval 才一次 raft（吞吐高 100 倍）

间隙：
  节点 A 崩溃 → 节点 A 上 cache 中的剩余值丢失
  分布式集群中，间隙范围 = CACHE × 节点数
```

CockroachDB 文档明确警告：分布式环境下 SEQUENCE 是"反模式"，推荐使用 `unique_rowid()`（基于时间戳+节点 ID 的无锁分配）作为主键。

### YugabyteDB：CACHE 默认从 1 升到 100

YugabyteDB 是基于 PostgreSQL 协议的分布式 SQL，早期完全继承 PG 的 `CACHE 1` 默认值，导致每次 nextval 都触发跨节点 raft 操作，性能极差：

```sql
-- YB 2.13（2022 年）之前：CACHE 1
CREATE SEQUENCE order_seq;
-- 实测吞吐：< 100 ops/s（跨节点 raft 主导）

-- YB 2.13+ 默认 CACHE 100
CREATE SEQUENCE order_seq;
-- 实测吞吐：~10K ops/s

-- 显式高 CACHE
CREATE SEQUENCE high_seq CACHE 1000;
-- 实测吞吐：~50K ops/s

-- 全局参数也可调整默认值
SET ysql_sequence_cache_minval = 100;
```

YugabyteDB 在 2.13（2022-04）发布说明中明确解释：

> "We have changed the default cache size from 1 to 100 to dramatically improve sequence performance in distributed deployments. Users requiring strict consistency can still set CACHE 1 explicitly."

这是分布式数据库继承单机数据库默认值时常见的问题——单机引擎里 `CACHE 1` 的代价是 1 次 fsync（~1ms），分布式引擎里是 1 次 raft（~10ms），后者必须用更大 cache 才能达到可用性能。

### Snowflake：自动管理的"黑盒"

Snowflake 的 SEQUENCE 完全不暴露 CACHE 参数：

```sql
CREATE SEQUENCE order_seq START 1 INCREMENT 1;
-- 没有 CACHE 子句的概念
SELECT order_seq.nextval;

-- ORDER / NOORDER 子句存在但语义不同（用于 IDENTITY 列）
CREATE TABLE orders (id INT AUTOINCREMENT START 1 INCREMENT 1 ORDER);
-- ORDER：保证严格递增（性能更低）
-- NOORDER（默认）：仅保证唯一，可能不连续不递增
```

Snowflake 文档明确说明 SEQUENCE 不保证：

- 连续（不保证 1, 2, 3, ...）
- 严格递增（不同 micro-partition 可能交错）
- 集群一致（warehouse 重启可能产生跳跃）

仅保证：

- 全局唯一（在该 SEQUENCE 内）
- 在事务中分配的值不重复

Snowflake 内部如何实现 cache 是一个"服务化"细节——sequence service 是独立微服务，每个 warehouse 通过 RPC 请求批量值。这种设计的优势是 cache 大小随负载自适应，不需要 DBA 调优。

### TiDB：SEQUENCE CACHE 1000 + AUTO_INCREMENT CACHE 30000

TiDB 同时支持两种 ID 生成机制，CACHE 默认值不同：

```sql
-- TiDB SEQUENCE（6.4+ 完善）
CREATE SEQUENCE order_seq CACHE 1000;
-- 默认 CACHE 1000
-- 每个 tidb-server 独立 cache

-- TiDB AUTO_INCREMENT（兼容 MySQL）
CREATE TABLE orders (id BIGINT AUTO_INCREMENT PRIMARY KEY);
-- 默认每个 tidb-server cache 30000 个 ID
-- 可通过 AUTO_ID_CACHE 选项调整：
CREATE TABLE orders2 (
    id BIGINT AUTO_INCREMENT PRIMARY KEY
) AUTO_ID_CACHE 100;

-- AUTO_RANDOM（推荐分布式主键）
CREATE TABLE orders3 (id BIGINT AUTO_RANDOM PRIMARY KEY);
-- 不存在 cache 概念，每次随机生成
```

TiDB 的设计逻辑：

```
SEQUENCE CACHE 1000 的考量：
  - 每个 tidb-server 一次取 1000 个值
  - 写入 PD（Placement Driver）的元数据
  - tidb-server 崩溃 → 999 个值丢失
  - 间隙最大值 = 1000 × tidb_server_count

AUTO_INCREMENT CACHE 30000 的考量：
  - 默认值更激进，因为 AUTO_INCREMENT 通常用于纯代理键
  - tidb-server 崩溃 → 29999 个值丢失
  - 但 30000 的间隙在 BIGINT 空间下完全无伤
  - 性能：与单机 MySQL 接近

为什么默认 cache 这么大？
  - PD 通信延迟约 5-10ms
  - cache=1 → 5K ops/s（PD 通信主导）
  - cache=30000 → 100K+ ops/s
```

TiDB 文档建议：业务对 ID 顺序敏感（如对账场景）时使用 `AUTO_ID_CACHE 1`，否则保留默认。

### Vertica：CACHE 默认 250000 的极端选择

Vertica 是默认 CACHE 最大的数据库之一：

```sql
CREATE SEQUENCE order_seq;
-- 默认 CACHE 250000
-- 每个节点一次取 250000 个值

CREATE SEQUENCE high_seq CACHE 1000000;
-- 显式更大

CREATE SEQUENCE low_seq CACHE 1;
-- 关闭 cache，每次都写 catalog
```

Vertica 的设计思路：

```
作为列式 MPP 分析数据库：
  - 主要场景是 ETL 批量插入
  - 单次 ETL 可能插入百万行
  - 250000 cache 几乎能覆盖整个 ETL 不触发 catalog 写
  - 节点崩溃间隙 250000 在百亿级 BIGINT 空间下完全无关

崩溃间隙最大值 = 250000 × 节点数
  10 节点集群 → 250 万间隙
  这在分析场景完全可接受
```

Vertica 的极端默认值是"知道用户场景后的最优解"——分析数据库的 SEQUENCE 几乎只用于代理键，性能优先无需保留。

### MariaDB / MySQL 对比：SEQUENCE 引擎与 AUTO_INCREMENT

MySQL 至今（9.0）不支持 `CREATE SEQUENCE`，唯一的自增机制是 `AUTO_INCREMENT`。其 cache 机制由 `innodb_autoinc_lock_mode` 间接控制：

```sql
-- MySQL/MariaDB AUTO_INCREMENT
CREATE TABLE orders (id BIGINT AUTO_INCREMENT PRIMARY KEY);

-- innodb_autoinc_lock_mode 不是真正的 cache 大小，但影响分配粒度
-- mode 0：每次都加表锁（无 cache，最严格连续）
-- mode 1：单行 INSERT 立即释放，批量 INSERT 持锁到结束
-- mode 2：完全 mutex 内分配（最高吞吐，可能交错）
```

MariaDB 10.3 的 SEQUENCE 引擎与 AUTO_INCREMENT 是两套独立机制，cache 行为不同：

```
MariaDB AUTO_INCREMENT：
  - 由 innodb_autoinc_lock_mode 控制
  - 默认 mode 1
  - 计数器存储在 InnoDB data dictionary
  - MySQL 8.0 起持久化到 redo log，崩溃后不回退

MariaDB SEQUENCE 引擎：
  - 独立存储引擎（CREATE TABLE ... ENGINE=SEQUENCE）
  - 默认 CACHE 1000
  - 行为类似 PostgreSQL（per session cache）

业务推荐：
  - 单表代理键：AUTO_INCREMENT
  - 跨表共享序号：SEQUENCE 引擎
  - 严格无间隙：应用层计数器表
```

### SAP HANA / Exasol / Greenplum / H2 简要对比

```sql
-- SAP HANA（默认 CACHE 1，indexserver 共享）
CREATE SEQUENCE my_seq START WITH 1 INCREMENT BY 1 CACHE 100;
SELECT my_seq.NEXTVAL FROM DUMMY;

-- Exasol（默认 CACHE 1000，节点本地）
CREATE SEQUENCE my_seq START WITH 1 INCREMENT BY 1 CACHE 1000;
SELECT NEXTVAL(my_seq);

-- Greenplum（默认 CACHE 1，per session，继承 PG）
CREATE SEQUENCE my_seq;
SELECT nextval('my_seq');
-- segment 间不共享 cache，每个 segment 各自缓存

-- H2（默认 CACHE 32，per session）
CREATE SEQUENCE my_seq CACHE 100;
SELECT NEXT VALUE FOR my_seq;
-- H2 早期版本就支持 CACHE，是 Java 内嵌库的小亮点
```

H2 是少数明确文档化默认 CACHE（32）的引擎之一，符合"内存数据库不需要太大 cache"的设计哲学——单 fsync 在嵌入式场景代价很小。

### 不支持 SEQUENCE 的引擎清单

```
完全不支持 CREATE SEQUENCE 语法：
  MySQL（8.0/9.0 仍不支持）
  SQLite（rowid 内部计数）
  BigQuery（推荐 GENERATE_UUID）
  ClickHouse（推荐 UInt64 时间戳）
  Hive / Impala / Spark SQL / MaxCompute（批处理引擎）
  Trino / Presto / Athena（无写入引擎，外部生成）
  StarRocks / Doris（替代方案在路线图）
  CrateDB（推荐 gen_random_text_uuid）
  Materialize / RisingWave（部分支持，流处理特殊）
  InfluxDB / QuestDB（时序无 SEQUENCE 概念）
  Firebolt（不支持）
```

这些引擎共同的特点：要么是分析/批处理引擎（不需要在线分配 ID），要么是流处理/时序引擎（自然有时间维度），要么是设计上拒绝全局序列（如 BigQuery 的设计哲学是"分布式系统不应依赖全局协调"）。

## Oracle RAC ORDER 深度剖析

Oracle 的 `ORDER` 子句在 RAC 上的代价值得专门一节，因为这是 SEQUENCE 在分布式语境下最经典的"性能悬崖"。

### NOORDER 在 RAC 上的行为

```sql
CREATE SEQUENCE rac_seq CACHE 1000 NOORDER;
```

每个 RAC 实例独立缓存：

```
T0：Instance 1 请求 cache → SYS.SEQ$ 给 [1, 1000]
T1：Instance 2 请求 cache → SYS.SEQ$ 给 [1001, 2000]
T2：Instance 1 nextval → 1
T3：Instance 2 nextval → 1001
T4：Instance 1 nextval → 2
T5：Instance 2 nextval → 1002
```

外界看到的 INSERT 顺序：1, 1001, 2, 1002, 3, 1003... **完全不递增**。但每个实例内部 `1, 2, 3, ...` 递增，吞吐极高（每实例 100K+ ops/s）。

### ORDER 在 RAC 上的行为

```sql
CREATE SEQUENCE rac_seq CACHE 100 ORDER;
```

每次 nextval 都需要全局协调：

```
T0：Instance 1 nextval
  → 通过 GES (Global Enqueue Service) 获取 sequence enqueue
  → 该 enqueue 是全局唯一的，跨节点序列化
  → 取得 1，释放 enqueue
T1：Instance 2 nextval
  → 请求同一个 GES enqueue
  → 等待 Instance 1 释放
  → 跨网络往返：5-50 微秒
  → 取得 2
T2：Instance 1 nextval
  → 再次请求 enqueue
  → 等待 Instance 2 释放
  → ...
```

每次跨节点 GES 协调成本是单实例 latch 的 100-1000 倍。在 OLTP 系统上，单 RAC 序列的 ORDER 可能限制整个集群吞吐到 < 1K ops/s——这是为什么 Oracle DBA 圈广泛流传"never use ORDER on RAC"的原因。

### 何时真的需要 ORDER

```
合法场景：
  1. 时间戳模拟：SCN-style ordering，但应该用 SCN 而非 SEQUENCE
  2. 财务对账：业务订单号需严格递增
  3. 业务规则：最小化对账复杂度

实际上的"伪需求"：
  - "我们的报表需要严格递增 ID"
    → 报表用 ORDER BY id 即可，不需要 ORDER 序列
  - "用户希望看到连续的订单号"
    → 这与"递增"是两个问题，单实例 NOORDER 在每实例内仍递增
  - "审计需要"
    → 审计应该看 commit_time 而非 id

真正需要 ORDER 的场景：分布式锁、跨节点事件总顺序、log 序号
但这些场景的最优实现通常不是 SEQUENCE，而是 SCN 或时钟同步（TrueTime）
```

Oracle 19c 引入的 `SCALABLE` 序列（CREATE SEQUENCE ... SCALE EXTEND）是 ORDER 的反向方案——通过给 ID 加上"实例号 × 10^N"前缀，保证跨实例不冲突且单实例内递增，但放弃了全局递增。

## PostgreSQL CACHE 跨 backend 行为详解

PostgreSQL 的 `CACHE` 是 per backend 的特性，常常导致用户对"实际间隙范围"误判。

### Per backend cache 的实测

```sql
CREATE SEQUENCE test_seq CACHE 100;

-- Session 1
SELECT nextval('test_seq');  -- 1
-- 这一次调用让 Session 1 的 backend 缓存了 [1, 100]
SELECT nextval('test_seq');  -- 2
-- 缓存范围内，纯内存

-- Session 2（不同连接）
SELECT nextval('test_seq');  -- 101
-- Session 2 的 backend 取 [101, 200]
-- 不是 3！

-- Session 1 关闭
-- 内存中剩余的 3-100 全部丢失

-- Session 1 重新连接
SELECT nextval('test_seq');  -- 201
-- 新 backend 取 [201, 300]
-- 与之前 Session 1 的 cache 没有任何关系
```

实际间隙的累积公式：

```
PostgreSQL SEQUENCE 的间隙最大值 ≈ CACHE × 历史 backend 数

例：
  CACHE 100，长期运行
  连接池配置 max_connections = 200
  长期运行后，可能产生间隙最多 100 × 200 = 20000

实际开发中：
  使用连接池（如 PgBouncer transaction mode）
  会显著增加 backend 的"翻新"频率
  间隙累积更快
```

### PostgreSQL 的 CACHE 1 性能特性

如前文所述，PostgreSQL 即使 `CACHE 1` 也有 SEQ_LOG_VALS=32 的隐式 batch：

```c
// src/include/access/xlog_internal.h（节选）
#define SEQ_LOG_VALS 32

// nextval_internal 的伪码
nextval_internal(seq_oid):
    cache_state = get_session_cache(seq_oid)
    if cache_state.has_value():
        return cache_state.next()

    // cache 用尽或不存在，需要持久化新值
    LockBuffer(seq_buffer, BUFFER_LOCK_EXCLUSIVE)
    last_value = read_from_page()
    new_last = last_value + max(CACHE, 1)
    if log_threshold_crossed():  // 每 SEQ_LOG_VALS 次写一次 WAL
        XLogBeginInsert()
        // log new_last + log_cnt
        XLogInsert()
    write_to_page(new_last)
    UnlockBuffer(seq_buffer)

    cache_state.set_range(last_value+1, new_last)
    return cache_state.next()
```

崩溃恢复时：

```
WAL 中最后的 sequence 记录：value=64, log_cnt=32
  含义：已经持久化到 64，但下一段从 96 开始算
  也就是 64 之后的 32 个值（65-96）已经"算过"

崩溃后：
  从 WAL 恢复，next start = 96
  即使用户视角的 cache 是 1，崩溃也丢了 32 个值（65-96）
```

这是为什么有人在 PG 论坛抱怨 `CACHE 1 也有大间隙`。原因不在 CACHE，而在 SEQ_LOG_VALS 这个内部常量。

## 崩溃间隙：实战分析

让我们通过几个真实案例理解不同引擎的崩溃间隙。

### 案例 1：电商订单系统从 Oracle 迁移到 PostgreSQL

```
原 Oracle 系统：
  CREATE SEQUENCE order_seq CACHE 1000
  单实例，每天 1000 万订单
  每月平均崩溃 1 次（计划维护）
  实际间隙：每月 ~1000 个号
  业务接受度：高（订单号本来就不要求连续）

迁移到 PostgreSQL（直接 CACHE 1000）：
  连接池 PgBouncer，配置 200 个 backend
  每个 backend cache 1000
  正常运行：吞吐与 Oracle 接近
  PG 重启：所有 backend 同时关闭 → 间隙最多 200 × 1000 = 200000

业务不可接受！
  解决方案：
  1. 改 CACHE 100（间隙降到 200 × 100 = 20000，仍较大）
  2. 改 CACHE 10（吞吐下降，但间隙 < 2000）
  3. 接受 PG 的 per backend cache 行为，业务调整对 ID 间隙的预期
```

### 案例 2：SQL Server IDENTITY 的"消失的 1000 单"

```
某零售系统：
  CREATE TABLE orders (id INT IDENTITY, ...)
  正常运行 6 个月，订单号连续 1 ~ 1500000
  服务器异常重启
  重启后下一个订单号变成 1500999（不是 1500001！）

业务报表突然出现 998 个空白订单号，引发审计质疑。

调查：
  SQL Server IDENTITY 默认 cache 1000
  内部预分配到 1500000 后已经预取到 1501000
  但只 INSERT 到 1500000
  崩溃 → cache 丢失 → 下次从 1501000 + 1 = 1501001 开始
  
（实际上是 1501000 而不是 1500999，但业务系统已经 panic）

修复：
  方案 A：DBCC TRACEON(272, -1)，重启后所有 IDENTITY 退化为传统行为
  方案 B：改用 SEQUENCE NO CACHE
  方案 C：业务接受间隙，文档化此行为
```

### 案例 3：YugabyteDB 升级 2.13 后的吞吐跳跃

```
某金融服务团队：
  YB 2.10，CACHE 默认 1
  生产监控显示 SEQUENCE nextval 占用 30% CPU
  实际吞吐：~500 ops/s

升级到 YB 2.13（默认 CACHE 100）：
  无任何代码改动，吞吐：~30K ops/s（提升 60 倍）
  CPU 占用：~5%
  代价：崩溃间隙从 ~10 增加到 ~1000
  
团队的额外评估：
  审计要求 ID 仅需"在事务内唯一"和"全局递增"
  不要求"连续"
  → 接受 CACHE 100 的默认值
```

### 间隙容忍策略矩阵

| 业务场景 | 推荐 CACHE | 崩溃间隙容忍 | 备注 |
|---------|-----------|------------|------|
| 严格连续编号（发票/对账） | 不用 SEQUENCE | 0 | 用应用层计数器表 |
| 一般业务 ID（订单/用户） | 100-1000 | 1K-10K | 业务接受小间隙 |
| 代理键（仅内部用） | 10000+ | 100K+ | 完全不在乎间隙 |
| 高并发分析数据 | 100000+ | 1M+ | 性能优先 |
| 分布式数据库（CockroachDB/TiDB） | 100-10000 | 跨节点累积 | 注意 cache × 节点数 |
| RAC（Oracle）+ 严格递增 | 用 ORDER（性能代价大） | 0 | 不推荐，用 SCALABLE 替代 |

## 关键发现

### 1. CACHE 默认值跨越六个数量级

| 区间 | 引擎 |
|------|------|
| 默认 1 | PostgreSQL, Greenplum, SAP HANA, HSQLDB, Derby, Firebird, Informix, CockroachDB, Yellowbrick |
| 默认 20 | Oracle, DB2, OceanBase Oracle |
| 默认 32 | H2 |
| 默认 50（实现定义） | SQL Server |
| 默认 100 | YugabyteDB（2.13+），GaussDB |
| 默认 1000 | MariaDB SEQUENCE, TiDB SEQUENCE, Exasol, OceanBase MySQL |
| 默认 30000 | TiDB AUTO_INCREMENT |
| 默认 250000 | Vertica |

这种六个数量级的差异，反映的不是技术的"对错"，而是各引擎设计者对"目标场景"的预设：单机 OLTP（Oracle）vs 嵌入式（H2）vs 分析 MPP（Vertica）vs 分布式（TiDB）。**没有"正确"的默认 CACHE 值**，只有"匹配场景"的选择。

### 2. NOCACHE 不等于零间隙

事务回滚、INSERT 失败、崩溃恢复的最后段落都会产生间隙，与 CACHE 无关。如果业务真的要求"严格连续编号"（发票号、合同号），**任何 SEQUENCE 都不合适**——必须用应用层 `SELECT FOR UPDATE` 计数器表，接受性能代价。

### 3. 缓存粒度比 CACHE 大小更重要

PostgreSQL 的 `CACHE 100 + 200 backends` 在崩溃时可能产生 20000 间隙，远大于 Oracle `CACHE 1000` 单实例的 1000 间隙。理解"per session vs per instance vs per node"的差异，比纠结具体 CACHE 数字更关键。

### 4. ORDER 在 RAC/分布式上是性能悬崖

Oracle ORDER + RAC、DB2 ORDER + pureScale、强制全局递增的需求会让吞吐降到 1K ops/s 量级，比 NOORDER 慢 1-2 个数量级。**99% 的"必须严格递增"需求，实际上是"必须唯一"+"基本有序"的混淆**。能容忍 NOORDER 就坚决不要 ORDER。

### 5. 分布式数据库的 CACHE 必须更大

单机数据库的 `CACHE 1` 代价是 1 次 fsync（~1ms），分布式数据库的 `CACHE 1` 代价是 1 次 raft（~10ms）。YugabyteDB 把默认从 1 改成 100、TiDB 把 AUTO_INCREMENT 默认 cache 设为 30000，本质都是承认这个差异。任何兼容 PG 的分布式数据库都应该重新评估默认 CACHE 值。

### 6. SQL Server IDENTITY 是隐式 cache 的反面教材

为追求性能而引入用户不可见的 1000/10000 cache，结果在数据库领域引发长达十年的"消失的订单号"故事。**任何隐式 cache 都应该可关闭、可观测、可文档化**——这是 SQL Server 2012 给所有引擎设计者的教训。

### 7. 标准缺位是各引擎差异的根源

SQL:2003 定义了 `CREATE SEQUENCE` 语法但完全回避 CACHE 行为。这是历史遗产——1990s 的 SQL 委员会想避开 Oracle 专利，又想给各厂商留实现自由。结果是同样写 `CACHE 100`，PG 是 per session 100，Oracle 是 per instance 100，TiDB 是 per tidb-server 100，含义截然不同。**做跨引擎迁移时，CACHE 子句的语义需要人工逐字段验证**。

### 8. 默认值变更需要版本警示

YugabyteDB 2.13 把默认 CACHE 从 1 改到 100，是一个反向案例——升级后行为变了，对依赖 ID 严格递增的应用来说是 breaking change。任何引擎修改默认 CACHE 都应在 release notes 显著标注。

## 对引擎开发者的建议

### 1. 缓存粒度的设计选择

```
单进程引擎（H2/SQLite/DuckDB）：
  → 全局 cache 即可（无 session 概念）
  → 默认 CACHE 32-100 平衡性能与间隙

单实例多连接引擎（Oracle/SQL Server/DB2）：
  → instance 级 cache（shared pool）
  → 默认 CACHE 20-50 较保守
  → 显式 CACHE 1000+ 留给高吞吐场景

每连接 cache 引擎（PostgreSQL/Greenplum/H2）：
  → 文档明确 per backend 语义
  → 提示用户连接池场景的间隙累积

分布式引擎（CockroachDB/TiDB/YugabyteDB）：
  → 必须比单机引擎默认 cache 大 10-100 倍
  → raft/paxos 协调代价远大于 fsync
  → 显式 CACHE 1 应该警告用户"性能极差"
```

### 2. 崩溃恢复的实现要点

```
WAL/redo log 的 batch 写入：
  - 不要每次 cache 用尽都写日志（开销过大）
  - 也不要拖到 CACHE 全用完才写（崩溃间隙过大）
  - 折中：每 cache_size / 2 写一次（崩溃间隙 ~cache_size/2）

PostgreSQL 的 SEQ_LOG_VALS=32 是经典实现：
  - 即使 CACHE 1，也每 32 次才写 WAL
  - 用户感知的 cache 与物理 batch 解耦

崩溃恢复流程：
  - 从最新 WAL 记录读取 next_value
  - 内存 cache 全部失效
  - 第一次 nextval 重新分配新 cache 段
```

### 3. 监控指标暴露

```
建议引擎暴露的 SEQUENCE 监控指标：
  - sequence.cache_hits（cache 内分配次数）
  - sequence.cache_misses（cache 用尽次数）
  - sequence.cache_refills_total（持久化次数）
  - sequence.fsync_duration（写入延迟）
  - sequence.gap_estimated_total（估计间隙累积）

这些指标对 DBA 调优 CACHE 大小至关重要：
  - cache_misses 高 → 增大 CACHE
  - gap_estimated 大 → 业务侧确认是否可接受
  - fsync_duration 长 → 检查存储性能
```

### 4. 默认值的设计原则

```
默认 CACHE 应该满足：
  - 单连接场景：100 ms 内不应触发 cache miss
    例：单连接 1000 ops/s 的吞吐 → CACHE 100 满足要求
  - 高并发场景：吞吐瓶颈不在 sequence
    例：100 个连接 10000 ops/s → CACHE 1000 满足要求
  - 崩溃间隙：< 0.1% 的"业务时长 × 平均吞吐"
    例：每天 1M ops 业务 → 间隙 < 1000 即可

实践推荐：
  单机 OLTP：100-500
  单机 OLAP：10000-100000
  分布式 OLTP：1000-10000
  分布式 OLAP：100000+
```

### 5. 跨引擎迁移的检查清单

```
迁移 SEQUENCE 时必须验证：
  [ ] 默认 CACHE 大小是否相同
  [ ] CACHE 粒度（session vs instance vs cluster）
  [ ] NOCACHE 子句的行为
  [ ] ORDER 子句是否存在
  [ ] 崩溃时缓存值的归宿
  [ ] 事务回滚是否归还序号（几乎所有引擎都不归还）
  [ ] 跨节点协调代价（分布式特有）
  [ ] 业务对间隙的真实容忍度
```

### 6. 反模式警示

```
绝对反模式：
  - 用 NOCACHE 期望"无间隙"（事务回滚仍产生间隙）
  - 在 RAC 上启用 ORDER 期望性能（吞吐降 100×）
  - 在分布式数据库继承单机的 CACHE 1 默认（吞吐悬崖）
  - 把 SQL Server IDENTITY 的 1000 间隙当 bug 上报（这是设计）
  
推荐策略：
  - 业务必须连续编号 → 应用层计数器表（不用 SEQUENCE）
  - 业务接受小间隙 → 默认 CACHE 100-1000
  - 业务完全不在乎 → 大 CACHE（10000+）
  - 分布式 + 高吞吐 → 评估 raft 代价，cache 取大
```

## 横向总结：CACHE 调优决策树

```
开始：你需要 SEQUENCE 吗？
  │
  ├─ 业务需要"严格连续编号"（发票/合同）？
  │   └─ 是 → 不要用 SEQUENCE，用应用层计数器表
  │
  ├─ 业务能接受 ID 间隙吗？
  │   ├─ 否 → 重新评估业务需求（多数"不能"是"未确认"）
  │   └─ 是 → 继续
  │
  ├─ 单机引擎吗？
  │   ├─ 是
  │   │   ├─ 高并发 OLTP → CACHE 100-1000
  │   │   ├─ 一般 OLTP → CACHE 20-100（默认即可）
  │   │   └─ 分析/批处理 → CACHE 10000+
  │   └─ 否（分布式）
  │       ├─ 网络延迟 < 1ms → CACHE 100-1000
  │       ├─ 网络延迟 1-10ms → CACHE 1000-10000
  │       └─ 网络延迟 > 10ms → CACHE 10000+
  │
  ├─ 多实例/集群（RAC/pureScale）？
  │   ├─ 业务真的需要全局严格递增？
  │   │   ├─ 是 → ORDER（接受性能损失）+ 监控
  │   │   └─ 否 → NOORDER（强烈推荐）+ 大 CACHE
  │   └─ 评估每节点 CACHE 大小，注意累积间隙
  │
  └─ 监控
      ├─ cache_misses 高 → 增大 CACHE
      ├─ 崩溃间隙大于业务容忍 → 减小 CACHE
      └─ 性能瓶颈在 SEQUENCE → 评估是否需要 SEQUENCE 还是 UUID/snowflake
```

## 参考资料

- ISO/IEC 9075-2:2003 Section 11.3 — `<sequence generator definition>`（仅语法，无 CACHE 行为）
- Oracle: [CREATE SEQUENCE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-SEQUENCE.html) / [Performance Tuning Sequences in RAC](https://docs.oracle.com/en/database/oracle/oracle-database/19/racad/configuring-recovery-manager-and-archiving.html)
- PostgreSQL: [CREATE SEQUENCE](https://www.postgresql.org/docs/current/sql-createsequence.html) / `src/backend/commands/sequence.c`（SEQ_LOG_VALS 常量）
- SQL Server: [Sequence Numbers](https://learn.microsoft.com/en-us/sql/relational-databases/sequence-numbers/sequence-numbers) / [KB 2790921: IDENTITY Cache Behavior](https://learn.microsoft.com/en-us/troubleshoot/sql/sql-server/identity-value-jumps)
- DB2: [CREATE SEQUENCE Statement](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-sequence)
- MariaDB: [SEQUENCE Engine](https://mariadb.com/kb/en/create-sequence/)（10.3+）
- TiDB: [SEQUENCE](https://docs.pingcap.com/tidb/stable/sql-statement-create-sequence) / [AUTO_INCREMENT](https://docs.pingcap.com/tidb/stable/auto-increment)
- CockroachDB: [CREATE SEQUENCE](https://www.cockroachlabs.com/docs/stable/create-sequence.html)
- YugabyteDB 2.13 Release Notes: 默认 CACHE 从 1 改为 100
- Snowflake: [Sequences](https://docs.snowflake.com/en/sql-reference/sql/create-sequence)
- Vertica: [CREATE SEQUENCE](https://docs.vertica.com/latest/en/sql-reference/statements/create-statements/create-sequence/)
- Tahbouchi & Le Maistre: "Sequence-Based Identifiers in Distributed Databases", VLDB 2018（分布式序列协调代价分析）
- Bernstein, P. & Newcomer, E.: "Principles of Transaction Processing" (2009), Chapter 5 — Generators and Sequences
