# 服务端预编译语句 (Server-Side Prepared Statements)

一次 `INSERT INTO orders (id, amount) VALUES (?, ?)` 在协议层是怎么走的？是把字面量拼到 SQL 字符串里发过去，还是先发一份"模板"让服务端 Parse、再用单独的 Bind 包送参数值？这两条路径的字节数、CPU、抗注入能力可以差出一个数量级——服务端预编译协议（Parse/Bind/Execute）就是其中"把模板和参数分开"那条路，它定义了 OLTP 数据库与驱动之间最贴近字节的契约。

## 协议层 Parse/Bind/Execute vs 客户端字符串拼接

预编译语句在工程上有两个不同层次：

1. **客户端字符串拼接**（伪预编译）：JDBC/PHP PDO 等驱动把 `?` 替换成转义后的字面量，再以普通查询发送。客户端 API 看起来是 PreparedStatement，但服务端只看到一条完整的 SQL 文本。优点是兼容性好，缺点是无法重用计划，且转义实现错误就成了 SQL 注入入口。
2. **协议层服务端预编译**：客户端通过专门的协议消息把"语句模板"和"参数值"分两次发送。服务端编译一次模板，后续每次 Execute 只送参数。计划复用、参数二进制化、抗注入这三件事都在协议层被原生保证。

本文聚焦后者：**协议级 Parse/Bind/Execute 流程、参数绑定与生命周期管理、自动/显式 Deallocate、连接池中转的相互作用**。它与 `prepared-statement-cache.md`（聚焦优化器计划缓存、bind peeking、跨会话计划共享）是两件事——前者是字节流的契约，后者是优化器的内部状态机。两篇文章互为补充，本文不再讨论 plan cache、bind peeking、SQL hint 等优化器主题。

## 为什么协议层比 SQL 层 PREPARE 更重要

SQL:1992 规定的 `PREPARE name FROM ...; EXECUTE name USING ...` 是 SQL 层语法，每次还要嵌在 SQL 文本里。协议层预编译是一条**独立的字节通道**，下面三件事是 SQL 层 PREPARE 做不到的：

1. **二进制参数**：整数 12345 在文本协议是 5 字节字符串，二进制是 4 字节大端整数；DATE/TIMESTAMP/DECIMAL 节省更多。
2. **空往返与流水线**：协议层可以一个 packet 同时携带 Parse + Bind + Execute + Sync，SQL 层 PREPARE/EXECUTE 必须分两个语句往返。
3. **结果集格式协商**：协议层 Bind 时可以指定每列结果用文本还是二进制返回，SQL 层不可能。

这就是为什么 PostgreSQL JDBC、MySQL Connector/J、psycopg、libpq、go-sql-driver 实际全部跑在协议层 Parse/Bind/Execute 路径上，SQL 层 `PREPARE` 主要被人工查询和某些代理使用。

## 标准定义

### ISO/IEC 9075 SQL/CLI（嵌入式 SQL 与 ODBC 基础）

ISO/IEC 9075-3:2008 定义的 SQL/CLI（Call-Level Interface）是 ODBC 的标准化版本，规定了 C 语言风格的预编译 API：

| API 函数 | 作用 | 对应 ODBC |
|---------|------|----------|
| `SQLPrepare(stmt, sql, len)` | 编译 SQL 文本，返回语句句柄 | `SQLPrepare` |
| `SQLBindParameter(stmt, n, ...)` | 绑定第 n 个参数到变量 | `SQLBindParameter` |
| `SQLExecute(stmt)` | 执行已编译语句 | `SQLExecute` |
| `SQLNumParams(stmt, &count)` | 询问参数数量 | `SQLNumParams` |
| `SQLDescribeParam(stmt, n, ...)` | 询问参数类型 | `SQLDescribeParam` |
| `SQLFreeHandle(stmt)` | 释放语句句柄 | `SQLFreeStmt(SQL_DROP)` |

SQL/CLI 是**API 标准**，不是 wire 标准——它规定了驱动如何对应用暴露预编译能力，但不规定字节如何打到网络上。每个驱动把 SQLPrepare 翻译成各自数据库的私有 wire 协议。

### JDBC PreparedStatement（JSR 221）

`java.sql.PreparedStatement` 接口是 Java 标准的预编译抽象，定义了 setInt/setString/setNull/setBlob 等 setter 与 executeQuery/executeUpdate/addBatch。它继承自 SQL/CLI 的设计哲学：参数从 1 开始编号，不带名字，默认按顺序绑定。

### 协议层标准的缺位

与 wire 协议本身一样，**没有跨厂商的协议层预编译标准**。Apache Arrow Flight SQL（2022+）的 `CommandPreparedStatementQuery` 是新兴的事实标准，但目前只有 Doris、InfluxDB IOx、Dremio 等少数引擎采用。主流引擎都使用各自的私有协议消息。

## 支持矩阵（综合）

### 服务端协议级 Parse/Bind/Execute 协议消息

| 引擎 | 协议层消息 | 二进制参数 | 二进制结果 | 命名/匿名语句 | 版本 |
|------|------------|-----------|-----------|---------------|------|
| PostgreSQL | Parse/Bind/Execute (Extended Query) | 是 | 是（按列协商） | 都支持 | 7.4 (2003)+ |
| MySQL | COM_STMT_PREPARE/EXECUTE | 是 | 是 | 仅匿名（int ID） | 4.1 (2004)+ |
| MariaDB | 同 MySQL + COM_STMT_BULK_EXECUTE | 是 | 是 | 仅匿名 | 早期；BULK 10.2+ |
| SQL Server | TDS RPC: sp_prepare/sp_execute/sp_executesql | 是 | 是 | 句柄整数 | 2000+ |
| Oracle | OCI bind/define + Net 协议 | 是 | 是 | 句柄 | 早期 |
| DB2 | DRDA PRPSQLSTT/EXCSQLSTT | 是 | 是 | 区段（section） | 早期 |
| SQLite | C API: sqlite3_prepare_v2/bind/step | 是（嵌入式） | 是（嵌入式） | API 句柄 | 3.0+ |
| ClickHouse Native | ClientInfo + parameterized SETTINGS | 部分 | 是 | 否（按 query 文本） | 22.3+（参数化）|
| ClickHouse HTTP | HTTP query params + `param_name=value` | 部分 | 是 | 否 | 22.3+（参数化）|
| Snowflake | REST `/queries/v1/query-request` 带 bindings | 是 | 是 (Arrow) | 否 | 早期 GA |
| BigQuery | gRPC/REST `JobService.InsertJob` 带 queryParameters | 是 | 是 | 否 | GA |
| Redshift | PG Extended Query | 是 | 是 | 都支持 | 继承 PG |
| DuckDB | C/Python API: duckdb_prepare/bind/execute | 是 | 是 | API 句柄 | 早期 |
| Trino | HTTP `/v1/statement` + PREPARE/EXECUTE | -- | -- | 命名 (HTTP header) | 早期 |
| Presto | 同 Trino | -- | -- | 命名 (HTTP header) | 0.80+ |
| Spark SQL | HiveServer2 ExecuteStatement + parameters | 部分 | -- | 操作句柄 | 3.4+（参数化）|
| Hive | HiveServer2 ExecuteStatement | -- | -- | 操作句柄 | 不原生支持参数 |
| Flink SQL | SQL Gateway HTTP / JDBC | -- | -- | -- | 受限 |
| Databricks | Statement Execution API + parameters | 是 | 是 (Arrow) | 否 | 2024+ |
| Teradata | CLIv2 PCL / TDP Prepare/Execute | 是 | 是 | 句柄 | 早期 |
| Greenplum | PG Extended Query | 是 | 是 | 都支持 | 继承 PG |
| CockroachDB | PG Extended Query | 是 | 是 | 都支持 | 继承 PG |
| TiDB | COM_STMT_PREPARE/EXECUTE | 是 | 是 | 仅匿名 | 继承 MySQL |
| OceanBase | MySQL + Oracle 双协议 | 是 | 是 | 双模 | 早期 |
| YugabyteDB (YSQL) | PG Extended Query | 是 | 是 | 都支持 | 继承 PG |
| YugabyteDB (YCQL) | CQL PREPARE/EXECUTE 帧 | 是 | 是 | MD5 ID | 继承 Cassandra |
| SingleStore | COM_STMT_PREPARE/EXECUTE | 是 | 是 | 仅匿名 | 早期 |
| Vertica | 私有协议（类 PG）Parse/Bind/Execute | 是 | 是 | 都支持 | 早期 |
| Impala | HiveServer2 + Beeswax | -- | -- | 操作句柄 | 受限 |
| StarRocks | COM_STMT_PREPARE/EXECUTE | 是 | 是 | 仅匿名 | 2.2+ |
| Doris | COM_STMT_PREPARE/EXECUTE + Flight SQL | 是 | 是 | 仅匿名 / 命名 | 1.2+ |
| MonetDB | MAPI prepare 响应 | 部分 | 是 | 整数 ID | 早期 |
| CrateDB | PG Extended Query | 是 | 是 | 都支持 | 继承 PG |
| TimescaleDB | PG Extended Query | 是 | 是 | 都支持 | 继承 PG |
| QuestDB | PG Extended Query (子集) | 部分 | 部分 | 都支持 | 部分 |
| Exasol | WebSocket prepare/executePreparedStatement JSON 帧 | 是 | 是 | 整数句柄 | 早期 |
| SAP HANA | SQLDBC PREPARE/EXECUTE 二进制段 | 是 | 是 | 句柄 | 早期 |
| Informix | SQLI 协议 PREPARE | 是 | 是 | 命名 | 早期 |
| Firebird | XDR op_prepare_statement/op_execute | 是 | 是 | 整数 ID | 早期 |
| H2 | TCP 私有协议 | 是 | 是 | ID | 早期 |
| HSQLDB | HSQLDB 私有协议 | 是 | 是 | ID | 早期 |
| Derby | DRDA PRPSQLSTT/EXCSQLSTT | 是 | 是 | 区段 | 早期 |
| Amazon Athena | REST API `StartQueryExecution` + executionParameters | 是 | 是 | 否 | 2022+ |
| Azure Synapse | TDS sp_prepare | 是 | 是 | 句柄 | 继承 SQL Server |
| Google Spanner | gRPC ExecuteSql + params | 是 | 是 | 否 | GA |
| Materialize | PG Extended Query | 是 | 是 | 都支持 | 继承 PG |
| RisingWave | PG Extended Query | 是 | 是 | 都支持 | 继承 PG |
| InfluxDB (IOx) | Arrow Flight SQL CommandPreparedStatementQuery | 是 | 是 (Arrow) | 句柄 | 3.x |
| Databend | MySQL COM_STMT_PREPARE + Flight SQL | 是 | 是 | 仅匿名 / 句柄 | GA |
| Yellowbrick | PG Extended Query | 是 | 是 | 都支持 | 继承 PG |
| Firebolt | REST API + queryParameters | 部分 | -- | 否 | GA |

