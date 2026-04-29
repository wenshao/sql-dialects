# 计划参数化 (Plan Parameterization)

线上系统每秒钟数万条 ad-hoc SQL 涌入，每条仅 WHERE 中的字面量不同——如果数据库每次都全量重新解析、重新优化，CPU 和共享内存会被巨量"几乎相同"的执行计划淹没。计划参数化（Plan Parameterization）正是数据库自动把字面量替换为绑定变量、让形态相同的 SQL 共享同一份计划的核心机制。但参数化并非免费午餐：把 `WHERE status = 'active'`（占总行数 5%）和 `WHERE status = 'archived'`（占 95%）共享同一份计划，可能让一类查询走错索引——这就是 **bind peeking** 与 **parameter sniffing** 问题，是 OLTP 引擎工程师必须直面的取舍。

## 概念与术语

为便于讨论，先界定本文涉及的几个核心概念：

- **Ad-hoc SQL**：客户端直接发送的、字面量未参数化的 SQL 文本。例如 `SELECT * FROM orders WHERE id = 12345`。
- **参数化 SQL**：字面量被占位符替代的形式。例如 `SELECT * FROM orders WHERE id = ?` 或 `SELECT * FROM orders WHERE id = $1`。
- **自动参数化（Auto-parameterization）**：引擎在解析 ad-hoc SQL 时自动将"安全"的字面量替换为参数，再去缓存里查找已有计划。SQL Server 称为 simple parameterization，Oracle 称为 CURSOR_SHARING。
- **强制参数化（Forced parameterization）**：把所有字面量（包括会影响计划选择的"危险"字面量）一律替换为参数，最大化计划复用，但牺牲个别查询的最优性。
- **Bind Peeking / Parameter Sniffing**：当一个参数化 SQL 第一次执行时，优化器"窥探"绑定变量的实际值并据此选择计划；后续执行复用此计划，即使新的绑定值会让该计划很糟糕。Oracle 叫 bind peeking，SQL Server 叫 parameter sniffing，本质相同。
- **Plan Cache Hit**：参数化的最终目的——同一个查询模板（SQL text 哈希 + 参数类型）命中缓存里的已编译计划，跳过解析和优化。

理解这五个术语的相互关系是阅读本文的关键。

## 没有 SQL 标准

SQL 标准只规定了显式的 `PREPARE ... EXECUTE` 接口（参见 `prepared-statement-cache.md`），把字面量"自动"识别成参数这件事完全是各厂商自行扩展的领域。ISO/IEC 9075 没有任何关于：

- 如何决定一个字面量是否安全可以参数化（数字 `123` 安全？字符串 `'A'` 安全？日期 `'2025-01-01'` 安全？）
- 字面量类型推断的优先级（`12345` 是 INT 还是 BIGINT？`'12.5'` 是 DECIMAL 还是 VARCHAR？）
- 何时让 ad-hoc SQL 共享计划、何时强制硬解析
- bind peeking 该用第一次的值，还是历史值的统计聚合，还是用代表性值

各引擎在这一空白领域演化出了完全不同的策略，也是本文的核心比较点。

## 支持矩阵（综合）

### 自动参数化（Auto-parameterization / Simple Parameterization）

| 引擎 | 支持 | 默认开启 | 触发条件 | 备注 |
|------|------|---------|---------|------|
| SQL Server | 是 | 是 | "safe plan" 判定 | 2005+ simple parameterization |
| Oracle | 是 | 否 (默认 EXACT) | `CURSOR_SHARING` 参数 | 8i+ |
| PostgreSQL | -- | -- | -- | 仅显式 PREPARE 时参数化 |
| MySQL | -- | -- | -- | 不支持 |
| MariaDB | -- | -- | -- | 不支持 |
| SQLite | -- | -- | -- | 不支持 |
| DB2 | 是 (REOPT 部分等价) | 否 | `STMT_CONC` 注册表变量 | 9.7+ statement concentrator |
| Snowflake | 内部 | 是 (引擎实现) | -- | 用户不可控，结果缓存为主 |
| BigQuery | -- | -- | -- | 仅显式查询参数 |
| Redshift | 是 (有限) | 是 | 编译缓存匹配 | 字面量参数化模板匹配 |
| DuckDB | -- | -- | -- | 不支持 |
| ClickHouse | -- | -- | -- | 不支持 |
| Trino | -- | -- | -- | 不支持 |
| Presto | -- | -- | -- | 不支持 |
| Spark SQL | -- | -- | -- | DataFrame API 内部缓存 |
| Hive | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | 不支持 |
| Databricks | -- | -- | -- | 通过 Photon 缓存 |
| Teradata | 是 (Request Cache) | 是 | 字面量泛化 | -- |
| Greenplum | -- | -- | -- | 继承 PG，不支持 |
| CockroachDB | 是 | 是 | 自动 | 22.1+ auto-parameterize for plan cache |
| TiDB | 是 | 是 (4.0+) | `tidb_enable_prepared_plan_cache` 关联 | 6.0+ general plan cache |
| OceanBase | 是 (Fast Parser) | 是 | 文本归一化 | 1.x+ |
| YugabyteDB | -- | -- | -- | 继承 PG |
| SingleStore | 是 (`PLAN_CACHE`) | 是 | 文本规范化 | 早期 |
| Vertica | -- | -- | -- | 不支持 |
| Impala | -- | -- | -- | 不支持 |
| StarRocks | 是 (3.0+) | 否 | `enable_query_cache` | -- |
| Doris | -- | -- | -- | 不支持 |
| MonetDB | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | 不支持 |
| TimescaleDB | -- | -- | -- | 继承 PG |
| QuestDB | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | 不支持 |
| SAP HANA | 是 | 是 | `parameter_homogenization` | 1.0 SP09+ |
| Informix | -- | -- | -- | 不支持 |
| Firebird | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | 仅显式 PREPARE |
| HSQLDB | -- | -- | -- | 仅显式 PREPARE |
| Derby | -- | -- | -- | 仅显式 PREPARE |
| Amazon Athena | -- | -- | -- | 不支持 |
| Azure Synapse | 是 (Dedicated) | 是 | 继承 SQL Server | -- |
| Google Spanner | 是 | 是 | 自动参数化 | 内置 |
| Materialize | -- | -- | -- | 继承 PG |
| RisingWave | -- | -- | -- | 继承 PG |
| InfluxDB (SQL) | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | 不支持 |
| Yellowbrick | -- | -- | -- | 继承 PG |
| Firebolt | -- | -- | -- | 不支持 |
| PolarDB | 是 | 否 | 兼容 MySQL/PG | 取决于兼容模式 |
| GaussDB | 是 | 是 | 兼容 Oracle | 兼容模式启用 CURSOR_SHARING |

> 统计：约 14 个引擎提供原生的自动参数化能力，多数 OLAP 引擎（包括 Snowflake/BigQuery/Trino/Spark SQL）哲学上拒绝在用户层做自动参数化，因为分析型查询的"参数"差异往往就是优化的关键。

### 强制参数化（Forced Parameterization / 全字面量替换）

