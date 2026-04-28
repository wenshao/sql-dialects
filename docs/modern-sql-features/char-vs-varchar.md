# 字符类型语义对比 (CHAR vs VARCHAR vs TEXT)

`CHAR(10)`、`VARCHAR(10)`、`TEXT`——这三个看似简单的字符类型，是 SQL 引擎中最容易让人误用的"陷阱组合"。一个 `CHAR(10)` 列在 PostgreSQL 中存 `'abc'` 会变成 `'abc       '`（右补 7 个空格），在 Snowflake 中却原样保存；同样的 `VARCHAR(255)` 在 MySQL 5.0.3 之前最多存 255 字符，之后变成 65535 字节；同样写 `TEXT`，在 SQL Server 是 2GB 大对象（已废弃），在 PostgreSQL 是 1GB 普通字符串，在 ClickHouse 则是无长度限制的 `String`。本文系统对比 45+ 数据库的 `CHAR`/`VARCHAR`/`TEXT`/`NCHAR`/`NVARCHAR` 语义差异，覆盖填充行为、长度语义、最大尺寸、性能影响等核心维度，是引擎开发者和跨库迁移工程师的必备参考。

## SQL:1992 标准定义

SQL:1992 (ISO/IEC 9075-2) 在第 4.2 节首次形式化定义了字符类型，奠定了"定长 + 变长"二分法：

```sql
<character string type> ::=
      CHARACTER [ <left paren> <length> <right paren> ]
    | CHAR [ <left paren> <length> <right paren> ]
    | CHARACTER VARYING <left paren> <length> <right paren>
    | CHAR VARYING <left paren> <length> <right paren>
    | VARCHAR <left paren> <length> <right paren>

<national character string type> ::=
      NATIONAL CHARACTER [ <left paren> <length> <right paren> ]
    | NATIONAL CHAR [ <left paren> <length> <right paren> ]
    | NCHAR [ <left paren> <length> <right paren> ]
    | NATIONAL CHARACTER VARYING <left paren> <length> <right paren>
    | NCHAR VARYING <left paren> <length> <right paren>
```

标准的关键语义点：

1. **CHAR(n) 是定长类型**：长度 < n 时必须右补空格 (right-pad with spaces)，长度 > n 时报错
2. **VARCHAR(n) 是变长类型**：仅记录实际长度，不补空格；溢出仍然报错
3. **NCHAR / NVARCHAR**：使用国家字符集 (national character set)，通常是 Unicode（UCS-2/UTF-16）
4. **比较语义 (PAD SPACE 默认)**：标准默认 `'abc' = 'abc   '`（短串末尾补空格后再比较）
5. **长度单位是字符 (character)**：标准定义为字符数，但具体字符 = 字节数还是 Unicode 码点取决于字符集
6. **CLOB (SQL:1999)**：`CHARACTER LARGE OBJECT`，独立的大对象类型，详见 [`blob-clob-handling.md`](./blob-clob-handling.md)

> SQL:2008 引入了 `CHARACTER LARGE OBJECT` 的可变长度规范，允许 CLOB 也带 `(n)` 长度修饰；SQL:2003 在排序规则匹配时引入 `NO PAD` 选项，允许引擎覆盖标准默认的 `PAD SPACE` 比较行为。

## 总体支持矩阵 (45+ 引擎)

### CHAR 填充与比较行为

下表汇总 45+ 引擎对 `CHAR(n)` 列的右填充 (right-pad) 与比较时空格修剪 (space trimming) 行为：

| 引擎 | 存储时右填充空格 | 检索时返回带填充值 | 比较时按空格修剪 (PAD SPACE) | CHAR 最大长度 |
|------|----------------|-----------------|-----------------------|-------------|
| PostgreSQL | 是 | 是 | 是 (CHAR 比较忽略尾部空格) | 10485760 字符 |
| MySQL | 是 | 否 (尾空格被剥离) | 是 (PAD SPACE 默认) | 255 字符 |
| MariaDB | 是 | 否 (同 MySQL) | 是 | 255 字符 |
| SQLite | 否 (TEXT 亲和) | 否 | 否 | 受 BLOB 限制 (~1GB) |
| Oracle | 是 | 是 (blank-padded) | 是 (CHAR 启用 blank-padded 比较) | 2000 字节 |
| SQL Server | 是 (依赖 ANSI_PADDING) | 是 | 是 (= 比较时) | 8000 字节 |
| DB2 | 是 | 是 | 是 (PAD SPACE) | 254 字节 |
| Snowflake | 否 (CHAR = VARCHAR 别名) | 否 | 否 (CHAR 不补空格) | 16777216 字节 |
| BigQuery | -- (无 CHAR 类型) | -- | -- | 不适用 |
| Redshift | 是 | 是 | 是 | 4096 字节 |
| DuckDB | 否 (CHAR = VARCHAR 别名) | 否 | 否 | 无显式上限 |
| ClickHouse | -- (无 CHAR；FixedString 右补 \0) | -- | -- | 无 (FixedString 任意 n) |
| Trino | 是 | 是 | 是 (PAD SPACE) | 65536 字符 |
| Presto | 是 | 是 | 是 | 65536 字符 |
| Spark SQL | 是 | 否 (默认剥离尾空格) | 是 | 受 STRING 限制 |
| Hive | 是 | 否 | 是 | 255 字符 |
| Flink SQL | 是 | 是 | 是 | 2147483647 字符 |
| Databricks | 是 | 否 | 是 | 受 STRING 限制 |
| Teradata | 是 | 是 | 是 (PAD SPACE) | 64000 字符 |
| Greenplum | 是 (继承 PG) | 是 | 是 | 10485760 字符 |
| CockroachDB | 是 (兼容 PG) | 是 | 是 | 与 PG 一致 |
| TiDB | 是 (兼容 MySQL) | 否 | 是 | 255 字符 |
| OceanBase (MySQL 模式) | 是 | 否 | 是 | 255 字符 |
| OceanBase (Oracle 模式) | 是 | 是 | 是 | 2000 字节 |
| YugabyteDB | 是 (兼容 PG) | 是 | 是 | 1 GB |
| SingleStore | 是 (兼容 MySQL) | 否 | 是 | 255 字符 |
| Vertica | 是 | 是 | 是 (PAD SPACE) | 65000 字节 |
| Impala | 是 | 是 | 是 | 255 字符 |
| StarRocks | 是 | 是 | 是 | 255 字节 |
| Doris | 是 | 是 | 是 | 255 字节 |
| MonetDB | 是 | 是 | 是 | 受系统资源限制 |
| CrateDB | -- (无 CHAR 类型) | -- | -- | 不适用 |
| TimescaleDB | 是 (继承 PG) | 是 | 是 | 1 GB |
| QuestDB | -- (无 CHAR 类型) | -- | -- | 不适用 |
| Exasol | 是 | 是 | 是 | 2000 字符 |
| SAP HANA | 是 | 是 | 是 | 5000 字节 (CHAR 已废弃) |
| Informix | 是 | 是 | 是 | 32767 字节 |
| Firebird | 是 | 是 | 是 (PAD SPACE) | 32767 字节 |
| H2 | 是 (符合 SQL 标准) | 是 | 是 | 1000000000 字符 |
| HSQLDB | 是 | 是 | 是 | 16777216 字符 (理论) |
| Derby | 是 | 是 | 是 | 254 字符 |
| Amazon Athena | 是 (继承 Trino) | 是 | 是 | 65536 字符 |
| Azure Synapse | 是 (继承 SQL Server) | 是 | 是 | 8000 字节 |
| Google Spanner | -- (无 CHAR 类型) | -- | -- | 不适用 |
| Materialize | 是 (兼容 PG) | 是 | 是 | 与 PG 一致 |
| RisingWave | 是 (兼容 PG) | 是 | 是 | 与 PG 一致 |
| InfluxDB (SQL) | -- (无 CHAR 类型) | -- | -- | 不适用 |
| DatabendDB | -- (无 CHAR 类型) | -- | -- | 不适用 |
| Yellowbrick | 是 | 是 | 是 | 64000 字节 |
| Firebolt | -- (无 CHAR 类型) | -- | -- | 不适用 |

> 注：上表中 "存储时右填充空格" 描述插入或更新时 CHAR(n) 是否会自动追加空格使长度等于 n。"检索时返回带填充值" 描述 SELECT 时是否原样返回填充。"比较时按空格修剪" 描述 `'abc' = 'abc  '` 是否为 true。

### VARCHAR 最大长度与编码语义

