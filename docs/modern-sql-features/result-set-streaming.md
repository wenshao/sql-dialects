# 结果集流式传输 (Result Set Streaming)

一条 `SELECT * FROM big_table` 真正决定客户端会不会 OOM 的，不是 SQL 本身，而是结果集到底是"边算边送"还是"一锤子全送回来"。在亿级行的 OLAP 报表、ETL 抽数、Kafka 灌库、BI 大查询、Arrow 数据分发等场景，能否流式传输（streaming result set）直接决定应用是 200 MB 内存运行还是 200 GB 内存崩溃。流式传输是 wire 协议、客户端驱动、JDBC/ODBC API、应用程序四层共同协作的产物，任何一层默认全缓冲（buffer-all），上层的努力都白费。

## 为什么大结果集是协议级问题，不是 SQL 级问题

把一千万行结果"流"到客户端的本质是：客户端尚未读完时，服务端不能丢弃已计算行；服务端继续推送时，TCP 接收缓冲区不溢出；驱动层不一次性把所有 DataRow 装进 List；应用层 ResultSet.next() 阻塞等待网络而非等待内存释放。这条链路上任意一环把"慢慢拉"误解成"全部装入内存"，整体就退化成全缓冲。

举几个真实事故：

1. **psql 执行 `\copy (SELECT *) TO STDOUT`**：psql 客户端会把整个结果先放进 PGresult 才输出，10 GB 表直接 OOM。改用 `COPY ... TO STDOUT` 才真正流式。
2. **PgJDBC 执行 SELECT 查百万行**：默认 `fetchSize=0` 表示"一次取完"，与 `setFetchSize(1000)` 是天差地别。
3. **MySQL Connector/J 默认全缓冲**：必须设 `useCursorFetch=true` 或 `Statement.setFetchSize(Integer.MIN_VALUE)`，否则 200 万行查询客户端进程飙到 8 GB。
4. **Oracle JDBC 默认 prefetch 10 行**：批跑 ETL 时网络 RTT 成为瓶颈，单查询 10 分钟，调到 1000 后 30 秒。
5. **ClickHouse 默认 HTTP 格式 JSONEachRow**：客户端 Python urllib 的 `read()` 默认全缓冲，应该用 `iter_lines()` 流式消费。

这些问题没有一个属于 SQL 标准，全都是协议 + 驱动 + 应用三层"默认值"和"API 语义"的角力。

## 没有 SQL 标准的流式传输

ISO/IEC 9075（SQL 标准）只定义查询语义、游标语义（DECLARE / OPEN / FETCH n）和静态/动态 SQL 接口，**完全不涉及网络层结果集如何流动**。SQL/CLI（ODBC 的 ISO 化身）规定 `SQLFetch` 的语义但留给驱动实现。因此流式传输完全是：

| 维度 | 标准化情况 |
|------|----------|
| 游标 DECLARE / FETCH 语法 | 标准 (SQL:1992 / SQL:1999) |
| ResultSet 接口 (next / getXxx) | API 标准 (JDBC / ODBC / ADO.NET) |
| `Statement.setFetchSize` 语义 | API 标准定义为 *提示*，行为由驱动决定 |
| 协议层结果集分块 | **完全不标准**，每个 wire 协议自定义 |
| 服务端游标 vs 客户端游标 | 私有特性 |
| 列式流（Arrow Flight） | 事实标准（Apache Arrow 项目，2022+） |

JDBC 规范明确说 "fetchSize is a hint to the driver. The driver is free to ignore the hint."；这条灰色地带导致同样调 `setFetchSize(100)` 在 PgJDBC 是关键开关，在 SQL Server JDBC 是 RPC fetch 提示，在 Connector/J 默认被忽略。

## 支持矩阵 (45+ 引擎)

### 流式核心能力

| 引擎 | 服务端游标 | 协议级流式（无游标） | fetchSize 提示 | 列式流（Arrow） | 中途取消 |
|------|:---:|:---:|:---:|:---:|:---:|
| PostgreSQL | DECLARE CURSOR | Extended Query + MaxRows | 是 (PgJDBC) | ADBC / pg_arrow | CancelRequest 异步包 |
| MySQL | useCursorFetch | streaming (fetchSize=Integer.MIN_VALUE) | 部分 | -- | KILL QUERY (新连接) |
| MariaDB | 同 MySQL | useCursorFetch / streamResultSet | 部分 | -- | KILL QUERY |
| SQLite | -- (嵌入式) | sqlite3_step 行迭代 | -- | -- | sqlite3_interrupt() |
| Oracle | OCI 引用游标 | 行预取 (prefetch row count) | 是 (默认 10) | OCI 19c+ Arrow | OCIBreak/OCIReset |
| SQL Server | T-SQL CURSOR + RPC fetch | TDS Row mode 默认行模式流式 | 是 (Statement.setFetchSize) | -- | TDS Attention 包 |
| DB2 | DECLARE CURSOR | DRDA QRYBLKSZ | 是 | -- | INTERRUPT |
| Snowflake | -- | HTTP chunked + Arrow chunks | 是 (chunkSize) | 是 | jobs.cancel REST |
| BigQuery | Storage Read API streams | 默认 jobs.getQueryResults 分页 | pageSize | 是 (Storage API Arrow) | jobs.cancel |
| Redshift | 继承 PG DECLARE | 继承 PG Extended Query | 是 (PgJDBC) | UNLOAD only | CancelRequest |
| DuckDB | -- (嵌入式) | -- | -- | Arrow Native | duckdb_interrupt() |
| ClickHouse | -- | Native + HTTP chunked + Arrow Stream | 是 (max_block_size) | 是 (Arrow / ArrowStream) | KILL QUERY / 取消 HTTP |
| Trino | -- | HTTP REST 分页 (nextUri) | -- | Spooled chunks Arrow (Trino 412+) | DELETE /v1/query/{id} |
| Presto | -- | HTTP REST 分页 | -- | -- | DELETE query |
| Spark SQL | -- | Thrift HiveServer2 fetchSize | 是 | Arrow via Spark Connect | INTERRUPT JOB |
| Hive | -- | Thrift HiveServer2 FetchResults | maxRows | -- | CancelOperation |
| Flink SQL | -- | SQL Gateway 分批返回 | 部分 | -- | jobcancel |
| Databricks | -- | Thrift / SQL Statement Execution API + Arrow | 是 | 是 (Arrow stream) | cancel statement |
| Teradata | DECLARE CURSOR | StatementInfoParcel 行块 | 是 | -- | ABORT SESSION |
| Greenplum | DECLARE CURSOR | 继承 PG Extended Query | 是 | -- | CancelRequest |
| CockroachDB | DECLARE CURSOR (23.2+) | Extended Query MaxRows | 是 (PgJDBC) | -- | CancelRequest |
| TiDB | useCursorFetch (8.0+) | 继承 MySQL streamResultSet | 部分 | -- | KILL QUERY |
| OceanBase | useCursorFetch (MySQL 模式) / OCI (Oracle 模式) | 是 | 是 | -- | KILL QUERY |
| YugabyteDB | DECLARE CURSOR | 继承 PG | 是 | -- | CancelRequest |
| SingleStore | -- | streaming 子集 | 部分 | -- | KILL QUERY |
| Vertica | DECLARE CURSOR | 类 PG 流式 | 是 | -- | INTERRUPT STATEMENT |
| Impala | -- | HiveServer2 FetchResults | 是 | -- | CancelOperation |
| StarRocks | -- | MySQL 流式 / HTTP Stream Read | fetchSize=MIN_VALUE | -- | KILL QUERY |
| Doris | -- | MySQL 流式 / HTTP | fetchSize=MIN_VALUE | -- | KILL QUERY |
| MonetDB | -- | MAPI 行块 (replysize) | 是 (replysize) | -- | session 中断 |
| CrateDB | -- | 继承 PG Extended | 部分 | -- | KILL |
| TimescaleDB | DECLARE CURSOR | 继承 PG | 是 | -- | CancelRequest |
| QuestDB | -- | PG Extended / HTTP chunked | 部分 | -- | -- |
| Exasol | -- | WebSocket batch | 是 (resultSetMaxRows) | -- | abortQuery |
| SAP HANA | DECLARE CURSOR | 行块返回 | 是 (fetchSize) | -- | cancelStatement |
| Informix | DECLARE CURSOR | SQLI 行块 | 是 | -- | INTERRUPT |
| Firebird | DECLARE CURSOR (PSQL) | XDR 行块 (op_fetch) | 是 (FETCH_VERSION) | -- | fb_cancel_operation |
| H2 | -- | 内嵌全缓冲；远程模式分块 | 部分 | -- | -- |
| HSQLDB | -- | 行块 | 部分 | -- | -- |
| Derby | DECLARE CURSOR | DRDA 行块 | 是 | -- | -- |
| Amazon Athena | -- | GetQueryResults 分页 / Storage API | maxResults | 是 (Athena v3 Arrow) | StopQueryExecution |
| Azure Synapse | T-SQL CURSOR | TDS Row mode | 是 | -- | TDS Attention |
| Google Spanner | -- | gRPC streaming PartialResultSet | -- | -- | sessions.cancelQuery |
| Materialize | DECLARE CURSOR | SUBSCRIBE 流式推送 | 是 | -- | CancelRequest |
| RisingWave | DECLARE CURSOR | SUBSCRIBE 流式推送 | 是 | -- | CancelRequest |
| InfluxDB (3.x SQL) | -- | Arrow Flight SQL DoGet | -- | 是 (原生 Flight) | gRPC cancel |
| Databend | -- | HTTP chunked / Arrow Stream / MySQL | 是 | 是 | KILL QUERY |
| Yellowbrick | DECLARE CURSOR | 继承 PG Extended Query | 是 | -- | CancelRequest |
| Firebolt | -- | HTTPS REST 分页 | pageSize | -- | -- |
| Dremio | -- | Arrow Flight SQL DoGet | -- | 是 (原生 Flight) | gRPC cancel |
| Doris (Arrow Flight) | -- | Arrow Flight SQL (实验) | -- | 是 (实验/GA) | gRPC cancel |

