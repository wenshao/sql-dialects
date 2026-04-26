# 锁升级 (Lock Escalation)

一张表上 1 万行的并发更新到底应该持有 1 万把行锁、20 把页锁，还是 1 把表锁？这个看似简单的工程取舍，把数据库引擎切成了三个阵营——主动升级派 (SQL Server / DB2 / Sybase)、永不升级派 (Oracle / PostgreSQL / MySQL InnoDB)、根本没有行锁可升级派 (ClickHouse / Snowflake / BigQuery)。理解这条分歧线，是诊断生产环境锁阻塞、内存压力、并发退化的起点。

锁升级的本质是**用并发度换内存**：每行锁约 100~300 字节，1 万行行锁要消耗 1~3MB 内存，1 亿行就是 10~30GB——这对早期 32 位数据库是灾难性的。SQL Server 和 DB2 选择在锁数量超过阈值时主动转换为表锁，节省内存但牺牲并发；Oracle 和 PostgreSQL 选择把锁信息直接存在数据行内部 (ITL / xmin/xmax)，让锁数量与数据规模无关；MySQL InnoDB 选择独立的锁内存空间但通过 bitmap 紧凑表示。三种思路都各有合理性，但带来截然不同的运维行为。

## 没有 SQL 标准

SQL:1992 / SQL:2008 / SQL:2016 / SQL:2023 标准从未规定锁升级机制——标准甚至不规定锁的存在形式。`FOR UPDATE` 子句只规定了**语义**（防止其他事务修改），不规定实现（行锁/页锁/表锁/MVCC 快照）。这导致：

- **是否升级**完全由引擎决定 (SQL Server、DB2 升级；Oracle、PostgreSQL 不升级)
- **升级阈值**没有统一标准 (SQL Server 5000、DB2 由 LOCKLIST/MAXLOCKS 计算)
- **升级方向**不一致 (SQL Server 直接 row → table，Sybase 经过 row → page → table)
- **是否可禁用**完全是引擎特性 (SQL Server 提供 LOCK_ESCALATION = DISABLE，多数引擎无对应开关)
- **分区表行为**差异巨大 (SQL Server AUTO 模式可升级到分区级，DB2 始终升到表级)

由于缺乏标准，应用代码很难写出"跨引擎正确"的锁管理逻辑——一段在 Oracle 上完美运行的批量更新代码，在 SQL Server 上可能因锁升级导致整表阻塞。这条分歧线的实际影响远超大多数 SQL 方言差异。

## 支持矩阵 (45+ 引擎)

### 行级锁 + 锁升级整体能力

| 引擎 | 行级锁 | 页锁 | 表锁 | 升级阈值可配 | 可禁用升级 | 分区感知升级 | 升级触发条件 |
|------|--------|------|------|------------|----------|------------|------------|
| PostgreSQL | 是 (元组头) | -- | 是 | -- | -- (永不升级) | -- | 永不升级 |
| MySQL InnoDB | 是 (lock space) | -- | 是 | -- | -- (永不升级) | -- | 永不升级 |
| MariaDB (InnoDB) | 是 | -- | 是 | -- | -- | -- | 永不升级 |
| MariaDB (Aria) | -- | 是 | 是 | -- | -- | -- | 仅有页锁 |
| MariaDB (MyISAM) | -- | -- | 是 | -- | -- | -- | 仅有表锁 |
| SQLite | -- | -- | 是 (整库) | -- | -- | -- | 文件级锁 |
| Oracle | 是 (ITL) | -- | 是 (TM) | -- | -- (从不升级) | -- | 从不升级 |
| SQL Server | 是 | 是 | 是 | TF1224 (~5000) | LOCK_ESCALATION = DISABLE | AUTO 模式 | 单语句 5000 锁 |
| Sybase ASE | 是 | 是 | 是 | sp_setpsexe 阈值 | lock scheme datarows | -- | row → page → table |
| DB2 (LUW) | 是 | -- | 是 | LOCKLIST + MAXLOCKS | LOCKLIST 增大 | -- | LOCKLIST 接近上限 |
| DB2 z/OS | 是 | 是 | 是 | LOCKMAX | LOCKMAX 0 | -- | 表级 LOCKMAX 触发 |
| Informix | 是 | 是 | 是 | LOCKS 配置 | -- | -- | row → page → table |
| Firebird | 是 | -- | -- | -- | -- (从不升级) | -- | 从不升级 |
| Snowflake | -- | -- | 是 (隐式) | -- | -- | -- | 无行锁，无升级 |
| BigQuery | -- | -- | -- | -- | -- | -- | 无锁，DML 序列化 |
| Redshift | -- | -- | 是 | -- | -- | -- | 仅表锁 |
| DuckDB | -- | -- | 是 (DB 级) | -- | -- | -- | 单进程，无升级 |
| ClickHouse | -- | -- | 部分元数据 | -- | -- | -- | 无行锁 |
| Trino / Presto | -- | -- | -- | -- | -- | -- | 计算引擎，无锁 |
| Spark SQL | -- | -- | -- | -- | -- | -- | 无锁 |
| Hive | -- | -- | 是 (ZooKeeper) | -- | -- | -- | 仅表/分区锁 |
| Flink SQL | -- | -- | -- | -- | -- | -- | 流处理无锁 |
| Databricks | -- | -- | 是 (Delta) | -- | -- | -- | Delta 乐观并发 |
| Teradata | 是 | -- | 是 | -- | LOCKING ROW | -- | 从不升级 |
| Greenplum | -- | -- | 是 | -- | -- | -- | 主要表级 |
| CockroachDB | 是 (range lock) | -- | -- | -- | -- (从不升级) | -- | 范围锁，无升级 |
| TiDB | 是 | -- | 是 | -- | -- (从不升级) | -- | 从不升级 |
| OceanBase | 是 | -- | 是 | -- | -- | -- | 从不升级 |
| YugabyteDB | 是 | -- | 是 | -- | -- (继承 PG) | -- | 从不升级 |
| SingleStore | 是 | -- | 是 | -- | -- | -- | 从不升级 |
| Vertica | -- | -- | 是 | -- | -- | -- | 仅表锁 |
| Impala | -- | -- | -- | -- | -- | -- | 无锁 |
| StarRocks | -- | -- | 表级元数据 | -- | -- | -- | 无行锁 |
| Doris | -- | -- | 表级元数据 | -- | -- | -- | 无行锁 |
| MonetDB | -- | -- | 是 | -- | -- | -- | 仅表锁 |
| CrateDB | -- | -- | -- | -- | -- | -- | 无锁 |
| TimescaleDB | 是 (继承 PG) | -- | 是 | -- | -- | -- | 从不升级 |
| QuestDB | -- | -- | 是 (writer) | -- | -- | -- | 单写入者，无升级 |
| Exasol | -- | -- | 是 | -- | -- | -- | 仅表锁 |
| SAP HANA | 是 | -- | 是 | global_allocation_limit | -- | -- | 内存压力触发 |
| H2 | 是 (MVStore) | -- | 是 | -- | -- | -- | 从不升级 |
| HSQLDB | 是 (mvcc 模式) | -- | 是 | -- | -- | -- | 从不升级 |
| Derby | 是 | -- | 是 | derby.locks.escalationThreshold | 阈值大值 | -- | 单事务 5000 锁 (默认) |
| Amazon Athena | -- | -- | -- | -- | -- | -- | 无锁 |
| Azure Synapse | -- | -- | 是 | -- | -- | -- | 类似 SQL Server 但简化 |
| Google Spanner | 是 (range) | -- | -- | -- | -- (从不升级) | -- | 范围锁，无升级 |
| Materialize | -- | -- | -- | -- | -- | -- | 流式无锁 |
| RisingWave | -- | -- | -- | -- | -- | -- | 流式无锁 |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | -- | 时序无锁 |
| DatabendDB | -- | -- | 表级元数据 | -- | -- | -- | 无行锁 |
| Yellowbrick | -- | -- | 是 | -- | -- | -- | 仅表锁 |
| Firebolt | -- | -- | -- | -- | -- | -- | 无锁 |

