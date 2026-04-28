# 事务流水线 (Transaction Pipelining)

OLTP 应用提交一个事务往往要发起 3-10 条 SQL：BEGIN、若干 INSERT/UPDATE、COMMIT。如果客户端串行收发，每条都要等一次 round-trip，跨可用区或跨地域时单事务延迟很容易突破 50 ms；而流水线化后客户端可以连续推送整批命令，服务器按顺序处理并连续回送响应——同样的事务延迟可以压缩到 1-2 个 RTT。流水线（pipelining）/ 请求批处理（request batching）是协议层最朴素也最关键的延迟优化手段，但各数据库的支持深度差异极大。

## 为什么流水线对延迟而非吞吐更关键

吞吐瓶颈通常在 CPU 和 I/O，可以通过开更多连接横向扩展；但单事务延迟受限于网络物理 RTT，无法用并发掩盖。一个跨 AZ 链路的 RTT 通常 1-2 ms，跨地域 30-100 ms。一笔包含 6 条语句的事务，串行收发要 6×RTT；流水线化后只需 1×RTT 推送 + 1×RTT 取最后响应。在金融交易、Auth/Token 验证、广告竞价等场景，p99 延迟从 60 ms 降到 5 ms 是质变。

流水线**不增加吞吐量**——CPU 和 I/O 不变；它**减少延迟**——客户端不再被 RTT 阻塞。这与连接池、prepared statement cache、批量插入是不同维度的优化。

## 没有 SQL 标准

ISO/IEC 9075（SQL 标准）只规定语法和语义，不涉及网络协议层。因此流水线完全是"协议私有特性 + 客户端 API"的组合，缺乏跨引擎一致性：

| 维度 | 标准化情况 |
|------|----------|
| SQL 层 BEGIN/COMMIT | 标准（ISO/IEC 9075-2, Section 4.35） |
| 多语句串（multi-statement） | 部分标准（compound statement、stored procedure） |
| 协议层流水线 | **完全不标准** |
| 客户端 API（pipeline mode） | **完全不标准**，每个驱动自定义 |
| 失败传播规则 | 协议私有 |

可以说"流水线"是数据库工业界最分散的特性之一：协议设计早期为简化客户端实现，多采用严格的"请求-响应"同步模式；后来为了性能加上流水线，但每家都走自己的路。

## 支持矩阵（45+ 引擎）

### 协议级流水线、批处理与显式 API

| 引擎 | 协议级流水线 | 事务流水线 (BEGIN/Q.../COMMIT 一次发) | 自动流水线客户端 | 显式 pipeline API | 乱序完成 | 关键版本 |
|------|------------|-----------------------------------|----------------|-----------------|---------|---------|
| PostgreSQL | 是 (extended query) | 是 | 部分驱动 | libpq 14+ / PgJDBC | 否 (FIFO) | libpq 14 (2021) |
| MySQL | 多语句查询 (CLIENT_MULTI_STATEMENTS) | 是 (一条文本含多句) | 否 (Connector/J 部分) | 否 | 否 | 4.1 (2004) |
| MariaDB | 同 MySQL + COM_STMT_BULK_EXECUTE | 是 | 否 | 否 | 否 | 10.2 (2017) |
| SQLite | -- (嵌入式) | -- | -- | -- | -- | -- |
| Oracle | OCI Statement Batching / Array DML | 是 (PL/SQL 块) | OCI Implicit Buffer | OCI/JDBC sendBatch | 否 | 10g (2003) |
| SQL Server | TDS RPC 批 / sp_executesql | 是 (一条 batch) | .NET batched send | TDS attention | 否 | 2000+ |
| DB2 | DRDA chained CMD | 是 | 否 | JDBC addBatch | 否 | 早期 |
| Snowflake | HTTPS 单请求 | 多语句 API | -- | Multi-Statement | 否 | GA |
| BigQuery | gRPC + REST | -- | -- | jobs.query 批量 | 异步 job | GA |
| Redshift | PostgreSQL v3 | 是 | 否 (Redshift 数据 API 异步) | 部分 | 否 | 继承 PG |
| DuckDB | 嵌入式 | -- (函数调用) | -- | Appender / 多语句 | -- | -- |
| ClickHouse | Native TCP / HTTP / gRPC | HTTP query 串接 | 否 | gRPC streaming | 流式 | 早期 |
| Trino | HTTP REST | 否 (无事务) | -- | 无 | 否 | -- |
| Presto | HTTP REST | 否 | -- | 无 | 否 | -- |
| Spark SQL | Thrift Server | 否 (无事务) | -- | DataFrame batch | 否 | -- |
| Hive | Thrift HiveServer2 | -- | -- | 无 | -- | -- |
| Flink SQL | SQL Gateway | -- | -- | -- | -- | -- |
| Databricks | Thrift / SQL API | -- | -- | -- | -- | -- |
| Teradata | TDP CLIv2 | 是 (BTEQ 批) | 否 | JDBC addBatch | 否 | V2R5+ |
| Greenplum | PostgreSQL v3 | 是 (继承 PG) | 部分驱动 | 继承 libpq | 否 | 继承 PG |
| CockroachDB | PostgreSQL v3 | 是 | 部分驱动 | 继承 libpq | 否 | 19.2+ |
| TiDB | MySQL Protocol | 是 (CLIENT_MULTI_STATEMENTS) | 否 | 否 | 否 | 早期 |
| OceanBase | MySQL/Oracle 双协议 | 是 | OB Connector 优化 | 否 | 否 | 早期 |
| YugabyteDB | PostgreSQL v3 | 是 | 部分驱动 | 继承 libpq | 否 | 2.6+ |
| SingleStore | MySQL Protocol | 是 | 否 | 否 | 否 | 早期 |
| Vertica | Vertica 私有 | 是 | 部分驱动 | 部分 | 否 | 早期 |
| Impala | HiveServer2 / Beeswax | 否 | -- | 无 | -- | -- |
| StarRocks | MySQL / HTTP Stream Load | 部分 | 否 | 否 | -- | -- |
| Doris | MySQL / HTTP Stream Load | 部分 | 否 | 否 | -- | -- |
| MonetDB | MAPI | 是 (语句串) | 否 | 否 | 否 | 早期 |
| CrateDB | PostgreSQL v3 | 是 (继承 PG) | 部分驱动 | 部分 | 否 | 4.0+ |
| TimescaleDB | PostgreSQL v3 | 是 (继承 PG) | 部分驱动 | 继承 libpq | 否 | 继承 PG |
| QuestDB | PG v3 / ILP / HTTP | ILP 批 | ILP 客户端 | 否 | ILP 是 | 早期 |
| Exasol | WebSocket JSON | 否 (单请求) | -- | 否 | -- | -- |
| SAP HANA | SQLDBC | 是 | 否 | sendBatch | 否 | 2.0+ |
| Informix | SQLI | 是 | 否 | 否 | 否 | 早期 |
| Firebird | XDR Wire | 否 | -- | 部分 | 否 | -- |
| H2 | TCP / PG mode | 否 | -- | 否 | -- | -- |
| HSQLDB | 私有 / HTTP | 否 | -- | 否 | -- | -- |
| Derby | DRDA | 是 (chained) | 否 | JDBC addBatch | 否 | 继承 DRDA |
| Amazon Athena | HTTPS REST | -- | -- | -- | 异步 | -- |
| Azure Synapse | TDS | 是 | -- | -- | -- | 继承 SQL Server |
| Google Spanner | gRPC | 是 (TransactionRunner 批) | 部分 SDK | gRPC streaming | 部分 | GA |
| Materialize | PostgreSQL v3 | 是 | 部分驱动 | 继承 libpq | 否 | 继承 PG |
| RisingWave | PostgreSQL v3 | 是 | 部分驱动 | 继承 libpq | 否 | 继承 PG |
| InfluxDB (3.x SQL) | Arrow Flight SQL | -- | -- | gRPC streaming | 流式 | -- |
| Databend | MySQL / ClickHouse / REST | 是 (MySQL 多语句) | 否 | 否 | -- | GA |
| Yellowbrick | PostgreSQL v3 | 是 | 部分驱动 | 继承 libpq | 否 | 继承 PG |
| Firebolt | HTTPS REST | 否 | -- | 否 | 异步 | -- |
| Cassandra (CQL) | CQL Native | 是 (BATCH 语句) | Java driver async | execute_async | 是 | 1.2+ |
| ScyllaDB | CQL Native | 是 (BATCH) | shard-aware async | execute_async | 是 | 早期 |
| MongoDB (SQL/BI) | OP_MSG | 是 (writeBulk / OP_MSG batch) | 自动 | bulkWrite | 是 (有序/无序) | 3.6+ (2017) |
| Redis (RediSQL) | RESP | 是 (MULTI/EXEC + pipelining) | 自动 | pipeline / multi | 否 | 1.x+ |

