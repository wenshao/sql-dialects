# 客户端 Wire 协议 (Database Wire Protocols)

一条 SQL 语句从客户端走到服务器的路径，远比语法树复杂：TCP 握手、版本协商、认证、加密、字节序、参数绑定、结果流式返回、二进制 COPY、取消通知——这些都由 wire 协议定义。SQL 方言决定你能**写**什么查询，wire 协议决定你能**连**哪个数据库。

## 为什么 Wire 协议兼容性比 SQL 方言兼容性更重要

SQL 方言可以用 AST 翻译、视图、函数映射等方式屏蔽差异。但 wire 协议不同：

1. **驱动生态锁定**：JDBC/ODBC/ADO.NET/libpq/go-sql-driver 都是针对特定 wire 协议编写的。实现同一种 wire 协议，就能免费获得整个驱动生态。
2. **BI/ETL 工具即插即用**：Tableau、Power BI、DBeaver、Metabase、dbt 等工具的连接器只认 wire 协议，不认 SQL 方言的细微差异。
3. **连接池与中间件**：PgBouncer、ProxySQL、MaxScale、ShardingSphere 都是协议级代理，只有实现协议才能接入。
4. **OLTP 协议延迟敏感**：单次查询的网络往返、包大小、解析开销直接决定 QPS。应用层选型时，协议开销比 SQL 兼容度更关键。
5. **迁移成本**：改一条 SQL 方言要改代码；切换 wire 协议要换驱动、连接串、客户端配置、监控工具。
6. **认证机制绑定**：SCRAM、Kerberos、IAM、mTLS 都在 wire 协议层完成，应用层无法"适配"。

因此，当一个新数据库选择"兼容 PostgreSQL 协议"或"兼容 MySQL 协议"时，它是在白嫖整个驱动/工具生态。CockroachDB、YugabyteDB、Materialize、RisingWave 选 PG 协议；TiDB、OceanBase、StarRocks 选 MySQL 协议，无一例外。

## 没有"SQL wire 协议"标准

ISO/IEC 9075 只定义语法与语义，不涉及字节。工业界有若干"API 标准"，但**没有 wire 标准**：

| 规范 | 层级 | 说明 |
|------|------|------|
| ODBC (ISO/IEC 9075-3 SQL/CLI) | API 标准 | C 函数接口，底层仍调用私有 wire |
| JDBC (JSR 221) | API 标准 | Java 接口，Driver 内部实现各家 wire |
| ADO.NET | API 标准 | .NET 接口，Provider 实现各家 wire |
| OLE DB | API 标准 | 已弃用 |
| DRDA (Distributed Relational Database Architecture) | IBM 开源但非事实标准 | DB2/Derby 使用 |
| Apache Arrow Flight SQL | 事实标准（RPC） | 2022+ 新兴，基于 gRPC |

ODBC/JDBC 屏蔽了 wire 协议细节，但每个驱动背后仍是私有 wire：psqlODBC 说 PostgreSQL wire，Connector/J 说 MySQL wire，OJDBC 说 Oracle Net8。

## 支持矩阵：45+ 数据库 Wire 协议全景

### 基础协议信息

