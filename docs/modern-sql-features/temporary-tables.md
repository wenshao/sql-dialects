# 临时表与表变量

数据库处理中间结果的核心机制——从 SQL 标准的 `CREATE TEMPORARY TABLE` 到各引擎千差万别的作用域、生命周期和性能特征，临时表是每个 SQL 引擎必须面对的设计抉择。

## 支持矩阵

| 引擎 | 本地临时表 | 全局临时表 | 表变量 | ON COMMIT 子句 | 内存优化 |
|------|-----------|-----------|--------|---------------|---------|
| SQL Server | `#table` | `##table` | `@table` | 不支持 | 内存优化表变量 |
| PostgreSQL | `CREATE TEMP TABLE` | 不支持 | 不支持 | DELETE/PRESERVE/DROP | 不支持 |
| MySQL | `CREATE TEMPORARY TABLE` | 不支持 | 不支持 | 不支持 | MEMORY 引擎 |
| Oracle | `CREATE GLOBAL TEMPORARY TABLE` | GTT（DDL 持久） | PL/SQL 集合 | DELETE/PRESERVE ROWS | 不支持 |
| MariaDB | `CREATE TEMPORARY TABLE` | 不支持 | 不支持 | 不支持 | MEMORY 引擎 |
| Db2 | `DECLARE GLOBAL TEMPORARY TABLE` | `CREATE GLOBAL TEMPORARY TABLE` | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| SQLite | `CREATE TEMP TABLE` | 不支持 | 不支持 | 不支持 | 内存模式 |
| Teradata | `CREATE VOLATILE TABLE` | `CREATE GLOBAL TEMPORARY TABLE` | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| Snowflake | `CREATE TEMPORARY TABLE` | 不支持 | 不支持 | 不支持 | 自动 |
| BigQuery | 脚本内临时表 | 不支持 | 不支持 | 不支持 | 自动 |
| Redshift | `CREATE TEMP TABLE` | 不支持 | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| Databricks | `CREATE TEMPORARY VIEW`² | `CREATE GLOBAL TEMP VIEW`² | 不支持 | 不支持 | 自动 |
| DuckDB | `CREATE TEMP TABLE` | 不支持 | 不支持 | 不支持 | 自动 |
| ClickHouse | `CREATE TEMPORARY TABLE` | 不支持 | 不支持 | 不支持 | Memory 引擎 |
| CockroachDB | `CREATE TEMP TABLE` | 不支持 | 不支持 | PRESERVE ROWS（仅） | 不支持 |
| TiDB | `CREATE TEMPORARY TABLE` | `CREATE GLOBAL TEMPORARY TABLE` | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| OceanBase | `CREATE TEMPORARY TABLE` | `CREATE GLOBAL TEMPORARY TABLE` | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| Hive | `CREATE TEMPORARY TABLE` | 不支持 | 不支持 | 不支持 | 不支持 |
| Spark SQL | `CREATE TEMPORARY VIEW`² | `CREATE GLOBAL TEMP VIEW`² | 不支持 | 不支持 | 自动 |
| Presto/Trino | memory connector | 不支持 | 不支持 | 不支持 | 内存连接器 |
| Vertica | `CREATE LOCAL TEMP TABLE` | `CREATE GLOBAL TEMP TABLE` | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| Greenplum | `CREATE TEMP TABLE` | 不支持 | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| SAP HANA | `CREATE LOCAL TEMPORARY TABLE` | `CREATE GLOBAL TEMPORARY TABLE` | 不支持 | DELETE/PRESERVE（仅全局） | 列/行存储 |
| Informix | `CREATE TEMP TABLE` | 不支持 | 不支持 | 不支持 | 不支持 |
| Firebird | `CREATE GLOBAL TEMPORARY TABLE` | GTT（DDL 持久） | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| H2 | `CREATE LOCAL TEMPORARY TABLE` | `CREATE GLOBAL TEMPORARY TABLE` | 不支持 | DELETE/PRESERVE ROWS | 内存模式 |
| HSQLDB | `CREATE LOCAL TEMPORARY TABLE` | `CREATE GLOBAL TEMPORARY TABLE` | 不支持 | DELETE/PRESERVE ROWS | 内存模式 |
| Derby | `DECLARE GLOBAL TEMPORARY TABLE` | 不支持 | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| MonetDB | `CREATE LOCAL TEMP TABLE` | `CREATE GLOBAL TEMP TABLE` | 不支持 | DELETE/PRESERVE ROWS | 自动 |
| Exasol | 无原生语法 | 不支持 | 不支持 | 不支持 | 自动 |
| SingleStore | `CREATE TEMPORARY TABLE` | 不支持 | 不支持 | 不支持 | 行存储 |
| YugabyteDB | `CREATE TEMP TABLE` | 不支持 | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| PolarDB | `CREATE TEMPORARY TABLE` | `CREATE GLOBAL TEMPORARY TABLE` | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| GaussDB | `CREATE TEMPORARY TABLE` | `CREATE GLOBAL TEMPORARY TABLE` | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| VoltDB | 不支持 | 不支持 | 不支持 | 不支持 | 全内存 |
| Citus | `CREATE TEMP TABLE` | 不支持 | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| QuestDB | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| TimescaleDB | `CREATE TEMP TABLE` | 不支持 | 不支持 | DELETE/PRESERVE ROWS | 不支持 |
| StarRocks | `CREATE TEMPORARY TABLE` | 不支持 | 不支持 | 不支持 | 自动 |
| Doris | `CREATE TEMPORARY TABLE` | 不支持 | 不支持 | 不支持 | 自动 |
| MaxCompute | 脚本变量 `@var` | 不支持 | 不支持 | 不支持 | 自动 |
| ByConity | `CREATE TEMPORARY TABLE` | 不支持 | 不支持 | 不支持 | 自动 |
| Umbra | `CREATE TEMP TABLE` | 不支持 | 不支持 | 不支持 | 自动 |