| 引擎 | VARCHAR 最大长度 | 长度单位 (字符 / 字节) | 行级总大小限制 | 版本说明 |
|------|----------------|---------------------|--------------|---------|
| PostgreSQL | 10485760 字符 (~10MB) | 字符 (UTF-8 多字节) | 1.6TB 行 (TOAST) | 全版本 |
| MySQL | 65535 字节 (行级总和) | 字符 (但映射为字节) | 65535 字节 (含其他列) | 5.0.3+ (之前为 255 字符) |
| MariaDB | 65535 字节 (行级总和) | 字符 | 65535 字节 | 全版本 (兼容 MySQL 5.0.3+) |
| SQLite | 无显式上限 (受 BLOB 限制) | 字节 (TEXT 亲和性) | -- | 类型亲和性 |
| Oracle | 4000 字节 (默认) | 字节或字符 (取决于 SEMANTICS 参数) | 行级 ~256KB | 12c 起 `MAX_STRING_SIZE=EXTENDED` 支持 32767 字节 |
| SQL Server | 8000 字节，`VARCHAR(MAX)` 达 2GB | 字节 (单字节) / 字符 (Unicode) | 8060 字节 (含其他列) | `VARCHAR(MAX)` 自 2005 引入 |
| DB2 | 32672 字节 | 字节 (默认) 或 OCTETS | 32677 字节 (页 = 32K 时) | 全版本 |
| Snowflake | 16777216 字节 (16MB) | 字符 (`CHARACTER`) | 列级 16MB | GA |
| BigQuery | 10485760 字节 (10MB) | 字节 | 行级 100MB | GA |
| Redshift | 65535 字节 | 字节 | 行级 4MB (默认) | GA |
| DuckDB | 无显式上限 | 字符 | 受内存限制 | 0.3+ |
| ClickHouse | 无 (`String` 类型) | 字节 | 受系统资源 | 全版本 |
| Trino | 无显式上限 | 字符 | -- | 全版本 |
| Presto | 无显式上限 | 字符 | -- | 全版本 |
| Spark SQL | 受 STRING 限制 (~2GB) | 字符 (但行为类似 STRING) | -- | 3.0+ |
| Hive | 65535 字符 | 字符 | -- | 0.12+ (CHAR 0.13+) |
| Flink SQL | 2147483647 字符 | 字符 | -- | 全版本 |
| Databricks | 受 STRING 限制 | 字符 | -- | -- |
| Teradata | 64000 字符 | 字符 | -- | -- |
| Greenplum | 1 GB | 字符 | -- | 继承 PG |
| CockroachDB | 无显式上限 | 字符 | -- | 兼容 PG |
| TiDB | 65535 字节 (兼容 MySQL) | 字符 | 65535 字节 | 全版本 |
| OceanBase (MySQL) | 65535 字节 | 字符 | 65535 字节 | 全版本 |
| OceanBase (Oracle) | 4000 / 32767 字节 | 字节 / 字符 | 取决于参数 | 全版本 |
| YugabyteDB | 1 GB (继承 PG) | 字符 | -- | 全版本 |
| SingleStore | 65535 字节 | 字符 | 65535 字节 | 全版本 |
| Vertica | 65000 字节 | 字节 (默认) | 32MB 行 | 全版本 |
| Impala | 受 STRING 限制 (~2GB) | 字符 | -- | 全版本 |
| StarRocks | 65535 字节 (默认) / 1MB / `STRING` 1MB | 字节 | -- | 2.5+ |
| Doris | 65535 字节 (默认) | 字节 | -- | 1.2+ |
| MonetDB | 无显式上限 | 字符 | -- | 全版本 |
| CrateDB | 无显式上限 | 字符 | -- | 全版本 |
| TimescaleDB | 1 GB (继承 PG) | 字符 | -- | 全版本 |
| QuestDB | 无显式上限 | UTF-8 字节 | -- | 7.3+ (varchar 类型) |
| Exasol | 2000000 字符 | 字符 | -- | 全版本 |
| SAP HANA | 5000 字节 (`VARCHAR`) / 5000 字符 (`NVARCHAR`) | 字节 (`VARCHAR` 已废弃) / 字符 (`NVARCHAR`) | -- | 全版本 |
| Informix | 255 字节 (VARCHAR) / 32739 字节 (LVARCHAR) | 字节 | -- | 全版本 |
| Firebird | 32767 字节 (页大小决定) | 字节或字符 | -- | 全版本 |
| H2 | 1000000000 字符 | 字符 | -- | 全版本 |
| HSQLDB | 16777216 字符 | 字符 | -- | 全版本 |
| Derby | 32672 字节 | 字符 | -- | 全版本 |
| Amazon Athena | 65535 字符 | 字符 | -- | 继承 Trino |
| Azure Synapse | 8000 字节 / `VARCHAR(MAX)` 2GB | 字节 (单字节) / 字符 (Unicode) | -- | 继承 SQL Server |
| Google Spanner | 10485760 字节 (10MB) | 字节 | 行级 4MB | 全版本 |
| Materialize | 1 GB (继承 PG) | 字符 | -- | 全版本 |
| RisingWave | 1 GB (继承 PG) | 字符 | -- | 全版本 |
| InfluxDB (SQL) | -- (字符串列存为 STRING) | 字节 | -- | IOx 引擎 |
| DatabendDB | 1 MB (推荐) | 字节 | -- | 全版本 |
| Yellowbrick | 64000 字节 | 字节 | -- | 全版本 |
| Firebolt | 受 TEXT 限制 (8MB) | 字节 | -- | 全版本 |

### TEXT / CLOB 阈值与替代方案

不同引擎对"超大字符串"的处理路径分化为四类：(a) 专用 TEXT 类型族，(b) 标准 CLOB 类型，(c) `VARCHAR(MAX)` 替代，(d) 与 `VARCHAR` 合并的统一类型。

| 引擎 | 大字符串类型 | 临界点 / 阈值 | 内联存储阈值 | 大对象引擎 |
|------|------------|------------|------------|----------|
| PostgreSQL | `TEXT` (无长度) | 1 GB (varlena 上限) | ~2KB (TOAST) | TOAST 表 |
| MySQL | `TINYTEXT` (255B) / `TEXT` (64KB) / `MEDIUMTEXT` (16MB) / `LONGTEXT` (4GB) | 65535 字节 起 | 768 字节 (溢出) | 溢出页 |
| MariaDB | 同 MySQL | 同 MySQL | 同 MySQL | 同 MySQL |
| SQLite | `TEXT` (动态) | 由 `SQLITE_MAX_LENGTH` 决定 (默认 ~1GB) | 页内 / 溢出页 | 溢出页链 |
| Oracle | `CLOB` / `NCLOB` (自 SQL:1999) | (4GB-1) × `DB_BLOCK_SIZE` 字节 (约 128 TB) | 4000 字节 (`ENABLE STORAGE IN ROW`) | LOB 段 (SECUREFILE) |
| SQL Server | `VARCHAR(MAX)` / `NVARCHAR(MAX)` | 2 GB | 8000 字节 (溢出到 LOB 单元) | `LOB_DATA` 分配单元 |
| DB2 | `CLOB(n)` / `LONG VARCHAR` | 2 GB (CLOB) / 32700 字节 (LONG VARCHAR) | 由 `INLINE LENGTH` 决定 | LOB 表空间 |
| Snowflake | `VARCHAR` / `STRING` / `TEXT` 全部别名 | 16 MB (`VARCHAR(16777216)`) | 微分区列存 | 列存自动 |
| BigQuery | `STRING` | 10 MB (列值) | 列式 Capacitor | -- |
| Redshift | `VARCHAR(65535)` | 65535 字节 | 行存压缩 | -- |
| DuckDB | `VARCHAR` / `TEXT` (别名) | 无限制 | 列存 | -- |
| ClickHouse | `String` | 无限制 | LZ4 列存 | -- |
| Trino | `VARCHAR` | 连接器决定 | -- | 连接器层 |
| Presto | `VARCHAR` | 同 Trino | -- | -- |
| Spark SQL | `STRING` | ~2 GB (JVM 数组限制) | -- | -- |
| Hive | `STRING` | 2 GB | -- | HDFS |
| Flink SQL | `STRING` / `VARCHAR` | 2147483647 字符 | -- | -- |
| Databricks | `STRING` | -- | Delta 文件 | -- |
| Teradata | `CLOB` | 2 GB | 行内 / 行外 | -- |
| Greenplum | `TEXT` (1GB) / 外存 LOB | 1 GB | TOAST | TOAST |
| CockroachDB | `STRING` (无长度) | 64 MiB (软限制) / 1 GB (硬限制) | KV 行 | -- |
| TiDB | `TEXT` 系列 (兼容 MySQL) | 4GB (LONGTEXT) | 6MB 单列默认 | 自动溢出 |
| OceanBase | `TEXT` (M) / `CLOB` (O) | 48MB / 512MB | 24KB 内联 | LOB 段 |
| YugabyteDB | `TEXT` | 256 MB (软限制) | -- | -- |
| SingleStore | `TEXT..LONGTEXT` | 4 GB | -- | -- |
| Vertica | `LONG VARCHAR` | 32 MB | 投影内联 | -- |
| Impala | `STRING` | 2 GB | Parquet 列存 | -- |
| StarRocks | `STRING` / `VARCHAR(1048576)` | 1 MB (默认) / 2 GB (调参) | -- | -- |
| Doris | `STRING` | 2 GB | -- | -- |
| MonetDB | `TEXT` / `CLOB` (`STRING` 别名) | ~2 GB | 列式 BAT | -- |
| CrateDB | `TEXT` | 受 Lucene 限制 (32766 字节/term) | -- | Elasticsearch |
| TimescaleDB | `TEXT` | 1 GB | TOAST | TOAST |
| QuestDB | `string` (32767) / `varchar` (无限) | -- | -- | -- |
| Exasol | `CLOB` (2 MB 列限制实际等同 VARCHAR) | 2 MB | 列存 | -- |
| SAP HANA | `CLOB` / `NCLOB` (`TEXT` 已废弃) | 2 GB | INLINE LOB | LOB 容器 |
| Informix | `TEXT` (传统) / `CLOB` (Smart LOB) | 2 GB / 4 TB | -- | Smart Large Object Space |
| Firebird | `BLOB SUB_TYPE 1 (TEXT)` | 4 GB | 8KB 页 | BLOB 段链 |
| H2 | `CLOB` | 2^31-1 字节 | 32K 内联 | 独立页 |
| HSQLDB | `CLOB` | 64 TB (理论) | -- | `.lobs` 文件 |
| Derby | `CLOB` | 2 GB | 32K 行内 | 独立页 |
| Amazon Athena | `VARCHAR` | 受存储格式限制 | -- | S3 |
| Azure Synapse | `VARCHAR(MAX)` / `NVARCHAR(MAX)` | 2 GB | 8060 字节 | LOB 单元 |
| Google Spanner | `STRING(MAX)` | 10 MiB (列) | -- | -- |
| Materialize | `TEXT` | 继承 PG (1 GB) | -- | -- |
| RisingWave | `TEXT` / `VARCHAR` | 继承 PG | -- | -- |
| InfluxDB (SQL) | `STRING` | 64KB (field 软限制) | -- | TSM |
| DatabendDB | `STRING` | 1 MB (推荐) | Parquet | -- |
| Yellowbrick | `VARCHAR` (64000) | 64000 字节 | -- | -- |
| Firebolt | `TEXT` | 8 MB | -- | -- |