> 关键观察：约 35+ 引擎实现了原生协议级预编译；ClickHouse/Snowflake/BigQuery/Trino/Athena 等"分析型"引擎仅在协议或 REST 层支持参数化查询，缺乏可重用的服务端语句句柄。Spark/Hive/Flink 的 SQL 层因起源于批处理，对协议层预编译支持较弱。

### SQL 层 PREPARE / EXECUTE / DEALLOCATE 语法

| 引擎 | SQL 层语法 | 占位符 | 与协议层语句共享命名空间 |
|------|------------|-------|-------------------------|
| PostgreSQL | `PREPARE/EXECUTE/DEALLOCATE` | `$1, $2` | 是（同会话同名空间） |
| MySQL | `PREPARE/EXECUTE/DEALLOCATE` | `?` | 否（独立命名空间） |
| MariaDB | 同 MySQL | `?` | 否 |
| SQL Server | `sp_prepare/sp_execute/sp_unprepare` | `@p1` | 句柄整数空间 |
| Oracle | -- (仅 OCI / PL/SQL) | `:1` / `:name` | 仅 OCI |
| DB2 | `PREPARE/EXECUTE/DEALLOCATE` | `?` / `:host` | 是 |
| SQLite | -- (仅 C API) | `?` / `?NNN` / `:name` / `@name` / `$name` | 仅 API |
| Redshift | `PREPARE/EXECUTE/DEALLOCATE` | `$1` | 是（继承 PG） |
| DuckDB | `PREPARE/EXECUTE/DEALLOCATE` | `?` / `$1` | 是 |
| ClickHouse | -- | -- | -- |
| Snowflake | -- | -- | -- |
| BigQuery | -- | `@param` (脚本) | -- |
| Trino | `PREPARE/EXECUTE/DEALLOCATE PREPARE` | `?` | 通过 HTTP header 共享 |
| Presto | 同 Trino | `?` | 同 Trino |
| Spark SQL | 部分 (3.4+ 仅 EXECUTE IMMEDIATE) | `?` / `:param` | -- |
| Hive | -- | -- | -- |
| Databricks | `EXECUTE IMMEDIATE` | `:name` / `?` | -- |
| Teradata | `USING (...) AS DATA` (BTEQ 风格) | `?` | -- |
| Greenplum | 同 PG | `$1` | 是 |
| CockroachDB | 同 PG | `$1` | 是 |
| TiDB | 同 MySQL | `?` | 否 |
| OceanBase | 同 MySQL/Oracle | `?` / `:1` | 否 |
| YugabyteDB | 同 PG | `$1` | 是 |
| SingleStore | 同 MySQL | `?` | 否 |
| Vertica | `PREPARE/EXECUTE/DEALLOCATE` | `?` / `:1` | 是 |
| StarRocks | 同 MySQL | `?` | 否 |
| Doris | 同 MySQL | `?` | 否 |
| MonetDB | `PREPARE/EXECUTE/DEALLOCATE PREPARE` | `?` | 是 |
| Materialize | 同 PG | `$1` | 是 |
| RisingWave | 同 PG | `$1` | 是 |
| Exasol | `PREPARE/EXECUTE` | `?` | -- |
| SAP HANA | -- (仅 SQLDBC) | `?` / `:name` | 仅 API |
| Informix | `PREPARE/EXECUTE/DECLARE/FREE` | `?` | -- |
| Firebird | -- (仅 API) | `?` | 仅 API |
| H2 | `PREPARE/EXECUTE/DEALLOCATE` | `?` | 是 |
| HSQLDB | `PREPARE/EXECUTE` | `?` | 是 |
| Derby | -- (仅 JDBC) | `?` | 仅 API |
| Athena | -- (仅 REST API) | `?` | -- |

### 命名 (Named) vs 匿名 (Unnamed) 预编译语句

PostgreSQL Extended Query 协议同时支持两种语句：**命名**（有字符串 ID，跨多次 Bind/Execute 持久存在直到 Sync 结束事务或显式 Close）与**匿名**（空字符串 ID，新的 Parse 自动覆盖前一个）。这是协议层设计的关键分歧：

| 引擎 | 命名 | 匿名 | 默认风格 |
|------|------|------|----------|
| PostgreSQL | 是（任意字符串） | 是（空字符串） | 驱动选择，JDBC 默认匿名→命名升级 |
| MySQL | 否（仅 4 字节 stmt_id） | -- | int ID 即"匿名"句柄 |
| Oracle | 句柄（实际是命名） | -- | OCI 默认按句柄 |
| SQL Server | 句柄（int） | sp_executesql 即"匿名" | sp_prepare → 句柄 |
| DB2 | 句柄 + 区段 | -- | -- |
| YugabyteDB | 是 | 是 | 同 PG |
| CockroachDB | 是 | 是 | 同 PG |
| Trino | 命名（HTTP header） | -- | 仅命名 |

> **关键点**：PostgreSQL 的"匿名语句"是协议优化用——驱动想发"一次性参数化查询"时不付出命名管理成本。一旦下一条 Parse 出现，前一个匿名计划就被丢弃，无需 Deallocate。这是 PG JDBC `prepareThreshold=0` 时的默认路径。

### 自动 Deallocate / 生命周期管理

