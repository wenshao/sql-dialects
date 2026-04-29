# 计划重编译触发条件 (Plan Recompilation Triggers)

凌晨四点的告警邮件标题是"OLTP 平均响应时间从 3 ms 飙到 240 ms"。DBA 登录数据库一看，缓存命中率正常，但 `sys.dm_exec_query_stats` 里同一条 SQL 的 `plan_generation_num` 在 5 分钟内涨了 12000 次。原因排查到最后，是凌晨自动统计信息更新（auto_update_statistics）触发了 plan invalidation，所有热点查询同时硬解析，CPU 撞满。这就是计划重编译触发条件（plan recompilation triggers）选错或没控制好时的典型故障——本来用来"让计划与数据保持一致"的机制，反而成了系统抖动的源头。

## 为什么计划重编译触发条件值得单独讨论

计划缓存（参见 `prepared-statement-cache.md`、`plan-cache-eviction.md`）解决了"编译一次、执行万次"的问题。计划稳定性（参见 `query-plan-stability.md`）解决了"避免计划无故漂移"的问题。但还有第三个核心问题：**什么时候应该让缓存里的旧计划失效，让优化器重新生成？**

理论上看似简单——表结构变了、统计信息变了、绑定参数值分布变了，就该重编译。但每个引擎对这三类触发条件的处理细节差异极大：

- **DDL 变化**：所有引擎都会失效（不失效就是 bug），但失效的"颗粒度"和"传播延迟"不同。SQL Server 立即失效；PostgreSQL 通过 invalidation message 在事务提交时广播；CockroachDB 依赖 schema 版本号。
- **统计信息变化**：差异最大。SQL Server 默认在 `modification_count > sqrt(1000 * N)` 时触发（compat 130+），Oracle 在 `_OPTIMIZER_INVALIDATION_PERIOD` 内分散触发（默认 5 小时），PostgreSQL **完全不会**因 ANALYZE 自动让 prepared statement 失效，TiDB 提供 `tidb_plan_cache_invalidation_on_fresh_stats` 控制开关。
- **参数值分布变化（parameter sniffing）**：默认通常不重编译，需要显式 hint。SQL Server 的 `OPTION (RECOMPILE)`、Oracle 的 `BIND_AWARE`、PostgreSQL 的 `plan_cache_mode = force_custom_plan` 各有各的语法。
- **手动失效**：用 `sp_recompile`、`DBMS_SHARED_POOL.PURGE`、`DEALLOCATE`、`ALTER SYSTEM FLUSH PLAN CACHE` 等命令显式踢出某条计划。

如果你不知道这些触发条件什么时候会发生，那么"为什么这条 SQL 突然变慢/突然变快"就是一个永远查不清的玄学问题。

## 没有 SQL 标准

ISO/IEC 9075（SQL 标准）从 SQL:1992 起定义了 `PREPARE` / `EXECUTE` / `DEALLOCATE`，但完全没有规定：

- 计划编译完成后能保留多久
- 何时应当重新编译（schema 变化、统计变化、参数值变化、手动触发……）
- 是否提供 `WITH RECOMPILE` / `OPTION (RECOMPILE)` 等显式重编译语法
- 显式重编译 hint 的语法是查询级、语句级还是会话级
- 统计信息更新的"触发阈值"是百分比、绝对值还是平方根公式
- DDL 是同步失效还是惰性失效
- 是否支持单条计划的强制重编译（targeted invalidation）

因此本文涉及的所有概念都属于**实现层（implementation-defined）**，跨引擎迁移时必须重新理解。Oracle 的 cursor invalidation、SQL Server 的 plan recompilation、PostgreSQL 的 plancache.c 重编译机制、MySQL 的 prepared statement cache 是各自独立设计、互不兼容的体系。

## 支持矩阵（45+ 引擎）

### Schema 变化触发的失效

DDL 操作（`ALTER TABLE`、`CREATE INDEX`、`DROP COLUMN` 等）对相关计划的失效是所有可信引擎的最低保证。差异在于失效的颗粒度和延迟。

| 引擎 | DDL 即时失效 | 失效粒度 | 跨节点传播 | 引入版本 |
|------|-------------|---------|-----------|---------|
| SQL Server | 是 | 表/索引引用 | 单实例 | 早期 |
| Oracle | 是 | 对象级游标失效 | RAC 跨节点广播 | 早期 |
| PostgreSQL | 提交时 | invalidation message | 单实例 | 8.x+ (plancache) |
| MySQL | 是 | 会话级 PS 失效 | 单实例 | 5.0+ |
| MariaDB | 是 | 会话级 PS 失效 | 单实例 | 早期 |
| SQLite | 是 | sqlite3_prepare 重新编译 | -- | 早期 |
| DB2 LUW | 是 | 包级失效 (package invalidation) | 单实例 | 早期 |
| Snowflake | 是 | 元数据驱动 | 全局 | GA |
| BigQuery | 是 | 元数据驱动 | 全局 | GA |
| Redshift | 是 | 编译段失效 | 集群 | GA |
| ClickHouse | 不缓存 | -- | -- | -- |
| Trino | 不缓存 | -- | -- | -- |
| Presto | 不缓存 | -- | -- | -- |
| Spark SQL | 是 | DataFrame 计划 | 应用级 | -- |
| Hive | 是 | 元数据 | 元数据驱动 | -- |
| Flink SQL | 不缓存 | -- | -- | -- |
| Databricks | 是 | 同 Spark + Photon | 集群 | -- |
| Teradata | 是 | Request Cache 失效 | AMP 广播 | 早期 |
| Greenplum | 提交时 | invalidation message | 段间广播 | -- |
| CockroachDB | 是（leasing） | 描述符 lease 翻版 | 集群 | 早期 |
| TiDB | 是 | schema 版本递增 | TSO + lease | 4.0+ |
| OceanBase | 是 | schema_version 触发 | 租户级 | 早期 |
| YugabyteDB | 提交时 | catalog version | 集群 | 继承 PG |
| SingleStore | 是 | 计划失效 | 节点广播 | 7.x+ |
| Vertica | 不缓存 | -- | -- | -- |
| Impala | 是 | catalog v2 | catalog 服务广播 | -- |
| StarRocks | 是 | FE 元数据 | FE 广播 | -- |
| Doris | 是 | FE 元数据 | FE 广播 | -- |
| MonetDB | 是 | -- | -- | -- |
| CrateDB | -- | -- | -- | -- |
| TimescaleDB | 提交时 | invalidation message | 单实例 | 继承 PG |
| QuestDB | 不缓存 | -- | -- | -- |
| Exasol | 是 | 自动 | 集群 | -- |
| SAP HANA | 是 | 计划失效 | 多副本 | 早期 |
| Informix | 是 | SQ 缓存失效 | 单实例 | -- |
| Firebird | 是 | 显式 PREPARE 重新执行 | -- | -- |
| H2 | 是 | -- | 嵌入式 | 早期 |
| HSQLDB | 是 | -- | 嵌入式 | -- |
| Derby | 是 | Statement Cache 失效 | 嵌入式 | -- |
| Amazon Athena | 不缓存计划 | -- | -- | -- |
| Azure Synapse | 是 | 继承 SQL Server | 实例 | GA |
| Google Spanner | 是 | schema change job | 全局 | GA |
| Materialize | 是 | 视图重物化 | 集群 | -- |
| RisingWave | 是 | 继承 PG | 集群 | -- |
| InfluxDB (SQL) | -- | -- | -- | -- |
| DatabendDB | -- | -- | -- | -- |
| Yellowbrick | 提交时 | 继承 PG | -- | -- |
| Firebolt | -- | -- | -- | -- |