> 统计：约 40+ 引擎在某种形式上支持流式传输；嵌入式（SQLite/DuckDB/H2 嵌入式）通过函数迭代天然不缓冲；纯 REST 分页型（Snowflake / BigQuery 默认 jobs.getQueryResults）虽不算"协议流"但用户态可以分页拉。Arrow Flight SQL 阵营（Dremio / InfluxDB 3.x / Doris / DuckDB 扩展）以 gRPC 流为底，是新一代列式流标准。

### Arrow Flight SQL 与 ADBC 阵营

| 项目/产品 | 角色 | 起始时间 | 协议底层 | 备注 |
|---------|------|---------|---------|------|
| Apache Arrow Flight SQL | 协议规范 | 2022-04 (Arrow 8.0) | gRPC + Arrow IPC | 列式流的事实标准 |
| ADBC (Arrow Database Connectivity) | 客户端 API | 2023-01 (ADBC 0.1) | Flight SQL / 各家原生 | "用 Arrow 描述结果集"的 JDBC |
| InfluxDB 3.x (IOx) | GA 实现 | 2023+ | Flight SQL | 查询必走 Flight |
| Dremio | GA | 2022+ | Flight SQL | 原生 Arrow 引擎 |
| DuckDB nanoarrow / flight 扩展 | 社区扩展 | 2023+ | Flight SQL | 把 DuckDB 暴露为 Flight 端点 |
| Apache Doris | 实验 → GA | 2024+ | Flight SQL | ADBC 客户端可读 |
| ClickHouse | 部分 (Arrow 格式) | 早期 | HTTP / Native (非 Flight) | 走 HTTP，不是 Flight RPC |
| BigQuery Storage Read API | 类 Flight (gRPC + Arrow) | 2018+ | gRPC + Arrow | 协议非 Flight 但格式相同 |
| Snowflake | Arrow chunks (HTTP) | 2020+ | HTTPS chunked | 非 Flight，但客户端解码 Arrow |
| Databricks | Arrow stream | 2022+ | Thrift/SQL API | 非 Flight |

### 默认行为分类

按"客户端默认要不要全缓冲"区分：

| 类别 | 引擎 | 默认行为 |
|------|------|---------|
| 默认协议级流式（行块） | ClickHouse Native, MonetDB, Trino, Spanner, Databricks, BigQuery Storage API, InfluxDB 3.x, Dremio | 服务端边算边送，客户端边收边消费 |
| 默认全缓冲，可手动开流 | PostgreSQL (libpq + psql), MySQL Connector/J, MariaDB Connector/J, Oracle JDBC, SQL Server JDBC, DB2 JDBC, Snowflake JDBC | 必须显式 fetchSize / useCursorFetch / DECLARE CURSOR |
| 嵌入式天然非缓冲 | SQLite, DuckDB, H2 (内嵌) | sqlite3_step / Pending / iterator API |
| 纯 REST 分页 | Trino HTTP, Presto, Snowflake REST, BigQuery REST, Athena, Firebolt | 客户端用 nextUri / pageToken 拉下一页 |
| 流式订阅推送 | Materialize SUBSCRIBE, RisingWave SUBSCRIBE, ClickHouse 实时表 | 服务端持续推 delta，FIFO 流式 |

## 关键结论：为什么默认全缓冲

老牌 OLTP 数据库（PG / MySQL / Oracle / SQL Server）的客户端 API 设计自 1990 年代，那时网络慢、内存便宜、查询小。把所有结果一次性拿回客户端，再调 ResultSet.next() 内存遍历是最简单的实现。三十年后的 ETL/BI 大查询场景下这成为了陷阱。**"默认全缓冲"是历史包袱，不是设计选择**。新引擎（ClickHouse / BigQuery / InfluxDB 3.x / Trino）从设计第一天就走流式，省去了这层教育成本。

## PostgreSQL Extended Query：协议天然支持，但客户端要配合