> 统计：45+ 引擎中只有 6 个真正实现锁升级 (SQL Server、Sybase ASE、DB2 LUW、DB2 z/OS、Informix、Derby)，其余要么明确不升级 (Oracle / PostgreSQL / MySQL InnoDB / Firebird / CockroachDB / TiDB)，要么根本没有行锁可升级 (Snowflake / BigQuery / ClickHouse / Trino / Spark)。

### 锁升级方向矩阵

| 引擎 | row → page | row → table | page → table | row → partition | row → 不升级 |
|------|-----------|-------------|--------------|-----------------|-------------|
| SQL Server | -- | 是 | -- | AUTO 模式 | DISABLE 模式 |
| Sybase ASE | 是 (allpages) | 是 | 是 | -- | datarows 模式 |
| DB2 LUW | -- | 是 (大批量) | -- | -- | LOCKLIST 充足时 |
| DB2 z/OS | -- | 是 | 是 (页锁存在) | -- | LOCKMAX 0 |
| Informix | 是 | 是 | 是 | -- | -- |
| Oracle | -- | -- | -- | -- | 从不 (ITL 内嵌) |
| PostgreSQL | -- | -- | -- | -- | 从不 (元组头) |
| MySQL InnoDB | -- | -- | -- | -- | 从不 (lock space) |
| Firebird | -- | -- | -- | -- | 从不 (TIP/TPC) |
| CockroachDB | -- | -- | -- | -- | 从不 (Raft range) |
| Derby | -- | 是 | -- | -- | 阈值未达时 |

### 配置方式与阈值

| 引擎 | 配置参数/语法 | 默认值 | 单位 | 作用域 |
|------|------------|--------|------|--------|
| SQL Server | `ALTER TABLE ... SET (LOCK_ESCALATION = ...)` | TABLE | 模式 | 表级 |
| SQL Server | TF 1224 (跨语句计数禁用) | 关 | bool | 实例 |
| SQL Server | TF 1211 (完全禁用升级) | 关 | bool | 实例 |
| SQL Server | 升级阈值 | 5000 | 锁数 | 单语句 |
| Sybase ASE | `sp_dboption ... 'page locks'` | -- | bool | 库级 |
| Sybase ASE | `lock scheme allpages/datapages/datarows` | datarows (12.5+) | 模式 | 表级 |
| Sybase ASE | `lock promotion HWM` | 200 | 锁数 | 表/库 |
| Sybase ASE | `lock promotion LWM` | 200 | 锁数 | 表/库 |
| Sybase ASE | `lock promotion PCT` | 100 | 百分比 | 表/库 |
| DB2 LUW | `LOCKLIST` | 4096 (4K 页) | 4KB 页 | 数据库 |
| DB2 LUW | `MAXLOCKS` | 10 | 百分比 | 数据库 |
| DB2 z/OS | `LOCKMAX SYSTEM/USER/0` | -- | 锁数 | 表空间/表 |
| DB2 z/OS | `NUMLKTS` | -- | 锁数 | 系统 |
| DB2 z/OS | `NUMLKUS` | -- | 锁数 | 系统 |
| Informix | `LOCKS` 配置参数 | 20000 | 锁数 | 实例 |
| Informix | `LOCK MODE PAGE/ROW` | -- | 模式 | 表级 |
| Derby | `derby.locks.escalationThreshold` | 5000 | 锁数 | 实例 |
| Oracle | -- (无锁升级，无相关配置) | -- | -- | -- |
| PostgreSQL | -- (无锁升级，无相关配置) | -- | -- | -- |
| MySQL InnoDB | -- (无锁升级，无相关配置) | -- | -- | -- |