| 引擎 | 原生协议 | 格式 | 默认端口 | TLS | 版本协商 | Extended Query | 流式/COPY |
|------|---------|------|---------|-----|----------|----------------|-----------|
| PostgreSQL | PostgreSQL v3 | 二进制/文本混合 | 5432 | SSL/TLS | startup msg | 是 | COPY BINARY |
| MySQL | MySQL Protocol | 二进制（4.1+ 结果集二进制） | 3306 | SSL/TLS | capability flags | COM_STMT_* | LOAD DATA LOCAL |
| MariaDB | MariaDB Protocol (MySQL 超集) | 二进制 | 3306 | SSL/TLS | capability flags | 是 | LOAD DATA |
| SQLite | -- (嵌入式) | -- | -- | -- | -- | API 内调用 | -- |
| Oracle | TNS/Net8 (Oracle Net) | 二进制 TNS 包 | 1521 | SQLNet 加密 / TCPS | TNS handshake | OCI 绑定 | Direct Path |
| SQL Server | TDS (Tabular Data Stream) | 二进制 | 1433 | TDS over TLS | TDS pre-login | RPC 请求 | Bulk Copy (BCP) |
| DB2 | DRDA | 二进制 | 50000 | TLS | DDM | DRDA CMD | LOAD |
| Snowflake | HTTPS REST | JSON / Arrow | 443 | 强制 TLS | HTTP 版本头 | JDBC 内模拟 | PUT/GET + COPY |
| BigQuery | gRPC + HTTPS REST | Protobuf + Arrow (Storage API) | 443 | 强制 TLS | gRPC 元数据 | 参数化查询 | Storage Write API |
| Redshift | PostgreSQL v3 (修改版) | 二进制/文本 | 5439 | SSL/TLS | startup msg | 是 | COPY (S3) |
| DuckDB | -- (嵌入式) / Arrow Flight SQL (选配) | -- / Arrow | -- / 47470 | -- / TLS | -- | API | Arrow IPC |
| ClickHouse | Native TCP | 二进制 | 9000 | TLS (9440) | server version | 预处理语句 | Native / RowBinary |
| ClickHouse | HTTP(S) | 文本/二进制格式参数 | 8123 / 8443 | TLS | HTTP 头 | 参数化查询 | 所有 Format |
| ClickHouse | MySQL 协议（部分） | 二进制 | 9004 | TLS | -- | 是 | -- |
| ClickHouse | PostgreSQL 协议（部分） | 二进制 | 9005 | TLS | -- | 有限 | -- |
| Trino | HTTP REST | JSON | 8080 / 8443 | TLS | HTTP 头 | 预处理语句 | Spooled chunks |
| Presto | HTTP REST | JSON | 8080 | TLS | -- | -- | 分页获取 |
| Spark SQL | Thrift Server (HiveServer2) | 二进制 Thrift | 10000 | SASL/TLS | TProtocol | HiveServer2 语句 | JDBC 批量 |
| Hive | HiveServer2 (Thrift) | 二进制 Thrift | 10000 | SASL/Kerberos | TProtocolVersion | 是 | -- |
| Flink SQL | SQL Gateway HTTP / JDBC | JSON / Thrift | 8083 / 10000 | TLS | REST 版本 | 预处理语句 | -- |
| Databricks | Thrift / SQL Statement Execution API | Thrift / JSON / Arrow | 443 | 强制 TLS | HTTP 头 | 参数化 | Arrow 流 |
| Teradata | Teradata Director Program (TDP) | 二进制 | 1025 | TLS 1.2+ | CLIv2 握手 | PREPARE | FastLoad |
| Greenplum | PostgreSQL v3 | 二进制/文本 | 5432 | SSL/TLS | startup msg | 是 | gpfdist |
| CockroachDB | PostgreSQL v3 | 二进制/文本 | 26257 | 强制 TLS | startup msg | 是 | COPY BINARY |
| TiDB | MySQL Protocol | 二进制 | 4000 | SSL/TLS | capability flags | COM_STMT_* | LOAD DATA |
| OceanBase | MySQL Protocol + Oracle 模式（OB 2.x+） | 二进制 | 2881 | SSL/TLS | capability flags | 是 | OBClient Load |
| YugabyteDB (YSQL) | PostgreSQL v3 | 二进制/文本 | 5433 | TLS | startup msg | 是 | COPY |
| YugabyteDB (YCQL) | Cassandra CQL Native | 二进制 | 9042 | TLS | CQL 版本帧 | PREPARE | BATCH |
| SingleStore | MySQL Protocol | 二进制 | 3306 | SSL/TLS | capability flags | 是 | LOAD DATA |
| Vertica | Vertica 私有 (类 PG 结构) | 二进制 | 5433 | SSL/TLS | startup msg | 是 | COPY |
| Impala | HiveServer2 (Thrift) + Beeswax | Thrift 二进制 | 21000 / 21050 | SASL/TLS | Thrift 版本 | 是 | -- |
| StarRocks | MySQL Protocol（查询）+ HTTP（StreamLoad） | 二进制 / HTTP | 9030 / 8030 | TLS | capability flags | 是 | Stream Load |
| Doris | MySQL Protocol + HTTP | 二进制 / HTTP | 9030 / 8030 | TLS | capability flags | 是 | Stream Load |
| MonetDB | MAPI | 文本 + 二进制响应 | 50000 | TLS (Jun2023+) | MAPI 版本字符串 | 是 | COPY INTO |
| CrateDB | PostgreSQL v3 | 二进制 | 5432 | TLS | startup msg | 部分 | COPY FROM |
| TimescaleDB | PostgreSQL v3（扩展） | 二进制/文本 | 5432 | SSL/TLS | 继承 PG | 是 | COPY |
| QuestDB | PostgreSQL v3 + ILP + HTTP | 二进制 / 文本 / HTTP | 8812 / 9009 / 9000 | TLS | startup msg | 部分 | ILP TCP |
| Exasol | Exasol 私有 (基于 WebSocket) | JSON 帧 | 8563 | 强制 TLS | login 帧 | 是 | IMPORT/EXPORT |
| SAP HANA | SQL Command Network Protocol (SQLDBC) | 二进制 | 30015 | TLS | 握手包 | 是 | IMPORT |
| Informix | SQLI | 二进制 | 1526 | SSL | ASF/ODS 版本 | 是 | Load utility |
| Firebird | Firebird Wire Protocol (XDR) | 二进制 | 3050 | TLS (v3+) | op_connect | 是 | External Tables |
| H2 | TCP 私有 / PostgreSQL 模式 / PG Server | 二进制 / PG | 9092 | TLS | version 字节 | 是 | CSVREAD |
| HSQLDB | HSQLDB 私有 / HTTP | 二进制 / HTTP | 9001 | TLS | handshake | 是 | 文本 import |
| Derby | DRDA | 二进制 | 1527 | SSL | DDM | 是 | LOAD |
| Amazon Athena | HTTPS REST (AWS API) | JSON / Arrow (Athena v3) | 443 | 强制 TLS | API 版本 | 预处理语句 | 结果到 S3 |
| Azure Synapse (Dedicated) | TDS | 二进制 | 1433 | TLS | TDS pre-login | RPC | PolyBase |
| Google Spanner | gRPC | Protobuf | 443 | 强制 TLS | gRPC 元数据 | 是 | Mutation API |
| Google Spanner (PG interface) | PostgreSQL v3 | 二进制 | 5432 | TLS | startup msg | 是 | -- |
| Materialize | PostgreSQL v3 | 二进制 | 6875 | TLS | startup msg | 是 | COPY SUBSCRIBE |
| RisingWave | PostgreSQL v3 | 二进制 | 4566 | TLS | startup msg | 是 | COPY |
| InfluxDB (IOx / 3.x SQL) | Arrow Flight SQL + HTTP v1/v2 | Arrow / JSON | 8086 / 443 | TLS | Flight handshake | 是 | line protocol |
| Databend | MySQL Protocol + ClickHouse HTTP + REST | 二进制 / HTTP | 3307 / 8000 | TLS | capability flags | 是 | COPY INTO |
| Yellowbrick | PostgreSQL v3 | 二进制/文本 | 5432 | SSL/TLS | startup msg | 是 | bulk loader (ybload) |
| Firebolt | HTTPS REST | JSON | 443 | 强制 TLS | API 版本头 | 参数化 | COPY FROM |

### MySQL 协议兼容阵营

| 引擎 | 支持版本 | 默认端口 | 差异点 |
|------|---------|---------|--------|
| MySQL | 5.0+ → 9.0 (协议 4.1+) | 3306 | 参考实现 |
| MariaDB | 10.x | 3306 | 扩展 capability（MARIADB_CLIENT_*） |
| Percona Server | 基于 MySQL | 3306 | 完全兼容 |
| TiDB | 自 4.1 | 4000 | 缺少 BINLOG_DUMP、XA RECOVER 部分命令 |
| OceanBase | MySQL 模式 | 2881 | 兼容协议，命令集略异 |
| Vitess (gate) | 继承 MySQL | 15306 | VTGate 作为代理 |
| PolarDB-X | MySQL 协议 | 3306 | 阿里云 MySQL 分片 |
| Aurora MySQL | MySQL 5.7/8.0 | 3306 | 完全兼容 |
| SingleStore | MySQL 5.7 | 3306 | 子集 |
| StarRocks | MySQL 子集 | 9030 | 无 binlog / 复制命令 |
| Apache Doris | MySQL 子集 | 9030 | 同上 |
| ClickHouse | 可选开启 | 9004 | 仅查询，无事务命令 |
| Databend | MySQL handshake | 3307 | 仅查询 |
| ProxySQL | MySQL 代理 | 6033 | 透明代理 |

### PostgreSQL 协议兼容阵营

| 引擎 | PG 协议版本 | 端口 | 差异点 |
|------|------------|------|--------|
| PostgreSQL | v3 (7.4+) | 5432 | 参考实现 |
| Amazon Aurora PostgreSQL | v3 | 5432 | 完全兼容 |
| Amazon Redshift | v3 + 扩展 | 5439 | 子集，大量 PG 函数缺失 |
| Google AlloyDB | v3 | 5432 | 完全兼容 |
| Azure Database for PostgreSQL | v3 | 5432 | 完全兼容 |
| Greenplum | v3 | 5432 | 继承 PG 8.4 协议 |
| CockroachDB | v3 | 26257 | 高兼容，无游标 |
| YugabyteDB (YSQL) | v3 | 5433 | 继承 PG 11 协议 |
| CrateDB | v3 | 5432 | 子集 |
| Materialize | v3 | 6875 | 流式 + SUBSCRIBE |
| RisingWave | v3 | 4566 | 流式扩展 |
| TimescaleDB | v3 | 5432 | PG 扩展 |
| QuestDB | v3 子集 | 8812 | 仅读查询完整支持 |
| Yellowbrick | v3 | 5432 | 基于 PG fork |
| Vertica | 类 PG | 5433 | wire 兼容 PG，服务端源于 C-Store 项目 |
| Google Spanner (PG) | v3 | 5432 | 2022 新增 |
| Neon | v3 | 5432 | PG 兼容，有 Serverless 扩展 |
| Supabase | v3 | 5432 | 完全是 PG |
| EDB (EnterpriseDB) | v3 | 5444 | PG 兼容 |
| Babelfish for Aurora | v3 + TDS | 5432/1433 | 同时支持 PG 和 TDS |

