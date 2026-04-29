# 嵌套事务 (Nested Transactions)

`BEGIN TRAN` 嵌套了 5 层，最内层的 `ROLLBACK TRAN` 把外层 4 层全部回滚——这是 SQL Server 开发者最容易踩的陷阱之一。"嵌套事务" (nested transactions) 是数据库领域被严重误用的概念：SQL 标准从未真正定义过它，主流引擎几乎都不支持真正的嵌套事务语义，而是用 SAVEPOINT 提供"部分回滚点"作为伪装替代。理解什么是真正的嵌套事务、为什么 SQL 标准回避了它、各引擎的伪嵌套行为差异——这是事务系统开发者和应用架构师都必须掌握的基础。

## SQL 标准的立场

ISO/IEC 9075 SQL 标准从 SQL-92 到 SQL:2023，**从未定义过真正的嵌套事务**。标准中只引入了几个相关概念：

- **SQL:1999** (Section 17.1) 引入了 SAVEPOINT 语句族（`SAVEPOINT` / `ROLLBACK TO SAVEPOINT` / `RELEASE SAVEPOINT`），作为"部分回滚"机制
- **SQL:1999** (Section 17.2) 定义了 CHAINED TRANSACTION (`COMMIT AND CHAIN` / `ROLLBACK AND CHAIN`)，提交后立即开启新事务，但不构成嵌套
- **SQL:2003 / 2011** 引入的事务管理语句仍然只覆盖单一事务模型

真正的"嵌套事务" (Moss 1985, Beeri 1989) 需要满足三个核心特性：

1. **子事务独立提交/回滚**：子事务可以独立于父事务 commit 或 abort
2. **失败隔离**：子事务失败不影响父事务和兄弟子事务
3. **隔离级别独立**：子事务可以设置独立的隔离级别

主流 SQL 数据库**没有任何一个**完整实现这三条。多数引擎用 SAVEPOINT 提供"伪嵌套"——可以部分回滚，但子事务无法独立 commit、无法独立设置隔离级别、与父事务共享同一连接和锁集合。

SQL Server 的 `BEGIN TRAN` / `COMMIT TRAN` 嵌套语法看似支持嵌套事务，**实际上是计数器语义**：只有最外层的 COMMIT 真正提交，任何 ROLLBACK 都会回滚所有层。这是数据库领域最广为流传的"陷阱"之一。

## 支持矩阵（综合）

### 嵌套事务相关能力

| 引擎 | 真正嵌套事务 | SAVEPOINT (SQL:1999) | BEGIN 嵌套语法 | @@TRANCOUNT 类计数器 | 备注 |
|------|------------|---------------------|----------------|-------------------|------|
| PostgreSQL | -- | 是 | 报错 | -- | 嵌套 BEGIN 报 NOTICE，仍然在原事务中 |
| MySQL (InnoDB) | -- | 是 | 隐式提交外层 | -- | START TRANSACTION 隐式提交前序事务 |
| MariaDB (InnoDB) | -- | 是 | 隐式提交外层 | -- | 同 MySQL |
| SQLite | -- | 是 | 报错 | -- | "cannot start a transaction within a transaction" |
| Oracle | -- | 是 | 不支持 | -- | v6 后无 BEGIN TRAN 语法，PL/SQL 块不开启事务 |
| SQL Server | -- (伪嵌套) | `SAVE TRANSACTION` | `BEGIN TRAN` 计数 | `@@TRANCOUNT` | 计数器语义，COMMIT 内层无效 |
| Sybase ASE | -- (伪嵌套) | `SAVE TRANSACTION` | `BEGIN TRAN` 计数 | `@@TRANCOUNT` | 与 SQL Server 一致 |
| DB2 | 部分 (BEGIN ATOMIC) | 是 | 不支持 | -- | BEGIN ATOMIC 是真正原子块 |
| Snowflake | -- | -- | 报错 | -- | 嵌套 BEGIN TRANSACTION 报错 |
| BigQuery | -- | -- | 报错 | -- | 不允许嵌套 BEGIN TRANSACTION |
| Redshift | -- | -- | 报错 | -- | 嵌套 BEGIN 报警告 |
| DuckDB | -- | 是 | 报错 | -- | "transaction is already active" |
| ClickHouse | -- | -- | 报错 | -- | 实验性事务，不支持嵌套 |
| Trino | -- | -- | 报错 | -- | 不支持嵌套 |
| Presto | -- | -- | 报错 | -- | 同 Trino |
| Spark SQL | -- | -- | -- | -- | 无传统事务模型 |
| Hive | -- | -- | -- | -- | ACID 表无嵌套 |
| Flink SQL | -- | -- | -- | -- | 流处理，事务由 checkpoint 实现 |
| Databricks | -- | -- | -- | -- | Delta Lake 文件级事务 |
| Teradata | -- | -- | 隐式提交 | -- | ANSI 模式自动开启 |
| Greenplum | -- | 是 | 报错 | -- | 继承 PG |
| CockroachDB | -- | 是 | 报错 | -- | 嵌套 BEGIN 报错 |
| TiDB | -- | 是 | 隐式提交外层 | -- | MySQL 兼容行为 |
| OceanBase | -- (伪嵌套) | 是 | 看模式 | `@@TRANCOUNT`(SQLServer 模式) | MySQL/Oracle 模式不同 |
| YugabyteDB | -- | 是 | 报错 | -- | 继承 PG |
| SingleStore | -- | -- | 报错 | -- | 不支持嵌套 |
| Vertica | -- | 是 | 报错 | -- | 嵌套 BEGIN 报错 |
| Impala | -- | -- | -- | -- | 无传统事务 |
| StarRocks | -- | -- | -- | -- | 无传统事务模型 |
| Doris | -- | -- | -- | -- | 无传统事务模型 |
| MonetDB | -- | 是 | 报错 | -- | 嵌套 START TRANSACTION 报错 |
| CrateDB | -- | -- | -- | -- | 不支持事务 |
| TimescaleDB | -- | 是 | 报错 | -- | 继承 PG |
| QuestDB | -- | -- | -- | -- | 无事务支持 |
| Exasol | -- | -- | 报错 | -- | 不支持嵌套 |
| SAP HANA | -- | 是 | 报错 | -- | 嵌套 BEGIN TRANSACTION 报错 |
| Informix | 部分 | 是 | 不支持 | -- | 子事务模型 |
| Firebird | -- | 是 | 不支持 | -- | 多事务模型（连接级事务句柄） |
| H2 | -- | 是 | 报错 | -- | 嵌套 BEGIN 报错 |
| HSQLDB | -- | 是 | 报错 | -- | 嵌套 BEGIN 报错 |
| Derby | -- | 是 | 报错 | -- | 嵌套 BEGIN 报错 |
| Amazon Athena | -- | -- | -- | -- | 单语句无事务 |
| Azure Synapse | -- (伪嵌套) | `SAVE TRANSACTION` | `BEGIN TRAN` 计数 | `@@TRANCOUNT` | 继承 SQL Server |
| Google Spanner | -- | -- | -- | -- | 单一读写事务 |
| Materialize | -- | -- | -- | -- | 流式视图 |
| RisingWave | -- | -- | -- | -- | 流处理 |
| InfluxDB (SQL) | -- | -- | -- | -- | 时序无事务 |
| DatabendDB | -- | -- | 报错 | -- | 不支持嵌套 |
| Yellowbrick | -- | 是 | 报错 | -- | 继承 PG |
| Firebolt | -- | -- | -- | -- | 不支持事务嵌套 |
| EDB Postgres | -- | 是 | 报错 | -- | 继承 PG |
| AlloyDB | -- | 是 | 报错 | -- | 继承 PG |
| Aurora (PG) | -- | 是 | 报错 | -- | 继承 PG |
| Aurora (MySQL) | -- | 是 | 隐式提交外层 | -- | 同 MySQL |
| openGauss | -- | 是 | 报错 | -- | PG 衍生 |