> 统计：约 30+ 引擎在协议或客户端层支持某种形式的流水线/批处理；无事务或无 OLTP 场景的引擎（Trino/Presto/Spark/Flink）通常不需要流水线优化。

### 客户端驱动 / 连接池层支持

| 客户端/中间件 | 流水线支持 | 关键版本 | 备注 |
|-------------|----------|---------|------|
| libpq (C, PostgreSQL 官方) | PQpipelineMode | PostgreSQL 14 (2021-09) | 显式 API：PQenterPipelineMode 等 |
| psqlODBC | 不支持显式 pipeline | -- | 依赖 libpq，但默认未开放 |
| PgJDBC | PgJDBC PipelineBatch + reWriteBatchedInserts | 9.4+ | addBatch + 批量 INSERT 改写 |
| Npgsql (.NET) | 隐式 pipeline + multiplexing | 6.0 (2021-11) | Multiplexing 自动流水线 |
| asyncpg (Python) | 全面流水线 | 0.x+ | 基于 prepared statement，自动 pipeline |
| node-postgres (pg) | 隐式 (libpq mode) / Cursor 不支持 | -- | 单连接顺序发送，async/await 串行 |
| Rust tokio-postgres | pipeline 可选 | 0.6+ | client.simple_query_pipelined |
| MySQL Connector/J | rewriteBatchedStatements | 5.x+ | 客户端把多个 INSERT 合并为单语句 |
| MariaDB Connector/J | useBatchMultiSend | 1.6+ | 真正的协议级批发送 |
| Connector/Python (MySQL) | execute_many | 8.x+ | rewriteBatched 非默认 |
| asyncmy / aiomysql | 部分 | -- | 异步但不真正流水线 |
| Microsoft JDBC for SQL Server | sendStringParametersAsUnicode | 2008+ | TDS RPC 批，addBatch |
| Microsoft.Data.SqlClient (.NET) | SqlBulkCopy / 批 RPC | 2.x+ | TDS RPC 流水线 |
| OCI (Oracle C 接口) | OCIStmtExecute(iters>1) | 10g (2003) | Statement Batching, Array DML |
| Oracle JDBC (ojdbc) | sendBatch / executeBatch | 10g | 默认开启 |
| Cassandra Java Driver | execute_async + token-aware | 1.x+ | 自动 async pipelining |
| MongoDB Driver (Java/Node/Python) | bulkWrite | 3.6+ | OP_MSG 批量传输 |
| ClickHouse JDBC / Go driver | INSERT batch + query 串接 | 早期 | HTTP/Native 都支持 |
| ClickHouse-rs (Rust) | block-based async | 早期 | Native 协议天然支持 |
| jOOQ | 无原生 pipeline | -- | 依赖底层驱动 batch |
| HikariCP | 无 (连接池) | -- | 透传驱动能力 |
| PgBouncer | pipelining 1.21+ (2023-10) | 1.21 | session/transaction 池支持 |
| Odyssey | 是 (PG pooler) | -- | 默认支持 |
| pgcat | 是 (Rust PG pooler) | -- | 默认支持 |
| ProxySQL | MySQL 多语句透传 | -- | 不重排 |
| Vitess | 自动批合并 | -- | 路由层重新组装 |
| ShardingSphere | 路由层批 | -- | Java 实现 |

### 流水线 vs 显式批量的概念对照

| 概念 | 适用层 | 典型语义 | 示例 |
|------|------|---------|------|
| 协议流水线 (pipelining) | wire 协议层 | 不等响应即发送下一请求；服务器按 FIFO 处理并按序回复 | libpq pipeline mode |
| 多语句 (multi-statement) | SQL 文本层 | 一条文本字符串包含多个 SQL，分号分隔 | `BEGIN;UPDATE...;COMMIT;` |
| 客户端批 (addBatch) | JDBC / 驱动 API | 客户端缓冲多次 execute，executeBatch 一次发 | PreparedStatement.addBatch() |
| 数组 DML (Array DML) | 驱动 API | 一条带占位符的语句 + N 行参数 = N 次执行 | OCI(iters=N) |
| 服务端批 (BATCH) | SQL 语句层 | 数据库识别 BATCH 关键字并整体处理 | Cassandra `BEGIN BATCH` |
| 异步批 (async/await) | 应用层 | 利用 future/promise 在同一连接上并发提交 | Cassandra Java driver execute_async |

注意它们可以叠加：JDBC addBatch 通常翻译为协议层流水线（如果驱动支持）；MySQL 的 rewriteBatchedStatements 把 N 个 INSERT 改写成一个 `INSERT ... VALUES (..),(..),...` 多值语句，本质上是多语句而非协议流水线。

## PostgreSQL libpq Pipeline Mode 深入剖析

PostgreSQL 14（2021 年 9 月）官方在 libpq 中引入了 **pipeline mode**，是 OSS 数据库里第一个把流水线 API 完整暴露给应用程序的客户端库。它建立在 PostgreSQL 协议（v3）的 Extended Query 子协议之上，把多年来"协议本就支持但客户端没用"的能力正式开放。

### 协议背景：Extended Query 早就支持流水线

PostgreSQL v3 协议中 Extended Query 由若干消息组成：

| 客户端 → 服务端 | 服务端 → 客户端 |
|-----------------|----------------|
| Parse (P) | ParseComplete (1) |
| Bind (B) | BindComplete (2) |
| Describe (D) | RowDescription (T) / ParameterDescription (t) / NoData (n) |
| Execute (E) | DataRow (D) ... CommandComplete (C) / EmptyQueryResponse (I) |
| Sync (S) | ReadyForQuery (Z) |
| Flush (H) | (无单独响应) |

关键点：

1. **Sync 是事务划界 + 错误屏障**：服务端遇到 Sync 才发 ReadyForQuery，错误也只在该 Sync 之前的命令中传播
2. **Flush 强制刷网络但不分隔事务**：客户端需要部分响应时用，不影响错误传播
3. **没有强制"等响应"的规则**：协议从未规定客户端必须收到 ParseComplete 才能发下一个 Parse

也就是说，2003 年 PG 7.4 引入 Extended Query 时协议**已经允许流水线**。但 libpq 的同步 API（PQexecParams 等）每次都内部插入 Sync 并阻塞等响应，应用层无法利用。直到 14 才补上"显式控制 Sync 时机"的 API。

### libpq Pipeline Mode 状态机