### LOCK_ESCALATION 语法支持

| 引擎 | 语法 | 选项 | 引入版本 |
|------|------|------|--------|
| SQL Server | `ALTER TABLE t SET (LOCK_ESCALATION = TABLE)` | TABLE / AUTO / DISABLE | 2008 |
| SQL Server | `ALTER TABLE t SET (LOCK_ESCALATION = AUTO)` | -- | 2008 |
| SQL Server | `ALTER TABLE t SET (LOCK_ESCALATION = DISABLE)` | -- | 2008 |
| Sybase ASE | `sp_setpsexe table_name option value` | HWM/LWM/PCT | 12.5+ |
| Sybase ASE | `alter table t lock allpages/datapages/datarows` | 三种模式 | 11.9+ |
| DB2 LUW | `UPDATE DB CFG USING LOCKLIST n MAXLOCKS p` | 间接控制 | V8+ |
| DB2 z/OS | `CREATE TABLESPACE ... LOCKMAX n` | n / SYSTEM / 0 | -- |
| Derby | `derby.locks.escalationThreshold` 系统属性 | 锁数 | 10.0+ |
| Oracle | -- (语法不存在) | -- | 永远 |
| PostgreSQL | -- (语法不存在) | -- | 永远 |
| MySQL | -- (语法不存在) | -- | 永远 |

### 分区表锁升级行为

| 引擎 | 分区表升级粒度 | 是否独立分区锁 | 配置方式 |
|------|--------------|--------------|---------|
| SQL Server | TABLE 模式直接到表级 | -- | LOCK_ESCALATION = TABLE |
| SQL Server | AUTO 模式可升级到分区 | 是 | LOCK_ESCALATION = AUTO |
| Oracle | 永不升级 | 分区独立 ITL | -- |
| PostgreSQL | 永不升级 | 分区独立元组头 | -- |
| DB2 LUW | 表级 LOCKLIST 共享 | -- | -- |
| Sybase ASE | 取决于分区策略 | 部分支持 | -- |
| MySQL InnoDB | 永不升级 | 分区独立 lock space | -- |
| TiDB | 永不升级 | Region 独立锁 | -- |
| CockroachDB | 永不升级 | Range 独立锁 | -- |

## SQL Server：最完整的锁升级实现

### 升级阈值与触发条件

```sql
-- SQL Server 锁升级触发条件 (官方文档):
--   1. 单个语句在单个对象上获取 5000 个锁
--   2. 锁内存超过 sp_configure 'locks' 上限的 40% (动态分配模式)
--   3. 锁内存超过 buffer pool 的 24% (静态分配模式)

-- 查看当前锁数量
SELECT
    OBJECT_NAME(p.object_id) AS table_name,
    request_mode,
    request_status,
    COUNT(*) AS lock_count
FROM sys.dm_tran_locks l
JOIN sys.partitions p ON l.resource_associated_entity_id = p.hobt_id
WHERE resource_type IN ('KEY', 'PAGE', 'OBJECT')
GROUP BY OBJECT_NAME(p.object_id), request_mode, request_status
ORDER BY lock_count DESC;

-- 升级前监控锁阶梯：KEY 锁数量接近 5000 时即将升级
```

### LOCK_ESCALATION 三种模式

```sql
-- TABLE 模式 (默认)：直接升级到表级，忽略分区
ALTER TABLE Sales.SalesOrderDetail SET (LOCK_ESCALATION = TABLE);
-- 5000 个 KEY 锁 → 1 个 X 表锁 (整表阻塞)
-- 适用：小表、低并发、批量操作

-- AUTO 模式：分区表升级到分区，普通表升级到表
ALTER TABLE Sales.SalesOrderDetail SET (LOCK_ESCALATION = AUTO);
-- 仅当表分区且查询限定单分区时升级到分区级
-- 跨分区查询仍升级到表级
-- 适用：大型分区表、需要分区级并发

-- DISABLE 模式：完全禁用锁升级
ALTER TABLE Sales.SalesOrderDetail SET (LOCK_ESCALATION = DISABLE);
-- 即使 100 万行行锁也不升级
-- 风险：lock memory 耗尽，连接报错
-- 适用：极端高并发 OLTP，且锁内存充足
```

### Trace Flag 1224 与 1211

```sql
-- TF 1224：禁用基于"单语句锁数"的升级 (但保留基于内存压力的升级)
DBCC TRACEON(1224, -1);   -- 全局开启
-- 效果：5000 锁阈值不再触发，仅当锁内存超过 40% 时升级
-- 用途：避免大批量 UPDATE/DELETE 因 5000 阈值意外升级

-- TF 1211：完全禁用锁升级 (包括内存压力升级)
DBCC TRACEON(1211, -1);
-- 效果：永不升级，无论多少锁、多少内存
-- 风险：lock memory 耗尽时报错 1204 (Out of locks)
-- 1211 优先级高于 1224

-- 启动时持久化 (注册表或 -T 启动参数)
-- DBCC TRACEON 仅当前实例运行期生效

-- 查看活动 trace flag
DBCC TRACESTATUS(-1);
```

### 升级失败的回退行为

```sql
-- 锁升级是"尝试性"的：如果获取表级 X 锁失败 (其他事务持有冲突锁)
-- 当前事务继续以行/页锁运行
-- 但每 1250 个新锁会再次尝试升级 (称为"escalation retry")

-- 监控升级事件 (SQL Server 2008+)
-- Extended Events: lock_escalation
CREATE EVENT SESSION lock_esc_monitor
ON SERVER
ADD EVENT sqlserver.lock_escalation
(
    ACTION (sqlserver.sql_text, sqlserver.session_id)
    WHERE database_id = DB_ID('YourDB')
)
ADD TARGET package0.event_file (SET filename = 'lock_esc.xel');

ALTER EVENT SESSION lock_esc_monitor ON SERVER STATE = START;
```