> 统计：约 23 个引擎支持 SAVEPOINT 提供"伪嵌套"能力；约 4 个引擎家族（SQL Server、Sybase、Azure Synapse、OceanBase Oracle/SQLServer 兼容模式）支持 `BEGIN TRAN` 计数器语义；约 25+ 个引擎完全不支持任何形式的事务嵌套（包括 OLAP/MPP/流处理引擎）。
>
> **没有任何引擎支持真正的嵌套事务**（子事务独立提交+独立隔离级别+完全失败隔离）。距离最近的是 DB2 BEGIN ATOMIC 块和 PostgreSQL 子事务，但都缺失独立提交语义。

### BEGIN 嵌套时各引擎的具体行为

| 引擎 | 嵌套 BEGIN 行为 | 错误代码/警告 |
|------|----------------|--------------|
| PostgreSQL | NOTICE: there is already a transaction in progress | 25001 |
| MySQL | 隐式 COMMIT 外层 + 开启新事务 | 静默 |
| MariaDB | 隐式 COMMIT 外层 + 开启新事务 | 静默 |
| SQL Server | @@TRANCOUNT++（计数器嵌套） | 静默 |
| Oracle | 不存在 BEGIN TRAN 语法 | -- |
| DB2 | 不存在 BEGIN TRAN 语法 | SQL0001N（部分版本） |
| SQLite | "cannot start a transaction within a transaction" | SQLITE_ERROR |
| DuckDB | "TransactionContext Error: Cannot start a transaction within a transaction" | -- |
| Snowflake | "Begin transaction can only be used outside of an existing transaction" | 002000 |
| BigQuery | "BEGIN TRANSACTION cannot be invoked from within an existing transaction" | -- |
| ClickHouse | "TransactionsInfo: Active transaction" | 49 |
| Trino/Presto | "Already in transaction" | -- |
| Vertica | "Cannot begin a transaction inside a transaction" | -- |
| H2 | 静默忽略（已经在事务中） | -- |
| HSQLDB | 静默忽略 | -- |
| CockroachDB | "there is already a transaction in progress" | 25001 |

### CHAINED TRANSACTION (SQL:1999)

| 引擎 | COMMIT AND CHAIN | ROLLBACK AND CHAIN | 与嵌套关系 |
|------|-----------------|-------------------|-----------|
| PostgreSQL | 是 (12+) | 是 (12+) | 不构成嵌套，而是连续单事务 |
| MySQL | 是 | 是 | 同上 |
| MariaDB | 是 | 是 | 同上 |
| SQL Server | -- | -- | 不支持 |
| Oracle | -- | -- | 用 SET TRANSACTION 手动 |
| DB2 | -- | -- | 不支持 |

### 与 PG 子事务限制相关参数

| 参数 | 默认值 | 含义 | 影响 |
|------|-------|------|------|
| 每后端缓存子事务 XID | 64 | PGPROC.subxids 数组上限 | 超过后触发 subxid overflow |
| pg_subtrans SLRU buffers | 32 (PG 13-) / 配置化 (PG 14+) | 子事务父链缓存 | 大量子事务导致 SLRU 抖动 |
| max_xact_id (xidStopLimit) | 2^31 - 1M | 防止 XID 回卷的硬限制 | 子事务消耗 XID 加速回卷 |
| autovacuum_freeze_max_age | 200M | 触发强制 vacuum 阈值 | 子事务多导致 vacuum 频繁 |

## 真正的嵌套事务 vs SAVEPOINT vs BEGIN 计数嵌套

### 概念对比

```
真正嵌套事务 (Moss 1985):
    BEGIN T1
        BEGIN T2 (T1 的子事务)
            INSERT...
            COMMIT T2  -- 子事务独立提交（变更对父事务可见，但仍未对外提交）
        BEGIN T3 (T1 的子事务)
            UPDATE...
            ROLLBACK T3  -- 子事务独立回滚（不影响 T2 已提交的变更）
        SELECT...
        COMMIT T1  -- 整体提交，所有内层变更对外可见

SAVEPOINT (SQL:1999):
    BEGIN T1
        SAVEPOINT sp1
            INSERT...
            -- "RELEASE SAVEPOINT sp1" 不是独立提交，只是释放保存点
            -- 变更对外可见性取决于 T1 是否最终 COMMIT
        SAVEPOINT sp2
            UPDATE...
            ROLLBACK TO sp2  -- 只回滚 sp2 之后的变更
        COMMIT T1  -- 必须依赖外层提交才能让所有变更生效

BEGIN 计数嵌套 (SQL Server):
    BEGIN TRAN              -- @@TRANCOUNT = 1
        BEGIN TRAN          -- @@TRANCOUNT = 2 (但语义上不是子事务)
            INSERT...
            COMMIT TRAN     -- @@TRANCOUNT = 1 (内层 COMMIT 是 NOOP)
        ROLLBACK TRAN       -- @@TRANCOUNT = 0 (回滚整个！包括内层)
    -- 此时无活跃事务，外层 COMMIT 报错
```

### 三种语义的关键差异表

| 语义 | 子事务独立 COMMIT | 子事务失败隔离 | 内层 ROLLBACK 影响外层 | 共享锁集 | 共享连接 |
|------|------------------|---------------|----------------------|---------|---------|
| 真正嵌套（理论） | 是 | 是 | 否 | 否（子事务独立） | 否 |
| 真正嵌套（OS 学术原型） | 是 | 是 | 否 | 部分共享 | 看实现 |
| SAVEPOINT | -- (RELEASE 不是 commit) | 是（部分回滚） | 否（仅级联到子保存点） | 是（共享） | 是 |
| BEGIN 计数嵌套 | -- (内层 COMMIT 无效) | -- | 是（一次性全部回滚） | 是 | 是 |
| 自治事务 (Oracle) | 是 | 是 | 否 | 否（独立 undo） | 是（同物理连接） |

## SQL Server：伪嵌套事务深度解析

SQL Server 的 `BEGIN TRAN` 嵌套是数据库领域最经典的**反面教材**。它从 Sybase 时代继承的语法允许嵌套，但语义完全不是嵌套事务。

### @@TRANCOUNT 系统变量

```sql
-- @@TRANCOUNT 是 INT 类型，记录当前会话事务"嵌套深度"
SELECT @@TRANCOUNT;  -- 0（初始无事务）

BEGIN TRAN;
SELECT @@TRANCOUNT;  -- 1

BEGIN TRAN;
SELECT @@TRANCOUNT;  -- 2 (嵌套)

BEGIN TRAN inner_tx;
SELECT @@TRANCOUNT;  -- 3

COMMIT TRAN;          -- @@TRANCOUNT = 2 (内层 COMMIT 是 NOOP, 仅减少计数)
COMMIT TRAN;          -- @@TRANCOUNT = 1
COMMIT TRAN;          -- @@TRANCOUNT = 0 (此时才真正提交！)
```

关键事实：
- `@@TRANCOUNT` 只是一个**计数器**，不代表真正的事务栈
- 内层 `BEGIN TRAN` 仅做 `@@TRANCOUNT++`，**不开启新事务**
- 内层 `COMMIT TRAN` 仅做 `@@TRANCOUNT--`，**不提交任何变更**
- 只有最外层 `COMMIT TRAN`（让 `@@TRANCOUNT` 归零）才真正提交
- **任何 `ROLLBACK TRAN` 立即把 `@@TRANCOUNT` 归零**，回滚所有层

### 经典陷阱 1：内层 ROLLBACK 全盘回滚

```sql
BEGIN TRAN;            -- @@TRANCOUNT = 1
INSERT INTO orders VALUES (1, 'Outer');

    BEGIN TRAN;        -- @@TRANCOUNT = 2
    INSERT INTO orders VALUES (2, 'Inner');
    ROLLBACK TRAN;     -- @@TRANCOUNT = 0 (一刀切！)
                       -- (1, 'Outer') 也被回滚了！

COMMIT TRAN;           -- 错误！3902: COMMIT TRAN 与 BEGIN TRAN 不匹配
                       -- 因为 @@TRANCOUNT 已经是 0
```