```
PQ_PIPELINE_OFF    -- 默认，每个 PQexec* 自带 Sync
       │
       │ PQenterPipelineMode()
       ▼
PQ_PIPELINE_ON     -- 流水线模式，命令不自动 Sync
       │  │
       │  └── PQpipelineSync()        -- 显式插入 Sync 边界
       │  └── PQsendQueryParams()     -- 入队但不刷
       │  └── PQsendPrepare/...       -- 入队
       │  └── PQpipelineFlush()       -- 强制网络刷新
       │
       │ PQexitPipelineMode()
       ▼
PQ_PIPELINE_ABORTED -- 收到错误后进入，需要清空到下一个 Sync
       │
       │ 处理完 PipelineSync 响应
       ▼
PQ_PIPELINE_ON  / PQ_PIPELINE_OFF
```

### 典型使用模式

```c
PGconn *conn = PQconnectdb("host=...");
PQenterPipelineMode(conn);

/* 排队 N 个命令，不等响应 */
for (int i = 0; i < N; i++) {
    PQsendQueryParams(conn, "INSERT INTO t VALUES ($1, $2)",
                      2, NULL, vals[i], lens[i], fmts[i], 0);
}
PQpipelineSync(conn);  /* 在尾部放一个 Sync 屏障 */

/* 拉取响应：每条对应一个 PGresult */
for (int i = 0; i < N; i++) {
    PGresult *res = PQgetResult(conn);
    /* 处理结果 */
    PQclear(res);
    PQgetResult(conn);  /* 拉取 NULL，标识本条结束 */
}
/* 拉取 PGRES_PIPELINE_SYNC 标识 Sync 屏障 */
PGresult *sync = PQgetResult(conn);
assert(PQresultStatus(sync) == PGRES_PIPELINE_SYNC);

PQexitPipelineMode(conn);
```

### 错误传播规则（pipeline 中的语义陷阱）

Pipeline 中一条命令出错时，PostgreSQL 服务端会：

1. 把错误响应发给该条命令
2. **跳过本 Sync 屏障内所有后续命令**，发回 PGRES_PIPELINE_ABORTED
3. 直到收到 Sync，发回 ReadyForQuery 后状态机回到 PQ_PIPELINE_ON

这个语义意味着：

- 想让 N 条命令独立失败：每条后面跟一个 PQpipelineSync（性能下降）
- 想让 N 条命令构成事务：全部包在 BEGIN/COMMIT 里加一个 Sync（标准做法）
- 想容忍部分失败：用 SAVEPOINT，每条后 RELEASE/ROLLBACK TO，pipeline 里仍是顺序串

PgJDBC 的 PipelineBatch（驱动级 API，9.4 起）在协议层做了同样的事，但暴露给应用的是更高层的 BatchUpdate 抽象。

### 性能数据（社区基准）

PostgreSQL 14 commit 6868c8c（Alvaro Herrera, 2021-03）的 commit message 给出参考数据：

- 跨大西洋链路（RTT 约 100 ms）：500 条 INSERT 串行 50 秒，pipeline 1.2 秒，约 40 倍提升
- 同一数据中心（RTT 约 0.1 ms）：500 条 INSERT 串行 80 ms，pipeline 30 ms，约 2.5 倍
- 本地 socket：差异基本消失（RTT 几十微秒，不再是瓶颈）

结论：流水线收益与网络 RTT 强正相关，跨区域/跨云场景收益最大。

## MySQL 多语句查询（CLIENT_MULTI_STATEMENTS）

MySQL 4.1（2004）在 capability flags 中加入 **CLIENT_MULTI_STATEMENTS**，允许一个 COM_QUERY 文本中包含多条 SQL 用分号分隔。这是 MySQL 协议侧"流水线"的主要形式，但语义和 PG 的协议级流水线截然不同：

```
COM_QUERY 文本 = "BEGIN;UPDATE t1 SET x=1 WHERE id=10;UPDATE t2 SET y=2 WHERE id=10;COMMIT;"
                 ↓
服务端解析 → 顺序执行 → 顺序返回 4 个结果集
```

### 关键区别

| 维度 | PostgreSQL pipeline | MySQL multi-statement |
|------|--------------------|----------------------|
| 协议层级 | wire 协议级（多个独立请求帧） | SQL 解析层（一个请求多语句） |
| 客户端缓冲 | 排队 N 个独立 Parse/Bind/Execute | 字符串拼接 |
| 解析开销 | 每条独立解析，可缓存计划 | 整体一次解析 |
| 错误处理 | Sync 屏障可控 | 默认遇到错误停止后续 |
| 参数化 | 每条带二进制参数 | 必须文本拼接（SQL 注入风险） |
| 默认开启 | 否 (需 PQenterPipelineMode) | 否 (capability bit 协商) |
| 客户端 API | PQsendQueryParams | mysql_real_query 一次性 |

为安全 MySQL Connector/J 默认 `allowMultiQueries=false`；显式开启需在 JDBC URL 加 `allowMultiQueries=true`，使用时务必小心 SQL 注入。

### MySQL COM_STMT_BULK_EXECUTE（MariaDB 10.2 扩展）

MariaDB 协议里 COM_STMT_BULK_EXECUTE（命令字 0x1c）允许一个 prepared statement 携带 N 行参数，等价于 N 次 EXECUTE 但只发一次。这是真正的批 DML 协议帧：

```
[stmt_id][flags][n_params][types][param0_row0][param1_row0]...[param0_rowN][param1_rowN]
```

返回 N 次 OK 包。MySQL 8.x 不支持，仅 MariaDB 10.2+ 实现。

### CLIENT_MULTI_STATEMENTS 与连接池的相互作用

ProxySQL 等中间件默认透传多语句，但部分语句路由策略（按表分片）需要拆分语句，因此一些 sharding 中间件（Vitess、MyCAT）禁用或限制多语句。

## SQL Server TDS Connection Pipelining

SQL Server 的 TDS（Tabular Data Stream）协议从 7.0 起支持在一个 RPC 包里嵌入**多条参数化 SQL**，称为 RPC 批：

```
TDS RPCRequest:
  RpcName = "sp_executesql"
  Param1  = N'INSERT...; UPDATE...; COMMIT'   -- 文本批
  Param2  = N'@p1 int, @p2 nvarchar(50)'      -- 参数声明
  Param3  = 100                                -- @p1
  Param4  = N'foo'                             -- @p2
```

这是一种"协议层多语句"，类似 MySQL 但参数是真二进制的。.NET 的 SqlClient 在 ADO.NET 6+ 引入 **batched async send**：连接维护一个待发送队列，调用 await ExecuteNonQueryAsync 时驱动尝试合并相邻 RPC 一次发出。

### TDS 的 Attention 机制

与 PG/MySQL 不同，TDS 客户端可以**异步发送 attention 包（0x06）取消正在执行的请求**。在流水线场景下这很有用：客户端发现错误时可以提前打断后续命令，避免"数据已写入但客户端不想要"的状态。但 attention 也会影响 pipeline 的语义复杂度。

## Oracle OCI Statement Batching / Array DML

Oracle 早在 8i（1999）的 OCI 接口就支持 **Array DML**：一条 INSERT/UPDATE/DELETE 携带多组绑定值。10g（2003）加入更通用的 **OCIStmtExecute(iters > 1)**：

```c
OCIStmt *stmt = ...;
OCIBindByPos(stmt, &bnd1, ..., &age_array[0], sizeof(int), SQLT_INT, ...);
OCIBindByPos(stmt, &bnd2, ..., name_array,    50,          SQLT_STR, ...);

/* iters = N: 一次发送 N 行参数 */
OCIStmtExecute(svc, stmt, err, /*iters=*/1000, /*rowoff=*/0, NULL, NULL, OCI_DEFAULT);
```