> 注：DDL 失效的"延迟"是分布式 SQL 引擎的核心难点。CockroachDB 用 schema lease（默认 5 分钟）保证最终所有节点一致；TiDB 通过 placement driver 全局递增 schema version；Spanner 走 schema change job 异步处理。

### 统计信息变化触发的失效

| 引擎 | 自动统计失效 | 默认阈值 | 可配置项 | 引入版本 |
|------|-------------|---------|---------|---------|
| SQL Server | 是 | `sqrt(1000*N)`（compat 130+） | `AUTO_UPDATE_STATISTICS` | 2016+ (compat 130) |
| Oracle | 是（异步） | `_OPTIMIZER_INVALIDATION_PERIOD` 5h | `NO_INVALIDATE` 参数 | 10g+ |
| PostgreSQL | **否**（不会自动让 prepared statement 重编译） | -- | 需 `DEALLOCATE` + `PREPARE` | -- |
| MySQL | 是（粗粒度） | `innodb_stats_auto_recalc` | `STATS_AUTO_RECALC` | 5.6+ |
| MariaDB | 是 | EITS 自动更新 | `use_stat_tables` | 10.0+ |
| SQLite | -- | 需手动 `ANALYZE` | -- | -- |
| DB2 LUW | 是（自动 RUNSTATS） | `AUTO_RUNSTATS` | DB2 配置 | 早期 |
| Snowflake | 自动 | 微分区元数据 | -- | GA |
| BigQuery | 自动 | -- | -- | GA |
| Redshift | 自动 ANALYZE | `auto_analyze` | -- | GA |
| ClickHouse | 不缓存计划 | -- | -- | -- |
| Trino | 不缓存计划 | -- | -- | -- |
| Spark SQL | -- | DataFrame 重编译 | `CBO` | -- |
| Hive | 是 | `hive.stats.autogather` | -- | -- |
| Databricks | 是 | Photon 元数据 | -- | -- |
| Teradata | 是 | 数据 demographics 阈值 | -- | -- |
| Greenplum | 是 | `gp_autostats_mode` | -- | -- |
| CockroachDB | 是 | 异步统计自动重编译 | `sql.stats.automatic_collection.enabled` | 19.x+ |
| TiDB | 可配置 | `tidb_plan_cache_invalidation_on_fresh_stats` | 6.5+ 可关 | 6.x+ |
| OceanBase | 是 | 命中权重 + 动态采样 | `ob_enable_plan_cache` | 早期 |
| YugabyteDB | 是 | 继承 PG（不自动失效）| -- | -- |
| SingleStore | 自动 | -- | -- | -- |
| Vertica | 不缓存 | -- | -- | -- |
| Impala | -- | -- | -- | -- |
| StarRocks | 是 | FE 自动收集 | -- | -- |
| Doris | 是 | FE 自动收集 | -- | -- |
| SAP HANA | 是 | -- | -- | 早期 |
| Informix | 是 | UPDATE STATISTICS 触发 | -- | -- |
| Azure Synapse | 是 | sqrt(1000*N) | -- | GA |
| Google Spanner | 自动 | -- | -- | GA |
| Materialize | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- |

> 关键差异：PostgreSQL 是少数**统计变化不会自动让 prepared statement 失效**的引擎，它的 plancache 只对 schema 变化（invalidation message）做出反应。如果你 `ANALYZE` 后想让 prepared statement 用新统计，必须 `DEALLOCATE` + `PREPARE` 重新执行。这是从 PG 到 SQL Server 迁移时最常见的认知差。

### 显式重编译 Hint：OPTION (RECOMPILE) / WITH RECOMPILE

| 引擎 | 查询级 hint | 过程级 hint | 会话级开关 | 引入版本 |
|------|------------|------------|-----------|---------|
| SQL Server | `OPTION (RECOMPILE)` | `WITH RECOMPILE` / `EXEC WITH RECOMPILE` | `SET STATISTICS_RECOMPILE` (扩展) | OPTION 2008+，WITH 早期 |
| Oracle | -- (用 `BIND_AWARE` / `NO_BIND_AWARE`) | `EXECUTE IMMEDIATE` | `CURSOR_SHARING` | 11g+ |
| PostgreSQL | -- | -- | `plan_cache_mode = {auto,force_custom_plan,force_generic_plan}` | 12+ |
| MySQL | -- | -- | -- | -- |
| MariaDB | -- | -- | -- | -- |
| DB2 LUW | `REOPT(ALWAYS/ONCE/NONE)` | `REOPT` 包绑定参数 | `REOPT` 注册表变量 | 早期 |
| TiDB | `/*+ IGNORE_PLAN_CACHE() */` | -- | `tidb_session_plan_cache_size` | 4.0+ |
| OceanBase | -- (`USE_PLAN_CACHE(NONE)`) | -- | `ob_enable_plan_cache` | 早期 |
| CockroachDB | -- | -- | `sql.query_cache.enabled` | -- |
| Snowflake | -- | -- | -- | -- |
| BigQuery | -- | -- | -- | -- |
| StarRocks | -- | -- | `enable_query_cache` | -- |
| Doris | -- | -- | `enable_sql_cache` | -- |
| SAP HANA | `WITH HINT(NO_PLAN_CACHE)` | -- | -- | 早期 |
| Informix | `SET OPTIMIZATION` | -- | -- | -- |
| Vertica | -- | -- | 不缓存 | -- |
| Spark SQL | -- | DataFrame `cache()` | -- | -- |
| Trino | 不缓存 | -- | -- | -- |
| Teradata | -- | -- | `RequestCacheSize=0` | -- |

