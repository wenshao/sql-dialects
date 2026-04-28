# 计划缓存淘汰策略 (Plan Cache Eviction Policies)

凌晨三点告警响起：QPS 没变，CPU 飙到 95%，p99 延迟从 5 ms 涨到 800 ms——一查 `sys.dm_exec_cached_plans`，发现计划缓存命中率从 99.5% 跌到 12%。这是计划缓存淘汰失效（plan cache eviction storm）的典型症状：缓存被海量"一次性"动态 SQL 挤爆，热点查询被迫每次硬解析。淘汰算法选错了，吞吐量瞬间塌方。

## 为什么计划缓存淘汰是个核心话题

计划缓存（plan cache / library cache / shared pool）是 OLTP 引擎吞吐量的命脉。一条中等复杂度的 OLTP 查询，硬解析（hard parse）耗时通常在 1-10 ms（涉及解析、绑定、优化器搜索），而命中计划缓存后的执行可能只需 50-200 us。这意味着缓存命中率从 99% 跌到 90%，CPU 消耗在编译上的开销可以从 1% 飙升到 30%——足以把一台原本健康的数据库压垮。

但缓存空间总是有限的。SQL Server 默认 plan cache 最大占 max server memory 的 75%（早期版本），但实际可用空间受其他内存池竞争。Oracle 的 shared pool 是固定大小（或 ASMM 自动调整），library cache 是其中一部分。当缓存满了又有新计划进来，淘汰算法（eviction policy）决定踢谁。如果踢错了：

- **误踢热点计划**：核心 OLTP 查询被迫硬解析，吞吐量塌方
- **保留垃圾计划**：一次性的 ad-hoc 查询占着茅坑，缓存命中率持续下降
- **抖动（thrashing）**：刚刚淘汰的计划立刻又被请求，反复编译反复淘汰
- **碎片化**：library cache 被切成小块，大计划无法分配连续内存

不同引擎在算法上做了不同的折中：SQL Server 用基于代价的 LRU（cost-based aging），Oracle 用 LRU + KEEP/RECYCLE 池，CockroachDB 用简单 LRU（默认 100 entries），TiDB 用会话级 LRU。本文将横向对比 45+ 引擎的淘汰策略，并深入解析几个关键引擎的实现细节。

## 没有 SQL 标准

ISO/IEC 9075（SQL 标准）只在 SQL:1992 定义了 PREPARE / EXECUTE / DEALLOCATE 三条 SQL 层接口（参见 prepared-statement-cache.md），完全没有规定：

- 计划缓存是否存在
- 缓存的作用域（会话级/实例级/集群级）
- 淘汰策略
- 内存上限
- 是否支持显式 pin / unpin
- 缓存命中的判定（文本哈希/规范化/参数化）

这导致每个引擎的实现差异巨大。本文涉及的所有内容都是**实现层概念**，跨引擎迁移时需要重新理解。

## 支持矩阵（45+ 引擎）

### 缓存大小限制与淘汰策略

| 引擎 | 显式大小上限 | 默认上限 | 淘汰算法 | 作用域 | 引入版本 |
|------|--------------|---------|---------|--------|---------|
| SQL Server | 隐式（max server memory 子集） | 内存压力下动态 | LRU + 代价加权老化 | 实例级 | 2005+ |
| Oracle | `SHARED_POOL_SIZE` (KEEP/RECYCLE 子池) | ASMM 动态 | LRU + 锁 + KEEP 池 | 实例级 | 早期 |
| PostgreSQL | 无全局缓存 | -- | -- | 会话级（每个 backend 独立） | 早期 |
| MySQL | Query Cache 已移除 | -- | LRU（query cache 时代） | 实例级（已废弃） | 移除于 8.0.3 |
| MySQL | PS Cache `max_prepared_stmt_count` | 16382 | 显式释放/会话断开 | 会话级 | 5.0+ |
| MariaDB | `query_cache_size` | 0（默认禁用） | LRU + 失效 | 实例级 | 早期 |
| SQLite | `cache_size` (page cache, 非 plan) | 隐式 | -- | 连接级 | 不适用 |
| DB2 LUW | `PCKCACHESZ` | AUTOMATIC | LRU + 引用计数 | 实例级 | 早期 |
| Snowflake | `RESULT_CACHE`（结果缓存，非计划） | 24 小时 | TTL + 失效 | 账号级 | GA |
| BigQuery | 计划/结果均不显式暴露 | 24 小时（结果） | -- | 项目级 | GA |
| Redshift | 编译缓存（compiled segments） | 隐式 | LRU | 集群级 | GA |
| ClickHouse | 不显式暴露 plan cache | -- | -- | 不缓存（每次重新解析） | -- |
| Trino | 不缓存计划 | -- | -- | 协调器内存 | -- |
| Presto | 不缓存计划 | -- | -- | -- | -- |
| Spark SQL | DataFrame 计划缓存 | 隐式 | LRU | 应用级 | -- |
| Hive | -- | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | -- | 不支持 |
| Databricks | 同 Spark + Photon | -- | LRU | 集群级 | -- |
| Teradata | Request Cache `RequestCacheSize` | 隐式 | LRU | 实例级 | V2R6+ |
| Greenplum | 继承 PG（无全局） | -- | -- | 会话级 | -- |
| CockroachDB | `sql.query_cache.enabled` + `--cache` | 100 entries | LRU | 节点级 | 19.x+ |
| TiDB | `tidb_session_plan_cache_size` | 100 | LRU | 会话级 | 4.0+ (会话), 7.1+ (实例) |
| TiDB | `tidb_instance_plan_cache_target_mem_size` | 100MB | LRU | 实例级 | 7.1+ |
| OceanBase | `plan_cache_mem_limit_pct` | 5% 租户内存 | LRU + 命中权重 | 租户级 | 早期 |
| YugabyteDB | 继承 PG | -- | -- | 会话级 | -- |
| SingleStore | Plancache | 自动 | LRU | 节点级 | 7.x+ |
| Vertica | 不缓存（每次重新计划） | -- | -- | -- | -- |
| Impala | Frontend 编译缓存 | 隐式 | LRU | 协调器级 | -- |
| StarRocks | FE 计划缓存 | 隐式 | LRU | FE 级 | 较新 |
| Doris | FE 计划缓存 | 隐式 | LRU | FE 级 | 较新 |
| MonetDB | 不显式暴露 | -- | -- | -- | -- |
| CrateDB | -- | -- | -- | 不显式 | -- |
| TimescaleDB | 继承 PG | -- | -- | 会话级 | -- |
| QuestDB | -- | -- | -- | -- | 不支持 |
| Exasol | 自动 | 隐式 | LRU | 实例级 | -- |
| SAP HANA | `M_SQL_PLAN_CACHE` | `sql_plan_cache_size` | LRU | 实例级 | 早期 |
| Informix | SQ 缓存 | `STMT_CACHE` | LRU + 引用计数 | 实例级 | -- |
| Firebird | 显式 PREPARE | 隐式 | -- | 连接级 | -- |
| H2 | `QUERY_CACHE_SIZE` | 8 (默认) | LRU | 连接级 | 早期 |
| HSQLDB | -- | -- | -- | 连接级 | -- |
| Derby | Statement Cache | `derby.language.statementCacheSize` | LRU | 连接级 | -- |
| Amazon Athena | 仅结果缓存 | 24 小时 | TTL | 工作组级 | -- |
| Azure Synapse | 继承 SQL Server | -- | LRU + 代价加权 | 实例级 | -- |
| Google Spanner | 自动 | 隐式 | -- | 项目级 | GA |
| Materialize | 计划复用（视图/订阅） | -- | -- | 集群级 | -- |
| RisingWave | 继承 PG | -- | -- | 会话级 | -- |
| InfluxDB (SQL/IOx) | -- | -- | -- | 不显式 | -- |
| Databend | -- | -- | -- | 不显式 | -- |
| Yellowbrick | 继承 PG | -- | -- | 会话级 | -- |
| Firebolt | -- | -- | -- | -- | -- |