### NCHAR / NVARCHAR：Unicode 显式标注

`NCHAR` / `NVARCHAR` (`NATIONAL CHAR / VARCHAR`) 是 SQL:1992 定义的"国家字符集"类型。在历史上字符集默认是 ASCII/Latin-1 的引擎中，N 类型用于显式标注"使用 Unicode"。今天大多数引擎默认 UTF-8，N 类型的存在感大幅减弱。

| 引擎 | NCHAR | NVARCHAR | NCLOB / NTEXT | 与非 N 类型的差异 |
|------|-------|---------|--------------|-------------------|
| PostgreSQL | 解析为 CHAR | 解析为 VARCHAR | -- | 完全无差异 (使用数据库级编码) |
| MySQL | 是 | 是 | -- | 等价于 `CHAR CHARACTER SET utf8`|
| MariaDB | 是 | 是 | -- | 同 MySQL |
| SQLite | -- | -- | -- | TEXT 亲和性，无 N 概念 |
| Oracle | 是 | `NVARCHAR2` | `NCLOB` | 强制使用 NLS_NCHAR_CHARACTERSET (通常 AL16UTF16) |
| SQL Server | 是 | 是 | `NTEXT` (废弃) | N 类型 = UCS-2/UTF-16；非 N = 单字节字符集 |
| DB2 | 是 (`GRAPHIC`) | 是 (`VARGRAPHIC`) | `DBCLOB` | DB2 中 GRAPHIC = 双字节字符 |
| Snowflake | -- | -- | -- | 默认 UTF-8，无 N 类型 |
| BigQuery | -- | -- | -- | STRING 默认 UTF-8 |
| Redshift | -- | -- | -- | VARCHAR 默认 UTF-8 |
| DuckDB | -- | -- | -- | VARCHAR 即 UTF-8 |
| ClickHouse | -- | -- | -- | String 即 UTF-8 |
| Trino | 解析忽略 | 解析忽略 | -- | 无差异 |
| Presto | 解析忽略 | 解析忽略 | -- | 无差异 |
| Spark SQL | -- | -- | -- | STRING 即 UTF-8 |
| Hive | -- | -- | -- | STRING 即 UTF-8 |
| Flink SQL | -- | -- | -- | STRING 即 UTF-8 |
| Teradata | -- | -- | -- | CHARACTER SET 子句 |
| TiDB | 是 (兼容 MySQL) | 是 | -- | 与 utf8 等价 |
| OceanBase (Oracle) | 是 | `NVARCHAR2` | -- | 与 Oracle 相同 |
| Azure Synapse | 是 | 是 | -- | 与 SQL Server 相同 |
| SAP HANA | -- | 是 | `NCLOB` | NVARCHAR 用 UTF-16，VARCHAR 单字节 (已废弃) |
| H2 | 是 (别名) | 是 (别名) | `NCLOB` | 等价于 CHAR/VARCHAR/CLOB |
| HSQLDB | 是 (别名) | 是 (别名) | `NCLOB` | 等价于 CHAR/VARCHAR/CLOB |
| Derby | 是 (别名) | 是 (别名) | -- | 等价于 CHAR/VARCHAR |

> 关键观察：
> - **PostgreSQL/Trino/Hive/Spark/ClickHouse 等"现代默认 UTF-8"引擎**：N 类型若被支持，仅作为 CHAR/VARCHAR 别名解析，无任何差异
> - **SQL Server/Oracle 等"传统多字符集"引擎**：N 类型有真实差异，使用专用的 Unicode 编码 (UCS-2 / UTF-16 / AL16UTF16)
> - **DB2** 用 `GRAPHIC` / `VARGRAPHIC` / `DBCLOB` 三件套，是早期双字节字符集 (DBCS) 的产物

### 长度语义 (字节 vs 字符)

| 引擎 | VARCHAR(n) 默认含义 | 显式控制方式 |
|------|------------------|------------|
| PostgreSQL | 字符 | 无 (固定字符语义) |
| MySQL | 字符 (但行级总和按字节计) | `CHARSET=` 影响每字符字节数 |
| MariaDB | 字符 | 同 MySQL |
| SQLite | 字节 (TEXT 亲和性) | 无 |
| Oracle | 字节 (默认) | `VARCHAR2(10 BYTE)` / `VARCHAR2(10 CHAR)` ；会话参数 `NLS_LENGTH_SEMANTICS=BYTE/CHAR` |
| SQL Server | 字节 | `VARCHAR` = 单字节字符集；`NVARCHAR` = 字符 (但实际是 UTF-16 码元) |
| DB2 | 字节 | `VARCHAR(10 OCTETS)` 显式字节 ; `VARCHAR(10 CODEUNITS32)` 显式字符 |
| Snowflake | 字符 | 无 |
| BigQuery | 字节 | 无 (STRING 长度按字节) |
| Redshift | 字节 | 无 (VARCHAR(n) 中 n 是字节数) |
| DuckDB | 字符 | 无 |
| ClickHouse | -- | `FixedString(n)` 中 n 是字节 |
| Trino / Presto | 字符 | 无 |
| Spark SQL | 字符 | 无 |
| Hive | 字符 | 无 |
| Teradata | 字符 (默认) | `CHARACTER SET LATIN` 字节; `UNICODE` 字符 |
| TiDB | 字符 (兼容 MySQL) | -- |
| OceanBase (MySQL) | 字符 | -- |
| OceanBase (Oracle) | 字节 (默认) | `BYTE` / `CHAR` 修饰 |
| Azure Synapse | 字节 / 字符 | 同 SQL Server |
| SAP HANA | 字节 (`VARCHAR`) / 字符 (`NVARCHAR`) | 通过类型选择 |
| Vertica | 字节 (默认) | -- |
| Informix | 字节 | -- |
| Firebird | 取决于 `CHARACTER SET` 子句 | `VARCHAR(10) CHARACTER SET UTF8` 时 n 仍是字符 |
| H2 / HSQLDB / Derby | 字符 | -- |
| Google Spanner | 字节 | `STRING(n)` 中 n 是字节 |

### CHAR vs VARCHAR 存储差异

| 引擎 | CHAR(n) 存储 | VARCHAR(n) 存储 | 内部是否合并 |
|------|------------|----------------|-----------|
| PostgreSQL | 总是 n 字符宽 (右补空格)，但底层仍 varlena | 仅实际长度 (varlena) | 内部都是 varlena，CHAR 仅多一步补空格 |
| MySQL (InnoDB) | 行内 `n × max_byte_per_char` 固定字节 (如 utf8mb4 的 CHAR(10) = 40 字节) | 1 或 2 字节长度前缀 + 实际字节 | 不同 |
| Oracle | 总是 n 字节宽 (CHAR 语义) 或 n 字符宽 (CHAR 语义) | 仅实际长度 | 不同 (CHAR 在行存固定占 n 字节) |
| SQL Server | n 字节 (CHAR) 或 2n 字节 (NCHAR) | 2 字节长度 + 实际数据 | 不同 |
| DB2 | n 字节固定 | 2/4 字节长度 + 实际 | 不同 |
| SQLite | 动态长度 (TEXT 亲和性) | 动态长度 | 完全合并 |
| Snowflake | 同 VARCHAR | 同 VARCHAR | 完全合并 |
| DuckDB | 同 VARCHAR | 同 VARCHAR | 完全合并 |
| Trino / Presto | CHAR 行内填充 | VARCHAR 不填充 | 不同 |
| Hive | 同 VARCHAR (RCFile/ORC 列存) | 同 VARCHAR | 列存格式按列处理 |

## SQL:1992 与标准变迁

```sql
-- SQL:1992 第 4.2.1 节定义的核心语义:
-- 1. CHARACTER(n) 是固定长度字符串
-- 2. CHARACTER VARYING(n) 是可变长度字符串
-- 3. 短于 n 的 CHAR 值，存储/传输时右补空格至 n
-- 4. 短于 n 的 VARCHAR 值，记录实际长度
-- 5. 默认比较是 PAD SPACE：'abc' = 'abc   ' 为 TRUE
-- 6. 默认排序按字符代码点；字符集决定可存内容

-- SQL:1999 引入 CLOB
CREATE TABLE doc (
    id INT,
    body CHARACTER LARGE OBJECT(2G)  -- CLOB 标准语法
);

-- SQL:2003 引入 NO PAD 排序规则
-- COLLATE "binary" / "C" 等通常是 NO PAD
-- 此时 'abc' <> 'abc   '
```