> 关键提示：`OPTION (RECOMPILE)` 是 SQL Server 的查询级 hint，2008 引入；`WITH RECOMPILE` 在更早版本（2000+）就已存在，但是**过程级**的，作用域是整个存储过程。两者不要混用。

### NO_PLAN_CACHE / IGNORE_PLAN_CACHE 类 hint

让某条查询绕过缓存（即每次都重编译，不进缓存也不命中缓存）：

| 引擎 | 语法 | 备注 |
|------|------|------|
| SQL Server | `OPTION (RECOMPILE)` | 编译后不存入缓存 |
| Oracle | `/*+ NO_BIND_AWARE */` 或绕过 | 影响 cursor sharing |
| TiDB | `/*+ IGNORE_PLAN_CACHE() */` | 4.0+ |
| OceanBase | `/*+ USE_PLAN_CACHE(NONE) */` | -- |
| SAP HANA | `WITH HINT(NO_PLAN_CACHE)` | -- |
| Snowflake | -- | 无显式 hint |
| BigQuery | -- | 无显式 hint |

### 手动失效命令

| 引擎 | 全局清空 | 单条失效 | 按对象失效 | 备注 |
|------|---------|---------|-----------|------|
| SQL Server | `DBCC FREEPROCCACHE` | `DBCC FREEPROCCACHE(plan_handle)` | `sp_recompile <obj>` | sp_recompile 是按对象 |
| Oracle | `ALTER SYSTEM FLUSH SHARED_POOL` | `DBMS_SHARED_POOL.PURGE` | `ALTER PACKAGE COMPILE` 隐含 | 全局慎用 |
| PostgreSQL | -- | `DEALLOCATE name` | -- | `DEALLOCATE ALL` 仅会话级 |
| MySQL | -- | `DEALLOCATE PREPARE name` | -- | 仅会话级 |
| DB2 LUW | `FLUSH PACKAGE CACHE DYNAMIC` | -- | -- | -- |
| TiDB | -- | `ADMIN FLUSH PLAN_CACHE INSTANCE` | -- | 7.1+ |
| OceanBase | `ALTER SYSTEM FLUSH PLAN CACHE` | -- | -- | 租户级 |
| SAP HANA | `ALTER SYSTEM CLEAR SQL PLAN CACHE` | -- | -- | -- |
| CockroachDB | -- | -- | -- | 无 SQL 接口 |
| Snowflake | -- | -- | -- | -- |
| Spark SQL | `CLEAR CACHE` | -- | -- | 资源缓存，不严格是计划 |

### 统计阈值 / 数据分布触发

是否在数据修改量达到一定阈值时主动让计划失效（相对于"被动等下次执行才检测"）：

| 引擎 | 触发模型 | 默认阈值（modification_count） | 可调 | 备注 |
|------|---------|---------------------------|------|------|
| SQL Server (compat ≤ 120) | 老阈值 | `500 + 20% * N` | trace flag 2371 启用新公式 | 2014 及更早 |
| SQL Server (compat ≥ 130) | 新阈值 | `MIN(500+20%*N, sqrt(1000*N))` | 默认 | 2016+ |
| Oracle | 异步 | 10% 行变化（auto_invalidate） | `NO_INVALIDATE`/`DBMS_STATS` 控制 | -- |
| PostgreSQL | 不主动失效 prepared | `autovacuum_*` 控制 ANALYZE，但不让 plancache 失效 | -- | 需手动 `DEALLOCATE` |
| MySQL | InnoDB 表统计 | 1/16 行变化 | `innodb_stats_auto_recalc` | -- |
| TiDB | `tidb_auto_analyze_ratio` | 50% 默认 | `tidb_plan_cache_invalidation_on_fresh_stats` | 6.x+ |
| OceanBase | 动态采样 | -- | -- | -- |
| DB2 LUW | 自动 RUNSTATS | `auto_runstats` | -- | -- |
| Greenplum | `gp_autostats_on_change_threshold` | 20w 行 | -- | -- |
| Snowflake | 微分区 | 自动 | -- | -- |
| BigQuery | 元数据 | 自动 | -- | -- |

> 统计：约 12 个引擎实现了"基于阈值的统计变化自动触发计划失效"，其余引擎要么不缓存计划（Trino/ClickHouse/Vertica）要么不主动响应统计变化（PostgreSQL 是最典型的例子）。

## 各引擎深度解析

### SQL Server：触发条件最丰富的引擎

SQL Server 是商用数据库中重编译触发条件最丰富的引擎，每条 SQL 的 plan recompile 触发条件包括：

```text
1. Schema 变化（最简单）：
   - ALTER TABLE / ALTER INDEX / DROP COLUMN
   - 索引创建或删除
   - 触发器、约束变更

2. 统计信息变化：
   - 默认阈值（compat 130+）：
     modification_count >= MIN(500 + 20% * N, sqrt(1000 * N))
   - 老阈值（compat ≤ 120）：modification_count >= 500 + 20% * N
   - 触发条件：通过 sysschedule 在执行查询前检查

3. SET 选项变化：
   - ANSI_NULLS / ANSI_PADDING / QUOTED_IDENTIFIER 等被改变后
   - 计划与原会话设置不匹配，强制重编译

4. 临时表变化：
   - 存储过程内部 #temp 表的列变化或行数变化（>=6 行触发）

5. 显式 hint：
   - OPTION (RECOMPILE)：单条查询级，2008 引入
   - WITH RECOMPILE：存储过程级，早期就有

6. 手动命令：
   - sp_recompile @objname：让对象关联的所有计划失效
   - DBCC FREEPROCCACHE：清空整个 plan cache
   - DBCC FREESYSTEMCACHE：清空特定 cache store
```