| 引擎 | 支持 | 配置层级 | 启用语法 | 版本 |
|------|------|---------|---------|------|
| SQL Server | 是 | 数据库 | `ALTER DATABASE ... SET PARAMETERIZATION FORCED` | 2005+ |
| Oracle | 是 | 系统/会话 | `ALTER SYSTEM SET CURSOR_SHARING=FORCE` | 8i+ |
| Oracle | 是 (已废弃) | 系统/会话 | `CURSOR_SHARING=SIMILAR` | 9i-10g, 11g 已废弃 |
| DB2 | 是 | 实例 | `db2set DB2_REDUCED_OPTIMIZATION` 等 | 9.7+ |
| TiDB | 是 | 全局/会话 | `tidb_enable_non_prepared_plan_cache=ON` | 6.0+ |
| OceanBase | 是 | 全局/会话 | `cursor_sharing` (Oracle 兼容) | 4.0+ |
| SAP HANA | 是 | 系统 | `parameter_homogenization=true` | 默认开启 |
| GaussDB | 是 | 会话 | `cursor_sharing=FORCE` | 兼容 Oracle |
| 其他 | 通常 -- | -- | -- | -- |

> 统计：仅约 7 个引擎提供"强制参数化"开关，且几乎全部位于成熟的 OLTP/HTAP 引擎中。

### 每查询级别的 CURSOR_SHARING / 控制

| 引擎 | 单查询参数化控制 | 语法 | 版本 |
|------|----------------|------|------|
| Oracle | 是 | `/*+ CURSOR_SHARING_EXACT */` Hint | 9i+ |
| SQL Server | 是 | `OPTION (PARAMETERIZATION FORCED/SIMPLE)` (计划指南) | 2005+ |
| SQL Server | 是 | `sp_create_plan_guide` | 2005+ |
| TiDB | 是 | SQL Hint `/*+ IGNORE_PLAN_CACHE() */` | 6.0+ |
| OceanBase | 是 | Hint | 4.0+ |
| 其他 | -- | -- | -- |

### 绑定变量窥探（Bind Peeking）

| 引擎 | Bind Peeking | 自适应共享 | 默认开启 | 版本 |
|------|------------|-----------|---------|------|
| Oracle | 是 | Adaptive Cursor Sharing | 是 | Peek 9i+, ACS 11g+ |
| SQL Server | 是 (parameter sniffing) | -- (需手动) | 是 | 长期 |
| SQL Server | 部分 | OPTIMIZE FOR UNKNOWN | 2008+ | -- |
| SQL Server | 部分 | Query Store + Parameter Sensitive Plan | SQL Server 2022 | 2022+ |
| PostgreSQL | 是 (custom plan 阶段) | `plan_cache_mode` | 是 | Peek 长期，cache_mode 12+ |
| MySQL | 极少 | -- | 是 | 5.7+ 部分支持 |
| MariaDB | 极少 | -- | 是 | -- |
| DB2 | 是 (REOPT) | REOPT 选项 | `REOPT NONE` 默认 | 9.7+ |
| Snowflake | 内部 | -- | -- | -- |
| Redshift | 是 (有限) | -- | -- | -- |
| CockroachDB | 是 | session-based ideal plan | 是 | 22.1+ |
| TiDB | 是 | -- | 是 | 6.0+ |
| OceanBase | 是 | ACS 风格 | 是 | 4.0+ |
| SAP HANA | 是 | parameter sensitivity | 是 | 1.0 SP09+ |
| Teradata | 是 | -- | -- | -- |

> 统计：约 12 个引擎实现了某种形式的 bind peeking 或 parameter sniffing，其中只有 Oracle (ACS)、SAP HANA、CockroachDB、SQL Server 2022 (Parameter Sensitive Plan) 提供完整的"自适应"机制。

### 参数嗅探缓解策略

| 引擎 | 提示/配置 | 策略 | 版本 |
|------|----------|------|------|
| SQL Server | `OPTION (RECOMPILE)` | 每次重新编译 | 2005+ |
| SQL Server | `OPTION (OPTIMIZE FOR (var = value))` | 用指定值嗅探 | 2008+ |
| SQL Server | `OPTION (OPTIMIZE FOR UNKNOWN)` | 用统计平均值 | 2008+ |
| SQL Server | Trace Flag 4136 | 全局禁用嗅探 | 2008 SP1 CU7+ |
| SQL Server | Database Scoped Configuration | `PARAMETER_SNIFFING=OFF` | 2016+ |
| SQL Server | Parameter Sensitive Plan | 为不同参数生成多计划 | 2022+ |
| Oracle | `BIND_AWARE` Hint | 强制 ACS 多计划 | 11g+ |
| Oracle | `NO_BIND_AWARE` Hint | 禁用 ACS | 11g+ |
| Oracle | `_optim_peek_user_binds=FALSE` | 关闭 peek (隐藏参数) | 9i+ |
| PostgreSQL | `plan_cache_mode = force_custom_plan` | 每次按实际值优化 | 12+ |
| PostgreSQL | `plan_cache_mode = force_generic_plan` | 强制使用通用计划 | 12+ |
| PostgreSQL | `plan_cache_mode = auto` | 5 次后比较 | 12+ |
| DB2 | `REOPT ALWAYS` | 每次重新优化 | 9.7+ |
| DB2 | `REOPT ONCE` | 第一次嗅探后固定 | 9.7+ |
| DB2 | `REOPT NONE` | 通用计划，从不嗅探 | 9.7+ |
| TiDB | `tidb_session_plan_cache_size` | 控制缓存条数 | 6.0+ |

## 各引擎的实现策略

### SQL Server: simple → forced parameterization

SQL Server 是参数化能力最成熟的引擎之一，提供两个层级：

**Simple Parameterization (2005+，默认开启)**：

```sql
-- 用户写：
SELECT * FROM Orders WHERE OrderID = 12345;

-- SQL Server 内部转换为：
SELECT * FROM Orders WHERE OrderID = @1;
-- 类型：@1 INT
```

但 SQL Server 只在判定为 **safe plan** 的情况下才做 simple parameterization。"safe" 定义为：无论参数取何值，都会得到相同的计划（如等值索引查找单行）。一旦优化器认为参数值会影响计划，立即放弃 simple parameterization，回退到字面量计划：

```sql
-- 这条不会被自动参数化（IN 列表数量影响计划）：
SELECT * FROM Orders WHERE Status IN ('A', 'B', 'C');

-- 这条不会被自动参数化（范围条件可能走索引或扫描）：
SELECT * FROM Orders WHERE OrderDate >= '2025-01-01';

-- 这条会被自动参数化（PK 等值查找）：
SELECT * FROM Orders WHERE OrderID = 12345;
```

**Forced Parameterization (2005+，默认关闭)**：

通过数据库级配置开启：

```sql
ALTER DATABASE MyDB SET PARAMETERIZATION FORCED;
```

启用后所有字面量都会被替换为参数（除了少量例外）。代价是：

- 范围查询可能走错索引（值的选择性差异被抹平）
- IN 列表大小变化导致计划失效
- 字符串类型字面量统一为 NVARCHAR(4000)，可能影响隐式转换

例外情况（即使 FORCED 也保留字面量）：
- INSERT ... VALUES 中的字面量
- TOP / OFFSET / FETCH 中的字面量
- LIKE 模式
- USE / SET 选项参数
- 与计算列定义中字面量比较的常量

**Optimize for ad hoc workloads (2008+)**：

```sql
-- 服务器级配置
EXEC sp_configure 'optimize for ad hoc workloads', 1;
RECONFIGURE;
```