这是 SQL Server 开发者最常见的错误。期望"只回滚内层"必须使用 `SAVE TRANSACTION` + `ROLLBACK TRAN savepoint_name`：

```sql
BEGIN TRAN;
INSERT INTO orders VALUES (1, 'Outer');
SAVE TRANSACTION sp_inner;     -- 创建保存点（不增加 @@TRANCOUNT）
INSERT INTO orders VALUES (2, 'Inner');
ROLLBACK TRAN sp_inner;        -- 回滚到保存点（@@TRANCOUNT 不变）
COMMIT TRAN;                   -- 正确提交 (1, 'Outer')
```

### 经典陷阱 2：命名 BEGIN TRAN 误以为创建保存点

```sql
BEGIN TRAN outer_tx;
INSERT INTO t VALUES (1);
    BEGIN TRAN inner_tx;       -- 这只是给嵌套起了个名字（被忽略）
    INSERT INTO t VALUES (2);
    ROLLBACK TRAN inner_tx;    -- 错误！3903: 找不到名为 'inner_tx' 的事务
                               -- ROLLBACK TRAN with name 只对 SAVE TRAN 名字有效
```

`BEGIN TRAN tx_name` 中的 tx_name 仅作为最外层事务名，对内层没有任何意义。`ROLLBACK TRAN tx_name` 只能匹配 `SAVE TRAN tx_name` 创建的保存点。

### 经典陷阱 3：触发器内 ROLLBACK

```sql
CREATE TRIGGER trg_audit ON orders AFTER INSERT
AS
BEGIN
    IF EXISTS (SELECT 1 FROM inserted WHERE total < 0)
        ROLLBACK TRAN;  -- 整个调用栈的事务全部回滚！
END;

BEGIN TRAN;
INSERT INTO orders VALUES (1, -100);  -- 触发器 ROLLBACK
                                       -- @@TRANCOUNT = 0
INSERT INTO orders VALUES (2, 50);     -- 这条 INSERT 在自动隐式事务中
                                       -- 实际上立即提交（可能不是预期行为）
COMMIT TRAN;  -- 错误：没有事务可提交
```

触发器内的 ROLLBACK 会同时回滚触发它的语句和外层所有事务，并把控制流交还给客户端，常导致难以排查的会话状态问题。

### XACT_ABORT 与 XACT_STATE()

```sql
SET XACT_ABORT ON;  -- 任何运行时错误立即整体回滚
BEGIN TRAN;
    INSERT INTO t VALUES (1);
    INSERT INTO t VALUES ('not_an_int');  -- 类型错误
    -- @@TRANCOUNT = 0，整个事务已被引擎自动回滚
COMMIT TRAN;  -- 错误

-- XACT_STATE() 返回事务"健康度"
-- 1 = 可提交事务
-- 0 = 无事务
-- -1 = "doomed" 事务（无法提交，只能 ROLLBACK）
BEGIN TRY
    BEGIN TRAN;
    -- ...
    SELECT @@TRANCOUNT, XACT_STATE();
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() = -1
        ROLLBACK;        -- 必须 ROLLBACK，无法 COMMIT
    ELSE IF XACT_STATE() = 1
        COMMIT;          -- 仍可提交
END CATCH;
```

### 推荐的 SQL Server 嵌套事务模式

```sql
CREATE PROCEDURE sp_safe_inner_op
AS
BEGIN
    DECLARE @already_in_tx BIT = CASE WHEN @@TRANCOUNT > 0 THEN 1 ELSE 0 END;

    IF @already_in_tx = 0
        BEGIN TRAN;
    ELSE
        SAVE TRAN sp_inner;  -- 调用方已开启事务，这里创建保存点

    BEGIN TRY
        -- 业务逻辑
        INSERT INTO t VALUES (1);

        IF @already_in_tx = 0
            COMMIT TRAN;
        -- 调用方已开启事务，不 COMMIT，由调用方决定
    END TRY
    BEGIN CATCH
        IF @already_in_tx = 0
            -- 自己开启的事务，可以全部回滚
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        ELSE
            -- 调用方的事务，只回滚到保存点
            IF XACT_STATE() = 1 ROLLBACK TRAN sp_inner;
            ELSE THROW;  -- 事务 doomed，向上抛出
        THROW;  -- 重新抛出异常
    END CATCH;
END;
```

这种模式（"是否需要新建事务取决于调用上下文"）在 ORM 框架中非常常见——Spring/.NET 的 `Required` 传播模式就是这个语义。

## PostgreSQL：真正嵌套不可能，子事务=SAVEPOINT

PostgreSQL 是少数明确告诉开发者"我们不支持嵌套事务"的引擎。

### 嵌套 BEGIN 报警告

```sql
BEGIN;
INSERT INTO t VALUES (1);
BEGIN;  -- WARNING: there is already a transaction in progress
        -- 当前事务状态不变，仍是同一事务
COMMIT; -- 提交整个事务
```

PostgreSQL 不会报错（仅 WARNING），但第二个 `BEGIN` 是无操作 (NOOP)。这种设计有助于客户端代码在不知道是否已开启事务时安全调用。

### 子事务 = SAVEPOINT 的实现

PostgreSQL 内部用**子事务 (subtransaction)** 实现 SAVEPOINT。每个 SAVEPOINT 创建一个独立的 virtual transaction ID (vXID)：

```
主事务 XID = 1000
├─ SAVEPOINT sp1 → 子事务 XID = 1001
│  ├─ SAVEPOINT sp2 → 子事务 XID = 1002
│  └─ SAVEPOINT sp3 → 子事务 XID = 1003
└─ ...

每个元组的 xmin/xmax 记录写入时的 XID（可以是子事务）
pg_subtrans 文件跟踪父子关系：1001→1000, 1002→1001
MVCC 可见性判断时：先查元组 XID，若是子事务则递归查找根事务
```

子事务的关键性质：
- 每个子事务消耗一个 XID（与主事务并列分配）
- 子事务不能独立提交（RELEASE 仅释放保存点，变更仍属于父事务）
- 子事务可以独立回滚（ROLLBACK TO 撤销自该 SAVEPOINT 之后的变更）
- 子事务持有的锁与父事务合并（不是独立锁集）

### 64 个子事务的"软上限"

PostgreSQL 中**每个后端进程（PGPROC 结构）只能缓存 64 个子事务 XID**。超过 64 个时触发 "subxid overflow"，后续的子事务 XID 不再缓存在共享内存，而是只能通过查询 pg_subtrans SLRU 文件获取：

```c
// src/include/storage/proc.h
#define PGPROC_MAX_CACHED_SUBXIDS 64

typedef struct XidCache {
    TransactionId xids[PGPROC_MAX_CACHED_SUBXIDS];
} XidCache;

typedef struct PGPROC {
    // ...
    XidCache    subxids;          // 缓存的子事务 XID
    bool        subxidStatus.overflowed;  // 是否溢出
    // ...
} PGPROC;
```

溢出后的影响：
- **快照计算变慢**：每次需要计算 visibility 时，必须读取 pg_subtrans 文件来识别父子关系
- **pg_subtrans SLRU 抖动**：默认仅 32 个 SLRU buffer，大量子事务下命中率骤降
- **vacuum 推进受阻**：长事务 + 大量子事务延迟 vacuum_xmin 推进
- **可能波及所有会话**：一个会话的 subxid overflow 会让所有会话的快照计算变慢

```sql
-- 性能问题示例：大循环中的异常处理
DO $$
BEGIN
    FOR i IN 1..100000 LOOP
        BEGIN
            INSERT INTO t VALUES (i);
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;
    END LOOP;
END; $$;
-- 每次 BEGIN/EXCEPTION 创建子事务
-- 100000 个子事务 → pg_subtrans 严重抖动 → 慢数十倍
-- 推荐改为 INSERT ... ON CONFLICT DO NOTHING（单语句）
```

