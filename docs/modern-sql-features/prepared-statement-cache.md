# 预编译语句与计划缓存 (Prepared Statements and Plan Cache)

每秒处理 10 万次查询的 OLTP 系统，如果每次都要走一遍语法解析、语义分析、查询重写和优化器搜索，CPU 将被编译开销淹没——计划缓存（Plan Cache）正是把"编译一次、执行万次"变成可能的核心机制，也是 OLTP 引擎吞吐量从千 QPS 跃升到十万 QPS 的关键拐点。

## 为什么计划缓存如此重要

一个典型的 SELECT 查询从文本到执行计划要经历五个阶段：词法分析、语法分析、语义分析（catalog 解析、权限检查）、查询重写（视图展开、子查询提升）、查询优化（基于代价的搜索）。在 Oracle 上一个中等复杂度的 OLTP 查询，硬解析（hard parse）耗时常在 1-10 ms，软解析（soft parse，即命中库缓存）耗时在 50-200 us，而一次仅命中索引的执行可能只需要 100 us。这意味着如果不缓存计划，编译开销会比执行开销高出 10-100 倍。

但计划缓存并非"越多越好"。OLTP 场景偏好"编译一次、固化到底"以追求极限吞吐；OLAP 场景则偏好"每次都重新优化"以适应数据分布的变化。两者在同一个引擎中往往需要做艰难的折中——这就是 **bind peeking / parameter sniffing** 问题的根源，也是本文要深入讨论的核心话题。

## SQL 标准定义：SQL:1992 PREPARE / EXECUTE

SQL:1992 标准（ISO/IEC 9075:1992，Section 17）正式引入了动态 SQL 接口，其中包含四条核心语句：

```sql
-- 准备语句：返回一个语句句柄
PREPARE <statement_name> FROM <statement_string>;

-- 描述语句：获取参数和结果列的元数据
DESCRIBE <statement_name> [INPUT | OUTPUT] INTO <descriptor>;

-- 执行语句：传入参数值
EXECUTE <statement_name> [USING <parameter_values>];

-- 释放语句：从命名空间中移除
DEALLOCATE PREPARE <statement_name>;
```

标准的核心语义：

1. **准备阶段做编译**：PREPARE 时完成解析、语义检查、优化，生成可执行计划
2. **执行阶段只填值**：EXECUTE 时仅绑定参数值并执行，不重新优化
3. **生命周期与会话绑定**：标准未规定跨会话共享，事实上各引擎实现差异巨大
4. **参数标记符**：占位符使用 `?`（位置参数）或 `$1, $2`（PostgreSQL 风格）或 `:name`（Oracle 风格）
5. **DESCRIBE 返回元数据**：让客户端可以预先分配缓冲区

需要注意的是，SQL:1992 只规定了 SQL 层面的 PREPARE / EXECUTE 语法。各数据库**协议层**的预编译机制（如 PostgreSQL extended query protocol、MySQL COM_STMT_PREPARE、Oracle OCI bind 接口）是各自实现的扩展，它们与 SQL 层的 PREPARE 是两套独立体系。

## 支持矩阵（综合）

### SQL 层 PREPARE / EXECUTE / DEALLOCATE

| 引擎 | PREPARE | EXECUTE | DEALLOCATE | 参数风格 | 版本 |
|------|---------|---------|------------|---------|------|
| PostgreSQL | 是 | 是 | 是 | `$1, $2` | 早期 |
| MySQL | 是 | 是 | 是 | `?` | 4.1+ |
| MariaDB | 是 | 是 | 是 | `?` | 早期 |
| SQLite | -- | -- | -- | C API only | 仅 API |
| Oracle | -- | -- | -- | OCI / PL/SQL | 仅 API |
| SQL Server | `sp_prepare` | `sp_execute` | `sp_unprepare` | `@p1` | 2000+ |
| DB2 | 是 | 是 | 是 | `?` / `:host` | 早期 |
| Snowflake | -- | -- | -- | 客户端绑定 | -- |
| BigQuery | -- | -- | -- | 客户端参数 | -- |
| Redshift | 是 | 是 | 是 | `$1, $2` | 继承 PG |
| DuckDB | 是 | 是 | 是 | `?` / `$1` | 早期 |
| ClickHouse | -- | -- | -- | 协议参数 | -- |
| Trino | 是 | 是 | 是 | `?` | 早期 |
| Presto | 是 | 是 | 是 | `?` | 早期 |
| Spark SQL | -- | -- | -- | DataFrame API | -- |
| Hive | -- | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | Table API | -- |
| Databricks | 是 | 是 | 是 | `?` | 2024+ |
| Teradata | 是 | 是 | 是 | `?` | 早期 |
| Greenplum | 是 | 是 | 是 | `$1, $2` | 继承 PG |
| CockroachDB | 是 | 是 | 是 | `$1, $2` | 早期 |
| TiDB | 是 | 是 | 是 | `?` | 早期 |
| OceanBase | 是 | 是 | 是 | `?` / `:1` | 早期 |
| YugabyteDB | 是 | 是 | 是 | `$1, $2` | 继承 PG |
| SingleStore | 是 | 是 | 是 | `?` | 早期 |
| Vertica | 是 | 是 | 是 | `?` | 早期 |
| Impala | -- | -- | -- | -- | 不支持 |
| StarRocks | 是 | 是 | 是 | `?` | 2.2+ |
| Doris | 是 | 是 | 是 | `?` | 1.2+ |
| MonetDB | 是 | 是 | 是 | `?` | 早期 |
| CrateDB | -- | -- | -- | 协议层 | -- |
| TimescaleDB | 是 | 是 | 是 | `$1, $2` | 继承 PG |
| QuestDB | -- | -- | -- | 协议层 | -- |
| Exasol | 是 | 是 | 是 | `?` | 早期 |
| SAP HANA | 是 | 是 | 是 | `?` | 早期 |
| Informix | 是 | 是 | 是 | `?` | 早期 |
| Firebird | -- | -- | -- | API only | -- |
| H2 | 是 | 是 | 是 | `?` | 早期 |
| HSQLDB | 是 | 是 | 是 | `?` | 早期 |
| Derby | 是 | 是 | 是 | `?` | 早期 |
| Amazon Athena | -- | -- | -- | -- | 不支持 |
| Azure Synapse | `sp_prepare` | `sp_execute` | `sp_unprepare` | `@p1` | 继承 SQL Server |
| Google Spanner | -- | -- | -- | 客户端参数 | -- |
| Materialize | 是 | 是 | 是 | `$1, $2` | 继承 PG |
| RisingWave | 是 | 是 | 是 | `$1, $2` | 继承 PG |
| InfluxDB (SQL) | -- | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | -- | 不支持 |
| Yellowbrick | 是 | 是 | 是 | `$1, $2` | 继承 PG |
| Firebolt | -- | -- | -- | -- | 不支持 |