### Implicit Statement Buffering

Oracle JDBC（ojdbc）默认开启 **Implicit Statement Caching + Batching**：连接对象内部缓冲 addBatch 调用，executeBatch 时一次发出。`oracle.jdbc.defaultBatchValue` 决定缓冲触发阈值（默认 1）。设为更大值会更积极合并。

### Net8/TNS 协议层

OCI 之下的 TNS 协议（Oracle Net）有一个 piggyback 机制，允许客户端的"小命令"（如 OAUTH、SCN 推送）搭便车跟在主请求包后，省一次 round-trip。这不是通用流水线，但对登录、版本协商等握手阶段有显著收益。

## CockroachDB / TiDB / 其他 wire 兼容引擎

### CockroachDB

完全兼容 PostgreSQL v3 协议，pipeline mode 直接由 libpq 驱动支持。CRDB 19.2+ 优化了"流水线事务"路径：把 BEGIN/INSERT*N/COMMIT 一组命令在 raft 层合并成单次 leaseholder 通信，在跨可用区集群上单事务延迟从 4-5×RTT 降到 1-2×RTT。

CRDB 的 sql/conn_executor.go 中有专门的 pipelined writes 概念（与协议流水线同名但不完全等同）：把 INSERT/UPDATE 的 KV 写入异步发出，COMMIT 时再 flush。这是服务端内部的优化，对客户端透明。

### TiDB

兼容 MySQL 协议，因此继承 CLIENT_MULTI_STATEMENTS 的多语句机制。TiDB 自身没有协议层显式流水线 API，但 TiDB Lightning 和 BR 等内部工具用 batch DML 实现高吞吐。

### YugabyteDB / CrateDB / Materialize / RisingWave

均基于 PG v3 协议，libpq pipeline mode 可直接使用。但要注意：

- YugabyteDB 用 PG 11 fork，对 pipeline mode 的支持基于其升级到的 PG 上游版本
- Materialize 是流式数据库，pipeline 主要价值在初始化阶段批量定义视图
- RisingWave 同上

### Vertica

私有协议但对外暴露的 JDBC/ODBC 行为类似 PG。Vertica 7+ 支持 batched insert，11+ 加入"COPY LOCAL FROM stdin"的 pipelined 数据传输。

## Cassandra / ScyllaDB Java Driver Token-Aware Async

Cassandra Java Driver 自 1.x 起就把 **execute_async** 作为一等公民。配合 token-aware 路由策略，应用可以同时往多个分片协调器发请求：

```java
List<CompletionStage<AsyncResultSet>> futures = new ArrayList<>();
for (int i = 0; i < N; i++) {
    futures.add(session.executeAsync(prepared.bind(args[i])));
}
CompletableFuture.allOf(futures.toArray(new CompletableFuture[0])).join();
```

### CQL BATCH 语句

CQL 1.2+ 提供 BATCH 语句把多条 DML 服务端批处理：

```cql
BEGIN BATCH
  INSERT INTO t1 (id, v) VALUES (1, 'a');
  INSERT INTO t2 (id, v) VALUES (1, 'b');
  UPDATE t3 SET v='c' WHERE id=1;
APPLY BATCH;
```

LOGGED BATCH 提供原子性（基于 batch log）；UNLOGGED BATCH 不保证原子性但开销更小。注意大 BATCH 是 Cassandra 的反模式：增加协调器内存压力，常被生产环境推荐限制在 5-10 KB。

### ScyllaDB shard-aware

ScyllaDB 的官方驱动加入 shard-aware 调度：根据 partition key 直接连到目标分片所在的具体 CPU 核（per-core 架构），实现 thread-per-shard 流水线，避免在协调器上排队。

## MongoDB OP_MSG 批处理

MongoDB 3.6（2017）引入 **OP_MSG** 替代 OP_QUERY。OP_MSG 是基于"sections"的二进制帧，原生支持 bulk write：

```
OP_MSG {
    flags: 0,
    sections: [
        Section type=0: { insert: "users", $db: "test", ordered: true }
        Section type=1: identifier="documents", documents=[...100 docs...]
    ]
}
```

服务端在一个 OP_MSG 里收 100 条插入，原子性地对每条返回 ack。客户端 bulkWrite API（Java/Node/Python 各驱动）封装了这个流程。MongoDB SQL/BI Connector 在 SELECT 上不能流水线，但 INSERT/UPDATE 透过 BulkWriteOperation 走 OP_MSG。

### MongoDB 多语句事务

4.0 起支持 multi-document transaction，3.6 不支持。事务的 startTransaction/commitTransaction 都是独立 OP_MSG，因此事务流水线需要客户端层叠几次 OP_MSG，没有协议级原子帧。

## 连接池与流水线的相互作用

流水线在跨可用区/跨地域时收益最大，但生产环境通常通过 PgBouncer / ProxySQL / pgcat 等中间件接入数据库。这些中间件**是否透传 pipeline** 直接决定了应用是否真的能享受协议层批发送。

### PgBouncer 1.21（2023-10）：里程碑

PgBouncer 1.21（2023-10）正式加入 pipelining support：transaction pooling 和 statement pooling 模式都能透传 libpq pipeline。在此之前，pipeline 在 PgBouncer 后面会被强制打散为同步请求，等价于普通 PQexecParams。

时间线：

| 工具 | pipeline 透传支持 | 起始版本 / 年份 |
|------|------------------|----------------|
| PgBouncer | 是 | 1.21 (2023-10) |
| Odyssey | 是 | 1.0 (Yandex) |
| pgcat | 是 | 0.x（默认） |
| Connection Pool (内置 PG) | 是 | -- |
| Heimdall Proxy | 是 | -- |
| ProxySQL (MySQL) | 多语句透传 | 早期 |
| MaxScale (MariaDB) | 多语句透传 | 早期 |
| Vitess (MySQL) | 部分（按 sharding 拆分） | -- |
| MySQL Router | 是 | 8.0+ |

### Pooling 模式与 pipeline 的兼容性

| Pooling 模式 | Session pool | Transaction pool | Statement pool |
|-------------|------------|----------------|---------------|
| 维度 | 一连接一会话 | 事务结束放回池 | 单语句结束放回 |
| Pipeline 兼容性 | 完全兼容 | 仅事务内 pipeline | 仅单语句之前的 prepare 可 pipeline |
| 适用场景 | 长连接 OLTP | 高并发短事务 | 极致连接复用 |

statement pool 模式下，多个 BEGIN/COMMIT 可能落在不同后端连接上，pipeline 失去事务原子性意义。绝大多数生产环境选 transaction pool。

## 其他维度的支持详情

### 隐式流水线客户端（Async Driver）

某些异步驱动天然实现流水线，应用无需显式调用 pipeline API：

| 驱动 | 隐式机制 | 备注 |
|------|---------|------|
| asyncpg (Python, PG) | 单连接 future 队列 | execute / fetch 默认 pipeline |
| Npgsql Multiplexing (.NET, PG) | 多请求复用单连接 | 6.0+ 实验，7.0 GA |
| tokio-postgres (Rust) | mpsc 队列 | 默认按发送顺序 pipeline |
| Cassandra Driver (Java) | execute_async | 1.x+ |
| MongoDB Driver | bulkWrite | 3.6+ |
| node-postgres | 否（单连接顺序） | 不真正 pipeline |
| Connector/J (MySQL) | 否（同步） | 仅 rewriteBatched 改写 INSERT |

### 显式 Pipeline API 对比