> 统计：约 14 个引擎拥有显式的全局/实例级计划缓存与可调淘汰策略，约 18 个引擎仅在会话级缓存预编译语句，其余引擎要么不缓存（Trino/ClickHouse/Vertica）要么仅有结果缓存（BigQuery/Athena/Snowflake）。

### 计划编译代价权重与 Pinning

| 引擎 | 代价加权老化 | 显式 PIN | KEEP 池 | 计划基线/Plan Guide | OPTIMIZE FOR AD HOC |
|------|-------------|---------|---------|--------------------|---------------------|
| SQL Server | 是（Compile Cost） | -- | -- | Plan Guide / Query Store | 2008+ |
| Oracle | -- | `DBMS_SHARED_POOL.KEEP` | KEEP/RECYCLE | SQL Plan Baseline | -- |
| PostgreSQL | -- | -- | -- | -- (pg_hint_plan 扩展) | -- |
| MySQL | -- | -- | -- | -- (Optimizer hints) | -- |
| DB2 LUW | -- | 引用计数 | -- | Optimization Profiles | -- |
| Teradata | -- | -- | -- | -- | -- |
| OceanBase | 是（命中权重） | -- | -- | Plan Baseline | -- |
| TiDB | -- | -- | -- | SQL Plan Management | -- |
| CockroachDB | -- | -- | -- | -- | -- |
| Spark SQL | -- | -- | -- | -- | -- |
| SAP HANA | -- | -- | -- | Plan Stability | -- |
| Vertica | 不缓存 | -- | -- | -- | -- |
| YugabyteDB | -- | -- | -- | pg_hint_plan | -- |
| SingleStore | -- | -- | -- | -- | -- |

### 自动参数化与 FORCED PARAMETERIZATION

参数化（auto-parameterization / forced parameterization）影响哪些"看起来不同的 SQL"会共用同一个缓存条目。

| 引擎 | 自动参数化 | 强制参数化 | CURSOR_SHARING | 备注 |
|------|-----------|------------|----------------|------|
| SQL Server | SIMPLE（默认） | `FORCED` (DB 级) | -- | `ALTER DATABASE ... SET PARAMETERIZATION FORCED` |
| Oracle | -- | -- | `EXACT` / `FORCE` / `SIMILAR` | `CURSOR_SHARING=FORCE` 替换字面值 |
| PostgreSQL | -- | -- | -- | 仅 PREPARE 显式参数 |
| MySQL | -- | -- | -- | 仅 PREPARE 显式参数 |
| OceanBase | 是（默认） | `ob_enable_force_serializable_parameter`（受版本影响） | -- | 自动归一化字面值 |
| TiDB | 部分（PreparedStmt 路径） | -- | -- | 显式 PREPARE 走计划缓存 |
| CockroachDB | -- | -- | -- | 仅 prepared statement |
| DB2 LUW | -- | `STMT_CONC=LITERALS` | -- | 字面值参数化 |
| SAP HANA | 是（默认） | -- | -- | -- |

### 系统视图与 DDL 接口

| 引擎 | 缓存视图 | 清空命令 | 失效命令 | 单条目移除 |
|------|---------|---------|---------|-----------|
| SQL Server | `sys.dm_exec_cached_plans` | `DBCC FREEPROCCACHE` | `DBCC FREESYSTEMCACHE` | `DBCC FREEPROCCACHE(plan_handle)` |
| Oracle | `V$SQLAREA` / `V$SQL` | `ALTER SYSTEM FLUSH SHARED_POOL` | `DBMS_SHARED_POOL.PURGE` | `PURGE` 单条 |
| PostgreSQL | `pg_prepared_statements`（会话） | `DEALLOCATE ALL` | -- | `DEALLOCATE name` |
| MySQL | `performance_schema.prepared_statements_instances` | -- | -- | `DEALLOCATE PREPARE name` |
| DB2 LUW | `MON_GET_PKG_CACHE_STMT` | `FLUSH PACKAGE CACHE DYNAMIC` | -- | -- |
| TiDB | `INFORMATION_SCHEMA.STATEMENTS_SUMMARY` | -- | -- | -- |
| OceanBase | `GV$OB_PLAN_CACHE_STAT` / `GV$OB_PLAN_CACHE_PLAN_STAT` | `ALTER SYSTEM FLUSH PLAN CACHE` | -- | -- |
| CockroachDB | `crdb_internal.node_queries` | -- | -- | -- |
| SAP HANA | `M_SQL_PLAN_CACHE` | `ALTER SYSTEM CLEAR SQL PLAN CACHE` | -- | -- |
| Spark SQL | -- | `CLEAR CACHE`（资源缓存，非计划） | -- | -- |

> 注: PostgreSQL 没有"全局计划缓存"，因此也没有清空命令。`DEALLOCATE ALL` 只影响当前会话的预编译语句。

## SQL Server: Plan Cache LRU + 代价加权老化深度解析

SQL Server 的 plan cache 是商用关系数据库中最早实现"基于代价的 LRU"的引擎之一，核心思想是：编译昂贵的计划应该比简单计划更难被淘汰。

### 缓存结构

SQL Server plan cache 内部由四个 cache store 组成：

```sql
-- 查看四个 cache store 的当前状态
SELECT name, type,
       single_pages_kb + multi_pages_kb AS total_kb,
       buckets_count, entries_count
FROM sys.dm_os_memory_cache_counters
WHERE type IN ('CACHESTORE_SQLCP',     -- ad-hoc / auto-param SQL
               'CACHESTORE_OBJCP',     -- 存储过程、触发器、函数
               'CACHESTORE_PHDR',      -- 视图、约束、缺省
               'CACHESTORE_XPROC');    -- 扩展存储过程
```

四个 store 各有独立的 LRU 链表与 hash 表。

### Compile Cost 与 Aging 算法

每个 plan 入缓存时被赋予一个初始代价（cost），定义为：

```
initial_cost = max(IO_cost + CPU_cost + Memory_cost, 0)
单位：page / tick / 字节，归一化为整数

每次缓存命中时：current_cost = initial_cost  (重置为满)
每次后台 lazy writer 扫描时：current_cost -= 1
当 current_cost == 0 且系统有内存压力：可被淘汰
```