#### OPTION (RECOMPILE)：查询级单次重编译

```sql
-- 2008 引入，最常用的 hint
SELECT * FROM sales
WHERE region = @region
  AND amount > @min_amount
OPTION (RECOMPILE);

-- 关键语义：
-- 1. 此次执行强制重编译
-- 2. 编译后不存入 plan cache（执行完即丢）
-- 3. 优化器看到的是绑定变量的"实际值"（parameter-embedded optimization）
-- 4. 适合 parameter sniffing 严重、但参数值差异大的查询
```

#### WITH RECOMPILE：过程级永久标记

```sql
-- 创建时声明
CREATE PROCEDURE GetSalesByRegion @region NVARCHAR(50)
WITH RECOMPILE
AS
    SELECT * FROM sales WHERE region = @region;
GO

-- 执行时声明（每次执行强制）
EXEC GetSalesByRegion @region = 'APAC' WITH RECOMPILE;

-- 注意：
-- 1. 过程级 WITH RECOMPILE 比查询级粗
-- 2. 过程内所有 SQL 都重编译
-- 3. 现代实践推荐 OPTION (RECOMPILE) 精确到语句
```

#### sp_recompile：按对象失效

```sql
-- 让所有引用 dbo.Customers 的计划失效
EXEC sp_recompile 'dbo.Customers';

-- 让特定存储过程下次执行时重编译
EXEC sp_recompile 'dbo.GetCustomerOrders';

-- 实现：UPDATE schema_ver，依赖该对象的计划在下次执行时检测到 schema 版本不一致后重编译
```

### SQL Server 统计阈值深度解析（compat 130 改变）

SQL Server 2016 引入 compatibility level 130，把统计阈值从老公式改成了平方根公式。这是 SQL Server 历史上最重要的优化器行为改变之一。

#### 老阈值（compat 100-120）

```text
触发条件：modification_count >= 500 + 20% * N

例子：
N = 10,000     → 阈值 = 500 + 2,000   = 2,500
N = 100,000    → 阈值 = 500 + 20,000  = 20,500
N = 1,000,000  → 阈值 = 500 + 200,000 = 200,500
N = 10,000,000 → 阈值 = 500 + 2,000,000 = 2,000,500（约 20%）

问题：大表更新阈值过高，统计长期不更新
解决方案：trace flag 2371（启用新公式，2008R2 SP1 引入）
```

#### 新阈值（compat 130+）

```text
触发条件：modification_count >= MIN(500 + 20% * N, sqrt(1000 * N))

例子：
N = 10,000     → MIN(2,500, 3,162)     = 2,500（与老阈值相同）
N = 100,000    → MIN(20,500, 10,000)   = 10,000（约 10%）
N = 1,000,000  → MIN(200,500, 31,623)  = 31,623（约 3.2%）
N = 10,000,000 → MIN(2,000,500, 100,000) = 100,000（仅 1%）
N = 100,000,000 → MIN(20,000,500, 316,228) = 316,228（仅 0.3%）

数学性质：
- N 越大，阈值占总行数比例越小
- 平方根曲线让大表能更频繁更新统计
- 等价于 trace flag 2371 默认启用
```

#### 启用新公式的方法

```sql
-- 方法 1：升级数据库到 compat 130+
ALTER DATABASE MyDb SET COMPATIBILITY_LEVEL = 130;

-- 方法 2：保持老 compat，但启用 trace flag 2371（仅适合 2014）
DBCC TRACEON (2371, -1);

-- 方法 3：手动控制（高频更新场景）
UPDATE STATISTICS dbo.LargeTable WITH FULLSCAN;
-- 或
EXEC sp_updatestats;
```

### Oracle：CURSOR_SHARING 与 SIMILAR 的兴衰

Oracle 的计划重编译机制围绕 cursor 概念。每条 SQL 在 library cache 里有 parent cursor（对应 SQL 文本）和 child cursor（对应具体的执行计划）。

```text
触发条件：
1. DDL：让所有引用对象的 child cursor 失效
2. DBMS_STATS.GATHER_*: 默认 NO_INVALIDATE = AUTO_INVALIDATE
   - 在 _OPTIMIZER_INVALIDATION_PERIOD（默认 5 小时）内随机分散重编译
3. ADAPTIVE CURSOR SHARING (11g+)：
   - bind peeking 后发现执行差异大，标记为 BIND_AWARE
   - 后续不同 bind 值会编译多个 child cursor
4. 显式：DBMS_SHARED_POOL.PURGE / ALTER SYSTEM FLUSH SHARED_POOL
```

#### CURSOR_SHARING 三档：EXACT / SIMILAR / FORCE

```sql
-- EXACT (默认)：SQL 文本必须完全相同才共享 cursor
ALTER SYSTEM SET CURSOR_SHARING = EXACT;

-- FORCE：把字面值替换为绑定变量，强制共享
ALTER SYSTEM SET CURSOR_SHARING = FORCE;
-- 例如：SELECT * FROM t WHERE id = 100 → SELECT * FROM t WHERE id = :"SYS_B_0"

-- SIMILAR：（仅对 selectivity 影响小的字面值替换）
-- 11g 起 deprecated，12c 起官方建议不要再用
-- 推荐：使用 FORCE + Adaptive Cursor Sharing
```

#### Adaptive Cursor Sharing（11g+）

```text
机制：
1. 第一次执行：使用 bind 值编译初始计划（bind peeking）
2. 多次执行后：如果发现不同 bind 值的执行特性差异大，
   将 cursor 标记为 BIND_AWARE
3. BIND_AWARE 后：根据 bind 值"分桶"，每桶编译独立 child cursor
4. 结果：同一 SQL 文本可能有 5-10 个 child cursor 并存

副作用：
- library cache 占用增加
- 编译次数增加（每个 child cursor 都需要硬解析）
- 适合处理 skewed bind 分布
```

#### 失效"无效化时间窗"