| 引擎 | 会话结束自动释放 | 事务结束自动释放 | DDL 自动失效 | 显式 DEALLOCATE | DISCARD ALL |
|------|-----------------|-----------------|--------------|-----------------|-------------|
| PostgreSQL | 是 | 否（命名）/ 是（匿名 Sync 后） | 是（catalog 版本号） | 是 | 是 (`DISCARD PLANS`) |
| MySQL | 是 | 否 | 是（schema 版本） | 是 (`COM_STMT_CLOSE`) | 是 (`RESET CONNECTION`) |
| MariaDB | 是 | 否 | 是 | 是 | 是 |
| SQL Server | 是 | 否 | 是（句柄失效） | `sp_unprepare` | `DBCC FREEPROCCACHE` |
| Oracle | 是（库缓存例外） | 否 | 是 | OCIStmtRelease | `ALTER SYSTEM FLUSH SHARED_POOL` |
| DB2 | 是 | 否 | 是 | 是 | -- |
| SQLite | 是（连接关闭） | 否 | 是 | `sqlite3_finalize` | -- |
| Redshift | 是 | 否 | 是 | 是 | 是 |
| DuckDB | 是 | -- | 是 | 是 | -- |
| ClickHouse | -- | -- | -- | -- | -- |
| Trino | -- | 查询结束 | -- | 是 | -- |
| CockroachDB | 是 | 否 | 是 | 是 | 是 |
| TiDB | 是 | 否 | 是 | 是 | -- |
| OceanBase | 是 | 否 | 是 | 是 | -- |
| YugabyteDB | 是 | 否 | 是 | 是 | 是 |
| SingleStore | 是 | 否 | 是 | 是 | -- |
| Vertica | 是 | 否 | 是 | 是 | -- |
| Materialize | 是 | -- | 是 | 是 | -- |

### 单会话最大预编译语句数 / 内存上限

| 引擎 | 单会话上限 | 全局上限 | 配置参数 |
|------|-----------|---------|---------|
| PostgreSQL | 无显式上限（受 work_mem/会话内存约束） | -- | -- |
| MySQL | `max_prepared_stmt_count` 默认 16382 | 全局共享 | `max_prepared_stmt_count` |
| MariaDB | 默认 16382 | 全局 | `max_prepared_stmt_count` |
| SQL Server | 32767（句柄空间） | 受 plan cache 内存控制 | `max server memory` |
| Oracle | 受 PGA/库缓存约束 | -- | `pga_aggregate_target` |
| DB2 | 受 PCKCACHESZ 约束 | 全局 | `PCKCACHESZ` |
| SQLite | 受连接内存约束 | -- | -- |
| Redshift | 无显式上限 | -- | -- |
| ClickHouse | -- | -- | -- |
| CockroachDB | 默认 100MB / 会话 | -- | `sql.session.prepared_statements.max_size` |
| TiDB | 默认 0（不限） | 全局 | `max_prepared_stmt_count` |
| OceanBase | 默认 16382 | 全局 | `max_prepared_stmt_count` |
| YugabyteDB | 同 PG | -- | -- |
| SingleStore | 默认 65535 | 全局 | -- |

> MySQL 默认 16382 是历史遗留：协议中 `stmt_id` 是 4 字节无符号整数，理论上 ~42 亿，但服务端为防止应用泄漏内存设置了软上限。生产环境用 ORM 时常常被打爆，需调到 1M 以上。

### 协议消息编号速览

| 协议 | 准备消息 | 绑定消息 | 执行消息 | 关闭消息 |
|------|---------|---------|---------|---------|
| PostgreSQL v3 | `Parse` (P, 0x50) | `Bind` (B, 0x42) | `Execute` (E, 0x45) | `Close` (C, 0x43) |
| MySQL 4.1+ | `COM_STMT_PREPARE` (0x16) | `COM_STMT_SEND_LONG_DATA` (0x18) + Execute 内绑定 | `COM_STMT_EXECUTE` (0x17) | `COM_STMT_CLOSE` (0x19) |
| MariaDB | 同 MySQL + `COM_STMT_BULK_EXECUTE` (0xfa) | 同 MySQL | 同 MySQL + BULK | 同 MySQL |
| TDS | RPC `sp_prepare` (procid 11) | RPC 参数列表 | RPC `sp_execute` (procid 12) | RPC `sp_unprepare` (procid 15) |
| DRDA | `PRPSQLSTT` (0x200D) | `OPNQRY/EXCSQLSTT` SQLDA | `EXCSQLSTT` (0x200A) | `RDBCMM` (释放) |
| Cassandra Native | PREPARE 帧 (opcode 0x09) | -- | EXECUTE 帧 (opcode 0x0A) | -- (TTL 失效) |
| Arrow Flight SQL | `ActionCreatePreparedStatementRequest` | `Schema` 中的 parameters | `getStream` + `FlightSqlClient.executeUpdate` | `ActionClosePreparedStatementRequest` |

## 各引擎深入

### PostgreSQL：Frontend/Backend 协议的 Parse/Bind/Describe/Execute 五步法

PostgreSQL Extended Query 协议自 7.4 (2003) 起作为 Simple Query (Q 消息) 的高性能替代品引入。它把一次查询拆成 5+1 步：

```
Frontend → Backend                  Backend → Frontend
Parse     (P stmt_name, sql, types)
                                    ParseComplete  (1)
Bind      (B portal, stmt, formats, values, result_formats)
                                    BindComplete   (2)
Describe  (D 'P' portal | 'S' stmt) -- 可选
                                    RowDescription | NoData | ParameterDescription
Execute   (E portal, max_rows)
                                    DataRow * N | CommandComplete
Sync      (S)
                                    ReadyForQuery
```

**关键设计**：

1. **语句 (statement) 与门户 (portal) 解耦**：一个 Parse 出来的命名语句可以被多次 Bind 成不同 portal，每个 portal 是"参数已绑、可被 Execute"的可执行实例。这让"同一查询，不同参数"的 OLTP 模式天然高效。
2. **格式协商按列粒度**：Bind 消息有两个 format 数组，分别指定**每个参数**的输入格式（文本/二进制）和**每个返回列**的输出格式。驱动可以让某些参数走文本（兼容性）而某些列走二进制（性能）。
3. **Sync 是事务边界**：Sync 之后服务端进入 ReadyForQuery，事务隐式结束（除非已开 BEGIN）。Parse/Bind/Execute 之间出现错误，服务端会"跳过"剩余消息直到下一个 Sync——这是协议层的故障恢复机制。
4. **类型 OID 显式传递**：Parse 消息可以选择性地为每个参数指定 OID 类型；不传则服务端从查询上下文推断（有时会推断错误，比如 `WHERE id = $1` 中 id 是 bigint 时）。

```
-- 文本协议 SQL 层等价（功能子集）
PREPARE my_query (int, text) AS
    SELECT id, amount FROM orders WHERE user_id = $1 AND status = $2;

EXECUTE my_query (42, 'paid');

DEALLOCATE my_query;
```

**生命周期细节**：

- 命名语句活到会话结束，或显式 `Close 'S' stmt_name` / `DEALLOCATE`，或 `DISCARD PLANS` / `DISCARD ALL`。
- 匿名语句（空 stmt_name）活到下一次 Parse 出现，或 Sync 出现且未携带 Bind/Execute 引用它。
- DDL 修改 catalog 后会更新版本号，下一次 Execute 命中失效语句时会报 `ERROR: cached plan must not change result type` 或自动重新规划（取决于 PG 版本）。

**libpq 接口对应**：

| 函数 | 对应协议消息 |
|------|------------|
| `PQprepare(conn, stmt_name, query, nParams, paramTypes)` | Parse |
| `PQexecPrepared(conn, stmt_name, ..., paramFormats, resultFormat)` | Bind + Describe + Execute + Sync |
| `PQsendPrepare` / `PQsendQueryPrepared` | 异步版 |
| `PQdescribePrepared(conn, stmt_name)` | Describe 'S' |
| `PQclosePrepared(conn, stmt_name)` (libpq 17+) | Close 'S' |

PG JDBC 的 `prepareThreshold` 控制升级路径：默认 5，意味着同一 PreparedStatement 第 5 次执行才使用命名语句，前 4 次用匿名。这是为了让短生命周期连接不在服务端积累命名语句。

```
PG JDBC 升级流程:
  执行 1-4: 匿名 Parse + Bind + Execute + Sync   (每次都重新 parse)
  执行 5+:  命名 Parse 一次, 之后只 Bind + Execute + Sync
```

### MySQL：COM_STMT_PREPARE 二进制协议（4.1+，2004）

