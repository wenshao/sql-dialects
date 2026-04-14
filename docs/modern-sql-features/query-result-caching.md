# 查询结果缓存 (Query Result Caching)

把一次 SQL 查询的最终结果集直接缓存起来——听上去是一个再自然不过的优化，却是数据库工程史上争议最大的"功能"之一。Snowflake 把它做成了招牌优势，Oracle 在 11g 就引入了 RESULT_CACHE 提示，BigQuery 默认给用户 24 小时的免费查询缓存，而 MySQL 却在 8.0.3 版本彻底删除了内置的 query cache，PostgreSQL 核心团队至今拒绝进入核心。本文系统梳理 45+ 个主流数据库对查询结果缓存的支持情况，并讨论结果缓存为什么既诱人又危险。

> 本文聚焦于**结果缓存 (Result Cache)**——缓存的是查询的最终结果集。与之容易混淆的**计划缓存 (Plan / Prepared Statement Cache)**请参见配套文章 `prepared-statement-cache.md`；后者缓存的是执行计划，并不避免数据扫描。

## 为什么结果缓存充满争议

从用户视角看，结果缓存几乎是"零成本的免费午餐"——同一个查询第二次执行零延迟返回。但从引擎视角看，这是工程上代价最高、陷阱最深的一类优化：

1. **失效 (invalidation) 的正确性**：只要任何一个被查询引用的表有 DML 写入，缓存就必须立刻作废。分布式数据库中，写入与读取可能发生在不同节点，跨节点的缓存失效广播既慢又容易漏。
2. **非确定性函数**：`NOW()`、`CURRENT_USER`、`RAND()`、`UUID()` 等函数让"相同 SQL 同一结果"的前提不再成立；一旦误缓存即语义错误。
3. **权限与行级安全**：在支持 RLS / VPD / CLS 的数据库中，同一条 SQL 在不同用户下应返回不同行。缓存键如果不包含用户上下文，就会泄露数据。
4. **隔离级别**：缓存命中的结果集属于历史某个时间点，它能否满足读到的事务的隔离级别？REPEATABLE READ 还是 READ COMMITTED？
5. **大结果集的内存成本**：把一份几百 MB 的结果集装进共享内存，可能换来"慢 SELECT 挤掉所有真正的热数据"。
6. **写多读少场景的负收益**：DML 频繁时，维护缓存失效的开销远高于缓存命中的收益，MySQL 就栽在了这一点上。
7. **高并发锁**：早期 MySQL query cache 是一把全局 mutex，在 32 核以上机器上成为可观测的瓶颈。

结果缓存的"诱惑"与"风险"形成了一种鲜明的行业分化：
- **决策偏向 Yes**：数据仓库、分析型数据库（Snowflake、BigQuery、Oracle Exadata）——查询重复率高、写入频率低、多租户可按用户隔离。
- **决策偏向 No**：OLTP / HTAP / 核心开源数据库（PostgreSQL、MySQL 8.0+、SQL Server、DuckDB、Trino）——认为应用层缓存或物化视图更合适。

## SQL 标准：不存在

SQL:2023 及之前的标准都**没有**涉及查询结果缓存。它完全属于引擎内部的性能优化，因此各家在以下维度上都可能不同：

- 是否默认启用
- 缓存键是完整 SQL 文本还是标准化 (normalized) 后的 AST/指纹
- 缓存单位是整个查询还是查询的某些子树（中间结果/物化视图）
- 失效策略：DML 触发、TTL、版本号、乐观校验
- 作用域：会话、用户、数据库、集群
- 是否允许客户端持有（如 Oracle OCI Client Result Cache）
- 禁用语法与开关名

本文所有比较都建立在"文档化的、生产可用的"结果缓存能力之上，不包括临时表、查询重写、物化视图等相邻能力。

## 支持矩阵

### 1. 服务器端结果缓存 (Server-side Result Cache)

| 引擎 | 是否支持 | 默认开启 | 引入版本 | 配置/提示 |
|------|---------|---------|---------|----------|
| PostgreSQL | -- | -- | -- | 核心团队明确拒绝 |
| MySQL | 历史有，8.0.3 移除 | 5.x 默认关闭 | 4.0 引入，8.0.3 移除 | `query_cache_type` |
| MariaDB | 是（已不推荐） | 否 | 继承自 MySQL | `query_cache_type=ON` |
| SQLite | -- | -- | -- | 无此概念 |
| Oracle | 是 | 按对象/语句 | 11gR1 (2007) | `RESULT_CACHE_MODE` / `/*+ RESULT_CACHE */` |
| SQL Server | -- | -- | -- | 无正式 result cache |
| DB2 | 部分（MQT 自动匹配） | 否 | LUW 9.7+ | 依赖 MQT |
| Snowflake | 是 | 是 | GA | `USE_CACHED_RESULT` |
| BigQuery | 是 | 是 | GA | `useQueryCache` |
| Redshift | 是 | 是 | GA | `enable_result_cache_for_session` |
| DuckDB | -- | -- | -- | 设计上不需要 |
| ClickHouse | 是 | 否 | 23.6 (2023-06) | `use_query_cache=1` |
| Trino | -- | -- | -- | 只有文件/元数据缓存 |
| Presto | -- | -- | -- | 同 Trino |
| Spark SQL | 部分（`CACHE TABLE`） | 否 | 手动 | `CACHE TABLE` / `cache()` |
| Hive | 是 | 否 | 2.3 (LLAP) | `hive.query.results.cache.enabled` |
| Flink SQL | -- | -- | -- | 流处理无此概念 |
| Databricks | 是（Disk Cache + Result） | 是（SQL Warehouse） | GA | `disable_result_cache` |
| Teradata | 是 | 否 | V2R6+ | Request Cache |
| Greenplum | -- | -- | -- | 继承 PostgreSQL |
| CockroachDB | -- | -- | -- | 无 |
| TiDB | -- | -- | -- | 只有计划缓存 |
| OceanBase | 是 | 否 | 3.x | `_enable_result_cache` |
| YugabyteDB | -- | -- | -- | 无 |
| SingleStore | 是（Result Cache） | 是（S2MS） | 7.5+ | `result_set_cache_size` |
| Vertica | -- | -- | -- | 无（但有 depot） |
| Impala | -- | -- | -- | 无 |
| StarRocks | 是 | 否 | 2.5+ | `enable_query_cache` |
| Doris | 是 | 否 | 1.2+ | `cache_enable_sql_mode` |
| MonetDB | -- | -- | -- | 无 |
| CrateDB | -- | -- | -- | 无 |
| TimescaleDB | -- | -- | -- | 继承 PG |
| QuestDB | -- | -- | -- | 无 |
| Exasol | 是 | 是 | GA | Query Cache |
| SAP HANA | 是 | 否 | 2.0 SPS04 | `RESULT CACHE` 提示 |
| Informix | -- | -- | -- | 只有 SQL 缓存 |
| Firebird | -- | -- | -- | 无 |
| H2 | -- | -- | -- | 无 |
| HSQLDB | -- | -- | -- | 无 |
| Derby | -- | -- | -- | 无 |
| Amazon Athena | 是 | 否 (v3) | 2022+ | `ResultReuseConfiguration` |
| Azure Synapse | 是 | 否 | GA | `RESULT_SET_CACHING ON` |
| Google Spanner | -- | -- | -- | 无 |
| Materialize | 物化（持续增量） | 是 | 核心能力 | 非传统 result cache |
| RisingWave | 物化（持续增量） | 是 | 核心能力 | 非传统 result cache |
| InfluxDB (SQL) | -- | -- | -- | 无 |
| DatabendDB | 是 | 否 | 1.x | `enable_query_result_cache` |
| Yellowbrick | 是 | 否 | GA | Result Cache |
| Firebolt | 是 | 是 | GA | `use_cached_result` |
| Alibaba PolarDB | 是 | 否 | GA | 服务器端 result cache |