### 升级与分区表的交互

```sql
-- AUTO 模式下分区级升级的精确条件:
--   1. 表必须分区
--   2. 查询的 WHERE 必须能让优化器证明只访问单一分区
--   3. 升级到该分区的 X 锁，其他分区不受影响

-- 演示
CREATE PARTITION FUNCTION pf_year (INT) AS RANGE RIGHT FOR VALUES (2024, 2025, 2026);
CREATE PARTITION SCHEME ps_year AS PARTITION pf_year ALL TO ([PRIMARY]);

CREATE TABLE Orders (
    OrderID INT,
    OrderYear INT,
    Amount MONEY
) ON ps_year(OrderYear);

ALTER TABLE Orders SET (LOCK_ESCALATION = AUTO);

-- 这个语句仅升级到 2024 分区，其他分区仍可并发
DELETE FROM Orders WHERE OrderYear = 2024 AND Amount < 100;

-- 这个语句跨分区，升级到整表
DELETE FROM Orders WHERE Amount < 100;
```

## DB2：LOCKLIST 与 MAXLOCKS 联合控制

### 双参数升级模型

```sql
-- DB2 LUW 升级触发条件 (二选一):
--   1. 单事务持有的锁内存 > LOCKLIST * MAXLOCKS / 100
--   2. 数据库整体锁内存 > LOCKLIST (即 100% 用尽)

-- 查看当前配置
GET DB CFG FOR mydb;
-- 输出包含：
--   LOCKLIST = 4096   (单位 4KB 页, 总 16MB)
--   MAXLOCKS = 10     (百分比, 单事务可用 1.6MB)

-- 计算单事务可用锁数:
-- 锁内存 = LOCKLIST * 4096 * MAXLOCKS / 100
--        = 4096 * 4096 * 10 / 100 = 1,677,721 字节
-- 每锁约 96 字节 → 单事务约 17,476 锁

-- 调整 LOCKLIST (DB2 9.5+ 可在线生效)
UPDATE DB CFG FOR mydb USING LOCKLIST 16384;   -- 增加到 64MB
UPDATE DB CFG FOR mydb USING MAXLOCKS 22;      -- 单事务可用 22%
```

### LOCKLIST 自动调整 (STMM)

```sql
-- DB2 9.1+ 引入 Self-Tuning Memory Manager
-- LOCKLIST 设为 AUTOMATIC 时由 STMM 动态调整

UPDATE DB CFG FOR mydb USING LOCKLIST AUTOMATIC;
UPDATE DB CFG FOR mydb USING MAXLOCKS AUTOMATIC;

-- STMM 会观察实际锁使用率：
--   持续接近 100% → 增大 LOCKLIST
--   长期 < 50%   → 缩小 LOCKLIST，释放内存给其他池
-- 调整通常每 30 秒一次，渐进式

-- 监控 STMM 行为
SELECT
    DBPARTITIONNUM,
    LOCKLIST_SIZE,
    MAXLOCKS,
    LOCK_ESCALS,
    LOCK_LIST_IN_USE
FROM TABLE(MON_GET_DATABASE(-1)) AS T;
```

### 升级事件诊断

```sql
-- DB2 升级事件写入 db2diag.log
-- 典型条目:
-- ADM5500W  DB2 is performing lock escalation. The total number of locks
--           currently held is "5234". The target number of locks to hold
--           is "1056".

-- 查看事件历史
SELECT
    EVENT_TIMESTAMP,
    APPLICATION_HANDLE,
    EVENT_TYPE,
    LOCK_ESCALS_SINCE_LAST_EVENT
FROM TABLE(MON_GET_LOCK_ESCALATIONS()) AS T
ORDER BY EVENT_TIMESTAMP DESC;

-- 升级失败 (lock memory 耗尽) 报错 SQL0912N "lock list 已满"
-- 解决：增大 LOCKLIST，或减少事务批量大小
```

### DB2 z/OS 的 LOCKMAX

```sql
-- DB2 z/OS 用 LOCKMAX 直接控制单表升级阈值

CREATE TABLESPACE TS1 IN DB1
    LOCKMAX 1000          -- 单事务在该表 1000 锁触发升级
    LOCKSIZE PAGE;        -- 页锁

-- LOCKMAX SYSTEM: 使用系统默认 (NUMLKTS)
-- LOCKMAX 0:      禁用升级 (类似 SQL Server 的 DISABLE)
-- LOCKMAX n:      指定阈值

ALTER TABLESPACE TS1 LOCKMAX 0;   -- 禁用此表的锁升级
```

## Sybase ASE：三级升级阶梯

### 锁模式选择

```sql
-- Sybase ASE 12.5+ 支持三种锁模式 (lock scheme):
-- allpages: 行级 → 页级 → 表级 (传统)
-- datapages: 仅页级和表级
-- datarows: 仅行级和表级 (默认 12.5.1+)

-- 创建表时指定
CREATE TABLE orders (id INT, amount MONEY)
    LOCK DATAROWS;

-- 改变现有表
ALTER TABLE orders LOCK DATAPAGES;

-- 查看当前设置
sp_help orders;
```

### 升级阈值三参数模型