> 注: Oracle 不提供 SQL 层的 PREPARE/EXECUTE 语句。Oracle 的预编译完全通过 OCI/JDBC 客户端 API 与库缓存（library cache）实现，与 SQL:1992 标准的 SQL 层语法不同。SQLite 同理，仅有 C API（sqlite3_prepare_v2）。
>
> 统计：约 30+ 引擎提供 SQL 层 PREPARE/EXECUTE，约 15 引擎仅提供协议层或客户端 API 绑定。

### 协议层预编译语句（二进制 vs 文本协议）

| 引擎 | 协议层 PREPARE | 二进制传参 | 文本传参 | 备注 |
|------|----------------|------------|----------|------|
| PostgreSQL | 是 (Extended Query) | 是 | 是 | Parse/Bind/Execute 三阶段 |
| MySQL | 是 (COM_STMT_PREPARE) | 是 | 是 | 二进制协议性能更高 |
| MariaDB | 是 | 是 | 是 | 与 MySQL 兼容 |
| Oracle | 是 (OCI) | 是 | -- | OCI 全二进制 |
| SQL Server | 是 (TDS) | 是 | -- | TDS 协议 RPC 调用 |
| DB2 | 是 (DRDA) | 是 | -- | DRDA 协议 |
| SQLite | 不适用 (嵌入式) | -- | -- | 直接 C API |
| Snowflake | 是 (REST/Arrow) | 是 | -- | HTTP + Arrow IPC |
| BigQuery | 是 (REST) | 是 | -- | REST API 参数化 |
| Redshift | 是 (PG 协议) | 是 | 是 | 继承 PG |
| DuckDB | 不适用 (嵌入式) | 是 | -- | C/Python API |
| ClickHouse | 是 (HTTP/Native) | 是 | 是 | Native 协议二进制 |
| Trino | 是 (HTTP) | -- | 是 | REST，文本协议 |
| Spark SQL | -- | -- | -- | 通过 DataFrame |
| CockroachDB | 是 (PG 协议) | 是 | 是 | 继承 PG |
| TiDB | 是 (MySQL 协议) | 是 | 是 | 继承 MySQL |
| OceanBase | 是 (MySQL/Oracle 双模) | 是 | 是 | 双协议 |
| Vertica | 是 | 是 | -- | 私有协议 |
| SingleStore | 是 (MySQL 协议) | 是 | 是 | -- |
| StarRocks | 是 (MySQL 协议) | 是 | 是 | 2.2+ |
| Doris | 是 (MySQL 协议) | 是 | 是 | 1.2+ |
| Greenplum | 是 (PG 协议) | 是 | 是 | -- |
| YugabyteDB | 是 (PG 协议) | 是 | 是 | -- |

> 二进制协议 vs 文本协议的关键区别在于参数和结果的编码方式。文本协议下整数 12345 传输 5 字节字符串 "12345"，二进制协议下传输 4 字节大端整数。对于高频 OLTP 工作负载，二进制协议可减少 30-50% 的网络字节数和 CPU 编解码开销。

### 自动查询计划缓存（Auto Plan Cache）

| 引擎 | 自动缓存 | 作用域 | 默认开启 | 配置参数 |
|------|---------|--------|---------|---------|
| Oracle | 是 (库缓存) | 全局 | 是 | `shared_pool_size` |
| SQL Server | 是 (Plan Cache) | 全局 | 是 | `max server memory` |
| DB2 | 是 (Package Cache) | 全局 | 是 | `PCKCACHESZ` |
| PostgreSQL | 部分 | 会话级 | 是 | `plan_cache_mode` |
| MySQL | -- | -- | -- | -- (8.0 移除 Query Cache) |
| MariaDB | 部分 (Query Cache) | 全局 | 否 | `query_cache_type` |
| SQLite | 是 (语句缓存) | 连接级 | 是 | `sqlite3_prepare_v2` |
| Snowflake | 内部 (不暴露) | 全局 | 是 | -- |
| BigQuery | 结果缓存 | 全局 (24h) | 是 | -- |
| Redshift | 是 (Result Cache + 编译缓存) | 全局 | 是 | -- |
| DuckDB | -- | 会话级 | -- | -- |
| ClickHouse | Query Cache | 全局 | 否 | `query_cache` (23.6+) |
| Trino | -- | -- | -- | 无计划缓存 |
| Spark SQL | -- | -- | -- | 仅 catalyst 内部缓存 |
| Hive | -- | -- | -- | -- |
| Databricks | Photon Cache + Disk Cache | 全局 | 是 | -- |
| Teradata | 是 (Request Cache) | 全局 | 是 | -- |
| Greenplum | 部分 | 会话级 | 是 | 继承 PG |
| CockroachDB | 是 (分布式) | 全局 | 是 | `sql.query_cache.enabled` |
| TiDB | 是 (Plan Cache) | 会话/全局 | 是 (4.0+) | `tidb_enable_prepared_plan_cache` |
| OceanBase | 是 (Plan Cache) | 全局 | 是 | `ob_plan_cache_percentage` |
| YugabyteDB | 是 | 会话/全局 | 是 | 继承 PG + 改进 |
| SingleStore | 是 | 全局 | 是 | -- |
| Vertica | 是 | 全局 | 是 | -- |
| StarRocks | 是 (SQL Cache + Plan Cache) | 全局 | 是 | -- |
| Doris | 是 (SQL Cache) | 全局 | 是 | -- |
| MonetDB | -- | -- | -- | -- |
| TimescaleDB | 部分 | 会话级 | 是 | 继承 PG |
| Exasol | 是 | 全局 | 是 | -- |
| SAP HANA | 是 (Plan Cache) | 全局 | 是 | `plan_cache_size` |
| Informix | 是 (SQL 语句缓存) | 全局 | 可配 | `STMT_CACHE` |
| H2 | 是 (语句缓存) | 连接级 | 是 | -- |
| HSQLDB | 是 (语句缓存) | 连接级 | 是 | -- |
| Materialize | -- | -- | -- | -- |
| RisingWave | -- | -- | -- | -- |