> 粗略统计：明确支持 server-side result cache 的引擎约 19 个；明确**不支持**的引擎约 22 个；其余属于"能通过 CACHE TABLE / 物化视图 / 中间结果缓存等临近机制变通"的类别。

### 2. 客户端结果缓存 (Client-side Result Cache)

这是一项少见得多的能力：让客户端驱动在内存中直接保留结果集，并由服务器推送失效通知。

| 引擎 | 是否支持 | 机制 | 备注 |
|------|---------|------|------|
| Oracle | 是 | OCI Client Result Cache | 11gR1+，由 OCI 驱动维护，服务器推送失效 |
| SAP HANA | 部分 | 客户端 LOB 缓存 | 非通用 result cache |
| SQL Server | -- | -- | 仅 ADO.NET 级别的应用缓存 |
| MySQL | -- | -- | 无 |
| PostgreSQL | -- | -- | 无 |
| DB2 | 部分 | CLI / JDBC 缓存 | 有限 |
| Snowflake | -- | -- | Snowflake 的缓存位于云服务层 |
| BigQuery | -- | -- | 服务端 |
| Redshift | -- | -- | 服务端 |
| 其余 40+ 数据库 | -- | -- | 无客户端原生 result cache |

> 行业里真正把"客户端 result cache"做成一等公民的只有 Oracle OCI。其他数据库如果有"客户端缓存"，几乎都是 JDBC / ODBC 的游标/预读缓冲，并非带失效通知的结果缓存。

### 3. 函数级结果缓存 (Function Result Cache)

即在一次查询内（或跨查询）缓存确定性函数/UDF 的返回值，避免对相同输入重复计算。

| 引擎 | 是否支持 | 形式 | 备注 |
|------|---------|------|------|
| Oracle | 是 | PL/SQL Function Result Cache (`RESULT_CACHE`) | 11gR1 引入，针对 PL/SQL 函数 |
| PostgreSQL | 部分 | `IMMUTABLE` + Memoize 节点 | 14+ 的 Memoize 节点对参数化子查询 |
| SQL Server | 部分 | Scalar UDF Inlining (2019+) | 不是缓存而是内联重写 |
| MySQL / MariaDB | -- | -- | 无 |
| DB2 | 是 | `DETERMINISTIC` 函数缓存 | |
| Snowflake | 是 | 对 IMMUTABLE / deterministic UDF 可能复用 | 非文档化保证 |
| BigQuery | 是 | 确定性 SQL UDF 可被结果缓存整体复用 | 间接 |
| DuckDB | 部分 | 查询内常量折叠 | 不是跨查询缓存 |
| ClickHouse | 部分 | Memoization for deterministic functions（有限） | |
| Spark SQL | -- | -- | 依赖 CSE |
| Teradata | -- | -- | |

### 4. 缓存键 (Cache Key) 构成

| 引擎 | 键类型 | 是否含参数绑定 | 是否含会话上下文 |
|------|-------|--------------|----------------|
| Oracle | 规范化 SQL 文本 + 绑定变量 + 环境 | 是 | 是（NLS、优化器参数） |
| Snowflake | 规范化 SQL + 角色 + 会话参数 + 数据版本 | 是 | 是（角色、时区） |
| BigQuery | 规范化查询文本（含项目） | 是 | 是（项目、区域） |
| Redshift | SQL 文本 + 用户 | 是 | 是 |
| MySQL（历史） | 完整 SQL 文本（大小写、空格敏感） | 否 | 弱 |
| MariaDB | 完整 SQL 文本 | 否 | 弱 |
| ClickHouse | 规范化 AST + 用户 + 设置 | 是 | 是 |
| Exasol | 规范化 SQL + 用户 | 是 | 是 |
| Databricks | 规范化 + 集群 + 用户 | 是 | 是 |
| SQL Server | 不适用 | -- | -- |
| PostgreSQL | 不适用 | -- | -- |

> MySQL 的"完整文本"键是其 query cache 劣势的重要来源：`SELECT * FROM t`、`select * from t`、`SELECT * FROM  t`（多一个空格）被视为不同的查询。

### 5. DML 失效行为