² Spark SQL 和 Databricks 的临时视图 (TEMPORARY VIEW) 不是临时表。临时视图只是命名的查询别名，不物化数据、不支持索引、不支持 DML 操作（INSERT/UPDATE/DELETE）。它们在此矩阵中列出是因为功能上用于替代临时表存放中间结果，但本质上是不同的机制。

## 核心概念

### SQL 标准定义（SQL:1992+）

```
标准语法:
CREATE { LOCAL | GLOBAL } TEMPORARY TABLE table_name (
    column_definitions...
) ON COMMIT { DELETE ROWS | PRESERVE ROWS }
```

**LOCAL TEMPORARY** — 表定义和数据都仅对当前会话可见，会话结束时销毁。
**GLOBAL TEMPORARY** — 表定义对所有会话可见（DDL 持久存储在数据字典中），数据对各会话隔离。

### DDL 持久性 vs 数据可见性

```
┌─────────────────────────────────┐
│  LOCAL TEMPORARY TABLE          │
│  - DDL: 会话级（会话结束即销毁）  │
│  - 数据: 会话级                  │
│  - 类比: 局部变量               │
├─────────────────────────────────┤
│  GLOBAL TEMPORARY TABLE         │
│  - DDL: 永久存储在数据字典       │
│  - 数据: 会话级隔离             │
│  - 类比: 全局模板，局部数据      │
└─────────────────────────────────┘
```

这个区别是很多困惑的根源。Oracle/Firebird 的 GTT 是 DDL 持久的：`CREATE GLOBAL TEMPORARY TABLE` 一次，然后所有会话都能使用，各自看各自的数据。而 SQL Server 的 `##table` 完全不同：DDL 和数据都在创建会话上下文中，其他会话可以引用同一份数据。

## 语法对比

### SQL Server

```sql
-- 本地临时表（# 前缀，会话级）
CREATE TABLE #temp_orders (
    order_id INT PRIMARY KEY, customer_id INT, amount DECIMAL(10,2)
);

-- 全局临时表（## 前缀，所有会话可见，最后引用会话断开后销毁）
CREATE TABLE ##shared_config (key_name NVARCHAR(100) PRIMARY KEY, value NVARCHAR(500));

-- 表变量（@ 前缀，批处理级，不参与事务回滚）
DECLARE @items TABLE (
    item_id INT IDENTITY(1,1), product_name NVARCHAR(100),
    quantity INT, INDEX ix_product (product_name)  -- 2014+ 内联索引
);

-- 内存优化表变量（2014+，不使用 tempdb）
CREATE TYPE dbo.OrderItemType AS TABLE (
    item_id INT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 10000),
    product_name NVARCHAR(100) NOT NULL
) WITH (MEMORY_OPTIMIZED = ON);

-- SELECT INTO 隐式创建临时表
SELECT customer_id, SUM(amount) AS total INTO #totals FROM orders GROUP BY customer_id;
```