MySQL 4.1 引入了二进制协议（也称扩展协议），是 PG Extended Query 的精神兄弟，但设计风格非常不同：

```
Client → Server                                  Server → Client
COM_STMT_PREPARE (0x16) + sql_text
                                                 OK 包: stmt_id (4B), num_columns, num_params, warnings
                                                 ColumnDefinition * num_params  (如果 num_params > 0)
                                                 EOF / OK
                                                 ColumnDefinition * num_columns (如果 num_columns > 0)
                                                 EOF / OK
COM_STMT_EXECUTE (0x17) + stmt_id +
    flags + iteration_count(=1) +
    null_bitmap + new_params_bound_flag +
    [type_codes] + parameter_values_binary
                                                 ColumnDefinition * num_columns
                                                 ResultRow (binary) * N
                                                 EOF / OK
COM_STMT_CLOSE (0x19) + stmt_id
                                                 (无响应)
```

**关键差异（vs PG）**：

1. **匿名语句不存在**：MySQL 协议中只有"通过 stmt_id 引用"一种方式。stmt_id 是服务端分配的 4 字节整数，对客户端透明。
2. **没有独立的 Bind 消息**：参数值在 `COM_STMT_EXECUTE` 包内联。也就是说每次执行都重新发送参数，没有 PG 那种"一次 Bind 多次 Execute"的可能。
3. **`new_params_bound_flag` 优化**：第二次开始可以省略 type_codes 数组（如果类型不变），节约几个字节。
4. **二进制结果集格式独立**：PREPARE 出来的语句执行时强制返回二进制结果（无需协商）。这与 PG 的"按列协商"是相反的设计选择。
5. **`COM_STMT_RESET` (0x1a)**：清除 send_long_data 累积的大对象参数缓冲区。
6. **`COM_STMT_SEND_LONG_DATA` (0x18)**：分块发送 BLOB/TEXT 参数值，避免单包过大。

**SQL 层 PREPARE / EXECUTE**（与协议层独立）：

```
SET @id = 42;
SET @status = 'paid';
PREPARE my_query FROM 'SELECT id, amount FROM orders WHERE user_id = ? AND status = ?';
EXECUTE my_query USING @id, @status;
DEALLOCATE PREPARE my_query;
```

注意 SQL 层使用用户变量 `@var` 作为参数容器；协议层直接送二进制值。两者命名空间完全独立——`PREPARE my_query FROM '...'` 不会让协议层的 `COM_STMT_PREPARE` 看到 `my_query` 这个名字。

**MariaDB 扩展：COM_STMT_BULK_EXECUTE (0xfa)**

MariaDB 10.2 引入了批量执行命令，允许一次性发送多组参数：

```
COM_STMT_BULK_EXECUTE 消息体:
  stmt_id           (4B)
  bulk_flag         (2B): 携带 SEND_TYPES_TO_SERVER / SEND_UNIT_RESULTS
  type_codes        (per-param)
  values_set_1, values_set_2, ..., values_set_N
```

服务端按组应用，整体 OK 或错误。INSERT 批量插入场景比 N 次 COM_STMT_EXECUTE 节约 (N-1) 次往返。MySQL 没有此命令，但应用层可以用 `INSERT ... VALUES (?,?), (?,?), (?,?)` 模拟。

### SQL Server：sp_prepare / sp_execute / sp_executesql 三种 RPC

SQL Server 不在 TDS 协议层定义专门的 PREPARE 消息，而是把它做成系统存储过程，通过 RPC 调用。这是 TDS 一以贯之的"任何动作都是 RPC"哲学。

| 系统存储过程 | 用途 | 是否可重用 |
|-------------|------|----------|
| `sp_prepare @handle OUTPUT, '@p1 int', 'SELECT ... WHERE id = @p1'` | 编译并返回句柄 | 句柄持久 |
| `sp_execute @handle, value1, ...` | 用句柄执行 | 是 |
| `sp_unprepare @handle` | 释放句柄 | -- |
| `sp_executesql 'SELECT ... WHERE id = @p1', '@p1 int', value1` | 一次性"匿名"参数化执行 | 服务端自动缓存 |
| `sp_prepexec @handle OUTPUT, '@p1 int', '...', value1` | prepare + execute 合并 | 句柄持久 |

**ADO.NET 默认行为**：第一次执行时使用 `sp_executesql`（依赖服务端自动参数化与计划缓存），如果同一命令对象多次执行，驱动可能切换到 `sp_prepexec`/`sp_execute`（控制 by `Prepare()` 调用）。这是 PG JDBC `prepareThreshold` 的 SQL Server 翻版。

**RPC 包结构**（TDS 7.4+，简化）：

```
RPC Header (Token 0xE0 / RPC stream)
  ProcID = 11 (sp_prepare)
  Options
  Parameters:
    @1: handle (int, OUTPUT direction)
    @2: declaration string ('@p1 int, @p2 nvarchar(50)')
    @3: SQL statement (nvarchar)
    @4: options (smallint)
```

执行时（procid=12 sp_execute）的参数列表只送 handle 和实际值，不再送 SQL 文本。

### Oracle：OCI 与 Net8 的 bind/define 模型

Oracle 客户端接口 (OCI) 把一次预编译查询分成 4 个阶段：

| OCI 函数 | 协议消息 (Net8) | 作用 |
|----------|----------------|------|
| `OCIStmtPrepare2(svc, &stmt, sql, ...)` | OPI Prepare (kpoprp) | 解析、规划，返回语句句柄 |
| `OCIBindByPos / OCIBindByName(stmt, ...)` | -- (本地缓冲注册) | 把客户端缓冲区绑到参数槽位 |
| `OCIDefineByPos(stmt, ...)` | -- (本地) | 把客户端缓冲区绑到结果列 |
| `OCIStmtExecute(svc, stmt, iters, ...)` | OPI Execute (kpoexe) | 实际网络往返；可一次执行 N 次（数组绑定） |
| `OCIStmtFetch2(stmt, ...)` | OPI Fetch (kpofch) | 拉取行 |
| `OCIStmtRelease(stmt, ...)` | -- (本地，回到库缓存) | 归还句柄 |

**与其他数据库最大的不同点**：

1. **数组绑定**：`OCIBindByPos` 可以把整个 C 数组绑定到参数，`OCIStmtExecute` 的 `iters` 参数指定执行多少次。这等同于"一次 Execute 完成 N 行 INSERT"，在 OCI 之外几乎找不到等价物（MariaDB BULK 是后辈）。
2. **句柄"还回库缓存"语义**：`OCIStmtRelease` 不真正销毁，而是把语句标记为可被其他会话复用。库缓存（library cache）是全局共享的——这与 PG/MySQL 的"语句句柄属于会话"截然不同。
3. **没有协议级"匿名"概念**：所有语句都通过句柄。但客户端可以把句柄立即 Release 回库缓存达到类似匿名的效果。
4. **隐式准备**：JDBC `Statement` 在 Oracle 也走 prepare 路径——Oracle 的设计是"任何 SQL 都先 prepare 再 execute"，没有"直接执行"通道。

### ClickHouse：参数化查询而非真正的服务端 Prepared

ClickHouse 直到 22.3 (2022) 才引入参数化查询，且**没有协议层的可重用语句句柄**——每次查询仍要发送完整的 SQL 模板，只是参数值通过专门的协议字段传递：

```
HTTP 接口（22.3+）:
POST /?query=SELECT+id+FROM+events+WHERE+user_id={user_id:UInt64}+AND+date={date:Date}
     &param_user_id=12345
     &param_date=2024-01-01

Native 协议 (TCP 9000):
ClientInfo 中携带 query_parameters 字段
SQL 文本中使用 {name:Type} 占位符
```

**与传统 prepared statement 的区别**：

| 维度 | ClickHouse 参数化 | 传统协议预编译 |
|------|-------------------|---------------|
| 是否可重用编译结果 | 否（每次重发 SQL） | 是（句柄复用） |
| 是否减少 SQL 文本传输 | 否 | 是 |
| 是否抗 SQL 注入 | 是（参数与文本分离） | 是 |
| 是否减少解析时间 | 否（每次都解析） | 是 |
| 类型在客户端还是服务端 | 模板里显式标注 | 服务端 OID 推断 |