这是 SQL Server 的核心创新：编译代价高的计划在被命中后会"回血"到原始 cost，因此即使一段时间没被命中，也比 cost=1 的简单计划更耐淘汰。

### 查看代价

```sql
-- 查看每个计划当前的 cost
SELECT TOP 20
    cp.bucketid,
    cp.refcounts,
    cp.usecounts,
    cp.size_in_bytes,
    cp.cacheobjtype,
    cp.objtype,
    sql.text,
    cp.plan_handle,
    -- 当前 cost（每次 lazy writer 扫描会递减）
    qs.last_elapsed_time AS last_compile_us
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) sql
LEFT JOIN sys.dm_exec_query_stats qs
    ON qs.plan_handle = cp.plan_handle
ORDER BY cp.size_in_bytes DESC;
```

### DBCC FREEPROCCACHE：手动清空

```sql
-- 清空整个 plan cache（生产慎用，会导致大规模硬解析风暴）
DBCC FREEPROCCACHE;

-- 清空特定 plan
DBCC FREEPROCCACHE (0x06000700CA75A123B0207FB...);

-- 清空特定资源池（仅清属于该池的）
DBCC FREEPROCCACHE ('default');

-- 清空特定 cache store
DBCC FREESYSTEMCACHE ('SQL Plans');
DBCC FREESYSTEMCACHE ('Object Plans');
```

注意 `DBCC FREEPROCCACHE` 在生产 OLTP 系统上可能导致瞬间 CPU 飙升（所有热点查询同时硬解析），属于"应急只读"操作。

### Optimize for Ad Hoc Workloads（2008+）

针对"动态 SQL 一次性查询淹没缓存"的常见问题，SQL Server 2008 引入了 server-level 选项：

```sql
-- 启用：第一次执行只缓存一个 ~200 字节的 stub（不缓存完整计划）
EXEC sp_configure 'optimize for ad hoc workloads', 1;
RECONFIGURE;

-- 之后逻辑：
-- 第 1 次执行: 编译完整计划 + 缓存 stub（只记 hash）
-- 第 2 次执行: stub 命中 → 这次才缓存完整计划
-- 这样一次性 SQL 不会浪费完整 plan 的内存
```

启用前缓存中可能有几十万个仅执行一次的"垃圾"计划占用 GB 级内存，启用后这些 SQL 只占 200 字节 stub，整体 plan cache 内存可能下降到原来的 20-30%。

```sql
-- 验证：查看 stub 与完整 plan 的比例
SELECT
    objtype,
    cacheobjtype,
    COUNT(*) AS plan_count,
    SUM(size_in_bytes) / 1024 / 1024 AS size_mb
FROM sys.dm_exec_cached_plans
GROUP BY objtype, cacheobjtype
ORDER BY size_mb DESC;
-- 启用 optimize for ad hoc 后会看到大量 'Compiled Plan Stub' 类型条目
```

### Forced Parameterization

```sql
-- 数据库级开关：强制把所有字面值参数化
ALTER DATABASE MyDB SET PARAMETERIZATION FORCED;

-- 默认 SIMPLE 参数化只对极简查询生效（无 join、无子查询、无聚合）
-- FORCED 参数化对几乎所有查询生效，但可能引发 parameter sniffing 问题
```

### 内存压力下的淘汰

SQL Server 的 plan cache 不是固定大小，而是受多重压力调节：

```
Local memory pressure (instance):
  - max server memory 接近时
  - 触发 lazy writer 扫描所有 cache store
  - cost 递减到 0 的 plan 立即被释放

Global memory pressure (Windows):
  - OS Working Set 警告
  - SQL Server 主动释放更多缓存

Cache size limits (内置阈值，2008+):
  - Plan cache 上限 = 75% of (max server memory - 0~4GB) for first 4GB
                    + 10% of (max server memory - 4~64GB)
                    + 5% of (max server memory - >64GB)
  - 超过上限时触发淘汰
```

## Oracle: Library Cache LRU + Pinned + KEEP 池

Oracle 的 library cache（共享池的子区域）是关系数据库 plan cache 的"鼻祖"，其设计影响了后续几乎所有引擎。

### Library Cache 结构

Library cache 不只缓存 SQL 计划，还包括：

```
Library cache 内容：
  - SQL cursors (parsed + optimized plans)
  - PL/SQL packages, procedures, functions
  - Java classes, views, synonyms
  - Schema objects metadata

每个对象有：
  - Library cache handle（hash 索引）
  - Library cache object (LCO)：实际数据
  - Pin/Lock 计数器
  - LRU position
```

### 父子游标（Parent/Child Cursor）

Oracle 区分父游标（同一 SQL 文本）和子游标（同一 SQL + 不同绑定 / 优化器环境 / NLS 设置等）：

```sql
-- 一个 SQL 文本一个父游标
-- 不同会话、不同环境可能产生多个子游标
SELECT sql_id, child_number, plan_hash_value, executions, optimizer_env_hash_value
FROM V$SQL
WHERE sql_text LIKE 'SELECT * FROM orders WHERE customer_id = :1%'
ORDER BY sql_id, child_number;
```

子游标过多（通常 >1000）是常见性能病症，会导致库缓存碎片化和 cursor: pin S 等待。

### LRU 与 Pin/Lock

```
Pin (执行中):
  - 当前正在执行的 SQL，不能被淘汰
  - Pin 计数 > 0 时，对象固定在 library cache
  - 执行结束后 unpin

Lock (持有中):
  - 会话持有的 cursor 引用
  - 持有期间不能被 DROP / ALTER

LRU position:
  - 未 pin / 未 lock 的对象按 LRU 排队
  - shared pool 内存压力时从 LRU 尾部淘汰
```

### KEEP 池：永不淘汰

`DBMS_SHARED_POOL.KEEP` 把对象固定在 library cache 中，不参与 LRU 淘汰：

```sql
-- 查找特定 SQL 的 address 和 hash_value
SELECT address, hash_value, sql_text
FROM V$SQLAREA
WHERE sql_text LIKE '%critical_query%';

-- KEEP 一个 cursor
EXEC DBMS_SHARED_POOL.KEEP('00000000A1B2C3D4, 12345678', 'C');
-- 第二个参数：'C' = cursor, 'P' = procedure, 'R' = trigger, ...

-- 检查已 KEEP 的对象
SELECT * FROM V$DB_OBJECT_CACHE WHERE kept = 'YES';

-- 取消 KEEP
EXEC DBMS_SHARED_POOL.UNKEEP('00000000A1B2C3D4, 12345678', 'C');
```

KEEP 适合用于：

- 高频但不规则访问的 SQL（普通 LRU 可能淘汰）
- 大型 PL/SQL 包（避免反复加载）
- 关键存储过程

### Buffer Cache 的 KEEP/RECYCLE 池（注意区分）

Oracle 还有 buffer cache 层面的 `DB_KEEP_CACHE_SIZE` 和 `DB_RECYCLE_CACHE_SIZE`：