GitLab 在 2021 年因子事务 overflow 导致全站性能下降的事件，让 PG 子事务问题广为人知。社区在 PG 14/15/16 中陆续优化 SLRU 性能，但根本问题——`PGPROC_MAX_CACHED_SUBXIDS` 硬编码为 64——仍未解决。

### xidStopLimit 与子事务 XID 消耗

```sql
-- PostgreSQL 的 32-bit XID 限制
-- 每个事务（包括子事务）消耗一个 XID
-- 当 XID 即将耗尽时，触发 xidStopLimit:
--   max_xid_age - 1M = xidStopLimit (默认 2^31 - 1M = ~2.1B)
--   超过此值后所有非 vacuum 操作被拒绝

SELECT datname, age(datfrozenxid) FROM pg_database;
-- 显示每个数据库距离 XID 回卷还有多少 XID 可用
```

子事务对 XID 消耗的影响：
- 单个事务带 100 个 SAVEPOINT → 消耗 101 个 XID（主事务 + 100 子事务）
- 高并发 + 异常处理循环 → XID 消耗加速 → vacuum 压力增大
- 大型业务系统中，子事务可能贡献 30%+ 的 XID 消耗

### PostgreSQL 推荐做法

```sql
-- 1) 避免在循环中使用 BEGIN/EXCEPTION 块
-- 错误模式：
DO $$
BEGIN
    FOR i IN 1..1000000 LOOP
        BEGIN INSERT INTO t VALUES (i); EXCEPTION WHEN unique_violation THEN NULL; END;
    END LOOP;
END; $$;

-- 推荐模式：
INSERT INTO t SELECT generate_series(1, 1000000)
ON CONFLICT (id) DO NOTHING;

-- 2) 监控 subxid overflow
SELECT pid, backend_xid, backend_xmin, state
FROM pg_stat_activity WHERE state = 'active';
-- 配合查看 pg_stat_slru 视图（PG 13+）

-- 3) 使用 CTE / 单语句而非显式保存点
WITH inserted AS (
    INSERT INTO target SELECT * FROM staging WHERE valid
    RETURNING id
)
INSERT INTO log SELECT id, 'imported' FROM inserted;
```

## MySQL / MariaDB：嵌套 BEGIN 隐式提交

MySQL 的 `BEGIN` / `START TRANSACTION` 语句**永远先隐式提交当前事务**，再开启新事务：

```sql
START TRANSACTION;
INSERT INTO t VALUES (1);

START TRANSACTION;  -- 隐式 COMMIT 上面的事务！(1) 已经持久化
INSERT INTO t VALUES (2);

ROLLBACK;  -- 仅回滚 (2)，(1) 仍存在
```

这种行为意味着 MySQL **完全不允许事务嵌套**，连计数器嵌套都没有。开发者必须用 SAVEPOINT 实现嵌套语义：

```sql
START TRANSACTION;
INSERT INTO t VALUES (1);
SAVEPOINT sp_inner;
INSERT INTO t VALUES (2);
ROLLBACK TO SAVEPOINT sp_inner;  -- 仅回滚 (2)
COMMIT;
```

### MySQL 的 DDL 隐式提交

更隐蔽的问题：MySQL 中**所有 DDL 语句（CREATE/DROP/ALTER）都隐式 COMMIT 当前事务**：

```sql
START TRANSACTION;
INSERT INTO t VALUES (1);
CREATE TABLE tmp(x INT);  -- 隐式 COMMIT！(1) 已持久化
INSERT INTO t VALUES (2);
ROLLBACK;  -- 仅回滚 (2)
```

这与 PostgreSQL 等支持事务化 DDL 的引擎形成鲜明对比。

## Oracle：v6 后无 BEGIN TRAN 语法

Oracle 从 v6 (1988) 开始就**不再支持显式 `BEGIN TRANSACTION` 语法**。所有 DML 语句自动开启隐式事务，直到遇到 `COMMIT` 或 `ROLLBACK`。

```sql
-- Oracle 中没有 BEGIN TRAN 这条语句
-- 隐式事务模型：
INSERT INTO t VALUES (1);  -- 自动开启事务
INSERT INTO t VALUES (2);
COMMIT;                    -- 提交整个事务
-- 下一条 DML 自动开启新事务
```

### Oracle 的 SET TRANSACTION

Oracle 用 `SET TRANSACTION` 设置事务属性，**不开启新事务**：

```sql
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- 设置后续事务的隔离级别，但不开启嵌套
INSERT INTO t VALUES (1);
COMMIT;
```

### PL/SQL 块不开启新事务

Oracle PL/SQL 的 BEGIN/END 块**不开启新事务**：

```sql
-- 错误印象：以为 PL/SQL 的 BEGIN 是事务边界
BEGIN
    INSERT INTO t VALUES (1);
    -- 这里没有事务边界变化
    BEGIN
        INSERT INTO t VALUES (2);
    END;
    -- 还是同一事务
    COMMIT;
END;
/
```

PL/SQL 的 BEGIN/END 仅是**词法块**，与事务边界无关。如果块内调用 SAVEPOINT，则保存点跨块作用：

```sql
DECLARE
    e_custom EXCEPTION;
BEGIN
    INSERT INTO t VALUES (1);
    SAVEPOINT sp_outer;
    BEGIN
        INSERT INTO t VALUES (2);
        SAVEPOINT sp_inner;
        INSERT INTO t VALUES (3);
        RAISE e_custom;
    EXCEPTION
        WHEN e_custom THEN
            ROLLBACK TO SAVEPOINT sp_inner;
            -- 仅回滚 (3)；(2) 保留
    END;
    COMMIT;  -- 提交 (1), (2)
END;
/
```

### PRAGMA AUTONOMOUS_TRANSACTION：真正的"独立事务"

Oracle 唯一支持真正"独立事务"的方式是 `PRAGMA AUTONOMOUS_TRANSACTION`，但这不是嵌套事务，而是**自治事务**——它完全脱离父事务的提交/回滚边界：

```sql
CREATE OR REPLACE PROCEDURE log_event(p_msg VARCHAR2) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO audit_log VALUES (SYSTIMESTAMP, p_msg);
    COMMIT;  -- 自治事务的 COMMIT 独立生效
END;
/

-- 调用方
BEGIN
    INSERT INTO orders VALUES (1);
    log_event('order created');  -- 独立事务，立即提交
    ROLLBACK;  -- 仅回滚 orders 的 INSERT；audit_log 已提交
END;
/
```

这与嵌套事务的语义完全不同。详见 `autonomous-transactions.md`。

## DB2：BEGIN ATOMIC（最接近真正嵌套）

DB2 不支持 `BEGIN TRANSACTION` 语法（与 Oracle 类似的隐式事务模型），但提供 `BEGIN ATOMIC` / `END` 块作为**真正的原子嵌套块**：

```sql
CREATE PROCEDURE outer_proc()
BEGIN
    INSERT INTO t VALUES (1);

    BEGIN ATOMIC    -- 嵌套原子块（不是新事务，但是原子单元）
        INSERT INTO t VALUES (2);
        INSERT INTO t VALUES (3);
        -- 块内任何语句失败 → 整个 ATOMIC 块原子回滚
        -- 但外层事务的 (1) 不受影响
    END;

    INSERT INTO t VALUES (4);
    COMMIT;
END;
```

### BEGIN ATOMIC 的特性

- **原子性**：块内所有语句要么全部成功，要么全部回滚
- **嵌套**：可以嵌套多层 BEGIN ATOMIC 块
- **失败隔离**：内层块失败不会自动回滚外层
- **不是真正子事务**：内层不能独立提交（COMMIT 仍提交整个外层事务）