### PostgreSQL

```sql
CREATE TEMP TABLE temp_orders (
    order_id SERIAL PRIMARY KEY, customer_id INT, amount NUMERIC(10,2)
);

-- ON COMMIT 三种行为
CREATE TEMP TABLE t1 (id INT) ON COMMIT DELETE ROWS;    -- 提交后清空数据
CREATE TEMP TABLE t2 (id INT) ON COMMIT PRESERVE ROWS;  -- 默认，保留到会话结束
CREATE TEMP TABLE t3 (id INT) ON COMMIT DROP;            -- 提交后删除整个表

-- CTAS
CREATE TEMP TABLE temp_summary AS
SELECT customer_id, COUNT(*) AS cnt FROM orders GROUP BY customer_id;

-- pg_temp schema：临时表隐式在 search_path 最前面，优先于同名永久表
```

### MySQL / MariaDB

```sql
CREATE TEMPORARY TABLE temp_orders (
    order_id INT AUTO_INCREMENT PRIMARY KEY, customer_id INT, amount DECIMAL(10,2)
) ENGINE = InnoDB;

-- MEMORY 引擎（全内存，不支持 BLOB/TEXT）
CREATE TEMPORARY TABLE temp_lookup (id INT PRIMARY KEY, name VARCHAR(100)) ENGINE = MEMORY;

-- CTAS
CREATE TEMPORARY TABLE temp_summary
SELECT customer_id, SUM(amount) AS total FROM orders GROUP BY customer_id;

-- 注意：同一查询中不能多次引用同一临时表（8.0 前）；SHOW TABLES 不显示临时表
-- MySQL 8.0+ TempTable 引擎：SET GLOBAL temptable_max_ram = 1073741824;
```

### Oracle

```sql
-- GTT（DDL 持久，创建一次，所有会话共享定义）
CREATE GLOBAL TEMPORARY TABLE temp_orders (
    order_id NUMBER PRIMARY KEY, customer_id NUMBER, amount NUMBER(10,2)
) ON COMMIT DELETE ROWS;  -- 默认行为：事务提交后数据清空

CREATE GLOBAL TEMPORARY TABLE temp_cache (
    cache_key VARCHAR2(100) PRIMARY KEY, cache_value CLOB
) ON COMMIT PRESERVE ROWS;  -- 会话结束后清空

-- 18c+ 私有临时表（真正的会话级 DDL，必须以 ORA$PTT_ 前缀开头）
CREATE PRIVATE TEMPORARY TABLE ora$ptt_temp (id NUMBER, value VARCHAR2(200))
ON COMMIT DROP DEFINITION;  -- 事务结束后连定义都删除

-- PL/SQL 集合（表变量的 Oracle 对应物）
DECLARE
    TYPE order_tab IS TABLE OF orders%ROWTYPE INDEX BY PLS_INTEGER;
    v_orders order_tab;
BEGIN
    SELECT * BULK COLLECT INTO v_orders FROM orders WHERE customer_id = 100;
END;
/
```

### Db2

```sql
-- DGTT（会话级，DDL 不持久，不写目录）
DECLARE GLOBAL TEMPORARY TABLE session.temp_orders (
    order_id INT, customer_id INT, amount DECIMAL(10,2)
) ON COMMIT DELETE ROWS NOT LOGGED;

-- CGTT（DDL 持久，类似 Oracle GTT）
CREATE GLOBAL TEMPORARY TABLE temp_template (id INT, value VARCHAR(200))
ON COMMIT PRESERVE ROWS;
```

### Snowflake / BigQuery / DuckDB / ClickHouse

```sql
-- Snowflake（TEMPORARY vs TRANSIENT：前者会话级，后者持久但无 Fail-safe）
CREATE TEMPORARY TABLE temp_orders (order_id INT, amount NUMBER(10,2));
CREATE TRANSIENT TABLE staging_orders (order_id INT);  -- 非临时表，只是减少保护

-- BigQuery（脚本内临时表，使用 _SESSION 数据集）
CREATE TEMP TABLE temp_orders AS SELECT * FROM `project.dataset.orders` WHERE order_date = CURRENT_DATE();

-- DuckDB（内存优先，支持 CREATE OR REPLACE TEMP TABLE）
CREATE OR REPLACE TEMP TABLE temp_orders AS SELECT * FROM read_csv('orders.csv');

-- ClickHouse（固定 Memory 引擎，不支持索引和分布式查询）
CREATE TEMPORARY TABLE temp_orders (order_id UInt64, amount Decimal(10,2));
```