| 引擎 | DML 粒度 | DDL 失效 | 跨会话 | 备注 |
|------|---------|---------|-------|------|
| Oracle | 按依赖对象 | 是 | 是 | Result Cache Block 按 dependency 维护 |
| Snowflake | 元数据版本变更 | 是 | 是 | 按 micro-partition 版本校验 |
| BigQuery | 表/视图变更 | 是 | 是 | 任一输入表变化即失效 |
| Redshift | DML 失效 | 是 | 是 | |
| MySQL（历史） | 按表粒度粗失效 | 是 | 是 | 任何写入 → 整表缓存全部作废 |
| MariaDB | 同 MySQL | 是 | 是 | |
| ClickHouse | 按表 UUID + 版本 | 是 | 是 | TTL 为主，DML 失效可选 |
| Databricks | Delta 事务日志版本 | 是 | 是 | |
| Exasol | 表变更 | 是 | 是 | |
| Hive LLAP | 表事件通知 | 是 | 是 | |
| Azure Synapse | 表/列级 | 是 | 是 | 视图/外表有限制 |
| Athena | 手动 TTL | 否（需手动） | 是 | TTL 到期前不自动失效 |
| OceanBase | 按表版本 | 是 | 是 | |
| SAP HANA | 按表版本 | 是 | 是 | |

### 6. TTL / 最大有效期

| 引擎 | 默认 TTL | 可调 | 备注 |
|------|---------|------|------|
| Snowflake | 24 小时 | 可延长至 31 天（通过访问）| 结果被再次访问时刷新 24h 窗口 |
| BigQuery | 24 小时 | 不可调 | 固定 |
| Redshift | 默认无 TTL，依赖 LRU | -- | |
| Oracle | 无强制 TTL，依赖依赖对象失效 | `RESULT_CACHE_MAX_RESULT` 等 | |
| ClickHouse | `query_cache_ttl`，默认 60 秒 | 是 | 偏向"短寿命"策略 |
| MySQL（历史） | 无 TTL，LRU | -- | |
| Athena | `MaxAgeInMinutes` | 是 | 用户显式设置 |
| Exasol | 无 TTL，基于版本 | -- | |
| Azure Synapse | 按内存 LRU | -- | |
| Databricks | 24h（SQL Warehouse）| 可调 | |
| StarRocks | `query_cache_entry_max_bytes` 等 | 是 | |
| Doris | `cache_result_max_row_count` 等 | 是 | |
| OceanBase | `_enable_result_cache` + LRU | 是 | |
| SAP HANA | Hint 级别 TTL | 是 | |

### 7. 绕过 / 禁用语法

各家禁用结果缓存的开关名相当分散，这是排错与基准测试时必查的一项：

| 引擎 | 会话级开关 | 查询级 Hint | 参数名 |
|------|-----------|------------|--------|
| Snowflake | `ALTER SESSION SET USE_CACHED_RESULT=FALSE` | -- | `USE_CACHED_RESULT` |
| BigQuery | -- | `#standardSQL` 作业选项 `useQueryCache=false` | Job config |
| Redshift | `SET enable_result_cache_for_session TO off` | -- | |
| Oracle | `ALTER SESSION SET RESULT_CACHE_MODE=MANUAL` | `/*+ NO_RESULT_CACHE */` | `RESULT_CACHE_MODE` |
| Databricks | `SET use_cached_result = false` | -- | SQL Warehouse |
| ClickHouse | `SET use_query_cache = 0` | `SETTINGS use_query_cache=0` | `use_query_cache` |
| MySQL（历史） | `SET SESSION query_cache_type = OFF` | `SQL_NO_CACHE` | `query_cache_type` |
| MariaDB | 同上 | `SQL_NO_CACHE` | |
| Exasol | `ALTER SESSION SET QUERY_CACHE='OFF'` | -- | |
| Athena | 不启用 `ResultReuseConfiguration` | API 调用层 | |
| Azure Synapse | `SET RESULT_SET_CACHING OFF` (db) | -- | `RESULT_SET_CACHING` |
| SAP HANA | Hint `WITH HINT(NO_RESULT_CACHE)` | 是 | |
| SingleStore | `SET result_set_cache_size=0` | -- | |
| Firebolt | `SET use_cached_result=false` | -- | |
| StarRocks | `SET enable_query_cache=false` | -- | |
| Doris | `SET enable_sql_cache=false` | -- | |
| OceanBase | 会话变量 | Hint | |

### 8. 作用域 (Scope)

| 引擎 | 全局共享 | 按用户 | 按会话 | 按角色/租户 |
|------|---------|-------|-------|-----------|
| Oracle | 是（共享池） | 是 | -- | PDB 级隔离 |
| Snowflake | 是（云服务层） | 按用户 | 按会话 | 是（按角色） |
| BigQuery | 按项目 | 按用户 | -- | 按项目 |
| Redshift | 按集群 | 是 | -- | -- |
| MySQL（历史） | 全局 | -- | -- | -- |
| ClickHouse | 全局 | 是 | 可按会话 | -- |
| Azure Synapse | 按数据库 | 是 | -- | -- |
| Databricks | 按 Warehouse | 是 | -- | -- |
| Exasol | 全局 | 是 | -- | -- |

### 9. 大小限制

| 引擎 | 条目大小上限 | 总大小 |
|------|-----------|-------|
| Oracle | `RESULT_CACHE_MAX_RESULT`（默认 5%）| `RESULT_CACHE_MAX_SIZE`（共享池的一部分）|
| ClickHouse | `query_cache_max_size_in_bytes`、`max_entries` | 是 |
| MySQL（历史） | `query_cache_limit` | `query_cache_size` |
| MariaDB | 同上 | 同上 |
| Snowflake | 由云服务层托管 | 不可调 |
| BigQuery | 10 GB | 不可调 |
| Redshift | LRU | 由 leader 节点内存决定 |
| StarRocks | `query_cache_entry_max_bytes` | `query_cache_size` |
| Doris | `cache_result_max_data_size` | `cache_last_version_interval_second` |
| Exasol | 自动 | 自动 |

## 重点引擎详解

### Oracle：把结果缓存做到工业级

Oracle 在 11gR1 (2007) 引入 Server Result Cache 与 Client Result Cache，是工业界最早把结果缓存做成一等公民的关系数据库之一。

#### Server Result Cache

Oracle Server Result Cache 位于共享池 (Shared Pool) 内，由一组参数控制：

```sql
-- 查看参数
SHOW PARAMETER RESULT_CACHE;
-- RESULT_CACHE_MODE       string  MANUAL
-- RESULT_CACHE_MAX_SIZE   big int 32M
-- RESULT_CACHE_MAX_RESULT integer 5        -- 单条结果最多占用 5%
-- RESULT_CACHE_REMOTE_EXPIRATION integer 0 -- 远程对象有效期(分钟)
```