```sql
CREATE PROCEDURE multi_step_import(IN p_batch_id INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            INSERT INTO error_log VALUES (p_batch_id, 'failed');
            -- 此处 SQLEXCEPTION 已使外层 ATOMIC 块整体回滚
        END;

    BEGIN ATOMIC
        INSERT INTO step1 SELECT * FROM staging WHERE batch_id = p_batch_id;
        BEGIN ATOMIC
            -- 内层块：转换数据
            UPDATE step1 SET val = val * 1.1 WHERE batch_id = p_batch_id;
            -- 如果失败，仅内层 ATOMIC 块回滚，外层继续
        END;
        INSERT INTO step2 SELECT * FROM step1 WHERE batch_id = p_batch_id;
    END;
    COMMIT;
END;
```

### DB2 的链式嵌套（CHAINED 类）

DB2 支持 SAVEPOINT 实现"伪嵌套"：

```sql
CALL sp_outer_logic;  -- 不开启新事务，使用调用方事务

CREATE PROCEDURE sp_outer_logic()
BEGIN
    INSERT INTO t VALUES (1);
    SAVEPOINT sp_inner ON ROLLBACK RETAIN CURSORS;
    INSERT INTO t VALUES (2);
    -- 业务校验失败
    ROLLBACK TO SAVEPOINT sp_inner;
    -- 仅回滚 (2)；(1) 保留
    RELEASE SAVEPOINT sp_inner;
END;
```

DB2 SAVEPOINT 子句：
- `ON ROLLBACK RETAIN CURSORS`：回滚时保留游标（默认）
- `ON ROLLBACK RETAIN LOCKS`：回滚时保留锁（默认）
- `UNIQUE`：要求保存点名字唯一（重复则报错）

## CockroachDB：分布式 SAVEPOINT

CockroachDB 的嵌套支持经历了漫长演进：

- **19.2 之前**：仅支持特殊的 `cockroach_restart` 内置保存点（用于序列化重试）
- **20.1 (2020)**：全面支持 SQL:1999 标准 SAVEPOINT / ROLLBACK TO / RELEASE
- **20.2+**：支持嵌套保存点

```sql
-- 早期 cockroach_restart 模式（用于客户端重试 40001 错误）
BEGIN;
SAVEPOINT cockroach_restart;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
-- 遇到 40001 serialization_failure：
ROLLBACK TO SAVEPOINT cockroach_restart;
-- 重试事务
COMMIT;

-- 现代通用 SAVEPOINT（20.1+）
BEGIN;
INSERT INTO orders VALUES (1);
SAVEPOINT sp1;
INSERT INTO orders VALUES (2);
ROLLBACK TO SAVEPOINT sp1;
COMMIT;

-- 嵌套 BEGIN 报错
BEGIN; BEGIN;
-- ERROR: there is already a transaction in progress
```

CockroachDB 的分布式特性使得 SAVEPOINT 实现更复杂：
- **跨节点协调**：ROLLBACK TO 需要撤销分布式写入的时间戳
- **MVCC 与 KV 层**：保存点对应 KV 层的"intent" 时间戳栅栏
- **事务重启**：序列化失败时的保存点处理需要协调器配合

## SQLite：无嵌套，全靠 SAVEPOINT

SQLite 完全不支持嵌套 BEGIN（会报错），但提供完整的 SAVEPOINT 三元组，并且 SAVEPOINT 可以**在无事务时使用**（隐式开启事务）：

```sql
-- SQLite 独特语义：SAVEPOINT 可以隐式开启事务
SAVEPOINT my_outer;  -- 自动开启事务
INSERT INTO t VALUES (1);
SAVEPOINT my_inner;
INSERT INTO t VALUES (2);
RELEASE my_outer;     -- 释放最外层等同于 COMMIT
                      -- my_inner 被级联释放

-- 嵌套 BEGIN 报错
BEGIN; BEGIN;
-- Error: cannot start a transaction within a transaction
```

SQLite 的 SAVEPOINT 实现通过 journal/WAL 文件：每个保存点记录当前 journal 位置，ROLLBACK TO 根据 journal 回放。

## TiDB / OceanBase：MySQL 兼容陷阱

### TiDB（继承 MySQL 隐式提交语义）

```sql
-- TiDB 6.2+ 支持 SAVEPOINT
BEGIN;
INSERT INTO t VALUES (1);
SAVEPOINT sp1;
INSERT INTO t VALUES (2);
ROLLBACK TO SAVEPOINT sp1;
COMMIT;

-- 嵌套 BEGIN：MySQL 兼容行为，隐式 COMMIT 外层
BEGIN;
INSERT INTO t VALUES (1);
BEGIN;  -- 隐式 COMMIT 外层
INSERT INTO t VALUES (2);
ROLLBACK;  -- 仅回滚 (2)
```

TiDB 6.2 之前**完全不支持 SAVEPOINT**，给 MySQL 兼容性带来挑战。

### OceanBase（双模式）

OceanBase 在 MySQL 模式下行为与 MySQL 一致；在 Oracle 模式下行为与 Oracle 一致；在 SQL Server 兼容模式下支持 `@@TRANCOUNT`：

```sql
-- MySQL 模式
BEGIN;
SAVEPOINT sp1;
INSERT INTO t VALUES (1);
ROLLBACK TO SAVEPOINT sp1;
COMMIT;

-- Oracle 模式
INSERT INTO t VALUES (1);
SAVEPOINT sp1;
INSERT INTO t VALUES (2);
ROLLBACK TO SAVEPOINT sp1;  -- 仅回滚 (2)
COMMIT;

-- SQL Server 兼容模式
BEGIN TRAN;
SELECT @@TRANCOUNT;  -- 1
BEGIN TRAN;
SELECT @@TRANCOUNT;  -- 2
COMMIT TRAN;  -- @@TRANCOUNT = 1
COMMIT TRAN;  -- @@TRANCOUNT = 0
```

## YugabyteDB / Greenplum / TimescaleDB：继承 PG

PostgreSQL 衍生品（YugabyteDB / Greenplum / TimescaleDB / Aurora PG / AlloyDB / EDB Postgres / openGauss）继承 PG 的 SAVEPOINT 行为和子事务限制：

- 嵌套 BEGIN 仅打 NOTICE，不报错
- SAVEPOINT 实现为子事务
- 受 64 子事务缓存上限影响

YugabyteDB 在分布式环境下，子事务实现更复杂：
- 每个 SAVEPOINT 分配独立的 TxnStatusTablet 条目
- 跨节点 SAVEPOINT 协调通过 Raft 日志同步
- 大量子事务对元数据存储造成压力

## OLAP / MPP 引擎：完全不支持

Snowflake、BigQuery、Redshift、ClickHouse、Trino、Spark SQL、Hive、Databricks、Impala、StarRocks、Doris 等 OLAP/MPP 引擎**完全不支持任何形式的事务嵌套**（包括 SAVEPOINT 和 BEGIN 嵌套）。

### Snowflake

```sql
-- Snowflake 不支持 SAVEPOINT
BEGIN TRANSACTION;
    INSERT INTO orders VALUES (1);
    BEGIN TRANSACTION;
    -- ERROR: Begin transaction can only be used outside of an existing transaction
COMMIT;

-- 替代方案：用存储过程 + EXCEPTION 块
EXECUTE IMMEDIATE $$
BEGIN
    BEGIN TRANSACTION;
    INSERT INTO t VALUES (1);
    -- 无 SAVEPOINT；只能选择全部回滚或全部提交
    COMMIT;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
```

### BigQuery

```sql
-- 多语句事务（2022 推出）
BEGIN TRANSACTION;
    INSERT INTO orders VALUES (1);
    -- 嵌套 BEGIN 报错：BEGIN TRANSACTION cannot be invoked from within an existing transaction
COMMIT TRANSACTION;
```

### ClickHouse