### Arrow Flight SQL 阵营（新兴）

| 引擎 | 状态 | 端口 | 备注 |
|------|------|------|------|
| Apache Doris | 实验/GA | 9611 | ADBC Flight SQL 支持 |
| InfluxDB IOx / 3.x | GA | 8086/443 | 查询必走 Flight |
| Dremio | GA | 32010 | 原生支持 |
| DuckDB | 社区扩展 | 47470 | nanoarrow / flight 扩展 |
| SQLFlite | 示例实现 | -- | Apache 官方参考 |
| Google BigQuery | Storage Read API（类 Flight） | 443 | Arrow 格式 + gRPC |
| Databricks | 部分 Photon 结果 | 443 | JDBC 内部使用 Arrow |

## PostgreSQL 协议深度解析

### 协议版本演进

| 版本 | 年份 | 对应 PostgreSQL | 关键特性 |
|------|------|-----------------|---------|
| v1 | 1996 | 6.4 前 | 简单协议，已淘汰 |
| v2 | 1998 | 6.4 – 7.3 | 独立认证包 |
| v3 | 2003 | 7.4 → 至今 | startup msg、参数协商、扩展协议 |

PostgreSQL 协议 v3 自 2003 年 PostgreSQL 7.4 开始稳定，20+ 年未换大版本，这是它能被生态广泛复用的关键——兼容包袱极小。

### 启动消息 (Startup Message)

```text
StartupMessage
  Length : int32
  ProtocolVersion : int32  (0x00030000 表示 3.0)
  Parameters :
    "user" : <username>
    "database" : <database>
    "application_name" : <app>
    "client_encoding" : <encoding>
    ... 其他可选参数 ...
  (null terminator)
```

客户端连上后直接发送 StartupMessage（无版本协商握手），服务器根据版本号决定走哪条路径。如果服务器要求 SSL，客户端先发 SSLRequest（保留 code 80877103），服务器回 'S' 或 'N'。

### Simple Query (COM_QUERY 类比)

```text
Query ('Q')
  Length : int32
  QueryString : CString

→ 服务器依次发：
  RowDescription ('T')  -- 列元数据
  DataRow ('D') × N      -- 每行
  CommandComplete ('C')  -- "SELECT 123"
  ReadyForQuery ('Z')    -- 空闲/事务状态
```

Simple Query 一次发送完整 SQL，服务器以文本格式返回所有结果。适合一次性查询，但每次都要解析 SQL，无法传参。

### Extended Query Protocol (关键差异)

```text
1. Parse ('P')
   StatementName : CString   (空字符串 = unnamed)
   Query : CString
   ParameterTypes : int16 + int32[]

2. Bind ('B')
   PortalName : CString
   StatementName : CString
   ParameterFormats : int16 + int16[]    (0=文本, 1=二进制)
   ParameterValues : int16 + [length+bytes]
   ResultFormats : int16 + int16[]

3. Describe ('D') -- 可选
4. Execute ('E')
   PortalName : CString
   MaxRows : int32

5. Sync ('S')  -- 提交整批命令
```

Extended Query 把一次查询拆成 Parse/Bind/Execute，允许：

- **预处理语句复用**：Parse 一次，多次 Bind/Execute，服务器缓存计划
- **参数二进制传输**：避免字符串拼接 SQL，防注入
- **部分读取结果**：Execute 的 MaxRows 控制返回行数，实现游标语义
- **批量流水线**：多个 Parse/Bind/Execute 后一个 Sync，减少 RTT

JDBC / libpq / asyncpg / pgx / node-postgres 几乎都默认用 Extended Query。

### COPY 子协议

```text
Query ('Q'): COPY tbl FROM STDIN WITH (FORMAT binary)

服务器 → CopyInResponse ('G') : 列格式
客户端 → CopyData ('d') × N : 二进制行数据
客户端 → CopyDone ('c')
服务器 → CommandComplete + ReadyForQuery
```

COPY BINARY 的单行格式：

```
FieldCount : int16
对每列 : Length : int32 (-1 表示 NULL) + Bytes
```

COPY BINARY 是 PostgreSQL 协议里**最快的批量导入通道**，可以达到 100k-500k 行/秒。相比之下，INSERT 走 Extended Query 约 10k-30k 行/秒，即使批量也慢一个数量级。

### 认证消息

| 方法 | 消息 | 备注 |
|------|------|------|
| Trust | AuthenticationOk (R=0) | 无认证 |
| MD5 | AuthenticationMD5Password (R=5) | 已弃用 |
| SCRAM-SHA-256 | AuthenticationSASL (R=10) | PG 10+ 推荐 |
| GSSAPI | AuthenticationGSS (R=7) | Kerberos |
| SSPI | AuthenticationSSPI (R=9) | Windows |
| Cleartext | AuthenticationCleartextPassword (R=3) | 仅在 TLS 下 |

### 错误、通知、异步消息

PostgreSQL 协议允许服务器在任意时刻异步发送：

- `NotificationResponse ('A')`：LISTEN/NOTIFY 推送
- `NoticeResponse ('N')`：非致命提示（如 DROP CASCADE 警告）
- `ParameterStatus ('S')`：会话变量变化（如 SET timezone）
- `ErrorResponse ('E')`：带 severity/code/detail 的结构化错误

这是 PG 协议的核心优势之一：服务器推送非同步、非阻塞。Materialize 的 SUBSCRIBE 完全依赖这个机制实现增量流推送。

## MySQL 协议深度解析

### 协议版本

| 版本 | 说明 |
|------|------|
| Protocol 9 | MySQL 3.22 之前，历史遗物 |
| Protocol 10 | MySQL 3.22+，当今所有实现 |
| Protocol 4.1 | 握手扩展，密码 SHA1，结果集二进制格式 |

"协议 10 + 4.1 能力位" 是现代 MySQL 协议的事实标准。

### 包结构 (MySQL Packet)

```text
每个 MySQL 包:
  PayloadLength : 3 字节 (小端)
  SequenceId : 1 字节
  Payload : N 字节 (≤ 16MB - 1)

大包: 超过 16MB - 1 的数据被分成多个 seq_id 递增的包。
```

SequenceId 每次 client → server 往返重置为 0。这个单字节序号在中间代理（ProxySQL、MaxScale）里是大麻烦：代理必须正确转发并可能重写 seq_id。