> 关键观察：**全局共享计划缓存**是商业 OLTP 数据库（Oracle/SQL Server/DB2/SAP HANA）的标配。**会话级计划缓存**是 PostgreSQL 系（PG/Greenplum/Redshift/CockroachDB 较早期版本）的传统做法，因为 PG 的进程模型让跨会话共享变得复杂。新一代分布式 OLTP（TiDB/OceanBase/CockroachDB）则倾向全局缓存。

### 跨会话计划共享

| 引擎 | 跨会话共享 | 共享粒度 | 实现机制 |
|------|------------|---------|---------|
| Oracle | 是 | SQL 文本哈希 | Library Cache (SGA) |
| SQL Server | 是 | SQL 文本哈希 | Plan Cache (Buffer Pool) |
| DB2 | 是 | 包/语句 | Package Cache |
| SAP HANA | 是 | SQL 哈希 | Plan Cache |
| PostgreSQL | 否 (原生) | -- | 进程模型限制 |
| Greenplum | 否 | -- | 继承 PG |
| MySQL | 否 (8.0+) | -- | Query Cache 已移除 |
| TiDB | 是 (v6.1+ Global Plan Cache) | SQL 摘要 | 全局结构 |
| OceanBase | 是 | SQL ID | 全局 Plan Cache |
| CockroachDB | 是 | 节点本地 | 每节点共享 |
| YugabyteDB | 是 (v2.18+) | 节点本地 | 类似 CockroachDB |
| Snowflake | 内部 | -- | 服务端编译缓存 |
| Redshift | 是 | SQL 哈希 | 全局编译缓存 |

### Bind Peeking / Parameter Sniffing

| 引擎 | 支持 bind peeking | 自适应执行 | 参数感知缓存 |
|------|-------------------|------------|---------------|
| Oracle | 是 (9i+) | 是 (11g 自适应游标共享 ACS) | 多版本游标 |
| SQL Server | 是 | 否 (仅 Query Store + AQP) | 单版本计划，可能"中毒" |
| DB2 | 是 (REOPT 选项) | 是 | REOPT ALWAYS/ONCE/NONE |
| PostgreSQL | 是 (custom plan 5 次后切 generic) | 否 | 启发式 |
| MySQL | 否 (始终重新优化) | 否 | -- |
| TiDB | 是 | 部分 | -- |
| OceanBase | 是 | 是 (ACS) | 类似 Oracle |
| SAP HANA | 是 | 是 (Re-optimization) | -- |
| CockroachDB | 是 | -- | -- |

### 计划淘汰策略

| 引擎 | 淘汰算法 | 触发条件 |
|------|---------|---------|
| Oracle | LRU | shared_pool 内存压力 |
| SQL Server | 基于代价的老化（age = exec_count × cost） | 内存压力 |
| DB2 | LRU | PCKCACHESZ 限制 |
| PostgreSQL | 会话结束销毁 | 会话生命周期 |
| TiDB | LRU | 计数限制 (`tidb_prepared_plan_cache_size`) |
| OceanBase | LRU + 内存比例 | `ob_plan_cache_percentage` |
| SAP HANA | LRU | `plan_cache_size` |
| ClickHouse | TTL + LRU | `query_cache_ttl` (23.6+) |
| CockroachDB | LRU | `sql.query_cache.size` |

### 强制计划 / 计划指南 / 提示

| 引擎 | 强制计划 | 计划指南 | Hint 语法 |
|------|---------|----------|-----------|
| Oracle | SQL Plan Baselines | SQL Profiles / Patches | `/*+ INDEX(...) */` |
| SQL Server | Force Plan / Plan Guide | Query Store force plan | `OPTION (FORCE ORDER)` |
| DB2 | Optimization Profile | -- | `/*+ ... */` |
| MySQL | -- | -- | `/*+ INDEX(...) */` (8.0+) |
| PostgreSQL | 否 (核心) | pg_hint_plan 扩展 | 扩展 |
| TiDB | SQL Binding | 是 | `/*+ USE_INDEX(...) */` |
| OceanBase | Outline | 是 | `/*+ ... */` |
| SAP HANA | Plan Stability | 是 | `WITH HINT(...)` |
| Snowflake | -- | -- | -- |
| BigQuery | -- | -- | -- |
| CockroachDB | -- | -- | -- |
| YugabyteDB | pg_hint_plan | 否 | 扩展 |

### DDL 触发的计划失效

| 引擎 | DDL 失效 | 统计信息更新失效 | 视图/函数变更 |
|------|---------|-----------------|---------------|
| Oracle | 是 (硬失效) | 是 (软失效) | 是 |
| SQL Server | 是 | 是 (auto update stats) | 是 |
| PostgreSQL | 是 (catalog 版本号) | 是 (relhastriggers 等) | 是 |
| MySQL | 是 | 是 | 是 |
| DB2 | 是 | 是 | 是 |
| TiDB | 是 (schema 版本) | 是 | 是 |
| OceanBase | 是 | 是 | 是 |
| CockroachDB | 是 | 是 | 是 |
| Snowflake | -- | -- | -- |

### 自适应查询执行 / 重优化

| 引擎 | 运行时重优化 | 自适应连接 | 分区裁剪运行时 |
|------|--------------|-----------|---------------|
| Oracle | 是 (Adaptive Plans 12c+) | 是 | 是 |
| SQL Server | 是 (Adaptive Query Processing 2017+) | 是 (AQP) | 是 |
| Spark SQL | 是 (AQE 3.0+) | 是 | 是 |
| Databricks | 是 | 是 | 是 |
| Trino | 部分 | 否 | 是 |
| Snowflake | 是 (内部) | 是 | 是 |
| BigQuery | 是 (Dynamic Reshuffling) | 是 | 是 |
| Redshift | 部分 | -- | -- |
| TiDB | 部分 | -- | -- |
| ClickHouse | 否 | -- | -- |
| PostgreSQL | 否 | -- | -- |
| MySQL | 否 | -- | -- |

### 查询指纹与摘要

| 引擎 | 指纹算法 | 用途 |
|------|---------|------|
| Oracle | SQL_ID (MD5 截取) | V$SQL 共享 |
| SQL Server | query_hash + plan_hash | DMV 聚合 |
| MySQL | DIGEST (规范化哈希) | Performance Schema |
| TiDB | SQL Digest | Statement Summary |
| OceanBase | SQL ID | -- |
| PostgreSQL | pg_stat_statements queryid | 扩展 |
| CockroachDB | Statement Fingerprint ID | -- |
| Snowflake | query_hash | account_usage |
| BigQuery | query hash | INFORMATION_SCHEMA.JOBS |