ClickHouse 的设计哲学是"每次查询独立"——OLAP 工作负载下查询很少重复，因此协议层的可重用 prepared 价值不高；但参数化能挡住 SQL 注入并支持类型化绑定，这是 22.x 之前完全缺失的。

```
SELECT * FROM events
WHERE user_id = {uid:UInt64}
  AND event_date BETWEEN {start:Date} AND {end:Date}
SETTINGS param_uid='12345', param_start='2024-01-01', param_end='2024-01-31';
```

### CockroachDB：继承 PG 协议，但分布式语义有差异

CockroachDB 完整实现了 PostgreSQL Extended Query（Parse/Bind/Describe/Execute），客户端无须修改。但分布式语义带来几个细节差异：

1. **每节点本地计划缓存**：客户端命中的网关节点缓存 prepared 语句。如果会话因网络异常重连到另一节点，原 prepared 语句不可用——驱动需要做重 Parse。
2. **`server.session.prepared_statements.max_size`**：单会话所有 prepared 语句总字节上限，超限服务端拒绝新 Parse。
3. **DDL 影响**：CRDB 的 schema 变更是版本化的，DDL 后下一次 Execute 会触发自动重 Parse，对客户端透明（PG 是显式失败）。
4. **匿名语句优化**：与 PG 一致，匿名 Parse 不进入计划缓存路径。

### TiDB：MySQL 协议 + 全局 Plan Cache

TiDB 的协议层完全是 MySQL：`COM_STMT_PREPARE/EXECUTE/CLOSE`。但内部 plan cache 是全局的（`tidb_enable_prepared_plan_cache=on`），相同 SQL 文本（按摘要）的不同会话可以复用同一执行计划——这是与原生 MySQL 最大的内部差异，但对协议层透明。

`tidb_prepared_plan_cache_size` 控制单会话缓存的语句数（默认 100），超限走 LRU 淘汰，不影响 `max_prepared_stmt_count`（4 字节句柄空间）。

### SQLite：嵌入式的 sqlite3_prepare_v2

SQLite 没有 wire 协议，prepared 完全在 C API 内：

```c
sqlite3_stmt *stmt;
int rc = sqlite3_prepare_v2(db,
    "SELECT id, amount FROM orders WHERE user_id = ? AND status = ?",
    -1,        // sql 字符串长度，-1 表示零结尾
    &stmt,     // 输出语句句柄
    NULL);     // 输出剩余 SQL（用于多语句 SQL）

sqlite3_bind_int(stmt, 1, 42);
sqlite3_bind_text(stmt, 2, "paid", -1, SQLITE_STATIC);

while (sqlite3_step(stmt) == SQLITE_ROW) {
    int id = sqlite3_column_int(stmt, 0);
    double amount = sqlite3_column_double(stmt, 1);
    /* ... */
}

sqlite3_reset(stmt);     // 重置游标，保留绑定
sqlite3_clear_bindings(stmt);  // 可选：清空参数
sqlite3_finalize(stmt);  // 释放
```

**v2 vs 原 v1 的差异**：`sqlite3_prepare_v2` 会保留 SQL 文本副本，让 `sqlite3_step` 在 schema 变更后能自动重 prepare。原 v1 (`sqlite3_prepare`) 不保留，schema 变更后步进直接报错。**生产代码必须用 v2**。

`sqlite3_prepare_v3` (3.20+) 增加了 prepFlags（如 `SQLITE_PREPARE_PERSISTENT` 提示长期持有，`SQLITE_PREPARE_NO_VTAB` 禁用虚表），但语义与 v2 相同。

### YugabyteDB / Greenplum / Materialize / RisingWave / CrateDB：PG 协议系

这些引擎都实现了 PG Extended Query，客户端零修改。差异在内部计划缓存与 DDL 失效语义：

- **YugabyteDB**：YSQL 接口完整 PG，YCQL 接口走 Cassandra Native（PREPARE 帧返回 16 字节 MD5 ID）。
- **Greenplum**：基于 PG 8.4 fork，协议完全兼容；prepared 在 segment 间分布执行，但客户端只与 master 交互。
- **Materialize / RisingWave**：流式数据库，Parse 出来的语句被注册为持续视图的查询模板；Execute 时返回当前快照。
- **CrateDB**：PG 协议子集，部分 PG 类型（如 record/range）不支持 Bind。

### Trino / Presto：HTTP-based "prepared" 通过 header 携带

Trino 的 prepared 语句不在协议层（HTTP 是无状态的），而是把语句文本作为 HTTP request header `X-Trino-Prepared-Statement` 携带：

```
POST /v1/statement
X-Trino-Prepared-Statement: my_query=SELECT id FROM orders WHERE user_id = ?
X-Trino-User: alice
Content-Type: text/plain

EXECUTE my_query USING 42
```

服务端把 header 中的 `my_query` 注册到会话，后续在请求体中执行 `EXECUTE my_query USING ...`。释放通过 SQL 层 `DEALLOCATE PREPARE my_query`。

参数总是文本传输（HTTP 字符流），无法二进制化。这是 Trino 协议本质决定的——HTTP/JSON 不支持二进制参数。

## PG Frontend/Backend 协议 Parse/Bind/Describe/Execute 深度

### Parse 消息格式

```
Parse (P, 0x50):
  字节 0:    'P'                                    -- 消息类型
  字节 1-4:  Int32 message_length                   -- 含 length 自身但不含 'P'
  字符串:   stmt_name (零结尾, 空字符串=匿名)
  字符串:   query (零结尾, SQL 文本)
  Int16:    num_param_types                         -- 显式指定的参数 OID 数量
  Int32 *:  parameter_type_oid * num_param_types    -- 0 表示让服务端推断
```

**实操要点**：
- `num_param_types` 不必等于实际参数数量；剩余参数让服务端推断。
- 显式 OID 来自 PG `pg_type.oid`（如 23 = int4，1043 = varchar）。
- 同一 stmt_name 的二次 Parse 必须先 Close，否则服务端报 `42P05: prepared statement "..." already exists`。

### Bind 消息格式

```
Bind (B, 0x42):
  'B' + length
  字符串:   portal_name (零结尾, 空字符串=匿名 portal)
  字符串:   stmt_name
  Int16:    num_param_format_codes
  Int16 *:  format_codes (0=text, 1=binary)         -- 0 个表示全部文本; 1 个表示全部该格式
  Int16:    num_param_values
  对参数 i:
    Int32:  value_length (-1 表示 NULL)
    字节:  raw_value (按上面 format_code 解释)
  Int16:    num_result_format_codes
  Int16 *:  result_format_codes                     -- 同样的简化语义
```

**关键点**：format_codes 数组**长度可以是 0、1 或 num_params**。0 表示全部文本；1 表示所有参数用同一格式；其他表示按列指定。这种设计在网络字节上做了智能优化。

### Describe 消息格式

```
Describe (D, 0x44):
  'D' + length
  Byte:     'S' (语句) | 'P' (portal)
  字符串:  name
```

服务端响应：
- `'S'`：先返回 `ParameterDescription` (类型 OID 列表) 再返回 `RowDescription`/`NoData`。
- `'P'`：只返回 `RowDescription`/`NoData`（参数已在 Bind 时具体化）。

JDBC/psycopg 在 Parse + Bind 后自动 Describe 一次以获取列元数据，从第二次执行开始可省略 Describe（驱动缓存）。

### Execute 消息格式

```
Execute (E, 0x45):
  'E' + length
  字符串:  portal_name
  Int32:    max_rows (0 表示不限)
```

**`max_rows` 与游标行为**：传 N 时服务端返回最多 N 行后发送 `PortalSuspended`；后续 Execute 同一 portal 继续。这是**协议层游标**——比 SQL 层 `DECLARE CURSOR` 更轻量，被 JDBC `setFetchSize(N)` 使用。

### Sync 与流水线

```
Sync (S, 0x53):  (无消息体)
```

Sync 之前可以连续发送多个 Parse/Bind/Execute。错误时服务端"跳过"剩余消息直到 Sync，然后回复 ReadyForQuery。这就是协议层的**pipelining**。

JDBC `addBatch()` + `executeBatch()`：内部多次 Bind+Execute，最后一个 Sync——节约 (N-1) 次往返。但单次错误会让整批失败回到 Sync。

### 二进制参数格式举例