`RESULT_CACHE_MODE` 有两种取值：

- `MANUAL` (默认)：只有显式使用 `/*+ RESULT_CACHE */` 提示或带 `RESULT_CACHE` 属性的表才缓存
- `FORCE`：对所有未被 `NO_RESULT_CACHE` 排除的查询都尝试缓存

```sql
-- 查询级提示
SELECT /*+ RESULT_CACHE */ department_id, AVG(salary)
  FROM employees
 GROUP BY department_id;

-- 显式禁用
SELECT /*+ NO_RESULT_CACHE */ * FROM employees WHERE emp_id = :1;

-- 表级属性：对该表上的任何查询都尝试结果缓存
ALTER TABLE sales RESULT_CACHE (MODE FORCE);

-- 清空结果缓存
EXEC DBMS_RESULT_CACHE.FLUSH;
```

失效行为：Oracle Result Cache 不是基于 TTL 而是基于**依赖追踪**——Result Cache Block 记录查询依赖的对象，对应对象的 DML 提交后，依赖的缓存条目立即被标记失效。因此 Oracle 的结果缓存一般不会"读到陈旧数据"，但代价是写入路径要支付额外开销。

被拒绝缓存的常见原因包括：

- 包含非确定性函数：`SYSDATE`、`CURRENT_TIMESTAMP`、`SYS_GUID` 等
- 查询 `SEQUENCE.NEXTVAL`
- 引用了系统表 (如 `V$` 动态视图)
- 使用 CURRVAL / LEVEL / ROWNUM（版本相关）
- 引用了带行级 VPD 策略的表且策略涉及会话上下文
- 使用 `SELECT ... FOR UPDATE`

#### Client Result Cache（OCI Client Result Cache）

Oracle 还把结果缓存延伸到了客户端。OCI Client Result Cache 让 OCI / JDBC OCI 驱动在本地进程内缓存结果，服务器负责推送失效通知：

```sql
-- 服务器端启用
ALTER SYSTEM SET CLIENT_RESULT_CACHE_SIZE = 32M SCOPE=SPFILE;
ALTER SYSTEM SET CLIENT_RESULT_CACHE_LAG  = 3000  SCOPE=SPFILE; -- 毫秒
-- 需要重启

-- 表级启用
ALTER TABLE customers RESULT_CACHE (MODE FORCE);
```

客户端与服务器间通过 OCI round-trip 捎带的"变更通知"来使本地缓存失效，`CLIENT_RESULT_CACHE_LAG` 允许用户接受一定时间内的弱一致性（即在 lag 内允许读取尚未收到失效通知的缓存）。

客户端缓存的杀手级场景是**小维度表**：几十行的国家代码表被上千个应用进程反复查询，用了客户端缓存后这些 round-trip 直接消失。

#### PL/SQL Function Result Cache

Oracle 11gR1 还针对 PL/SQL 函数引入了独立的 Function Result Cache：

```sql
CREATE OR REPLACE FUNCTION get_dept_name(p_id NUMBER) RETURN VARCHAR2
  RESULT_CACHE RELIES_ON (departments)
AS
  v_name VARCHAR2(100);
BEGIN
  SELECT dname INTO v_name FROM departments WHERE deptno = p_id;
  RETURN v_name;
END;
```

`RELIES_ON` 子句显式声明依赖的对象（12c 之后可省略，Oracle 会自动推断）；对相同输入参数再调用时直接返回缓存，对 departments 的 DML 会立即使相关条目失效。这是把"Memoization + 依赖失效"做进数据库语言层面的经典案例。

### Snowflake：以 Result Cache 为卖点

Snowflake 把结果缓存做成了用户最显眼的性能卖点之一。它有三层缓存：

1. **Result Cache**（云服务层，24 小时）
2. **Metadata Cache**（云服务层，统计/元数据）
3. **Warehouse Cache / SSD Cache**（虚拟仓库本地 SSD，存储的是列存数据的副本）

这三层经常被混为一谈，但严格来说只有第一层是"查询结果缓存"：

```sql
-- 会话级禁用
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- 再次启用
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
```

Snowflake result cache 的关键特性：

- **24 小时 TTL**：结果自最后一次被访问起 24 小时内有效；每次命中都会刷新窗口；最长可延长到 31 天
- **自动使用**：不需要任何提示，只要查询"哈希一致 + 数据未变 + 权限匹配"
- **跨用户共享**：同账户内、有相同访问权限的不同用户可以命中同一条结果
- **自动失效**：任何引用的表/物化视图发生数据变更（micro-partition 版本变化）都会使相关缓存失效
- **不依赖虚拟仓库**：即便虚拟仓库处于挂起状态，命中 result cache 的查询也能立即返回——这是 Snowflake 把 result cache 放在云服务层而非计算层的重要动机
- **失效的"非典型"触发**：调用 `CURRENT_TIMESTAMP`、`CURRENT_USER`、`IS_ROLE_IN_SESSION` 等依赖会话上下文的函数会让查询无法使用 result cache

#### Result Cache vs Metadata Cache 的区别

许多 Snowflake 用户容易把两者混淆，事实上它们的触发条件完全不同：

- **Metadata Cache**：针对 `SELECT COUNT(*)`、`SELECT MIN/MAX` 等可以仅通过 micro-partition 元数据回答的查询；不需要扫描任何数据文件，也不消耗虚拟仓库时长。它并不依赖"先前执行过同一条 SQL"。
- **Result Cache**：必须先前有人（同账户下的任何有权用户）真实执行过**哈希等价**的 SQL，且底层数据未变，才命中。

当一个 `SELECT COUNT(*) FROM t` 第一次执行就零扫描完成，用户最容易误以为是 result cache 命中；实际是 metadata cache。区分方法：检查 Query Profile 的 "BYTES SCANNED = 0" 与是否有 "RESULT_SCAN" 标记。

### BigQuery：24 小时默认结果缓存

BigQuery 的 query cache 是用户最容易"免费吃到"的功能之一：所有查询默认开启，缓存 24 小时。