PostgreSQL 协议的 Extended Query 子协议天然支持"分批拉行"，但需要客户端正确使用。

### Extended Query 中的 Execute MaxRows

```text
1. Parse  ('P')  -- 解析 SQL 为 prepared statement
2. Bind   ('B')  -- 绑定参数到 portal
3. Execute('E') Portal=p1 MaxRows=100
                  -- 服务端只发回 100 行就停下，发 PortalSuspended
4. Execute('E') Portal=p1 MaxRows=100   -- 继续拉下一批
                  ...
5. Sync   ('S')  -- 完成
```

`Execute` 命令的 `MaxRows` 参数（int32）是 PG 协议层"分批"的核心。MaxRows = 0 表示"一次取完"。MaxRows > 0 时，服务端发完该数量行后回 `PortalSuspended ('s')` 而非 `CommandComplete ('C')`，客户端可以再发 Execute 继续拉。

PG 服务端在执行 SELECT 时会把执行计划（executor state）保存在 portal 中，下次 Execute 从中断点继续。这是"流式"的本质：服务端不一次性算完结果集，而是按需求生成。

### 但 PSQL CLI 完全不流

直接运行 `psql -c "SELECT * FROM big" > out.txt` 时 psql 还是会 OOM。原因：**psql 调用 libpq 的 PQexec 是"同步取全部"模式**，PQexec 内部走 Simple Query (Q 协议)，服务端一次性发回所有 DataRow，psql 把它们全部塞进 PGresult 才输出。

唯一例外是 psql 的 `\copy` 命令——它直接走 PG 的 COPY 子协议，逐行处理 stdout，是真流式。

### DECLARE CURSOR：SQL 层显式服务端游标

```sql
BEGIN;
DECLARE my_cursor CURSOR FOR SELECT * FROM big_table;
FETCH 1000 FROM my_cursor;     -- 取 1000 行
FETCH 1000 FROM my_cursor;     -- 再取 1000 行
...
CLOSE my_cursor;
COMMIT;
```

DECLARE CURSOR 是 SQL 标准的服务端游标语法，**必须在事务中**。事务提交前 portal 持久存在，可以反复 FETCH。`WITH HOLD` 选项让 cursor 跨事务存活但代价是 commit 时把剩余结果物化到磁盘。

### PgJDBC fetchSize 模式（必须 autoCommit=false）

PgJDBC 的精妙在于：调用 `Statement.setFetchSize(N)` 后，驱动**自动**生成 DECLARE CURSOR + FETCH N 序列，对应用透明：

```java
// 关键：必须关闭自动提交，否则 fetchSize 被忽略
conn.setAutoCommit(false);

PreparedStatement ps = conn.prepareStatement("SELECT * FROM big");
ps.setFetchSize(1000);  // 触发 PgJDBC 内部 DECLARE CURSOR

ResultSet rs = ps.executeQuery();
while (rs.next()) {
    // 每次到第 1001、2001、... 行触发新的 FETCH 1000 RPC
}
rs.close();
conn.commit();
```

PgJDBC 源码 `org.postgresql.jdbc.PgStatement.executeWithFlags` 中：

```
if (fetchSize > 0 && !connection.getAutoCommit()) {
    // 包成 DECLARE CURSOR + FETCH
    queryExecutor.execute(query, parameters, ..., fetchSize, ...);
}
```

为什么必须关闭 autoCommit？因为 PG 的 DECLARE CURSOR 必须在显式事务中。autoCommit=true 时每条语句都隐式 BEGIN/COMMIT，cursor 立即被销毁，无法 FETCH 第二批。

### libpq 的单行模式 (single-row mode)

PostgreSQL 9.2 加入 `PQsetSingleRowMode`，libpq C 客户端可以让 PQgetResult 每行返回一个 PGresult：

```c
PGconn *conn = PQconnectdb(...);
PQsendQuery(conn, "SELECT * FROM big");
PQsetSingleRowMode(conn);

while ((res = PQgetResult(conn))) {
    if (PQresultStatus(res) == PGRES_SINGLE_TUPLE) {
        process_row(res, 0);  // 单行 PGresult
    } else if (PQresultStatus(res) == PGRES_TUPLES_OK) {
        // 最后一个空 PGresult 标识结束
    }
    PQclear(res);
}
```

但单行模式仍然要服务端一次性发完所有行，只是客户端逐行处理 + 不在 libpq 里囤积。要服务端按需算，仍然要走 DECLARE CURSOR 路径。

### 取消正在执行的查询

PG 协议有专门的 `CancelRequest` 包，**通过新建一条 TCP 连接发送**，把目标 backend 的 PID 和 cancel key 传过去：

```
CancelRequest:
  Length : int32 = 16
  CancelRequestCode : int32 = 80877102
  ProcessID : int32     -- 目标 backend PID
  CancelKey : int32     -- StartupMessage 时拿到的 secret
```

为什么要新建连接？因为原连接被服务端阻塞在等结果，没法在它上面发别的命令。CancelRequest 是 PG 协议唯一可以"插队"的命令。PgJDBC 的 `Statement.cancel()` 内部就是新建一条短连接发这个包。

## MySQL Connector/J 的两种流式模式与陷阱

MySQL Connector/J 提供两种"流式"模式，语义、性能、适用场景完全不同。

### 模式一：useCursorFetch=true（服务端游标）

```java
// JDBC URL 加参数
String url = "jdbc:mysql://host:3306/db?useCursorFetch=true&defaultFetchSize=500";

PreparedStatement ps = conn.prepareStatement("SELECT * FROM big");
ps.setFetchSize(500);  // 与 defaultFetchSize 同义
ResultSet rs = ps.executeQuery();
```

底层走 MySQL 协议的 **COM_STMT_FETCH**：

```
COM_STMT_PREPARE → 服务端缓存 stmt_id
COM_STMT_EXECUTE → 服务端打开服务端游标，返回 0 行
COM_STMT_FETCH stmt_id, 500 → 服务端返回 500 行
COM_STMT_FETCH stmt_id, 500 → 再 500 行
...
COM_STMT_RESET / COM_STMT_CLOSE
```

注意服务端游标在 MySQL 中：

- **必须是 prepared statement**（COM_STMT_*）
- 服务端用临时表（MEMORY 引擎或 InnoDB 临时表）物化结果
- 物化时机：COM_STMT_EXECUTE 时一次性算完整个结果，写入临时表
- "流式"是 fetch 阶段从临时表分块读，不是真正的边算边发

因此 MySQL useCursorFetch 仍然要等查询完全计算完，对超大结果只是"客户端不 OOM 但服务端会用临时表"。

### 模式二：streamResultSet（fetchSize=Integer.MIN_VALUE）

```java
PreparedStatement ps = conn.prepareStatement("SELECT * FROM big",
    ResultSet.TYPE_FORWARD_ONLY, ResultSet.CONCUR_READ_ONLY);
ps.setFetchSize(Integer.MIN_VALUE);  // -2147483648 是"魔法值"
ResultSet rs = ps.executeQuery();
```