```sql
-- 实验性 Transactions (v22.3+)
SET allow_experimental_transactions = 1;
BEGIN TRANSACTION;
    INSERT INTO t VALUES (1);
    -- 嵌套 BEGIN 报错
COMMIT;
```

### 流处理引擎（Flink / Materialize / RisingWave）

流式 SQL 引擎的事务概念由 **checkpoint** 实现，与传统 ACID 事务不同：
- 不支持显式 BEGIN/COMMIT
- "嵌套"概念不适用
- exactly-once 通过 checkpoint barrier + 两阶段提交实现

## 翻译模式：用 SAVEPOINT 模拟嵌套

跨数据库的应用代码经常需要把"嵌套事务"翻译为目标引擎支持的语法。

### Spring `@Transactional(propagation=NESTED)`

```java
// Java 应用代码
@Transactional(propagation = Propagation.REQUIRED)
public void outerMethod() {
    doWork1();
    try {
        innerMethod();
    } catch (Exception e) {
        log.error("inner failed", e);
    }
    doWork2();
}

@Transactional(propagation = Propagation.NESTED)
public void innerMethod() {
    doRiskyWork();
}
```

Spring 的底层翻译（JDBC API）：

```java
// 框架自动生成的代码
Connection conn = dataSource.getConnection();
conn.setAutoCommit(false);

// outerMethod 开始
doWork1();  // INSERT...

// innerMethod 开始（NESTED）
Savepoint sp = conn.setSavepoint("nested_1");
try {
    doRiskyWork();
    conn.releaseSavepoint(sp);
} catch (SQLException e) {
    conn.rollback(sp);  // 只回滚到保存点
    throw e;
}

// outerMethod 继续
doWork2();
conn.commit();
```

### .NET 的 TransactionScope

```csharp
using (var outer = new TransactionScope())
{
    using (var conn = new SqlConnection(...))
    {
        conn.Open();
        // 执行 SQL
    }

    using (var inner = new TransactionScope(TransactionScopeOption.RequiresNew))
    {
        // 开启新的独立事务（跨连接，需要 MSDTC）
    }

    outer.Complete();
}
```

`TransactionScopeOption.RequiresNew` 在 SQL Server 上**不是嵌套事务**，而是开启一个**全新的独立事务**（通过分布式事务协调器 MSDTC）。

### Django `transaction.savepoint()`

```python
# Django ORM 的嵌套事务支持
from django.db import transaction

@transaction.atomic
def outer_view(request):
    # 外层事务
    do_work_1()
    try:
        with transaction.atomic():
            # 内层事务（实际是 SAVEPOINT）
            do_risky_work()
    except Exception:
        # 内层回滚到 SAVEPOINT，外层继续
        log_error()
    do_work_2()
```

Django 的 `transaction.atomic()` 嵌套调用底层使用 SAVEPOINT。

### Python DB-API 风格

```python
# 大多数 Python DB-API 驱动都提供 connection.savepoint() 接口
conn = sqlite3.connect("db")
conn.execute("BEGIN")
try:
    conn.execute("INSERT INTO t VALUES (1)")

    sp = conn.savepoint("inner")
    try:
        conn.execute("INSERT INTO t VALUES (2)")
        sp.release()
    except Exception:
        sp.rollback()

    conn.commit()
except Exception:
    conn.rollback()
```

### 跨引擎兼容代码

```python
def begin_nested(conn, dialect):
    """开启"嵌套事务"（跨引擎适配）"""
    if dialect == 'sqlserver':
        # SQL Server 用 SAVE TRANSACTION
        sp_name = generate_savepoint_name()
        conn.execute(f"SAVE TRANSACTION {sp_name}")
        return SavepointHandle(sp_name, dialect)
    elif dialect in ('postgres', 'mysql', 'sqlite', 'oracle'):
        # 标准 SAVEPOINT
        sp_name = generate_savepoint_name()
        conn.execute(f"SAVEPOINT {sp_name}")
        return SavepointHandle(sp_name, dialect)
    elif dialect in ('snowflake', 'bigquery'):
        # 不支持嵌套，需要应用层处理
        raise NotImplementedError(f"{dialect} does not support nested transactions")
```

## 真正嵌套事务的"理论原型"

学术界对嵌套事务的研究始于 **Moss (1985)** 的博士论文 "Nested Transactions: An Approach to Reliable Distributed Computing"。这是 Argus 编程语言中的核心特性，定义了真正嵌套事务的形式语义。

### Moss 模型的关键规则

1. **commit-up rule**：子事务 commit 后，其变更对父事务可见，但仍未对外提交。直到根事务 commit 才真正持久化
2. **abort-down rule**：父事务 abort，所有未 commit 的子事务自动 abort
3. **lock inheritance**：子事务释放的锁会"继承"给父事务（不会立即释放给其他事务）
4. **independent failure**：子事务失败不影响父事务（除非父事务捕获错误后选择 abort）

### 工业级实现的差距

主流 SQL 数据库距离 Moss 模型的差距：

- **PostgreSQL**：最接近——子事务有独立 XID、独立 abort、可见性继承。但**子事务无法独立 commit**（RELEASE 不是 commit）
- **DB2 BEGIN ATOMIC**：原子嵌套块有失败隔离，但仍然只是单事务的子单元
- **SQL Server BEGIN TRAN**：仅计数器嵌套，不是真正嵌套
- **MySQL/Oracle**：完全不支持嵌套，仅 SAVEPOINT

部分学术原型和实验性数据库（如 ARIES/NT 论文中的实现、IBM Starburst、KeyKOS）实现了更接近 Moss 模型的嵌套事务，但都未进入主流商业产品。原因：
- 实现复杂度高（独立锁集、独立 undo log、跨子事务死锁检测）
- 性能开销大（每个子事务都需要独立的事务表条目）
- 应用场景有限——SAVEPOINT + 自治事务已能覆盖 90% 实际需求

## 关键设计决策与陷阱

### 决策 1：为什么 SQL 标准回避嵌套事务？

SQL 标准委员会在 SQL:1999 时就讨论过嵌套事务，但最终选择只引入 SAVEPOINT，原因包括：

1. **实现差异巨大**：商业引擎对"嵌套"的实现五花八门（SQL Server 计数、Oracle 完全不支持、DB2 ATOMIC 块）
2. **应用需求碎片化**：审计日志要"自治"、批量加载要"部分回滚"、分布式事务要"独立提交"——单一概念难以覆盖
3. **SAVEPOINT 已够用**：Spring/Django/JDBC 都用 SAVEPOINT 实现"嵌套语义"，标准化已足够

### 决策 2：BEGIN TRAN 嵌套语法的历史包袱

SQL Server 从 Sybase 4.x 继承的 `BEGIN TRAN` 嵌套是**历史包袱**：
- 1980 年代设计时，Sybase 把"事务计数"作为简化嵌套调用的折衷方案
- 1990 年代 Microsoft 收购 Sybase 部分技术，保留了这个语义
- 改变将破坏数十年存量代码，所以一直保留至今

这种语义在每一代 SQL Server 开发者中都重新制造混乱。Microsoft 的官方文档**强烈警告**不要依赖嵌套 BEGIN TRAN 的"嵌套行为"。

### 陷阱 1：连接池与嵌套语义

```python
# 危险：连接池中归还连接前未确认事务状态
conn = pool.get()
conn.execute("BEGIN")
# ... 业务逻辑抛异常 ...
pool.put(conn)  # 危险！下个用户拿到的连接可能仍在事务中

# 修复：归还前显式回滚
try:
    conn.execute("BEGIN")
    do_work()
    conn.execute("COMMIT")
finally:
    if conn.in_transaction:
        conn.execute("ROLLBACK")
    pool.put(conn)
```

### 陷阱 2：事务超时与嵌套保存点