```python
from google.cloud import bigquery
client = bigquery.Client()
job_config = bigquery.QueryJobConfig(use_query_cache=False)  # 禁用
client.query("SELECT ...", job_config=job_config)
```

命中 BigQuery query cache 的关键条件：

- 查询必须是**确定性**的（不含 `CURRENT_TIMESTAMP`、`CURRENT_USER`、`RAND`、`SESSION_USER` 等）
- 未引用通配符表、`INFORMATION_SCHEMA`、外部表（连接到 Drive 的表除外且视情况）
- 不包含有副作用的 DML
- 查询字符串（规范化后）与之前的作业完全一致
- 引用的表自上次执行以来未发生修改
- 结果集不能太大（目前 10 GB 以下）
- 调用方有权限读取引用表

**重要计费含义**：命中 cache 的作业**不计费**（$0），这使得 BigQuery 的 query cache 具备强烈的成本动机——经常执行同一个仪表盘查询的团队在一天内只会支付一次扫描费用。

### MySQL：query cache 的"删除记"

MySQL 的 query cache 是整个行业最著名的**反面教材**。它在 4.0 引入，经历十多年演进，最终在 **MySQL 8.0.3 (2017 年 9 月)** 被彻底移除。

#### 早期（4.0 - 5.7）

```sql
-- 5.x 的开关
SET GLOBAL query_cache_type = 1;      -- 0=OFF, 1=ON, 2=DEMAND
SET GLOBAL query_cache_size = 32M;

-- 查询级强制
SELECT SQL_CACHE   * FROM t WHERE id = 1;
SELECT SQL_NO_CACHE * FROM t WHERE id = 1;
```

设计上的"原罪"：

1. **按完整 SQL 文本匹配**：任何大小写、空白差异都会导致 miss；参数化 SQL 的命中率几乎为零
2. **按表粒度粗失效**：对任一表的任何 DML 都会让涉及该表的所有缓存条目作废
3. **全局 mutex**：查询执行完成要写入缓存时要拿全局锁，在多核机器上成为吞吐瓶颈
4. **OLTP 负收益**：写入频繁时，维护失效的开销远大于收益

早在 5.7 (2016) 官方文档中就已经把 query cache 标记为 deprecated，默认关闭。Percona 的基准测试显示在高并发 OLTP 下开启 query cache 反而让 TPS 下降 15%–30%。

#### 8.0.3 的彻底移除

MySQL 8.0.3 (2017 年 9 月) 发布说明里明确写：

> The query cache is now removed. The `query_cache_type`, `query_cache_size`, `query_cache_limit`, `query_cache_min_res_unit`, `query_cache_wlock_invalidate`, and `have_query_cache` system variables have been removed. The `SQL_CACHE` and `SQL_NO_CACHE` SQL modifiers have been removed.

MySQL 团队的理由可以概括为三条：

1. **正确性难以保证**：尤其在复制 (replication) 和 InnoDB 行级锁交互上出现过多次 corner case
2. **收益被应用层缓存抢走**：Memcached/Redis 在应用层早已占领了"热点 SELECT 缓存"的生态位
3. **多核扩展性差**：Query Cache 的架构与现代多核 CPU 已经不匹配

对许多习惯依赖 query cache 的遗留应用，8.0 升级是一次不得不面对的"架构改造"——正确答案是：**把缓存移到应用层**。

### MariaDB：仍然保留但不鼓励

MariaDB 在"分叉"之后没有跟随 MySQL 删除 query cache，至今 10.x / 11.x 仍然保留：

```sql
-- MariaDB 10.5 默认关闭
SET GLOBAL query_cache_type = ON;
SET GLOBAL query_cache_size = 64M;

SELECT SQL_CACHE    * FROM t;
SELECT SQL_NO_CACHE * FROM t;
```

但 MariaDB 官方手册同样明确指出：在高并发写入场景下不要开启；对于只读的小型工作负载仍可能有正收益。MariaDB 的态度是"不删除以免破坏兼容，但也不推荐"。

### SQL Server：没有正式的 result cache

SQL Server 从未提供严格意义上的 result cache。它提供的是：

- **Plan Cache**：缓存已编译的执行计划（见配套文章 `prepared-statement-cache.md`）
- **Buffer Pool**：缓存 8KB 页，影响 I/O 而非结果集
- **Columnstore object pool**：列存段的编码缓冲
- **Scalar UDF Inlining (2019+)**：把标量 UDF 内联到计划中，避免逐行调用的开销，但这是重写不是缓存

实践中，当开发者想要 SQL Server 的"result cache"时，一般会使用以下替代：

```sql
-- 索引视图 (Indexed View)：物化 + 自动维护
CREATE VIEW dbo.vDeptSum WITH SCHEMABINDING AS
SELECT dept, COUNT_BIG(*) AS cnt, SUM(salary) AS total
  FROM dbo.employees
 GROUP BY dept;

CREATE UNIQUE CLUSTERED INDEX IX_vDeptSum ON dbo.vDeptSum(dept);
```

或 `CHECKPOINT` + 临时表 + TempDB 等变通。

### PostgreSQL：刻意不做

PostgreSQL 核心团队对 result cache 的态度是**明确拒绝**。原因在 pgsql-hackers 邮件列表的多次讨论中都有记载，核心论点包括：

1. 失效正确性是 ACID 数据库不能妥协的底线，任何结果缓存都要求做到"写入立即可见"
2. 多版本并发 (MVCC) + 事务可见性让"一条 SQL 的结果"本身就依赖事务 ID，共享缓存的收益被事务隔离吃掉
3. 用户已经可以通过物化视图、FUNCTION `IMMUTABLE` + Memoize、外层应用缓存 (Redis / Memcached) 达成同样效果
4. 内核的"缓存基建"应该投到共享缓冲池、计划缓存、JIT 等更通用的方向

PostgreSQL 14 引入的 **Memoize 节点**有时被误解为"结果缓存"。实际上 Memoize 只缓存**一次查询内部**参数化子查询的结果（即嵌套循环内侧的重复执行），执行完毕即释放，不跨查询，不跨会话：

```sql
-- Memoize 的典型形态：外层 NLJ 扫描 1000 行 customer_id，
-- 内层对每个 customer_id 去查 orders。Memoize 会保留内层
-- 对每个 distinct customer_id 的结果，避免重复扫描。
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id, (SELECT COUNT(*) FROM orders o WHERE o.cid = c.id)
  FROM customers c;
```