底层不开服务端游标，而是 Connector/J 把 socket 切换为"逐行读取" 模式：

- 服务端正常返回结果集（逐行从执行计划吐到 socket 缓冲区）
- 客户端每次 `rs.next()` 从 socket 读一行
- 由于 TCP 流控，服务端在客户端来不及消费时被反压（backpressure）

这是真正的"边算边发"流式，但代价：

1. **该连接在 ResultSet 关闭前不能执行任何其他语句**——因为 socket 还在被结果集占用
2. 客户端不能调 `setMaxRows(N)` 或 `LIMIT` 之外的截断
3. 应用必须及时消费，否则服务端长事务、锁等待
4. 任何客户端阻塞都会导致服务端 thread 阻塞在 send（高 QPS 下严重）

### Connector/J streamResultSet 陷阱

**陷阱 1：必须读完或主动关闭**

```java
ResultSet rs = ...;  // streaming
rs.next();
rs.next();
rs.close();  // 必须显式关闭！否则连接占用直到超时
```

如果中途抛异常没关 ResultSet，连接进入"等数据被消费"状态，下次 ResultSet.executeQuery() 报错 "Streaming result set ... is still active"。HikariCP 等池化连接如不正确处理会被回收。

**陷阱 2：与 setMaxRows 冲突**

`Statement.setMaxRows(100)` 在普通模式下让服务端 LIMIT 100；在 streaming 模式下被忽略，服务端仍发全部数据，客户端读到 100 后必须 close 才能停止。

**陷阱 3：与连接池的相互作用**

部分连接池（DBCP / Druid）在 conn.close() 时若 ResultSet 未关，会"温柔丢弃"包，导致 socket 中残留半个 packet，下次借出连接时报 "Got packets out of order"。HikariCP 通过 keepalive 心跳能检测但不能修复。

### 第三种：MySQL X DevAPI（异步流）

MySQL 8.0 引入 X Protocol（端口 33060），原生支持异步迭代器：

```java
// X DevAPI Java 8+
SqlResult res = session.sql("SELECT * FROM big").execute();
res.fetchAllAsync().thenAccept(rows -> ...);
```

X Protocol 走 protobuf + HTTP/2 多路复用，结构上比 MySQL 经典协议先进，但生态远弱于经典协议。

## SQL Server TDS Row 模式与 fetchSize

SQL Server 的 TDS（Tabular Data Stream）协议默认走 **Row mode**：服务端执行查询时**逐行**通过 TDS Row token (0xD1 / 0xD3) 发送，客户端在 `rs.next()` 时从 socket 拉一行。

```
TDS Token Stream:
  COLMETADATA (0x81)  -- 列元数据
  ROW (0xD1 / NBCROW 0xD2) ...  -- 每行一个 token
  DONE (0xFD)         -- 结果集结束
```

这与 PG/MySQL 的"DataRow 一次发完"截然不同——TDS 行模式天然流式。但 SQL Server JDBC（mssql-jdbc）默认仍会在内存里缓冲整个结果集到 ResultSet 内部 List，除非：

```java
// 显式触发流式
Statement stmt = conn.createStatement(
    ResultSet.TYPE_FORWARD_ONLY, ResultSet.CONCUR_READ_ONLY);
stmt.setFetchSize(100);  // 提示 JDBC 不要全缓冲
ResultSet rs = stmt.executeQuery("SELECT * FROM big");
// 此时 rs.next() 边读边消费 socket
```

mssql-jdbc 的 `responseBuffering=adaptive` 是默认，意味着它会缓冲一部分以便 ResultSet.absolute / first / last 等可滚动操作。要强制流式：`responseBuffering=adaptive` + `selectMethod=cursor`，让 SQL Server 端开真正的服务端游标，PRC fetch 拉块。

### TDS Attention 包：唯一的中途取消机制

```
TDS Header:
  Type = 0x06 (Attention)
  Status = 0x01 (End of message)
```

客户端发 0x06 包，服务端中断当前 RPC、发 DONE token，客户端清空到 DONE 为止。这与 PG 的 CancelRequest 思路一致，但 TDS 通过同一连接发送，不需要新建连接——这是 TDS 的设计优势。

## Oracle OCI Prefetch：1999 年起的隐式流

Oracle 在 OCI（Oracle Call Interface）层面早在 8i（1999）就支持 **prefetch row count / prefetch memory**：客户端在 OCIStmtFetch 时一次拉 N 行，缓存在客户端，应用 OCIStmtFetch 拿下一行只是读本地缓存：

```c
ub4 prefetch_rows = 1000;
OCIAttrSet(stmt, OCI_HTYPE_STMT, &prefetch_rows, sizeof(ub4),
           OCI_ATTR_PREFETCH_ROWS, err);

OCIStmtExecute(svc, stmt, err, 0, 0, NULL, NULL, OCI_DEFAULT);

while (OCIStmtFetch2(stmt, err, 1, OCI_FETCH_NEXT, 0, OCI_DEFAULT) == OCI_SUCCESS) {
    // 实际每 1000 行才网络往返一次
}
```

Oracle JDBC（ojdbc）默认 prefetch 10 行，可通过：

```java
((OracleStatement)stmt).setRowPrefetch(1000);
// 或者
stmt.setFetchSize(1000);
```

**默认值 10 来自 1990 年代窄带连接假设**，现代百兆/千兆链路应调到 1000-5000，否则纯网络 RTT 主导查询延迟。同样的查询 prefetch 10 跑 10 分钟，prefetch 1000 跑 30 秒在 Oracle JDBC ETL 场景中是常见现象。

### Oracle 的 OCI 19c+ Arrow 支持

Oracle Database 19c 起 OCI 内部把行结果集转换为 Arrow 列式格式（实验特性），客户端可以零拷贝消费。这是 Oracle 对 Arrow Flight SQL 的回应。

### Oracle 引用游标 (REF CURSOR)

```sql
DECLARE
    rc SYS_REFCURSOR;
BEGIN
    OPEN rc FOR SELECT * FROM big;
    -- 把 rc 作为 OUT 参数返回给客户端
END;
```

客户端拿到 REF CURSOR 后用 OCIStmtFetch 流式消费，与服务端游标语义相同。这是 PL/SQL 把"返回结果集"接口化的方式。

## ClickHouse：天然流式 + Native + HTTP + Arrow

ClickHouse 的所有协议默认都是流式——服务端执行时逐 block（默认 65536 行）从 pipeline 算出，立刻通过 socket 发给客户端。客户端的 ClickHouseDataReader 也是 block 级迭代器。

### Native TCP 协议

```
请求: ClientPacket QUERY (1)
  query_id, settings, query_text, ...

响应: ServerPacket DATA (1) ...
  block: header columns count, rows count, column1 data, column2 data, ...
ServerPacket DATA (1) ...   -- 又一个 block
ServerPacket DATA (1) ...
...
ServerPacket EndOfStream (5)
```

每个 DATA 包就是一个 block，列存格式打包。客户端可以在收到第一个 block 时就开始处理，无需等查询完成。