此选项的核心作用：第一次执行某 ad-hoc SQL 时，**只缓存计划存根（stub）** 而不是完整计划——只占几百字节内存。第二次同样文本再来时，编译为完整计划并替换存根。这避免了"一次性 SQL 占满 plan cache" 的问题。

注意：optimize for ad hoc workloads **不是参数化**，而是缓存大小控制策略。通常与 simple/forced parameterization 协同启用。

**Parameter Sniffing 控制**：

```sql
-- 1. RECOMPILE：每次都重新优化
SELECT * FROM Orders WHERE Status = @status
OPTION (RECOMPILE);

-- 2. OPTIMIZE FOR：嗅探指定值
SELECT * FROM Orders WHERE Status = @status
OPTION (OPTIMIZE FOR (@status = 'active'));

-- 3. OPTIMIZE FOR UNKNOWN：用统计直方图均值
SELECT * FROM Orders WHERE Status = @status
OPTION (OPTIMIZE FOR UNKNOWN);

-- 4. 数据库级关闭嗅探
ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SNIFFING = OFF;

-- 5. SQL Server 2022+ Parameter Sensitive Plan：为不同参数自动生成多个计划
-- 默认开启，由 Query Store 驱动
```

### Oracle: CURSOR_SHARING 三档与 Adaptive Cursor Sharing

Oracle 的参数化能力以 `CURSOR_SHARING` 参数为核心，从 8i (1999) 即开始演化：

```sql
-- 三个值：EXACT (默认) / FORCE / SIMILAR
ALTER SYSTEM SET CURSOR_SHARING = FORCE;

-- 会话级别：
ALTER SESSION SET CURSOR_SHARING = FORCE;
```

| 值 | 行为 | 引入版本 |
|---|------|---------|
| EXACT | 仅当 SQL 文本完全相同（含字面量）才共享计划 | 默认 |
| FORCE | 把所有字面量替换为绑定变量后共享计划 | 8i (1999) |
| SIMILAR | 复杂规则：仅在不影响计划的字面量替换为绑定 | 9i, 已在 11g (2007) 废弃 |

SIMILAR 的问题：它要"动态"判断每个字面量是否影响计划，可能为同一参数化文本生成多个子游标（child cursors），导致游标爆炸。11g 引入了 Adaptive Cursor Sharing 取代它。

**Bind Peeking (9i+)**：

```sql
-- 第一次执行
SELECT * FROM orders WHERE status = :s;
-- 绑定 :s = 'active'，假设 active 占 5%

-- 优化器 peek 到 'active'，选择索引扫描
-- 计划被缓存

-- 第二次执行
EXECUTE WITH :s = 'archived';  -- 占 95%
-- 复用索引扫描计划！全表 95% 的行做随机 I/O，性能崩溃
```

**Adaptive Cursor Sharing (11g+, 2007)**：

ACS 是对 bind peeking 的根本性改进，关键概念：

1. **Bind Sensitive**：优化器标记某些游标"参数敏感"——它的计划质量取决于绑定值。判定条件包括：
   - 等值条件中绑定变量参与了选择性差异大的列
   - 范围条件中的绑定变量
   - LIKE 中的绑定变量
   - 列上有数据倾斜（直方图显示频率分布不均）

2. **Bind Aware**：经过几次执行后，如果发现实际行数与估计行数差异大，游标进入 "bind aware" 状态。

3. **多计划共存**：bind aware 游标会按绑定值的"选择性桶"维护多个子游标。每个新的绑定值先用现有桶的计划试运行，如果实际行数偏离桶的范围，触发硬解析生成新计划。

```sql
-- 查看 ACS 状态
SELECT sql_id, child_number, is_bind_sensitive, is_bind_aware,
       executions, buffer_gets
FROM v$sql
WHERE sql_id = '&your_sql_id';

-- 强制启用 ACS
SELECT /*+ BIND_AWARE */ * FROM orders WHERE status = :s;

-- 禁用 ACS
SELECT /*+ NO_BIND_AWARE */ * FROM orders WHERE status = :s;

-- 查看选择性桶（v$sql_cs_*）
SELECT * FROM v$sql_cs_histogram WHERE sql_id = '&your_sql_id';
SELECT * FROM v$sql_cs_selectivity WHERE sql_id = '&your_sql_id';
SELECT * FROM v$sql_cs_statistics WHERE sql_id = '&your_sql_id';
```

**关闭 bind peeking 的隐藏参数**：

```sql
-- 慎用：关闭 peeking 后所有计划都用平均统计估算
ALTER SYSTEM SET "_optim_peek_user_binds" = FALSE;
```

### MySQL / MariaDB: parameter sniffing 极弱

MySQL 长期对 parameter sniffing 几乎不做任何处理。MySQL 5.7 引入的 prepared statement plan cache 也非常基础，没有 ACS 类的自适应机制。MySQL 8.0 起：

```sql
-- 准备时不做参数嗅探，每次执行都使用相同计划
PREPARE stmt FROM 'SELECT * FROM orders WHERE status = ?';
EXECUTE stmt USING @s;

-- 没有 OPTIMIZE FOR、没有 ACS、没有自动重编译机制
-- 唯一的"参数化"路径就是显式 PREPARE
```

实际工程实践中，MySQL 用户通常依赖：

1. 应用层使用预编译协议（COM_STMT_PREPARE）
2. 关键查询用 `IGNORE INDEX` / `FORCE INDEX` Hint 固定计划
3. 极端场景对 ad-hoc 文本拼接（牺牲缓存命中换计划准确性）

### PostgreSQL: custom plan vs generic plan + plan_cache_mode (12+)

PostgreSQL 不做隐式的字面量参数化——只有显式 `PREPARE` 才进入参数化路径。但 PG 在 prepared statement 上有一套独特的"自动选择"机制：

```sql
PREPARE stmt(int) AS SELECT * FROM orders WHERE customer_id = $1;

-- 第 1-5 次执行：custom plan
-- 每次按实际参数值重新优化（如同 ad-hoc）
EXECUTE stmt(123);
EXECUTE stmt(456);
EXECUTE stmt(789);
EXECUTE stmt(101);
EXECUTE stmt(102);

-- 第 6 次开始：PG 计算 generic plan 的代价
-- 如果 generic plan 代价 < custom plan 平均代价 + 启发式 buffer
-- 则切换到 generic plan，从此每次执行不重新优化
EXECUTE stmt(103);  -- 可能开始用 generic plan
```

**plan_cache_mode 参数 (12+, 2019)**：

```sql
-- 默认值：5 次后启发式选择
SET plan_cache_mode = 'auto';

-- 永远使用 custom plan：每次按实际值重新优化
-- 适合参数倾斜大的工作负载
SET plan_cache_mode = 'force_custom_plan';

-- 永远使用 generic plan：第一次后不再重优化
-- 适合参数选择性差异小的高 QPS OLTP
SET plan_cache_mode = 'force_generic_plan';
```

启发式公式（PG 源码 `plancache.c`）：

```
generic_cost < min(custom_avg_cost) + 10 * cpu_operator_cost
```

含义：generic plan 必须明显优于 custom plan 的最佳历史代价才会被采纳。10 * cpu_operator_cost 是反对 generic plan 的"惯性偏置"。

### CockroachDB: session-based plan stability

CockroachDB (22.1+) 引入了显式的 query plan cache，对 ad-hoc SQL 自动参数化：