PostgreSQL 生态中如果你真的需要 result cache，建议走：
- **Materialized View + `REFRESH MATERIALIZED VIEW CONCURRENTLY`**
- 应用层 `Redis` / `Memcached`
- 扩展 `pg_prewarm`、`pg_buffercache` 调优 buffer pool

### ClickHouse：23.6 引入 query_cache

ClickHouse 社区在 **23.6 (2023 年 6 月)** 引入了服务器端的 query cache：

```sql
-- 启用
SET use_query_cache = 1;
SET query_cache_ttl = 60;       -- 秒
SET query_cache_max_entries = 1024;

-- 查询级
SELECT count() FROM hits
 SETTINGS use_query_cache = 1, query_cache_ttl = 300;
```

ClickHouse 的 query cache 设计明显吸取了 MySQL 的教训：

- **键是规范化 AST**，不是原文，对大小写/空白鲁棒
- **默认关闭**——作为可选能力，而不是默认全局行为
- **以 TTL 为主、DML 失效为辅**——因为典型分析查询即便读到几秒前的数据也可接受
- **条目与总大小都可调**
- **可按用户限制缓存使用**，避免一个"坏查询"把共享缓存吃光

设计原则之一是：对于 ClickHouse 典型的分析工作负载，"秒级陈旧"优于"精确但昂贵的失效"。

### Trino / Presto：不做 result cache

Trino (以及早期 PrestoDB) 有意不做查询结果缓存。Trino 的理由与 PostgreSQL 类似：连接的后端存储（Hive、Iceberg、Delta、RDBMS）版本语义差别巨大，无法给出统一的失效语义；而它能做的是：

- **File metadata cache**：缓存 Parquet/ORC 的 footer 与 row group 统计
- **Hive metastore cache**
- **Rubix / Alluxio**：缓存数据文件本身
- **Client-side 物化视图**：由用户手工写入 Iceberg 物化视图

这种分层思路的本质是："不在查询层缓存结果，在存储/元数据层缓存 I/O"。

### DuckDB：设计上不需要

DuckDB 的核心哲学是"让查询快到不需要 cache"。在嵌入式分析的典型工作负载下，它的列向量化引擎加上本地 NVMe 通常几十毫秒就能完成，结果缓存引入的状态管理、失效开销得不偿失。

DuckDB 的"缓存"只有：

- OS page cache（操作系统层）
- Parquet metadata 缓存
- 会话内常量折叠

若用户确实需要缓存，官方推荐的做法是：把上一次查询结果用 `CREATE TABLE AS` 物化到临时表，由用户自己控制生命周期。

### Databricks / Spark：多层可选

Databricks 在 SQL Warehouse 上提供了服务器端 result cache（默认启用），可用 `SET use_cached_result = false` 禁用。在底层 Spark 上还存在用户显式的 `CACHE TABLE`：

```sql
CACHE TABLE sales_2024 AS SELECT * FROM sales WHERE year = 2024;

-- 持久化级别
CACHE LAZY TABLE sales_2024 OPTIONS ('storageLevel' 'MEMORY_AND_DISK_SER');

-- 清理
UNCACHE TABLE sales_2024;
```

Databricks 还额外叠了一层 **Disk Cache**（读自 cloud storage 的数据文件本地 SSD 缓存），与 result cache 正交。Databricks 的 result cache 以 Delta 事务日志版本为失效依据——在 Delta Lake 上失效粒度天然清晰。

### Hive LLAP 与其他 Hadoop 栈

- **Hive 2.3+**：LLAP 守护进程支持查询结果缓存 `hive.query.results.cache.enabled=true`，基于表事件通知失效
- **Impala**：无 result cache，只有基于 HDFS block 的 data cache
- **Spark SQL**：无原生 result cache，通过 `CACHE TABLE` 手动物化
- **Flink SQL**：流处理语义下"结果缓存"概念不适用

### 新型分析系统

- **StarRocks**：`enable_query_cache`，支持局部（per-tablet）结果缓存，可跨查询复用相同子图的部分结果
- **Doris**：`cache_enable_sql_mode` + `cache_enable_partition_mode` 两种模式，前者 SQL 级缓存，后者按分区缓存（对滚动时间分区的 dashboard 友好）
- **SingleStore**：`result_set_cache_size` 控制结果集缓存
- **Databend**：`enable_query_result_cache` 可选
- **Firebolt**：默认开启结果缓存
- **Yellowbrick**：默认开启
- **Exasol**：默认开启，透明；在内部有"全局查询缓存"
- **Azure Synapse (专用 SQL 池)**：通过 `ALTER DATABASE ... SET RESULT_SET_CACHING ON` 启用，以数据库为粒度
- **Amazon Athena**：v3 开始支持 `ResultReuseConfiguration`，手动指定 `MaxAgeInMinutes`
- **Alibaba PolarDB**：提供服务器端结果缓存，跨 RW/RO 节点可共享

### 持续物化替代方案：Materialize / RisingWave

Materialize 与 RisingWave 代表了一种不同的哲学：**与其缓存结果，不如让结果一直是最新的**。

```sql
-- Materialize 语法
CREATE MATERIALIZED VIEW top_sellers AS
SELECT product_id, SUM(amount)
  FROM orders
 GROUP BY product_id
 ORDER BY 2 DESC LIMIT 10;
```

这类系统把查询注册为物化视图，引擎基于 Differential Dataflow 或流式增量计算保持结果实时可用。从用户体验看，它既提供"查询即刻返回"的缓存式体验，又天然解决了失效问题。它们不属于传统意义的 result cache，但在需求层面与 result cache 高度竞争。

## MySQL Query Cache 的"删除记"

MySQL 的 query cache 是整个数据库行业关于"结果缓存"的最重要案例研究，值得专门回顾。

### 时间线