| 数据库 / 客户端 | API 形态 | 入队 | 边界 | 拉响应 |
|--------------|---------|-----|------|-------|
| libpq (PG 14+) | C 函数 | PQsendQueryParams | PQpipelineSync | PQgetResult |
| PgJDBC | Batch | addBatch | executeBatch | getUpdateCounts |
| Npgsql | Connector batch | NpgsqlBatch.Add | ExecuteNonQuery | result reader |
| OCI | iters 参数 | OCIBindByPos + array | OCIStmtExecute | 单次返回 |
| MariaDB Connector/J | useBatchMultiSend | addBatch | executeBatch | -- |
| MongoDB | BulkWriteOperation | insertOne/updateOne | execute | BulkWriteResult |
| Cassandra | BatchStatement | add | execute | ResultSet |
| Spanner | TransactionRunner | -- | run() | -- |

### 乱序完成（Out-of-order）

绝大多数 OLTP 协议的 pipeline **必须 FIFO**：服务端按入队顺序处理，按入队顺序回复。乱序完成需要协议帧带 request_id：

| 引擎 | 乱序支持 | 机制 |
|------|---------|-----|
| HTTP/2 (BigQuery, Snowflake) | 是 | stream_id |
| gRPC (Spanner, InfluxDB 3.x) | 是 | stream_id |
| Cassandra CQL | 是 | stream id（16 位） |
| MongoDB OP_MSG | 是 (unordered bulk) | requestId |
| PostgreSQL v3 | 否 | 协议无请求 id |
| MySQL Protocol | 否 | -- |
| TDS | 否（单 RPC 内顺序） | -- |
| Oracle Net8 | 否 | -- |

CQL 的 stream id 是有意设计：单个 TCP 连接可承载 32k 个并发请求，配合 Java driver 的 connection-per-host 池实现高扇出。这也解释了为什么 CQL/MongoDB 应用模型默认是异步的，而 OLTP（PG/MySQL）应用默认是同步的。

## 客户端 API 实战示例

### libpq Pipeline（C，PG 14+）

```c
#include <libpq-fe.h>

int main(void) {
    PGconn *conn = PQconnectdb("host=localhost dbname=test");

    if (PQenterPipelineMode(conn) == 0) { /* error */ }

    /* 批量插入 1000 行 */
    PGresult *res;
    for (int i = 0; i < 1000; i++) {
        const char *vals[2] = { ids[i], names[i] };
        if (!PQsendQueryParams(conn,
                "INSERT INTO users (id, name) VALUES ($1, $2)",
                2, NULL, vals, NULL, NULL, 0)) {
            /* error */
        }
    }
    PQpipelineSync(conn);

    /* 拉取 1000 个 PGRES_COMMAND_OK + 1 个 PGRES_PIPELINE_SYNC */
    for (int i = 0; i <= 1000; i++) {
        res = PQgetResult(conn);
        if (PQresultStatus(res) == PGRES_PIPELINE_SYNC) break;
        if (PQresultStatus(res) != PGRES_COMMAND_OK) { /* handle error */ }
        PQclear(res);
        PQgetResult(conn);  /* skip NULL terminator */
    }

    PQexitPipelineMode(conn);
    PQfinish(conn);
}
```

### PgJDBC Pipeline Batch（Java）

```java
String sql = "INSERT INTO users (id, name) VALUES (?, ?)";
try (PreparedStatement ps = conn.prepareStatement(sql)) {
    for (int i = 0; i < 1000; i++) {
        ps.setInt(1, ids[i]);
        ps.setString(2, names[i]);
        ps.addBatch();
    }
    int[] counts = ps.executeBatch();  // 协议层 pipeline 发送
}
```

JDBC URL 加 `reWriteBatchedInserts=true` 时 PgJDBC 会进一步把上述拼成一个 multi-row INSERT；这是 SQL 层的优化，与 pipeline 协议层正交。

### Npgsql Multiplexing（.NET）

```csharp
// Connection string: "Multiplexing=true;Host=...;..."
var batch = new NpgsqlBatch(conn);
for (int i = 0; i < 1000; i++) {
    var cmd = new NpgsqlBatchCommand("INSERT INTO users (id, name) VALUES ($1, $2)");
    cmd.Parameters.AddWithValue(ids[i]);
    cmd.Parameters.AddWithValue(names[i]);
    batch.BatchCommands.Add(cmd);
}
await batch.ExecuteNonQueryAsync();
```

### asyncpg（Python）

```python
import asyncpg

async def bulk_insert(conn, rows):
    await conn.executemany(
        "INSERT INTO users (id, name) VALUES ($1, $2)", rows
    )
    # asyncpg 默认 pipeline，rows 内部按 PG protocol pipelined
```

### MySQL Connector/J（Java，rewriteBatchedStatements）

```java
// JDBC URL: jdbc:mysql://...?rewriteBatchedStatements=true
String sql = "INSERT INTO users (id, name) VALUES (?, ?)";
try (PreparedStatement ps = conn.prepareStatement(sql)) {
    for (int i = 0; i < 1000; i++) {
        ps.setInt(1, ids[i]);
        ps.setString(2, names[i]);
        ps.addBatch();
    }
    ps.executeBatch();
    // 实际发送: INSERT INTO users (id, name) VALUES (1,'a'),(2,'b'),...,(1000,'zz')
}
```

注意这是 SQL 层的 multi-value insert，不是真协议流水线。MariaDB Connector/J 的 useBatchMultiSend 才是协议级。

### Oracle JDBC sendBatch

```java
String sql = "INSERT INTO users (id, name) VALUES (?, ?)";
try (PreparedStatement ps = conn.prepareStatement(sql)) {
    ((OraclePreparedStatement) ps).setExecuteBatch(100);
    for (int i = 0; i < 1000; i++) {
        ps.setInt(1, ids[i]);
        ps.setString(2, names[i]);
        ps.executeUpdate();  // 内部缓冲，每 100 次 sendBatch
    }
    ((OraclePreparedStatement) ps).sendBatch();
}
```

### Cassandra Java Driver Async

```java
PreparedStatement ps = session.prepare("INSERT INTO users (id, name) VALUES (?, ?)");

List<CompletionStage<AsyncResultSet>> futures = new ArrayList<>();
for (int i = 0; i < 1000; i++) {
    futures.add(session.executeAsync(ps.bind(ids[i], names[i])));
}
// 等所有完成
CompletableFuture.allOf(
    futures.stream().map(CompletionStage::toCompletableFuture)
        .toArray(CompletableFuture[]::new)
).join();
```

### MongoDB BulkWrite（Java）

```java
List<WriteModel<Document>> writes = new ArrayList<>();
for (int i = 0; i < 1000; i++) {
    writes.add(new InsertOneModel<>(new Document("id", ids[i]).append("name", names[i])));
}
BulkWriteResult result = collection.bulkWrite(writes,
    new BulkWriteOptions().ordered(false));  // unordered: 服务端可乱序提交
```

## Spanner / 分布式事务的 pipeline 形态

Google Spanner 的 client library 通过 gRPC 走单 stream，BatchUpdate API 把多条 SQL 一次发给 leader spanserver：

```python
def insert_users(transaction):
    transaction.batch_update([
        "INSERT INTO Users (id, name) VALUES (1, 'a')",
        "INSERT INTO Users (id, name) VALUES (2, 'b')",
        "INSERT INTO Users (id, name) VALUES (3, 'c')",
    ])

database.run_in_transaction(insert_users)
```

Spanner 的 TransactionRunner 把 BatchUpdate / Mutation 缓冲，commit 时一并写入，与 PG pipeline 的差异：