```sql
-- 默认开启
SHOW CLUSTER SETTING sql.query_cache.enabled;  -- true
SHOW CLUSTER SETTING sql.plan_cache.enabled;   -- true (22.1+)

-- 自动参数化：
SELECT * FROM orders WHERE id = 1;
SELECT * FROM orders WHERE id = 2;
-- 内部都归一化为 SELECT * FROM orders WHERE id = $1
-- 第二条命中缓存，跳过解析与优化

-- 查看 plan cache
SELECT * FROM crdb_internal.cluster_statement_statistics
WHERE plan_gist IS NOT NULL
LIMIT 10;

-- 禁用某查询的缓存
SELECT * FROM orders WHERE id = 1 /* +DISABLE_QUERY_CACHE */;
```

CockroachDB 的设计选择：plan_cache 是 session-scoped 的"stable plan cache"，对参数化的 ad-hoc SQL 在 session 内保持计划稳定，跨 session 通过 cluster setting 控制全局缓存。

### TiDB: 通用计划缓存

TiDB 提供两个层级的参数化机制：

**显式 prepared plan cache (4.0+)**：

```sql
-- 仅对显式 PREPARE / EXECUTE 生效
SET tidb_enable_prepared_plan_cache = ON;
SET tidb_session_plan_cache_size = 100;
```

**通用 plan cache（非 prepared，6.0+）**：

```sql
-- 6.0+ 引入：对 ad-hoc SQL 自动参数化
SET tidb_enable_non_prepared_plan_cache = ON;
SET tidb_session_plan_cache_size = 100;

-- 自动参数化：
SELECT * FROM t WHERE id = 1;
SELECT * FROM t WHERE id = 2;
-- 共享计划，但 TiDB 会拒绝某些"高风险"模式的参数化
```

TiDB 的非 prepared plan cache 拒绝以下模式的自动参数化：
- 包含子查询的 SQL
- 包含 SELECT FOR UPDATE
- 包含 hint
- 包含表 partition 关联条件
- IN 子句长度可变

```sql
-- 查看哪些 SQL 没被缓存
SELECT * FROM information_schema.statements_summary
WHERE plan_in_cache = 0
LIMIT 10;

-- 强制不使用 plan cache（针对单个 SQL）
SELECT /*+ IGNORE_PLAN_CACHE() */ * FROM t WHERE id = 1;
```

### OceanBase: 双模 cursor sharing

OceanBase 同时支持 MySQL 和 Oracle 模式，在 Oracle 兼容模式下完整支持 `CURSOR_SHARING`：

```sql
-- Oracle 兼容模式下：
ALTER SYSTEM SET cursor_sharing = 'FORCE';

-- 默认情况下，OB 的 fast parser 也会做轻量级参数化
-- 对 OLTP 极简 SQL 命中"快速参数化"路径
```

OceanBase 4.x 实现了 ACS 风格的自适应共享：

```sql
-- 4.0+ 支持 SPM (SQL Plan Management) 类似 Oracle
DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE(...);
```

### SAP HANA: parameter homogenization

SAP HANA 默认开启 parameter homogenization，把字面量参数化后存入 plan cache：

```sql
-- 配置：
ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'system')
SET ('sql', 'parameter_homogenization') = 'true' WITH RECONFIGURE;

-- 关闭：
SET ('sql', 'parameter_homogenization') = 'false' WITH RECONFIGURE;
```

### 其他引擎

```sql
-- DB2: REOPT 选项控制嗅探时机
PREPARE stmt FROM 'SELECT * FROM orders WHERE status = ?'
WITH REOPT NONE;     -- 默认：用通用计划
WITH REOPT ONCE;     -- 第一次执行后嗅探一次
WITH REOPT ALWAYS;   -- 每次执行都重新优化

-- 启用 statement concentrator (类似 forced parameterization)
db2set DB2_REDUCED_OPTIMIZATION=NO_INDEX_LOOKUP

-- Teradata: Request Cache 自动归一化
-- 通过 dbscontrol 或 ResUsage 字段查看缓存命中

-- SingleStore: 默认开启 plan cache
SET GLOBAL plan_cache_size = 100000000;
SHOW STATUS LIKE 'plan_cache_%';

-- StarRocks 3.0+: query_cache（结果缓存为主）
SET enable_query_cache = true;

-- Redshift: 编译缓存对相同查询模板自动复用
-- 不暴露详细配置，但 query rewrite 会做有限的字面量参数化

-- Spanner: 自动参数化对 ad-hoc SQL 标准化
-- 通过 query parameters 显式参数化推荐
```

## Oracle Adaptive Cursor Sharing 深度剖析

ACS 是数据库参数化领域最复杂、也最有教学意义的机制。理解它，等于理解所有 bind peeking 取舍的本质。

### 三种游标状态

每个 SQL 在 v$sql 中有三个关键标记：

| 标记 | 含义 | 触发条件 |
|------|------|---------|
| `IS_BIND_SENSITIVE = Y` | 优化器认为绑定值会影响计划 | 等值条件 + 直方图列；范围条件；LIKE |
| `IS_BIND_AWARE = Y` | 启用了多计划共存机制 | 多次执行行数估计偏差大 |
| `IS_SHAREABLE = Y` | 当前游标可被复用 | 否则下次执行硬解析新游标 |

### 选择性桶（Selectivity Buckets）

ACS 把绑定变量产生的选择性映射到桶：

```
绑定值 :s = 'active' → 选择性 0.05
绑定值 :s = 'archived' → 选择性 0.95
绑定值 :s = 'deleted' → 选择性 0.001

桶 1: 选择性 [0.0, 0.10] → 计划 A (索引扫描)
桶 2: 选择性 (0.10, 0.50] → 计划 B (索引快速扫描)
桶 3: 选择性 (0.50, 1.0] → 计划 C (全表扫描)
```

每个新的绑定值先按"现有桶最近匹配"试运行，比较实际行数与估计行数：

- 偏差小：归入该桶，复用计划
- 偏差大：触发硬解析，创建新桶或扩展现有桶

### ACS 与统计信息的协同

ACS 依赖两个统计输入：

1. **直方图（Histogram）**：列上的值分布。`DBMS_STATS.GATHER_TABLE_STATS` 收集。
2. **绑定窥探（Bind Peeking）**：第一次硬解析时实际绑定值。

直方图缺失时，ACS 依然能工作但效果减弱——它依靠运行时实际行数差异来识别 sensitive 的绑定。

### ACS 失效与陷阱

```sql
-- 陷阱 1：ACS 不会立即生效
-- 第一次硬解析仍使用初始绑定值的计划
-- 需要至少 2-3 次执行才进入 bind aware 状态

-- 陷阱 2：游标失效后状态丢失
-- 表 ANALYZE、DDL、共享池 flush 都会重置
ALTER SYSTEM FLUSH SHARED_POOL;  -- 后果：所有 ACS 状态归零

-- 陷阱 3：游标爆炸
-- 极端倾斜数据可能产生数十个子游标
-- 受 V$SQL_SHARED_CURSOR.HASH_MATCH_FAILED 影响
SELECT child_number, is_bind_sensitive, is_bind_aware
FROM v$sql WHERE sql_id = '&id';

-- 陷阱 4：BIND_AWARE Hint 强制立即启用
SELECT /*+ BIND_AWARE */ * FROM orders WHERE status = :s;

-- 陷阱 5：cursor_sharing = FORCE + ACS 的微妙交互
-- FORCE 把字面量都换成绑定变量
-- ACS 必须更频繁地判别 sensitivity
-- 在大量字面量的 ad-hoc 场景下 ACS 开销显著
```