### 握手与认证

```text
1. 服务器 → Initial Handshake (protocol 10)
     protocol_version : 1
     server_version : string
     connection_id : 4
     auth_plugin_data_part_1 : 8
     capability_flags_1 : 2
     character_set : 1
     status_flags : 2
     capability_flags_2 : 2
     auth_plugin_data_len : 1
     reserved : 10
     auth_plugin_data_part_2 : max(13, len-8)
     auth_plugin_name : string

2. 客户端 → SSL Request (可选, 仅能力位开启 CLIENT_SSL)
3. 客户端 → Handshake Response
     capability_flags : 4
     max_packet : 4
     charset : 1
     reserved : 23
     username : CString
     auth_response : length-encoded
     database : CString (可选)
     auth_plugin_name : CString
     connection_attributes : key-value map

4. 服务器 → OK_Packet / ERR_Packet / AuthSwitchRequest
```

认证插件是 MySQL 协议的扩展点：

| 插件 | 说明 |
|------|------|
| mysql_native_password | SHA1(password) XOR SHA1(SHA1(password) + salt)，已过时但广用 |
| caching_sha2_password | MySQL 8.0 默认，SHA256，支持缓存 |
| sha256_password | 完整 RSA 加密 |
| authentication_ldap_sasl | 企业版 LDAP |
| authentication_kerberos | 企业版 Kerberos |
| auth_socket / auth_pam | Unix 域 / PAM |

**兼容性陷阱**：MySQL 8.0 默认 caching_sha2_password，老客户端（PHP mysqli 5.x、某些 JDBC）只认 mysql_native_password。TiDB、MariaDB、Aurora 选择兼容老插件以减少迁移阻力。

### COM_QUERY 请求

```text
COM_QUERY (0x03)
  SQL : 剩余字节

响应:
  - OK_Packet (DDL/DML)
  - ERR_Packet
  - ResultSet:
      column_count : length-encoded int
      ColumnDefinition × N
      EOF (或 OK with CLIENT_DEPRECATE_EOF)
      Row × M
      EOF / OK
```

ResultSet 的行有两种编码：

- **文本协议**（COM_QUERY 响应）：所有值都是字符串，客户端解析
- **二进制协议**（COM_STMT_EXECUTE 响应）：整数、浮点、时间戳用原生字节

文本 vs 二进制：1 亿行整数列，文本约 500MB，二进制约 400MB；但解析开销文本是二进制的 3-5 倍。

### COM_STMT_* 预处理语句

```text
COM_STMT_PREPARE (0x16)
  SQL

→ COM_STMT_PREPARE_OK:
    statement_id : 4
    num_columns : 2
    num_params : 2
    警告数

COM_STMT_EXECUTE (0x17)
  statement_id : 4
  flags : 1
  iteration_count : 4
  NULL-bitmap + new-params-bound + param_types + param_values

COM_STMT_CLOSE (0x19)
  statement_id : 4
```

MySQL 的 prepared statement 是**服务器端**的，需显式 CLOSE 释放。连接池常见陷阱：连接复用时 statement_id 泄漏。JDBC 默认 `useServerPrepStmts=false`，在客户端做参数替换。

### 压缩协议 (CLIENT_COMPRESS)

启用压缩能力位后，每个包外层再套一层：

```text
CompressedPacketHeader:
  CompressedPayloadLength : 3
  SequenceId : 1
  UncompressedPayloadLength : 3  (0 表示未压缩)
  Payload : zlib 压缩或原样
```

适合大结果集传输（慢网络下 10 倍吞吐），但 CPU 开销大。TiDB、Aurora 都支持。

### LOAD DATA LOCAL 子协议

```text
客户端: COM_QUERY LOAD DATA LOCAL INFILE 'file.csv' INTO TABLE t
服务器: LOCAL_INFILE_REQUEST (0xFB + 文件名)
客户端: 读取本地文件并发送文件内容
客户端: 空包 (0 字节) 标记结束
服务器: OK_Packet
```

这是**历史上 MySQL 最严重的安全漏洞源头**：恶意服务器可要求客户端读取任意本地文件。MySQL 8 默认禁用，需显式 `local_infile=ON`。

## TDS (Tabular Data Stream) 深度解析

TDS 由 Sybase 于 1984 年发明，微软在 1988 年和 Sybase 合作获得源码后将其改造为 SQL Server 协议。因此 TDS 同时是 Sybase ASE 和 SQL Server 的 wire 协议。

### TDS 版本矩阵

| TDS 版本 | 年份 | 产品 | 特性 |
|---------|------|------|------|
| TDS 4.2 | 1990 | SQL Server 4.2 / Sybase 早期 | 16-bit 长度 |
| TDS 7.0 | 1999 | SQL Server 7 | Unicode, 7 字节序言 |
| TDS 7.1 | 2000 | SQL Server 2000 | bigint, sql_variant |
| TDS 7.2 | 2005 | SQL Server 2005 | varchar(max), XML, MARS |
| TDS 7.3 | 2008 | SQL Server 2008 | date, time, datetime2 |
| TDS 7.4 | 2012 | SQL Server 2012 | always encrypted 前身 |
| TDS 8.0 | 2022 | SQL Server 2022 | TLS 1.3 强制, no pre-login encryption handshake |

MS-TDS 规范（[MS-TDS]）超过 400 页，细节比 PG/MySQL 协议复杂得多。

### TDS 包结构

```text
TDS Packet Header (8 bytes):
  Type : 1         (Query=0x01, RPC=0x03, PreLogin=0x12, Login7=0x10, ...)
  Status : 1       (bit 0 = EOM)
  Length : 2 (大端!)
  SPID : 2
  PacketID : 1
  Window : 1 (保留)
Payload : N
```

TDS 使用**大端字节序**于包头，但载荷里的整数是**小端**。这是历史遗留：包头来自网络字节序习惯，载荷是 x86 原生。

### PreLogin / Login7

```text
PreLogin (type=0x12):
  选项流: [OptionType(1) + Offset(2) + Length(2)] × N + 0xFF
  选项数据追加在末尾
  选项包括: VERSION, ENCRYPTION, INSTOPT, THREADID, MARS, TRACEID, FEDAUTHREQUIRED

Login7 (type=0x10):
  Length, TDSVersion, PacketSize, ClientProgVer, ClientPID, ConnectionID
  OptionFlags1/2/3
  ClientTimeZone, ClientLCID
  变长字段偏移/长度表 (HostName, UserName, Password(混淆), AppName, ...)
  变长字段数据
```

密码用 "XOR 0xA5 + 高低 nibble 交换" 混淆（非加密），主要为防肩窥。真正加密靠 TLS。

### 结果集：COLMETADATA + ROW

```text
服务器响应流式:
  COLMETADATA token (0x81)
    列数 + [usertype, flags, typeinfo, name] × N
  ROW token (0xD1) × M
    每列按 typeinfo 的规则编码
  DONE token (0xFD)
    status, curcmd, rowcount
```