## SQL:1992 标准动态 SQL 接口的语义模型

SQL:1992 把动态 SQL 划分为四步生命周期：

```sql
-- 第 1 步: PREPARE - 把查询文本转换成可执行的内部表示
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';

-- 第 2 步: DESCRIBE - 询问输入参数和输出列的元数据
DESCRIBE INPUT  stmt INTO :input_descriptor;
DESCRIBE OUTPUT stmt INTO :output_descriptor;

-- 第 3 步: EXECUTE - 绑定参数值并执行
EXECUTE stmt USING 42;

-- 第 4 步: DEALLOCATE - 释放语句资源
DEALLOCATE PREPARE stmt;
```

标准的关键设计点：

1. **PREPARE 是阻塞操作**：必须在 PREPARE 时就完成所有静态检查，包括对象存在性、列类型、权限。这意味着 PREPARE 时如果引用的表不存在就立即报错。
2. **DESCRIBE 是可选的**：客户端如果已知道参数和列结构（例如通过 ORM 映射），可以跳过 DESCRIBE。
3. **EXECUTE 可重复多次**：同一个语句句柄可以用不同参数执行多次。
4. **DEALLOCATE 是显式的**：标准没有规定隐式释放规则，事实上很多实现会在会话结束时自动释放。
5. **没有规定缓存共享**：标准只说 PREPARE 是会话内可见的。跨会话缓存是各家实现的扩展。

## 各引擎深度解析

### Oracle：Library Cache 与 Bind Peeking

Oracle 的预编译机制不通过 SQL 层的 PREPARE/EXECUTE 暴露，而是构建在 SGA 中的 **Library Cache** 之上。Library Cache 存储所有最近执行过的 SQL 语句、PL/SQL 块、Java 类等，所有会话共享。

```sql
-- 客户端通过 OCI/JDBC 绑定参数，例如 PL/SQL：
DECLARE
    v_id NUMBER := 42;
    v_name VARCHAR2(50);
BEGIN
    -- 静态 SQL：编译期完成绑定
    SELECT name INTO v_name FROM users WHERE id = v_id;
END;
/

-- 动态 SQL（DBMS_SQL 包）：运行期绑定
DECLARE
    cur INTEGER;
    rows_processed INTEGER;
BEGIN
    cur := DBMS_SQL.OPEN_CURSOR;
    DBMS_SQL.PARSE(cur, 'SELECT name FROM users WHERE id = :id', DBMS_SQL.NATIVE);
    DBMS_SQL.BIND_VARIABLE(cur, ':id', 42);
    rows_processed := DBMS_SQL.EXECUTE(cur);
    DBMS_SQL.CLOSE_CURSOR(cur);
END;
/

-- 查看 Library Cache 命中情况
SELECT sql_id, executions, parse_calls, fetches,
       buffer_gets, cpu_time, elapsed_time
FROM v$sql
WHERE sql_text LIKE '%users%';
```

Oracle 的解析分三个层次：
- **Hard Parse（硬解析）**：库缓存未命中，需要走完整的解析、优化流程，开销极大
- **Soft Parse（软解析）**：库缓存命中，但需要重新检查权限、对象有效性
- **Soft Soft Parse（软软解析）**：会话级游标缓存命中，几乎零开销

#### Bind Peeking（绑定变量窥视，9i+）

Oracle 9i 引入 bind peeking：第一次 PREPARE 时，优化器**窥视**绑定变量的实际值，用这个值生成最优计划，然后这个计划被缓存供后续所有执行使用。

```sql
-- 表 orders 有 1000 万行，status 列的分布:
--   'completed' 占 95%, 'pending' 占 4%, 'failed' 占 1%

-- 第一次执行（窥视到 status = 'failed'）
EXECUTE :status := 'failed';
SELECT COUNT(*) FROM orders WHERE status = :status;
-- Oracle 选择: 使用 status 列的索引（因为 'failed' 选择性高）

-- 第二次执行（不重新窥视，复用上面的计划）
EXECUTE :status := 'completed';
SELECT COUNT(*) FROM orders WHERE status = :status;
-- Oracle 仍然使用索引扫描 → 极慢！实际应该全表扫描
```

这就是经典的 **bind peeking 中毒** 问题：第一次执行的参数决定了所有后续执行的计划。

#### Adaptive Cursor Sharing（自适应游标共享，11g+）

Oracle 11g 引入 ACS 解决 bind peeking 中毒。核心思路：**为同一个 SQL 维护多个版本的执行计划**，根据绑定变量值的"等价类"自动选择。

```sql
-- 11g+ 的行为
-- 第一次: status = 'failed' → 计划 A（索引扫描）
EXECUTE :status := 'failed';
SELECT COUNT(*) FROM orders WHERE status = :status;

-- 第二次: status = 'completed' → ACS 监测到行数估计严重偏差
-- → 标记游标为 "bind-sensitive"
EXECUTE :status := 'completed';
SELECT COUNT(*) FROM orders WHERE status = :status;

-- 第三次: ACS 重新优化，生成计划 B（全表扫描）
-- → 现在缓存中有两个计划版本，根据传入值选择
EXECUTE :status := 'completed';
SELECT COUNT(*) FROM orders WHERE status = :status;

-- 查看绑定敏感性
SELECT sql_id, child_number, is_bind_sensitive, is_bind_aware
FROM v$sql WHERE sql_id = '...';
```

ACS 的工作原理：
1. **bind-sensitive**：优化器在编译时根据列直方图判断该 SQL 对参数敏感
2. **bind-aware**：执行时发现实际行数与估计严重偏差，标记为绑定感知
3. **多计划维护**：根据参数选择性的"桶"（selectivity bucket）选择对应的计划版本
4. **自适应学习**：通过 v$sql_cs_histogram、v$sql_cs_selectivity 持续学习

### SQL Server：Plan Cache 与参数嗅探

SQL Server 的 Plan Cache 与 Buffer Pool 共享内存，对所有数据库全局共享。计划查找通过 SQL 文本的哈希进行。

```sql
-- 显式预编译
EXEC sp_prepare @handle OUTPUT,
    N'@id INT',
    N'SELECT * FROM users WHERE id = @id';
EXEC sp_execute @handle, 42;
EXEC sp_unprepare @handle;

-- 自动参数化（Auto-parameterization）：简单语句被自动改写
SELECT * FROM users WHERE id = 42;
-- 内部改写为: SELECT * FROM users WHERE id = @1
-- 仅当查询非常简单且"安全"时才会自动参数化

-- 强制参数化（数据库选项）
ALTER DATABASE mydb SET PARAMETERIZATION FORCED;

-- 查看 Plan Cache
SELECT cp.cacheobjtype, cp.objtype, cp.usecounts, cp.size_in_bytes,
       st.text
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
WHERE st.text LIKE '%users%';
```