### ACS 的演化时间线

| 版本 | 增强 |
|------|------|
| 8i (1999) | CURSOR_SHARING=FORCE 引入 |
| 9i (2001) | bind peeking 引入 |
| 9i | CURSOR_SHARING=SIMILAR 引入 |
| 10g | SIMILAR 改进选择性判定 |
| 11g (2007) | ACS 引入；SIMILAR 已废弃 |
| 11gR2 | ACS 集成 SQL Plan Management |
| 12c (2013) | 自适应执行计划 + ACS 联动 |
| 12cR2 | Statistics Feedback 与 ACS 协同 |
| 19c | ACS 与 Real-Time Statistics 联动 |

## PostgreSQL plan_cache_mode 详解

PG 的 plan_cache_mode 在 12 (2019) 之前隐藏在源码内部，12 起暴露为用户可控参数。

### 三种模式的工程含义

```sql
-- auto (默认): 启发式
-- 前 5 次：custom plan
-- 第 6 次起：评估 generic plan
SET plan_cache_mode = 'auto';

-- force_custom_plan: 永远 custom
-- 每次都重新优化，相当于禁用计划缓存的"参数化优势"
-- 但保留了 PREPARE 的参数绑定语义和 SQL 注入防御
SET plan_cache_mode = 'force_custom_plan';

-- force_generic_plan: 永远 generic
-- 第一次硬解析（用 NULL 替换参数估计）后固化
-- OLTP 场景的极致吞吐选项
SET plan_cache_mode = 'force_generic_plan';
```

### 何时该用哪种模式

| 场景 | 推荐模式 | 原因 |
|------|---------|------|
| 高 QPS 单表 PK 查询 | `force_generic_plan` | 减少每次优化开销 |
| 参数选择性差异极大的搜索 | `force_custom_plan` | 避免错误的通用计划 |
| 一般 OLTP 应用 | `auto` (默认) | 启发式自动平衡 |
| 报表/分析查询（参数变化大） | `force_custom_plan` | 优化质量优先 |
| 小表读取（计划简单） | `force_generic_plan` | 优化器开销节约 |

### 实战案例

```sql
-- 案例 1：搜索分页
PREPARE search(text, int, int) AS
SELECT * FROM products WHERE name ILIKE $1 LIMIT $2 OFFSET $3;

-- $1 = 'a%' 选择性 50%
-- $1 = 'xyz%' 选择性 0.001%
-- 两者最优计划完全不同

-- 用 auto 时：
-- 前 5 次基于实际值优化
-- 第 6 次起 generic plan 可能选错
-- 推荐：force_custom_plan

-- 案例 2：dashboard 高频查询
PREPARE user_orders(int) AS
SELECT * FROM orders WHERE user_id = $1
ORDER BY created_at DESC LIMIT 10;

-- 所有 user_id 的选择性都相近（每用户订单数相似）
-- generic plan 完全够用
-- 推荐：force_generic_plan

-- 监控 prepared statement 计划选择
SELECT * FROM pg_prepared_statements;
-- generic_plans 列：使用 generic plan 的次数
-- custom_plans 列：使用 custom plan 的次数
```

## SQL Server forced parameterization 的实战警告

forced parameterization 看似是"加速 ad-hoc 工作负载"的银弹，但实战中暗藏多个陷阱。

### 陷阱 1：字符串字面量类型推断

```sql
-- 用户写：
SELECT * FROM Customers WHERE CustomerID = 'AB-12345';

-- forced parameterization 转换：
SELECT * FROM Customers WHERE CustomerID = @0;
-- @0 类型：NVARCHAR(4000)！

-- 如果 CustomerID 列是 VARCHAR(10)
-- 隐式转换 NVARCHAR → VARCHAR 会让索引失效
-- 性能从 0.001 秒退化到 10 秒
```

### 陷阱 2：范围条件计划共享

```sql
-- 用户写：
SELECT * FROM Sales WHERE SaleDate >= '2025-01-01' AND SaleDate < '2025-02-01';

-- forced parameterization：
SELECT * FROM Sales WHERE SaleDate >= @0 AND SaleDate < @1;

-- 但用户后来执行：
SELECT * FROM Sales WHERE SaleDate >= '2025-01-01' AND SaleDate < '2025-12-31';

-- 共享同一计划！
-- 1 个月数据走索引扫描合理
-- 12 个月数据应该全表扫描，但被迫走索引扫描
-- 性能差 50-100 倍
```

### 陷阱 3：IN 列表大小变化

```sql
-- 用户 A 执行：
SELECT * FROM Orders WHERE Status IN ('A');         -- 1 个值

-- 用户 B 执行：
SELECT * FROM Orders WHERE Status IN ('A', 'B', 'C', 'D', 'E');  -- 5 个值

-- forced parameterization 不会跨数量共享
-- 每个 IN 列表大小都是不同的计划
-- 反而比 simple parameterization 多生成大量计划
```

### 陷阱 4：与计划指南（Plan Guide）的协调

```sql
-- 即使数据库级 forced parameterization 开启
-- 也可以通过计划指南为单条 SQL 关闭：
EXEC sp_create_plan_guide
    @name = N'PG_disable_forced',
    @stmt = N'SELECT * FROM Sales WHERE SaleDate >= ''2025-01-01'' AND SaleDate < ''2025-02-01''',
    @type = N'SQL',
    @hints = N'OPTION (PARAMETERIZATION SIMPLE)';
```

### 陷阱 5：模板查询模板碰撞

forced parameterization 把所有字面量转换为参数后，不同业务的 SQL 可能映射到同一模板。如果其中一个查询的字面量决定了关键索引选择，另一个业务的查询就会受牵连。生产环境实践：

- 评估 ad-hoc 工作负载比例（< 30% 时不建议开启）
- 通过 Query Store 监控 forced parameterization 后计划稳定性
- 准备 plan guide 兜底关键查询
- 配合 SQL Server 2022 Parameter Sensitive Plan 自动应对倾斜

## 参数化与统计信息的相互依赖

参数化的最大风险来源——统计信息——值得专门讨论。

### 直方图与参数化的协同

```
没有直方图：
  优化器仅有 NDV (number of distinct values) 和总行数
  对绑定 :s 的选择性估计 = 1 / NDV
  全部值假定均匀分布

有直方图：
  特定值的频率已知，bind peek 后能给出准确选择性
  ACS / OPTIMIZE FOR UNKNOWN 才有意义
```

实践建议：高频参数化路径必须保证关键 WHERE 列上有最新直方图。

### 统计信息过期对参数化的影响

```sql
-- Oracle: 自动统计 + 增量统计
EXEC DBMS_STATS.GATHER_TABLE_STATS(
    ownname => 'SCOTT', tabname => 'ORDERS',
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
    method_opt => 'FOR ALL COLUMNS SIZE AUTO',
    cascade => TRUE
);

-- SQL Server: 自动更新触发阈值
-- 表大小 < 500 行：500 + 20% 行变化触发
-- 表大小 ≥ 500 行：500 + 表大小开方行变化（2014+ trace flag 2371）
ALTER DATABASE MyDB SET AUTO_UPDATE_STATISTICS ON;
ALTER DATABASE MyDB SET AUTO_UPDATE_STATISTICS_ASYNC ON;

-- PostgreSQL: autovacuum + ANALYZE
-- autovacuum_analyze_scale_factor = 0.1 (默认)
-- 即变化超过表 10% 触发 ANALYZE
```