与 PG 不同，TDS 使用 token-based streaming：每个 token 独立，不需要预告总长度。这让 SQL Server 可以在执行过程中持续推送行。

### RPC 请求 (Remote Procedure Call)

```text
Type=0x03 RPC 请求:
  RPCName (或 ProcID, 如 Sp_ExecuteSql = 10)
  OptionFlags
  参数列表:
    [ParamName, StatusFlag, TypeInfo, Value] × N
```

TDS 的 RPC 是 SQL Server 执行预处理语句的主要方式：客户端发 sp_prepexec 或 sp_executesql，服务器处理为参数化查询。ADO.NET、JDBC、Tedious 都用 RPC 路径。

### MARS (Multiple Active Result Sets)

TDS 7.2+ 支持单个连接上同时打开多个结果集。这在其他协议里很少见（PG 需要独立连接或 portal）。MARS 通过 SMUX 多路复用层实现：每个逻辑请求有独立的 SMUX session id。

### BCP (Bulk Copy Program)

```text
COLMETADATA token (FLAGS=bcp)
ROW token × M (大批量)
DONE
```

BCP 是 TDS 的高速批量导入协议，直接绕过 SQL 层，速度可达 500k+ 行/秒。SSIS / PolyBase / bcp.exe 工具都基于此。

## Oracle TNS / Net8

Oracle Net（历史名 SQL*Net / Net8）是 Oracle 的专有协议栈：

```
应用层：OCI / JDBC / ODP.NET
协议层：TTC (Two-Task Common)
传输层：TNS (Transparent Network Substrate)
网络层：TCP / TCPS (TLS) / IPC / Named Pipes
```

### TNS 包

```text
TNS Packet Header (8 bytes):
  Length : 2
  Checksum : 2
  Type : 1    (Connect=1, Accept=2, Refuse=4, Redirect=5, Data=6, ...)
  Reserved : 1
  Checksum : 2
Payload
```

### 连接建立

```text
1. 客户端 → CONNECT
   协议版本 min/max
   SDU/TDU (Session/Transport Data Unit 大小)
   服务名 / SID / Easy Connect 字符串
2. 服务器 → ACCEPT (协商的版本) / REDIRECT (到专有服务器) / REFUSE
3. 客户端 → DATA 里包含 TTC 协议消息
```

TTC 之上再套一层 **OCI (Oracle Call Interface)** 语义：OPI (Oracle Program Interface) 消息码定义所有 SQL 命令、绑定、取数等操作。

### 认证与加密

- **NASSL**：Oracle Advanced Security 的前身。
- **Native Network Encryption**：协议层内置 RC4/AES 加密（不是 TLS）。
- **TCPS**：TLS 1.2+ 包裹 TNS。
- **Kerberos / RADIUS / PKI**：通过 OCI 认证层协商。

### sqlnet.ora / tnsnames.ora

Oracle 的连接配置在客户端 `tnsnames.ora` 里：

```
MYDB =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = dbhost)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = mydb.example.com)))
```

连接字符串本质是 descriptor + alias 的二级解析。`sqlnet.ora` 控制全局行为（加密算法、超时、追踪）。

### Oracle TNS 的性能特征

- **Array Fetch**：OCI 默认 10 行/次，可调 1000+ 大幅降低 RTT
- **Direct Path Load**：绕过 SQL 层直写数据文件，SQL*Loader / External Tables 使用
- **Shared/Dedicated Server**：同一协议支持多路复用到共享后台进程

## Arrow Flight SQL：新兴标准

Apache Arrow Flight SQL 基于 gRPC，由 Apache Arrow 项目在 2022 年定义。目标是**取代 ODBC/JDBC 成为分析型数据库的 wire 标准**。

### 为什么需要新协议

传统协议（PG / MySQL / TDS / TNS）都是行存 wire 格式：每行独立字段，客户端拿到后还要逐行解析并可能转为列格式给分析代码（pandas / polars / DuckDB）。对 OLAP 是双重浪费。

Arrow Flight SQL 直接用 Arrow IPC 列存格式：

- 零拷贝：传输即内存格式，pandas/polars 直接映射
- gRPC HTTP/2：连接多路复用、服务器推送、标准流控
- 类型完整：Arrow 类型系统（Decimal128/256、List、Struct、Map）比 SQL ResultSet 更丰富
- 并行下载：多个 endpoint 同时拉数据（分布式天然适配）

### Flight SQL 核心 RPC

```protobuf
service FlightService {
  rpc GetFlightInfo(FlightDescriptor) returns (FlightInfo) {}
  rpc DoGet(Ticket) returns (stream FlightData) {}
  rpc DoPut(stream FlightData) returns (stream PutResult) {}
  rpc DoExchange(stream FlightData) returns (stream FlightData) {}
}

// Flight SQL 扩展
CommandStatementQuery  { query }
CommandStatementUpdate { query }
CommandPreparedStatementQuery { prepared_statement_handle, parameters }
ActionCreatePreparedStatementRequest { query }
```

典型流程：

```
1. Client.execute(sql)
  → GetFlightInfo(CommandStatementQuery { sql })
  → 返回 FlightInfo { endpoints : [endpoint_1, endpoint_2, ...] }
2. 对每个 endpoint 并行 DoGet(ticket)
  → 服务器流式返回 Arrow RecordBatch
3. 客户端零拷贝组装为表
```

### 实现现状

| 引擎 | Flight SQL 状态 |
|------|----------------|
| Dremio | GA，官方主协议 |
| InfluxDB IOx / 3.x | GA，SQL 查询必走 Flight SQL |
| Apache Doris | GA，可选开启 |
| DuckDB | 社区扩展 |
| PostgreSQL | 社区 PoC |
| Trino | 讨论中 |
| Spark Connect | 架构类似但非 Flight SQL |
| Databricks | JDBC 驱动内部已经用 Arrow |

ADBC（Arrow Database Connectivity）是 Arrow 生态的 ODBC/JDBC 替代品，内部默认走 Flight SQL。

## 各引擎 wire 协议详解

### PostgreSQL

- 协议：v3，端口 5432
- 认证：SCRAM-SHA-256（默认）、MD5（兼容）、GSSAPI、cert、trust
- 加密：SSL request + STARTTLS 风格协商
- 驱动：libpq (C), JDBC, psycopg2/psycopg3, asyncpg, pgx (Go), node-postgres, pq (Go), postgres-rs (Rust)
- 特色：COPY BINARY（高速批量）、LISTEN/NOTIFY（异步推送）、游标（DECLARE/FETCH）

### MySQL

- 协议：Protocol 10 + 4.1 能力位，端口 3306
- 认证：caching_sha2_password (8.0 默认) / mysql_native_password (兼容)
- 加密：CLIENT_SSL 能力位 + TLS 升级
- 驱动：Connector/C, Connector/J, mysqlclient, mysql2 (Node), go-sql-driver, rust-mysql
- 特色：压缩协议、LOAD DATA LOCAL（警惕安全）、X Protocol（MySQL 8 的 gRPC 替代，未普及）