```sql
-- buffer cache 的多池架构（与 library cache 是不同的概念）
ALTER SYSTEM SET DB_KEEP_CACHE_SIZE = 2G;
ALTER SYSTEM SET DB_RECYCLE_CACHE_SIZE = 512M;

-- 把表分配到 KEEP 池（数据块级别的"不淘汰"）
ALTER TABLE small_lookup_table STORAGE (BUFFER_POOL KEEP);
ALTER TABLE huge_log_table STORAGE (BUFFER_POOL RECYCLE);
```

注意：`DB_KEEP_CACHE_SIZE` 是数据块缓存的"KEEP 池"（小表常驻），不是 library cache 的 KEEP。`DBMS_SHARED_POOL.KEEP` 才是 library cache 的"pin"。两者经常被混淆。

### ALTER SYSTEM FLUSH SHARED_POOL

```sql
-- 清空整个 shared pool（包括 library cache 和 row cache）
ALTER SYSTEM FLUSH SHARED_POOL;

-- 但不会清空 KEEP 的对象，也不会清空 pin 中的 cursor

-- 清空特定 cursor（更精细）
EXEC DBMS_SHARED_POOL.PURGE('00000000A1B2C3D4, 12345678', 'C');
```

`FLUSH SHARED_POOL` 在生产系统上同样危险，会触发大规模硬解析风暴。

### Library Cache 命中率诊断

```sql
-- 整体命中率
SELECT namespace,
       gets, gethits,
       ROUND(gethits * 100.0 / NULLIF(gets, 0), 2) AS gethit_ratio,
       pins, pinhits,
       ROUND(pinhits * 100.0 / NULLIF(pins, 0), 2) AS pinhit_ratio,
       reloads, invalidations
FROM V$LIBRARYCACHE;

-- 健康指标：gethit_ratio 和 pinhit_ratio 都应 > 95%
-- reloads / pins > 1% 表明 shared pool 太小
-- invalidations 高表明频繁 DDL 导致计划失效
```

## PostgreSQL: 没有全局计划缓存，深度解析

PostgreSQL 是主流商用/开源 RDBMS 中"另类"的存在：**没有全局 plan cache**。每个 backend 进程独立维护自己的 prepared statement cache。

### 设计选择

PG 的进程模型导致：

```
每个连接 = 独立的 backend 进程
  - 独立的 plan cache（仅 prepared statement 缓存）
  - 进程结束 → 缓存全部丢弃
  - 进程间不共享 plan
```

这与 SQL Server / Oracle 的"实例级共享缓存"形成鲜明对比。

### pg_prepared_statements

```sql
-- 查看当前会话的 prepared statement 列表
SELECT name, statement, prepare_time, parameter_types, from_sql, generic_plans, custom_plans
FROM pg_prepared_statements;

-- 字段含义：
-- generic_plans: 已使用通用计划（不依赖参数值）的次数
-- custom_plans: 已使用定制计划（每次重新优化）的次数

-- PG 在前 5 次 EXECUTE 时使用 custom plan（针对实际参数优化）
-- 之后比较平均代价：如果 generic plan 平均代价更低 → 切换为 generic
```

这个 5 次切换逻辑在 plan_cache.c 中（`CACHED_PLAN_THRESHOLD = 5`）。

### 缺失全局缓存的代价

```
痛点 1：高 QPS OLTP 应用必须配合连接池
  - PgBouncer / pgcat 通过复用 backend 让 prepared statement 跨"客户端连接"复用
  - 没有连接池 → 每次新连接都要重新 PREPARE

痛点 2：transaction-mode pooling 时 prepared statement 失效
  - PgBouncer transaction mode 下，每次事务结束 backend 可能换给别的客户端
  - PREPARE 状态丢失 → 必须每次都 PREPARE
  - PG 14+ 引入 protocol-level prepared statement 但 PgBouncer 直到 1.21 才支持

痛点 3：内存占用高
  - 每个 backend 各自缓存一份 → N 连接 × M 模板 = N×M 份 plan
  - 1000 连接 × 100 模板 = 10 万份 plan（实际是 SQL Server / Oracle 的几十倍）
```

### PgBouncer Plan Cache（1.21+）

为缓解上述痛点，PgBouncer 1.21（2023）引入了 protocol-level prepared statement 支持：

```ini
# pgbouncer.ini
max_prepared_statements = 100   ; 每个客户端可缓存的 plan 数

# 工作原理：
# 1. 客户端 PREPARE → PgBouncer 转发给后端，记录 PS 元数据
# 2. 客户端 EXECUTE → PgBouncer 检查后端是否已有该 PS，若无则补 PREPARE 后再 EXECUTE
# 3. 后端 backend 在 PgBouncer 视角下"伪装"成总是有 PS 的
```

这相当于在 PgBouncer 层模拟了一个"全局" PREPARE cache，但仍然不是 PG 引擎本身的 plan cache。

### plan_cache_mode（PG 12+）

可以强制 generic / custom 行为：

```sql
SET plan_cache_mode = auto;          -- 默认：5 次后比较代价
SET plan_cache_mode = force_custom_plan;
SET plan_cache_mode = force_generic_plan;
```

`force_generic_plan` 适合参数分布稳定、希望避免重复优化的场景；`force_custom_plan` 适合参数分布差异巨大、generic plan 经常表现差的场景。

### 未来方向

PG 社区一直有"全局 plan cache"的提议，但落地难度大：

```
设计挑战：
  - 共享内存的并发控制（lwlock / spin lock）会成为新瓶颈
  - 计划失效（DDL、统计信息更新）需要跨进程通知
  - Catalog snapshot 的可见性：不同 backend 看到不同 catalog 版本
  - 多版本计划：同一 SQL 在不同 search_path / 角色下计划不同

替代方案：
  - 加强 PgBouncer 等中间层
  - 引入 background worker 维护"共享元数据"
  - 长连接 + 客户端连接池（如 HikariCP）
```

截至 PG 17，全局 plan cache 仍未列入主线开发计划，这是 PG 在 OLTP 高频场景下相对 Oracle / SQL Server 的明显短板。

## MySQL: Query Cache 的兴衰

MySQL Query Cache 是 plan cache 史上最著名的反面案例。

### Query Cache 的设计

```
Query Cache 缓存的是结果集，不是计划：
  - SQL 文本作为 key
  - 完整结果集作为 value
  - 表数据变更时 → 该表所有缓存项失效

设计假设：
  - 大部分查询是只读的
  - 同一查询会被反复执行
  - 表更新不频繁
```

### 为什么失败

Query Cache 在 5.7 被默认禁用，8.0.3 被完全移除（2017 年发布的 8.0.3 RC）：

```
问题 1：粗粒度失效
  - 表中任一行更新 → 该表所有 query cache 项失效
  - OLTP 场景几乎永远在写 → 命中率极低

问题 2：全局互斥锁
  - query cache 全局 mutex 在多核下成为瓶颈
  - 16 核以上 CPU 反而比禁用 query cache 慢

问题 3：内存碎片化
  - 不同大小的结果集填入定长 block
  - 长时间运行后 free list 碎片化严重

问题 4：字面值敏感
  - 'SELECT 1' 与 'select 1' 不命中（后者是不同 hash）
  - 字面值一变就 miss → OLTP 场景近乎无效
```