#### 参数嗅探（Parameter Sniffing）的"坏计划"问题

SQL Server 的参数嗅探机制与 Oracle 早期 bind peeking 类似：第一次执行时使用传入的参数值估计基数和成本，生成的计划被缓存。SQL Server **没有**类似 Oracle ACS 的自适应游标共享机制（直到 SQL Server 2022 才引入参数敏感计划优化 PSP），因此参数嗅探导致的计划中毒是 DBA 长期面临的痛点。

```sql
-- 表 sales: customer_id 分布严重倾斜
-- VIP 客户 1 有 500 万笔订单，普通客户每人约 100 笔

CREATE PROCEDURE GetSales @cust_id INT
AS
SELECT * FROM sales WHERE customer_id = @cust_id;

-- 第一次调用（传入普通客户）
EXEC GetSales @cust_id = 12345;
-- 嗅探到约 100 行 → 选择 Nested Loop + Index Seek

-- 后续调用（传入 VIP 客户 1）
EXEC GetSales @cust_id = 1;
-- 仍然使用 Nested Loop + Index Seek → 500 万次随机 I/O，灾难性慢
```

#### 缓解参数嗅探的工具箱

```sql
-- 方法 1: OPTION (RECOMPILE) - 每次都重编译
CREATE PROCEDURE GetSales @cust_id INT
AS
SELECT * FROM sales WHERE customer_id = @cust_id
OPTION (RECOMPILE);  -- 每次执行都生成新计划

-- 方法 2: OPTIMIZE FOR - 提示优化器使用特定值
SELECT * FROM sales WHERE customer_id = @cust_id
OPTION (OPTIMIZE FOR (@cust_id = 12345));  -- 始终按"普通客户"优化

-- 方法 3: OPTIMIZE FOR UNKNOWN - 使用列的平均分布
SELECT * FROM sales WHERE customer_id = @cust_id
OPTION (OPTIMIZE FOR UNKNOWN);

-- 方法 4: 局部变量"窃取"
CREATE PROCEDURE GetSales @cust_id INT
AS
DECLARE @local_cust_id INT = @cust_id;  -- 优化器看不到实际值
SELECT * FROM sales WHERE customer_id = @local_cust_id;

-- 方法 5: Query Store 强制好计划
EXEC sp_query_store_force_plan @query_id = 42, @plan_id = 73;

-- 方法 6: SQL Server 2022 的参数敏感计划优化（PSP）
-- 自动为同一查询维护多个计划版本，类似 Oracle ACS
ALTER DATABASE SCOPED CONFIGURATION SET PARAMETER_SENSITIVE_PLAN_OPTIMIZATION = ON;
```

#### Query Store：计划演进的时光机

SQL Server 2016 引入的 Query Store 是计划缓存领域的革命性功能。它持久化记录每个查询的所有历史计划及其性能指标，让 DBA 可以"穿越时空"诊断回归：

```sql
-- 启用 Query Store
ALTER DATABASE mydb SET QUERY_STORE = ON
(
    OPERATION_MODE = READ_WRITE,
    QUERY_CAPTURE_MODE = AUTO,
    MAX_STORAGE_SIZE_MB = 1000
);

-- 找出有计划回归的查询
SELECT q.query_id, qt.query_sql_text,
       p1.plan_id AS old_plan, p1.avg_duration AS old_duration,
       p2.plan_id AS new_plan, p2.avg_duration AS new_duration
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p1 ON q.query_id = p1.query_id
JOIN sys.query_store_plan p2 ON q.query_id = p2.query_id
WHERE p2.avg_duration > p1.avg_duration * 2
  AND p2.last_execution_time > p1.last_execution_time;

-- 强制使用某个历史计划
EXEC sp_query_store_force_plan @query_id, @plan_id;
```

### PostgreSQL：会话级 PREPARE 与 5 次切换的奥秘

PostgreSQL 的预编译机制有一个独特设计：**没有跨会话的全局计划缓存**。这是因为 PG 采用每连接一个进程的架构，进程间共享复杂数据结构成本很高。

```sql
-- SQL 层 PREPARE
PREPARE user_by_id (INT) AS
    SELECT * FROM users WHERE id = $1;

EXECUTE user_by_id(42);
EXECUTE user_by_id(43);

DEALLOCATE user_by_id;

-- 也可以 DEALLOCATE ALL 一次释放所有
DEALLOCATE ALL;

-- 查看当前会话的预编译语句
SELECT name, statement, prepare_time, parameter_types
FROM pg_prepared_statements;
```

#### plan_cache_mode 与 5 次切换启发式

PostgreSQL 对预编译语句使用一个有趣的启发式：**前 5 次执行使用 custom plan（每次重新优化），第 6 次开始切换到 generic plan（参数化的通用计划），如果 generic plan 的成本不显著差于 custom plan**。

```sql
-- 控制参数
SET plan_cache_mode = 'auto';            -- 默认: 5 次后切 generic
SET plan_cache_mode = 'force_custom_plan';   -- 始终重新优化
SET plan_cache_mode = 'force_generic_plan';  -- 始终用通用计划

-- 实验观察
PREPARE q AS SELECT * FROM users WHERE id = $1;

EXPLAIN (ANALYZE) EXECUTE q(1);  -- custom plan
EXPLAIN (ANALYZE) EXECUTE q(2);  -- custom plan
EXPLAIN (ANALYZE) EXECUTE q(3);  -- custom plan
EXPLAIN (ANALYZE) EXECUTE q(4);  -- custom plan
EXPLAIN (ANALYZE) EXECUTE q(5);  -- custom plan
EXPLAIN (ANALYZE) EXECUTE q(6);  -- 评估是否切 generic plan
```

5 次切换的逻辑（src/backend/utils/cache/plancache.c 中的 `choose_custom_plan`）：

```c
/*
 * Cache the custom plans we've seen so far, then compare with generic plan.
 * After 5 custom plans, decide based on average cost comparison.
 */
if (plansource->num_custom_plans < 5)
    return true;  /* 仍然使用 custom plan */

avg_custom_cost = plansource->total_custom_cost / plansource->num_custom_plans;
if (avg_custom_cost < generic_cost - some_threshold)
    return true;  /* custom 显著更便宜，继续 custom */

return false;     /* 切换到 generic plan */
```