历史里程碑：

- **1992**：SQL:1992 (SQL2) 正式定义 CHAR(n) / VARCHAR(n) / NCHAR / NVARCHAR
- **1999**：SQL:1999 (SQL3) 引入 CLOB / NCLOB
- **2003**：SQL:2003 引入 `NO PAD` 排序规则属性，允许覆盖默认 PAD SPACE 比较
- **2008**：SQL:2008 完善 CLOB 长度修饰
- **2016**：SQL:2016 在 JSON 上下文中重新审视字符串语义

## 各引擎深入解析

### PostgreSQL：CHAR 补空格，VARCHAR/TEXT 行为相同

PostgreSQL 严格遵循 SQL 标准对 CHAR 的填充规则，但对 VARCHAR 和 TEXT 在内部实现上几乎完全相同。

```sql
-- 创建测试表
CREATE TABLE pg_chartypes (
    c_char  CHAR(10),       -- 定长，右补空格
    c_vchar VARCHAR(10),    -- 变长，最多 10 字符
    c_text  TEXT            -- 变长，无长度限制（但单值 ≤ 1GB）
);

INSERT INTO pg_chartypes VALUES ('abc', 'abc', 'abc');

-- 验证 CHAR 右填充：
SELECT length(c_char), length(c_vchar), length(c_text) FROM pg_chartypes;
--  length | length | length
-- --------+--------+--------
--      10 |      3 |      3   ← CHAR 被填充到 10 字符

SELECT '|' || c_char || '|' AS char_padded,
       '|' || c_vchar || '|' AS varchar_no_pad,
       '|' || c_text || '|' AS text_no_pad
FROM pg_chartypes;
-- char_padded   | varchar_no_pad | text_no_pad
-- |abc       |  | |abc|          | |abc|

-- CHAR 比较忽略尾部空格 (PAD SPACE)
SELECT 'abc'::char(5) = 'abc'::char(10);   -- TRUE
SELECT 'abc'::char(5) = 'abc   '::varchar; -- TRUE (varchar 一侧也忽略尾空格)

-- VARCHAR/TEXT 之间比较保留尾部空格
SELECT 'abc'::text = 'abc   '::text;        -- FALSE
SELECT 'abc'::varchar = 'abc   '::varchar; -- FALSE
```

PostgreSQL 关键事实：
- **TEXT 与 VARCHAR(n) 内部存储完全相同**：都是 varlena 头 + 实际字节
- **CHAR(n) 的开销**：插入时填充空格，检索时返回填充值，比较时再修剪——比 VARCHAR 略慢
- **VARCHAR 不写长度时**：`VARCHAR` (无 n) 等价于 `TEXT`，无长度限制
- **TEXT 单值上限 1GB**：受 `varlena` 头部 30 位长度字段限制
- **不支持 NCHAR / NVARCHAR**：解析器接受但视为 CHAR / VARCHAR 别名

```sql
-- PostgreSQL 推荐：直接用 TEXT
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL,           -- 等同 VARCHAR(无限)
    bio TEXT
);
-- 不要写 VARCHAR(255)：n 限制带来运行时校验开销，不带来存储节省
```

### Oracle：VARCHAR2 主导，CHAR 仍 blank-padded

Oracle 是字符类型设计最分裂的引擎之一。

```sql
-- Oracle 字符类型一览：
CREATE TABLE oracle_chartypes (
    c_char    CHAR(10),         -- 右补空格至 10 字节
    c_varchar VARCHAR(10),      -- 保留语法但不推荐使用
    c_vc2     VARCHAR2(10),     -- 推荐：变长，最多 10 字节
    c_nchar   NCHAR(10),        -- AL16UTF16 编码，10 个 UCS-2 码元
    c_nvc2    NVARCHAR2(10),    -- AL16UTF16 编码，变长
    c_clob    CLOB,             -- 大字符对象，最多 (4GB-1) × 块大小
    c_long    LONG              -- 已废弃，只能有一个 LONG 列/表
);

-- VARCHAR2 长度语义切换：
CREATE TABLE t1 (
    name VARCHAR2(10 BYTE)      -- 10 字节，UTF-8 下中文不能存满 10 个
);
CREATE TABLE t2 (
    name VARCHAR2(10 CHAR)      -- 10 字符，UTF-8 下最多 30 字节
);

-- 会话级默认：
ALTER SESSION SET NLS_LENGTH_SEMANTICS = CHAR;  -- 默认改为 CHAR 语义

-- 12c 起的扩展：
-- 默认 VARCHAR2 限 4000 字节
-- 设置 MAX_STRING_SIZE=EXTENDED 后限 32767 字节 (需要先 PURGE RECYCLEBIN 等)
ALTER SYSTEM SET MAX_STRING_SIZE=EXTENDED SCOPE=SPFILE;

-- CHAR 比较 (blank-padded comparison)：
SELECT 'abc' = 'abc   ' FROM dual;
-- 在 Oracle 中：如果两侧任一为 CHAR(n)，使用 blank-padded 比较，结果为 1 (TRUE)
-- 如果两侧都是 VARCHAR2，使用 non-padded 比较，结果为 0 (FALSE)

-- 验证：
DECLARE
    a CHAR(5)     := 'abc';
    b VARCHAR2(5) := 'abc';
BEGIN
    IF a = b THEN
        DBMS_OUTPUT.PUT_LINE('equal');     -- 输出 equal (CHAR 一侧触发 blank-padded)
    END IF;
END;
```

Oracle 关键事实：
- **VARCHAR vs VARCHAR2**：Oracle 文档明确 `VARCHAR` 是为未来 SQL 标准对齐保留的关键字，今天与 `VARCHAR2` 等价；强烈推荐总是用 `VARCHAR2`
- **VARCHAR2 自 7.x 引入**：随后逐渐取代 `VARCHAR` 成为标准
- **LONG 已废弃**：1990 年代的设计，整个表只能有 1 个 LONG 列，限制极多；新代码必须用 CLOB
- **CHAR(n) 默认 1**：`CHAR` 不带括号默认 `CHAR(1)`，`VARCHAR2` 必须显式带长度
- **NCHAR/NVARCHAR2 用 AL16UTF16**：与会话字符集独立，长度按 UCS-2 码元计

### SQL Server：CHAR 补空格 (依赖 ANSI_PADDING)，TEXT/NTEXT 已废弃

SQL Server 的字符类型行为受 `SET ANSI_PADDING` 历史选项影响，SQL Server 2000 起默认 ON (连接默认自 7.0)。

```sql
-- SQL Server 字符类型：
CREATE TABLE sqlserver_chartypes (
    c_char    CHAR(10),         -- 单字节字符集 (ANSI 排序规则)，右补空格
    c_varchar VARCHAR(10),      -- 单字节，变长
    c_vchar_max VARCHAR(MAX),   -- 单字节，最大 2GB（替代 TEXT）
    c_nchar   NCHAR(10),        -- UCS-2/UTF-16，每字符 2 字节
    c_nvarchar NVARCHAR(10),    -- UCS-2/UTF-16，变长
    c_nvchar_max NVARCHAR(MAX), -- UTF-16，最大 2GB（替代 NTEXT）
    c_text    TEXT,             -- 已废弃 (since 2005)
    c_ntext   NTEXT             -- 已废弃 (since 2005)
);

-- ANSI_PADDING 历史：
-- ANSI_PADDING ON  (推荐，SQL Server 2000 起默认 ON，连接默认自 7.0)：CHAR 右补空格
-- ANSI_PADDING OFF (历史遗留)：CHAR 行为退化为 VARCHAR
SET ANSI_PADDING ON;

-- 验证 CHAR 填充：
DECLARE @c CHAR(10) = 'abc';
SELECT LEN(@c), DATALENGTH(@c);
-- LEN(@c) = 3        (LEN 不计尾空格)
-- DATALENGTH(@c) = 10 (字节数计尾空格)

-- VARCHAR(MAX) 替代 TEXT：
-- SQL Server 2005 起，TEXT/NTEXT 标记为废弃，新代码用 VARCHAR(MAX)/NVARCHAR(MAX)
-- VARCHAR(MAX) 优势：
--   1. 支持所有字符串函数 (TEXT 不支持 LEN/SUBSTRING 等)
--   2. 行内最多 8000 字节，超过自动溢出
--   3. 可以建索引（前 900 字节）
--   4. 支持 .WRITE() 部分更新

-- CHAR 比较 (= 比较时按 PAD SPACE)：
SELECT CASE WHEN 'abc' = 'abc   ' THEN 1 ELSE 0 END;  -- 1 (= 比较修剪空格)
-- 但 LIKE 不修剪：
SELECT CASE WHEN 'abc' LIKE 'abc   ' THEN 1 ELSE 0 END; -- 0 (LIKE 不修剪)

-- 排序规则决定语义：
-- _CS_AS = 大小写敏感 + 重音敏感
-- _CI_AS = 大小写不敏感 + 重音敏感（默认）
-- _BIN  = 二进制比较（NO PAD）
SELECT 'abc' = 'abc   ' COLLATE Latin1_General_BIN;   -- 0 (BIN 是 NO PAD)
```