### TiDB / CockroachDB / Spark SQL

```sql
-- TiDB 本地临时表（数据仅在 TiDB Server 内存中，不写 TiKV）
CREATE TEMPORARY TABLE temp_local (id INT PRIMARY KEY, value VARCHAR(200));
-- TiDB 全局临时表（DDL 持久，数据事务级隔离）
CREATE GLOBAL TEMPORARY TABLE temp_global (id INT PRIMARY KEY) ON COMMIT DELETE ROWS;

-- CockroachDB（需启用实验特性，临时表仍通过 Raft 复制）
SET experimental_enable_temp_tables = 'on';
CREATE TEMP TABLE temp_orders (order_id INT PRIMARY KEY) ON COMMIT PRESERVE ROWS;

-- Spark SQL / Databricks（使用临时视图而非临时表）
CREATE TEMPORARY VIEW temp_orders AS SELECT * FROM orders WHERE amount > 100;
CREATE GLOBAL TEMPORARY VIEW global_orders AS SELECT * FROM orders;
SELECT * FROM global_temp.global_orders;  -- 通过 global_temp 数据库访问
```

## ON COMMIT 行为对比

| 行为 | 含义 | 支持引擎 |
|------|------|---------|
| `ON COMMIT DELETE ROWS` | 提交后清空数据 | Oracle, PostgreSQL, Db2, Teradata, Firebird, TiDB, Redshift, Vertica, H2, HSQLDB, SAP HANA, OceanBase, GaussDB |
| `ON COMMIT PRESERVE ROWS` | 保留到会话结束 | 同上 + CockroachDB（仅支持 PRESERVE ROWS） |
| `ON COMMIT DROP` | 提交后删除整个表 | PostgreSQL, Oracle PTT |
| 不支持 ON COMMIT | 数据始终保留到会话结束 | SQL Server, MySQL, MariaDB, SQLite, ClickHouse, Snowflake, BigQuery, DuckDB |

常见陷阱：Oracle GTT 默认 `DELETE ROWS`。从 SQL Server 迁移的开发者在事务提交后查询数据，发现已消失。PostgreSQL 默认 `PRESERVE ROWS`，行为相反。

## 作用域与生命周期矩阵

| 引擎 | DDL 可见性 | 数据可见性 | 生命周期 | 元数据存储 |
|------|-----------|-----------|---------|-----------|
| SQL Server `#` | 当前会话 + 子过程 | 当前会话 | 会话结束 | tempdb |
| SQL Server `##` | 所有会话 | 所有会话（共享） | 最后引用会话结束 | tempdb |
| SQL Server `@` | 当前批处理 | 当前批处理 | 批处理结束 | tempdb |
| PostgreSQL | 当前会话 | 当前会话 | 会话/事务/ON COMMIT | pg_temp_N schema |
| MySQL | 当前连接 | 当前连接 | 连接断开 | 临时文件 |
| Oracle GTT | 所有会话（永久） | 会话隔离 | DDL 永久，数据事务/会话 | 数据字典 |
| Oracle PTT | 当前会话 | 当前会话 | 事务/会话 | 仅内存 |
| Db2 DGTT | 当前会话 | 当前会话 | 会话结束 | 不写目录 |
| TiDB LOCAL | 当前会话 | 当前会话 | 会话结束 | 仅内存 |
| TiDB GLOBAL | 所有会话（永久） | 会话隔离 | DDL 永久，数据事务 | 系统表 |
| Snowflake | 当前会话 | 当前会话 | 会话结束 | 元数据服务 |
| BigQuery | 当前脚本 | 当前脚本 | 脚本结束 | _SESSION |

SQL Server `#table` 的特殊作用域：存储过程中创建的 `#table` 对其调用的子过程可见，但子过程创建同名 `#table` 会遮蔽外层版本。

## 临时表 vs CTE vs 子查询