#### PG 协议层 vs SQL 层 PREPARE

PostgreSQL 的 Extended Query Protocol 在协议层提供了 Parse/Bind/Execute 三步：

```
Parse:    客户端发送 'SELECT * FROM users WHERE id = $1' → 服务端解析、生成计划
Bind:     客户端发送参数值 (例如 42) → 服务端创建 portal
Execute:  客户端发送执行请求 → 服务端执行 portal
```

这与 SQL 层的 PREPARE/EXECUTE 共享底层缓存，但提供了更细粒度的控制。常见的连接池如 PgBouncer 在 transaction pooling 模式下会**破坏**预编译语句的复用，因为后端连接在事务结束后被回收。

### MySQL：Query Cache 的兴衰与每会话 Prepared

MySQL 的预编译机制经历了一段曲折的历史。

#### Query Cache（5.x）的废除

MySQL 5.0-5.7 提供 Query Cache：缓存完整的查询结果（不是计划），通过 SQL 文本完全匹配查找。当任何被引用的表发生写入时，相关的所有缓存条目都被失效。

```sql
-- 5.7 时代的配置（8.0 已废除）
SET GLOBAL query_cache_type = ON;
SET GLOBAL query_cache_size = 256 * 1024 * 1024;
SHOW STATUS LIKE 'Qcache%';
```

Query Cache 的致命问题：
1. **粗粒度失效**：一张大表的小更新失效所有缓存
2. **全局互斥锁**：多核 CPU 上成为可扩展性杀手
3. **正确性陷阱**：与某些 SQL 函数（NOW(), RAND()）交互复杂
4. **命中率低**：实际生产环境命中率常低于 10%

MySQL 8.0 直接移除 Query Cache 整个特性。这是数据库领域罕见的"否定之否定"：曾经被认为是优化银弹的功能，在十几年后被证明是负资产。

#### Prepared Statements

MySQL 的预编译语句完全是会话级的：

```sql
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
SET @id = 42;
EXECUTE stmt USING @id;
DEALLOCATE PREPARE stmt;

-- MySQL 没有跨会话的计划缓存
-- 每个会话独立维护自己的预编译计划
-- 连接断开后所有 prepared 自动释放
```

MySQL 的优化器（直到 8.0 较新版本）相对简单，对预编译语句也始终重新优化。这意味着：
- 没有 bind peeking 中毒问题（也没有 bind peeking 收益）
- 高频 OLTP 工作负载下编译开销难以分摊
- 连接池（如 ProxySQL）通常需要做语句缓存

### DB2：Package Cache 与 Dynamic SQL Cache

DB2 区分两种 SQL 形式：**静态 SQL**（嵌入在程序中，编译期 BIND 生成 package）和**动态 SQL**（运行期 PREPARE）。两者都通过 Package Cache 共享。

```sql
-- 动态 SQL PREPARE
PREPARE stmt FROM 'SELECT * FROM users WHERE id = ?';
EXECUTE stmt USING 42;

-- 查看 Package Cache
SELECT stmt_text, num_executions, total_cpu_time, num_compilations
FROM TABLE(MON_GET_PKG_CACHE_STMT(NULL, NULL, NULL, -1));

-- REOPT 选项控制 bind peeking 行为
PREPARE stmt FROM 'SELECT * FROM orders WHERE status = ?'
    WITH REOPT ALWAYS;   -- 每次都重新优化
PREPARE stmt FROM 'SELECT * FROM orders WHERE status = ?'
    WITH REOPT ONCE;     -- 第一次执行后用真实值重新优化
PREPARE stmt FROM 'SELECT * FROM orders WHERE status = ?'
    WITH REOPT NONE;     -- 永不重新优化
```

DB2 的 REOPT ONCE 是非常优雅的设计：第一次执行用占位符基数估计，第二次用真实参数重新优化并固化，避免了 ACS 那样的复杂多版本管理。

### ClickHouse：Query Cache（23.6+）的出现

ClickHouse 长期没有任何形式的查询/计划缓存，因为它的目标场景是 OLAP——每次查询的数据范围、谓词不同，缓存命中率天然很低。但 23.6（2023 年 6 月）加入了 **Query Cache**：

```sql
-- 启用查询缓存
SET use_query_cache = 1;

SELECT count() FROM huge_table WHERE date = '2024-01-01';

-- 查看缓存
SELECT * FROM system.query_cache;

-- 配置 TTL 与大小
-- query_cache_size       = 1073741824    (1 GB)
-- query_cache_ttl        = 60            (秒)
-- query_cache_min_query_runs = 0
-- query_cache_min_query_duration = 0
```

ClickHouse Query Cache 的关键特点：
1. **结果级缓存**，不是计划级。命中等于跳过整个查询执行
2. **基于查询文本哈希**，必须完全匹配
3. **TTL 驱动失效**，不监听底层数据变更（用户负责设定合理 TTL）
4. **每用户隔离**，避免权限泄漏
5. **可被显式禁用**：`SETTINGS use_query_cache = 0`

Snowflake、BigQuery 的"结果缓存"在概念上相似，但 ClickHouse 把它做成了用户可控的细粒度功能。

### Snowflake：三层缓存与零计划缓存

Snowflake 的缓存体系有三层：

1. **Result Cache（结果缓存）**：跨 warehouse 的全局缓存，24 小时 TTL，按规范化查询文本哈希。任何用户在任何 warehouse 上执行相同的查询都可命中。底层数据变化会自动失效。
2. **Local Disk Cache**：每个 virtual warehouse 节点上的 SSD 缓存，存储从 S3 拉取的微分区数据
3. **Remote Cache**：S3 上的持久化数据本身

值得注意的是 Snowflake **不暴露**任何计划缓存。每个查询都重新编译，但因为编译发生在云端服务层（Cloud Services Layer），且 Snowflake 内部确实有跨用户的编译缓存，用户感知不到编译开销。

```sql
-- 查看结果缓存命中
SELECT query_id, query_text, total_elapsed_time,
       execution_status, warehouse_name,
       compilation_time, queued_provisioning_time, queued_repair_time,
       queued_overload_time, transaction_blocked_time,
       bytes_scanned, percentage_scanned_from_cache
FROM table(information_schema.query_history())
WHERE query_text LIKE '%mytable%';
```

### BigQuery：缓存查询结果

BigQuery 提供 24 小时的查询结果缓存，与 Snowflake Result Cache 类似：