```sql
-- Sybase ASE 升级由三个参数协同决定:
--   HWM (High Water Mark): 锁数高水位
--   LWM (Low Water Mark):  锁数低水位 (须 >= HWM)
--   PCT (Percent):         占总锁内存的百分比

-- 默认值: HWM=200, LWM=200, PCT=100

-- 升级判定 (单表):
--   IF locks_held >= HWM AND
--     (locks_held >= LWM OR locks_held / total_locks * 100 >= PCT)
--   THEN escalate

-- 设置表级阈值
sp_setpsexe @objname = 'orders',
            @optname = 'lock promotion HWM', @optvalue = 1000;
sp_setpsexe @objname = 'orders',
            @optname = 'lock promotion LWM', @optvalue = 1500;
sp_setpsexe @objname = 'orders',
            @optname = 'lock promotion PCT', @optvalue = 50;

-- 设置数据库级默认 (适用于该 DB 所有表)
sp_dboption mydb, 'lock promotion HWM', 5000;
```

### 升级监控

```sql
-- 查看锁升级统计
sp_sysmon "00:01:00", lockmgmt;
-- 输出包含:
--   Total Lock Promotions   42
--   Page Promotions         30
--   Table Promotions        12
--   Total Promotion Failures 3
```

## Oracle：永不升级的 ITL 设计

### Interested Transaction List (ITL)

```
Oracle 数据块结构 (8KB block 简化):
┌────────────────────────────────────────────┐
│ Block Header (~20 bytes)                   │
├────────────────────────────────────────────┤
│ Transaction Header                         │
│   ITL Slot 1: XID, UBA, Lock, Flag, ...    │ ← 23 字节/槽
│   ITL Slot 2: ...                          │
│   ITL Slot 3: ...                          │
│   ...                                      │
│   ITL Slot N: (INITRANS=1, MAXTRANS=255)   │
├────────────────────────────────────────────┤
│ Free Space                                 │
├────────────────────────────────────────────┤
│ Row Directory                              │
├────────────────────────────────────────────┤
│ Row Data                                   │
│   Row 1: [ Lock Byte | columns... ]        │ ← 锁字节 1 byte
│   Row 2: [ Lock Byte | columns... ]        │
│   ...                                      │
└────────────────────────────────────────────┘
```

每行的"锁字节"指向 ITL 中的某个槽，槽里记录持有者事务 ID (XID)。这意味着：

- **锁信息直接存在数据块里**：不需要独立的锁内存空间
- **锁数量与数据规模无关**：100 万行被锁 = 100 万个锁字节，跟 100 行没有内存差异
- **锁内存就是数据内存**：blocks 在 buffer pool 里，锁信息天然随之
- **永远不需要升级**：因为没有内存压力可言

```sql
-- 查看 ITL 配置
SELECT TABLE_NAME, INI_TRANS, MAX_TRANS
FROM USER_TABLES
WHERE TABLE_NAME = 'ORDERS';

-- 修改 ITL 槽数 (高并发表建议增加 INITRANS)
ALTER TABLE orders INITRANS 8;     -- 预分配 8 个并发事务槽
ALTER TABLE orders MAXTRANS 255;   -- 最多 255 个并发事务

-- ITL 槽不足时新事务会等待 ("ITL waits")
-- 这是 Oracle 高并发热块的典型瓶颈
```

### TX 锁与 TM 锁的二级协议

```sql
-- Oracle 实际有两类锁:
-- TX (Transaction Lock): 事务锁，存在于 ITL 中，标识哪个事务持有
-- TM (Table Lock):       表级 DML 锁，防止 DDL 与 DML 并发

-- 查看锁
SELECT type, lmode, request, sid, id1, id2
FROM v$lock
WHERE type IN ('TX', 'TM');

-- TM 模式:
--   1: NULL    (无锁)
--   2: SS  (Sub-Share, 等价 IS)
--   3: SX  (Sub-eXclusive, 等价 IX)
--   4: S   (Share)
--   5: SSX (Share Sub-eXclusive, 等价 SIX)
--   6: X   (eXclusive)

-- 普通 INSERT/UPDATE/DELETE 持有 TM Mode 3 (SX) + 行级 TX 锁
-- 行级锁数量不会触发升级，因为根本没有"升级"概念
```

### Oracle 设计哲学

Oracle 的 "no lock escalation" 是 1980 年代设计决策的延续。Oracle 7 之前只有表锁，Oracle 7 引入行锁时同步设计了 ITL，从一开始就让"行锁数量"不再是内存约束。这个设计的代价是：

- 数据块内必须预留 ITL 空间，写入密集表常需要更大 INITRANS
- ITL 槽不足会导致 ITL waits，是高并发场景的微妙瓶颈
- 块的有效行数会因 ITL 占用而减少（每槽 23 字节）

但这些代价都局限在物理设计层面，运维不需要担心"突然升级到表锁"这类逻辑行为变化。

## PostgreSQL：xmin/xmax 内嵌的天然无升级

### 元组头中的事务标记

```
PostgreSQL HeapTupleHeader 结构 (23 字节固定 + 可变部分):
┌─────────────────────────────────────────────────┐
│ t_xmin (4 bytes)  ← 创建事务的 XID              │
│ t_xmax (4 bytes)  ← 删除/更新事务的 XID         │
│ t_cid  (4 bytes)  ← Command ID                  │
│ t_ctid (6 bytes)  ← Tuple ID (block_id, offset) │
│ t_infomask2 (2 bytes) ← 字段数 + 标志位         │
│ t_infomask  (2 bytes) ← HEAP_XMIN_FROZEN 等标志│
│ t_hoff (1 byte)       ← Header 长度             │
│ t_bits (变长)         ← NULL bitmap             │
└─────────────────────────────────────────────────┘
```

行锁的实现：
- **共享锁** (FOR SHARE): 在 xmax 中写入"多事务"标识，并在 multixact 表中记录
- **独占锁** (FOR UPDATE): 在 xmax 中直接写入持有事务的 XID
- **当前更新** (UPDATE): xmax = 修改事务 XID

```sql
-- 查看元组头 (需要 pageinspect 扩展)
CREATE EXTENSION IF NOT EXISTS pageinspect;

SELECT t_xmin, t_xmax, t_ctid
FROM heap_page_items(get_raw_page('orders', 0));
```