```
临时表适用场景:                    CTE 适用场景:                   子查询适用场景:
✓ 中间结果多次引用                 ✓ 单次查询内的中间步骤           ✓ 简单一次性过滤
✓ 需要索引加速                    ✓ 递归查询                      ✓ 优化器可下推谓词
✓ 数据量大                       ✓ 提高可读性                    ✗ 嵌套过深降低可读性
✓ 跨查询共享                     ✗ 注意物化 vs 内联差异
```

### CTE 物化策略差异

| 引擎 | 默认行为 | 强制物化 | 强制内联 |
|------|---------|---------|---------|
| PostgreSQL 12+ | 引用 1 次内联，>1 次物化 | `MATERIALIZED` | `NOT MATERIALIZED` |
| SQL Server | 总是内联 | 不支持 | 默认 |
| MySQL 8.0+ | 优化器决定（可合并或物化） | 不支持 | 不支持 |
| Oracle | 优化器决定 | `/*+ MATERIALIZE */` | `/*+ INLINE */` |
| ClickHouse | 总是内联 | 不支持 | 默认 |

SQL Server 中 CTE 被引用两次会展开为两次计算。如果聚合代价高，临时表是更好的选择。

## 索引与统计信息

| 引擎 | 创建时索引 | 后续加索引 | 自动统计 | 备注 |
|------|-----------|-----------|---------|------|
| SQL Server `#` | 是 | 是 | 是（自动） | 完整统计支持 |
| SQL Server `@` | 是（2014+） | 否 | 否（固定 1 行） | 2019+ 延迟编译改善 |
| PostgreSQL | 是 | 是 | 需手动 ANALYZE | 自动不处理临时表 |
| MySQL | 是 | 是 | 是 | |
| Oracle GTT | 是 | 是 | 需手动收集 | 会话级统计(12c+) |
| ClickHouse | 否 | 否 | 否 | Memory 引擎无索引 |
| DuckDB | 是 | 是 | 自动 | |

### SQL Server 表变量统计陷阱

```sql
-- @table 优化器固定估计 1 行（2019 之前）
DECLARE @orders TABLE (id INT PRIMARY KEY, customer_id INT INDEX ix_cust);
INSERT INTO @orders SELECT * FROM orders WHERE year = 2024;
-- 即使插入 100 万行，优化器认为 1 行 → 选择 Nested Loop → 性能灾难

-- 2019+ 修复: 表变量延迟编译
ALTER DATABASE SCOPED CONFIGURATION SET DEFERRED_TABLE_VARIABLE_COMPILATION = ON;
```

## 命名约定与隔离

| 引擎 | 命名规则 | 隔离机制 | 同名冲突处理 |
|------|---------|---------|-------------|
| SQL Server | `#`/`##` 前缀 | 内部追加唯一后缀（可用 116 字符） | 前缀区分 |
| PostgreSQL | 无前缀 | pg_temp_N schema | 临时表优先 |
| MySQL | 无前缀 | 连接内部隔离 | 临时表遮蔽永久表 |
| Oracle PTT | `ORA$PTT_` 前缀 | 会话内部 | 前缀区分 |
| SAP HANA | `#` 前缀（可选） | 会话内部 | 前缀区分 |
| SQLite | 无前缀 | temp schema | `temp.table_name` |

PostgreSQL 安全注意：恶意用户可创建同名临时对象劫持查询。安全函数中应使用 schema 限定名。

## DDL 限制

| 操作 | SQL Server # | PostgreSQL | MySQL | Oracle GTT | Oracle PTT |
|------|-------------|-----------|-------|-----------|-----------|
| ALTER TABLE | 是 | 是 | 是 | 是 | 否 |
| TRUNCATE | 是 | 是 | 是 | 是 | 是 |
| 创建索引 | 是 | 是 | 是 | 是 | 否 |
| 创建触发器 | 是 | 是 | 否 | 是 | 否 |
| 视图引用 | 否 | 是（临时视图） | 否 | 是 | 否 |
| 外键→永久表 | 否 | 是 | 否 | 否 | 否 |
| 分区 | 否 | 是(12+) | 否 | 是 | 否 |

### 复制行为

```
MySQL SBR: 临时表 DDL/DML 被复制 → 主库异常断开时从库残留临时表
MySQL RBR: 临时表操作不复制 → 安全
PostgreSQL: 临时表不参与逻辑复制；物理复制中 WAL 包含临时表操作
SQL Server: tempdb 节点本地，不参与复制和 AG
```