| 维度 | PG pipeline | Spanner BatchUpdate |
|------|-------------|--------------------|
| 协议 | PG v3 | gRPC |
| 时机 | 客户端主动 push | 客户端 SDK 自动收集 |
| 错误中止 | Sync 屏障内整体 abort | 单条失败可继续 |
| 跨 region | 需手动 retry | TrueTime 协调 |
| 串行度 | 严格 FIFO | 协调器并行 |

YugabyteDB 的 PG 接口继承 libpq pipeline；其 YCQL 接口走 Cassandra Java driver async，两端语义不同。

## 二进制格式与 pipeline 的协同

PG pipeline 通常配合 binary format 使用，进一步省去文本编码/解码开销：

```c
PQsendQueryParams(conn, sql, n_params,
                  paramTypes,      /* 类型 OID */
                  paramValues,     /* 二进制字节指针 */
                  paramLengths,    /* 长度 */
                  paramFormats,    /* 1 = binary */
                  /*resultFormat=*/1);  /* 1 = binary */
```

binary format 的 4 字节 int32 比文本 "1234567" 节省 60% 字节，pipeline 时这些字节差距乘以批大小，对带宽敏感场景显著。

MySQL 的 prepared statement（COM_STMT_EXECUTE）默认走 binary protocol。PG 文本 vs 二进制由客户端选择，pgcrypto 等扩展在 binary format 下省略 hex 转换。

## 流水线在 OLTP 应用模式中的位置

不同应用工作流对 pipeline 的依赖程度差异很大：

| 应用模式 | RTT 数 / 事务 | pipeline 收益 |
|---------|-------------|--------------|
| 单 SELECT/UPDATE | 1 | 几乎无收益 |
| ORM 一次取多对象 | N+1（lazy loading）| 巨大（解决 N+1 问题） |
| 复杂业务事务 (5-10 条 DML) | 5-10 | 显著（5-10 倍延迟降低） |
| 批量 ETL 写入 | 1000+ | 可与 COPY/LOAD 比较 |
| 长事务（含外部调用） | 不固定 | 取决于 DB 部分占比 |
| 报表查询（单大 SELECT） | 1 | 无 |

ORM 的 N+1 问题是 pipeline 最大的潜在受益场景：Hibernate 默认 lazy loading 时一次 SELECT parent + N 次 SELECT child；如果驱动支持 pipeline，可以把 N 个 child select 一次发出。但 Hibernate 目前不主动开启 pipeline，需要用户切换到 fetch=join 或 batch=N 设置。

## 流水线的协议级压缩

部分协议在 pipeline 上叠加压缩：

| 引擎 | 协议压缩 | 备注 |
|------|---------|------|
| MySQL | CLIENT_COMPRESS (zlib) | 4.0+，pipeline 后压缩比反而更高 |
| PostgreSQL | 14+ libpq compression | scram-sha-256 之后协商 |
| Snowflake | HTTPS gzip / Arrow IPC | 默认开启 |
| ClickHouse | LZ4 / ZSTD native | 服务端默认压缩 |
| Spanner | gRPC gzip | 默认开启 |
| MongoDB | OP_COMPRESSED | 3.6+，snappy/zlib/zstd |

pipeline 后单批数据更大，压缩字典可重用，压缩率从单独压缩的 30% 提升到 60%+。

## 历史时间线

| 年份 | 事件 |
|------|------|
| 1999 | Oracle 8i 引入 OCI Array DML |
| 2003 | Oracle 10g OCIStmtExecute(iters>1) 通用化批 DML |
| 2003 | PostgreSQL 7.4 Extended Query 协议（理论支持流水线但客户端未用） |
| 2004 | MySQL 4.1 加入 CLIENT_MULTI_STATEMENTS |
| 2007 | Cassandra 项目启动，CQL 协议设计 stream id |
| 2010 | PgJDBC addBatch 在协议层实现 batched extended query |
| 2014 | PgJDBC 9.4 PipelineBatch API 显式开放 |
| 2017 | MariaDB 10.2 COM_STMT_BULK_EXECUTE |
| 2017 | MongoDB 3.6 OP_MSG 替代 OP_QUERY，原生 bulk |
| 2019 | CockroachDB 19.2 内部 pipelined writes 优化 |
| 2021-09 | PostgreSQL 14 libpq Pipeline Mode 正式开放 |
| 2021-11 | Npgsql 6.0 Multiplexing |
| 2023-10 | PgBouncer 1.21 pipelining 透传支持 |
| 2024 | Databricks Connector pipeline 改进 |
| 2026 | Arrow Flight SQL pipeline 标准化讨论 |

## 流水线下的事务语义陷阱

### 1. 隐式事务 vs 显式事务

PostgreSQL pipeline 中如果不显式 BEGIN，每条命令是独立的 implicit 事务。批量 INSERT 不带 BEGIN/COMMIT 会变成 N 个独立提交，性能反而比一次 COMMIT 差很多（每条都 fsync）。正确做法：

```c
PQsendQueryParams(conn, "BEGIN", ...);
for (i = 0; i < N; i++) PQsendQueryParams(conn, "INSERT ...", ...);
PQsendQueryParams(conn, "COMMIT", ...);
PQpipelineSync(conn);
```

### 2. 错误传播：是否需要 SAVEPOINT

PG pipeline 在事务里遇到错误会跳过到下一个 Sync，整个事务进入 abort 状态。如果想容忍单条失败：

```sql
BEGIN;
SAVEPOINT s1; INSERT ...; RELEASE SAVEPOINT s1;
SAVEPOINT s2; INSERT ...; RELEASE SAVEPOINT s2;
...
COMMIT;
```

每个 SAVEPOINT/RELEASE 是独立命令，仍可 pipeline；只是在某条 INSERT 失败时，要发 ROLLBACK TO 而非继续。

MySQL multi-statement 默认遇错继续（INSERT ... ON DUPLICATE KEY 的语义）；JDBC executeBatch 在 SQL Server/Oracle 的行为依赖 `BATCH_UPDATE_EXCEPTION` 配置。

### 3. 隔离级别与 pipeline 的预读

读已提交（Read Committed）下，pipeline 中前一条 SELECT 的可见性取决于该条 SELECT 进入 executor 的时刻，而非客户端发出时刻。流水线缩短了客户端等待时间，但服务端仍按收到顺序立即执行，因此 RC 的语义与同步模式一致。

可重复读（Repeatable Read）下事务内所有读看到的快照是事务开始时的版本，pipeline 不影响。

### 4. 与连接池的事务边界

transaction pool 模式下，同一连接对象在事务结束（COMMIT/ROLLBACK）后会还回池中。如果 pipeline 在 COMMIT 之后还排了几条命令（被池误判为新事务），可能落到错误连接。正确做法：每个事务的 pipeline 必须以 PQpipelineSync + COMMIT 收尾。

### 5. 取消（Cancel）与 pipeline

PG 用独立的 CancelRequest（CN）连接发送取消，TDS 用 attention 包；MySQL 没有取消机制（除非杀连接）。pipeline 中已发出的命令一旦在服务端开始执行，取消语义依赖具体协议，应用层不应假设"客户端 cancel 会立刻终止 pipeline 中剩余命令"。

## 性能影响因素

### RTT 与 pipeline 收益

```
单事务 N 条命令的延迟模型：
  同步: N × RTT + N × server_time
  pipeline: 1 × RTT + N × server_time + 1 × RTT (拉最后响应)

收益: (N-2) × RTT ≈ 与 N 和 RTT 成正比
```

### 批大小对吞吐量的影响

并非越大越好：