```sql
-- 让 DBMS_STATS 收集后立即失效（不分散）
EXEC DBMS_STATS.GATHER_TABLE_STATS(
  ownname => 'SCOTT',
  tabname => 'EMP',
  no_invalidate => FALSE  -- 立即失效
);

-- 让收集后不立即失效（默认 AUTO_INVALIDATE：5 小时内分散失效）
EXEC DBMS_STATS.GATHER_TABLE_STATS(
  ownname => 'SCOTT',
  tabname => 'EMP'
  -- 默认 no_invalidate => DBMS_STATS.AUTO_INVALIDATE
);

-- 全局参数（隐藏）
ALTER SYSTEM SET "_optimizer_invalidation_period" = 18000; -- 5 小时
```

> 重要历史：CURSOR_SHARING = SIMILAR 在 11g 被 deprecated（11.1.0.7 文档明确标注），原因是它产生了大量的 child cursor 但又无法像 ACS 那样智能分桶，导致 library cache 严重碎片化。Oracle 12c 起官方建议直接用 EXACT 或 FORCE，不要使用 SIMILAR。

### PostgreSQL：plancache.c 的特殊语义

PostgreSQL 的计划重编译机制集中在源码 `src/backend/utils/cache/plancache.c`，它的设计哲学是：**只对 schema 变化敏感，不对统计变化敏感**。

```text
触发条件：
1. DDL：通过 invalidation message 在事务提交时广播，
   依赖该对象的 plancache 全部失效
2. ANALYZE：不直接让 plancache 失效（这是与 SQL Server 最大的差异！）
3. PREPARE / EXECUTE 协议：保留 plancache 直到 DEALLOCATE 或会话结束
4. 显式：DEALLOCATE name 或 DEALLOCATE ALL
```

#### Generic vs Custom Plan：5 次执行规则

PostgreSQL 12 之前没有显式开关，逻辑硬编码在 plancache.c 中：

```c
// src/backend/utils/cache/plancache.c (简化伪代码)
if (cplan->generic_cost <= cplan->total_custom_cost / num_custom_plans + 10
    || num_custom_plans >= 5) {
    use_generic_plan();
} else {
    use_custom_plan();  // 这次重新编译
}
```

具体行为：

```text
执行次数 1-5：每次都用绑定值"窥视"（bind peek），生成 custom plan
执行 5 次后：开始评估
  if generic plan 代价 <= 平均 custom 代价 + 10：
    锁定 generic plan（之后不再用 bind 值优化）
  else:
    继续用 custom plan（每次都重编译）
```

这个 5 次的硬编码常常造成生产中的"奇怪现象"：

```text
现象：
- 第 1-5 次执行：500 ms（custom plan，bind 值优化）
- 第 6 次执行：50 ms（切到 generic plan，对当前 bind 值刚好高效）
- 第 7 次执行：5000 ms（generic plan 对新 bind 值不友好，不重编译）

排查路径：
1. EXPLAIN (ANALYZE, GENERIC_PLAN) 查看 generic plan
2. 比较 generic 和 custom 的代价差异
3. 设置 plan_cache_mode = force_custom_plan 强制每次重编译
```

#### plan_cache_mode (PG 12+)

```sql
-- 让所有 prepared statement 总是用 custom plan（每次重编译）
SET plan_cache_mode = force_custom_plan;

-- 让所有 prepared statement 总是用 generic plan（一次编译）
SET plan_cache_mode = force_generic_plan;

-- 默认：5 次后决定
SET plan_cache_mode = auto;

-- 应用建议：
-- - bind 值分布稳定 + 低开销 → force_generic_plan
-- - bind 值差异大 + 高代价查询 → force_custom_plan
-- - 不确定 → auto，但监控查询时长抖动
```

#### 让统计变化生效

```sql
-- 错误做法（不会让 plancache 用新统计）
PREPARE q1(int) AS SELECT * FROM orders WHERE customer_id = $1;
EXECUTE q1(100);  -- 用旧统计编译
ANALYZE orders;
EXECUTE q1(100);  -- 仍用旧 plancache，统计被无视

-- 正确做法
DEALLOCATE q1;
PREPARE q1(int) AS SELECT * FROM orders WHERE customer_id = $1;
EXECUTE q1(100);  -- 重新编译，用新统计

-- 或者：force_custom_plan 让每次都重新评估
SET plan_cache_mode = force_custom_plan;
EXECUTE q1(100);  -- 每次都重新优化
```

### MySQL：粗粒度的 prepared statement cache

MySQL 的计划缓存机制相对原始（Query Cache 已在 8.0.3 移除）：

```text
触发条件：
1. ALTER TABLE：让所有引用该表的 prepared statement 失效
2. innodb_stats_auto_recalc：1/16 行变化触发统计自动收集
3. 显式：DEALLOCATE PREPARE name
4. 会话级：会话断开 → 全部失效
```

#### ALTER TABLE 自动失效

```sql
-- 会话 A
PREPARE q1 FROM 'SELECT * FROM orders WHERE id = ?';
EXECUTE q1 USING @id;  -- 走缓存，毫秒级

-- 会话 B
ALTER TABLE orders ADD COLUMN status_v2 VARCHAR(50);

-- 会话 A 再执行
EXECUTE q1 USING @id;
-- 错误：Prepared statement needs to be re-prepared

-- 注意：MySQL 不会"自动重新编译"，而是直接报错
-- 应用代码必须捕获错误后 DEALLOCATE + PREPARE
-- JDBC: SQLState 'HY000', errorCode 1615
```

#### 统计变化与 prepared statement

```sql
-- MySQL 8.x 默认行为：
-- 1. innodb_stats_auto_recalc=ON：1/16 行变化时自动重收集
-- 2. 重收集后：不强制让 prepared statement 重编译
-- 3. 但优化器在 EXECUTE 时会重新评估代价（每次执行都走优化器）
-- 这点与 PostgreSQL 5 次规则不同：MySQL 是"prepare 时编译参数"，但执行时仍参考最新统计

-- 强制立即重收集
ANALYZE TABLE orders;
```

### DB2 LUW：REOPT 三档

DB2 LUW 提供了非常细致的 REOPT 选项：

```sql
-- 在动态 SQL 中通过 register 控制
SET CURRENT QUERY OPTIMIZATION = 5;

-- 单条 SQL 的 REOPT hint
SELECT * FROM sales WHERE region = ? FOR FETCH ONLY
WITH UR REOPT ALWAYS;

-- REOPT 三档：
-- NONE   ：第一次绑定时编译，后续重用（默认）
-- ONCE   ：第一次执行时用真实绑定值优化，之后固化
-- ALWAYS ：每次执行都用绑定值重新优化（类似 OPTION (RECOMPILE)）
```