统计信息陈旧时，bind peek 得到的选择性估计错误，无论是 ACS 还是 PG plan_cache_mode 都会做出错误判断。

## ad-hoc 与参数化的协议路径对比

理解参数化必须理解协议层。同一条 SQL 通过不同协议路径可能完全不同。

### 路径 A: 显式 PREPARE（标准方式）

```python
# psycopg2 / PostgreSQL
cur.execute("SELECT * FROM orders WHERE id = %s", (12345,))
# 实际：协议层 Parse + Bind + Execute
# 服务器端有 prepared statement，进入 plan_cache_mode 路径

# JDBC / MySQL
PreparedStatement ps = conn.prepareStatement("SELECT * FROM orders WHERE id = ?");
ps.setInt(1, 12345);
ps.executeQuery();
# 服务器端 COM_STMT_PREPARE，进入 prepared plan cache
```

### 路径 B: 客户端拼接（ad-hoc）

```python
# 危险：SQL 注入 + 不进入参数化路径
cur.execute(f"SELECT * FROM orders WHERE id = {12345}")
# 服务器看到的是字面量 SQL
# 进入 simple/forced parameterization (如果引擎支持)
```

### 路径 C: 服务端宏 / 函数

```sql
-- 在数据库内部用 EXECUTE IMMEDIATE
DECLARE
  v_id INT := 12345;
  v_sql VARCHAR2(200);
  v_count INT;
BEGIN
  v_sql := 'SELECT COUNT(*) FROM orders WHERE id = :1';
  EXECUTE IMMEDIATE v_sql INTO v_count USING v_id;
END;
-- Oracle: 进入库缓存的 prepared cursor 路径
```

### 路径 D: 中间件参数化

某些应用框架（如 MyBatis、Hibernate）在客户端做参数化，结果传到服务端的是参数化后的 SQL 文本：

```sql
-- 应用层：
SELECT * FROM orders WHERE id = #{id}
-- 实际发送：
SELECT * FROM orders WHERE id = ?
-- 进入服务器的预编译路径
```

每条路径与服务器参数化机制的交互不同：

| 路径 | 服务器看到 | 参数化路径 |
|------|----------|-----------|
| A 显式 PREPARE | 协议层 Parse 命令 | 显式 prepared cache |
| B 客户端拼接 | 字面量 SQL 文本 | 自动参数化（如启用） |
| C 服务端 EXECUTE IMMEDIATE | 字符串 SQL | 共享池/库缓存 |
| D 中间件参数化 | 协议层 Prepare/Bind | 显式 prepared cache |

## 关键发现

### 发现 1：参数化能力与引擎类型强相关

OLTP 引擎（Oracle/SQL Server/DB2/MySQL/PostgreSQL）必须做参数化——核心收益是把每秒数千次硬解析压缩到接近零。OLAP 引擎（Snowflake/BigQuery/Trino/Redshift）哲学上拒绝隐式参数化——分析查询的"参数"差异（日期范围、维度过滤）正是优化器需要重新考虑的关键。

```
OLTP: 参数化是吞吐量基石 → 自动参数化默认开启
OLAP: 参数化是优化阻碍 → 完全跳过自动参数化
HTAP: 折中（TiDB/OceanBase）→ 提供开关，默认偏 OLTP
```

### 发现 2：bind peeking 是无解的取舍

无论 Oracle ACS、SQL Server Parameter Sensitive Plan、PG plan_cache_mode，本质上都在解决同一个无解的问题：**参数化要复用计划，但不同参数值要的计划不同**。三种解法：

1. **多计划共存**：Oracle ACS、SQL Server PSP（2022+）。代价：游标爆炸、内存占用、复杂度高。
2. **每次重新优化**：PG force_custom_plan、SQL Server OPTION(RECOMPILE)、DB2 REOPT ALWAYS。代价：失去参数化的吞吐优势。
3. **平均化代价**：PG force_generic_plan、SQL Server OPTIMIZE FOR UNKNOWN。代价：极端倾斜场景性能崩溃。

没有银弹，工程师必须按工作负载特征选择。

### 发现 3：自动参数化的"安全判定"是一门艺术

SQL Server 的 simple parameterization 只在判定 safe plan 时执行，这套规则极其复杂。Oracle 的 SIMILAR 在 11g 被废弃，原因正是 safe 判定不可靠。Forced parameterization 的存在恰恰是因为 simple parameterization 覆盖率有限。

学到的教训：**完全自动 + 完全正确 = 不可能**。引擎要么保守（simple，覆盖率低）、要么激进（forced，需用户兜底）、要么中间（SIMILAR/ACS，复杂度高）。

### 发现 4：协议层 vs SQL 层参数化是两套体系

许多用户混淆 `PREPARE ... EXECUTE` SQL 语句与 JDBC `PreparedStatement` 协议层 API。它们的交互是：

- 客户端 PreparedStatement → 协议层 Parse/Bind → 服务器内部的 prepared cache（与 SQL 层 PREPARE 通常共享但不一定）。
- SQL 层 `PREPARE` 仅为同会话 SQL 显式参数化提供入口。

理解这一点对调优至关重要——单纯统计 `pg_prepared_statements` 不能反映协议层的所有 prepare 量。

### 发现 5：统计信息是参数化的"地基"

参数化机制的所有"智能判断"——选择性估计、ACS 桶分配、PG generic vs custom 比较——都建立在统计信息之上。统计陈旧时：

- Oracle ACS 把所有绑定误判为同一桶
- PG plan_cache_mode 选错 generic vs custom
- SQL Server 优化器嗅探到错误的"代表性"值

实战要点：高 QPS 路径必须建立统计信息自动更新机制（不是默认依赖 autovacuum）。

### 发现 6：忽略参数化的代价比想象大

对一个典型 OLTP 系统，关闭自动参数化（如 SQL Server 切回 simple、Oracle 切回 EXACT）的可见后果：

- 共享池/plan cache 内存占用 5-10 倍增长
- 解析 CPU 从 5-10% 飙升到 50-70%
- 整体吞吐下降 30-60%

但启用 forced parameterization 也有代价：

- 个别"参数倾斜大"的查询性能下降 10-100 倍
- 调优工作必须配合 plan guide / hint 兜底
- 字符串字面量的隐式类型转换可能让索引失效

平衡点：simple parameterization 默认 + forced 选择性启用 + 关键查询用 hint 锁定。

### 发现 7：MySQL 在参数化领域的"长期欠账"

MySQL 是主流 OLTP 引擎中参数化能力最弱的。它没有：

- 自动 ad-hoc 参数化
- bind peeking 与多计划共存
- 类似 PG plan_cache_mode 的取舍开关
- 类似 OPTIMIZE FOR / RECOMPILE 的 hint

只有显式 PREPARE 的基础缓存。社区通过 MySQL 8.0 的 prepared statement plan cache 做了一些改进，但与 Oracle/SQL Server 的差距仍然显著。这也解释了为何在大型 MySQL 部署中，工程师常需要把 ad-hoc SQL 改成预编译 + 分库分表来缓解参数化能力的不足。