### multixact 多事务锁

当多个事务对同一行加共享锁时，PG 用 multixact 机制扩展 xmax：

```sql
-- xmax 字段被解释为 multixact ID
-- 真正的多事务列表存在 pg_multixact 子目录中

-- 查看 multixact 状态
SELECT * FROM pg_stat_activity WHERE wait_event_type = 'MultiXactMember';

-- multixact 也有自己的限制:
SHOW autovacuum_multixact_freeze_max_age;
-- 默认 400,000,000，超过会强制 anti-wraparound vacuum
```

### 重锁与表级锁

PostgreSQL 仍有表级锁 (8 种模式)，但行锁完全在元组头中，没有锁升级：

```sql
-- 行锁: 元组头 xmax (与数据存储在一起)
SELECT * FROM orders WHERE id = 1 FOR UPDATE;

-- 表级 IX 锁 (行排他 ROW EXCLUSIVE) 自动获取
-- 即使锁定 100 万行，仍然只是 100 万个 xmax 写入 + 1 个表级 RowExclusive 锁

-- 查看锁
SELECT relation::regclass, mode, granted
FROM pg_locks
WHERE pid = pg_backend_pid();
```

### PostgreSQL 设计哲学

PostgreSQL 跟 Oracle 异曲同工：把锁信息**直接编码在数据本身**。但 PG 用元组头而非独立的 ITL 区域。代价是：
- 每个 UPDATE 实际上是"插入新元组 + 标记旧元组 xmax"，产生 dead tuples 需要 VACUUM
- 长事务阻塞 VACUUM 会导致 bloat
- multixact wraparound 需要监控

但跟 Oracle 一样，"行锁数量与内存压力无关"这个属性彻底消除了锁升级的必要性。

## MySQL InnoDB：独立的紧凑锁空间

### Lock Memory 设计

MySQL InnoDB 的锁存储与 Oracle/PostgreSQL 不同：
- **不在元组头**：InnoDB 的行格式 (COMPACT/DYNAMIC) 没有事务标记字段
- **独立 lock space**：在共享内存中维护独立的锁哈希表
- **bitmap 紧凑存储**：同一页的多行锁用 bitmap 压缩

```
InnoDB 锁结构 (简化):
struct lock_t {
    trx_t*       trx;         // 持有事务
    uint32_t     type_mode;   // 锁类型 + 模式
    space_id_t   space;       // 表空间 ID
    page_no_t    page_no;     // 页号
    rec_id_t     rec_offset;  // 页内偏移 (或 bitmap)
    UT_LIST_NODE_T<lock_t> trx_locks;
    ...
};

// 同一页多行锁: 共享 lock_t 结构 + 页内位图
// 即每页一个 lock_t，用 bitmap 表示该页中哪些行被锁
```

这种设计让 1000 行行锁可能只需要 2~3 个 lock_t 结构 (按页分组)，大大降低内存开销。

### 永不升级的工程理由

```sql
-- InnoDB 永不升级，原因:
--   1. lock_t 紧凑设计，1000 行可能只需几 KB 内存
--   2. 无升级避免了"升级失败回退"的复杂性
--   3. ACID 隔离需要精确的行级冲突检测
--   4. 升级到表锁会破坏 MVCC 读不阻塞写的语义

-- 查看锁内存使用
SELECT
    sum(lock_data) AS total_lock_data,
    count(*) AS total_lock_objects
FROM performance_schema.data_locks;

-- 查看活动锁 (8.0+)
SELECT * FROM performance_schema.data_locks LIMIT 10;
SELECT * FROM performance_schema.data_lock_waits LIMIT 10;
```

### 锁空间的实际边界

```sql
-- innodb_buffer_pool_size 用于 buffer pool
-- 锁内存来自专门的内存池，无显式上限
-- 极端情况：锁内存膨胀导致 OOM Killer 杀进程

-- 监控锁内存
SHOW ENGINE INNODB STATUS\G
-- ROW LOCKS 段显示当前锁数量

SELECT engine_lock_id, lock_status, lock_data
FROM performance_schema.data_locks
WHERE OBJECT_NAME = 'orders'
LIMIT 10;
```

InnoDB 没有 lock memory 的硬上限——它信任锁的紧凑设计能将内存使用控制在合理范围。这与 SQL Server 的"主动节省"哲学截然相反。

## 其他引擎：升级与不升级的两阵营

### Informix：经典三级升级

```sql
-- Informix 默认 LOCKS = 20000 (全局锁数上限)
-- 每个表可独立配置升级行为

-- 表级锁模式
CREATE TABLE orders (...) LOCK MODE PAGE;   -- 默认页锁
CREATE TABLE orders (...) LOCK MODE ROW;    -- 行锁

-- 会话级覆盖
SET LOCK MODE TO WAIT;
SET LOCK MODE TO NOT WAIT;

-- 升级路径:
--   单事务在某表锁数过多 → 该表锁升级为表锁
--   全局 LOCKS 配置接近上限 → 报错 -134
```

### Firebird：MVCC 无升级

```sql
-- Firebird 类似 PostgreSQL，使用 MVCC
-- 每个版本记录在 record version chain 中
-- 行锁信息存在 Transaction State Bitmap (TSB) 中
-- 无锁升级概念

-- 查看锁
SELECT * FROM MON$LOCK_PRINT;
```

### CockroachDB：Range 级锁

```sql
-- CockroachDB 使用 Raft 范围锁
-- 锁存在 LockTable 中，按 range 维护
-- 无 row → table 升级，但有 range split/merge

-- 查看锁
SHOW CLUSTER QUERIES;
SELECT * FROM crdb_internal.cluster_locks;
```