- 网络包大小：超过 MSS（约 1460B）会多次 TCP 分片
- 服务端缓冲：libpq 服务端默认 8KB 接收缓冲，过大需 TCP 多次填充
- 内存压力：服务端要在执行结束前把所有响应存在缓冲区
- 错误回滚：批越大，一条失败导致的重试代价越大

实测在 1 GbE LAN 下 PG pipeline 批大小 100-500 是吞吐量拐点，1 ms RTT 跨 AZ 时拐点上移到 1000-2000，10 ms RTT 跨地域时甚至 5000+ 仍有提升。

### CPU 减负

服务端处理一批连续 RPC 比离散 RPC 减少：

- TCP recv 系统调用：从 N 次降到几次
- libpq 协议帧解析：可在一次 epoll wakeup 内串行解析
- 连接 pool 上下文切换：transaction pool 一次切换处理整批

## 设计争议

### 流水线为什么不是默认开启？

历史原因：libpq 在 90 年代设计时为简化 client 实现，把每个 PQexec 都包成同步请求。改默认会破坏现有应用的语义假设（如基于 PQresultStatus 的串行错误检查）。PG 14 给出"显式 API"是兼容性折中。

Npgsql 和 asyncpg 后来补上"隐式 multiplexing"算是部分平衡，但仍以 opt-in 形式存在。

### 协议级 vs SQL 级 pipeline 的取舍

PG 选协议级（每条独立的 Parse/Bind/Execute），优点：参数二进制安全、可重用 plan；缺点：客户端复杂度高。

MySQL 选 SQL 级 multi-statement，优点：客户端实现简单（一个字符串）；缺点：参数必须文本拼接、SQL 注入风险、计划无法分别缓存。

中间路线 MariaDB COM_STMT_BULK_EXECUTE 是协议级 + 批参数，是 OLTP DML 的最佳形态，但 MySQL 8.x 至今未跟进。

### 乱序完成的复杂度

CQL 设计请求 stream id 是为了利用单 TCP 连接的多路复用（HTTP/2 之前的解法）；但带来了客户端必须维护 outstanding request map 的复杂度。PG/MySQL 选择 FIFO 简化客户端实现，代价是 head-of-line blocking——一条慢查询会阻塞 pipeline 后续所有命令。

应用层面对 PG/MySQL 想做并发的话，建议每核 1-2 个连接；CQL/MongoDB 单连接即可承载千级并发请求。

### 流水线与 Auto-commit 的关系

JDBC 默认 auto-commit=true，每条 update 后自动 COMMIT。在 pipeline 上下文里 auto-commit 几乎总是错误：N 次单独 COMMIT 触发 N 次 fsync，pipeline 的 RTT 收益被 fsync 抵消。生产代码必须 setAutoCommit(false) + 显式 commit()。

## 对引擎开发者的实现建议

### 1. wire 协议设计选择

新引擎设计协议时应优先考虑以下点：

```
1. 是否支持流水线？
   - 必须能解耦"客户端发送"与"等待响应"
   - 协议解析器应能在收到下一条命令前不阻塞等待执行结束

2. 是否支持乱序完成？
   - request_id / stream_id 字段（CQL 风格）
   - 优点：单连接高并发；缺点：客户端复杂度
   - 推荐 OLTP 引擎：FIFO 简单；分析引擎：可考虑乱序

3. 错误传播模型？
   - 屏障模型（PG Sync）：批失败原子回滚
   - 单条失败模型（CQL/MongoDB）：可继续
   - 推荐：两种都支持，由客户端选

4. 取消机制？
   - 带外连接（PG CancelRequest）
   - 协议内 attention 包（TDS）
   - request_id 索引（CQL）
```

### 2. 服务端 pipeline 处理

```
连接处理循环（伪代码）:

func handle_connection(conn):
    parser = ProtocolParser(conn)
    executor = QueryExecutor()

    while !conn.closed:
        // 关键：parser 不阻塞等待 executor 完成
        cmd = parser.parse_next()      // 从 socket 读出一条命令
        if cmd is None: break

        if cmd.type == Sync:
            // 等待之前所有命令完成 + 发送 ReadyForQuery
            executor.await_all()
            send(ReadyForQuery)
        elif cmd.type == Flush:
            // 强制刷新当前响应缓冲
            conn.flush()
        else:
            // 排队执行 + 立即发响应（不等下一条）
            result = executor.execute(cmd)
            send(result)

    cleanup()
```

关键不变量：协议解析器与执行器应同时进行，避免 head-of-line blocking。

### 3. 错误传播屏障

```
PostgreSQL 风格屏障:

state = NORMAL
while !done:
    cmd = parse_next()
    if state == NORMAL:
        result = execute(cmd)
        if result.error:
            send_error(result)
            state = ERROR
        else:
            send(result)
    elif state == ERROR:
        if cmd.type != Sync:
            // 跳过命令，发 PIPELINE_ABORTED
            send(PIPELINE_ABORTED)
        else:
            send(ReadyForQuery, transaction_status=FAILED)
            state = NORMAL  // 屏障重置
```

### 4. 批 DML 的内存预算

```
prepared statement + N 行参数的内存模型:

class BatchExecutor:
    fn execute_batch(stmt, rows):
        // 选项 A: 每行独立执行（保守，N 倍开销）
        for row in rows:
            execute_single(stmt, row)

        // 选项 B: 批量绑定 + 单次执行（高效）
        plan = stmt.cached_plan
        executor = plan.start_batch_execution()
        for row in rows:
            executor.bind_row(row)
            executor.exec_one()  // 复用执行上下文
        executor.finish()
```

Oracle 的 Array DML 选 B：一次 prepare/optimize，N 次 bind + execute；执行上下文（HashTable、临时表空间）复用，节省大量 setup 成本。

### 5. 跨节点 pipeline 的服务端协调

分布式数据库的 pipeline 需要在 leader/coordinator 节点缓冲响应：

```
LeaderNode:
    pending_commands = queue
    on_recv(cmd):
        pending_commands.push(cmd)
        if cmd.type in [Sync, COMMIT]:
            // 屏障：执行所有 pending，按入队顺序回响应
            results = execute_in_order(pending_commands)
            send_all(results)
            pending_commands.clear()

    on_recv(Flush):
        // 当前已执行的部分立即回响应，未执行的继续 pending
        send_all(executed_so_far)
```

CockroachDB 在此基础上把"COMMIT 之前的 INSERT"打包成单 raft 提议，进一步省去 N 个 raft round-trip。

### 6. 客户端驱动设计

```
async/await 时代的最佳实践:

class AsyncConnection:
    pending_requests = queue
    response_handlers = queue  // future map

    async fn execute(query):
        future = create_future()
        self.pending_requests.push((query, future))
        self.response_handlers.push(future)
        self.try_flush()
        return await future

    fn try_flush():
        // 批量发送 pending requests，不等响应
        for query in self.pending_requests:
            self.write_to_socket(query)
        self.pending_requests.clear()

    fn on_response(resp):
        future = self.response_handlers.pop_front()
        future.set_result(resp)
```

asyncpg、tokio-postgres、Cassandra Java Driver 均按此模型，单连接可承载数百并发请求。

### 7. 测试要点

```
1. 协议合规
   - pipeline + 错误注入: 验证 abort 状态机
   - Sync 屏障粒度: 多 Sync 错误隔离正确
   - Flush 不分隔事务: 部分响应到达后事务仍活

2. 并发安全
   - 多线程 pipeline: 每个连接独立 PRNG / future map
   - 取消注入: cancel 后 pipeline 余命令不挂起

3. 性能基准
   - RTT scan: 0.1ms / 1ms / 10ms / 100ms 对比同步 vs pipeline
   - 批大小 scan: 1 / 10 / 100 / 1000 / 10000 找拐点
   - 错误率 scan: 0% / 1% / 10% 失败下的重试代价

4. 兼容性
   - 老客户端连新服务: capability flag 协商
   - 新客户端连老服务: pipeline 优雅降级到同步
   - 连接池透传: 验证 pgbouncer / proxysql 不破坏 pipeline
```