#### 包级 BIND 选项

```sql
-- 在 BIND 包时指定（数据库管理员行为）
BIND program.bnd REOPT ALL;

-- 显式失效包
FLUSH PACKAGE CACHE DYNAMIC;

-- 失效特定 schema 的包
CALL SYSPROC.ADMIN_CMD('FLUSH PACKAGE CACHE DYNAMIC');
```

### CockroachDB：基于 schema lease 的失效

CockroachDB 是分布式 SQL 引擎，DDL 失效需要在所有节点间协调：

```text
触发条件：
1. Schema 变化：通过 schema descriptor lease（默认 5 分钟）渐进式失效
2. 统计变化：异步重编译（基于 sql.stats.automatic_collection.enabled）
3. 配置：sql.query_cache.enabled = true（默认开），cache 大小 100 entries
4. 无显式 OPTION (RECOMPILE) 类的 hint
```

#### Schema Lease 的工作机制

```text
1. CockroachDB 节点缓存 schema descriptor（带 lease）
2. lease 默认 5 分钟过期，过期后必须从 KV 层重新读取
3. ALTER TABLE 时：旧 lease 上限设置为某时间戳，新 lease 用新 schema
4. 节点必须等所有旧 lease 过期才能完成 schema change
5. 结果：DDL 之后最多 5 分钟内所有节点完成失效
```

```sql
-- 调整 lease 长度（影响 DDL 传播速度）
SET CLUSTER SETTING sql.catalog.descriptor_lease_duration = '5m';

-- 监控当前所有 lease
SELECT * FROM crdb_internal.kv_descriptor_leases;
```

### TiDB：tidb_plan_cache_invalidation_on_fresh_stats

TiDB 6.x 起引入了一个非常有用的开关：让用户决定统计变化是否让 plan cache 失效。

```sql
-- 默认值（6.5+）：当统计被刷新时，相关 plan cache 自动失效
SET GLOBAL tidb_plan_cache_invalidation_on_fresh_stats = ON;

-- 关闭：统计刷新不影响 plan cache（节省编译开销，但可能用旧计划）
SET GLOBAL tidb_plan_cache_invalidation_on_fresh_stats = OFF;

-- 应用场景：
-- ON  ：业务对计划质量敏感，宁可重编译也要用最新统计（OLAP 场景）
-- OFF ：业务对延迟敏感，可接受短暂 stale 计划（OLTP 场景）
```

#### IGNORE_PLAN_CACHE() Hint

```sql
-- 单条 SQL 不进 plan cache
SELECT /*+ IGNORE_PLAN_CACHE() */ * FROM orders WHERE customer_id = ?;

-- 实例级清空（7.1+）
ADMIN FLUSH PLAN_CACHE INSTANCE;

-- 会话级配置
SET tidb_session_plan_cache_size = 100;       -- 默认值
SET tidb_enable_non_prepared_plan_cache = 1;  -- 7.0+ 非 prepared 语句也走 cache
```

### OceanBase：plan_cache_mem_limit_pct

OceanBase 的 plan cache 是租户级的（multi-tenant），淘汰和失效都基于租户内存压力：

```sql
-- 租户级 plan cache 内存上限
ALTER SYSTEM SET plan_cache_mem_limit_pct = 5;  -- 默认 5% 租户内存

-- 显式刷新某租户的 plan cache
ALTER SYSTEM FLUSH PLAN CACHE TENANT = 'tenant1';

-- 查看 plan cache 状态
SELECT * FROM GV$OB_PLAN_CACHE_STAT;

-- USE_PLAN_CACHE Hint
SELECT /*+ USE_PLAN_CACHE(NONE) */ * FROM orders;  -- 这条不进 cache
SELECT /*+ USE_PLAN_CACHE(DEFAULT) */ * FROM orders; -- 默认行为
```

### SAP HANA：M_SQL_PLAN_CACHE

```sql
-- 让 SQL 不进 plan cache
SELECT * FROM sales WITH HINT (NO_PLAN_CACHE)
WHERE region = 'APAC';

-- 清空 plan cache
ALTER SYSTEM CLEAR SQL PLAN CACHE;

-- 查看 plan cache 内容
SELECT statement_string, plan_id, last_execution_timestamp
FROM M_SQL_PLAN_CACHE
ORDER BY last_execution_timestamp DESC;

-- 删除单条
ALTER SYSTEM RECOMPILE PLAN <plan_id>;
```

### Snowflake / BigQuery：自动元数据驱动

云数仓基本不暴露 plan cache 控制：

```sql
-- Snowflake
-- 1. 不缓存执行计划（每次重新编译，依赖元数据缓存）
-- 2. 仅缓存查询结果（24 小时 TTL）
-- 3. 没有 OPTION (RECOMPILE) 类 hint

-- BigQuery
-- 1. 元数据驱动：表元数据变化自动让相关编译失效
-- 2. 无显式失效命令
-- 3. 仅可通过 jobConfig.useQueryCache 控制结果缓存
```

## 统计阈值场景模拟

下表展示在不同表大小下，三个引擎的统计阈值对比（修改 1 万行后是否触发统计更新与 plan invalidation）：

| 表大小 N | SQL Server compat 120 阈值 | SQL Server compat 130 阈值 | Oracle (10%) 阈值 | TiDB (50%) 阈值 |
|---------|--------------------------|--------------------------|-----------------|----------------|
| 10,000 | 2,500 | 2,500 | 1,000 | 5,000 |
| 100,000 | 20,500 | 10,000 | 10,000 | 50,000 |
| 1,000,000 | 200,500 | 31,623 | 100,000 | 500,000 |
| 10,000,000 | 2,000,500 | 100,000 | 1,000,000 | 5,000,000 |
| 100,000,000 | 20,000,500 | 316,228 | 10,000,000 | 50,000,000 |
| 1,000,000,000 | 200,000,500 | 1,000,000 | 100,000,000 | 500,000,000 |

> 关键观察：SQL Server compat 130 在大表上阈值最低（最敏感），Oracle 10% 在中等表友好，TiDB 50% 比较保守（避免频繁重编译）。