### TiDB：Percolator 模型无升级

```sql
-- TiDB 使用 Percolator 两阶段锁
-- Primary lock + Secondary locks 写入 Lock CF
-- 锁数量与数据规模线性，但无升级机制

-- 查看锁
ADMIN SHOW DDL JOBS;
SELECT * FROM information_schema.tikv_region_status;
```

### ClickHouse：根本没有行锁

```sql
-- ClickHouse 没有事务行锁，因此无锁升级
-- ALTER TABLE 通过 mutation 异步执行
-- 仅有元数据级锁 (READ/WRITE) 用于 DDL 串行化

-- 查看 mutations
SELECT * FROM system.mutations WHERE is_done = 0;

-- 查看元数据锁
SELECT * FROM system.processes;
```

### Snowflake / BigQuery：表级 MVCC

```sql
-- Snowflake: 每个事务对修改的表加表级隐式锁
--   (实际是 micro-partition 的 copy-on-write)
-- 无行锁，无锁升级

-- BigQuery: DML 操作通过快照隔离 + 序列化执行
-- 无显式锁概念

-- 这两种引擎的并发模型是"乐观 + 表级序列化"
-- 与 OLTP 锁模型完全不同维度
```

## 锁升级的成本与收益分析

### 单表操作的锁内存对比

| 锁定行数 | 行锁内存 (Oracle) | 行锁内存 (PG) | 行锁内存 (SQL Server) | 升级后 (SQL Server) |
|---------|------------------|---------------|---------------------|---------------------|
| 1,000 | 0 (ITL 嵌入) | 0 (元组头) | ~96 KB | 不升级 |
| 5,000 | 0 | 0 | ~480 KB | 升级为 1 表锁 (~96 字节) |
| 100,000 | 0 | 0 | -- | 升级 (省 ~9.6 MB) |
| 10,000,000 | 0 | 0 | -- | 升级 (省 ~960 MB) |

### 升级的并发副作用

```
SQL Server 升级前:
  事务 A: UPDATE orders SET status='X' WHERE region='APAC'
  → 持有 4500 KEY 锁 + 表 IX 锁
  → 其他事务可继续访问 region='EU' 的行

SQL Server 升级后 (5001 锁触发):
  事务 A: 升级为 1 表 X 锁
  → 其他事务对 orders 的所有 SELECT/UPDATE/DELETE 全部阻塞
  → 包括跟 APAC 完全无关的查询

升级的代价:
  - 内存节省: 5000 * ~96 = 480 KB
  - 并发损失: 可能阻塞数百个无关事务
  - 阻塞持续时间: 直到事务 COMMIT/ROLLBACK
```

### 何时应该禁用升级

**应该禁用 (LOCK_ESCALATION = DISABLE)**:
- 高并发 OLTP 表 (订单、用户会话)
- lock memory 充足 (服务器有大量内存)
- 业务对锁阻塞极度敏感
- 有完善的锁内存监控

**应该保留升级 (默认 TABLE)**:
- 维护窗口的批量操作 (ETL 加载)
- 内存受限的环境
- 单用户分析查询
- 历史数据清理

**应该用 AUTO 模式**:
- 大型分区表
- 操作通常限定在单分区内
- 跨分区查询较少

## 总结对比矩阵

### 锁升级三大阵营

| 阵营 | 代表引擎 | 锁存储位置 | 升级行为 | 设计哲学 |
|------|---------|-----------|---------|---------|
| 主动升级派 | SQL Server, DB2, Sybase ASE, Informix, Derby | 独立锁内存空间 | 阈值/内存触发 | 用并发换内存 |
| 永不升级派 | Oracle, PostgreSQL | 数据块/元组头内嵌 | 永不升级 | 锁与数据共存 |
| 紧凑无升级派 | MySQL InnoDB, CockroachDB, TiDB | 独立 lock space + bitmap | 永不升级 | 紧凑表示降低成本 |
| 无行锁派 | ClickHouse, Snowflake, BigQuery, Trino, Spark | 仅表/元数据级 | 无升级 | OLAP 无 OLTP 锁需求 |

### 配置可调性总览

| 引擎 | 可配置阈值 | 可禁用升级 | 分区感知 | 监控成熟度 |
|------|----------|----------|---------|----------|
| SQL Server | 否 (固定 5000) | 是 (DISABLE) | 是 (AUTO) | 高 (Extended Events) |
| DB2 LUW | 是 (LOCKLIST/MAXLOCKS) | 间接 (增大) | 否 | 中 (db2diag.log) |
| DB2 z/OS | 是 (LOCKMAX) | 是 (LOCKMAX 0) | 否 | 高 (Trace) |
| Sybase ASE | 是 (HWM/LWM/PCT) | 是 (datarows) | 否 | 中 (sp_sysmon) |
| Informix | 是 (LOCKS) | 否 | 否 | 低 |
| Derby | 是 (escalationThreshold) | 间接 | 否 | 低 |
| Oracle | -- | -- (本来不升级) | -- | -- |
| PostgreSQL | -- | -- (本来不升级) | -- | -- |
| MySQL | -- | -- (本来不升级) | -- | -- |

### 引擎选型建议

| 业务场景 | 推荐引擎/配置 | 理由 |
|---------|-------------|------|
| 高并发 OLTP，锁阻塞敏感 | Oracle / PostgreSQL | 永不升级，无意外阻塞 |
| 高并发 OLTP，必须 SQL Server | SQL Server + LOCK_ESCALATION=DISABLE | 主动控制升级 |
| 大型分区表，分区级并发 | SQL Server + LOCK_ESCALATION=AUTO | 升级到分区不到表 |
| 内存极度受限的小型部署 | SQL Server / DB2 默认 | 升级保护内存 |
| 批量 ETL 加载 | SQL Server 默认 / DB2 默认 | 升级提高吞吐 |
| 云原生 OLAP | Snowflake / BigQuery | 无锁模型，无升级问题 |
| 微秒级延迟分布式 | CockroachDB / TiDB | range 锁，无升级 |
| 时序/日志分析 | ClickHouse | 无行锁，无升级 |