### 发现 8：云数仓哲学：放弃自动参数化，依赖结果缓存

Snowflake / BigQuery / Redshift 普遍不暴露用户级的 plan cache 控制。它们的策略：

- 内部对相同 SQL 文本（包括字面量）做计划缓存（编译缓存）
- 对相同结果集做结果缓存（result cache）
- 不做"字面量参数化"——让用户自己用 query parameters 显式参数化

哲学根源：云数仓的查询通常持续秒到分钟级，编译开销占比相对小；用户更关心结果缓存命中率（节约计算成本）。强制参数化反而会让选择性敏感的查询走错计划。

### 发现 9：HTAP 引擎的折中策略

TiDB / CockroachDB / OceanBase 这类 HTAP 引擎承担了所有矛盾：

- TiDB 6.0+ 提供 `tidb_enable_non_prepared_plan_cache` 开关，但默认对子查询、SELECT FOR UPDATE 等"危险模式"拒绝缓存
- CockroachDB 默认开启自动参数化，但 plan cache 是 session-scoped 防止跨会话污染
- OceanBase 4.x 同时实现了 fast parser（快速参数化）+ ACS（多计划），双引擎兼容

这些设计反映了 HTAP 工程师的现实：既要 OLTP 的高吞吐，又要 OLAP 的优化质量，妥协无可避免。

### 发现 10：Parameter Sensitive Plan 是下一代方向

SQL Server 2022 引入的 Parameter Sensitive Plan (PSP) 是 ACS 思想的现代化版本：

```sql
-- SQL Server 2022+ 默认开启
-- Query Store + 优化器协作
-- 对单个 SQL 自动判别 sensitivity
-- 为不同参数自动维护多达 3 个计划
```

PSP 是过去 20 年 Oracle ACS 经验的提炼：
- 默认开启（ACS 用户长期诟病的"延迟启用"问题）
- 与 Query Store 集成（持久化计划历史）
- 限制最多 3 计划（防止游标爆炸）
- 仅对等值条件 + 直方图列敏感（保守判定）

未来 PG / MySQL 大概率会跟进类似机制——这是参数化领域的一致演进方向。

## 对引擎开发者的实现建议

### 1. 参数化的核心数据结构

```
ParameterizationCache {
    // SQL 模板归一化后的哈希
    template_hash: u64

    // 模板对应的 prepared plan（含参数类型签名）
    plans: HashMap<ParamTypeSignature, ExecutionPlan>

    // 选择性桶（ACS 风格）
    selectivity_buckets: Vec<SelectivityBucket>

    // 元数据：sensitivity 判定结果
    is_bind_sensitive: bool
    is_bind_aware: bool
}

SelectivityBucket {
    range: (f64, f64)             // 选择性区间
    plan: ExecutionPlan
    sample_bind_values: Vec<Value>  // 此桶代表性绑定值
    actual_rows_history: Vec<u64>   // 实际行数历史
}
```

### 2. 字面量归一化算法

```
fn normalize_sql(sql: &str) -> (NormalizedSql, Vec<Literal>):
    let mut tokens = lex(sql);
    let mut literals = Vec::new();
    for token in &mut tokens:
        if is_safe_literal(token):
            literals.push(token.clone());
            *token = Token::Placeholder(literals.len() - 1);
    return (concat_tokens(tokens), literals);

fn is_safe_literal(token: &Token) -> bool:
    // 整数/小数/字符串/日期：通常 safe
    // 但要排除：
    //   - LIKE 中的字面量（影响计划）
    //   - IN 列表（数量影响计划）
    //   - TOP / LIMIT / OFFSET（影响计划）
    //   - INSERT VALUES（语义为数据写入）
    match token {
        IntLiteral | DecimalLiteral | StringLiteral | DateLiteral => true,
        BoolLiteral | NullLiteral => false,  // 类型推断风险
        _ => false,
    }
```

### 3. Bind Peeking 实现

```
fn optimize_with_bind_peek(
    sql_template: &str,
    bind_values: &[Value],
    catalog: &Catalog,
) -> ExecutionPlan:
    // Step 1: 用绑定值替换占位符做选择性估计
    let estimated_selectivities = estimate_with_actuals(sql_template, bind_values);
    // Step 2: 调用优化器
    let plan = optimize(sql_template, estimated_selectivities, catalog);
    // Step 3: 标记 sensitive
    plan.is_bind_sensitive = check_sensitivity(plan, bind_values, catalog);
    return plan;

fn check_sensitivity(plan: &ExecutionPlan, binds: &[Value], catalog: &Catalog) -> bool:
    for predicate in plan.predicates():
        for bind_idx in predicate.bind_indices():
            let column = predicate.column();
            // 关键判定：列上是否有直方图
            if catalog.has_histogram(column):
                return true;
            // 范围 / LIKE 谓词总是 sensitive
            if predicate.is_range() || predicate.is_like():
                return true;
    return false;
```

### 4. ACS 多计划管理

```
fn execute_with_acs(
    cache: &mut ParameterizationCache,
    bind_values: &[Value],
    catalog: &Catalog,
) -> ExecutionResult:
    // Step 1: 计算当前绑定的选择性
    let current_sel = compute_selectivity(bind_values, catalog);

    // Step 2: 找最近匹配桶
    let bucket = cache.selectivity_buckets.iter()
        .min_by_key(|b| (b.range.0 - current_sel).abs() + (b.range.1 - current_sel).abs())
        .unwrap_or(&default_bucket());

    // Step 3: 用桶内计划执行，记录实际行数
    let result = execute(&bucket.plan, bind_values);
    let estimated_rows = bucket.plan.estimated_rows();
    let actual_rows = result.row_count();

    // Step 4: 判断是否偏差大
    let estimation_error = (actual_rows as f64 - estimated_rows as f64).abs() / estimated_rows as f64;

    if estimation_error > THRESHOLD {
        // 触发硬解析，创建新桶
        let new_plan = optimize_with_bind_peek(cache.template, bind_values, catalog);
        let new_bucket = SelectivityBucket {
            range: (current_sel * 0.8, current_sel * 1.2),
            plan: new_plan,
            ..
        };
        cache.selectivity_buckets.push(new_bucket);
        cache.is_bind_aware = true;
    } else {
        // 更新桶的统计
        bucket.actual_rows_history.push(actual_rows);
    }

    return result;
```

### 5. 防止游标爆炸

```
ACS 实现必须有上限保护：

const MAX_BUCKETS_PER_TEMPLATE: usize = 32;
const MAX_TEMPLATES_PER_SCHEMA: usize = 100_000;

if cache.selectivity_buckets.len() >= MAX_BUCKETS_PER_TEMPLATE {
    // 选择最老 / 最少使用的桶替换
    evict_oldest_bucket(&mut cache.selectivity_buckets);
}

if global_cache.template_count() >= MAX_TEMPLATES_PER_SCHEMA {
    // LRU 淘汰 + 标记进入"参数化保守模式"
    evict_lru_template();
    log_warning("plan cache pressure: switching to conservative parameterization");
}
```

### 6. 与统计信息系统协同

```
Trigger 1: 表统计信息更新 → 失效相关的 sensitive 计划缓存
fn on_stats_update(table: TableId, cache: &mut ParameterizationCache):
    cache.invalidate_entries_referencing(table);

Trigger 2: 直方图变化 → 重新评估 sensitivity
fn on_histogram_update(column: ColumnId, cache: &mut ParameterizationCache):
    for entry in cache.entries_referencing(column):
        entry.recompute_sensitivity();

Trigger 3: 大量 DML → 标记需要 stats 刷新
fn on_dml_threshold_exceeded(table: TableId):
    schedule_stats_refresh(table);
```