## 手动重编译模式与运维实践

### 标准排查流程

```text
现象：业务反映"某条 SQL 突然变慢"
↓
1. 确认是否是 plan recompile 引起：
   - SQL Server: SELECT plan_generation_num FROM sys.dm_exec_query_stats
   - Oracle: SELECT executions, parse_calls FROM v$sql
   - PostgreSQL: pg_stat_statements 的 calls 与时间分布
   - TiDB: STATEMENTS_SUMMARY.PLAN_DIGEST_CHANGED
↓
2. 如果计划没变：可能是 stats 变化但未 invalidate（PG / TiDB OFF）
   → DEALLOCATE + PREPARE 或重启会话
↓
3. 如果计划变了：可能是统计触发的"反向退化"
   → 找到旧计划用 plan baseline 锁定（参见 query-plan-stability.md）
↓
4. 如果是高频抖动：可能是 5 次规则 / Adaptive Cursor Sharing 引起
   → SET plan_cache_mode = force_custom_plan / force_generic_plan
```

### 重编译 hint 的"用不用"决策

```text
当问题是 parameter sniffing：
  - 单参数倾斜大 → OPTION (RECOMPILE) / REOPT ALWAYS
  - 多参数都倾斜 → 改写为多个存储过程，分别 hint

当问题是 stats stale：
  - SQL Server → UPDATE STATISTICS WITH FULLSCAN + DBCC FREEPROCCACHE
  - PostgreSQL → ANALYZE + DEALLOCATE
  - Oracle → DBMS_STATS.GATHER_*  (NO_INVALIDATE => FALSE)

当问题是 schema 变化未传播：
  - CockroachDB → 等待 schema lease 过期（最长 5 分钟）
  - 分布式引擎 → 检查 schema version 是否同步

当问题是 plan cache 满：
  - 参见 plan-cache-eviction.md
```

### 部署上线策略

```text
推荐做法：
1. 大量数据导入后：先 ANALYZE，再让 plan cache 失效
   - SQL Server: UPDATE STATISTICS + sp_recompile
   - PG: ANALYZE + 重启或 DEALLOCATE
2. 索引创建/重建后：让相关计划失效
   - SQL Server: sp_recompile <表名>
   - Oracle: 自动失效
3. 升级 compatibility level：先在测试环境验证统计阈值变化的影响
4. 监控指标：plan_generation_num（SQL Server）、parse_calls（Oracle）、
   plan_cache_hit_rate（OceanBase）

避免做法：
1. 生产高峰期 DBCC FREEPROCCACHE / ALTER SYSTEM FLUSH SHARED_POOL
   → 触发"惊群"（thundering herd）：所有 SQL 同时硬解析
2. 在 trigger / stored proc 内频繁调用 OPTION (RECOMPILE)
   → 可能引起 schedule 抖动
3. 把所有 prepared statement 都加 IGNORE_PLAN_CACHE
   → 等同于关闭 plan cache，吞吐量塌方
```

### 平滑失效模式（避免雪崩）

```text
SQL Server：
  - sp_recompile 仅标记，下次执行才编译
  - 而非 DBCC FREEPROCCACHE（一次清空）
  - 推荐分批：sp_recompile <table1>; WAITFOR DELAY '00:01:00'; sp_recompile <table2>;

Oracle：
  - DBMS_SHARED_POOL.PURGE 单条目移除
  - 而非 ALTER SYSTEM FLUSH SHARED_POOL（一次清空）
  - DBMS_STATS 使用 AUTO_INVALIDATE 让失效在 5 小时内分散

TiDB：
  - 仅 7.1+ 支持 ADMIN FLUSH PLAN_CACHE INSTANCE
  - 也是分批失效更安全

OceanBase：
  - ALTER SYSTEM FLUSH PLAN CACHE TENANT = 'xxx' 仅失效一个租户
```

## 多个并发触发条件的优先级

当多个触发条件同时满足时（DDL + stats + hint），各引擎的处理顺序：

| 引擎 | 优先级（高 → 低） |
|------|------------------|
| SQL Server | 显式 hint (OPTION RECOMPILE) > schema change > set option change > stats threshold |
| Oracle | 显式 PURGE > schema invalidation > stats invalidation > Adaptive Cursor |
| PostgreSQL | DEALLOCATE > schema invalidation message > plan_cache_mode > 5 次规则 |
| MySQL | DEALLOCATE > schema change (报错) > stats（不直接触发） |
| TiDB | IGNORE_PLAN_CACHE > schema version > plan_cache_invalidation_on_fresh_stats |

## 设计争议与权衡

### "失效得太勤快"还是"失效得太懒"？

```text
失效太勤快：
- 优势：计划永远反映最新数据分布
- 劣势：编译开销大，CPU 消耗高，OLTP 吞吐量下降
- 典型：SQL Server compat 130（sqrt 阈值）

失效太懒：
- 优势：编译开销低，吞吐量稳定
- 劣势：计划可能严重 stale，数据分布大变后性能塌方
- 典型：PostgreSQL（不让 stats 变化触发 invalidation）

折中：
- 对热点 OLTP 关闭 stats invalidation（如 TiDB OFF）
- 对 OLAP 大查询打开 force_custom_plan
- 用 plan baseline 锁定关键 SQL（参见 query-plan-stability.md）
```

### Schema 失效粒度：表级还是对象级？

```text
表级失效（粗）：
- ALTER TABLE → 失效所有引用该表的计划
- 实现简单，避免遗漏
- SQL Server / MySQL / PG 大致如此

对象级失效（细）：
- 只失效与改动列直接相关的计划
- 实现复杂，可能遗漏触发器、视图
- DB2 包级失效接近此模式

实践：
- 大多数引擎选择表级粗粒度失效
- 接受短暂的"过失效"以换取实现简单
```

### 统计阈值的"百分比派"vs"平方根派"

```text
百分比派：阈值 = X% × N
- 直观，易于理解
- 大表上阈值过高（10 亿行表 1 亿行变更才更新）
- 代表：Oracle 10%, TiDB 50%, SQL Server 老版本 20%

平方根派：阈值 = sqrt(K × N)
- 大表上阈值占比更小（更敏感）
- 数学性质：随 N 平方根级增长
- 代表：SQL Server compat 130 (sqrt(1000*N))

实践共识：大数据时代倾向平方根派，
但需要配合"分散失效"避免惊群（如 Oracle AUTO_INVALIDATE 5 小时）
```