SQL Server 关键事实：
- **ANSI_PADDING ON 自 SQL Server 2000 起默认 (连接默认自 7.0)**：之前需要显式设置才符合标准
- **TEXT/NTEXT 自 2005 废弃**：未来版本会移除，必须迁移到 `VARCHAR(MAX)` / `NVARCHAR(MAX)`
- **VARCHAR(MAX) 自 2005 引入**：行内 8000 字节 + 溢出 LOB
- **VARCHAR 是单字节字符集**：基于排序规则的代码页，不能存非该代码页的字符
- **NVARCHAR 是 UTF-16**：长度按代码单元 (UTF-16 code unit) 计，BMP 之外字符占 2 个单元
- **2019 起支持 UTF-8 排序规则**：`VARCHAR` 列可以使用 `Latin1_General_100_CI_AS_SC_UTF8` 等排序规则，单字节假设变成 UTF-8 字节

### MySQL / MariaDB：CHAR 填充但检索剥离尾空格

MySQL 是 SQL 标准合规度最低的引擎之一——它会"填充存储但剥离返回"。

```sql
-- MySQL 字符类型：
CREATE TABLE mysql_chartypes (
    c_char     CHAR(10),         -- 右补空格存储，但 SELECT 时剥离！
    c_varchar  VARCHAR(10),      -- 变长，最多 10 字符
    c_tinytext TINYTEXT,         -- 最大 255 字节
    c_text     TEXT,             -- 最大 65535 字节 (~64KB)
    c_mediumtext MEDIUMTEXT,     -- 最大 16777215 字节 (~16MB)
    c_longtext LONGTEXT          -- 最大 4294967295 字节 (~4GB)
) ENGINE=InnoDB CHARSET=utf8mb4;

-- 验证：CHAR 存储时填充
INSERT INTO mysql_chartypes (c_char) VALUES ('abc');
SELECT LENGTH(c_char), CHAR_LENGTH(c_char) FROM mysql_chartypes;
-- 默认行为：返回 3, 3
-- 因为 MySQL 检索时自动剥离尾部空格！

-- 但比较仍然是 PAD SPACE 语义：
SELECT 'abc' = 'abc   '; -- 1 (TRUE)

-- 启用 PAD_CHAR_TO_FULL_LENGTH SQL 模式可以改变：
SET sql_mode = 'PAD_CHAR_TO_FULL_LENGTH';
SELECT LENGTH(c_char), CHAR_LENGTH(c_char) FROM mysql_chartypes;
-- 此时返回 10, 10

-- VARCHAR 长度变迁：
-- MySQL < 5.0.3：VARCHAR(n) 中 n 最大 255 (字符)
-- MySQL >= 5.0.3：VARCHAR(n) 中 n 最大 65535 / max_byte_per_char (按字节)
-- 65535 是 row size 上限（受 myisam/innodb 行格式约束）

-- VARCHAR(255) 的迷思：
-- "为什么大家都写 VARCHAR(255)?" 因为 MySQL 5.0.3 之前 255 是上限
-- 今天没有理由用 255 而非更准确的长度

-- TEXT 系列与 VARCHAR 的区别：
-- 1. TEXT 不能在 InnoDB 行内完整存储 (除非 ROW_FORMAT=Dynamic/Compressed)
-- 2. TEXT 的索引必须是前缀索引：CREATE INDEX idx ON t(col(255))
-- 3. TEXT 不能有 DEFAULT 值
-- 4. TEXT 的行排序使用临时表 (磁盘排序)，性能差

-- 行级总和限制：
CREATE TABLE big_row (
    a VARCHAR(20000),
    b VARCHAR(50000)
) ENGINE=InnoDB CHARSET=utf8mb4;
-- 错误：Row size too large (> 8126)
-- 即使两个 VARCHAR 都 < 65535 字节，行总和必须 < ~8KB (取决于行格式)
```

MySQL 关键事实：
- **检索时剥离尾空格**：SQL 标准不要求，但 MySQL 这样做（违反标准但实用）
- **VARCHAR 上限 65535 字节**：自 5.0.3 起，但实际还受 row size 限制 (~8KB / 65535 字节)
- **CHAR 最大 255 字符**：所有 MySQL 版本一致
- **TEXT 4 兄弟**：TINYTEXT/TEXT/MEDIUMTEXT/LONGTEXT 是 MySQL 专有的"显式分级 LOB"
- **TEXT 与 VARCHAR 存储不同**：VARCHAR 行内（仅长度前缀），TEXT 通常溢出页存储
- **utf8 vs utf8mb4**：参见 [`charset-collation.md`](./charset-collation.md)

### DB2：CHAR 填充，CLOB 标准实现

```sql
-- DB2 字符类型：
CREATE TABLE db2_chartypes (
    c_char    CHAR(10),                -- 右补空格，最大 254 字节
    c_vchar   VARCHAR(10),             -- 变长，最大 32672 字节
    c_lvarchar LONG VARCHAR,           -- 最大 32700 字节，已不推荐 (用 CLOB 代替)
    c_clob    CLOB(2G),                -- 大字符对象，最大 2GB
    c_graphic GRAPHIC(10),             -- 双字节定长 (DBCS)
    c_vargraphic VARGRAPHIC(10),       -- 双字节变长
    c_dbclob  DBCLOB(2G)               -- 双字节大对象
);

-- CODEUNITS 修饰符（DB2 9.7+）：
CREATE TABLE chartypes_units (
    a VARCHAR(10 OCTETS),         -- 10 字节
    b VARCHAR(10 CODEUNITS16),    -- 10 个 UTF-16 码元
    c VARCHAR(10 CODEUNITS32)     -- 10 个 UTF-32 码点（即 10 个 Unicode 字符）
);

-- DB2 的 PAD SPACE 比较：
SELECT CASE WHEN 'abc' = 'abc   ' THEN 1 ELSE 0 END FROM SYSIBM.SYSDUMMY1;
-- 返回 1 (TRUE)
```

DB2 关键事实：
- **CHAR 最大 254 字节**：所有版本一致
- **VARCHAR 最大 32672**：受页大小影响（4K/8K/16K/32K 页对应不同上限）
- **LONG VARCHAR 已不推荐**：替换为 `CLOB`
- **CODEUNITS 显式控制语义**：是少数让用户在 BYTES/CODEUNITS16/CODEUNITS32 间精确选择的引擎

### SQLite：类型亲和性，CHAR 与 VARCHAR 都是 TEXT

```sql
-- SQLite 类型亲和性：
-- 列声明类型只是"亲和性提示"，不是强约束
-- 所有以下类型都映射到 TEXT 亲和性：
--   CHAR, VARCHAR, NCHAR, NVARCHAR, CHARACTER VARYING, TEXT, CLOB

CREATE TABLE sqlite_chartypes (
    c_char    CHAR(10),       -- 实际是 TEXT 亲和性
    c_varchar VARCHAR(10),    -- 实际是 TEXT 亲和性
    c_text    TEXT            -- TEXT 亲和性
);

-- 长度限制完全无效：
INSERT INTO sqlite_chartypes VALUES ('abcdefghijklmnopqrstuvwxyz', 
                                      'abcdefghijklmnopqrstuvwxyz',
                                      'abcdefghijklmnopqrstuvwxyz');
-- 全部成功，没有错误
SELECT length(c_char), length(c_varchar), length(c_text) FROM sqlite_chartypes;
--  26 | 26 | 26   ← 完整存储

-- SQLite 不补空格：
INSERT INTO sqlite_chartypes (c_char) VALUES ('abc');
SELECT '|' || c_char || '|' FROM sqlite_chartypes;
-- |abc|  ← 没有右补空格

-- 比较语义不修剪：
SELECT 'abc' = 'abc   ';  -- 0 (FALSE)

-- SQLite 单值最大 ~1GB（默认 SQLITE_MAX_LENGTH=1000000000）
-- 编译时可调整到 2^31-1 = ~2GB
```

SQLite 关键事实：
- **没有真正的 CHAR/VARCHAR**：声明的类型只是亲和性提示
- **不强制长度**：`VARCHAR(10)` 列可以存任意长度字符串
- **不补空格**：CHAR 不被填充
- **比较不修剪**：默认二进制比较
- **TEXT 亲和性**：值按字符串解释和存储

### ClickHouse：String 与 FixedString

ClickHouse 完全摒弃 SQL 标准的 CHAR/VARCHAR/TEXT 区分：

```sql
-- ClickHouse 字符类型：
CREATE TABLE ch_chartypes (
    c_string  String,                -- 无长度限制的变长字符串
    c_fixed   FixedString(10)        -- 定长 10 字节（不是字符！）
) ENGINE = MergeTree() ORDER BY tuple();

-- FixedString 行为：
INSERT INTO ch_chartypes VALUES ('hello', 'abc');
SELECT c_string, length(c_string), c_fixed, length(c_fixed) FROM ch_chartypes;
-- 'hello' | 5 | 'abc\0\0\0\0\0\0\0' | 10  ← 注意：右补 \0 (NULL byte)，不是空格

-- FixedString 关键事实：
-- 1. 长度按字节计，不是字符
-- 2. 右补 \0 (空字符) 而不是空格
-- 3. 比较时不修剪 \0
SELECT toFixedString('abc', 10) = toFixedString('abc\0\0\0\0\0\0\0', 10);
-- 1 (TRUE，因为底层就是 \0 填充)

-- VARCHAR 兼容（自 21.x 起）：
-- ClickHouse 解析 VARCHAR(n) 但忽略 n，等价于 String
CREATE TABLE ch_compat (
    a VARCHAR(255)        -- 实际等同于 String
) ENGINE = MergeTree() ORDER BY tuple();

-- LowCardinality 优化：
-- ClickHouse 推荐用 LowCardinality(String) 优化低基数字符串列
CREATE TABLE log_data (
    level LowCardinality(String),    -- 字典编码：'INFO','WARN','ERROR' 等
    message String
) ENGINE = MergeTree() ORDER BY tuple();
```