## 内存优化临时表

### SQL Server

```sql
-- 内存优化表变量：不使用 tempdb，无闩锁，无日志
CREATE TYPE dbo.MemType AS TABLE (
    id INT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 10000),
    value NVARCHAR(200) NOT NULL
) WITH (MEMORY_OPTIMIZED = ON);

-- tempdb 内存优化元数据（2019+）：解决高并发 tempdb 系统表闩锁争用
ALTER SERVER CONFIGURATION SET MEMORY_OPTIMIZED TEMPDB_METADATA = ON;
```

### MySQL 8.0+ TempTable 引擎

```sql
-- 8.0 前 MEMORY 引擎不支持变长字段 → 频繁溢出磁盘
-- 8.0+ TempTable 原生支持 VARCHAR/BLOB
SET GLOBAL internal_tmp_mem_storage_engine = 'TempTable';
SET GLOBAL temptable_max_ram = 1073741824;   -- 超出后 mmap
SET GLOBAL temptable_max_mmap = 1073741824;  -- 超出后 InnoDB 磁盘临时表

-- 监控
SHOW GLOBAL STATUS LIKE 'Created_tmp_%';
```

## 分布式环境的挑战

分布式数据库中临时表面临三个核心问题：数据本地性（是否分布到多节点）、元数据同步（DDL 是否需要全局可见）、以及节点故障时的恢复策略。

```
┌────────────────┬────────────────────────────────────────┐
│ CockroachDB    │ 临时表通过 Raft 复制                    │
│                │ → 安全但开销大，不适合高频创建             │
├────────────────┼────────────────────────────────────────┤
│ TiDB           │ 本地临时表仅在 TiDB Server 内存          │
│                │ → 不经过 TiKV，性能好但不持久             │
│                │ 全局临时表 DDL 存 TiKV，数据在会话内存     │
├────────────────┼────────────────────────────────────────┤
│ Snowflake      │ 临时表与普通表相同的云存储                 │
│                │ → 自动管理生命周期                       │
├────────────────┼────────────────────────────────────────┤
│ BigQuery       │ 脚本级隔离，_SESSION 数据集               │
│                │ → 不消耗存储费用                         │
├────────────────┼────────────────────────────────────────┤
│ YugabyteDB     │ 临时表仅在本地 tablet server             │
│                │ → 不跨节点复制，性能好                    │
└────────────────┴────────────────────────────────────────┘
```

关键设计取舍：CockroachDB 选择一致性（复制），TiDB 选择性能（本地内存）。如果你的引擎是分布式的，建议默认不复制临时表数据，仅在会话所在节点存储。

## 清理与连接池

连接池场景中临时表残留是高频问题。连接被归还后由另一个业务逻辑复用，可能遇到上一次遗留的临时表。

```sql
-- MySQL: 归还连接前显式 DROP（否则下个使用者可能看到残留数据或创建同名表失败）
DROP TEMPORARY TABLE IF EXISTS temp_orders;
DROP TEMPORARY TABLE IF EXISTS temp_summary;

-- PostgreSQL: DISCARD 命令
DISCARD TEMP;   -- 清除所有临时表
DISCARD ALL;    -- 重置整个会话状态（连 search_path 都重置）

-- SQL Server: sp_reset_connection（连接池自动调用）清理 #table
-- 但 ##table 不会被自动清理！

-- 通用最佳实践:
-- 1. 优先使用 ON COMMIT DELETE ROWS（事务级自动清空）
-- 2. 代码中 try/finally 显式 DROP
-- 3. 连接池验证查询检查残留状态
```

## 对引擎开发者的实现建议

### 1. 元数据管理

```
路线 A: 独立临时目录（SQL Server/PostgreSQL 模式）
  为临时表使用独立的元数据存储，不污染主目录
  优点: 创建/销毁快速    缺点: 跨目录引用需特殊处理

路线 B: 共享目录 + 可见性标记（Oracle GTT 模式）
  在主数据字典中存储 GTT 的 DDL
  优点: 统一管理    缺点: 需要可见性过滤

要点:
  - 临时表 OID 应使用独立 ID 空间，避免与永久表冲突
  - 元数据缓存需考虑会话级失效
  - 支持 CREATE OR REPLACE 语义避免重复创建错误
```