### 显式 hint 的位置：查询级 vs 过程级 vs 会话级

```text
查询级（OPTION RECOMPILE）：
- 精度最高
- 改动量最小
- SQL Server 2008+ 推荐做法

过程级（WITH RECOMPILE）：
- 粒度粗（整个 sproc 全部重编译）
- SQL Server 早期唯一选项

会话级（plan_cache_mode / SET CURSOR_SHARING）：
- 粒度最粗
- 适合调试、批处理任务
- 风险：影响该会话所有 SQL
```

## 关键发现 (Key Findings)

1. **没有 SQL 标准**：所有重编译触发条件都是实现层概念，跨引擎迁移必须重新理解。

2. **三大触发类别**：DDL 变化（最一致，所有引擎都失效）、统计变化（差异最大，PG 不主动响应）、显式 hint（语法各异）。

3. **SQL Server compat 130 改变了游戏规则**：2016 引入的 `MIN(500+20%*N, sqrt(1000*N))` 公式让大表统计更新更敏感，等价于 trace flag 2371 默认启用。从 compat 120 升级到 130 后大表 OLTP 计划重编译频率会显著上升，需要配合 `OPTION (KEEPFIXED PLAN)` 等 hint 防止抖动。

4. **OPTION (RECOMPILE) 自 2008 引入**：是 SQL Server 查询级最精细的重编译 hint，编译后不入缓存。`WITH RECOMPILE` 是过程级，作用域更粗，2008 之前唯一选项。

5. **Oracle CURSOR_SHARING SIMILAR 已过时**：11g 起 deprecated，12c 起官方明确建议不要用。原因是 SIMILAR 产生大量 child cursor 但又无法智能分桶，library cache 严重碎片化。推荐 EXACT 或 FORCE + Adaptive Cursor Sharing。

6. **PostgreSQL 是异类**：plancache 不会因 ANALYZE 自动失效，必须 `DEALLOCATE` + `PREPARE` 或 `SET plan_cache_mode = force_custom_plan`。这是从 SQL Server / Oracle 迁移时最容易踩的坑。

7. **PostgreSQL 5 次执行规则**：custom plan 执行 5 次后评估是否切到 generic plan。`plan_cache_mode`（PG 12+）提供了 force_custom_plan / force_generic_plan / auto 三档显式控制。

8. **MySQL 简单粗暴**：`ALTER TABLE` 让所有引用 PS 失效后报错（错误码 1615 'Prepared statement needs to be re-prepared'），应用必须 retry。统计变化不主动失效 PS，依赖 EXECUTE 时优化器评估。

9. **TiDB 提供了独有开关**：`tidb_plan_cache_invalidation_on_fresh_stats`（6.x+）让用户在"宁可重编译"和"宁可短暂 stale"之间显式选择。

10. **CockroachDB 基于 schema lease**：DDL 通过 5 分钟 lease 渐进式失效，分布式 SQL 引擎特有。

11. **OceanBase 租户级**：`plan_cache_mem_limit_pct` 默认 5% 租户内存，`ALTER SYSTEM FLUSH PLAN CACHE` 可按租户失效。

12. **DB2 REOPT 三档**：NONE / ONCE / ALWAYS，是商用引擎中除 SQL Server 外最细粒度的查询级控制。

13. **手动失效要分批**：生产高峰期 `DBCC FREEPROCCACHE` / `ALTER SYSTEM FLUSH SHARED_POOL` 会触发惊群。推荐 `sp_recompile <obj>` / `DBMS_SHARED_POOL.PURGE` 这种"按对象失效"的细粒度命令。

14. **多触发条件优先级**：基本上"显式 hint > schema 变化 > 统计变化"是普遍共识，但 PG 是个例外（schema 变化是唯一会主动让 plancache 失效的途径）。

15. **云数仓不暴露**：Snowflake / BigQuery / Athena 都不暴露 plan recompile 触发条件控制，全自动元数据驱动。

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992, Section 17 (PREPARE / EXECUTE / DEALLOCATE)
- SQL Server: [Plan Caching and Recompilation](https://learn.microsoft.com/en-us/sql/relational-databases/query-processing-architecture-guide)
- SQL Server: [OPTION (RECOMPILE)](https://learn.microsoft.com/en-us/sql/t-sql/queries/option-clause-transact-sql)
- SQL Server: [sp_recompile](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-recompile-transact-sql)
- SQL Server: [Statistics auto-update threshold](https://learn.microsoft.com/en-us/sql/relational-databases/statistics/statistics)
- Oracle: [Adaptive Cursor Sharing](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/cursor-sharing.html)
- Oracle: [DBMS_SHARED_POOL.PURGE](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_SHARED_POOL.html)
- Oracle: [DBMS_STATS.GATHER_TABLE_STATS NO_INVALIDATE parameter](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_STATS.html)
- PostgreSQL: [PREPARE / EXECUTE / DEALLOCATE](https://www.postgresql.org/docs/current/sql-prepare.html)
- PostgreSQL: [plan_cache_mode](https://www.postgresql.org/docs/current/runtime-config-query.html#GUC-PLAN-CACHE-MODE)
- PostgreSQL: [plancache.c source code](https://github.com/postgres/postgres/blob/master/src/backend/utils/cache/plancache.c)
- MySQL: [Prepared Statements](https://dev.mysql.com/doc/refman/8.0/en/sql-prepared-statements.html)
- DB2 LUW: [REOPT bind option](https://www.ibm.com/docs/en/db2/11.5)
- TiDB: [Plan Cache](https://docs.pingcap.com/tidb/stable/sql-prepared-plan-cache)
- TiDB: [tidb_plan_cache_invalidation_on_fresh_stats](https://docs.pingcap.com/tidb/stable/system-variables)
- OceanBase: [Plan Cache](https://en.oceanbase.com/docs/community-observer-en-10000000000901385)
- CockroachDB: [Schema Lease](https://www.cockroachlabs.com/docs/stable/online-schema-changes.html)
- SAP HANA: [SQL Plan Cache](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- 相关文章：`prepared-statement-cache.md` / `plan-cache-eviction.md` / `query-plan-stability.md`