### HTTP 协议的流式

```
GET /?query=SELECT+*+FROM+big&max_block_size=8192 HTTP/1.1
Host: ch:8123

→ HTTP/1.1 200 OK
   Transfer-Encoding: chunked
   X-ClickHouse-Format: Native (or JSONEachRow / Arrow / etc)

   <chunk: block 1>
   <chunk: block 2>
   ...
```

HTTP Transfer-Encoding: chunked 让 ClickHouse 服务端边算边推 chunk。客户端用 Python `requests` 必须 `stream=True` + `iter_content()` 才能流式消费：

```python
import requests
r = requests.post("http://ch:8123/?query=SELECT * FROM big",
                  stream=True)
for chunk in r.iter_content(chunk_size=65536):
    process(chunk)  # 边收边消费
r.close()
```

如果直接 `r.text` / `r.content`，requests 库会全缓冲到内存，与协议层流式无关。

### ClickHouse Arrow Stream 格式

```
SELECT * FROM big FORMAT ArrowStream
```

服务端把每个 block 直接序列化为 Arrow IPC stream message，客户端用 pyarrow / arrow-rs / arrow2 流式解码。这是 ClickHouse 暴露给 Arrow 生态的"零拷贝路径"，性能比 JSON 快 10-50 倍。

### ClickHouse 的 max_block_size

```
SELECT * FROM big SETTINGS max_block_size = 8192;
```

`max_block_size` 控制每个 block 多少行（默认 65536）。小 block 降低延迟（首字节更快），大 block 提高吞吐（每 block 摊薄元数据开销）。OLAP ETL 一般 65536；交互式查询前几千行可以小 block 8192。

## BigQuery Storage Read API：读级 Arrow 流

BigQuery 默认走 **jobs.getQueryResults** REST 分页（每页 100k 行 JSON），但要真流式读 TB 级表必须用 **Storage Read API**（gRPC + Arrow IPC）：

```python
from google.cloud import bigquery_storage_v1

client = bigquery_storage_v1.BigQueryReadClient()
session = client.create_read_session(
    parent="projects/myproj",
    read_session={
        "table": "projects/myproj/datasets/ds/tables/big_table",
        "data_format": bigquery_storage_v1.DataFormat.ARROW,
    },
    max_stream_count=8,  # 并行 8 流
)

for stream in session.streams:
    reader = client.read_rows(stream.name)
    for batch in reader.rows().to_arrow_iterable():
        process_arrow_batch(batch)
```

Storage Read API 的关键设计：

1. **可恢复的 ReadSession**：连接断了用同一个 session 重连，从中断点继续，不丢行不重复
2. **多流并行**：服务端把表切分成 N 个 stream（一般按物理分区），客户端可以并发读
3. **Arrow IPC 格式**：列式打包，客户端零拷贝
4. **服务端流控**：客户端慢了服务端不会无限缓冲，gRPC 反压

这是云数仓里"为大查询设计的流式"，与 OLTP 协议的流式语义不同——更像分布式 scan。

## Arrow Flight SQL 深度剖析

Apache Arrow Flight SQL（2022 年 4 月 Arrow 8.0 发布）是新一代列式流协议，定位是"统一替代 ODBC/JDBC 的 wire 协议"。

### 协议结构

Flight SQL 基于 **Apache Arrow Flight RPC**（Arrow 0.14 引入，2019），底层是 gRPC + Arrow IPC：

```protobuf
service FlightService {
    rpc Handshake(stream HandshakeRequest) returns (stream HandshakeResponse);
    rpc ListFlights(Criteria) returns (stream FlightInfo);
    rpc GetFlightInfo(FlightDescriptor) returns (FlightInfo);
    rpc DoGet(Ticket) returns (stream FlightData);   // 取数据流
    rpc DoPut(stream FlightData) returns (stream PutResult);  // 上传
    rpc DoExchange(stream FlightData) returns (stream FlightData);  // 双向
    rpc DoAction(Action) returns (stream Result);
}
```

Flight SQL 在此之上定义了 SQL 特有的命令（Statement / PreparedStatement / GetTables / GetSchemas）：

```protobuf
message CommandStatementQuery {
    string query = 1;
    bytes transaction_id = 2;
}

message CommandPreparedStatementQuery {
    bytes prepared_statement_handle = 1;
}
```

### 典型查询流程

```
1. 客户端 → GetFlightInfo(CommandStatementQuery{ "SELECT *" })
   服务端 → FlightInfo {
              endpoints: [
                Endpoint { ticket: "T1", locations: ["grpc://shard1"] },
                Endpoint { ticket: "T2", locations: ["grpc://shard2"] },
              ],
              schema: <Arrow schema bytes>,
              total_records: -1,  // 未知
              total_bytes: -1
           }

2. 客户端 → DoGet(Ticket{"T1"}) (串行或并行)
   服务端 → stream FlightData {
              data_header: <Arrow IPC schema>,
              data_body: <Arrow record batch bytes>,
            } (一个 batch)
   服务端 → stream FlightData { ... } (又一个 batch)
   ...
```

关键设计点：

1. **元数据 / 数据分离**：GetFlightInfo 返回端点列表，客户端 DoGet 拉数据。可以让客户端直连数据所在节点（数据本地化）。
2. **多端点并行**：客户端可以同时对 N 个 endpoint 发 DoGet，并行读分片结果。
3. **零拷贝传输**：Arrow record batch 在网络上的字节布局与内存中相同，客户端 mmap 进 Arrow array 不复制。
4. **schema 先行**：data_header 在第一个 batch 之前到达，客户端可预分配 reader。

### Flight SQL 与传统 wire 协议的对比

| 维度 | 传统协议 (PG / MySQL / TDS) | Arrow Flight SQL |
|------|-----------------------------|------------------|
| 数据格式 | 行式（DataRow）+ 文本/二进制 | 列式（Arrow IPC） |
| 序列化 | 每行解码 + 类型转换 | 零拷贝，列直接 mmap |
| 并发 | 单连接 FIFO | 多 endpoint 并行 |
| 流控 | TCP 反压 | gRPC HTTP/2 反压 |
| 元数据 | 每查询一次 RowDescription | FlightInfo 含 schema |
| 取消 | CancelRequest / Attention / KILL | gRPC Cancel |
| 认证 | SCRAM / Kerberos / IAM | gRPC interceptor (header) |
| 加密 | TLS over TCP | TLS over HTTP/2 |

Arrow Flight SQL 在大结果集（>10 万行）场景下性能比 JDBC over wire 协议快 5-30 倍，主要来自零拷贝和列式批处理。但对小查询（< 1k 行）gRPC + Arrow 的元数据开销反而比 PG 协议大。

### ADBC：用 Arrow 做的 JDBC

ADBC（Arrow Database Connectivity，2023-01 发布 0.1）是面向应用的客户端 API：