ClickHouse 关键事实：
- **没有 CHAR/VARCHAR**：只有 `String` 和 `FixedString(N)`
- **String 无长度限制**：受系统资源约束
- **FixedString 右补 \0**：与 SQL 标准的空格填充不同
- **String 和 LowCardinality(String)**：是性能优化的关键选择，与 SQL 标准无关

### Snowflake：所有字符类型统一为 VARCHAR(16777216)

```sql
-- Snowflake 字符类型：
CREATE TABLE snowflake_chartypes (
    c_char    CHAR(10),          -- 实际是 VARCHAR(10)
    c_varchar VARCHAR(10),       -- 标准变长
    c_string  STRING,            -- VARCHAR 别名，无长度
    c_text    TEXT,              -- VARCHAR 别名，无长度
    c_chars   CHARACTER(10)      -- VARCHAR(10) 别名
);

-- 全部等价：
SELECT GET_DDL('TABLE', 'snowflake_chartypes');
-- 看到 Snowflake 内部都展开为 VARCHAR(n) 形式

-- 默认长度：
-- VARCHAR / STRING / TEXT (不带括号) 等价于 VARCHAR(16777216) = 16 MB

-- 关键差异：CHAR 不补空格！
INSERT INTO snowflake_chartypes (c_char) VALUES ('abc');
SELECT '|' || c_char || '|' FROM snowflake_chartypes;
-- |abc|   ← 没有右补空格

-- 比较不修剪空格：
SELECT 'abc' = 'abc   ';  -- FALSE

-- 长度上限 16 MB：
-- VARCHAR / STRING / TEXT 列内单值最大 16777216 字节（16 MB）
-- 这是 Snowflake 列存格式的硬性约束

-- Unicode 默认：
-- 所有字符类型默认 UTF-8 编码
-- 不支持 NCHAR / NVARCHAR
```

Snowflake 关键事实：
- **所有类型别名**：CHAR / VARCHAR / STRING / TEXT / CHARACTER 全部等价
- **CHAR 不补空格**：违反 SQL 标准，但与 PostgreSQL/Oracle 不同
- **不修剪比较**：与 ClickHouse / SQLite 一致
- **16 MB 上限**：列存的物理约束

### BigQuery：仅 STRING，10MB 上限

```sql
-- BigQuery 字符类型：
CREATE TABLE bigquery_chartypes (
    c_string STRING,         -- 唯一字符类型
    c_strn   STRING(10)      -- 可选长度修饰，但 BigQuery 不强制
);

-- BigQuery 关键事实：
-- 1. 没有 CHAR / VARCHAR / TEXT / NCHAR / NVARCHAR
-- 2. STRING 内部按字节存储（10 MB 列值上限）
-- 3. STRING(n) 中 n 是字节数，但 BigQuery 不严格强制长度
-- 4. 默认 UTF-8 编码

-- 长度比较：
SELECT LENGTH('hello'), CHAR_LENGTH('hello');  -- 5, 5（CHAR_LENGTH 是字符）
SELECT BYTE_LENGTH('héllo');                   -- 6（UTF-8 字节，é = 2 字节）

-- 行级 100MB 上限：
-- 整行（所有列总和）最大 100 MB

-- 不修剪比较：
SELECT 'abc' = 'abc   ';  -- FALSE
```

### Trino / Presto：标准 CHAR + VARCHAR，但实际差异微小

```sql
-- Trino / Presto 字符类型：
CREATE TABLE trino_chartypes (
    c_char    CHAR(10),       -- 右补空格，标准语义
    c_varchar VARCHAR(10),    -- 变长
    c_vchar   VARCHAR          -- 不带长度，无限制
);

-- CHAR 行为符合标准：
SELECT CHAR_LENGTH(CAST('abc' AS CHAR(10)));  -- 10（含填充）

-- PAD SPACE 比较：
SELECT CAST('abc' AS CHAR(10)) = 'abc   ';   -- TRUE (PAD SPACE)

-- VARCHAR 不带长度：
SELECT CAST('abc' AS VARCHAR);                -- 等价于无限制 VARCHAR
```

Trino 关键事实：
- **VARCHAR 不带长度时**：实际无限制
- **CHAR 标准 PAD SPACE**：右补空格，比较修剪
- **不支持 TEXT/CLOB**：Trino/Presto 没有 TEXT 类型概念

### Spark SQL / Databricks：STRING 主导

```sql
-- Spark SQL 字符类型：
CREATE TABLE spark_chartypes (
    c_string  STRING,           -- 主要类型，无长度限制
    c_char    CHAR(10),         -- 自 3.0 引入，但默认行为同 VARCHAR
    c_varchar VARCHAR(10)       -- 自 3.0 引入
);

-- spark.sql.legacy.charVarcharAsString 控制行为：
-- ON (默认 3.0+)：CHAR/VARCHAR 等同 STRING，不强制长度，不填充
-- OFF：严格 CHAR/VARCHAR 语义，强制长度并右补空格

SET spark.sql.legacy.charVarcharAsString = false;
INSERT INTO spark_chartypes VALUES ('abc', 'abc', 'abc');
SELECT length(c_char), length(c_varchar) FROM spark_chartypes;
-- 默认严格模式：char=10（填充），varchar=3
-- legacy 模式：char=3（不填充），varchar=3

-- Spark/Databricks 实际推荐用 STRING，CHAR/VARCHAR 主要为 ANSI 兼容
```

## ANSI_PADDING：SQL Server 的历史包袱

`SET ANSI_PADDING` 是 SQL Server 控制 CHAR/BINARY 填充行为的会话选项：

```sql
-- ANSI_PADDING 历史与默认值：
-- - SQL Server 7.0+：连接级默认 ON
-- - SQL Server 2000+：数据库级默认 ON
-- - 长期建议：始终保持 ON（旧 SQL Server 6.5 及更早默认 OFF，已废弃）
-- - 强制推荐：始终使用 ON，未来版本可能强制启用

-- 验证当前设置：
DECLARE @setting INT;
SET @setting = (SELECT [is_ansi_padding_on] FROM sys.dm_exec_sessions WHERE session_id = @@SPID);
SELECT @setting;  -- 1 = ON, 0 = OFF

-- ANSI_PADDING ON 时（推荐 / 默认）：
SET ANSI_PADDING ON;
CREATE TABLE pad_on (c CHAR(10), v VARCHAR(10));
INSERT INTO pad_on VALUES ('abc', 'abc');
SELECT LEN(c), DATALENGTH(c), LEN(v), DATALENGTH(v) FROM pad_on;
-- 3, 10, 3, 3   ← CHAR 物理填充，VARCHAR 不填充

-- ANSI_PADDING OFF 时（历史遗留 / 兼容）：
SET ANSI_PADDING OFF;
CREATE TABLE pad_off (c CHAR(10), v VARCHAR(10));
INSERT INTO pad_off VALUES ('abc', 'abc');
SELECT LEN(c), DATALENGTH(c) FROM pad_off;
-- 3, 3   ← CHAR 也不填充，行为退化为 VARCHAR

-- 注意点：
-- 1. ANSI_PADDING 设置在 CREATE TABLE 时被"烧入"列定义
-- 2. 即使后续会话改变设置，已创建的列保持创建时的行为
-- 3. 微软建议：始终保持 ON，避免 OFF 导致的不可预测行为
```

ANSI_PADDING 关键事实：
- **ON 是默认且推荐**：自 SQL Server 2000 起（连接级自 7.0）
- **OFF 是历史选项**：将在未来版本移除
- **影响 CHAR / NCHAR / BINARY**：但 VARCHAR / NVARCHAR / VARBINARY 不受影响（始终不填充）
- **创建时绑定**：列的填充行为由 CREATE TABLE 时的会话设置决定

## Oracle VARCHAR vs VARCHAR2：保留字之谜

```sql
-- Oracle 中 VARCHAR 和 VARCHAR2 的关系：
-- 1. 当前版本：完全等价，都是变长字符串
-- 2. 文档明确：VARCHAR 是为未来 SQL 标准对齐保留的关键字
-- 3. Oracle 警告：未来 VARCHAR 的行为可能改变，强烈推荐 VARCHAR2

-- 等价性验证：
CREATE TABLE varchar_test (
    a VARCHAR(10),
    b VARCHAR2(10)
);
DESC varchar_test;
-- 输出：
-- A    VARCHAR2(10)   ← 注意：Oracle 内部把 VARCHAR 转成 VARCHAR2!
-- B    VARCHAR2(10)

-- 历史背景：
-- - Oracle 5（1985）引入 VARCHAR
-- - Oracle 7（1992）引入 VARCHAR2
-- - 当时 SQL 标准对 VARCHAR 比较语义未明确（PAD SPACE 还是 NO PAD）
-- - Oracle 决定：VARCHAR2 = 严格 NO PAD（不修剪空格比较）
-- - Oracle 决定：VARCHAR = 当未来标准明确后，可能改变
-- - 30 年后：VARCHAR 仍未改变，但 Oracle 仍坚持文档警告

-- 实际差异（无）：
SELECT 'abc' = 'abc   ' FROM dual;
-- 取决于上下文，但 VARCHAR / VARCHAR2 之间没有任何观察差异

-- 建议：
-- 新代码：永远使用 VARCHAR2
-- 移植代码：把 VARCHAR 替换为 VARCHAR2
```