```
int4 (OID 23):
  text:    "12345"           -- 5 字节
  binary:  0x00 00 30 39     -- 4 字节大端

timestamp (OID 1114):
  text:    "2024-01-15 12:34:56.789"
  binary:  Int64 (microseconds since 2000-01-01 00:00:00 UTC)

uuid (OID 2950):
  text:    "550e8400-e29b-41d4-a716-446655440000"  -- 36 字节
  binary:  16 字节

numeric (OID 1700):
  text:    "12345.67890"
  binary:  复杂结构（NumericVar：digits[], weight, sign, dscale）
```

DECIMAL/NUMERIC 是个反例——文本协议反而更简单。这就是为什么 PG JDBC 默认对 numeric 走文本，对 int/float/uuid/timestamp 走二进制。

## MySQL 二进制协议 vs 文本协议

### 文本协议（COM_QUERY, 0x03）

```
Client → Server:
  COM_QUERY + "SELECT id, amount FROM orders WHERE user_id = 42 AND status = 'paid'"

Server → Client:
  ColumnCount packet
  ColumnDefinition * N
  EOF
  ResultRow (text) * M:
    每个字段: length-encoded string of textual representation
  EOF / OK
```

整数 12345 占 5 字节字符串，浮点 3.14 占 4+ 字节字符串。结果行的所有字段都是字符串——客户端必须 `parseInt`/`parseDouble`。

### 二进制协议（COM_STMT_EXECUTE, 0x17）

```
Server → Client (准备阶段已建立 stmt_id 与 num_columns):
  ColumnDefinition * N (与文本协议相同)
  EOF
  Binary ResultRow * M:
    Byte 0: 0x00 (固定包头)
    NULL bitmap: ceil((num_columns + 7 + 2) / 8) 字节
    Field 1, 2, ...: 二进制编码（按 ColumnDefinition.type）
  EOF / OK
```

二进制字段编码（部分）：

| 类型 | 文本 | 二进制 |
|------|------|--------|
| TINYINT | 1-4 字节字符串 | 1 字节 |
| SMALLINT | 1-6 字节字符串 | 2 字节 |
| INT | 1-11 字节字符串 | 4 字节 |
| BIGINT | 1-20 字节字符串 | 8 字节 |
| FLOAT | 字符串 | 4 字节 IEEE 754 |
| DOUBLE | 字符串 | 8 字节 IEEE 754 |
| DATE | "YYYY-MM-DD" (10 字节) | 4-5 字节 (length-prefixed) |
| TIMESTAMP | "YYYY-MM-DD HH:MM:SS.uuuuuu" (26 字节) | 7-11 字节 |
| VARCHAR | length-prefix + UTF-8 | length-prefix + UTF-8（与文本相同）|

### 何时差距最大

OLTP 大量小查询，结果集是 1-10 行 × 5-20 个数值列：二进制协议节约 30-50% 网络字节、20-40% 客户端 CPU（无需 parse 数字字符串）。

OLAP 大量字符串列：差距很小（VARCHAR 编码相同），二进制协议没有显著收益。

**JDBC `useServerPrepStmts` 与 `cachePrepStmts`**：
- `useServerPrepStmts=true`：实际发送 COM_STMT_PREPARE，走二进制协议。
- `cachePrepStmts=true`：客户端缓存 stmt_id，重复执行省去 PREPARE 往返。
- 默认两者都是 false——MySQL Connector/J 历史上把 PreparedStatement 退化成客户端字符串拼接。要让协议层预编译生效必须显式打开。

## 连接池与代理：协议级预编译的隐藏成本

### PgBouncer transaction mode 的破窗

PgBouncer 1.21（2023-10）之前的版本在 **transaction pooling mode** 下完全无法支持协议层 prepared statements——这是社区使用 PG 协议预编译时最大的隐藏陷阱。

| PgBouncer 池模式 | 协议层 prepared 是否可用 | 1.21 之前 | 1.21+ |
|-----------------|-------------------------|----------|-------|
| Session pooling | 是 | 是（但客户端独占整条连接，损失池化收益） | 是 |
| Transaction pooling | 看版本 | **否**（语句句柄归属错乱） | 是（协议层透明 PREPARE 镜像） |
| Statement pooling | 否 | 否 | 否 |

**1.21 之前为什么不行**：transaction pooling 的语义是"事务结束就归还连接到池中"，而协议层的命名 prepared 语句**寄生在物理连接的会话状态里**。客户端 A 在物理连接 X 上 Parse 了 `stmt1`，事务提交，物理连接 X 被回到池中，客户端 B 拿到 X 在自己的会话中 Execute `stmt1`——服务端的 stmt1 是 A 的语句，B 会得到 `42P05: prepared statement "stmt1" does not exist`（如果 B 之前没有自己 Parse 过）或者执行错误的 SQL。

**1.21 解决方案**：PgBouncer 在协议层透明地为每个客户端维护 prepared statement 镜像。当客户端 A 发送 Parse(stmt1, sql)，PgBouncer 拦截并记录；事务结束物理连接归还时不真正在服务端 `DEALLOCATE`；下次客户端 A 取到不同的物理连接 Y 时，PgBouncer 在 Y 上 replay Parse(stmt1)（一次性透明开销）。

```
配置参数 (pgbouncer.ini):
  max_prepared_statements = 100   -- 每客户端最多镜像数, 0 = 禁用此功能
```

**实际影响**：1.21 之前生产环境通常的解决方法：
1. 切换到 session pooling（损失主要的池化收益）。
2. 关闭客户端的服务端 prepare（PG JDBC `prepareThreshold=0`，实际退化成每次发完整 SQL）。
3. 改用其他池化器：Odyssey（Yandex）、PgCat（CockroachDB）较早支持。

### MySQL 代理（ProxySQL / MaxScale / Vitess）

MySQL 协议层 prepared 在代理中同样棘手——`stmt_id` 是服务端分配的，代理无法保证客户端拿到的 stmt_id 与下次连接到的物理后端的 stmt_id 一致。各代理的应对：

| 代理 | 服务端预编译支持 | 实现方式 |
|------|------------------|---------|
| ProxySQL | 是（默认开启） | 维护 client_stmt_id ↔ backend_stmt_id 映射；切换连接时透明 re-PREPARE |
| MaxScale | 是 | 类似 ProxySQL，使用 PS routing 模式 |
| Vitess (vtgate) | 部分 | VTGate 重写参数化查询作为执行计划路由的一部分 |
| ShardingSphere | 是 | 协议层重写，每个分片独立 prepare |

### 透明性的代价

代理层做 prepared statement 镜像不是免费的：

1. **首次执行延迟**：物理连接切换时透明 re-PREPARE 增加一次往返。
2. **内存占用**：代理需为每客户端维护语句文本副本。`max_prepared_statements=100` × 每语句平均 2KB × 客户端数 = 内存上限。
3. **错误处理复杂**：物理连接上 PREPARE 失败时代理需把错误转发给客户端，且确保下次切换不会重复发送同样会失败的 Parse。
4. **协议特性缺失**：不是所有协议层特性都能完整 mirror。比如 PG 的 `Describe 'S'` 返回 `ParameterDescription`，代理在 re-PREPARE 时可能无法重现某些特殊的类型推断结果。

## YCQL / Cassandra Native：第三种范式

Cassandra 系（包括 YugabyteDB YCQL）的 PREPARE 协议有独特设计：

```
Frame Header:
  version, flags, stream_id, opcode (0x09 = PREPARE)
  body_length

PREPARE Body:
  long string: query text

Response Frame:
  opcode 0x08 = RESULT
  Body:
    result_kind = 4 (Prepared)
    short_bytes id          -- 16 字节 MD5 of query text
    Metadata (input column specs)
    Result Metadata (output column specs)
```

**关键点**：
- 语句 ID 是查询文本的 MD5（确定性的），客户端知道 ID 就可以直接 EXECUTE，无需先与本节点 PREPARE。
- 节点间通过 `system.prepared_statements` 表共享，重连后无需 re-PREPARE。
- 生命周期由集群 TTL 控制（默认 24 小时不使用就回收），客户端必须做"EXECUTE 失败时重 PREPARE"的容错。

```
EXECUTE Frame (opcode 0x0A):
  short_bytes id
  short value_count
  bytes value * count
  consistency, flags
```