## 监控与诊断

### 协议层流水线的可见性

| 引擎 | 监控指标 | 工具 |
|------|---------|------|
| PostgreSQL | pg_stat_statements 不区分 pipeline | tcpdump + pgsniff / pg_stat_activity |
| MySQL | performance_schema.statements_summary_by_thread_by_event_name | -- |
| SQL Server | sys.dm_exec_requests batch_text_size | Extended Events: rpc_batch_starting |
| Oracle | v$session.sql_id 序列变化 | AWR / SQL Monitor |
| CockroachDB | crdb_internal.statement_statistics | DB Console |
| Cassandra | nodetool tpstats | -- |

### 流水线性能基准命令

```bash
# pgbench 8.6+ 支持 pipeline 模式
pgbench -P 1 -T 60 --pipeline -j 4 -c 16 dbname

# psql 14+ 支持 \startpipeline / \endpipeline
psql -h host -d db
=> \startpipeline
=> SELECT 1;
=> SELECT 2;
=> \endpipeline
```

### 网络抓包验证 pipeline

```
# 截 PG 5432
tcpdump -i any -w /tmp/pg.pcap port 5432

# Wireshark Display Filter:
# pgsql.frontend && pgsql.type == "Parse"
# 看连续 Parse/Bind/Execute 之间是否有客户端等待间隙
```

观察客户端是否在两条 Execute 之间等了一个 RTT 来收 BindComplete + DataRow + CommandComplete——若有则未流水线。

## 关键发现

1. **没有 SQL 标准**：流水线纯粹是协议私有特性 + 客户端 API 拼凑而成，跨引擎差异巨大。

2. **PG 14 是工业里程碑**：2021-09 PostgreSQL 14 在 libpq 中引入显式 pipeline mode，是 OSS 数据库里第一个完整开放协议层流水线 API 的，深刻影响了后续 PG 兼容生态（CRDB / YB / Materialize / RisingWave 全部继承）。

3. **MySQL 多语句 vs PG pipeline 的取舍**：MySQL 4.1（2004）的 CLIENT_MULTI_STATEMENTS 早 PG 17 年，但语义更原始（SQL 层文本拼接，参数必须嵌入文本，SQL 注入风险）。MariaDB 10.2（2017）的 COM_STMT_BULK_EXECUTE 才是真正的协议级批 DML。

4. **Oracle 长期领先批 DML**：OCI Statement Batching/Array DML 自 8i (1999) 起就是 Oracle JDBC 默认行为，比 PG 早 22 年。但 Oracle 的"批"是 prepared statement 的多行参数，不是任意命令的协议流水线。

5. **PgBouncer 1.21 是连接池里程碑**：2023-10 PgBouncer 1.21 加入 pipelining 透传，结束了"PG 14 的 pipeline 在最常用的 PG 连接池后面失效"的尴尬。Odyssey 和 pgcat 此前已支持。

6. **乱序完成只在 NoSQL 起源协议中**：CQL（Cassandra/Scylla）、MongoDB OP_MSG、HTTP/2-基的 BigQuery / Snowflake / Spanner 设计请求 ID 支持乱序；OLTP 老协议（PG/MySQL/TDS/OCI）一律 FIFO，依赖头部阻塞模型，并发要靠多连接。

7. **NoSQL 批语义最原生**：Cassandra BATCH、MongoDB OP_MSG、CQL execute_async 是这些协议的"一等公民"，应用编程模型默认异步；OLTP 引擎的 pipeline 是后加的可选优化。

8. **跨可用区/跨地域才能看出收益**：本地 socket（RTT < 100us）pipeline 收益微弱；跨 AZ（1-2ms）3-5x；跨地域（30-100ms）10-40x。生产部署若要部署在异地容灾架构中，pipeline 几乎是必须的。

9. **rewriteBatchedStatements ≠ pipeline**：Connector/J 的 rewriteBatchedStatements 是把多个单行 INSERT 改写为 multi-value INSERT（SQL 层），不是协议流水线。MariaDB useBatchMultiSend 才是。

10. **隐式 pipelining driver 越来越多**：Npgsql 6.0 multiplexing、asyncpg、tokio-postgres 都把 pipeline 当作默认行为，不需要应用显式调用，是未来趋势。Java 生态因为 JDBC 同步 API 限制相对滞后。

11. **存储层 pipelined writes 是另一维度**：CockroachDB 的 pipelined writes、Spanner 的 commit-time fanout 是服务端内部优化，对应用 transparent；与协议层流水线（应用主动发请求批）正交。

12. **BATCH 不等于 fast**：Cassandra LOGGED BATCH 经常是反模式（协调器内存压力）；PG pipeline 中过大批可能撞 8KB 缓冲；批大小要根据 RTT、工作集大小、容错粒度综合权衡。

13. **流水线对 SSD 时代的价值**：早期数据库设计假设网络 RTT 远小于磁盘 IO，因此协议同步即可；现代 NVMe 写延迟降到 10us 后，跨 AZ 1ms 网络成为新瓶颈，pipeline 重新变得关键。

14. **协议演进中的 HTTP/2 与 gRPC 优势**：BigQuery / Snowflake / Spanner / InfluxDB 3.x 选 HTTP/2 或 gRPC 作为 wire 协议，天然支持流式和并发，省去自己造轮子。Arrow Flight SQL（2022+）正在成为新标准。

## 参考资料

- PostgreSQL: [libpq Pipeline Mode](https://www.postgresql.org/docs/current/libpq-pipeline-mode.html)
- PostgreSQL: [Frontend/Backend Protocol — Extended Query](https://www.postgresql.org/docs/current/protocol-flow.html#PROTOCOL-FLOW-EXT-QUERY)
- PostgreSQL 14 release notes (Sept 2021): pipeline support
- MySQL: [Client/Server Protocol — Multi-Statements](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_command_phase_sq_com_query.html)
- MariaDB: [COM_STMT_BULK_EXECUTE](https://mariadb.com/kb/en/com_stmt_bulk_execute/)
- Microsoft TDS Protocol Specification: [MS-TDS]
- Oracle: [OCI Programmer's Guide — Statement Batching](https://docs.oracle.com/database/121/LNOCI/oci04sql.htm)
- Cassandra: [Java Driver Asynchronous Execution](https://docs.datastax.com/en/developer/java-driver/latest/manual/async/)
- MongoDB: [OP_MSG Specification](https://www.mongodb.com/docs/manual/reference/mongodb-wire-protocol/#op_msg)
- PgJDBC: [Pipeline Batch / addBatch](https://jdbc.postgresql.org/documentation/server-prepare/)
- Npgsql: [Performance — Multiplexing](https://www.npgsql.org/doc/performance.html#multiplexing)
- asyncpg: [Pipelining queries](https://magicstack.github.io/asyncpg/current/usage.html)
- PgBouncer 1.21 release notes (Oct 2023): pipelining
- Odyssey README: connection pooler with pipelining
- pgcat README: PostgreSQL pooler with pipelining
- CockroachDB blog: [Pipelined Writes](https://www.cockroachlabs.com/blog/transaction-pipelining/)
- Heimdall Data: [Pipelining and PostgreSQL]
- ScyllaDB blog: [Shard-Aware Drivers]