### Oracle

- 协议：TNS/Net8，端口 1521
- 认证：O3LOGON（基于 DES 后升级 AES）、Kerberos、SSL/PKI、LDAP
- 加密：Native Network Encryption 或 TCPS
- 驱动：OCI (C)、OJDBC (thin/oci 两模式)、ODP.NET、python-oracledb、node-oracledb
- 特色：透明应用故障切换（TAF / AC）、DRCP（连接池中间件）、Advanced Queueing

### SQL Server / Azure SQL

- 协议：TDS（7.x/8.0），端口 1433
- 认证：SQL Server 身份验证、Windows（NTLM/Kerberos 通过 SSPI）、Azure AD
- 加密：TLS 自包含于 TDS，TDS 8.0 强制 TLS 1.3
- 驱动：ODBC Driver、Microsoft JDBC Driver、pyodbc、mssql (Python pytds)、tedious (Node)、go-mssqldb
- 特色：MARS 多结果集、BCP 批量、Always Encrypted（列级加密）、Contained Database

### DB2

- 协议：DRDA（Distributed Relational Database Architecture），端口 50000
- 格式：基于 DDM（Distributed Data Management）二进制码
- 认证：EUSRIDPWD、KERBEROS、EUSRSSBPWD、基于客户端证书
- 特色：跨 z/OS、Linux、Windows、i 系列都用同一协议；开源实现（JCC driver）
- Derby 使用同样的 DRDA，所以 DB2 客户端可以连 Derby

### Snowflake

- 协议：**纯 HTTPS REST**，端口 443
- 无原生 TCP 协议，所有 JDBC / ODBC 驱动内部翻译为 HTTP 调用
- 查询流程：POST /session/v1/login → POST /queries/v1/query-request → GET 分片结果
- 大结果集：服务器生成临时 S3 URL，客户端直接从 S3 下载
- 优点：穿透防火墙/代理简单，无需 TCP 端口开放
- 缺点：协议开销高，延迟敏感场景不适用
- 没有"Snowflake 协议兼容"概念——因为协议本身是内部 API，随时可变

### BigQuery

- 协议：gRPC（Storage Read API / Write API）+ HTTPS REST（控制面）
- 数据格式：Arrow（默认）或 Avro（Storage Read API）
- 认证：OAuth 2.0 / Service Account / ADC
- 特色：Storage Read API 支持并行读取（返回多个 stream），客户端可水平扩展消费

### Redshift

- 协议：PostgreSQL v3 的 fork，端口 5439
- 基于 PG 8.0.2 代码，但协议层有 AWS 扩展
- 认证：PG 密码、IAM Token（amazon-redshift-auth-token）
- 特色：COPY FROM S3/DynamoDB/EMR（不走客户端，由集群直接拉）
- Data API（REST）：通过 AWS API 执行查询，无需开 5439 端口

### DuckDB

- 纯嵌入式，无 wire 协议（同进程 API 调用）
- DuckDB Server 扩展：通过 PostgreSQL 协议或 Arrow Flight SQL 提供远程访问
- ODBC 驱动：进程内调用 + ODBC 接口

### ClickHouse

- **四协议并存**：
  - Native TCP (9000)：ClickHouse 原生协议，性能最高
  - HTTP(S) (8123/8443)：RESTful，最灵活
  - MySQL (9004)：兼容 MySQL 客户端
  - PostgreSQL (9005)：兼容 PG 客户端
- Native 协议：数据用 Native 格式（列存、按 block 传输），clickhouse-client 默认使用
- HTTP 协议可选多种 Format：`Native`, `RowBinary`, `JSONEachRow`, `Parquet`, `Arrow`, `CSV` 等
- 对外暴露多协议的设计是 ClickHouse 获得快速生态渗透的关键

### Trino / Presto

- 协议：HTTP REST，端口 8080（默认）
- 流式：客户端轮询 `/v1/statement/{queryId}/{next}`，服务器返回下一批数据 + 下一个 URL
- 数据格式：JSON（结果集）
- 认证：Basic Auth、Kerberos、OAuth 2.0、JWT
- Trino 新增 Spooled Protocol：大结果分片到对象存储，客户端直连下载（类似 Snowflake）

### Spark SQL / Hive / Impala

- HiveServer2 (Thrift Protocol)，端口 10000
- 基于 Apache Thrift，使用二进制 TBinaryProtocol
- 操作：`OpenSession`、`ExecuteStatement`、`FetchResults`
- 认证：Kerberos/SASL、LDAP、自定义
- Impala 加开 Beeswax（21000）兼容旧 Hive CLI；新客户端用 HiveServer2 (21050)

### Flink SQL

- SQL Gateway：HTTP REST（8083）
- JDBC Driver：基于 HiveServer2 Thrift（10000）
- 流式结果：Session + Operation + Result Fetch（支持流式 watermark）

### Databricks

- SQL Statement Execution API：HTTPS REST
- Thrift JDBC/ODBC Server：端口 443 + 路径 `/sql/1.0/endpoints/{id}`
- 结果集可选 Arrow 格式（Photon 引擎直接输出列存）

### Teradata

- 协议：CLIv2 over TCP，端口 1025
- Teradata Director Program (TDP) 协议
- 认证：Teradata 密码、LDAP、Kerberos、JWT
- FastLoad / FastExport / MultiLoad / TPT：各自独立的批量协议，基于 CLIv2 扩展

### Greenplum

- PostgreSQL v3 协议（端口 5432）
- Master 节点接受 PG 连接，Segment 之间用 Greenplum Interconnect（UDP-based MPP 通信）
- gpfdist：独立的 HTTP 协议用于外部表加载

### CockroachDB

- PostgreSQL v3 协议，端口 26257
- 兼容度：~95%（缺少少数扩展如 LISTEN/NOTIFY、部分系统表）
- 默认强制 TLS
- 驱动可直接用 pgx / psycopg3 / JDBC PostgreSQL

### TiDB

- MySQL Protocol，端口 4000
- 兼容度：~99% 对应 MySQL 5.7 和 8.0 子集
- TLS 支持 + 压缩协议
- 扩展：`TIDB_*` 系统命令不走 MySQL 标准

### OceanBase

- MySQL Protocol（端口 2881）+ Oracle 模式（端口 2881，同端口不同租户）
- OBClient / obcli 客户端是 MySQL 客户端的 fork
- Oracle 模式支持 OCI 子集（通过专有代理）

### YugabyteDB

- YSQL：PostgreSQL v3（端口 5433），基于 PG 11 代码
- YCQL：Cassandra CQL Native Protocol（端口 9042）
- 单集群双协议，表层共享底层存储

### SingleStore (MemSQL)

- MySQL Protocol（端口 3306）
- 完全兼容 MySQL 8.0 基础客户端
- 扩展：管理 API 走独立 HTTP