YugabyteDB 的 YCQL 接口完整继承此协议；YSQL 接口走 PG 协议。同一引擎暴露两种 prepared 协议是分布式 NewSQL 时代特有的现象。

## 关键发现

### 1. SQL 层 PREPARE 与协议层是两套独立体系

SQL:1992 的 `PREPARE name FROM ...` 和 PG/MySQL 的协议消息共享"预编译语句"这个概念名，但实现完全独立。同一会话中同名的 SQL 层 PREPARE 与协议层 Parse 不冲突——它们是不同的命名空间。生产代码几乎只走协议层，SQL 层 PREPARE 主要被人工 psql/mysql 客户端、ETL 脚本、某些 stored procedure 使用。

### 2. 二进制协议的真实价值在小整数与时间戳

INT、BIGINT、TIMESTAMP、UUID 在二进制协议节约 30-70% 字节；VARCHAR/TEXT 节约 0%；NUMERIC/DECIMAL 反而更复杂。这意味着协议选择对 OLTP 工作负载（事务表 + 整数列 + 时间戳列）效益最大；对宽 VARCHAR 主导的批处理几乎无收益。

### 3. PG 的"语句/portal 分离"是独特设计

PG 把 Parse 出来的"语句"和 Bind 出来的"门户"作为两个独立概念，让一个语句被多次 Bind 成不同 portal 同时存活——这是 MySQL/SQL Server 都没有的能力。但实际上，绝大多数驱动只用"匿名 portal" + "立即 Execute" 的简化路径，复杂的 portal 设计被低估。

### 4. PgBouncer 1.21 才让 transaction pooling 与协议预编译共存

2023 年 10 月之前，PG 生态最常见的高性能组合"PG JDBC + 服务端 prepared + PgBouncer transaction mode"是**协议级 broken**。无数生产事故源于此——升级到 PgBouncer 1.21+ 是免费的性能与稳定性收益。

### 5. ClickHouse/Snowflake/BigQuery 没有真正的"句柄复用"

参数化查询不等于服务端预编译。ClickHouse 22.x、Snowflake REST、BigQuery REST 都把参数与 SQL 分离传输（抗注入、类型安全），但每次请求服务端仍重新解析 SQL。"PREPARE 一次 EXECUTE 万次"的模型在这些引擎上不存在——OLAP 工作负载下也不需要。

### 6. MySQL 默认配置压不住 ORM

`max_prepared_stmt_count=16382` 看似很大，但 ORM（Hibernate、Sequelize、SQLAlchemy）在大量短连接 + 长时不释放语句的场景下能在几小时内打爆。`Can't create more than max_prepared_stmt_count statements` 是 MySQL 生产环境最常见的"莫名其妙崩溃"之一。**默认值需要调大或确保连接释放路径调用 `COM_STMT_CLOSE`**。

### 7. Oracle 的库缓存让"DEALLOCATE 不真正释放"

`OCIStmtRelease` 把语句还回库缓存而非销毁，让相同 SQL 文本在不同会话间共享解析结果——这是 Oracle 自 90 年代起就有的设计，至今其他主流引擎仍未完全跟上（PG/MySQL 是会话私有；TiDB/OceanBase 模仿但不完整）。

### 8. SQLite v2 的"自动重编译"是嵌入式数据库的实用主义

`sqlite3_prepare_v2` 保留 SQL 文本副本让 schema 变更后透明重 prepare——这是嵌入式场景对应用最友好的设计。PG/MySQL 是"prepared 语句失效报错让客户端处理"，更接近"协议契约"思路。两种哲学没有对错，但 SQLite 的方式让 ORM 实现简单很多。

### 9. Arrow Flight SQL 是协议层预编译的下一代候选

Apache Arrow Flight SQL（2022）的 `CommandPreparedStatementQuery` 把"协议层 prepared + 列式结果"标准化。InfluxDB IOx、Doris、Dremio 已采用。如果它能在 5 年内成为分析型数据库的事实协议，会终结当前每家私有 wire 协议的局面。但 OLTP 阵营（PG/MySQL/Oracle 系）短期不会迁移。

### 10. 协议层预编译与计划缓存解耦

服务端可以：
- 协议层 PREPARE，但不缓存计划（每次 EXECUTE 重新优化 → MySQL 默认行为）
- 协议层 PREPARE 且缓存计划（PG/Oracle/SQL Server）
- 不暴露协议层 PREPARE 但内部缓存计划（Snowflake 内部 plan 缓存）
- 既不 PREPARE 也不缓存（Trino/早期 ClickHouse）

这两个能力可以独立组合，本文聚焦前者，`prepared-statement-cache.md` 聚焦后者。理解二者的解耦是引擎设计选型的基础。

## 对引擎实现者的建议

### 1. 协议层句柄设计

```
两种主流方案:
  方案 A (PG): 客户端命名 (字符串)
    优点: 应用可见, 调试友好
    缺点: 客户端需要分配唯一名称
    适用: 同步式 OLTP 应用

  方案 B (MySQL/SQL Server): 服务端句柄 (整数)
    优点: 服务端控制空间, 紧凑
    缺点: 客户端需维护映射, 协议字节多
    适用: 大多数驱动场景

新引擎建议: 同时支持两种, PG 协议为内部默认, 兼容驱动需求
```

### 2. 匿名语句的优化路径

```
匿名 prepared 是协议层的"快路径":
  Parse(空名, sql) -> 不进入计划缓存
  Bind(空 portal, 空 stmt) -> 不进入 portal 表
  Execute(空 portal) -> 直接执行后销毁
  Sync -> ReadyForQuery

优势: 单查询场景比命名 prepared 节省 stmt_table 锁与内存
注意: 第二次 Parse 出现时丢弃前一个匿名计划
```

### 3. 二进制类型编码的兼容性陷阱

```
易错点:
  1. INT4 大端 vs 小端: PG 是大端 (网络序), 必须明确
  2. TIMESTAMP 纪元: PG 用 2000-01-01, MySQL 用 Unix epoch, 切勿混淆
  3. NUMERIC: 各家二进制结构不同, 文本格式更安全
  4. NULL 表示: 协议字段长度 -1 (PG/MySQL), bitmap 位 (MySQL 二进制结果)

设计建议:
  对类型编码做 conformance test 套件
  支持 "client preferred format" 协商, 不要强制
  默认对常见类型 (int/float/timestamp/uuid) 走二进制
  对 NUMERIC/JSON/数组等复杂类型默认文本
```

### 4. 生命周期与会话状态

```
关键决策:
  命名 prepared 寿命: 会话级 vs 事务级 vs 显式 close
    PG/MySQL: 会话级 (事务结束不释放)
    某些代理: 模拟事务级以兼容 transaction pooling

  DDL 失效策略:
    硬失效: 下一次 Execute 报错, 客户端需重 prepare (PG)
    软失效: 服务端透明重 prepare (CockroachDB / SQLite v2)
    隔离: prepared 锁住 schema, DDL 等待 (受争议)

  原则: 一致性 > 透明性, 客户端能感知失效更安全
```

### 5. 单会话上限的设置

```
推荐默认值:
  max_prepared_stmt_count_per_session = 1024 (软上限)
  max_prepared_stmt_size_per_session = 16 MB

错误处理:
  超限时返回明确错误码而非 OOM
  PG: 42P05 (or custom 53XXX)
  MySQL: 1461 (max_prepared_stmt_count)
  错误信息包含建议: "调用 DEALLOCATE 或减少 prepare 频率"

监控指标:
  prepared_stmts_count_per_session (gauge)
  prepared_stmts_total_bytes (gauge)
  prepared_stmts_evictions (counter)  -- 如果实现 LRU
```

### 6. 协议流水线 (Pipelining)

```
PG Sync 之前可连续 Parse/Bind/Execute:
  优势: 节省往返, JDBC executeBatch() 受益
  实现要点:
    Parse 失败后丢弃后续直到 Sync (不应执行污染状态)
    Bind/Execute 失败处理同上
    异步 ResultRow 流要保证按 Execute 顺序回送

错误恢复:
  错误后所有未完成的 Execute 都回滚 (隐式)
  ReadyForQuery 之前不接受新查询

设计建议:
  显式记录"流水线中是否已有错误"标志
  避免错误诊断冗余 (ErrorResponse + ReadyForQuery 配对)
```