### 7. 暴露给用户的可观察性

```
重要的诊断视图（参考 Oracle / SQL Server）：

V$SQL / sys.dm_exec_query_stats:
  - sql_text, plan_hash, executions
  - is_bind_sensitive, is_bind_aware
  - last_actual_rows, last_estimated_rows

V$SQL_CS_HISTOGRAM:
  - 每个桶的边界、命中次数

V$SQL_PLAN:
  - 完整执行计划文本

性能指标：
  - parse_count_hard / parse_count_soft (Oracle)
  - SP:CacheHit / SP:CacheMiss (SQL Server)
  - 命中率 = soft_parse / total_parse
```

### 8. 测试要点

```
单元测试：
  - 字面量归一化的边界（特殊字符、Unicode、转义）
  - 类型推断的正确性（INT vs BIGINT, VARCHAR vs NVARCHAR）
  - 不可参数化模式的拒绝（INSERT VALUES, TOP, LIKE）

集成测试：
  - 第一次执行硬解析 + 后续软解析路径
  - bind peeking 的选择性估计
  - ACS 多计划共存
  - 游标爆炸防护

性能测试：
  - 高 QPS 下硬解析比例
  - plan cache 内存占用增长曲线
  - sensitive vs insensitive 计划质量对比

混沌测试：
  - 表统计信息突变（5% → 95% 选择性翻转）
  - DDL 期间的计划失效
  - 内存压力下的 LRU 淘汰
```

## 总结对比矩阵

### 关键能力总览

| 能力 | Oracle | SQL Server | DB2 | PostgreSQL | MySQL | TiDB | OceanBase | SAP HANA |
|------|--------|------------|-----|-----------|-------|------|-----------|----------|
| 自动参数化 (默认) | EXACT | simple | -- | -- | -- | 是 | 是 | 是 |
| 强制参数化 | FORCE | FORCED | REOPT | -- | -- | non_prepared | force | homogenization |
| 单查询控制 | Hint | Plan Guide | REOPT | mode | -- | Hint | Hint | -- |
| Bind Peeking | 9i+ | 是 | REOPT | 是 | -- | 是 | 是 | 是 |
| 多计划共存 | ACS 11g+ | PSP 2022+ | -- | -- | -- | -- | ACS | -- |
| 用户控制开关 | CURSOR_SHARING | PARAMETERIZATION | REOPT | plan_cache_mode | -- | tidb_enable_* | cursor_sharing | parameter_homogenization |
| 计划稳定性集成 | SPM | Query Store | Profile | -- | -- | Binding | Outline | Plan Stability |

### 关键版本演进

| 年份 | 引擎 | 里程碑 |
|------|------|--------|
| 1999 | Oracle 8i | CURSOR_SHARING=FORCE 首次出现 |
| 2001 | Oracle 9i | bind peeking 引入；CURSOR_SHARING=SIMILAR |
| 2005 | SQL Server 2005 | simple + forced parameterization |
| 2007 | Oracle 11g | ACS 引入；SIMILAR 已废弃 |
| 2008 | SQL Server 2008 | OPTIMIZE FOR / OPTIMIZE FOR UNKNOWN |
| 2008 | SQL Server 2008 | "optimize for ad hoc workloads" 服务器配置 |
| 2009 | DB2 9.7 | REOPT 选项 |
| 2013 | Oracle 12c | 自适应执行计划 + ACS 联动 |
| 2016 | SQL Server 2016 | Query Store 引入 |
| 2017 | SQL Server 2017 | 自动调优 (Auto Tune) |
| 2019 | PostgreSQL 12 | plan_cache_mode 暴露为用户参数 |
| 2020 | TiDB 4.0 | prepared plan cache |
| 2022 | TiDB 6.0 | non-prepared plan cache（自动参数化） |
| 2022 | SQL Server 2022 | Parameter Sensitive Plan (PSP) |
| 2022 | CockroachDB 22.1 | 自动参数化 + plan cache |

### 工作负载选型建议

| 工作负载 | 推荐策略 | 推荐引擎/配置 |
|---------|---------|--------------|
| 高 QPS PK 等值查询 | 自动参数化 + generic plan | Oracle CURSOR_SHARING=EXACT + bind 接口 / PG force_generic_plan / SQL Server simple |
| 高 QPS 范围查询（参数倾斜大） | 多计划共存 | Oracle ACS / SQL Server PSP |
| 中频复杂报表 | 不参数化或 custom | PG force_custom_plan / SQL Server RECOMPILE |
| 极高 QPS 读 + 重复模板 | 强制参数化 | SQL Server FORCED / Oracle FORCE / TiDB non_prepared |
| 分析仓库（Snowflake/BigQuery） | 显式 query parameters | 客户端控制 |
| HTAP 混合 | 双开关 | TiDB session 级别 + 关键 SQL hint |
| 嵌入式/小负载 | 不需要参数化 | SQLite/DuckDB/H2 |

## 参考资料

- SQL Server: [Forced Parameterization](https://learn.microsoft.com/en-us/sql/relational-databases/query-processing-architecture-guide#forced-parameterization)
- SQL Server: [Optimize for ad hoc workloads](https://learn.microsoft.com/en-us/sql/database-engine/configure-windows/optimize-for-ad-hoc-workloads-server-configuration-option)
- SQL Server: [Parameter Sensitive Plan optimization](https://learn.microsoft.com/en-us/sql/relational-databases/performance/parameter-sensitivity-plan-optimization)
- Oracle: [CURSOR_SHARING Initialization Parameter](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/CURSOR_SHARING.html)
- Oracle: [Adaptive Cursor Sharing](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/adaptive-cursor-sharing.html)
- Oracle: SIMILAR deprecation note in [Oracle 11.2 New Features Guide](https://docs.oracle.com/cd/E18283_01/server.112/e17128/chapter1.htm)
- PostgreSQL: [SQL-PREPARE](https://www.postgresql.org/docs/current/sql-prepare.html) - plan_cache_mode 描述
- PostgreSQL: [Server Configuration: plan_cache_mode](https://www.postgresql.org/docs/current/runtime-config-query.html#GUC-PLAN-CACHE-MODE)
- DB2: [REOPT Bind Option](https://www.ibm.com/docs/en/db2/11.5?topic=options-reopt-bind-option)
- TiDB: [SQL Plan Cache](https://docs.pingcap.com/tidb/stable/sql-plan-management)
- TiDB: [tidb_enable_non_prepared_plan_cache](https://docs.pingcap.com/tidb/stable/system-variables#tidb_enable_non_prepared_plan_cache-new-in-v600)
- CockroachDB: [Plan Caching](https://www.cockroachlabs.com/docs/stable/cost-based-optimizer)
- OceanBase: [Plan Cache](https://en.oceanbase.com/docs/oceanbase-database/oceanbase-database)
- SAP HANA: [SQL Plan Cache and Parameter Homogenization](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Lahdenmäki, Tapio. "Relational Database Index Design and the Optimizers" (2005)
- Burleson, Donald. "Oracle Tuning: The Definitive Reference" - bind peeking chapter
