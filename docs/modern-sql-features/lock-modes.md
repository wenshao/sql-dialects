# 锁模式 (Lock Modes)

锁不是一个二元开关——某行数据可以同时被多个事务"以不同方式"持有，关键在于这些"持有方式"之间是否兼容。从 1976 年 IBM Jim Gray 在《Granularity of Locks and Degrees of Consistency in a Shared Database》中正式定义 S/X/U/IS/IX/SIX 六大基础锁模式以来，这套数学化的兼容性矩阵几乎成了所有 OLTP 数据库的并发控制基石。但 50 年过去，每个引擎都在这个基础上做了独有扩展：SQL Server 加了 Range 锁支持 SERIALIZABLE，Oracle 用 ITL 槽位实现"无升级行锁"，MySQL InnoDB 引入 Gap Lock 与 Next-Key Lock 解决 REPEATABLE READ 下的幻读，PostgreSQL 把 8 种表锁与 4 种行锁解耦。

本文系统对比 45+ 主流数据库的锁模式实现：基础的 S/X/U 锁、意向锁的 IS/IX/SIX 三角、键范围锁的复杂家族、SCHEMA-S/SCHEMA-M 元数据锁，以及 PostgreSQL 与 Oracle 提供的咨询锁。理解这些锁模式之间的兼容性矩阵，是看懂数据库阻塞监控、调优锁等待、设计低冲突应用的前提。

## SQL 标准与历史源头

### 没有 SQL 标准

SQL:2016（ISO/IEC 9075）以及之前的所有 SQL 标准**从未定义锁模式**。原因与元数据锁相同：标准只规定可观察的语义（隔离级别、事务行为），不规定实现。这意味着：

1. SQL 标准只规定 4 个隔离级别（READ UNCOMMITTED / READ COMMITTED / REPEATABLE READ / SERIALIZABLE）的可观察语义
2. 标准从不要求"必须用 S 锁"或"必须用 X 锁"——任何实现只要满足隔离级别即可
3. MVCC 引擎（PostgreSQL、Oracle）和锁基引擎（SQL Server 默认配置、MySQL InnoDB）实现完全不同的锁模式集合

因此各家数据库的锁模式集合差异巨大，从 SQLite 的 5 个文件级状态，到 SQL Server 的 20+ 种锁模式（含 Range 锁），跨度超过一个数量级。

### 1976 年 Gray 的奠基论文