## 长度语义：字节 vs 字符

不同引擎对 `VARCHAR(n)` 中 `n` 的解释差异巨大：

```sql
-- 场景：UTF-8 编码下，存储 5 个中文字符 "你好世界吗"
-- 中文字符 UTF-8 编码每字符 3 字节，共 15 字节

-- PostgreSQL（字符语义）：
CREATE TABLE pg_test (a VARCHAR(5));
INSERT INTO pg_test VALUES ('你好世界吗');  -- 成功（5 字符）

-- MySQL（字符语义）：
CREATE TABLE mysql_test (a VARCHAR(5)) CHARSET=utf8mb4;
INSERT INTO mysql_test VALUES ('你好世界吗');  -- 成功（5 字符）

-- Oracle（默认字节语义）：
CREATE TABLE oracle_test_byte (a VARCHAR2(5));   -- 默认 BYTE
INSERT INTO oracle_test_byte VALUES ('你好世界吗');  -- 失败！需要 15 字节
-- ORA-12899: value too large for column

-- Oracle（显式字符语义）：
CREATE TABLE oracle_test_char (a VARCHAR2(5 CHAR));
INSERT INTO oracle_test_char VALUES ('你好世界吗');  -- 成功

-- BigQuery（字节语义）：
CREATE TABLE bq_test (a STRING(5));
-- INSERT '你好世界吗'：失败（需要 15 字节，超过 5）
-- INSERT '你好'：成功（6 字节，超过 5！）—— 实际 BigQuery 不严格强制 STRING(n)

-- Redshift（字节语义）：
CREATE TABLE rs_test (a VARCHAR(5));
INSERT INTO rs_test VALUES ('你好世界吗');  -- 失败
-- ERROR: value too long for type character varying(5)
```

字节 vs 字符语义的影响表：

| 场景 | 字符语义 | 字节语义 |
|------|---------|---------|
| 多字节字符（中文/日文/Emoji） | 占 1 个长度 | 占多个长度 |
| ASCII 字符 | 占 1 个长度 | 占 1 个长度 |
| 长度边界检查 | 按字符计 | 按字节计 |
| 跨字符集迁移 | 行为一致 | 长度需要重新计算 |
| 对存储空间的预测 | 不可知（取决于实际字符） | 精确 |

## TINYTEXT / TEXT / MEDIUMTEXT / LONGTEXT：MySQL 的 LOB 分级

MySQL 是少数引擎中显式提供"LOB 大小分级"的：

```sql
-- MySQL TEXT 家族：
CREATE TABLE mysql_text_family (
    t1 TINYTEXT,      -- 最大 255 字节（2^8 - 1），1 字节长度前缀
    t2 TEXT,          -- 最大 65535 字节（2^16 - 1），2 字节长度前缀
    t3 MEDIUMTEXT,    -- 最大 16777215 字节（2^24 - 1），3 字节长度前缀
    t4 LONGTEXT       -- 最大 4294967295 字节（2^32 - 1），4 字节长度前缀
);

-- BLOB 家族对应：
CREATE TABLE mysql_blob_family (
    b1 TINYBLOB,      -- 255 字节
    b2 BLOB,          -- 64 KB
    b3 MEDIUMBLOB,    -- 16 MB
    b4 LONGBLOB       -- 4 GB
);

-- 选择建议：
-- - TINYTEXT：极少使用，VARCHAR(255) 通常更合适
-- - TEXT：典型 64KB 文本字段（评论、文章短摘要）
-- - MEDIUMTEXT：日志、文章正文
-- - LONGTEXT：极大文档、序列化对象

-- 关键差异（vs VARCHAR）：
-- 1. TEXT 不允许 DEFAULT 值（除非 NOT NULL DEFAULT (... 表达式)，MySQL 8.0.13+）
-- 2. TEXT 索引必须前缀：CREATE INDEX idx ON t(col(255))
-- 3. TEXT 默认溢出存储（行内仅长度+指针）
-- 4. TEXT 不可在内存表 (MEMORY engine) 中使用
-- 5. TEXT 列上的 GROUP BY/ORDER BY 使用磁盘临时表
```

## 关键发现

### 1. CHAR 填充行为分裂为四类

CHAR(n) 在 SQL 标准下"右补空格至 n"，但实际引擎行为分为四类：

| 类别 | 行为 | 代表引擎 |
|------|-----|---------|
| **严格标准** | 存储+检索都填充，比较修剪 | PostgreSQL、Oracle、SQL Server (ANSI_PADDING ON)、DB2、Vertica、Firebird |
| **存储填充检索剥离** | 存储时填充，但 SELECT 自动剥离尾空格 | MySQL、MariaDB、TiDB、Hive、Spark (legacy) |
| **完全不填充** | CHAR = VARCHAR 别名，不填充 | Snowflake、DuckDB、SQLite |
| **不存在 CHAR** | 没有 CHAR 类型 | BigQuery、Spanner、ClickHouse、CrateDB |

### 2. VARCHAR 最大长度跨度 5 个数量级

从 Informix VARCHAR 限 255 字节到 Snowflake VARCHAR(16777216) 的 16MB，再到 PostgreSQL/Trino/DuckDB 的"无限制"，跨度极大：

| 量级 | 代表引擎 | 典型上限 |
|------|---------|---------|
| **百字节级** | Informix VARCHAR (255 B) | 255 字节 |
| **千字节级** | Oracle VARCHAR2 (4000) | 4 KB |
| **万字节级** | SQL Server VARCHAR (8000)、DB2 (32672)、MySQL (65535)、Redshift (65535) | 8-65 KB |
| **MB 级** | SQL Server VARCHAR(MAX) (2GB)、Snowflake (16MB)、BigQuery (10MB) | 2 MB - 2 GB |
| **GB 级 / 无限** | PostgreSQL TEXT (1GB)、Trino/DuckDB/ClickHouse (无限) | 1 GB+ |

### 3. TEXT/CLOB 设计取决于历史路径

- **早期标准派**（Oracle/DB2/Firebird）：BLOB + CLOB + NCLOB，独立大对象段，专属 API
- **现代统一派**（PostgreSQL/DuckDB/Snowflake）：TEXT = VARCHAR 无长度限制，存储路径一致
- **替代派**（SQL Server）：用 VARCHAR(MAX) 替代 TEXT，原 TEXT 类型废弃
- **MySQL 分级派**：TINYTEXT/TEXT/MEDIUMTEXT/LONGTEXT，按预期大小选类型
- **简化派**（ClickHouse/BigQuery/Spanner）：只有 STRING，无 CHAR/VARCHAR/TEXT 区分

### 4. NCHAR/NVARCHAR 在 UTF-8 默认时代失去意义

在 PostgreSQL、MySQL 8、Snowflake、BigQuery 等"现代默认 UTF-8"引擎中，N 类型已无实际作用：

| 引擎类别 | N 类型状态 | 推荐 |
|---------|-----------|-----|
| 现代 UTF-8 默认 | 解析为别名或不支持 | 不要用 N 类型 |
| 双编码（SQL Server / Oracle） | 真实差异 | 多语言场景用 N 类型 |
| 双字节字符集（DB2 GRAPHIC） | 历史 DBCS 工具 | 仅维护遗留 |

### 5. 字节 vs 字符语义的迁移陷阱

跨引擎迁移时最大坑点：

- **从 PostgreSQL（字符）→ Oracle（默认字节）**：UTF-8 中文存不下，需要改 `VARCHAR2(n CHAR)` 或会话级 `NLS_LENGTH_SEMANTICS=CHAR`
- **从 MySQL（字符）→ Redshift（字节）**：所有 VARCHAR 长度需要 ×3 或 ×4
- **从 SQL Server VARCHAR（字节）→ NVARCHAR（字符）**：NVARCHAR(n) 中 n 是 UTF-16 码元，不是字符（BMP 之外字符占 2 个码元）

### 6. CHAR vs VARCHAR 性能：今天差异微小

历史上 CHAR 因定长存储被认为有性能优势：

- 行内固定偏移，可以快速定位
- 无长度前缀，节省空间（极短字符串）
- 不需要变长行管理

但今天大多数引擎中：

- **InnoDB DYNAMIC/COMPRESSED 行格式**：CHAR 与 VARCHAR 几乎等价
- **PostgreSQL varlena**：CHAR 仅多一步空格填充开销
- **列存引擎**：完全不区分 CHAR / VARCHAR，按列字典/RLE 编码
- **Snowflake/DuckDB/ClickHouse**：CHAR = VARCHAR

**结论**：除非是 SQL Server / Oracle 等行存引擎中"极短且确实定长"的场景（如固定 8 字节代码），用 VARCHAR 即可。

### 7. PAD SPACE vs NO PAD 比较

SQL:2003 引入 `NO PAD` 排序规则属性，覆盖标准 `PAD SPACE` 默认。今天的实际行为：

| 引擎 | 默认比较 | NO PAD 选项 |
|------|---------|-----------|
| PostgreSQL | `_C` 排序规则 NO PAD；`_libc` 排序规则 PAD SPACE | `COLLATE "C"` 或 `COLLATE "POSIX"` |
| MySQL | utf8mb4_general_ci PAD SPACE；utf8mb4_bin NO PAD | `COLLATE utf8mb4_bin` |
| SQL Server | _CI_AS PAD SPACE；_BIN/_BIN2 NO PAD | `COLLATE Latin1_General_BIN2` |
| Oracle | NO PAD（VARCHAR2 之间）/ PAD SPACE（CHAR 一侧） | 无显式选项 |
| ClickHouse | NO PAD（二进制比较） | -- |
| Snowflake | NO PAD | -- |