### Vertica

- 基于 PostgreSQL 协议（wire 兼容，非源码 fork；起源于 C-Store 项目）
- 端口 5433；wire 协议层与 PG 兼容，但服务端是起源于 C-Store (MIT/Brown, 2005) 的 clean-room 实现
- 专有 COPY（本地和 HDFS/S3）

### StarRocks / Apache Doris

- 查询：MySQL Protocol（端口 9030）
- 导入：HTTP Stream Load（端口 8030/8040）
- Stream Load 是列式导入协议，性能远超 INSERT

### MonetDB

- MAPI (MonetDB API) Protocol，端口 50000
- 文本协议（请求 + 多行响应），少量二进制块
- ODBC / JDBC / Python / R 驱动

### CrateDB

- PostgreSQL v3 协议，端口 5432
- 所有标准 PG 驱动可用
- 兼容度受限：OIDC 认证、部分系统表

### TimescaleDB

- PostgreSQL 扩展，完全继承 PG 协议（端口 5432）
- 客户端视角无任何协议差异

### QuestDB

- 三协议并存：
  - PostgreSQL v3（端口 8812，只读查询用）
  - InfluxDB Line Protocol over TCP（端口 9009，高速写入）
  - HTTP REST（端口 9000，查询 + 导入）
- ILP 的性能特点：每连接 > 1M 行/秒

### Exasol

- 基于 WebSocket 的 JSON 协议（端口 8563）
- 所有消息都是 JSON，无二进制帧
- 强制 TLS
- JDBC / ODBC 驱动是 WebSocket 客户端的包装

### SAP HANA

- SQLDBC 协议（端口 30015 = 3NN15，NN=实例号）
- 二进制协议，支持流式取数与 XA 事务
- 客户端：HDBCLI、ODBC、JDBC、ADO.NET、Python hdbcli、Node @sap/hana-client

### Informix

- SQLI (Structured Query Language Interface) 协议，端口 1526
- 基于 ASF/ODS 版本协商
- DRDA 兼容层（可让 DB2 客户端连 Informix）

### Firebird

- Wire Protocol over XDR（eXternal Data Representation），端口 3050
- 协议版本 10-17（v3.0 → v5.0）
- 同一连接可混合 DSQL 和 Services API

### H2

- 默认私有 TCP 协议（端口 9092）
- PG Server 模式：H2 可作为 PG 协议服务端，兼容 psql 连接
- Web 模式：HTTP 控制台

### HSQLDB

- 私有 HSQL 协议（端口 9001）
- HTTP/HTTPS 协议可选
- Apache OpenOffice / LibreOffice 内嵌版本用内存协议

### Derby

- DRDA 协议（端口 1527）
- 与 DB2 客户端完全兼容（可用 DB2 JDBC 驱动连 Derby）
- 嵌入式模式走 JVM 内调用

### Amazon Athena

- HTTPS AWS API，端口 443
- 查询异步：StartQueryExecution → GetQueryExecution 轮询 → GetQueryResults / Athena v3 Arrow
- JDBC/ODBC 驱动是 API 包装

### Azure Synapse / Fabric

- Dedicated pool：TDS（1433）
- Serverless SQL：TDS（1433）
- Fabric Warehouse：TDS + REST 混合

### Google Spanner

- gRPC + Protobuf（端口 443）
- PostgreSQL 接口（2022+，端口 5432，子集兼容）
- 事务语义：gRPC 流保持事务上下文

### Materialize

- PostgreSQL v3 协议（端口 6875）
- 扩展：`SUBSCRIBE` 语句把普通 PG 查询变成流式增量推送（基于 COPY 响应）

### RisingWave

- PostgreSQL v3 协议（端口 4566）
- 流式 SQL，客户端可以用 PG 工具连接并执行流定义

### InfluxDB (3.x / IOx)

- 查询：Arrow Flight SQL（端口 8086 或 443）
- 写入：Line Protocol over HTTP
- 之前 1.x/2.x 完全是 REST，无 SQL

### Databend

- MySQL Protocol（端口 3307）
- ClickHouse HTTP 协议（端口 8124）
- REST API（端口 8000）
- 设计哲学：多协议吸引不同生态

### Yellowbrick

- PostgreSQL v3（端口 5432）
- ybload 专有批量加载协议

### Firebolt

- HTTPS REST，端口 443
- JDBC/ODBC 驱动是 HTTP 客户端包装
- 无原生 TCP 协议

## 协议性能对比

### 单行查询 RTT 开销

| 协议 | Simple Query | Extended Query | 备注 |
|------|-------------|----------------|------|
| PostgreSQL v3 | 1 RTT | 2 RTT（Parse 缓存后 1 RTT） | 批量 pipeline 零等待 |
| MySQL | 1 RTT | 2 RTT（PREPARE + EXECUTE） | COM_STMT_CLOSE 无需额外 RTT |
| TDS | 1 RTT（sp_executesql） | 1 RTT（RPC + 已缓存计划） | MARS 下多路复用 |
| TNS/Net8 | 1 RTT | 1 RTT（OCI 绑定） | 默认 Array Fetch 10 行 |
| Snowflake HTTPS | 2-4 RTT（auth + query + poll + fetch） | 同 | HTTP 开销大 |
| BigQuery gRPC | 1 RTT + 2 RTT Storage Read | 同 | 并行消费 |
| Arrow Flight SQL | 1 RTT（GetFlightInfo）+ 1 RTT（DoGet） | 同 | gRPC stream 高效 |

### 1 亿行扫描吞吐（同机房）

| 协议/格式 | 吞吐（行/秒） | 原因 |
|----------|--------------|------|
| Arrow Flight SQL | 10M+ | 零拷贝列存 |
| ClickHouse Native | 8M+ | 列存 block |
| Spark JDBC + Arrow | 5M+ | Photon/Arrow 优化 |
| PostgreSQL Binary | 2M | 行级二进制 |
| MySQL 二进制 | 2M | 行级二进制 |
| PostgreSQL 文本 | 800k | 字符串编码 |
| MySQL 文本 | 500k | 字符串编码 + 扩展 |
| TDS 流式 | 1M | token 流 |
| Snowflake HTTPS (JSON) | 100k-300k | JSON 解析 |
| Snowflake HTTPS (Arrow) | 1M+ | v2 格式 |
| Thrift (HiveServer2) | 200k | Thrift 反序列化开销 |

## 安全考量

### TLS / 加密

| 协议 | TLS 支持方式 |
|------|-------------|
| PostgreSQL | SSLRequest 握手（保留 code）后 STARTTLS 升级 |
| MySQL | CLIENT_SSL 能力位 + TLS 升级 |
| TDS | PreLogin 的 ENCRYPTION 选项，TDS 8.0 强制 TLS 1.3 |
| Oracle TNS | TCPS 协议（独立端口）或 Native 加密 |
| Snowflake / BigQuery | 强制 TLS 1.2+（无明文端点） |
| gRPC | 天然 TLS |
| HTTP-based (Trino/ClickHouse HTTP) | HTTPS |