锁模式的理论基础来自 Jim Gray 1975 年在 IBM 的内部论文 [Granularity of Locks in a Shared Database](https://dl.acm.org/doi/10.1145/1097569.1097583)（VLDB 1975），1976 年发表在 *Modeling in Data Base Management Systems* 论文集中（与 Lorie、Putzolu、Traiger 合著）。这篇论文首次系统提出：

1. **S/X 二元锁的局限**：多粒度锁（行/页/表）需要更精细的协调
2. **意向锁的发明**：IS（意向共享）和 IX（意向排他）作为高粒度对象上的"占位声明"
3. **U 锁的需求**：解决"读后改写"场景下 S→X 升级造成的死锁
4. **SIX（Shared with Intent eXclusive）**：完整 6 种基础锁模式
5. **兼容性矩阵**：定义哪些锁模式之间可以并存

50 年后，这套设计仍然是 SQL Server、DB2、Sybase、Informix、SAP HANA 等所有 IBM 谱系数据库的核心。

## 锁模式分类总览

### 基础锁模式（Gray 模型）

| 缩写 | 全称 | 用途 | 兼容性 |
|------|------|------|--------|
| S | Shared (共享锁) | 读取保护 | 与 S/IS 兼容，与 X/IX/U 冲突 |
| X | Exclusive (排他锁) | 写入保护 | 与一切冲突 |
| U | Update (更新锁) | "我打算改"声明 | 与 S 兼容（早期），自身不兼容 |
| IS | Intention Shared (意向共享) | 高粒度上的 S 占位 | 与 IS/IX/S 兼容 |
| IX | Intention Exclusive (意向排他) | 高粒度上的 X 占位 | 与 IS/IX 兼容 |
| SIX | Shared with Intent Exclusive | "读全表，改少量行" | 与 IS 兼容 |
| IU | Intention Update | U 锁的高粒度占位 | SQL Server 扩展 |
| SIU | Shared with Intent Update | S + IU | SQL Server 扩展 |
| UIX | Update Intention Exclusive | U + IX | SQL Server 扩展 |

### 键范围锁（Key-Range Locks）

| 缩写 | 全称 | 用途 |
|------|------|------|
| KS | Key Range Shared | 索引区间共享 |
| KU | Key Range Update | 索引区间更新 |
| KX | Key Range Exclusive | 索引区间排他 |
| RangeS-S | Range Shared, Resource Shared | SQL Server SERIALIZABLE 范围扫描 |
| RangeS-U | Range Shared, Resource Update | SQL Server SERIALIZABLE 更新意图 |
| RangeI-N | Range Insert, Resource None | SQL Server 防止区间内插入 |
| RangeX-X | Range Exclusive, Resource Exclusive | SQL Server SERIALIZABLE 删除范围 |

### MySQL InnoDB 间隙锁系列

| 缩写 | 名称 | 用途 |
|------|------|------|
| Record Lock | 记录锁 | 仅锁索引记录本身 |
| Gap Lock | 间隙锁 | 锁定索引记录之间的间隙 |
| Next-Key Lock | 下一键锁 | Record + Gap 组合锁 |
| Insert Intention Lock | 插入意向锁 | 等待间隙的 INSERT 之间互相兼容 |

### Schema 锁

| 缩写 | 全称 | 用途 |
|------|------|------|
| Sch-S | Schema Stability | 编译时结构稳定锁（SQL Server） |
| Sch-M | Schema Modification | DDL 修改锁（SQL Server） |
| MDL_SHARED | MySQL 元数据共享 | DML 持有 |
| MDL_EXCLUSIVE | MySQL 元数据排他 | DDL 持有 |

### 咨询锁（Advisory Lock）

| 类型 | 引擎 | 键空间 |
|------|------|--------|
| pg_advisory_lock | PostgreSQL | bigint 或 (int,int) |
| GET_LOCK | MySQL/MariaDB | 字符串 |
| sp_getapplock | SQL Server | 字符串 |
| DBMS_LOCK.REQUEST | Oracle | 用户分配 ID |

## 支持矩阵

### 基础锁模式支持（45+ 引擎）

| 引擎 | S | X | U | IS | IX | SIX | IU | 键范围 | 咨询锁 |
|------|---|---|---|----|----|-----|----|--------|--------|
| PostgreSQL | 表级 8 种 | 表级 8 种 | -- | RowShare | RowExclusive | -- | -- | -- (Predicate Locks for SSI) | 是 (bigint) |
| MySQL InnoDB | 是 | 是 | -- | 是 | 是 | -- | -- | Gap/Next-Key/Insert Intention | 是 (string) |
| MariaDB (InnoDB) | 是 | 是 | -- | 是 | 是 | -- | -- | 同 InnoDB | 是 |
| MariaDB (Aria) | 表级 | 表级 | -- | -- | -- | -- | -- | -- | 是 |
| SQLite | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Oracle | RS | RX/X | -- | -- (合并到 RX) | -- (合并到 RX) | SRX | -- | -- (predicate via SCN) | DBMS_LOCK |
| SQL Server | 是 | 是 | 是 | 是 | 是 | 是 | 是 (IU) | KS/KU/KX/RangeS-S/RangeS-U/RangeI-N/RangeX-X | sp_getapplock |
| DB2 LUW | 是 | 是 | 是 | 是 | 是 | 是 | -- | NS/NX/W (NextKey) | -- |
| DB2 z/OS | 是 | 是 | 是 (U) | 是 | 是 | 是 | -- | -- | -- |
| Snowflake | -- | 表级 | -- | -- | -- | -- | -- | -- | -- |
| BigQuery | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Redshift | 是 (PG 衍生) | 是 | -- | -- | -- | -- | -- | -- | -- |
| DuckDB | -- | 表级 | -- | -- | -- | -- | -- | -- | -- |
| ClickHouse | -- | 部分元数据 | -- | -- | -- | -- | -- | -- | -- |
| Trino | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Presto | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Spark SQL | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Hive | 是 (ACID) | 是 | -- | 是 | 是 | -- | -- | -- | ZooKeeper |
| Flink SQL | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Databricks | -- | 表级 (Delta) | -- | -- | -- | -- | -- | -- | -- |
| Teradata | Read | Write/Excl | -- | Access | Access | -- | -- | -- | -- |
| Greenplum | 同 PG | 同 PG | -- | RowShare | RowExclusive | -- | -- | -- | 是 |
| CockroachDB | 是 (intent) | 是 | -- | -- | -- | -- | -- | -- (SSI predicate) | -- |
| TiDB | 是 (悲观) | 是 | -- | -- | -- | -- | -- | -- | -- |
| OceanBase | 是 | 是 | -- | 是 | 是 | -- | -- | Gap (兼容 MySQL) | -- |
| YugabyteDB | 是 | 是 | -- | 是 | 是 | -- | -- | -- | -- |
| SingleStore | 是 | 是 | -- | -- | -- | -- | -- | -- | -- |
| Vertica | S | X/SI | -- | IS | IX | -- | -- | -- | -- |
| Impala | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| StarRocks | -- | 表级 (元数据) | -- | -- | -- | -- | -- | -- | -- |
| Doris | -- | 表级 (元数据) | -- | -- | -- | -- | -- | -- | -- |
| MonetDB | -- | 表级 | -- | -- | -- | -- | -- | -- | -- |
| CrateDB | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| TimescaleDB | 同 PG | 同 PG | -- | RowShare | RowExclusive | -- | -- | -- | 是 |
| QuestDB | -- | Writer | -- | -- | -- | -- | -- | -- | -- |
| Exasol | 是 (表级) | 是 | -- | -- | -- | -- | -- | -- | -- |
| SAP HANA | 是 | 是 | -- | 是 | 是 | -- | -- | -- | -- |
| Informix | S | X | U | IS | IX | SIX | -- | -- | -- |
| Firebird | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| H2 | 是 | 是 | -- | -- | -- | -- | -- | -- | -- |
| HSQLDB | 是 | 是 | -- | -- | -- | -- | -- | -- | -- |
| Derby | S | X | U | IS | IX | SIX | -- | -- | -- |
| Amazon Athena | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| Azure Synapse | 是 (PolyBase 类 SQL Server) | 是 | 是 | 是 | 是 | -- | -- | 是 | -- |
| Google Spanner | 是 (read lock) | 是 (write lock) | -- | -- | -- | -- | -- | -- | -- |
| Materialize | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | -- | -- | -- | -- |
| DatabendDB | -- | 表级元数据 | -- | -- | -- | -- | -- | -- | -- |
| Yellowbrick | -- | 表级 | -- | -- | -- | -- | -- | -- | -- |
| Firebolt | -- | -- | -- | -- | -- | -- | -- | -- | -- |

> 关键观察：
> 1. SQL Server 是唯一支持完整 Gray 模型 + Range 锁全套的引擎（早期版本即支持）
> 2. 完整 IS/IX/SIX 体系主要存在于 SQL Server、DB2、Informix、Derby、Vertica 等 IBM/Sybase 谱系
> 3. PostgreSQL 用 8 种表级锁名替代意向锁体系（RowShare ≈ IS，RowExclusive ≈ IX）
> 4. Oracle 把意向锁合并到 RX 模式，用 ITL 槽位实现行锁元数据
> 5. 云数仓（Snowflake/BigQuery）和计算引擎（Trino/Spark/Flink）几乎不用传统锁

### Schema 锁（Sch-S / Sch-M）支持

| 引擎 | Schema 稳定锁 | Schema 修改锁 | 实现 |
|------|--------------|---------------|------|
| SQL Server | Sch-S | Sch-M | 显式两种锁 |
| MySQL | MDL_SHARED | MDL_EXCLUSIVE | MDL 子系统（5.5+） |
| MariaDB | MDL_SHARED | MDL_EXCLUSIVE | 同 MySQL |
| PostgreSQL | AccessShareLock | AccessExclusiveLock | 8 级锁阶 |
| Oracle | Library Cache Lock (Share) | Library Cache Lock (Excl) + DDL Lock | 库缓存双重锁 |
| DB2 | Plan Lock | Object Lock | 双层锁 |
| TiDB | Schema Lease | Schema Lease (excl) | 租约（在线 schema change） |
| CockroachDB | Schema Lease | Schema Version | 2 版本不变式 |
| Snowflake | -- | -- | 多版本 catalog |
| Hive | Shared (table) | Exclusive (table) | ZooKeeper / DbTxnManager |
| Vertica | T (Tuple Mover) | X | 多级锁阶 |

### 键范围锁（Key-Range Locks）支持

| 引擎 | 实现方式 | 锁模式 | 触发条件 |
|------|---------|--------|---------|
| SQL Server | 完整 Range 锁体系 | RangeS-S/RangeS-U/RangeI-N/RangeX-X | SERIALIZABLE 隔离级别 |
| MySQL InnoDB | Gap Lock + Next-Key Lock | Gap/Record/Next-Key/Insert-Intention | REPEATABLE READ 默认 |
| MariaDB InnoDB | 同 MySQL | 同 MySQL | REPEATABLE READ |
| OceanBase | 兼容 MySQL | Gap/Next-Key | REPEATABLE READ |
| PostgreSQL | Predicate Lock (SSI) | SIReadLock | SERIALIZABLE |
| DB2 LUW | NextKey Lock | NS/NX/W | RR/RS 隔离级别 |
| Oracle | -- (使用 SCN 多版本) | -- | -- |
| CockroachDB | Predicate Lock | -- (SSI 实现) | SERIALIZABLE 默认 |
| YugabyteDB | -- | -- | DocDB MVCC |

## 兼容性矩阵深入

### 基础 S/X/U 兼容性

最简单的两模式兼容性矩阵（CMU 15-721 教学示例）：

| 持有 \ 请求 | S | X |
|-----------|---|---|
| S | YES | NO |
| X | NO | NO |

加入 U 锁后变为三模式（DB2/SQL Server/Sybase 设计）：

| 持有 \ 请求 | S | U | X |
|-----------|---|---|---|
| S | YES | YES | NO |
| U | NO  | NO  | NO |
| X | NO  | NO  | NO |

关键观察：
- **U 锁与 S 锁兼容（请求方向）**：当事务持有 S 锁时，可以再请求 U 锁；这避免了"两个读者都想升级到 X 的死锁"
- **U 锁不与 S 兼容（持有方向）**：一旦持有 U 锁，新的 S 请求必须等待；这保证 U 锁能在适当时刻无阻塞地升级到 X
- **U 锁是单向兼容的**：与对称的 S/X 不同

### 完整 6 模式兼容性（Gray 模型）

包含意向锁后的完整兼容性矩阵：

| 持有 \ 请求 | IS | IX | S | SIX | U | X |
|-----------|----|----|---|-----|---|---|
| IS | YES | YES | YES | YES | YES | NO |
| IX | YES | YES | NO | NO | NO | NO |
| S  | YES | NO | YES | NO | YES | NO |
| SIX| YES | NO | NO | NO | NO | NO |
| U  | YES | NO | YES | NO | NO | NO |
| X  | NO | NO | NO | NO | NO | NO |

阅读方法（行 = 已持有，列 = 新请求）：
- IS-IX 兼容：两个事务都"打算访问某些行"，互相不冲突
- IS-S 兼容：高粒度上的 S 锁与意向 IS 兼容（都是读）
- IX-S 不兼容：意向写与表级共享冲突
- SIX 是混合模式：表级 S（防止其他人写整表）+ 意向 IX（自己要修改部分行）

### SQL Server 完整模式（含 IU/SIU/UIX）

SQL Server 是唯一实现了 IU 系列锁的主流引擎：

| 持有 \ 请求 | IS | IU | IX | S | SIU | SIX | U | UIX | X |
|-----------|----|----|----|----|----|-----|---|-----|---|
| IS | YES | YES | YES | YES | YES | YES | YES | YES | NO |
| IU | YES | NO | YES | YES | NO | YES | NO | YES | NO |
| IX | YES | YES | YES | NO | YES | NO | NO | YES | NO |
| S  | YES | YES | NO | YES | YES | NO | YES | NO | NO |
| SIU| YES | NO | YES | YES | NO | NO | NO | NO | NO |
| SIX| YES | YES | NO | NO | NO | NO | NO | NO | NO |
| U  | YES | NO | NO | YES | NO | NO | NO | NO | NO |
| UIX| YES | YES | YES | NO | NO | NO | NO | NO | NO |
| X  | NO | NO | NO | NO | NO | NO | NO | NO | NO |

注：IU = Intent Update（意向更新），SIU = Shared with Intent Update，UIX = Update with Intent Exclusive

完整文档参见 [SQL Server Lock Compatibility](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide#lock_compatibility)。

### 兼容性矩阵的对称性

理论上锁兼容性矩阵应当是**对称的**（A 与 B 兼容当且仅当 B 与 A 兼容），但实际中存在**非对称设计**——典型如 U 锁：

```
持有 S，请求 U: YES (允许)
持有 U，请求 S: NO  (拒绝)
```

这种非对称是有意设计的：U 锁一旦获取，就不能再有新的 S 请求进入，这样 U 锁升级到 X 时就不需要等待新的 S 锁释放。在 SQL Server 中，UPDATE 语句的执行流程是：

1. 扫描阶段对每行加 U 锁（兼容已存在的 S 锁）
2. 找到要修改的行后，将 U 升级为 X
3. 此时该行上的 S 锁已经释放（因为新 S 不能加），升级无需等待

### Oracle 6 种 TM 锁兼容性

Oracle 的 TM (DML 表级锁) 有 6 种模式，编号 0-6：

| 模式 | 名称 | 简写 | 用途 |
|------|------|------|------|
| 0 | None | - | 无锁 |
| 1 | Null | NULL | 占位 |
| 2 | Row Share | RS / SS | SELECT FOR UPDATE |
| 3 | Row Exclusive | RX / SX | INSERT/UPDATE/DELETE |
| 4 | Share | S | LOCK TABLE IN SHARE MODE |
| 5 | Share Row Exclusive | SRX / SSX | LOCK TABLE IN SHARE ROW EXCLUSIVE |
| 6 | Exclusive | X | LOCK TABLE IN EXCLUSIVE MODE / DDL |

兼容性矩阵：

| 持有 \ 请求 | RS | RX | S | SRX | X |
|-----------|----|----|----|----|---|
| RS  | YES | YES | YES | YES | NO |
| RX  | YES | YES | NO  | NO  | NO |
| S   | YES | NO  | YES | NO  | NO |
| SRX | YES | NO  | NO  | NO  | NO |
| X   | NO  | NO  | NO  | NO  | NO |

注意：Oracle 没有独立的 IS/IX 锁——它把意向语义直接编码到了 RS/RX 中（RS = "我有 SELECT FOR UPDATE 在某些行上"，RX = "我有 INSERT/UPDATE/DELETE 在某些行上"）。

## 各引擎详细说明

### SQL Server：完整 Gray 模型 + Range 锁全套

SQL Server 是历史上锁模式最完整的商业数据库，从 SQL Server 6.5（1996）就支持 S/X/U/IS/IX/SIX，2005 版本引入完整的 Range Lock 体系。

```sql
-- 通过 hint 显式指定锁模式
SELECT * FROM Orders WITH (UPDLOCK)        -- U 锁
    WHERE OrderID = 100;

SELECT * FROM Orders WITH (HOLDLOCK)        -- S 锁直到事务结束
    WHERE OrderID = 100;

SELECT * FROM Orders WITH (XLOCK)           -- X 锁
    WHERE OrderID = 100;

SELECT * FROM Orders WITH (TABLOCK)         -- 表级 S
    WHERE OrderID = 100;

SELECT * FROM Orders WITH (TABLOCKX)        -- 表级 X
    WHERE OrderID = 100;

SELECT * FROM Orders WITH (REPEATABLEREAD)  -- 强制 RR 隔离
    WHERE OrderID = 100;

-- 监控当前锁
SELECT
    request_session_id AS spid,
    resource_type,
    resource_associated_entity_id,
    request_mode,
    request_status
FROM sys.dm_tran_locks
WHERE resource_database_id = DB_ID();

-- 查看锁等待
SELECT
    blocking_session_id,
    session_id,
    wait_type,
    wait_time,
    last_wait_type
FROM sys.dm_os_waiting_tasks
WHERE wait_type LIKE 'LCK%';
```

#### Range 锁的 4 种组合

SQL Server 在 SERIALIZABLE 隔离级别下使用 Range 锁防止幻读，每种 Range 锁有两个组成部分：第一部分 `Range*` 描述索引区间的锁模式，第二部分描述区间端点（资源）上的锁模式：

```
RangeS-S: Range Shared, Resource Shared
  用途: 在 SERIALIZABLE 下做范围 SELECT
  含义: 区间和端点都是 S 锁，阻止其他事务在区间内 INSERT/UPDATE/DELETE

RangeS-U: Range Shared, Resource Update
  用途: SERIALIZABLE 下扫描后准备更新
  含义: 区间是 S（防止他人插入），端点是 U（准备升级到 X）

RangeI-N: Range Insert, Resource None
  用途: 测试插入是否会违反唯一约束
  含义: 临时锁，仅持续到约束检查完成

RangeX-X: Range Exclusive, Resource Exclusive
  用途: SERIALIZABLE 下的 DELETE 范围扫描
  含义: 区间和端点都是 X
```

完整 Range 锁兼容性矩阵：

| 持有 \ 请求 | RangeS-S | RangeS-U | RangeI-N | RangeX-X |
|-----------|----------|----------|----------|----------|
| RangeS-S  | YES | YES | NO  | NO |
| RangeS-U  | YES | NO  | NO  | NO |
| RangeI-N  | NO  | NO  | YES | NO |
| RangeX-X  | NO  | NO  | NO  | NO |

注意 RangeI-N 与 RangeI-N 兼容：两个并发的 INSERT 可以同时检查唯一约束，这是优化设计。

#### 锁模式转换规则

```
SELECT 默认: S 锁 (短暂，语句结束释放)
SELECT WITH (HOLDLOCK): S 锁 (持续到事务结束)
UPDATE: U 锁 → 找到目标行 → 升级为 X 锁
INSERT: IX 锁 (表级) + X 锁 (行级)
DELETE: X 锁

SERIALIZABLE 隔离级别下:
  范围 SELECT → RangeS-S
  范围 UPDATE → RangeS-U → RangeX-X
  范围 DELETE → RangeX-X
  INSERT (检查唯一性) → RangeI-N → 转换为 X 锁
```

#### 锁升级阈值

```sql
-- 默认: ~5000 行触发升级
ALTER TABLE Orders SET (LOCK_ESCALATION = TABLE);   -- 默认
ALTER TABLE Orders SET (LOCK_ESCALATION = AUTO);    -- 分区表升级到分区
ALTER TABLE Orders SET (LOCK_ESCALATION = DISABLE); -- 禁用升级

-- 对单分区操作可只升级到分区锁而非表锁
```

详见 [`lock-escalation.md`](./lock-escalation.md)。

### Oracle：6 种 TM 模式 + ITL 行锁

Oracle 的锁体系有两层：

1. **TM (DML Table Lock)**：表级锁，6 种模式（前述）
2. **TX (Transaction Lock)**：事务锁，标记某个事务持有某些行；存储在数据块的 ITL（Interested Transaction List）中

Oracle 的核心特性是**永不升级行锁**——无论一个事务锁了 1 行还是 1 亿行，都不会自动升级为表锁。这与 SQL Server 的 5000 行升级形成鲜明对比。

```sql
-- 显式 TM 锁
LOCK TABLE employees IN ROW SHARE MODE;            -- RS (mode 2)
LOCK TABLE employees IN ROW EXCLUSIVE MODE;        -- RX (mode 3)
LOCK TABLE employees IN SHARE MODE;                -- S  (mode 4)
LOCK TABLE employees IN SHARE ROW EXCLUSIVE MODE;  -- SRX (mode 5)
LOCK TABLE employees IN EXCLUSIVE MODE;            -- X  (mode 6)

-- NOWAIT / WAIT
LOCK TABLE employees IN EXCLUSIVE MODE NOWAIT;
LOCK TABLE employees IN EXCLUSIVE MODE WAIT 30;

-- 监控
SELECT
    sid,
    type,           -- TM (table) / TX (transaction) / UL (user lock) / 其他
    id1, id2,
    lmode,          -- 锁模式 (1-6)
    request,        -- 等待模式 (1-6)
    block           -- 是否阻塞他人
FROM v$lock
WHERE type IN ('TM', 'TX');

-- 解读 lmode/request 数字:
--   0 = None
--   1 = Null (NULL)
--   2 = Row-S (SS)
--   3 = Row-X (SX)
--   4 = Share (S)
--   5 = S/Row-X (SSX)
--   6 = Exclusive (X)

-- 阻塞链
SELECT s1.sid AS blocker, s2.sid AS waiter, s2.event
FROM v$lock l1, v$lock l2,
     v$session s1, v$session s2
WHERE l1.block = 1
  AND l2.request > 0
  AND l1.id1 = l2.id1
  AND l1.id2 = l2.id2
  AND l1.sid = s1.sid
  AND l2.sid = s2.sid;
```

#### TX 锁与 ITL 槽位

每个数据块（block）头部都有 ITL（Interested Transaction List）数组，默认 INITRANS=1 或 2 个槽位。每个 INSERT/UPDATE/DELETE 都需要在 ITL 中分配一个槽位记录"哪个事务正在修改本块"：

```sql
-- 查看表的 ITL 配置
SELECT table_name, ini_trans, max_trans
FROM user_tables
WHERE table_name = 'EMPLOYEES';

-- 增加 ITL 减少 ITL 等待 (适合高并发热表)
ALTER TABLE employees INITRANS 32;
```

ITL 槽位是有限的——如果同时有多个事务修改同一数据块，且 ITL 已满，新事务必须等待。这就是 Oracle 的 "ITL waits" 现象，监控指标为 `enq: TX - allocate ITL entry`。

#### 为什么 Oracle 不升级行锁

Oracle 的行锁不依赖独立锁管理器（不像 SQL Server 用内存中的 lock manager 表）——锁信息直接存于数据块的 ITL 中。这意味着：

1. 无独立内存压力（无 LOCKLIST 之类的全局结构）
2. 无升级动机（不存在锁元数据爆炸的问题）
3. 但 ITL 槽位有限，热块场景下需要调高 INITRANS

### MySQL InnoDB：S/X + IS/IX + Gap Lock 全家族

InnoDB 的锁体系是 OLTP 引擎中最复杂的之一。基础部分遵循 Gray 模型（S/X + IS/IX 意向锁），但在 REPEATABLE READ 隔离级别下扩展了 Gap Lock 与 Next-Key Lock 来防止幻读。

```sql
-- 基础锁模式
SELECT * FROM accounts WHERE id = 1 FOR SHARE;       -- S 锁 (8.0+)
SELECT * FROM accounts WHERE id = 1 LOCK IN SHARE MODE;  -- S 锁 (旧语法)
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;      -- X 锁

-- NOWAIT / SKIP LOCKED (8.0+)
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM jobs WHERE status='pending' FOR UPDATE SKIP LOCKED LIMIT 10;

-- 显式表锁 (设置意向锁 IS/IX)
LOCK TABLES accounts WRITE;     -- 表级 X (隐含 IX)
LOCK TABLES accounts READ;      -- 表级 S (隐含 IS)
UNLOCK TABLES;

-- 监控
SHOW ENGINE INNODB STATUS\G

SELECT
    engine_lock_id,
    engine_transaction_id,
    thread_id,
    object_name,
    lock_type,
    lock_mode,
    lock_status,
    lock_data
FROM performance_schema.data_locks;

SELECT * FROM performance_schema.data_lock_waits;
```

#### 锁模式编码

InnoDB 的 `data_locks` 视图中的 `lock_mode` 字段使用如下编码：

```
S         - Shared (record lock)
X         - Exclusive (record lock)
S,GAP     - Shared gap lock (only the gap, not the record)
X,GAP     - Exclusive gap lock
S,REC_NOT_GAP - Shared record lock without gap (READ COMMITTED 模式下)
X,REC_NOT_GAP - Exclusive record lock without gap
IS        - Intention shared (table level)
IX        - Intention exclusive (table level)
S,GAP,INSERT_INTENTION - Insert intention waiting on gap
X,GAP,INSERT_INTENTION - Insert intention with X gap
```

#### 表级意向锁与行级锁的关系

InnoDB 在表级别只有 IS/IX 锁（用于与显式 LOCK TABLES 协调），行级别才有 S/X 锁：

```sql
-- 事务在 accounts 表上执行 SELECT FOR SHARE:
--   1. 表级请求 IS 锁
--   2. 行级请求 S 锁

-- 事务在 accounts 表上执行 UPDATE:
--   1. 表级请求 IX 锁
--   2. 行级请求 X 锁

-- 兼容性 (表级 IS/IX 与显式 LOCK TABLES):
--   IS 与 IS、IX 兼容；与表级 S（READ）兼容；与表级 X（WRITE）冲突
--   IX 与 IS、IX 兼容；与表级 S/X 都冲突
```

### MySQL InnoDB Gap Lock & Next-Key Lock 深入

InnoDB 在 REPEATABLE READ 隔离级别下的默认行为是 **Next-Key Lock**——它锁定索引记录加上前面的间隙（gap）。这是 InnoDB 防止幻读的核心机制。

#### 三种锁的形式

```
设有索引 idx_age 包含值: 10, 20, 30, 40, 50

Record Lock:
  仅锁定记录本身，例如锁定 age=30 这一条索引项

Gap Lock:
  锁定记录之间的间隙，例如锁定 (20, 30) 区间
  注意是开区间——不包含端点

Next-Key Lock = Record Lock + Gap Lock:
  锁定一条记录及其前面的间隙，例如锁定 (20, 30]
  注意是左开右闭——这是 InnoDB 的特殊约定
```

#### REPEATABLE READ 下的 Next-Key Lock 行为

```sql
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;

-- 范围查询 + FOR UPDATE
SELECT * FROM users WHERE age BETWEEN 25 AND 35 FOR UPDATE;

-- InnoDB 加的锁:
-- 1. age=30 的记录上的 Next-Key Lock: (20, 30]
-- 2. age=35 之后的下一条索引项的 Gap Lock: (30, 40)
--    (实际上是 next-key (30, 40] 但只锁 gap 部分)
-- 3. 表级 IX 锁

-- 此时其他事务尝试:
-- INSERT INTO users (age) VALUES (25);   -- 阻塞 (25 在 (20,30] 内)
-- INSERT INTO users (age) VALUES (32);   -- 阻塞 (32 在 (30,40) 内)
-- INSERT INTO users (age) VALUES (45);   -- 不阻塞 (超出范围)
```

#### Insert Intention Lock

Gap Lock 之间互相兼容（多个事务可以同时持有同一个 gap 的 Gap Lock），但 Gap Lock 与 Insert Intention Lock 冲突。Insert Intention Lock 是一种特殊的 Gap Lock，由 INSERT 语句获取：

```sql
-- 场景: 两个事务并发 INSERT 到同一区间
-- 事务 T1: INSERT INTO t (age) VALUES (25)
-- 事务 T2: INSERT INTO t (age) VALUES (28)

-- T1 和 T2 都需要在 (20, 30) 区间获取 Insert Intention Lock
-- 这两个 Insert Intention Lock 之间是兼容的——并发 INSERT 不互相阻塞

-- 但如果先有事务持有了 Gap Lock:
-- 事务 T0: SELECT * FROM t WHERE age BETWEEN 20 AND 30 FOR UPDATE
-- 然后:
-- 事务 T1: INSERT INTO t (age) VALUES (25)   -- 阻塞
-- 事务 T2: INSERT INTO t (age) VALUES (28)   -- 阻塞
```

#### READ COMMITTED 下 Gap Lock 被禁用

InnoDB 在 READ COMMITTED 隔离级别下**禁用 Gap Lock**——只保留 Record Lock：

```sql
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;

SELECT * FROM users WHERE age BETWEEN 25 AND 35 FOR UPDATE;

-- InnoDB 仅加 Record Lock，不加 Gap Lock
-- 此时其他事务可以 INSERT INTO users (age) VALUES (28);
-- 这是 READ COMMITTED 不防幻读的体现
```

这也是为什么生产环境很多 MySQL 实例会切换到 READ COMMITTED：避免 Gap Lock 引起的死锁。代价是失去防幻读能力。

#### 唯一索引 vs 非唯一索引的差异

```sql
-- 唯一索引: 等值查询命中时只加 Record Lock，不加 Gap Lock
-- 因为唯一索引本身保证了不会有"中间插入"
SELECT * FROM users WHERE id = 5 FOR UPDATE;
-- 仅在 id=5 上加 Record Lock

-- 非唯一索引: 即使等值查询，也加 Next-Key Lock
SELECT * FROM users WHERE name = 'Alice' FOR UPDATE;
-- 加 Next-Key Lock 锁定 name='Alice' 前后的间隙
```

#### Phantom Read 防护示例

```sql
-- 没有 Next-Key Lock 时的幻读（其他引擎默认行为）:
-- T1: SELECT COUNT(*) FROM t WHERE age > 30   -- 返回 5
-- T2: INSERT INTO t (age) VALUES (35)          -- 不被阻塞
-- T1: SELECT COUNT(*) FROM t WHERE age > 30   -- 返回 6 (幻读)

-- InnoDB Next-Key Lock 防护:
-- T1: SELECT COUNT(*) FROM t WHERE age > 30 FOR UPDATE
--     加锁: 所有 age > 30 的记录 + 前后间隙 + supremum
-- T2: INSERT INTO t (age) VALUES (35)          -- 阻塞，等待 T1
```

注：InnoDB 普通 SELECT 用 MVCC 保证一致性读，Next-Key Lock 仅在 SELECT FOR SHARE/UPDATE 或 INSERT/UPDATE/DELETE 中获取。

### PostgreSQL：8 种表锁 + 4 种行锁

PostgreSQL 的锁体系结构独特：表级锁有 8 种命名模式（不直接使用 IS/IX 名称），行级锁通过 tuple 头部的 xmax 字段记录（不消耗共享内存）。

#### 8 种表级锁

```sql
-- 从弱到强的 8 种表锁
LOCK TABLE accounts IN ACCESS SHARE MODE;            -- 1: SELECT
LOCK TABLE accounts IN ROW SHARE MODE;               -- 2: SELECT FOR UPDATE/SHARE
LOCK TABLE accounts IN ROW EXCLUSIVE MODE;           -- 3: INSERT/UPDATE/DELETE
LOCK TABLE accounts IN SHARE UPDATE EXCLUSIVE MODE;  -- 4: VACUUM/ANALYZE/CREATE INDEX CONCURRENTLY
LOCK TABLE accounts IN SHARE MODE;                   -- 5: CREATE INDEX
LOCK TABLE accounts IN SHARE ROW EXCLUSIVE MODE;     -- 6: 较少使用
LOCK TABLE accounts IN EXCLUSIVE MODE;               -- 7: 阻塞所有读写（除 ACCESS SHARE）
LOCK TABLE accounts IN ACCESS EXCLUSIVE MODE;        -- 8: DROP/TRUNCATE/ALTER
```

8 种表锁的兼容性矩阵：

| 持有 \ 请求 | AccS | RowS | RowX | SUEx | Sh | SRowX | Ex | AccEx |
|-----------|------|------|------|------|----|----|----|----|
| AccessShare        | YES | YES | YES | YES | YES | YES | YES | NO |
| RowShare           | YES | YES | YES | YES | YES | YES | NO  | NO |
| RowExclusive       | YES | YES | YES | YES | NO  | NO  | NO  | NO |
| ShareUpdateExclusive | YES | YES | YES | NO | NO | NO | NO | NO |
| Share              | YES | YES | NO  | NO  | YES | NO  | NO  | NO |
| ShareRowExclusive  | YES | YES | NO  | NO  | NO  | NO  | NO  | NO |
| Exclusive          | YES | NO  | NO  | NO  | NO  | NO  | NO  | NO |
| AccessExclusive    | NO  | NO  | NO  | NO  | NO  | NO  | NO  | NO |

PostgreSQL 命名映射：
```
ACCESS SHARE    ≈ S (read intent)
ROW SHARE       ≈ IS
ROW EXCLUSIVE   ≈ IX
SHARE           ≈ S (table)
EXCLUSIVE       ≈ SIX
ACCESS EXCLUSIVE = X (table)
```

#### 4 种行级锁

```sql
-- 行级锁的 4 种变体
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;          -- 完整行锁
SELECT * FROM accounts WHERE id = 1 FOR NO KEY UPDATE;   -- 不锁主键，允许外键检查
SELECT * FROM accounts WHERE id = 1 FOR SHARE;           -- 共享锁
SELECT * FROM accounts WHERE id = 1 FOR KEY SHARE;       -- 仅锁主键
```

行级锁兼容性：

| 持有 \ 请求 | KEY SHARE | SHARE | NO KEY UPD | UPDATE |
|-----------|-----------|-------|------------|--------|
| KEY SHARE     | YES | YES | YES | NO  |
| SHARE         | YES | YES | NO  | NO  |
| NO KEY UPDATE | YES | NO  | NO  | NO  |
| UPDATE        | NO  | NO  | NO  | NO  |

KEY SHARE 与 NO KEY UPDATE 兼容是 PG 9.3 的设计：允许外键检查（KEY SHARE）与不修改主键的更新（NO KEY UPDATE）并存，避免外键场景下的常见死锁。

#### Predicate Lock for SSI

PostgreSQL 实现了 SSI (Serializable Snapshot Isolation)，但不使用 Range Lock。它通过 **Predicate Lock** 跟踪每个事务读取过哪些数据：

```sql
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- 监控
SELECT * FROM pg_locks WHERE locktype = 'page' AND mode = 'SIReadLock';
```

`SIReadLock` 是不阻塞任何操作的"虚拟锁"，仅用于追踪读集，提交时检测读写冲突。详见 [`mvcc-implementation.md`](./mvcc-implementation.md)。

### DB2：IS/IX/S/SIX/U/X/Z 完整体系

DB2 是 Gray 模型的"教科书实现"，包含完整的 6 种基础模式 + Z 锁（superexclusive）：

| 锁模式 | 缩写 | 用途 |
|--------|------|------|
| Intent None | IN | 无意向（读取无锁数据） |
| Intent Share | IS | 表级，事务将读某些行 |
| Next Key Share | NS | 行级 RR/RS 隔离的读 |
| Share | S | 表级共享 |
| Intent Exclusive | IX | 表级，事务将改某些行 |
| Share with Intent Exclusive | SIX | 表级 S + IX |
| Update | U | 行级 U 锁 |
| Next Key Weak Exclusive | NW | 类似 X 但允许 NS |
| Exclusive | X | 行级 X / 表级 X |
| Weak Exclusive | W | 用于 INSERT |
| Super Exclusive | Z | 最强锁，DDL 用 |

```sql
-- DB2 显式锁
LOCK TABLE employees IN SHARE MODE;
LOCK TABLE employees IN EXCLUSIVE MODE;

-- FOR UPDATE
SELECT * FROM employees WHERE id = 100 FOR UPDATE;

-- SKIP LOCKED DATA (DB2 特有语法)
SELECT * FROM job_queue
    WHERE status='ready'
    FOR UPDATE SKIP LOCKED DATA;

-- 监控
SELECT * FROM TABLE(MON_GET_LOCKS(NULL,-2)) AS L;

-- 锁等待
SELECT * FROM SYSIBMADM.SNAPLOCKWAIT;

-- 全局锁活动
SELECT * FROM SYSIBMADM.LOCKS_HELD;
```

DB2 的 LOCKLIST 内存池配置：

```sql
-- 调整 LOCKLIST (单位: 4KB pages)
UPDATE DB CFG FOR mydb USING LOCKLIST 50000;

-- MAXLOCKS: 单个事务最多占 LOCKLIST 的百分比
UPDATE DB CFG FOR mydb USING MAXLOCKS 22;

-- 当事务持锁超过 MAXLOCKS%，DB2 触发锁升级
-- 详见 lock-escalation.md
```

### SQLite：5 种文件级状态锁

SQLite 完全不实现行/页锁——它使用整个数据库文件的状态机（5 种状态）作为锁机制：

```
UNLOCKED (未锁定)
    ↓
SHARED   (共享锁: 读)
    ↓
RESERVED (保留锁: 准备写)
    ↓
PENDING  (等待锁: 阻止新读者)
    ↓
EXCLUSIVE(排他锁: 写)
```

每个连接同时只能持有一种状态：

| 状态 | 用途 | 是否阻塞读 | 是否阻塞写 |
|------|------|-----------|-----------|
| UNLOCKED | 无活动 | 否 | 否 |
| SHARED | 读 | 否（多个 SHARED 可并存） | 是 |
| RESERVED | 写事务开始 | 否（其他读可以继续） | 是（互斥） |
| PENDING | 等待所有 SHARED 释放 | 是（不允许新 SHARED） | 是 |
| EXCLUSIVE | 实际写入数据库文件 | 是 | 是 |

```sql
-- SQLite 没有行锁/表锁概念
-- 所有事务隐式按上述状态机协调

-- 写事务的状态转换:
BEGIN;
SELECT * FROM t WHERE id = 1;     -- SHARED
INSERT INTO t VALUES (...);        -- RESERVED
                                    -- 待释放 buffer 时升级 → PENDING → EXCLUSIVE
COMMIT;                             -- 释放，回 UNLOCKED
```

WAL 模式下机制略有不同：写入直接进 WAL 文件，读者继续从主数据库文件读取已提交数据。但**写者仍是串行化的**——全数据库范围只有一个写者。

```sql
-- 启用 WAL 模式
PRAGMA journal_mode=WAL;

-- 设置忙等待超时 (ms)
PRAGMA busy_timeout = 5000;
```

### CockroachDB：Intent 锁 + Predicate 锁

CockroachDB 用 KV 层的 **intent** 实现行锁。每个写操作在 KV 中留下一个 "write intent" 标记，包含事务 ID：

```
KV 行的物理表示:
  key = "/Table/orders/1/balance"
  value = (timestamp=100, value=500, intent_txn=null)         -- 已提交版本

  写入时新增 intent:
  value = (timestamp=200, value=800, intent_txn=T123)         -- 未提交 intent
```

其他事务读到 intent 时：
1. 检查 intent 持有者事务状态
2. 若已 commit: 应用 value
3. 若仍在运行: 比较优先级，决定等待或 push txn

```sql
-- FOR UPDATE 在 20.1+ 支持
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE NOWAIT;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE SKIP LOCKED;  -- 22.2+

-- 设置事务优先级
SET TRANSACTION PRIORITY HIGH;       -- LOW / NORMAL / HIGH

-- 监控
SHOW LOCKS;
```

### Hive：ACID 表的 IS/IX/S/X

Hive 在引入 ACID 表（Hive 0.13+，完整 ACID 在 3.0）后实现了完整的锁体系，使用 ZooKeeper 或内置的 DbTxnManager 协调：

```
Shared Lock (S): 读
Exclusive Lock (X): 写 / 修改 schema
Intention Shared (IS): 表级
Intention Exclusive (IX): 表级
```

Hive 锁兼容性：

| 持有 \ 请求 | S | X | IS | IX |
|-----------|---|---|----|----|
| S | YES | NO | YES | NO |
| X | NO | NO | NO | NO |
| IS| YES | NO | YES | YES |
| IX| NO  | NO | YES | YES |

```sql
-- Hive 锁配置
SET hive.support.concurrency = true;
SET hive.txn.manager = org.apache.hadoop.hive.ql.lockmgr.DbTxnManager;

-- 显式表锁
LOCK TABLE customers SHARED;
LOCK TABLE customers EXCLUSIVE;
UNLOCK TABLE customers;

-- 显式分区锁
LOCK TABLE customers PARTITION (region='APAC') EXCLUSIVE;

-- 查看当前锁
SHOW LOCKS;
SHOW LOCKS customers;
SHOW LOCKS customers EXTENDED;
SHOW LOCKS customers PARTITION (region='APAC');
```

### Vertica：7 级锁阶（O/I/S/IS/IX/SI/X）

Vertica 实现了 7 种锁模式，其中包含独特的 O (Owner) 和 SI (Shared with Intent X) 模式：

| 锁模式 | 缩写 | 用途 |
|--------|------|------|
| Usage | U | 类似 IS |
| Insert | I | INSERT 专用 |
| Shared | S | SELECT |
| Intent Shared | IS | 表级 |
| Intent Exclusive | IX | 表级 |
| Shared/Intent Exclusive | SI | UPDATE/DELETE |
| Exclusive | X | DDL |

```sql
-- 查看当前锁
SELECT * FROM v_monitor.locks;

-- 锁等待
SELECT * FROM v_monitor.lock_usage;
```

### Teradata：4 种锁阶（Access/Read/Write/Exclusive）

Teradata 使用最简单的 4 种锁模式，与传统的 S/X/U 模型不完全对应：

| 锁模式 | 用途 | 兼容性 |
|--------|------|--------|
| Access | 脏读 | 与一切兼容（除 Exclusive） |
| Read | SELECT | 与 Access/Read 兼容 |
| Write | UPDATE/INSERT/DELETE | 与 Access 兼容 |
| Exclusive | DDL | 与一切冲突 |

```sql
-- LOCKING modifier (前置式语法)
LOCKING TABLE customers FOR ACCESS
SELECT * FROM customers;

LOCKING TABLE customers FOR EXCLUSIVE
LOCKING ROW FOR WRITE
SELECT * FROM customers WHERE id = 100;

-- NOWAIT
LOCKING TABLE customers FOR WRITE NOWAIT
INSERT INTO customers VALUES (...);
```

### Snowflake：无传统锁，全表写锁

Snowflake 完全抛弃了行锁概念。其架构基于不可变微分区，DML 写入会重写微分区。同表的 DML 之间通过表级写锁串行化：

```sql
-- 监控
SHOW LOCKS;

-- 查看锁持有者和等待者
SHOW LOCKS IN ACCOUNT;

-- 强制中止事务
SELECT SYSTEM$ABORT_TRANSACTION(<txn_id>);
```

无 IS/IX、无 SIX、无 Range Lock、无咨询锁——这是云数仓为 OLAP 优化做出的根本设计取舍。

### BigQuery：无锁 + 微批次串行

BigQuery 的 DML 语句在表级别串行化（通过 commit token 机制），无任何用户可见的锁 API。多语句事务（2021 年 GA）使用快照隔离 + 提交时冲突检测。

### Redshift：从 PG 8 锁简化为 3 种

Redshift 是 PostgreSQL 8.0 的 fork，但简化了锁体系，主要使用三种：

```
AccessShareLock   - SELECT
AccessExclusiveLock - DDL / VACUUM / COPY
ShareRowExclusive  - 部分维护操作

注意: Redshift 不支持 SELECT FOR UPDATE / FOR SHARE
```

### Google Spanner：Read Lock + Write Lock

Spanner 在 read-write 事务中使用两种锁：

```
Read Lock: SELECT 时获取，与其他 read lock 兼容
Write Lock: UPDATE/INSERT/DELETE 获取，与一切冲突
```

Spanner 用 wound-wait 死锁避免（详见 [`locks-deadlocks.md`](./locks-deadlocks.md)），不需要传统的 IS/IX 意向锁。

### TiDB：MySQL 兼容的悲观锁

TiDB 自 3.0 引入悲观锁模式后，锁模式完全兼容 MySQL InnoDB：S/X 行锁、IS/IX 表级意向锁、Gap Lock（在 4.0+ 默认禁用，仅在唯一索引检查时启用）。

```sql
-- 显式启用悲观事务
BEGIN PESSIMISTIC;
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;

-- 全局配置
SET GLOBAL tidb_txn_mode = 'pessimistic';
```

### OceanBase：完整兼容 MySQL InnoDB

OceanBase 是阿里自研分布式数据库，锁模型完整兼容 MySQL InnoDB（Gap Lock、Next-Key Lock、IS/IX 意向锁），同时也支持 Oracle 兼容模式（TM/TX 锁）。

### YugabyteDB：DocDB 行级锁

YugabyteDB 在 DocDB 层实现了细粒度行锁，兼容 PostgreSQL 的 4 种行锁模式：

```sql
SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR NO KEY UPDATE;
SELECT * FROM accounts WHERE id = 1 FOR SHARE;
SELECT * FROM accounts WHERE id = 1 FOR KEY SHARE;
```

## SQL Server Key-Range Lock for SERIALIZABLE 深入

SQL Server 的 Key-Range Lock 是 SERIALIZABLE 隔离级别的核心机制——它在索引层面锁定"键的区间"，防止其他事务在该区间内插入新行（幻读）。

### Key-Range Lock 的设计目标

在 SERIALIZABLE 下，SQL Server 必须保证：
1. 范围 SELECT 在事务期间多次执行返回相同结果
2. 已存在行的修改对其他事务可见性受隔离保护
3. 区间内的新行不能被其他事务插入

实现方式：在范围扫描时，对扫描经过的每个索引项加 RangeS-S 锁。这把锁覆盖：
- 索引项本身（资源）：S 模式
- 索引项与其前驱之间的间隙（range）：S 模式

### 简单示例

```sql
-- 设置: 表 accounts 在 balance 列上有索引，已有数据 100, 200, 300, 400, 500

-- 事务 T1 启动 SERIALIZABLE
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;

SELECT * FROM accounts WHERE balance BETWEEN 200 AND 400;
-- 返回 balance=200, 300, 400 三行

-- SQL Server 加的锁:
-- balance=200: RangeS-S (range 部分锁 (100, 200), resource 锁 200)
-- balance=300: RangeS-S (range (200, 300), resource 300)
-- balance=400: RangeS-S (range (300, 400), resource 400)
-- balance=500: RangeS-S (range (400, 500), resource 500)
--   注意需要锁到 500 才能保证 400 后面的间隙不能插入

-- 事务 T2 尝试:
INSERT INTO accounts VALUES (..., 250);  -- 阻塞 (250 在 (200, 300) 内)
INSERT INTO accounts VALUES (..., 350);  -- 阻塞 (350 在 (300, 400) 内)
INSERT INTO accounts VALUES (..., 600);  -- 不阻塞 (超出范围)
INSERT INTO accounts VALUES (..., 50);   -- 不阻塞 (超出范围)
```

### Range 锁与 Insert Intention 的交互

```sql
-- T1 持有 RangeS-S 锁定 (200, 300)
-- T2 尝试 INSERT VALUES (250):
--   1. T2 请求 RangeI-N 锁 (Insert Intention)
--   2. RangeI-N 与 RangeS-S 冲突 (RangeI-N 的 range 部分是 I，与 S 不兼容)
--   3. T2 阻塞，等待 T1 提交
```

### Range 锁的 Bookmarks 行为

SQL Server 的 Range 锁是基于"key + 间隙"的——这意味着如果事务先锁了 key 200，再锁 key 300，**两者之间的 (200, 300) 间隙也被锁了**：

```
锁的物理表示:
  RangeS-S on key 200: 锁 (prev_key, 200)，包含 200
  RangeS-S on key 300: 锁 (200, 300)，包含 300
  RangeS-S on key 400: 锁 (300, 400)，包含 400

  整体效果: (prev_key, 400] 整个区间被锁
```

### 为什么 SQL Server 选择 Range Lock 而非 Predicate Lock

PostgreSQL 用 Predicate Lock（仅追踪不阻塞）+ 提交时冲突检测实现 SSI。SQL Server 用 Range Lock（实际阻塞）实现 SERIALIZABLE。两种方法的取舍：

| 维度 | Range Lock (SQL Server) | Predicate Lock (PG SSI) |
|------|-----------------------|------------------------|
| 实现复杂度 | 较低（基于已有锁机制） | 较高（需追踪读集） |
| 阻塞行为 | 提前阻塞（写者等读者） | 提交时回滚 |
| CPU 开销 | 中（普通锁开销） | 较高（读集追踪 + 冲突检测） |
| 死锁可能 | 高（锁等待形成环路） | 低（无锁等待） |
| 吞吐量 | 低冲突场景较好 | 高冲突场景较好 |

### Range 锁的性能影响

```sql
-- 错误使用 SERIALIZABLE 导致大量阻塞:
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRANSACTION;

-- 全表扫描!
SELECT * FROM huge_table WHERE non_indexed_col = 'X';

-- SQL Server 必须锁定整个表（无索引可锁）
-- 实际可能加 Sch-S + 表级 S 锁
-- 任何 INSERT/UPDATE/DELETE 全部阻塞，直到事务结束

-- 正确做法: 仅在确实需要"防幻读"时使用 SERIALIZABLE
-- 大部分场景用 SNAPSHOT 隔离 (基于 MVCC，无 Range 锁)
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
```

### Range 锁与 Snapshot Isolation 的对比

SQL Server 2005 引入 SNAPSHOT 隔离后，Range 锁的实际使用大幅减少：

```sql
-- 传统 SERIALIZABLE
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- 使用 Range 锁阻止幻读

-- SNAPSHOT (基于 MVCC，2005+)
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
-- 不使用任何阻塞锁，从快照读
-- 但可能在提交时检测到 update conflict (3960 错误)

-- 启用 READ_COMMITTED_SNAPSHOT 数据库选项
ALTER DATABASE mydb SET READ_COMMITTED_SNAPSHOT ON;
-- READ COMMITTED 也会改用 MVCC，不再用读锁
```

详见 [`mvcc-implementation.md`](./mvcc-implementation.md)。

## 咨询锁深入

咨询锁（advisory lock，应用锁）是数据库提供的"通用锁原语"——不锁定任何具体的数据行/表，仅作为应用层互斥的协调点。

### PostgreSQL pg_advisory_lock

PostgreSQL 是咨询锁支持最完善的引擎：

```sql
-- 阻塞获取
SELECT pg_advisory_lock(12345);

-- 非阻塞尝试
SELECT pg_try_advisory_lock(12345);  -- 返回 boolean

-- 共享锁版本
SELECT pg_advisory_lock_shared(12345);
SELECT pg_try_advisory_lock_shared(12345);

-- 事务级 (事务结束自动释放)
SELECT pg_advisory_xact_lock(12345);
SELECT pg_try_advisory_xact_lock(12345);

-- 两参数版本 (两个 int32 组合成 bigint)
SELECT pg_advisory_lock(1, 2);

-- 释放
SELECT pg_advisory_unlock(12345);
SELECT pg_advisory_unlock_all();   -- 释放所有
```

#### 咨询锁的兼容性

PostgreSQL 咨询锁也有 S/X 模式：

| 持有 \ 请求 | Shared | Exclusive |
|-----------|--------|-----------|
| Shared    | YES | NO |
| Exclusive | NO  | NO |

#### 典型使用场景

```sql
-- 1. 单实例 leader 选举
SELECT pg_try_advisory_lock(hashtext('leader-election'));
-- 返回 true 即成为 leader

-- 2. 分布式定时任务 (避免重复执行)
BEGIN;
IF pg_try_advisory_xact_lock(hashtext('cleanup-job')) THEN
  -- 执行清理逻辑
END IF;
COMMIT;
-- 事务结束锁自动释放

-- 3. 防止并发修改 (锁某个业务实体)
SELECT pg_advisory_lock(hashtext('user-' || user_id));
-- 处理 user
SELECT pg_advisory_unlock(hashtext('user-' || user_id));
```

### MySQL GET_LOCK

```sql
-- 获取 (timeout 秒)
SELECT GET_LOCK('mylock', 5);    -- 0=未获取, 1=已获取, NULL=错误

-- 检查
SELECT IS_FREE_LOCK('mylock');   -- 1=空闲, 0=被占用
SELECT IS_USED_LOCK('mylock');   -- 返回持有者 connection_id

-- 释放
SELECT RELEASE_LOCK('mylock');
SELECT RELEASE_ALL_LOCKS();      -- 8.0+

-- 5.7.5+ 是实例级锁 (之前是会话级)
-- 同一会话可以持有多个不同名字的锁
```

### SQL Server sp_getapplock

```sql
-- 获取 (在事务内)
BEGIN TRANSACTION;
EXEC sp_getapplock
    @Resource = 'myresource',
    @LockMode = 'Exclusive',     -- 或 'Shared', 'Update', 'IntentShared', 'IntentExclusive'
    @LockOwner = 'Transaction',  -- 或 'Session'
    @LockTimeout = 5000;

-- 检查
SELECT APPLOCK_TEST('public', 'myresource', 'Exclusive', 'Transaction');
SELECT APPLOCK_MODE('public', 'myresource', 'Transaction');

-- 释放
EXEC sp_releaseapplock @Resource = 'myresource';
COMMIT TRANSACTION;
```

注意：SQL Server 的咨询锁支持完整的 6 种模式（包括 IS/IX/SIX），是最全的咨询锁实现。

### Oracle DBMS_LOCK

```sql
DECLARE
  lockhandle VARCHAR2(128);
  status     INTEGER;
BEGIN
  -- 分配锁名（持久化到 DBMS_LOCK_ALLOCATED）
  DBMS_LOCK.ALLOCATE_UNIQUE('mylock', lockhandle);

  -- 请求锁 (mode: NL/SS/SX/S/SSX/X)
  status := DBMS_LOCK.REQUEST(
    lockhandle    => lockhandle,
    lockmode      => DBMS_LOCK.X_MODE,
    timeout       => 60,
    release_on_commit => TRUE);

  -- 0=success, 1=timeout, 2=deadlock, 3=parameter error,
  -- 4=already own, 5=illegal handle

  -- 释放
  status := DBMS_LOCK.RELEASE(lockhandle);
END;
```

注意：Oracle DBMS_LOCK 需要显式 EXECUTE 权限，且 11g 起标记为 deprecated（鼓励应用层用 DBMS_PIPE 或显式表锁）。

## 关键发现

1. **Gray 1976 论文奠定了 50 年的锁模型基础**。S/X/U/IS/IX/SIX 这六种基础锁模式，几乎所有传统 OLTP 数据库（SQL Server、DB2、Sybase、Informix、Derby、SAP HANA）都直接采用。Oracle 把意向锁合并到 RX/RS，PostgreSQL 用 8 种命名表锁替代——但本质仍是 Gray 模型的变体。这套设计的优雅之处在于兼容性矩阵的对称性（除了 U 锁的非对称设计是有意为之）。

2. **U 锁是为防止 S→X 升级死锁而生**。"两个事务都先读后改"是 OLTP 的常见模式：T1 持 S 锁、T2 持 S 锁，两者都想升级 X 锁，立即死锁。U 锁的解决方案是：UPDATE 语句的扫描阶段加 U 锁（兼容已有 S，但拒绝新 S），找到目标行后无阻塞升级 X。SQL Server、DB2、Informix、Derby 都实现了 U 锁；MySQL InnoDB、PostgreSQL 都没有原生 U 锁——它们用其他机制（如 InnoDB 的 NOWAIT 重试、PG 的 FOR UPDATE 直接加 X）。

3. **SQL Server 的锁模式是商业引擎中最完整的**。完整的 S/X/U/IS/IX/SIX/IU/SIU/UIX 共 9 种基础模式 + 4 种 Range 锁 = 13 种核心锁模式。这种丰富性来自 SQL Server 长期保持锁基隔离（lock-based isolation）作为默认（而 PostgreSQL/Oracle 早就转向 MVCC）。代价是锁管理器复杂、内存开销大，因此 SQL Server 必须支持锁升级（~5000 行）。

4. **MySQL InnoDB 的 Next-Key Lock 是 REPEATABLE READ 防幻读的核心**。其他引擎在 RR 隔离下要么允许幻读（PG 在 RR 实际是快照隔离），要么用 MVCC（Oracle）。InnoDB 选择"锁基防幻读"——Record Lock + Gap Lock 的组合。这导致 InnoDB 在 RR 下的死锁率比 PG 高，但保证了"数据库行为可预测"（任何范围扫描都不会幻读）。

5. **Gap Lock 在 READ COMMITTED 被禁用是性能优化**。生产环境的 MySQL 实例多数切到 RC 隔离的根本原因：避免 Gap Lock 引起的死锁。代价是失去防幻读能力，但应用层往往可以接受。RC 模式下 InnoDB 仅保留 Record Lock，并发性能显著提升。

6. **SQL Server Range 锁是 SERIALIZABLE 隔离的核心**。RangeS-S/RangeS-U/RangeI-N/RangeX-X 四种 Range 锁组合覆盖了 SERIALIZABLE 下的所有读写场景。但 SQL Server 2005 引入 SNAPSHOT 隔离后，Range 锁的实际使用大幅减少——MVCC 比锁基 SERIALIZABLE 在大多数 OLTP 场景下性能更好。

7. **Oracle 不区分 IS/IX——它把意向锁编码到 RS/RX 中**。这是设计上的简化：RS（Row Share）= "我有 SELECT FOR UPDATE 在某些行上"，RX（Row eXclusive）= "我有 INSERT/UPDATE/DELETE 在某些行上"。意向语义与实际行锁请求合二为一。代价是表级锁的语义稍欠精确，但简化了用户认知（v$lock 视图只有 6 种模式编号）。

8. **PostgreSQL 把意向锁体系包装成 8 种命名表锁**。RowShare ≈ IS、RowExclusive ≈ IX、Share ≈ S、Exclusive ≈ SIX、AccessExclusive = X 等。这种命名比抽象的 IS/IX 更直观，但本质是相同的兼容性矩阵。PG 还在 9.3 引入 NO KEY UPDATE / KEY SHARE 行锁——专门为外键场景设计，避免了"FK 检查 vs 主键无关字段更新"的常见死锁。

9. **Oracle 的"永不升级行锁"是行业独一份**。Oracle 行锁存于数据块的 ITL 槽位中（不消耗独立内存），因此无升级动机。其他实现（SQL Server 5000 行、DB2 LOCKLIST 满）都需要升级以保护 lock manager 内存。代价是 Oracle 必须调高 INITRANS（默认仅 1-2 个 ITL 槽位）以应对热块场景。

10. **SQLite 的 5 种文件级状态是"极简主义"的极致**。整库一把写锁、写者完全串行——这种设计在嵌入式场景下极度高效（无需复杂锁管理器、无死锁、无意向锁），但完全不适合多写并发的 OLTP。WAL 模式仅改善读写并发（读不阻塞写），写仍是串行的。

11. **CockroachDB 用 KV intent + 优先级替代了完整锁模式**。无 IS/IX、无 SIX、无 Range Lock——只有 "intent"（写未提交标记）和 "lock"（FOR UPDATE 后的显式锁）。冲突解决依赖事务优先级 + push txn，避免了分布式 wait-for graph 的复杂性。这是分布式 SQL 对传统锁模式的"减法设计"。

12. **PostgreSQL 咨询锁是被低估的应用层工具**。bigint 键空间允许任意 hash 字符串成键，`pg_try_advisory_lock` 是非阻塞的，事务级版本自动释放——是分布式定时任务、单实例 leader 选举、限流器的优雅实现。MySQL 的 `GET_LOCK` 自 5.7.5 起升级为实例级（之前是会话级），但仍只支持字符串键。SQL Server 的 `sp_getapplock` 是最全的咨询锁实现，支持完整 6 种模式。

13. **Hive 是计算引擎中唯一支持完整 IS/IX 的**。Hive 0.13 引入 ACID 表后，需要协调多个事务的并发写入，因此实现了 Gray 模型的子集。其他计算引擎（Trino、Spark SQL、Flink SQL）完全无锁——它们假设上游存储系统负责并发控制。

14. **Vertica 的 7 级锁阶包含独特的 SI 模式**。Shared with Intent X 模式专门为列存的 UPDATE/DELETE 设计——同时持有读全表（用于 MVCC 验证）和写入意向（用于追加新版本）的语义。这是列存数据库特有的锁模式设计。

15. **DB2 的 Z 锁（Super Exclusive）是最强锁模式**。比 X 锁还强——X 锁仍然兼容 IN（Intent None），Z 锁拒绝一切。Z 锁专用于不能容忍任何并发的 DDL，如 LOAD utility、TRUNCATE。其他引擎多用 ACCESS EXCLUSIVE（PG）或 Sch-M（SQL Server）实现等价语义。

16. **Snowflake/BigQuery/ClickHouse 代表"无锁哲学"**。云数仓和分析引擎用不可变存储 + MVCC + 乐观重试替代了所有传统锁机制。在 OLAP 场景下这是合理的——读多写少、批量更新、追加为主。代价是无法支持点更新热点（同一行高频并发写入），这也是为什么这些引擎都不适合 OLTP。

17. **Schema 锁（Sch-S/Sch-M）是 DDL 与 DML 的同步层**。所有传统 OLTP 数据库都有等价机制：SQL Server 的 Sch-S/Sch-M、MySQL 的 MDL、PostgreSQL 的 AccessShare/AccessExclusive、Oracle 的 Library Cache Lock。云原生引擎（Snowflake/BigQuery/CockroachDB）改用版本化 catalog 替代锁机制——DDL 创建 schema 新版本，旧事务继续读旧版本。详见 [`metadata-locks.md`](./metadata-locks.md)。

18. **键范围锁有两种实现路线**：
    - SQL Server 的 Range Lock：基于已有锁机制，直接锁索引区间
    - PostgreSQL SSI 的 Predicate Lock：追踪读集，提交时检测冲突
    - 第三种是 InnoDB 的 Gap Lock：仅在 REPEATABLE READ 下使用，是 Range Lock 的简化版

19. **意向锁是多粒度锁体系的"占位声明"**。它们的存在不是为了阻塞 DML，而是为了**让表级 LOCK 操作能立即知道"有事务正在使用此表"**。如果没有 IS/IX，LOCK TABLE EXCLUSIVE 必须扫描所有行检查锁——成本爆炸。意向锁让粗粒度锁的检查变成 O(1)。

20. **SQL Server 的 IU/SIU/UIX 是真正的"完整 Gray + U 锁"**。Gray 1976 原始论文未涉及 U 锁的意向版本。SQL Server 是唯一系统实现了 IU 系列的引擎——专门为 SERIALIZABLE 下的 UPDATE 范围扫描设计。其他引擎要么不实现 U 锁（PG/MySQL），要么不实现 U 的意向版本（DB2/Informix）。

## 参考资料

- Gray, J. et al. *Granularity of Locks and Degrees of Consistency in a Shared Database* (IBM Research, 1975) — 锁模式理论的奠基
- [SQL Server Lock Compatibility](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide#lock_compatibility)
- [SQL Server Key-Range Locking](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide#key-range-locking)
- [Oracle TM/TX Lock Modes](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/data-concurrency-and-consistency.html)
- [MySQL InnoDB Locking](https://dev.mysql.com/doc/refman/8.0/en/innodb-locking.html)
- [PostgreSQL Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html)
- [PostgreSQL Advisory Locks](https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS)
- [DB2 Lock Modes](https://www.ibm.com/docs/en/db2/11.5?topic=locks-lock-attributes)
- [Hive Locking](https://cwiki.apache.org/confluence/display/Hive/Locking)
- [SQLite File Locking](https://www.sqlite.org/lockingv3.html)
- [Vertica Locking](https://docs.vertica.com/latest/en/admin/database/transactions/locking/)
- [CockroachDB Locking](https://www.cockroachlabs.com/docs/stable/architecture/transaction-layer.html)
- [Teradata LOCKING Modifier](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Data-Manipulation-Language)
- 相关文章: [`locks-deadlocks.md`](./locks-deadlocks.md), [`lock-escalation.md`](./lock-escalation.md), [`metadata-locks.md`](./metadata-locks.md), [`mvcc-implementation.md`](./mvcc-implementation.md)