```sql
-- PostgreSQL idle_in_transaction_session_timeout
-- 长事务 + 大量保存点 → 容易触发超时
SET idle_in_transaction_session_timeout = '60s';

BEGIN;
INSERT INTO t VALUES (1);
SAVEPOINT sp1;
INSERT INTO t VALUES (2);
-- 应用层等待用户输入...60s 后...
-- ERROR: terminating connection due to idle-in-transaction timeout
-- 整个事务被回滚！包括所有保存点
```

### 陷阱 3：触发器中的嵌套

不同引擎对触发器内启动嵌套行为不同：
- **PostgreSQL**：触发器内已经在父事务中，嵌套 BEGIN 无意义；EXCEPTION 块自动创建子事务
- **SQL Server**：触发器内的 ROLLBACK 回滚整个事务，包括外层调用方
- **Oracle**：触发器中不能 COMMIT/ROLLBACK（除非自治事务）

### 陷阱 4：分布式事务（XA）下的嵌套

XA 协议（X/Open）严格规定每个分支必须是平面事务：
- XA 事务**不允许嵌套**
- DB2 在 XA 模式下禁用 SAVEPOINT
- SQL Server 在分布式事务（MSDTC）中限制 BEGIN TRAN 嵌套行为

```sql
-- DB2 XA 限制
XA START 'tx1';
SAVEPOINT sp1;  -- SQLSTATE 3B502: SAVEPOINT 不允许在 XA 分支中
```

## 各引擎"伪嵌套"的精确语义对比

### 例 1：内层 ROLLBACK 行为

```sql
-- 测试用例
BEGIN;
INSERT INTO t VALUES (1, 'outer');
    BEGIN;                            -- 内层 BEGIN
    INSERT INTO t VALUES (2, 'inner');
    ROLLBACK;                         -- 内层 ROLLBACK
INSERT INTO t VALUES (3, 'after');    -- 这条是否能执行？
COMMIT;
SELECT * FROM t;
```

| 引擎 | 内层 BEGIN 后状态 | 内层 ROLLBACK 后状态 | 最终 t 内容 |
|------|------------------|--------------------|----------- |
| PostgreSQL | NOTICE，仍在原事务 | 整个事务回滚 | （空） |
| MySQL | 隐式 COMMIT 外层 | 仅回滚 (2) | (1) |
| SQL Server | @@TRANCOUNT = 2 | @@TRANCOUNT = 0，全部回滚 | （空），COMMIT 报错 |
| Oracle | 没有 BEGIN TRAN 语法 | -- | -- |
| SQLite | 报错 | -- | -- |
| DuckDB | 报错 | -- | -- |
| Snowflake | 报错 | -- | -- |

### 例 2：内层 COMMIT 行为

```sql
BEGIN;
INSERT INTO t VALUES (1, 'outer');
    BEGIN;
    INSERT INTO t VALUES (2, 'inner');
    COMMIT;                          -- 内层 COMMIT
INSERT INTO t VALUES (3, 'after');
ROLLBACK;
```

| 引擎 | 内层 COMMIT 行为 | (3) 是否执行 | ROLLBACK 后 t 内容 |
|------|----------------|------------|-------------------|
| PostgreSQL | 提交整个事务 | (3) 在新事务，已 ROLLBACK | (1), (2) |
| MySQL | 内层 BEGIN 已隐式 COMMIT 外层 | (3) 在新事务被 ROLLBACK | (1), (2) |
| SQL Server | @@TRANCOUNT--，无实际效果 | (3) 在原事务中 | （空，全部回滚） |
| SQLite | 错误，无嵌套 | -- | -- |

### 例 3：SAVEPOINT 替代

```sql
BEGIN;
INSERT INTO t VALUES (1, 'outer');
SAVEPOINT sp_inner;
INSERT INTO t VALUES (2, 'inner');
ROLLBACK TO SAVEPOINT sp_inner;
INSERT INTO t VALUES (3, 'after');
COMMIT;
```

所有支持 SAVEPOINT 的引擎在此场景下行为一致：t = {(1), (3)}。

## 实际架构设计建议

### 何时使用 SAVEPOINT？

适合场景：
- 批量加载中的局部错误恢复（部分行失败不影响整批）
- ORM 嵌套调用（@Transactional NESTED 传播）
- 存储过程中的容错逻辑

不适合场景：
- 需要"独立提交"语义（应使用自治事务或独立连接）
- 大循环中频繁创建（PG 子事务 overflow）
- 长时间持有（与连接池/超时配合不佳）

### 何时使用真正"独立事务"？

需要 commit/rollback 完全独立时：
- **审计日志**：业务事务回滚后日志仍要保留
- **错误跟踪**：异常处理本身需要独立事务
- **资源计费**：扣费成功后即使后续失败也不返还
- **限流配额**：消费配额需要独立提交

可选方案：
- Oracle / DB2 / EDB / 国产数据库：`PRAGMA AUTONOMOUS_TRANSACTION`
- PostgreSQL：dblink 回环 / pg_background
- SQL Server：SQLCLR 独立连接 / Service Broker
- MySQL：应用层独立连接

详见 `autonomous-transactions.md`。

### 何时避免嵌套？

考虑改用单语句的场景：
- `INSERT ... ON CONFLICT DO NOTHING / UPDATE`（PG/MySQL/SQLite）
- `MERGE INTO`（Oracle/DB2/SQL Server/PG 15+）
- 批量 SQL 替代逐行处理
- CTE 链式 DML（PostgreSQL）

## 对引擎开发者的实现建议

### 1. SAVEPOINT 数据结构

```
SavepointStack {
    levels: Vec<SavepointLevel>,
}

SavepointLevel {
    name: String,
    parent_xid: TxnId,
    sub_xid: TxnId,            // 仅 PG 风格
    undo_offset: u64,          // 仅 InnoDB/SQLite 风格
    locks_held: HashSet<Lock>,
    cursors_state: CursorSnapshot,
}
```

实现选择：
- **PG 风格**：每个 SAVEPOINT 对应一个独立子事务（子 XID + pg_subtrans）
- **InnoDB 风格**：SAVEPOINT 仅记录 undo log 偏移；ROLLBACK TO 重放 undo
- **SQLite 风格**：基于 journal 文件位置；级联 SAVEPOINT 在内存栈中

### 2. ROLLBACK TO 算法

```
ROLLBACK TO SAVEPOINT sp_name:
    1. 找到 sp_name 在保存点栈中的位置 (level_idx)
    2. 销毁 level_idx 之后的所有保存点（级联销毁）
    3. 撤销 level_idx 之后的所有数据修改：
       - PG: 标记子事务 XID 为 aborted
       - InnoDB: 重放 undo log 至 level_idx 的偏移
       - SQLite: 回放 journal 至 level_idx 的位置
    4. 释放 level_idx 之后获取的锁（如果保存点持有锁）
    5. 保留 sp_name 本身（仍可再次 ROLLBACK TO 或 RELEASE）
```

### 3. 子事务上限的设计权衡

PostgreSQL 的 `PGPROC_MAX_CACHED_SUBXIDS = 64` 是 1990 年代设计的硬编码常量：
- **小**：减少 PGPROC 内存占用，加速快照计算
- **大**：减少 subxid overflow，但占用共享内存

替代设计：
- **动态扩展**：超过 64 时分配额外内存（PG 14+ 部分优化）
- **分布式存储**：将子事务表移到 LSM 树（如 YugabyteDB 的做法）
- **去除上限**：把子事务跟踪移到查询计划而非全局共享内存

### 4. 嵌套 BEGIN 的处理策略

引擎设计的几种选择：

| 策略 | 引擎 | 优点 | 缺点 |
|------|------|------|------|
| 报错 | SQLite/DuckDB/Snowflake | 语义清晰 | 客户端代码繁琐 |
| Warning 后 NOOP | PostgreSQL | 客户端友好 | 容易掩盖 bug |
| 隐式提交外层 | MySQL/MariaDB | 与单事务模型一致 | 容易丢失数据 |
| 计数器嵌套 | SQL Server/Sybase | 看起来支持嵌套 | 语义陷阱多 |