MySQL 8.0.3 release notes：

> The query cache is now removed. The QUERY_CACHE_TYPE, QUERY_CACHE_LIMIT, QUERY_CACHE_SIZE, and QUERY_CACHE_WLOCK_INVALIDATE system variables, and the FLUSH QUERY CACHE and RESET QUERY CACHE statements, were removed.

### MySQL 8.0+ 的预编译语句缓存

8.0 之后 MySQL 仍支持 prepared statement，但是会话级：

```sql
-- 准备语句
PREPARE stmt FROM 'SELECT * FROM orders WHERE id = ?';

-- 执行
SET @id = 12345;
EXECUTE stmt USING @id;

-- 释放
DEALLOCATE PREPARE stmt;

-- 查看会话内的 prepared statement
SELECT * FROM performance_schema.prepared_statements_instances;

-- 全局上限
SHOW VARIABLES LIKE 'max_prepared_stmt_count';
-- 默认 16382，达到上限再 PREPARE 会报 1461 错误
```

会话级预编译语句没有自动 LRU 淘汰：达到 `max_prepared_stmt_count` 上限时，新的 PREPARE 会失败而不是淘汰旧的。

### MariaDB 仍保留 Query Cache（默认禁用）

```sql
-- MariaDB 仍可启用 query cache
SET GLOBAL query_cache_size = 256 * 1024 * 1024;
SET GLOBAL query_cache_type = ON;

-- 但社区共识仍然是：除非确认是只读重负载，否则不要开启
```

## CockroachDB: 简单 LRU + 100 条上限

CockroachDB 在 19.x 引入计划缓存，设计上明显参考了简单实现：

```sql
-- 集群级配置
SHOW CLUSTER SETTING sql.query_cache.enabled;

-- 默认开启，缓存 prepared statement 的优化结果
-- 节点级，不跨节点共享
```

### LRU 行为

```
缓存大小：sql.query_cache.size（默认 8 MiB）
等价槽位：默认 ~100 entries
淘汰算法：纯 LRU，无代价加权
作用域：每个节点独立
```

### 查看与诊断

```sql
-- 当前节点活跃 query
SELECT query_id, txn_id, statement
FROM crdb_internal.node_queries
LIMIT 10;

-- 集群指标（从 Prometheus 或 _status/vars）
-- sql.query.cache.hits
-- sql.query.cache.misses
-- sql.query.cache.evictions
```

CockroachDB 没有暴露 plan cache 的 system view，主要通过 metrics 监控。

## TiDB: 会话级 + 实例级双层缓存

TiDB 7.1+ 引入了实例级 plan cache，与原有会话级形成双层架构：

### 会话级 Plan Cache（4.0+）

```sql
-- 会话级，每个 session 独立
SHOW VARIABLES LIKE 'tidb_session_plan_cache_size';
-- 默认 100

-- 启用 prepared plan cache
SET tidb_enable_prepared_plan_cache = ON;

-- 查看会话级缓存命中
SELECT * FROM INFORMATION_SCHEMA.STATEMENTS_SUMMARY
WHERE PLAN_CACHE_HITS > 0
ORDER BY PLAN_CACHE_HITS DESC;
```

### 实例级 Plan Cache（7.1+）

```sql
-- 实例级（节点内所有 session 共享）
SHOW VARIABLES LIKE 'tidb_instance_plan_cache_target_mem_size';
-- 默认 100MB

SHOW VARIABLES LIKE 'tidb_enable_instance_plan_cache';
SET GLOBAL tidb_enable_instance_plan_cache = ON;

-- 实例级缓存命中
SHOW VARIABLES LIKE 'tidb_instance_plan_cache%';
```

### 非 PreparedStmt 的 General Plan Cache

```sql
-- 7.0+ 支持非 prepared 路径的 plan cache
SET tidb_enable_non_prepared_plan_cache = ON;

-- 这意味着普通 SELECT（无显式 PREPARE）也能进入 plan cache
-- 受 tidb_non_prepared_plan_cache_size 限制
```

### 淘汰算法

```
TiDB 会话级：纯 LRU
TiDB 实例级：LRU + 内存目标
  - 当 size 超过 target_mem_size 时按 LRU 淘汰
  - 不区分编译代价（无代价加权）
  - 不支持显式 pin
```

## OceanBase: 租户级 + 命中权重

OceanBase 的 plan cache 在分布式数据库中较为成熟，原生设计就考虑了多租户隔离：

```sql
-- 租户级配置
ALTER SYSTEM SET plan_cache_mem_limit_pct = 5;  -- 占租户内存 5%
ALTER SYSTEM SET plan_cache_evict_interval = 1s;

-- 查看 plan cache 状态
SELECT * FROM GV$OB_PLAN_CACHE_STAT;

-- 字段：mem_used, mem_hold, hit_count, miss_count, plan_num, ...

-- 单条 plan 信息
SELECT plan_id, sql_id, type, hit_count, executions,
       elapsed_time, cpu_time, mem_used
FROM GV$OB_PLAN_CACHE_PLAN_STAT
ORDER BY hit_count DESC LIMIT 20;
```

### 淘汰策略

```
触发条件：
  - 内存占用接近 plan_cache_mem_limit_pct 上限
  - 后台 evict 任务定期触发（plan_cache_evict_interval）

淘汰算法：
  - 基于命中权重的 LRU
  - 命中次数高的 plan 排到前面，难被淘汰
  - 类似 SQL Server 的 cost-based aging，但权重维度不同（命中 vs 编译代价）
```

### 自动参数化

OceanBase 默认对所有 SQL 进行自动参数化，类似 SQL Server 的 SIMPLE 参数化但更激进：

```sql
-- 输入：
SELECT * FROM orders WHERE customer_id = 100;
SELECT * FROM orders WHERE customer_id = 200;

-- OB 内部归一化为：
SELECT * FROM orders WHERE customer_id = ?;
-- 两条 SQL 共用同一个 plan cache 条目
```

## Spark SQL: DataFrame Plan 复用

Spark SQL 不像 OLTP 引擎那样有"hash 表 + LRU"的 plan cache，但 DataFrame API 提供了类似的复用机制：

```scala
// DataFrame 的逻辑计划被分析（analyzed）一次后缓存
val df = spark.read.parquet("path").filter("status = 'OK'")
df.cache()       // 缓存计算结果（不是 plan）

// 通过 .persist() / .cache() 缓存的是 RDD 中间结果
// 计划本身在每次 action 时如果未变化，会复用
```

实际上 Spark 的"计划"在每次查询时都会重新分析、优化（Catalyst pass），但优化器中的部分子表达式有 memoization：

```
CacheManager:
  - DataFrame.cache() / persist() 注册 LogicalPlan → RDD 映射
  - 后续查询遇到相同 LogicalPlan 子树 → 直接复用 RDD
  - 不是传统意义上的 plan cache，更像是结果集缓存
```