### 7. 与连接池的协作

```
透明性陷阱:
  连接池可能在事务边界回收物理连接
  服务端命名 prepared 是物理连接的状态 → 切换后失效

解决方案 (引擎层):
  方案 1: 提供"client identity"协议字段
    池化器把同一客户端ID的请求路由到同物理连接
  方案 2: 提供"prepared statement transfer"协议
    显式 dump/restore 语句状态
  方案 3 (最常见): 不在引擎层解决, 让池化器自己镜像

PgBouncer 1.21 选择方案 3, 引擎不变, 池化器实现 mirror
```

### 8. 测试与一致性

```
必测场景:
  1. 重复 Parse 同名: 应报错
  2. Parse 后立即 Close, 再 Parse 同名: 应成功
  3. Bind 引用未 Parse 的 stmt: 应报错
  4. Execute 引用未 Bind 的 portal: 应报错
  5. 参数数量与类型 OID 不匹配: 应报错
  6. NULL 参数 (length=-1): 正常处理
  7. 二进制 vs 文本格式互换: 结果一致
  8. DDL 后旧 prepared 的行为: 失败 / 重 prepare
  9. 并发会话各自的命名空间: 互不干扰
  10. max_prepared_stmt_count 临界: 优雅拒绝

性能基准:
  Simple Query (Q) vs Extended Query (Parse/Bind/Execute) 同样查询的延迟比
  二进制 vs 文本结果集吞吐量比
  N 次 Bind+Execute 流水线 vs N 次独立查询往返比
```

### 9. 安全考量

```
SQL 注入: 协议层预编译 != 自动安全
  陷阱: 应用把不信任值用字符串拼接到 SQL 文本里, 然后 Parse
  保护: 应用必须用参数槽位 (?, $1) 传递值, 不要拼接

服务端解析逃逸: 极少数 SQL 解析器漏洞导致参数被解释为 SQL
  防御: 协议层必须区分 Parse 时的 SQL 文本和 Bind 时的参数二进制
        参数永远不进入 parser

资源耗尽攻击:
  恶意客户端疯狂 PREPARE 不 DEALLOCATE → OOM
  防御: 单会话上限 + 单连接频率限制 + 监控
```

## 总结对比矩阵

### 协议层预编译的关键能力

| 能力 | PostgreSQL | MySQL | SQL Server | Oracle | DB2 | SQLite | ClickHouse | Snowflake | Trino |
|------|-----------|-------|------------|--------|-----|--------|-----------|-----------|-------|
| 协议层 PREPARE | 是 | 是 | 是 | 是 | 是 | 嵌入式 | 否 | REST | HTTP header |
| 二进制参数 | 是 | 是 | 是 | 是 | 是 | 嵌入式 | 部分 | 是 | 否 |
| 二进制结果 | 是 | 是 | 是 | 是 | 是 | 嵌入式 | 是 | 是 | 否 |
| 命名语句 | 是 | 否 | 句柄 | 句柄 | 区段 | 句柄 | -- | -- | 是 |
| 匿名语句 | 是 | 句柄即匿名 | sp_executesql | -- | -- | -- | -- | -- | -- |
| Pipelining | 是 (Sync) | 否 | 否 | 部分 | 否 | -- | -- | -- | -- |
| 服务端句柄 | 命名/匿名 | int32 | int | OCI 句柄 | 区段号 | sqlite3_stmt* | -- | -- | -- |
| 自动 DDL 失效 | 是 | 是 | 是 | 是 | 是 | 是 (v2) | -- | -- | -- |
| 跨会话共享 | 否 | 否 | 计划共享 | 库缓存 | 包共享 | -- | -- | -- | -- |

### 引擎选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| 高频 OLTP，小查询参数化 | PG + 服务端 prepared + libpq/JDBC + 二进制 | 二进制协议网络与 CPU 双优 |
| MySQL 兼容生态 | MySQL/MariaDB/TiDB + Connector/J + `useServerPrepStmts=true&cachePrepStmts=true` | 必须显式打开服务端 prepare |
| 短连接 + 高并发池化 | PG + PgBouncer 1.21+ + transaction mode + JDBC | 池化与协议预编译共存 |
| 流水线批处理 | PG JDBC `addBatch()` + `executeBatch()` 利用 Sync | 节省 (N-1) 次往返 |
| 嵌入式应用 | SQLite v2 / DuckDB | 协议开销为 0，编译开销近 0 |
| 分析型查询 (无重用) | ClickHouse 参数化 / Snowflake REST | 不需要协议层句柄复用 |
| 跨厂商列式协议 | Arrow Flight SQL (实验) | 标准化中 |
| 分布式 OLTP | CockroachDB / YugabyteDB / TiDB | 继承 PG/MySQL 协议，零客户端修改 |
| Oracle 兼容 | Oracle / OceanBase Oracle 模式 + OCI/JDBC | 数组绑定无替代 |

### 各协议设计哲学对比

```
PostgreSQL: 显式可组合
  Parse + Bind + Describe + Execute + Sync 五个原子消息
  应用/驱动可以精细控制每一步
  pipelining + 按列格式协商 = 最灵活

MySQL: 紧凑高效
  PREPARE/EXECUTE/CLOSE 三个核心命令
  Bind 内联在 EXECUTE 中
  服务端整数句柄 = 协议字节最少
  设计哲学: "OLTP 短查询不需要更多原子性"

SQL Server: RPC 一切
  没有专门的 PREPARE 消息, 一切都是 RPC
  sp_prepare/sp_execute 是系统存储过程
  设计哲学: "扩展性靠系统过程, 协议保持简单"

Oracle OCI: 客户端为王
  bind/define 在客户端缓冲区注册
  服务端不知道客户端缓冲区结构
  数组绑定 + 库缓存 = 极致 OLTP 吞吐
  设计哲学: "把状态放客户端"

Cassandra/YCQL: 确定性 ID
  PREPARE 返回 MD5(query)
  集群间共享, 无需 re-prepare
  设计哲学: "在分布式系统里, 协议必须无状态"

Arrow Flight SQL: 列式优先
  执行流是 Arrow IPC stream
  prepared 用 protobuf 编码
  设计哲学: "OLAP 时代的 wire 协议应该是列式"
```

## 参考资料

- ISO/IEC 9075-3:2008 — SQL/CLI (Call-Level Interface)
- JSR 221 — JDBC API Specification
- PostgreSQL: [Frontend/Backend Protocol — Extended Query](https://www.postgresql.org/docs/current/protocol-flow.html#PROTOCOL-FLOW-EXT-QUERY)
- PostgreSQL: [Message Formats](https://www.postgresql.org/docs/current/protocol-message-formats.html)
- PostgreSQL: [SQL PREPARE](https://www.postgresql.org/docs/current/sql-prepare.html)
- MySQL Reference Manual: [Prepared Statements](https://dev.mysql.com/doc/refman/8.0/en/sql-prepared-statements.html)
- MySQL Internals: [COM_STMT_PREPARE](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_com_stmt_prepare.html)
- MariaDB: [COM_STMT_BULK_EXECUTE](https://mariadb.com/kb/en/com_stmt_bulk_execute/)
- SQL Server: [sp_prepare / sp_execute / sp_unprepare](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-prepare-transact-sql)
- Oracle: [OCI Statement Functions (OCIStmtPrepare2)](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnoci/statement-functions.html)
- IBM DB2: [DRDA Reference](https://www.ibm.com/docs/en/db2/11.5?topic=overview-drda)
- SQLite: [sqlite3_prepare_v2](https://www.sqlite.org/c3ref/prepare.html)
- ClickHouse: [Parameterized Queries (22.3+)](https://clickhouse.com/docs/en/interfaces/cli#cli-queries-with-parameters)
- PgBouncer: [Release Notes 1.21.0 — protocol-level prepared statements](https://www.pgbouncer.org/2023/10/pgbouncer-1-21-0)
- Apache Arrow Flight SQL: [Specification](https://arrow.apache.org/docs/format/FlightSql.html)
- Cassandra Native Protocol: [v4 Specification](https://github.com/apache/cassandra/blob/trunk/doc/native_protocol_v4.spec)
- TDS Protocol: [Microsoft Open Specifications [MS-TDS]](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-tds/)