- **2000 年前后 (MySQL 4.0)**：query cache 首次引入，作为 MySQL 的一项性能卖点
- **2003–2010**：配合 `SELECT SQL_CACHE/SQL_NO_CACHE` 写法在互联网早期 LAMP 栈大量使用
- **2015 年左右**：Percona / MariaDB / Facebook 多个团队陆续发布基准，发现开启 query cache 在高并发下反而拖慢吞吐
- **2016 (MySQL 5.7.20)**：官方正式将 query cache 标记为 deprecated，文档开始引导用户关闭
- **2017 (MySQL 8.0.3, 2017-09)**：query cache **完全移除**，相关系统变量与 SQL 修饰词一并删除
- **2018–今**：MySQL 8.x 的 InnoDB buffer pool + 应用层 Redis 成为事实上的替代方案

### 为什么失败

根本原因不在"缓存"这个概念本身，而在实现细节上踩中了多核时代的几何级放大效应：

1. **全局锁**：query cache 的数据结构由单一 mutex 保护，每次查询完成想写入缓存都要排队
2. **失效粗**：任何 DML 打翻整表的所有缓存项
3. **按文本键**：ORM 生成的高度参数化 SQL 导致几乎每条都是 miss
4. **无 TTL**：缓存项可能存到被驱逐或被失效，但从不"超时主动让位"
5. **OLTP 反收益**：Percona 基准显示，在 sysbench OLTP 写入工作负载下，开启 query cache 使 TPS 下降 15%–40%

经验教训（为后来的 ClickHouse / Oracle / Snowflake 所吸收）：

- **不要以完整 SQL 文本作为 key**
- **不要用全局 mutex**
- **要提供 TTL**
- **要提供按用户的大小/命中上限**
- **默认关闭，由用户显式选择加入**
- **将结果缓存放在事务可见性之上，而不是之下**

## Oracle RESULT_CACHE 深度解析

回到 Oracle，它的 Result Cache 经过 11gR1 → 19c → 23ai 的多轮演进，是目前工业界设计最完整的 server-side result cache，值得单独拆解。

### 三种模式

```sql
-- 1. MANUAL (默认)：只缓存显式标注的查询/表
ALTER SYSTEM SET RESULT_CACHE_MODE = MANUAL;
SELECT /*+ RESULT_CACHE */ ...;

-- 2. FORCE：除了显式 NO_RESULT_CACHE，全部尝试缓存
ALTER SYSTEM SET RESULT_CACHE_MODE = FORCE;
SELECT /*+ NO_RESULT_CACHE */ ...;

-- 3. 表级 MANUAL / FORCE（更细粒度，表属性覆盖系统级）
ALTER TABLE countries RESULT_CACHE (MODE FORCE);
ALTER TABLE countries RESULT_CACHE (MODE DEFAULT);
```

FORCE 模式的"陷阱"：由于 result cache 条目的写入存在短时独占，FORCE 在高并发 OLTP 下可能导致 latch 竞争，Oracle 官方建议仅对"读多写少、结果较小、重复率高"的场景使用 FORCE。

### 关键参数

| 参数 | 默认 | 作用 |
|------|------|------|
| `RESULT_CACHE_MODE` | `MANUAL` | 全局模式 |
| `RESULT_CACHE_MAX_SIZE` | 由共享池派生 | Result Cache 可用总大小 |
| `RESULT_CACHE_MAX_RESULT` | 5 (%) | 单条结果占总大小的上限 |
| `RESULT_CACHE_REMOTE_EXPIRATION` | 0 (分钟) | 引用远端对象的缓存有效期 |

### 诊断视图

```sql
-- Result Cache 内存占用
SELECT * FROM v$result_cache_memory;

-- 每条 cached result 的状态
SELECT id, type, status, name, row_count, scan_count
  FROM v$result_cache_objects
 ORDER BY scan_count DESC;

-- 依赖关系：谁依赖哪些对象
SELECT * FROM v$result_cache_dependency;

-- 统计
SELECT name, value FROM v$result_cache_statistics;
```

"Create Count Success" / "Find Count" / "Invalidation Count" 三个指标一起看，能判断缓存是否真的有收益。如果 Invalidation Count ≈ Create Count，说明缓存寿命过短，FORCE 模式反而是净负收益。

### 不会被缓存的查询

Oracle 文档明确列出了若干"不缓存"的情况：

- 包含 `SYSDATE`、`SYSTIMESTAMP`、`CURRENT_DATE`、`CURRENT_TIMESTAMP`、`LOCAL_TIMESTAMP`
- 调用序列 `.NEXTVAL` / `.CURRVAL`
- 引用 `V$` 固定视图或临时表
- 查询含 `ROWNUM`、`LEVEL`、`PRIOR`（对应层次查询的非确定性）
- 查询使用了 `CURRENT_USER`、`USER`、`USERENV('...')`
- 带 `FOR UPDATE`
- 引用的表启用了行级 VPD/FGAC 且策略依赖会话上下文
- 返回非持久数据类型（如 REF CURSOR）

### 与 PL/SQL Function Result Cache 的协同

PL/SQL function result cache 与 SQL result cache 共享同一块内存池 (Result Cache Memory)，但失效逻辑是独立的。一个典型高价值场景：

```sql
-- 将维度表的查询包装为 PL/SQL 函数，并 RESULT_CACHE RELIES_ON
CREATE OR REPLACE FUNCTION get_country_name(p_code VARCHAR2)
  RETURN VARCHAR2
  RESULT_CACHE RELIES_ON (countries)
AS
  v_name VARCHAR2(100);
BEGIN
  SELECT name INTO v_name FROM countries WHERE code = p_code;
  RETURN v_name;
END;
```

在 ETL 工作流中，这比反复做小表 Hash Join 更优——PL/SQL function result cache 相当于给维度表提供了一条低成本的 "query-free" 访问通道。

## Snowflake 三层缓存再澄清

Snowflake 三层缓存常被初学者混淆，这里给出区分方法：

### 1. Result Cache (云服务层)

- **命中证据**：Query Profile 顶端显示 "QUERY RESULT REUSE"；计费显示 0 credits；不需要 warehouse running
- **命中条件**：规范化后的 SQL 哈希相同 + 底层数据未变 + 权限匹配 + 无非确定性函数
- **TTL**：24 小时（访问时刷新；上限 31 天）
- **作用域**：按账户，按会话角色

### 2. Metadata Cache (云服务层)