## SAP HANA: M_SQL_PLAN_CACHE

HANA 的 plan cache 视图非常详细：

```sql
-- 整体状态
SELECT * FROM M_SQL_PLAN_CACHE_OVERVIEW;
-- 字段：PLAN_CACHE_SIZE, USED_PLAN_CACHE_SIZE, PLAN_CACHE_HIT_RATIO,
--      EVICTED_PLAN_COUNT, ...

-- 单条 plan
SELECT plan_id, statement_hash, statement_string,
       execution_count, total_execution_time,
       plan_size, last_execution_timestamp
FROM M_SQL_PLAN_CACHE
ORDER BY execution_count DESC LIMIT 20;

-- 清空整个 plan cache
ALTER SYSTEM CLEAR SQL PLAN CACHE;

-- 配置上限
-- 通过 inifile 配置: [sql] plan_cache_size = 4G
```

HANA 的特点：

- LRU 淘汰
- 默认开启自动参数化（类似 OB）
- 提供 Plan Stability：把好的 plan 固化下来

## DB2 LUW: PCKCACHESZ + 引用计数

DB2 LUW 的 package cache 有显式上限 `PCKCACHESZ`：

```sql
-- 查看配置
SELECT NAME, VALUE FROM SYSIBMADM.DBCFG WHERE NAME = 'pckcachesz';

-- AUTOMATIC（默认）：DB2 自动调整
-- 数字：固定 4KB 页数

-- 查看缓存中的 SQL
SELECT EXECUTABLE_ID, NUM_EXECUTIONS, TOTAL_CPU_TIME, STMT_TEXT
FROM TABLE(MON_GET_PKG_CACHE_STMT(NULL, NULL, NULL, -2))
ORDER BY NUM_EXECUTIONS DESC
FETCH FIRST 10 ROWS ONLY;

-- 清空动态 SQL 缓存
FLUSH PACKAGE CACHE DYNAMIC;
```

DB2 用引用计数管理：执行中的语句不可被淘汰，引用计数归零后进入 LRU。

### STMT_CONC=LITERALS（字面值参数化）

```sql
-- 类似 SQL Server 的 forced parameterization
-- 在 db2set 中设置：
db2set DB2_STMM_LITERALS=LITERALS

-- 或语句级设置：
SET CURRENT STATEMENT CONCENTRATOR = LITERALS;

-- 之后 SELECT * FROM t WHERE id = 1 与 = 2 共用同一 plan
```

## Teradata: Request Cache

Teradata 的 plan cache 称为 request cache，作用域是实例级：

```sql
-- 查看当前缓存
SELECT * FROM DBC.RequestSummaryV;

-- 配置（DBSControl）
-- RequestCacheSize: 默认 60% of segment size
-- 淘汰：LRU
```

Teradata 在 SCRIPT / MACRO / VIEW 等多种粒度上都有缓存，与 Oracle library cache 思路类似。

## 关键设计争议与权衡

### 1. 全局缓存 vs 会话级缓存

```
全局缓存（Oracle, SQL Server, OB, HANA）：
  + 内存效率高（一份计划多 session 共享）
  + 跨连接命中率高
  - 共享内存并发控制复杂（latch / mutex）
  - 失效策略需要跨进程协调

会话级缓存（PostgreSQL, MySQL prepared）：
  + 实现简单，无并发问题
  + 进程隔离强，互不影响
  - 内存浪费（N 连接 × M 模板）
  - 必须配合连接池才能发挥价值
```

### 2. 纯 LRU vs 代价加权 LRU

```
纯 LRU（CockroachDB, TiDB, HANA, Teradata 等）：
  + 实现简单
  + 内存可预测
  - 大计划被频繁短促命中可能挤掉小但更重要的计划

代价加权 LRU（SQL Server, OceanBase）：
  + 编译昂贵的计划更"难淘汰"
  + 适合 OLTP 高复杂度查询为主的场景
  - 实现复杂，代价定义需要平衡
  - 极端情况下"垃圾大计划"长期占用空间
```

### 3. Pin / KEEP 池的必要性

```
有 KEEP 池（Oracle）：
  + 关键 SQL 永不淘汰
  + DBA 可以做精细化运维
  - 容易被滥用导致 shared pool 耗尽
  - KEEP 决策依赖人工判断

无 KEEP 池（大多数引擎）：
  + 一致性强，纯算法决策
  - 无法保护关键路径
  - 极端场景下需要应用层重试
```

### 4. 自动参数化（auto-param）的双刃剑

```
启用自动参数化：
  + 缓存命中率显著提升（同一模板共用 plan）
  + 减少硬解析

  - parameter sniffing 问题（首次参数决定 plan，后续参数差异大时性能塌方）
  - 字段类型推断错误可能导致 plan 不优
```

参见 prepared-statement-cache.md 中的 parameter sniffing 详细讨论。

### 5. Optimize for Ad Hoc Workloads 的副作用

```
SQL Server 启用 optimize for ad hoc workloads：
  + 一次性 SQL 不浪费内存（只缓存 stub）
  + 缓存空间留给真正高频的 SQL

  - 第二次执行才缓存完整 plan（多一次硬解析）
  - 对"两次执行后就不再用"的 SQL 反而更慢
```

最佳实践：在动态 SQL 比例高的环境（如 ORM 生成的查询）开启，纯存储过程环境无需开启。

## 与 Prepared Statement Cache 的关系

参见 prepared-statement-cache.md，两者是互补关系：

```
Prepared Statement Cache（PS Cache）：
  - 存储 PS 句柄 → SQL 文本 + 元数据
  - 主要为客户端协议服务
  - 通常会话级

Plan Cache：
  - 存储 SQL 文本 → 优化后的执行计划
  - 主要为优化器服务
  - 全局或会话级

关系：
  - PS Cache 命中 → 仍可能 plan cache miss（首次 EXECUTE 才编译）
  - Plan Cache 命中 → 不需要重新优化，直接执行
  - 两者都命中 → 最快路径（"软软解析"）
```

## 与 Query Fingerprinting 的关系

参见 query-fingerprinting.md，指纹是 plan cache 的"key 候选"：

```
Plan Cache 命中判定的常见做法：
  1. 字面值敏感：完整 SQL hash → key
  2. 字面值不敏感：parameterize 后的 SQL hash → key（query fingerprint）
  3. 计划级 hash：plan_hash_value（同一 SQL 不同 plan 算不同 entry）

不同引擎的选择：
  - SQL Server：默认完整 hash（除非启用 forced parameterization）
  - Oracle：sql_id（基于完整文本）+ child cursor（同 sql_id 多 plan）
  - PostgreSQL：PREPARE name（显式）
  - OceanBase：自动参数化后的 hash（fingerprint）
```

## 关键发现