```python
import adbc_driver_postgresql.dbapi as pg_adbc
import pyarrow as pa

with pg_adbc.connect("postgresql://...") as conn:
    with conn.cursor() as cursor:
        cursor.execute("SELECT * FROM big")
        # 直接拿 Arrow 表
        table: pa.Table = cursor.fetch_arrow_table()
        # 或流式
        reader: pa.RecordBatchReader = cursor.fetch_record_batch()
        for batch in reader:
            process(batch)
```

ADBC 支持的后端：

- **adbc_driver_flightsql**: 任何 Flight SQL 服务（Dremio、InfluxDB 3.x、Doris 等）
- **adbc_driver_postgresql**: 通过 libpq + COPY BINARY 转 Arrow
- **adbc_driver_snowflake**: 走 Snowflake REST + Arrow chunks
- **adbc_driver_sqlite / adbc_driver_duckdb**: 嵌入式

ADBC 的设计目标是"零拷贝 + 跨语言一致"。Java/Go/Rust/Python 都有客户端，结果都是 Arrow 列式数据。

## Snowflake / Databricks / Redshift 的 Arrow chunks

虽然不走 Flight SQL，但近年云数仓客户端（Snowflake JDBC、Databricks JDBC、Redshift Data API）都把结果集编码为 **Arrow IPC chunks** 通过 HTTPS chunked 推下来：

### Snowflake

```
POST /queries/v1/query-request HTTP/1.1
{ "sqlText": "SELECT * FROM big", ... }

→ HTTP/1.1 200 OK
   Transfer-Encoding: chunked

   { "data": { "chunks": [
       { "url": "https://s3-presigned/chunk1.arrow", "rowCount": 65536 },
       { "url": "https://s3-presigned/chunk2.arrow", "rowCount": 65536 },
       ...
   ]}}
```

服务端把结果集切成 N 个 Arrow IPC 文件丢到 S3，返回 presigned URL。客户端并行下载 chunk。这是云数仓"借用对象存储做流"的典型模式，对 GB 级结果集吞吐极高。

### Databricks SQL Statement Execution API

```
POST /api/2.0/sql/statements/execute
{
    "statement": "SELECT * FROM big",
    "format": "ARROW_STREAM",
    "disposition": "EXTERNAL_LINKS"
}

→ 200 OK
   { "result": { "external_links": [
       { "external_link": "https://storage/chunk1", "expiration": "..." },
       ...
   ]}}
```

Databricks 走相同思路。external_links 是 Azure Blob / S3 的 SAS URL，每个文件是 Arrow IPC。

## DECLARE CURSOR 跨引擎对比

```sql
-- PostgreSQL / Greenplum / YugabyteDB / CockroachDB / Materialize / RisingWave
BEGIN;
DECLARE cur CURSOR FOR SELECT * FROM big;
FETCH 1000 FROM cur;
CLOSE cur;
COMMIT;

-- Oracle PL/SQL（隐含游标 + REF CURSOR）
DECLARE
    rc SYS_REFCURSOR;
BEGIN
    OPEN rc FOR SELECT * FROM big;
    FETCH rc INTO row_buffer;
    CLOSE rc;
END;

-- SQL Server T-SQL
DECLARE @cur CURSOR;
SET @cur = CURSOR FORWARD_ONLY READ_ONLY FAST_FORWARD
    FOR SELECT * FROM big;
OPEN @cur;
FETCH NEXT FROM @cur INTO @col1, @col2;
CLOSE @cur;
DEALLOCATE @cur;

-- MySQL / MariaDB（仅在存储过程中）
DELIMITER //
CREATE PROCEDURE p()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE cur CURSOR FOR SELECT id FROM big;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO @id;
        IF done THEN LEAVE read_loop; END IF;
    END LOOP;
    CLOSE cur;
END//
```

MySQL/MariaDB 的游标只能在存储过程中使用，应用层流式必须走 useCursorFetch 或 streamResultSet（fetchSize=Integer.MIN_VALUE）。

## fetch_size 跨引擎语义对比

JDBC `Statement.setFetchSize(N)` 是个"提示"，每个驱动实现差异巨大：

| 驱动 | fetchSize 语义 | 默认值 | 必要前置条件 |
|------|--------------|------|----------|
| PgJDBC | 触发 DECLARE CURSOR + FETCH N | 0 (一次取完) | autoCommit=false |
| MySQL Connector/J | 普通模式忽略；MIN_VALUE 切流式；useCursorFetch 时 = COM_STMT_FETCH 块大小 | 0 | useCursorFetch=true 或值 = MIN_VALUE |
| MariaDB Connector/J | 同 MySQL，但加上 useCursorFetch / streamResultSet 选项 | 0 | useCursorFetch=true |
| Oracle JDBC (ojdbc) | OCI prefetch_rows | 10 | 无 |
| SQL Server JDBC (mssql-jdbc) | TDS RPC fetch hint | 128 | selectMethod=cursor 才真服务端游标 |
| DB2 JDBC | DRDA QRYBLKSZ | 32 | autoCommit=false |
| SAP HANA JDBC | SQLDBC fetchSize | 32 | 无 |
| Vertica JDBC | DECLARE CURSOR + FETCH | 0 | autoCommit=false |
| Snowflake JDBC | 内部 chunk size | 0 | -- |
| Spark Thrift JDBC | HiveServer2 maxRows | 1000 | -- |
| Teradata JDBC | StatementInfoParcel rowCount | 1 | -- |

> 关键提醒：**JDBC 规范说 fetchSize 是"提示"**，驱动可忽略。所以"调 fetchSize=1000 解决 OOM"在不同驱动上效果天差地别。MySQL 默认 0 不是流式，必须 MIN_VALUE。

## JDBC 流式抓数完整模板

```java
// PostgreSQL / 兼容引擎
String url = "jdbc:postgresql://host:5432/db?defaultRowFetchSize=1000";
try (Connection conn = DriverManager.getConnection(url, user, pwd)) {
    conn.setAutoCommit(false);  // 必须！否则 fetchSize 被忽略
    try (PreparedStatement ps = conn.prepareStatement(
            "SELECT * FROM big",
            ResultSet.TYPE_FORWARD_ONLY,
            ResultSet.CONCUR_READ_ONLY)) {
        ps.setFetchSize(1000);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                process(rs);
            }
        }
    }
    conn.commit();
}

// MySQL Connector/J streaming
String mysqlUrl = "jdbc:mysql://host:3306/db";
try (Connection conn = DriverManager.getConnection(mysqlUrl, user, pwd)) {
    try (Statement stmt = conn.createStatement(
            ResultSet.TYPE_FORWARD_ONLY,
            ResultSet.CONCUR_READ_ONLY)) {
        stmt.setFetchSize(Integer.MIN_VALUE);  // 魔法值
        try (ResultSet rs = stmt.executeQuery("SELECT * FROM big")) {
            while (rs.next()) {
                process(rs);
            }
        }
    }
}

// MySQL Connector/J useCursorFetch
String mysqlCursorUrl = "jdbc:mysql://host:3306/db?useCursorFetch=true";
try (Connection conn = DriverManager.getConnection(mysqlCursorUrl, ...)) {
    try (PreparedStatement ps = conn.prepareStatement("SELECT * FROM big")) {
        ps.setFetchSize(500);
        try (ResultSet rs = ps.executeQuery()) {
            while (rs.next()) { process(rs); }
        }
    }
}

// Oracle JDBC
try (Connection conn = DriverManager.getConnection(oracleUrl, ...)) {
    try (Statement stmt = conn.createStatement()) {
        stmt.setFetchSize(2000);  // 默认 10，调高
        try (ResultSet rs = stmt.executeQuery("SELECT * FROM big")) {
            while (rs.next()) { process(rs); }
        }
    }
}

// SQL Server JDBC（强制服务端游标）
String mssqlUrl = "jdbc:sqlserver://host:1433;databaseName=db;selectMethod=cursor";
try (Connection conn = DriverManager.getConnection(mssqlUrl, ...)) {
    try (Statement stmt = conn.createStatement()) {
        stmt.setFetchSize(1000);
        try (ResultSet rs = stmt.executeQuery("SELECT * FROM big")) {
            while (rs.next()) { process(rs); }
        }
    }
}
```