### 2. 存储层

```
内存存储:
  - 使用 arena allocator 管理临时表内存块，会话结束一次性释放
  - 需要内存用量追踪和限额控制

磁盘溢出:
  - 超过阈值时溢出到专用临时目录
  - 考虑 mmap 中间方案（MySQL TempTable 的做法）

WAL/日志:
  - 建议: 默认不写 redo log（不需要崩溃恢复），但保留 undo 支持事务回滚
  - Db2 的 NOT LOGGED 选项是好的设计参考
```

### 3. 并发与隔离

```
会话隔离:
  - 每个会话的临时表空间应完全独立
  - 避免在全局结构上产生锁争用（SQL Server tempdb 闩锁争用是反例）

命名隔离方案:
  方案 1: 名称前缀 + 内部后缀（SQL Server）— 简单但有长度限制
  方案 2: 独立 schema（PostgreSQL pg_temp_N）— 优雅但需 schema 解析
  方案 3: 会话内部映射表 — 灵活但增加查找开销
```

### 4. 优化器集成

```
统计信息:
  - 对临时表使用轻量级采样统计（插入后自动采样 ~1000 行）
  - 避免 SQL Server @table 固定 1 行估计的教训

执行计划缓存:
  - 临时表 schema 可能每次不同，不能简单缓存引用临时表的计划
  - 建议使用参数化模板，统计信息作为计划选择参数

CTE 物化决策:
  - 保留原始查询树信息，允许优化器在物化和内联之间切换
```

### 5. 资源限制与监控

```
应设置的限制:                      应暴露的监控指标:
- 每会话最大临时表数量              - 临时表总数量（按会话/全局）
- 每会话临时表总内存上限            - 临时表总内存使用量
- 全局临时表存储空间上限            - 溢出到磁盘的次数
- 单表最大行数/大小                - 创建/销毁 QPS

清理策略:
  - 正常结束: 同步清理
  - 异常断开: 后台线程异步清理（时间戳标记 + 定期扫描）
  - 全局临时表: 引用计数归零后延迟清理
```

### 6. DDL 事务性

```
PostgreSQL（推荐）: CREATE TEMP TABLE 是事务性的，回滚可撤销创建
MySQL: CREATE TEMPORARY TABLE 不隐式提交，DROP TEMPORARY TABLE 也不隐式提交 — 与普通 DDL 不同
SQL Server: #table 创建/删除都参与事务

建议:
  - 临时表 DDL 应参与事务
  - 至少确保不隐式提交用户事务
  - 支持 IF NOT EXISTS 避免重复创建的错误处理复杂性
```

### 7. 安全

```
1. 命名空间污染（PostgreSQL）: 恶意临时对象遮蔽永久对象 → 用 schema 限定名
2. 信息泄露（SQL Server ##table）: 全局临时表数据对所有会话可见 → 避免存储敏感数据
3. 资源耗尽: 恶意会话创建大量临时表耗尽 tempdb → 实施每会话资源配额
4. 权限: SQL Server 需 tempdb CREATE TABLE 权限；PostgreSQL 需数据库级 TEMPORARY 权限
```

## 参考资料

- ISO/IEC 9075-2 (SQL Foundation) Section 11.2, 11.32 (Temporary Tables)
- SQL Server: [Temporary Tables](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-transact-sql)
- PostgreSQL: [CREATE TABLE - TEMPORARY](https://www.postgresql.org/docs/current/sql-createtable.html)
- MySQL: [CREATE TEMPORARY TABLE](https://dev.mysql.com/doc/refman/8.0/en/create-temporary-table.html)
- Oracle: [Global Temporary Tables](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-TABLE.html)
- Oracle 18c: [Private Temporary Tables](https://docs.oracle.com/en/database/oracle/oracle-database/19/admin/managing-tables.html)
- Db2: [Temporary Tables](https://www.ibm.com/docs/en/db2/11.5?topic=tables-temporary)
- SQL Server: [Memory-Optimized TempDB](https://learn.microsoft.com/en-us/sql/relational-databases/databases/tempdb-database)
- SQL Server: [Table Variable Deferred Compilation](https://learn.microsoft.com/en-us/sql/relational-databases/performance/intelligent-query-processing)