### 认证后门风险

- MySQL LOAD DATA LOCAL：恶意服务器可读客户端文件，默认禁用
- PG trust 认证：pg_hba.conf 配置错误可导致免密登录
- TDS 7.0 的密码混淆曾是明文等价强度，TLS 强制后才解决
- Oracle O3LOGON-MD5 在早期版本有降级攻击，需启用 `SQLNET.ALLOWED_LOGON_VERSION_SERVER=12`

### 协议级别 DoS

- PG StartupMessage 允许任意长参数，旧版本未限长
- MySQL 16MB 单包限制，大于需分片，中间代理需支持
- TDS 的 token 流式设计可被慢速客户端利用吃连接池

## 关键发现

1. **PostgreSQL 协议 v3 从 2003 年稳定至今超过 20 年未换大版本**，这是它成为事实标准的基础。CockroachDB、YugabyteDB、Materialize、RisingWave、Redshift、Aurora、Neon、Spanner PG 接口、CrateDB、Yellowbrick 都选择它。

2. **MySQL 协议的兼容性更重简单性，适合 OLTP 生态**。TiDB、Vitess、MariaDB、PolarDB、OceanBase、StarRocks、Doris、Databend、SingleStore、Aurora MySQL 都选它。"协议 10 + 4.1 能力位"是事实标准，但 8.0 默认 caching_sha2_password 造成老客户端兼容阵痛。

3. **TDS 是 Sybase 于 1984 年发明**，1988 年微软获得源码后演化为 SQL Server 协议。MS-TDS 规范 400+ 页，复杂度远超 PG/MySQL，但 MARS 和 BCP 是独特优势。

4. **Oracle TNS/Net8 封闭但可组合**：TNS 传输层 + TTC 会话层 + OPI 应用层的三层架构允许 RAC、DRCP、Data Guard 等高级能力。第三方难以完整复现，Amazon RDS Oracle 和 OCI 都直接用 Oracle 官方协议栈。

5. **Snowflake 是纯 HTTPS**，无 TCP 原生协议。驱动把 JDBC/ODBC 请求翻译成 REST 调用。好处：穿透代理/防火墙零成本。代价：延迟敏感场景不适合。

6. **BigQuery、Spanner、Databricks 选择 gRPC**，原因：HTTP/2 多路复用、Protobuf 严格 schema、云原生负载均衡成熟。

7. **Arrow Flight SQL (2022+)** 是第一个被多家 OLAP 引擎认同的标准化列存 wire 协议。Dremio、InfluxDB 3.x、Doris 已 GA，Trino/Spark 在讨论。它可能是 ODBC/JDBC 三十年后的首个真正替代者。

8. **ClickHouse 的多协议策略成功**：Native + HTTP + MySQL 9004 + PG 9005，让它能被不同生态的工具直接连上。这种"协议大杂烩"的设计反而是其快速渗透的关键。

9. **QuestDB / InfluxDB 的 Line Protocol** 专注写入（> 1M 行/秒），与 SQL 查询协议分离。这种双协议架构（写走 ILP，读走 PG/Flight SQL）在时序数据库中已成常态。

10. **PG 协议兼容阵营 > MySQL 协议兼容阵营 > Oracle 协议兼容阵营**：按新数据库选型来看，PostgreSQL 协议是明显赢家。这一方面是 PG 协议简洁稳定，另一方面是 MySQL 协议的 4.1 版本握手 + 认证插件纠缠让新实现者踌躇。

11. **"驱动即协议"的事实**：当你选 JDBC 驱动、psycopg、libpq、go-sql-driver 时，你实际上选择了特定的 wire 协议。API 标准（ODBC / JDBC / ADO.NET）只是把选择推迟了一步。

12. **连接池/中间件的协议敏感度**：PgBouncer 需要支持 PG 协议 v3 全部消息类型；ProxySQL 必须正确处理 MySQL 的 seq_id；Vitess VTGate 是完整的 MySQL 协议服务端。改协议就要改这一整条中间件链。

13. **嵌入式数据库（SQLite、DuckDB、H2 默认、Derby 嵌入模式）没有 wire 协议**，但都提供可选的 server 扩展（DuckDB-Flight、H2 TCP Server、Derby Network Server / DRDA）以供远程访问。

14. **SCRAM-SHA-256 是现代协议的共同选择**：PG 10+、MongoDB、Kafka SASL、LDAP 都支持。相较 MD5 / SHA1，它有盐、迭代、服务器验证，且不需要 TLS（虽然实践中两者总一起用）。

15. **协议版本协商的两种风格**：
    - "发了再说"：PG、MySQL 先发 startup/handshake，服务器决定
    - "试探后定"：TDS、TNS 先发 PreLogin/CONNECT，双方协商
    第二种更灵活，但增加 RTT；第一种更快，但降级兼容需要客户端支持重试。

## 参考资料

- PostgreSQL: [Frontend/Backend Protocol](https://www.postgresql.org/docs/current/protocol.html)
- MySQL: [Client/Server Protocol](https://dev.mysql.com/doc/dev/mysql-server/latest/PAGE_PROTOCOL.html)
- MS-TDS: [[MS-TDS] Tabular Data Stream Protocol](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-tds/)
- Oracle Net Services: [Oracle Database Net Services Reference](https://docs.oracle.com/en/database/oracle/oracle-database/21/netrf/index.html)
- DRDA: [Open Group DRDA Specification](https://publications.opengroup.org/c066)
- Apache Arrow Flight SQL: [Flight SQL Protocol](https://arrow.apache.org/docs/format/FlightSql.html)
- ADBC: [Arrow Database Connectivity](https://arrow.apache.org/adbc/)
- ClickHouse Native Protocol: [ClickHouse/src/Client](https://github.com/ClickHouse/ClickHouse/tree/master/src/Client)
- Snowflake JDBC: [snowflake-jdbc source](https://github.com/snowflakedb/snowflake-jdbc)
- Cassandra Native Protocol v5: [cassandra/doc/native_protocol_v5.spec](https://github.com/apache/cassandra/blob/trunk/doc/native_protocol_v5.spec)
- pgbouncer protocol notes: [Official pgbouncer docs](https://www.pgbouncer.org/usage.html)
- MySQL Protocol Analysis: [Jan Lindström, Percona blog](https://www.percona.com/blog/)
- Exasol WebSocket API: [Exasol WebSocket API](https://github.com/exasol/websocket-api)
- Firebird Wire Protocol: [firebird/docs/firebird-protocol.md](https://firebirdsql.org/file/documentation/html/en/firebirddocs/pr-wire-protocol/firebird-protocol.html)
- Teradata CLIv2: [Teradata Call-Level Interface Version 2 Reference](https://docs.teradata.com/)
- SAP HANA SQLDBC: [SAP HANA Client Interface Programming Reference](https://help.sap.com/docs/SAP_HANA_CLIENT)