```sql
-- 配置查询作业禁用缓存
-- 在 API 中设置: configuration.query.useQueryCache = false

-- 查看缓存命中
SELECT job_id, query, cache_hit, total_bytes_processed
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY);
```

BigQuery 的缓存语义：
- **完全相同的查询文本**才命中（包括空白和注释）
- 涉及非确定性函数（CURRENT_TIMESTAMP, RAND）的查询**不会缓存**
- 任何引用的表更新会自动失效缓存
- 缓存命中**不收费**（节省 $$$$ 的关键功能）
- 默认开启，可在作业级别禁用

BigQuery 同样不暴露任何计划缓存机制。

### CockroachDB：分布式预编译与全局计划缓存

CockroachDB 兼容 PostgreSQL 协议，但在计划缓存上做了重要改进：**节点本地的全局共享计划缓存**。

```sql
-- 与 PG 兼容的 PREPARE/EXECUTE
PREPARE q AS SELECT * FROM users WHERE id = $1;
EXECUTE q(42);

-- 查看会话级语句
SHOW PREPARED STATEMENTS;

-- 全局计划缓存配置
SET CLUSTER SETTING sql.query_cache.enabled = true;
SET CLUSTER SETTING sql.query_cache.size = '256MiB';
```

CockroachDB 的设计要点：
1. 每个 SQL 节点维护本地的查询缓存，包含**逻辑计划和物理计划**
2. 缓存键是规范化后的 AST 哈希
3. 支持 placeholder fast path：简单的点查询直接走快速通道，跳过完整的 cost-based optimizer
4. 与 distributed plan 集成：物理计划包括分布式执行的 stage 划分

### TiDB：从无到有的 Plan Cache 演进

TiDB 4.0（2020）首次引入预编译计划缓存。在此之前 TiDB 每次执行都重新优化，限制了 OLTP 吞吐。

```sql
-- 启用预编译计划缓存（4.0+）
SET tidb_enable_prepared_plan_cache = 1;
SET tidb_prepared_plan_cache_size = 1000;

-- 5.1+: 通用计划缓存（非预编译也能命中）
SET tidb_enable_non_prepared_plan_cache = 1;

-- 6.5+: 实例级共享计划缓存
SET GLOBAL tidb_enable_instance_plan_cache = 1;
SET GLOBAL tidb_instance_plan_cache_max_size = '512MiB';

-- SQL Binding（强制计划）
CREATE GLOBAL BINDING FOR
    SELECT * FROM users WHERE id = ?
USING
    SELECT * /*+ USE_INDEX(users, idx_id) */ * FROM users WHERE id = ?;
```

TiDB 计划缓存的演进路线：
- **v4.0**：会话级预编译计划缓存（必须用 `?` 占位符）
- **v5.1**：通用计划缓存（自动参数化，无需显式 PREPARE）
- **v6.1**：改进的非预编译缓存
- **v6.5**：实例级（节点级）共享计划缓存

TiDB 的特殊挑战：分布式执行计划包括 TiKV/TiFlash 的 region 路由信息，region 调度变化时缓存的物理计划可能失效。TiDB 通过 schema version 和 region cache version 双重检查处理。

### OceanBase：双协议下的 Plan Cache

OceanBase 同时支持 MySQL 和 Oracle 协议，其 Plan Cache 设计借鉴了 Oracle 的库缓存概念：

```sql
-- 查看 Plan Cache 状态
SELECT * FROM oceanbase.gv$ob_plan_cache_stat;
SELECT * FROM oceanbase.gv$ob_plan_cache_plan_stat;

-- 配置
ALTER SYSTEM SET ob_plan_cache_percentage = 5;   -- 占租户内存的百分比
ALTER SYSTEM SET ob_plan_cache_evict_interval = '1h';

-- Outline (类似 Oracle SQL Profile)
CREATE OUTLINE ol_idx ON
    SELECT * FROM users WHERE id = ?
USING HINT
    /*+ INDEX(users, idx_id) */;
```

OceanBase 的 Plan Cache 关键设计：
- **租户级隔离**：多租户场景下每个租户独立的 Plan Cache
- **fast parser**：参数化的快速解析路径，跳过完整词法分析
- **ACS 类似机制**：自适应游标共享，根据参数选择性维护多版本计划
- **SQL ID**：类似 Oracle 的 SQL 文本哈希标识

### YugabyteDB：PostgreSQL 兼容 + 改进

YugabyteDB 复用了 PostgreSQL 的查询层代码，因此自然继承了 PG 的 PREPARE/EXECUTE 和 5 次切换 generic plan 的逻辑。但在 v2.18+ 加入了一些重要改进：

```sql
-- PG 兼容的 PREPARE
PREPARE q AS SELECT * FROM users WHERE id = $1;
EXECUTE q(42);

-- YugabyteDB 特有: 加速点查询的 batched nested loop join
SET yb_bnl_batch_size = 1024;
```

YugabyteDB 在分布式场景下做了 region 缓存协调，解决了纯 PG 协议无法处理跨节点路由的问题。

## 关键发现 / Key Findings

1. **SQL:1992 标准的 PREPARE/EXECUTE 普及率约 65%（约 30+/47 引擎）**。Oracle、SQL Server、SQLite、Snowflake、BigQuery 这些主流引擎都没有遵守 SQL 层语法，而是通过协议层或客户端 API 提供等价能力。这是数据库标准与实践脱节最严重的领域之一。

2. **全局共享 Plan Cache 是商业 OLTP 数据库的标配**。Oracle Library Cache、SQL Server Plan Cache、DB2 Package Cache、SAP HANA Plan Cache 都是几十年前就成熟的特性。开源 OLTP 数据库（PostgreSQL、MySQL）反而没有跨会话的计划缓存，这是它们在极致 OLTP 吞吐场景与商业数据库的主要差距之一。

3. **Bind Peeking / Parameter Sniffing 是计划缓存的双刃剑**。它带来了在第一次执行时就用真实值优化的能力，但也带来了"计划中毒"风险。Oracle 通过 ACS（11g+）、SQL Server 通过 PSP（2022+）、DB2 通过 REOPT ONCE 等机制各自尝试解决这个问题。PostgreSQL 的 5 次 custom plan 启发式是一种更轻量的替代方案。

4. **MySQL Query Cache 的兴衰是一个反面教材**。结果级缓存在写多读少、表大事务多的场景下负收益。MySQL 8.0 直接移除整个特性是务实的选择。ClickHouse 在 23.6 谨慎地重新引入 Query Cache，只用于显式启用且 TTL 明确的场景。