## 中途取消正在流式传输的查询

| 引擎 | 取消机制 | API |
|------|---------|----|
| PostgreSQL | 新连接发 CancelRequest 包 | Statement.cancel() / pg_cancel_backend() |
| MySQL / MariaDB | 新连接 KILL QUERY <thread_id> | Statement.cancel() / KILL |
| SQL Server | 同连接 TDS Attention 包 | Statement.cancel() / sp_who2 + KILL |
| Oracle | OCIBreak/OCIReset (同连接) | Statement.cancel() |
| ClickHouse | KILL QUERY WHERE query_id='X' / 取消 HTTP 连接 | client.close() / SQL |
| BigQuery | jobs.cancel REST | bq cancel <job_id> |
| Snowflake | system$cancel_query / SQL API DELETE | Statement.cancel() |
| Trino | DELETE /v1/query/{id} | client.close() / abortQuery |
| Databricks | sql/statements/<id>/cancel REST | client.cancel() |
| Spanner | sessions.cancelQuery gRPC | Spanner client cancel |
| InfluxDB 3.x | gRPC Flight Cancel | flightclient.cancel() |
| DuckDB | duckdb_interrupt() | conn.interrupt() |
| SQLite | sqlite3_interrupt() | conn.interrupt() |
| Cassandra (CQL) | 新连接 cancel session | session.cancel() |

异步取消通道是协议设计的"必修课"。没有异步取消的协议（早期 Firebird、QuestDB）实际上无法对长查询做超时控制，必须断 socket 才能停。

## 列式批 vs 行式流的取舍

| 维度 | 行式流 (PG / MySQL / TDS) | 列式批 (Arrow Flight / Storage API) |
|------|------------------------|-----------------------------------|
| 适合场景 | OLTP 单行查询、点查、低延迟 | OLAP 大扫描、ETL、分析型 |
| 单行延迟 | 极低（几微秒到几毫秒） | 一个批的延迟（几十毫秒） |
| 大查询吞吐 | 中（1-10 GB/s） | 高（10-50 GB/s） |
| CPU 开销 | 高（每行解码） | 低（列批 SIMD） |
| 内存峰值 | 1 行 | 1 个 batch（10k-100k 行） |
| 客户端 API | next() 单行迭代 | RecordBatchReader |
| 与 BI/ETL | JDBC ResultSet | Arrow Table / pandas / Polars |
| 取消粒度 | 行级 | 批级 |
| 跨语言一致 | 各驱动自管 | Arrow C ABI 强一致 |

OLTP 与 OLAP 在协议层就不该共用一种"流"。这也是为什么 Arrow Flight SQL 不打算替代 PG 协议而是补全 OLAP 这一侧。

## 服务端 vs 客户端 vs 协议级流：三种方案对照

```
方案 A: 服务端游标 (DECLARE CURSOR)
  ┌──────────┐   FETCH 1000     ┌──────────┐
  │ Client   │ ───────────────▶ │  Server  │
  │ Buffer   │                  │ Portal   │
  │ 1000 行  │                  │ 持久状态  │
  │          │ ◀─────────────── │          │
  │          │   Rows 1..1000   │          │
  └──────────┘                  └──────────┘

方案 B: 协议级流 (Connector/J streamResultSet / TDS Row mode)
  ┌──────────┐                  ┌──────────┐
  │ Client   │ ◀─────────────── │  Server  │
  │ TCP buf  │   Row by row     │ Pipeline │
  │ 1 行     │   持续推送        │ 边算边发  │
  └──────────┘                  └──────────┘
            (TCP 反压控制速率)

方案 C: 列式批流 (Arrow Flight SQL)
  ┌──────────┐                  ┌──────────┐
  │ Client   │ ◀─────────────── │  Server  │
  │ Arrow    │   batch (列存)   │ Pipeline │
  │ batch    │                  │          │
  │ reader   │ ◀─────────────── │          │
  │          │   batch (列存)   │          │
  └──────────┘                  └──────────┘
            (gRPC HTTP/2 反压)
```

| 维度 | A. 服务端游标 | B. 协议级流 | C. 列式批 |
|------|-----------|-----------|---------|
| 服务端状态 | Portal 必须保持 | 无（pipeline 直接吐） | 无 |
| 客户端控制 | 显式 FETCH | 被动消费 socket | DoGet 拉 batch |
| 反压 | 客户端拉时主动 | TCP 拥塞被动 | gRPC 反压 |
| 跨连接 | 否（同连接） | 否（独占连接） | 是（多端点） |
| 可恢复 | 部分（WITH HOLD） | 否 | 是（ReadSession） |
| 适合场景 | 已知大查询、需控速 | 通用流式抓数 | 大规模 OLAP 分析 |

## 关键发现

1. **没有 SQL 标准**：流式传输完全是协议私有特性 + 驱动 API 拼凑，跨引擎差异极大。SQL 标准只定义 DECLARE CURSOR，但 cursor 离实际网络流式的距离是"协议如何把行送过来"。

2. **默认全缓冲是历史包袱**：1990 年代设计的 PG / MySQL / Oracle / SQL Server 客户端 API 默认全缓冲，逼应用显式开启流式。新引擎（ClickHouse / BigQuery / InfluxDB 3.x）从设计第一天就走流式，不需要"额外开关"。

3. **PgJDBC fetchSize 必须配 autoCommit=false**：PG 的 DECLARE CURSOR 必须在事务中，autoCommit=true 时游标在每条语句后立即销毁，fetchSize 提示被忽略。这是 Java 应用查 PG 大表 OOM 的头号原因。

4. **MySQL Connector/J 的"魔法值" fetchSize=Integer.MIN_VALUE 是事实标准**：-2147483648 触发 streamResultSet 模式（连接独占式流），但应用必须严格 close ResultSet，否则连接池腐败。useCursorFetch 是另一条路，开启服务端游标但服务端会用临时表物化。