- **命中证据**：Query Profile 显示只有 `METADATA-BASED RESULT` 节点；`BYTES SCANNED = 0`；不需要 warehouse running
- **命中条件**：查询可以完全从 micro-partition 元数据回答（`COUNT(*)`、`MIN/MAX`、`SYSTEM$CLUSTERING_INFORMATION` 等）
- 与"是否有先前执行过相同 SQL"无关

### 3. Warehouse Local Cache (虚拟仓库层)

- **命中证据**：Query Profile 显示 `BYTES SCANNED > 0` 但 `% from cache` 接近 100%
- **命中条件**：数据文件已经在当前 warehouse 的 SSD 上；warehouse 挂起后会清空
- 与 SQL 文本无关，只与"数据分片是否在本地 SSD"有关

**常见误判**：

- 用户执行 `SELECT * FROM huge_table LIMIT 10`，第二次很快——这大概率是 **warehouse local cache** 而非 result cache，因为 `LIMIT 10` 不能被 metadata 直接回答（除非有 clustering），而且只要 warehouse 仍在运行就能命中 SSD 缓存
- 测试 benchmark 时不重启 warehouse，会把 warehouse cache 的效果误记到 result cache 上——正确的 benchmark 必须 `ALTER SESSION SET USE_CACHED_RESULT=FALSE` **同时** `ALTER WAREHOUSE ... SUSPEND`

## 关键发现

1. **结果缓存的行业分裂呈两极化**：数据仓库 / 云原生分析数据库普遍默认开启（Snowflake、BigQuery、Redshift、Databricks、Exasol、Firebolt），OLTP / 核心开源数据库几乎全部拒绝（PostgreSQL、MySQL 8.0+、SQL Server、DuckDB、Trino）。分水岭是"写入频率与失效开销的比值"。
2. **失效正确性是所有设计的阿喀琉斯之踵**。Oracle 用精细的依赖追踪换取正确性，Snowflake 用 micro-partition 版本换取正确性，BigQuery 用"表修改时间"换取正确性，而 MySQL 的"整表粗失效"是它最终被删除的核心原因。
3. **MySQL 8.0.3 移除 query cache 是行业转折点**。它把"默认开启 + 完整 SQL 文本 key + 全局 mutex"这套老设计彻底钉死为反模式，后来的 ClickHouse query cache 在几乎所有关键决策上都走了相反方向。
4. **PostgreSQL 的"不做"并非技术上做不到**，而是核心团队判断结果缓存的设计空间不足以让"通用且正确"的实现出现在 core 里；应用层缓存（Redis / Memcached）与物化视图 + Memoize 节点的组合提供了足够替代方案。
5. **Snowflake / BigQuery 把 result cache 做成了"计费优势"**，命中缓存的查询不消耗 warehouse credits 或计费字节——这让 result cache 从"性能优化"升级为"成本优化"，用户动机发生根本变化。
6. **Oracle 是唯一把 client-side result cache 做成工业级的关系数据库**。OCI Client Result Cache 对小维度表的 round-trip 消除效果显著，是 Oracle 在 OLTP 上持续有竞争力的细节设计之一。
7. **Function result cache 是结果缓存的一种更可靠形式**，因为 UDF 的依赖与输入更封闭。Oracle PL/SQL `RESULT_CACHE RELIES_ON` 是典范，DB2 `DETERMINISTIC` 函数缓存和 PostgreSQL 14 Memoize 节点是两种不同角度的实现。
8. **ClickHouse 23.6 的 query cache 是"晚到但正确"的设计**：默认关闭、规范化 key、TTL 为主、可按用户限流——它看上去像是把 MySQL 教训逐条反写而成的。
9. **Materialize / RisingWave 代表了对 result cache 的"釜底抽薪"**：与其缓存过时结果，不如增量维护实时结果。对 dashboard 场景尤其具有颠覆性。
10. **选型建议**：
    - **数据仓库 / BI 仪表盘**：Snowflake、BigQuery、Databricks、Exasol，开箱即用
    - **OLTP + 热维度表**：Oracle Client Result Cache / PolarDB result cache / 应用层 Redis
    - **自托管分析数据库**：ClickHouse query cache，按用户开启 + 设置合理 TTL
    - **PostgreSQL / MySQL 8.0+**：放弃 result cache，走应用层缓存 + 物化视图
    - **流式 + 实时看板**：Materialize / RisingWave，用增量物化替代结果缓存

## 参考资料

- Oracle: [Managing the Server and Client Result Caches](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgdba/tuning-result-cache.html)
- Oracle: [PL/SQL Function Result Cache](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/plsql-subprograms.html#GUID-4328BCC1-2E4A-461F-A5D7-A5E3150335B2)
- Snowflake: [Using Persisted Query Results](https://docs.snowflake.com/en/user-guide/querying-persisted-results)
- Snowflake: [USE_CACHED_RESULT](https://docs.snowflake.com/en/sql-reference/parameters#use-cached-result)
- BigQuery: [Using cached query results](https://cloud.google.com/bigquery/docs/cached-results)
- MySQL 8.0.3 Release Notes: [Query cache removal](https://dev.mysql.com/doc/relnotes/mysql/8.0/en/news-8-0-3.html)
- MariaDB: [Query Cache](https://mariadb.com/kb/en/query-cache/)
- ClickHouse 23.6: [Query Cache](https://clickhouse.com/docs/en/operations/query-cache)
- PostgreSQL: [Memoize node (PG 14 release notes)](https://www.postgresql.org/docs/release/14.0/)
- Amazon Redshift: [Result caching](https://docs.aws.amazon.com/redshift/latest/dg/c_challenges_achieving_high_performance_queries.html)
- Databricks: [Query result cache](https://docs.databricks.com/en/sql/admin/sql-warehouses.html)
- Azure Synapse: [Performance tuning with result set caching](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/performance-tuning-result-set-caching)
- Athena: [Query result reuse](https://docs.aws.amazon.com/athena/latest/ug/reusing-query-results.html)
- SAP HANA: [Result Cache](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- StarRocks: [Query Cache](https://docs.starrocks.io/docs/using_starrocks/query_cache/)
- Apache Doris: [SQL Cache](https://doris.apache.org/docs/query-acceleration/sql-cache/)
- Percona Blog: "MySQL query cache, why it sucks and why you should not use it"
- pgsql-hackers 归档中关于 Result Cache 的多次讨论