5. **PostgreSQL 的 plan_cache_mode = auto + 5 次切换**是优雅的折中。前 5 次用 custom plan 收集统计反馈，之后切换到 generic plan 节省编译开销——前提是 generic 不显著差于 custom。这避免了 bind peeking 中毒，也避免了每次重编译的开销。

6. **云数据仓库（Snowflake/BigQuery/Redshift）不暴露计划缓存**。它们或者在服务层做不可见的编译缓存（Snowflake Cloud Services Layer），或者完全依赖结果缓存（BigQuery 24h cache）。这与 OLAP 的查询模式吻合：每次查询的具体值不同，但相同查询的概率不低。

7. **结果缓存 vs 计划缓存是两个完全不同的层次**。Snowflake/BigQuery 的 24 小时结果缓存优化的是"完全相同的查询第二次执行"；Oracle/SQL Server 的计划缓存优化的是"相同结构的查询用不同参数执行"。前者命中率受查询模式影响巨大，后者是 OLTP 吞吐的基石。

8. **TiDB 的 Plan Cache 演进（4.0 → 6.5）**展示了分布式数据库 OLTP 优化的难度。从无缓存到会话级，再到非预编译缓存、实例级共享缓存，每一步都需要解决 schema 版本、region 路由、参数稳定性等分布式特有问题。

9. **DDL 失效是计划缓存的"硬需求"**。所有主流引擎都在 DDL 时强制失效相关计划（catalog 版本号比对）。但**统计信息更新**触发的失效是软性的（标记为可重优化），各家策略差异较大：Oracle 默认软失效但可强制硬失效，SQL Server 通过 auto update stats 阈值控制。

10. **Query Store（SQL Server 2016+）是计划演进治理的范式**。它持久化记录每个查询的所有历史计划及性能指标，让 DBA 能够看到"何时引入了坏计划"并强制回滚。Oracle 的 SQL Plan Baselines、SQL Profiles、SQL Patches 提供类似但更分散的能力。这种"计划观测性"正在成为新一代分布式数据库（TiDB Statement Summary、CockroachDB Statement Diagnostics）的必备特性。

11. **预编译语句与连接池的交互是常见陷阱**。PgBouncer transaction pooling 模式下后端连接频繁回收，预编译语句无法跨事务复用；MySQL 协议下连接池如 ProxySQL 需要额外的 client-side prepared statement cache 才能让 prepared statement 在连接复用时有意义。这导致很多框架（如 Hibernate）需要主动配置 `useServerPrepStmts` 等选项。

12. **自适应查询执行（AQE）是计划缓存的反面**。Spark SQL AQE（3.0+）、SQL Server AQP（2017+）、Oracle Adaptive Plans（12c+）都在运行时根据实际数据重新决策（join 算法、shuffle 分区数、广播阈值）。OLAP 场景下"运行时自适应"的价值远大于"编译时缓存"，这是 OLAP 引擎普遍不重视计划缓存的根本原因。

13. **查询指纹（Query Fingerprint）是观测性的基石**。Oracle SQL_ID、SQL Server query_hash、MySQL DIGEST、PostgreSQL pg_stat_statements queryid、TiDB SQL Digest 都是同一个理念：把语法结构相同但参数不同的查询归一化为一个标识符，用于性能聚合和告警。规范化算法的差异导致了不同工具间的统计口径不一致。

14. **二进制协议 vs 文本协议在 OLTP 高吞吐下显著影响 CPU 与网络开销**。MySQL 协议对预编译语句使用二进制结果集，PostgreSQL Extended Query 同样支持二进制传参。在每秒数万次小查询的 OLTP 场景下，二进制协议可减少 30-50% 的网络字节和 CPU 编解码成本。

15. **强制计划机制（Plan Baselines / Plan Guides / SQL Bindings）**是生产环境保护性能稳定的最后防线。Oracle SQL Plan Baselines、SQL Server Query Store force plan、TiDB SQL Binding、SAP HANA Plan Stability 都允许 DBA 锁定关键查询的执行计划，避免统计信息更新或版本升级导致的回归。这种"计划治理"能力在金融、电信等关键业务系统中是刚性需求。

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992, Section 17 (Dynamic SQL)
- Oracle: [The Library Cache](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/memory-architecture.html)
- Oracle: [Adaptive Cursor Sharing](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/cursor-sharing.html)
- SQL Server: [Execution Plan Caching and Reuse](https://learn.microsoft.com/en-us/sql/relational-databases/query-processing-architecture-guide)
- SQL Server: [Query Store](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)
- SQL Server: [Parameter Sensitive Plan Optimization](https://learn.microsoft.com/en-us/sql/relational-databases/performance/parameter-sensitivity-plan-optimization)
- PostgreSQL: [PREPARE](https://www.postgresql.org/docs/current/sql-prepare.html)
- PostgreSQL: [plan_cache_mode](https://www.postgresql.org/docs/current/runtime-config-query.html#GUC-PLAN-CACHE-MODE)
- PostgreSQL: [Extended Query Protocol](https://www.postgresql.org/docs/current/protocol-flow.html)
- MySQL: [PREPARE Statement](https://dev.mysql.com/doc/refman/8.0/en/prepare.html)
- MySQL: [Query Cache (5.7 historical)](https://dev.mysql.com/doc/refman/5.7/en/query-cache.html)
- DB2: [Package Cache](https://www.ibm.com/docs/en/db2)
- ClickHouse: [Query Cache](https://clickhouse.com/docs/en/operations/query-cache)
- Snowflake: [Using Persisted Query Results](https://docs.snowflake.com/en/user-guide/querying-persisted-results)
- BigQuery: [Using Cached Query Results](https://cloud.google.com/bigquery/docs/cached-results)
- CockroachDB: [SQL Statement Caching](https://www.cockroachlabs.com/docs/stable/architecture/sql-layer)
- TiDB: [SQL Plan Management](https://docs.pingcap.com/tidb/stable/sql-plan-management)
- TiDB: [Prepared Plan Cache](https://docs.pingcap.com/tidb/stable/sql-prepared-plan-cache)
- OceanBase: [Plan Cache Overview](https://www.oceanbase.com/docs)
- SAP HANA: [SQL Plan Cache](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Graefe, G. "Query Evaluation Techniques for Large Databases" (1993), ACM Computing Surveys
- Bruno, N., Chaudhuri, S. "Constrained Physical Design Tuning" (2008), VLDB