1. **没有 SQL 标准**：plan cache 的存在、形态、API 完全由各引擎自行决定，跨引擎迁移需要重新理解。
2. **全局缓存仅约 14 个引擎拥有**：SQL Server、Oracle、OceanBase、TiDB（7.1+ 实例级）、SAP HANA、DB2、Teradata、Exasol、Informix 等是少数派；PostgreSQL、MySQL、CockroachDB 等用会话级或没有。
3. **PostgreSQL 是个特例**：作为主流 OLTP 数据库竟然没有全局 plan cache，必须依赖 PgBouncer 等中间层弥补。
4. **MySQL Query Cache 已死**：8.0.3（2017）正式移除，是历史上著名的"看似聪明实则失败"的设计。
5. **SQL Server 的 cost-based aging 是商用引擎的最高水平**：编译代价高的计划更难被淘汰，配合 optimize for ad hoc 是 OLTP 调优的关键工具。
6. **Oracle 的 KEEP 池在大型企业仍有价值**：DBMS_SHARED_POOL.KEEP 让 DBA 能精细化保护关键 SQL，是其他引擎缺失的能力。
7. **CockroachDB 默认 100 条非常保守**：节点级 100 entries 在高并发场景容易爆，需要监控 sql.query.cache.evictions 调整。
8. **TiDB 的双层架构是分布式数据库的代表**：会话级（默认 100）+ 实例级（7.1+，默认 100MB）覆盖了不同访问模式。
9. **OceanBase 的命中权重 LRU 与 SQL Server 思路不同但目标一致**：都是让"重要"的 plan 更难淘汰，但权重定义不同（命中次数 vs 编译代价）。
10. **Forced Parameterization 是双刃剑**：能极大提升缓存命中率，但 parameter sniffing 风险被放大；SQL Server FORCED、Oracle CURSOR_SHARING=FORCE、OceanBase 默认开启都有这一权衡。
11. **DBCC FREEPROCCACHE / FLUSH SHARED_POOL 不是日常工具**：会触发硬解析风暴，仅用于应急或测试环境清理。
12. **plan cache 的"没有"也是设计选择**：Trino / ClickHouse / Vertica 等 OLAP 引擎选择不缓存计划，每次重新优化以适应数据变化。

## 对引擎开发者的实现建议

### 1. 缓存键的设计

```
传统方案：完整 SQL 文本 hash
  - 优点：实现简单
  - 缺点：字面值差异即 miss

参数化方案：归一化后 hash（推荐）
  - 把字面值替换为占位符后 hash
  - 提升命中率 10-100 倍（OLTP 典型场景）
  - 注意：归一化需考虑 IN (...) 列表、Hint 注释、多空格折叠

复合键方案：
  - SQL hash + 优化器参数 hash（NLS / search_path / role / 隔离级别）
  - 避免不同环境共用错误的 plan
```

### 2. 淘汰算法的工程权衡

```
最小可行方案：纯 LRU
  - 用双向链表 + hash 表
  - 空间复杂度 O(N)，每次操作 O(1)
  - 适合简单实现（CockroachDB 早期、TiDB）

进阶方案：Cost-aware LRU
  - 每个 entry 带 cost 字段
  - 命中时 cost 重置或递增
  - 后台 sweep 时 cost 递减，归零才进入 evict 候选
  - SQL Server 风格

更进阶方案：LRU-K / Clock-Pro / W-TinyLFU
  - 学术界已研究 30+ 年的算法
  - 但生产引擎几乎都用简化版（Cost-aware LRU 或纯 LRU）
  - 原因：复杂算法的常数开销在数据库场景往往得不偿失

切勿过度工程：
  - 不要为了"看起来高级"引入 Clock-Pro
  - 简单 LRU + 监控指标 + 暴露 free 命令往往够用
```

### 3. 并发控制

```
全局 plan cache 必须解决：
  - 多线程查找命中（读多）
  - 多线程插入新 plan（写少）
  - 后台 sweep 与前台并发

推荐方案：
  - 分桶（bucketing）：N 个独立桶，每桶独立 mutex/RWLock
  - 桶数选择：CPU 核数 × 4 或 hash 表大小的 1/16
  - SQL Server / Oracle 都用类似机制

避免：
  - 全局 mutex（MySQL Query Cache 的失败原因之一）
  - 复杂无锁结构（实现复杂度远超收益）
```

### 4. 失效与一致性

```
DDL 必须触发计划失效：
  - ALTER TABLE / DROP INDEX / ANALYZE 等
  - 标记相关 plan 为 invalid（不立即释放）
  - 下次执行前检查 invalid 标志

统计信息更新触发软失效：
  - PG: pg_statistic 变化时部分 plan 重新规划
  - SQL Server: 自动更新统计信息后重新编译
  - Oracle: dbms_stats.gather_table_stats 触发 rolling invalidation

跨节点失效（分布式）：
  - 元数据 epoch / 版本号
  - DDL 通过 metadata service 广播
  - TiDB / CockroachDB / OceanBase 都有此机制
```

### 5. 监控与可观测性

```
最少应暴露的指标：
  - cache_size_bytes（当前占用）
  - cache_size_limit（上限）
  - hit_count / miss_count（命中率）
  - eviction_count（被淘汰数）
  - compile_count（硬解析数）

进阶指标：
  - eviction_by_memory_pressure vs eviction_by_size_limit
  - top-N hot plans（按 hit count）
  - top-N memory plans（按 size）
  - average compile cost
  - cache thrashing detection（淘汰后短时间内重新插入的比例）

暴露管理 API：
  - SHOW PLAN CACHE STAT
  - SELECT FROM <plan_cache_view>
  - ADMIN FLUSH PLAN CACHE
  - ADMIN PIN PLAN <hash>
```

### 6. 测试要点

```
功能测试：
  - 同一 SQL 多次执行：第一次 miss，后续 hit
  - DDL 后失效：ALTER TABLE 后 plan 应被标记 invalid
  - 自动参数化：字面值差异的 SQL 共用 plan

容量测试：
  - 缓存达上限后插入新 plan：旧 plan 被淘汰
  - 内存压力下：cache 主动收缩
  - 并发插入：无 race condition

压力测试：
  - 高 QPS（>10 万）下 cache 不成为瓶颈
  - 持续 24 小时：无内存泄漏、无碎片化
  - 缓存命中率稳定（不抖动）

回归测试：
  - parameter sniffing 场景：首次参数与后续差异巨大时性能不塌方
  - 缓存爆破：海量 ad-hoc SQL 不挤垮热点 plan
```

### 7. 性能调优建议（DBA 视角）

```
SQL Server：
  - 监控 sys.dm_os_memory_clerks 中 CACHESTORE_SQLCP / CACHESTORE_OBJCP
  - 启用 optimize for ad hoc workloads（除非纯存储过程环境）
  - 避免随手 DBCC FREEPROCCACHE

Oracle：
  - 监控 V$LIBRARYCACHE 的 reload / invalidation
  - 检查 V$SQLAREA 中 child cursor 数量异常的 SQL
  - shared_pool 大小经验：是 SGA 的 10-20%

PostgreSQL：
  - 务必使用连接池（PgBouncer / pgcat / pgcat / odyssey）
  - PgBouncer 1.21+ 支持 protocol-level prepared statement
  - 监控 pg_prepared_statements 防止单连接 PS 泄漏

TiDB：
  - 7.1+ 启用 tidb_enable_instance_plan_cache
  - 调整 tidb_instance_plan_cache_target_mem_size（默认 100MB 偏小）
  - 监控 STATEMENTS_SUMMARY 的 PLAN_CACHE_HITS 比例

OceanBase：
  - 调整 plan_cache_mem_limit_pct（默认 5% 在小租户下偏小）
  - 监控 GV$OB_PLAN_CACHE_STAT 的 hit_count / miss_count
  - DDL 频繁时考虑 plan_cache_evict_interval

CockroachDB：
  - 默认 100 entries 不够用，调高 sql.query_cache.size
  - 监控 sql.query.cache.evictions 速率
```