新引擎设计应优先考虑**报错**或**Warning + NOOP**，避免计数器嵌套的语义陷阱。

### 5. 与隔离级别的交互

真正的嵌套事务可以子事务独立设置隔离级别。SAVEPOINT 不行——隔离级别是事务级别属性。

```sql
-- PostgreSQL：SAVEPOINT 不能修改隔离级别
BEGIN ISOLATION LEVEL SERIALIZABLE;
SAVEPOINT sp1;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- ERROR: SET TRANSACTION ISOLATION LEVEL must be called before any query
```

引擎实现建议：
- 文档中明确说明 SAVEPOINT 不改变隔离级别
- 不允许在 SAVEPOINT 后修改隔离级别（PG 行为）

### 6. 分布式嵌套的复杂度

分布式数据库（CockroachDB / YugabyteDB / TiDB / Spanner）实现 SAVEPOINT 时面临：
- **跨节点协调**：保存点元数据需要在所有参与节点同步
- **MVCC 与 KV 层**：保存点对应 KV 层的"intent" 时间戳栅栏
- **乐观/悲观锁交互**：乐观事务下保存点的撤销成本极低；悲观事务下需要释放部分锁
- **Raft 日志成本**：每个 SAVEPOINT 可能产生 Raft entry（部分实现）

设计权衡：
- 仅在协调器节点维护保存点元数据（CockroachDB 的做法）
- 延迟向工作节点广播保存点信息直到 ROLLBACK TO

### 7. 与查询计划缓存的交互

嵌套块内的执行计划是否复用？
- **PostgreSQL**：每个 PL/pgSQL 函数的查询计划独立缓存，与子事务无关
- **Oracle**：cursor 在 PL/SQL 块结束时关闭，不与保存点绑定
- **SQL Server**：编译时不感知 SAVEPOINT；运行时按 plan handle 复用

### 8. 测试矩阵

设计测试用例覆盖：
- 嵌套 SAVEPOINT 深度（10、100、1000、10000）
- ROLLBACK TO 中间层级（销毁后续保存点）
- 同名 SAVEPOINT 行为（覆盖 vs 栈式）
- 与 EXCEPTION/异常处理的交互
- 与隔离级别（READ COMMITTED / SERIALIZABLE）的组合
- 与连接池/超时的交互
- 触发器中的嵌套调用

## 总结对比矩阵

### 嵌套能力总览

| 能力 | PostgreSQL | SQL Server | Oracle | MySQL | DB2 | SQLite | Snowflake |
|------|-----------|------------|--------|-------|-----|--------|-----------|
| BEGIN TRAN 嵌套 | NOTICE | 计数器 | 不支持 | 隐式 COMMIT | 不支持 | 报错 | 报错 |
| SAVEPOINT | 子事务 | SAVE TRAN | 是 | 是 | 是 | 是 | -- |
| RELEASE SAVEPOINT | 是 | -- | -- | 是 | 是 | 是 | -- |
| @@TRANCOUNT 类计数 | -- | 是 | -- | -- | -- | -- | -- |
| BEGIN ATOMIC 块 | -- | -- | -- | -- | 是 | -- | -- |
| 自治事务 | dblink | -- | PRAGMA | -- | AUTONOMOUS | -- | -- |

### 推荐场景对照

| 场景 | 推荐引擎/语法 | 原因 |
|------|--------------|------|
| 部分回滚 | 任何 SAVEPOINT 引擎 | 标准化，跨引擎可移植 |
| 大循环容错（PG） | INSERT ... ON CONFLICT | 避免子事务 overflow |
| 真正"独立事务" | Oracle PRAGMA AUTONOMOUS | 唯一规范化的真正自治 |
| 嵌套块原子性（DB2） | BEGIN ATOMIC | 真正块级原子，无 SAVEPOINT 开销 |
| 跨引擎应用代码 | SAVEPOINT + 应用层判断 | 通用方案 |
| 高吞吐 OLAP（无嵌套） | 单语句 + MERGE/UPSERT | 避免事务嵌套需求 |

## 关键发现

1. **没有引擎实现真正的嵌套事务**：所有"嵌套"语法实际上都是 SAVEPOINT 或计数器
2. **SQL 标准只定义 SAVEPOINT**：SQL:1999 Section 17.1，避开了"嵌套事务"概念
3. **SQL Server `BEGIN TRAN` 是历史包袱**：计数器语义陷阱多，不应依赖
4. **PostgreSQL 子事务有 64 个软上限**：超出后性能急剧下降
5. **MySQL `BEGIN` 在事务中隐式 COMMIT**：完全不允许嵌套
6. **Oracle 自 v6 起就不支持 BEGIN TRAN**：必须用隐式事务 + SAVEPOINT
7. **DB2 `BEGIN ATOMIC` 是最接近"真正嵌套"的设计**：原子块 + 失败隔离
8. **OLAP/MPP 引擎几乎都不支持 SAVEPOINT**：事务模型偏向批量操作
9. **真正的"独立事务"语义是自治事务**：与嵌套事务是不同的概念
10. **Spring/Django 等框架的"嵌套传播"底层都是 SAVEPOINT**：跨引擎可移植

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2, Section 17.1 (SAVEPOINT statement family)
- SQL:1999 标准: Section 17.2 (chained transaction: COMMIT AND CHAIN)
- Moss, J.E.B. "Nested Transactions: An Approach to Reliable Distributed Computing" (1985), MIT PhD Thesis
- Beeri, C., Bernstein, P.A., Goodman, N. "A Model for Concurrency in Nested Transactions Systems" (1989), JACM
- Rothermel, K., Mohan, C. "ARIES/NT: A Recovery Method Based on Write-Ahead Logging for Nested Transactions" (1989), VLDB
- Microsoft: [BEGIN TRANSACTION (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/begin-transaction-transact-sql)
- Microsoft: [@@TRANCOUNT](https://learn.microsoft.com/en-us/sql/t-sql/functions/trancount-transact-sql)
- Microsoft: [SAVE TRANSACTION (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/save-transaction-transact-sql)
- PostgreSQL: [SAVEPOINT](https://www.postgresql.org/docs/current/sql-savepoint.html)
- PostgreSQL: [Subtransactions and Performance](https://www.postgresql.org/docs/current/runtime-config-resource.html)
- PostgreSQL: GitLab Postmortem (2021): [Subtransactions Considered Harmful](https://about.gitlab.com/blog/2021/09/29/why-we-spent-the-last-month-eliminating-postgresql-subtransactions/)
- MySQL: [SAVEPOINT, ROLLBACK TO SAVEPOINT, and RELEASE SAVEPOINT Statements](https://dev.mysql.com/doc/refman/8.0/en/savepoint.html)
- Oracle: [SAVEPOINT Statement](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SAVEPOINT.html)
- DB2: [SAVEPOINT statement](https://www.ibm.com/docs/en/db2/11.5?topic=statements-savepoint)
- DB2: [BEGIN ATOMIC](https://www.ibm.com/docs/en/db2/11.5?topic=statements-begin-atomic)
- SQLite: [SAVEPOINT, RELEASE, ROLLBACK TO](https://www.sqlite.org/lang_savepoint.html)
- CockroachDB: [SAVEPOINT](https://www.cockroachlabs.com/docs/stable/savepoint.html)
- TiDB: [SAVEPOINT](https://docs.pingcap.com/tidb/stable/sql-statement-savepoint)
- Snowflake: [Transactions](https://docs.snowflake.com/en/sql-reference/transactions)
- Spring Framework: [Transaction Propagation](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/transaction/annotation/Propagation.html)
- Django: [Database Transactions](https://docs.djangoproject.com/en/stable/topics/db/transactions/)
- JDBC 3.0 Specification (2002): java.sql.Savepoint interface
- Gray, J., Reuter, A. "Transaction Processing: Concepts and Techniques" (1993), Chapter 4