5. **Oracle JDBC 默认 prefetch=10 是性能陷阱**：1990 年代窄带连接的合理默认值，今天百兆链路下纯 RTT 主导，调到 1000-5000 后大查询提速 10-30 倍是常见现象。

6. **SQL Server TDS Row mode 协议天然流式**：TDS Row token 是逐行编码协议层，不需要服务端游标就能流式。但 mssql-jdbc 默认 responseBuffering=adaptive 会缓冲一部分，要 selectMethod=cursor 才真正服务端流式。

7. **Arrow Flight SQL 是 2022 年新事实标准**：Apache Arrow 8.0（2022-04）发布的 Flight SQL 是第一个跨厂商、列式、零拷贝、gRPC 原生的 SQL wire 协议。InfluxDB 3.x、Dremio、Doris、DuckDB（社区扩展）已 GA。它不是替代 PG/MySQL，而是补全 OLAP 一侧。

8. **ADBC 是 2023 年新事实标准 API**：Arrow Database Connectivity（2023-01 ADBC 0.1）是面向应用的 Arrow 一等公民 API，直接返回 RecordBatch，零拷贝。生态尚在早期，但 PostgreSQL / Snowflake / SQLite / DuckDB / Flight SQL 后端都有官方驱动。

9. **云数仓借用对象存储做流**：Snowflake、Databricks、BigQuery 把大查询结果切成 Arrow IPC 文件写到 S3 / Azure Blob，客户端拿 presigned URL 并行下载。这是"借对象存储做无限带宽"的工程巧思，单链路带宽不限于 gRPC 流。

10. **取消机制是协议设计的"必修课"**：PG 的 CancelRequest（新连接）、TDS 的 Attention（同连接）、MySQL 的 KILL QUERY（新连接 + 线程 ID）、ClickHouse 的 KILL QUERY 和 HTTP close、Flight SQL 的 gRPC Cancel——没有异步取消的协议无法做长查询超时。

11. **MySQL useCursorFetch 不是真"流"**：服务端开 prepared statement + 临时表物化整个结果集，再分块 FETCH。对超大结果服务端仍要算完才能开始 fetch，与 PG DECLARE CURSOR 的"边算边吐"语义不同。

12. **psql / mysql CLI 默认全缓冲**：psql 走 PQexec 全缓冲；mysql CLI 用 `--quick` 才流式。这是常见的"为什么命令行抽数会 OOM"的原因。CLI 工具不能假定支持流式。

13. **嵌入式数据库天然非缓冲**：SQLite (sqlite3_step)、DuckDB (Pending / iterator)、H2 内嵌模式都是函数迭代，应用主动调下一行，没有"全缓冲"的可能。这是嵌入式相对于网络数据库的天然优势。

14. **Snowflake / Databricks 默认 Arrow chunks 改善 BI 体验**：Tableau / Power BI 抽 1 亿行从 JDBC over JSON（10 分钟）切到 Arrow chunks（1 分钟）是典型场景，性能差 10-30 倍。

15. **流式订阅推送是另一维度**：Materialize / RisingWave 的 SUBSCRIBE、ClickHouse 的 LIVE VIEW（实验）、Kafka Connect Sink、CDC 是"持续流式"，与"大查询流式"语义不同——无终止、有 ACK、需要 backpressure。这超出了本文范围但同样属于流式协议家族。

16. **gRPC + HTTP/2 是新协议优势**：BigQuery / Spanner / InfluxDB 3.x / Snowflake / Databricks / Flight SQL 全部选 HTTP/2 或 gRPC，天然支持流式 + 多路复用 + 反压，省去自己造轮子。早期 PG/MySQL/TDS 的"自己设计 wire 协议"今天看是高昂的工程投入。

17. **取消粒度差异**：行式流可以行级取消（next 之前 break），列式批流取消粒度是 batch（拿到一个 batch 后才能取消下一个）。OLAP 用户对"取消半个 batch"通常不敏感，但 OLTP 行级取消对低延迟交互有意义。

## 参考资料

- ISO/IEC 9075-2:2016, Section 14 (Cursors)
- PostgreSQL: [Frontend/Backend Protocol — Extended Query](https://www.postgresql.org/docs/current/protocol-flow.html#PROTOCOL-FLOW-EXT-QUERY)
- PostgreSQL: [DECLARE CURSOR](https://www.postgresql.org/docs/current/sql-declare.html)
- PostgreSQL: [libpq Single-Row Mode](https://www.postgresql.org/docs/current/libpq-single-row-mode.html)
- PgJDBC: [Server-side prepared statements / fetchSize](https://jdbc.postgresql.org/documentation/query/#getting-results-based-on-a-cursor)
- MySQL: [Cursors / COM_STMT_FETCH](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_com_stmt_fetch.html)
- MySQL Connector/J: [ResultSet Streaming](https://dev.mysql.com/doc/connector-j/8.0/en/connector-j-reference-implementation-notes.html)
- MariaDB Connector/J: [streamResultSet option](https://mariadb.com/kb/en/about-mariadb-connector-j/)
- Oracle: [OCI Programmer's Guide — Prefetch Row Count (since 8i)](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnoci/)
- Oracle JDBC: [setRowPrefetch / setFetchSize](https://docs.oracle.com/en/database/oracle/oracle-database/19/jjdbc/)
- Microsoft TDS: [MS-TDS Specification — Row Token](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-tds/)
- Microsoft JDBC: [Adaptive Buffering / responseBuffering](https://learn.microsoft.com/en-us/sql/connect/jdbc/using-adaptive-buffering)
- ClickHouse: [HTTP Interface — chunked / Formats](https://clickhouse.com/docs/en/interfaces/http)
- ClickHouse: [Native Protocol / Arrow Format](https://clickhouse.com/docs/en/interfaces/formats)
- BigQuery: [Storage Read API](https://cloud.google.com/bigquery/docs/reference/storage)
- Snowflake: [Arrow result set encoding](https://docs.snowflake.com/en/user-guide/python-connector-pandas)
- Databricks: [SQL Statement Execution API](https://docs.databricks.com/api/workspace/statementexecution)
- Apache Arrow Flight SQL: [Specification (Arrow 8.0+, 2022)](https://arrow.apache.org/docs/format/FlightSql.html)
- Apache Arrow Flight: [RPC Specification](https://arrow.apache.org/docs/format/Flight.html)
- ADBC: [Arrow Database Connectivity Spec (0.1+, 2023)](https://arrow.apache.org/adbc/)
- ADBC: [PostgreSQL / Flight SQL / Snowflake / SQLite / DuckDB drivers](https://github.com/apache/arrow-adbc)
- Dremio: [Arrow Flight SQL endpoint](https://www.dremio.com/blog/introducing-apache-arrow-flight-sql/)
- InfluxDB 3.x (IOx): [Flight SQL query interface](https://docs.influxdata.com/influxdb/cloud-serverless/query-data/sql/)
- Apache Doris: [Arrow Flight SQL Support](https://doris.apache.org/docs/dev/lakehouse/arrow-flight-sql)