### 8. 常见反模式

```
反模式 1：每次都 PREPARE / DEALLOCATE
  - 等同于禁用 plan cache
  - ORM 框架经常踩坑（每次执行都重新创建 prepared statement）
  - 修复：使用连接级 PS 复用

反模式 2：DBCC FREEPROCCACHE 当作"重启大法"
  - 任何性能问题都先清空 plan cache
  - 短期看好像缓解，实则掩盖根本问题
  - 修复：定位真正原因（统计信息陈旧、parameter sniffing 等）

反模式 3：无限 PIN
  - Oracle DBA 把所有"重要" SQL 都 KEEP
  - shared pool 被 KEEP 对象塞满，新 SQL 无法入库
  - 修复：审计 KEEP 列表，仅保留真正高频且大计划的 SQL

反模式 4：忽略 plan cache 命中率
  - 监控 CPU / IO 但不监控编译开销
  - 命中率从 99% 跌到 90% 时不报警
  - 修复：把 cache hit ratio 加入核心监控

反模式 5：FORCED PARAMETERIZATION 作为银弹
  - 一开就解决所有"plan cache miss"问题
  - 实际触发 parameter sniffing，少数 SQL 性能塌方
  - 修复：评估每个 SQL 的参数分布，对高风险 SQL 显式 OPTION (RECOMPILE)
```

## 总结对比矩阵

### 核心能力对比

| 能力 | SQL Server | Oracle | PostgreSQL | MySQL | TiDB | OceanBase | CockroachDB | HANA | DB2 |
|------|-----------|--------|------------|-------|------|-----------|-------------|------|-----|
| 全局 plan cache | 是 | 是 | -- | -- | 7.1+ | 是 | 节点级 | 是 | 是 |
| 显式大小上限 | 隐式 | SHARED_POOL | -- | -- | 是 | 百分比 | 是 | 是 | 是 |
| 代价加权淘汰 | 是 | -- | -- | -- | -- | 命中权重 | -- | -- | -- |
| KEEP/PIN | -- | KEEP | -- | -- | -- | -- | -- | -- | -- |
| 自动参数化 | SIMPLE | -- | -- | -- | 部分 | 默认 | -- | 默认 | -- |
| Forced Parameterization | 是 | CURSOR_SHARING | -- | -- | -- | 部分 | -- | -- | LITERALS |
| 清空命令 | DBCC FREEPROCCACHE | FLUSH SHARED_POOL | -- | -- | -- | FLUSH PLAN CACHE | -- | CLEAR | FLUSH |
| 系统视图 | dm_exec_cached_plans | V$SQLAREA | pg_prepared_statements | PS table | STATEMENTS_SUMMARY | GV$OB_PLAN_CACHE_STAT | crdb_internal | M_SQL_PLAN_CACHE | MON_GET_PKG_CACHE_STMT |
| Plan Baseline / Guide | Plan Guide / Query Store | SQL Plan Baseline | pg_hint_plan | -- | SPM | Plan Baseline | -- | Plan Stability | Optimization Profiles |

### 引擎选型建议

| 场景 | 推荐引擎 | 原因 |
|------|---------|------|
| 高频 OLTP（QPS > 10 万） | SQL Server / Oracle / OceanBase | 全局缓存 + 代价加权 + 成熟运维工具 |
| OLTP + 复杂动态 SQL | SQL Server + optimize for ad hoc | stub 机制避免缓存爆破 |
| OLAP 即席查询 | Trino / ClickHouse | 不缓存计划，每次重新优化更适合多变查询 |
| 混合负载（HTAP） | TiDB 7.1+ / OceanBase | 双层缓存 + 分布式失效 |
| PG 生态 OLTP | PG + PgBouncer 1.21+ | protocol-level PS + 连接池 |
| 关键 SQL 保护 | Oracle KEEP 池 | 唯一支持显式 pin 的主流引擎 |
| 极简部署 | SQLite / DuckDB | 单连接，缓存问题被抹平 |

## 参考资料

- SQL Server: [Cached Plans](https://learn.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/sys-dm-exec-cached-plans-transact-sql)
- SQL Server: [Plan Caching](https://learn.microsoft.com/en-us/sql/relational-databases/query-processing-architecture-guide#execution-plan-caching-and-reuse)
- SQL Server: [Optimize for Ad Hoc Workloads](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/optimize-for-ad-hoc-workloads-server-configuration-option)
- SQL Server: [Forced Parameterization](https://learn.microsoft.com/en-us/sql/relational-databases/query-processing-architecture-guide#forced-parameterization)
- Oracle: [Library Cache](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/memory-architecture.html#GUID-A39C7AF1-A4F4-49CF-9C3E-8F8B05A5AC59)
- Oracle: [DBMS_SHARED_POOL](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_SHARED_POOL.html)
- Oracle: [V$LIBRARYCACHE](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/V-LIBRARYCACHE.html)
- PostgreSQL: [pg_prepared_statements](https://www.postgresql.org/docs/current/view-pg-prepared-statements.html)
- PostgreSQL: [plan_cache_mode](https://www.postgresql.org/docs/current/runtime-config-query.html#GUC-PLAN-CACHE-MODE)
- PgBouncer: [Prepared Statements](https://www.pgbouncer.org/usage.html#prepared-statements)
- MySQL 8.0.3 Release Notes: Query Cache removed
- MySQL: [PREPARE Statement](https://dev.mysql.com/doc/refman/8.0/en/prepare.html)
- TiDB: [Plan Cache](https://docs.pingcap.com/tidb/stable/sql-prepared-plan-cache)
- TiDB: [Instance Plan Cache (7.1+)](https://docs.pingcap.com/tidb/stable/sql-non-prepared-plan-cache)
- OceanBase: [Plan Cache](https://en.oceanbase.com/docs/common-oceanbase-database-10000000000877569)
- CockroachDB: [Query Cache](https://www.cockroachlabs.com/docs/stable/cluster-settings)
- SAP HANA: [SQL Plan Cache](https://help.sap.com/docs/SAP_HANA_PLATFORM/6b94445c94ae495c83a19646e7c3fd56/20cba2bd75191014ab3eb2a38b75dcde.html)
- DB2 LUW: [Package Cache](https://www.ibm.com/docs/en/db2/11.5?topic=parameters-pckcachesz-package-cache-size)
- 相关文章：[预编译语句与计划缓存](prepared-statement-cache.md)、[查询指纹与摘要](query-fingerprinting.md)