### 8. 设计建议

引擎开发者实现字符类型时的决策清单：

```
1. CHAR 是否填充？
   - 严格遵循 SQL 标准：PostgreSQL 路线
   - 不填充节省存储：Snowflake/DuckDB 路线（违反标准但简化语义）
   - 选择影响：CHAR(n) 列空间利用率、应用代码兼容性

2. 长度语义：字节还是字符？
   - 字符语义：用户友好，但存储不可预测
   - 字节语义：精确控制，但需用户理解多字节编码
   - 折中：DB2 的 OCTETS / CODEUNITS16 / CODEUNITS32 显式标注

3. 是否提供 TEXT/CLOB 独立类型？
   - 提供 → 必须设计 LOB Locator API（见 blob-clob-handling.md）
   - 不提供 → VARCHAR 上限决定了能存多大字符串

4. CHAR 与 VARCHAR 是否合并？
   - 合并：列存引擎、Snowflake、DuckDB——简化优化器
   - 区分：行存引擎需要支持定长行布局优化

5. 是否支持 N 类型？
   - 现代 UTF-8 默认：不必支持
   - 多字符集兼容：N 类型作为 Unicode 显式标注

6. 比较的 PAD SPACE 默认？
   - 标准默认：PAD SPACE（兼容 SQL:1992）
   - 现代默认：NO PAD（避免空格相关错误）
```

## 总结对比矩阵

| 引擎 | CHAR 填充 | CHAR/VARCHAR 内部合并 | TEXT/LOB 路径 | 长度单位 | 最大 VARCHAR | 字符集默认 |
|------|---------|--------------------|-------------|---------|------------|-----------|
| PostgreSQL | 是（标准） | 部分（CHAR 多一步填充） | TEXT (TOAST) / Large Object | 字符 | 1 GB | UTF-8 / 数据库级 |
| Oracle | 是（blank-padded） | 否 | CLOB | 字节 (默认) / 字符 | 4000 / 32767 字节 | 数据库级 |
| SQL Server | 是（ANSI_PADDING ON） | 否 | VARCHAR(MAX) | 字节 (VARCHAR) / UTF-16 单元 (NVARCHAR) | 8000 字节 / 2 GB | 排序规则代码页 |
| MySQL | 是（存）/ 否（取） | 否 | TEXT 4 兄弟 | 字符 | 65535 字节 (行级) | 表级配置 |
| DB2 | 是（标准） | 否 | CLOB / LONG VARCHAR | 字节 (BYTES) / 字符 (CODEUNITS) | 32672 字节 | 数据库级 |
| SQLite | 否（亲和性） | 是（合并） | TEXT 亲和性 | 字节 | 无 (~1GB) | UTF-8 / 16 |
| Snowflake | 否 | 是（完全合并） | TEXT = VARCHAR(16M) | 字符 | 16 MB | UTF-8 |
| BigQuery | -- | 是（仅 STRING） | STRING | 字节 | 10 MB | UTF-8 |
| Redshift | 是 | 否 | VARCHAR(65535) | 字节 | 65535 字节 | UTF-8 |
| DuckDB | 否 | 是（完全合并） | VARCHAR / TEXT | 字符 | 无 | UTF-8 |
| ClickHouse | -- (FixedString \0 填充) | 是（仅 String） | String | 字节 | 无 | UTF-8 |
| Trino / Presto | 是（标准） | 否 | VARCHAR 无限 | 字符 | 无 | UTF-8 |
| Spark SQL | 是（严格模式） | 取决于配置 | STRING | 字符 | ~2 GB | UTF-8 |
| Hive | 是（存）/ 否（取） | 否 | STRING | 字符 | 65535 字符 | UTF-8 |
| Teradata | 是 | 否 | CLOB | 字符 (默认) | 64000 字符 | 表级 |
| TiDB | 是（兼容 MySQL） | 否 | TEXT 4 兄弟 | 字符 | 65535 字节 | utf8mb4 |
| OceanBase (MySQL) | 是 | 否 | TEXT 4 兄弟 | 字符 | 65535 字节 | utf8mb4 |
| OceanBase (Oracle) | 是 | 否 | CLOB | 字节 (默认) | 4000 / 32767 字节 | 数据库级 |
| CockroachDB | 是（兼容 PG） | 部分 | STRING | 字符 | 64MiB 软限 | UTF-8 |
| YugabyteDB | 是（兼容 PG） | 部分 | TEXT | 字符 | 1 GB | UTF-8 |
| Vertica | 是 | 否 | LONG VARCHAR (32MB) | 字节 | 65000 字节 | UTF-8 |
| H2 | 是 | 否 | CLOB | 字符 | 1 GB | UTF-8 |
| HSQLDB | 是 | 否 | CLOB | 字符 | 16 M 字符 | UTF-8 |
| Derby | 是 | 否 | CLOB | 字符 | 32672 字节 | UTF-8 |
| Firebird | 是 | 否 | BLOB SUB_TYPE TEXT | 取决于 CHARACTER SET | 32767 字节 | 列级 |
| SAP HANA | 是 | 否 | CLOB / NCLOB | 字节 (VARCHAR 已废弃) / 字符 (NVARCHAR) | 5000 字节 | 列级 |
| Informix | 是 | 否 | TEXT / CLOB | 字节 | 255 字节 (VARCHAR) | 列级 |
| Spanner | -- | 是（仅 STRING） | STRING(MAX) | 字节 | 10 MiB | UTF-8 |
| Materialize | 是（兼容 PG） | 部分 | TEXT | 字符 | 1 GB | UTF-8 |
| Azure Synapse | 是（继承 SQL Server） | 否 | VARCHAR(MAX) | 字节 / UTF-16 | 8000 / 2 GB | 排序规则代码页 |

## 选型建议

| 场景 | 推荐类型 | 引擎示例 |
|------|--------|---------|
| 短字符串（< 64KB），需精确长度控制 | `VARCHAR(n)` | 几乎所有引擎 |
| 极短定长字符串（如 ISO 国家代码 2 字符） | `CHAR(n)` | PostgreSQL / SQL Server / Oracle |
| 不知具体长度的文本 | `TEXT` (PostgreSQL/CockroachDB) / `STRING` (BigQuery/Snowflake) / `VARCHAR` (无长度) | -- |
| 极大文本（> 1MB） | `CLOB` (Oracle/DB2) / `LONGTEXT` (MySQL) / `VARCHAR(MAX)` (SQL Server) / `TEXT` (PostgreSQL) | -- |
| 多语言混合（含 Emoji 等 4 字节字符） | `NVARCHAR` (SQL Server) / `VARCHAR2 ... CHAR` (Oracle) / `VARCHAR utf8mb4` (MySQL) | -- |
| 跨引擎迁移友好 | 始终用 `VARCHAR(n)` 或 `TEXT`，避免 `CHAR(n)` | -- |
| 列存查询（ClickHouse/DuckDB） | `String` / `VARCHAR`，配合 `LowCardinality` 优化低基数 | ClickHouse / DuckDB |

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992, Section 4.2 (Character strings)
- SQL:1999 标准: ISO/IEC 9075-2:1999, Section 4.2 (引入 CLOB / NCLOB)
- SQL:2003 标准: ISO/IEC 9075-2:2003, Section 4.2 (引入 NO PAD 排序规则)
- PostgreSQL: [Character Types](https://www.postgresql.org/docs/current/datatype-character.html)
- Oracle: [Data Types](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Data-Types.html)
- Oracle: [VARCHAR vs VARCHAR2](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Data-Types.html#GUID-0DC7FFAA-F03F-4448-8487-F2592496A510)
- SQL Server: [char and varchar](https://learn.microsoft.com/en-us/sql/t-sql/data-types/char-and-varchar-transact-sql)
- SQL Server: [SET ANSI_PADDING](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-ansi-padding-transact-sql)
- MySQL: [The CHAR and VARCHAR Types](https://dev.mysql.com/doc/refman/8.0/en/char.html)
- MySQL: [The TEXT and BLOB Types](https://dev.mysql.com/doc/refman/8.0/en/blob.html)
- DB2: [String data types](https://www.ibm.com/docs/en/db2/11.5?topic=list-string-data-types)
- SQLite: [Datatypes In SQLite](https://www.sqlite.org/datatype3.html) (Type Affinity)
- ClickHouse: [String Data Type](https://clickhouse.com/docs/en/sql-reference/data-types/string)
- ClickHouse: [FixedString](https://clickhouse.com/docs/en/sql-reference/data-types/fixedstring)
- Snowflake: [Text Data Types](https://docs.snowflake.com/en/sql-reference/data-types-text)
- BigQuery: [String type](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types#string_type)
- Redshift: [Character types](https://docs.aws.amazon.com/redshift/latest/dg/r_Character_types.html)
- DuckDB: [VARCHAR](https://duckdb.org/docs/sql/data_types/text)
- Spark SQL: [Char and Varchar](https://spark.apache.org/docs/latest/sql-ref-datatypes.html)
- Trino: [Character types](https://trino.io/docs/current/language/types.html#character)
- Vertica: [VARCHAR](https://docs.vertica.com/latest/en/sql-reference/data-types/character-data-types/)
- SAP HANA: [SQL Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM)