## 关键发现

**1. 锁升级是历史遗留的内存优化**：1980-1990 年代数据库内存稀缺 (32 位系统 4GB 上限)，每行锁 100~300 字节意味着 1000 万行锁就是 1~3GB 的灾难性内存占用。SQL Server 5000 锁阈值就是那个时代的产物。今天 64 位、TB 级内存的服务器，这个阈值已经显得保守。

**2. "永不升级" 不是没有代价**：Oracle 的 ITL 设计需要数据块预留事务槽，写入密集表需要调高 INITRANS 否则会有 ITL waits；PostgreSQL 的元组头 + multixact 机制需要 VACUUM 配合，长事务会引发 bloat。这些都是用其他维度的复杂性换"无升级"的简单性。

**3. SQL Server 的 LOCK_ESCALATION = DISABLE 是高并发救命开关**：很多生产环境的"突然全表阻塞"事件，根本原因都是某个大批量 UPDATE/DELETE 触发了升级。LOCK_ESCALATION = DISABLE 配合充足的 lock memory 是高并发 SQL Server 系统的事实标准配置。

**4. DB2 的 LOCKLIST + MAXLOCKS 是双因子模型**：单事务上限是 LOCKLIST × MAXLOCKS / 100，全局上限是 LOCKLIST。两个参数协同决定升级，比 SQL Server 的"5000 固定值"更灵活但也更难调优。STMM 自动调整减轻了这个负担。

**5. Sybase ASE 的 datarows 模式是唯一保留三级锁的现代实现**：行级 → 页级 → 表级的传统升级路径在 SQL Server 时代已被简化为"行直接到表"，但 Sybase ASE (现 SAP ASE) 仍保留这个完整阶梯。这是 1980 年代锁设计的活化石。

**6. MySQL InnoDB 的 lock_t 紧凑设计走了第三条路**：既不像 Oracle 嵌入数据块，也不像 SQL Server 用大锁结构，而是按页 bitmap 紧凑存储。同一页 1000 行的锁可能只需 2~3 个 lock_t，让"不升级"在工程上可行。

**7. 分区表升级是 SQL Server 独有的精细化控制**：LOCK_ESCALATION = AUTO 让大型分区表的"单分区操作"不影响其他分区。但触发条件严格 (优化器必须证明单分区)，跨分区查询仍升级到表。

**8. Trace Flag 1224 vs 1211 的微妙区别**：TF 1224 仅禁用"5000 锁阈值"触发，保留"内存压力"触发；TF 1211 完全禁用所有升级。生产环境通常推荐 TF 1224，因为彻底禁用 (TF 1211) 可能在内存压力下报 1204 错误。

**9. 云数据仓库整体抛弃了锁升级问题**：Snowflake、BigQuery、ClickHouse、Trino、Spark 这些 OLAP 引擎要么完全无锁 (依赖 MVCC 快照)，要么仅在表级协调，根本不存在"行锁数量过多"的问题。这是过去十年数据库设计哲学的最大转变之一。

**10. 锁升级是引擎可观测性的重要事件**：SQL Server 的 lock_escalation Extended Event、DB2 的 db2diag.log ADM5500W 警告、Sybase 的 sp_sysmon 升级统计——这些都是诊断"突然性能退化"的关键线索。生产监控应该把锁升级事件视为告警级事件，因为它通常预示着并发模型已经退化。

## 参考资料

- SQL Server: [Lock Escalation](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide#lock_escalation)
- SQL Server: [LOCK_ESCALATION ALTER TABLE](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-table-set-statements-transact-sql#lock_escalation)
- SQL Server: [Trace Flag 1211 / 1224](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-traceon-trace-flags-transact-sql)
- DB2 LUW: [LOCKLIST 配置](https://www.ibm.com/docs/en/db2/11.5?topic=parameters-locklist-maximum-storage-lock-list)
- DB2 LUW: [MAXLOCKS 配置](https://www.ibm.com/docs/en/db2/11.5?topic=parameters-maxlocks-maximum-percent-lock-list-before-escalation)
- DB2 z/OS: [LOCKMAX clause](https://www.ibm.com/docs/en/db2-for-zos)
- Sybase ASE: [Lock Schemes](https://infocenter.sybase.com/help/index.jsp)
- Oracle: [Concepts - Locking](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/data-concurrency-and-consistency.html)
- Oracle: [ITL and Block Format](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/logical-storage-structures.html)
- PostgreSQL: [Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html)
- PostgreSQL: [Multixact Members](https://www.postgresql.org/docs/current/routine-vacuuming.html#VACUUM-FOR-MULTIXACT-WRAPAROUND)
- MySQL: [InnoDB Locking](https://dev.mysql.com/doc/refman/8.0/en/innodb-locking.html)
- Informix: [Lock Mode and Locks Configuration](https://www.ibm.com/docs/en/informix-servers)
- Derby: [Lock Escalation](https://db.apache.org/derby/docs/10.16/devguide/cdevconcepts33258.html)
- Firebird: [Transaction Management](https://firebirdsql.org/file/documentation/papers_presentations/Power_Firebird_Transactions.pdf)
- CockroachDB: [Lock Table](https://www.cockroachlabs.com/docs/stable/architecture/transaction-layer.html)
- TiDB: [Pessimistic Lock Implementation](https://docs.pingcap.com/tidb/stable/pessimistic-transaction)
- 相关文章: [locks-deadlocks.md](./locks-deadlocks.md)
- 相关文章: [mvcc-implementation.md](./mvcc-implementation.md)
