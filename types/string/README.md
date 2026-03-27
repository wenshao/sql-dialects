# 字符串类型 (STRING)

各数据库字符串类型对比，包括 CHAR、VARCHAR、TEXT、CLOB 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | VARCHAR/TEXT/CHAR，CHARSET 字符集关键 |
| [PostgreSQL](postgres.sql) | VARCHAR/TEXT/CHAR，TEXT 无长度限制 |
| [SQLite](sqlite.sql) | TEXT 统一类型，无长度限制 |
| [Oracle](oracle.sql) | VARCHAR2(4000)/CLOB/NVARCHAR2，字节/字符语义 |
| [SQL Server](sqlserver.sql) | VARCHAR/NVARCHAR(MAX)/TEXT(已弃用) |
| [MariaDB](mariadb.sql) | 兼容 MySQL 字符串类型 |
| [Firebird](firebird.sql) | VARCHAR/CHAR/BLOB SUB_TYPE TEXT |
| [IBM Db2](db2.sql) | VARCHAR/CLOB/GRAPHIC(双字节) |
| [SAP HANA](saphana.sql) | VARCHAR/NVARCHAR/CLOB/NCLOB |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | STRING(UTF-8)，无长度限制 |
| [Snowflake](snowflake.sql) | VARCHAR(16MB)，UTF-8 统一 |
| [ClickHouse](clickhouse.sql) | String(无限)/FixedString(N)/LowCardinality |
| [Hive](hive.sql) | STRING/VARCHAR/CHAR |
| [Spark SQL](spark.sql) | STRING/VARCHAR/CHAR |
| [Flink SQL](flink.sql) | STRING/VARCHAR/CHAR |
| [StarRocks](starrocks.sql) | VARCHAR/CHAR/STRING(3.0+) |
| [Doris](doris.sql) | VARCHAR/CHAR/STRING |
| [Trino](trino.sql) | VARCHAR/CHAR |
| [DuckDB](duckdb.sql) | VARCHAR/TEXT，无长度限制 |
| [MaxCompute](maxcompute.sql) | STRING/VARCHAR，STRING 无限长 |
| [Hologres](hologres.sql) | TEXT/VARCHAR(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | VARCHAR(65535)/CHAR(PG 兼容) |
| [Azure Synapse](synapse.sql) | VARCHAR/NVARCHAR(T-SQL 兼容) |
| [Databricks SQL](databricks.sql) | STRING 类型为主 |
| [Greenplum](greenplum.sql) | PG 兼容 TEXT/VARCHAR |
| [Impala](impala.sql) | STRING/VARCHAR/CHAR |
| [Vertica](vertica.sql) | VARCHAR/LONG VARCHAR 列式优化 |
| [Teradata](teradata.sql) | VARCHAR/CLOB/GRAPHIC(UNICODE) |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | MySQL 兼容 VARCHAR/TEXT |
| [OceanBase](oceanbase.sql) | MySQL/Oracle 双模式字符串类型 |
| [CockroachDB](cockroachdb.sql) | PG 兼容 STRING/VARCHAR |
| [Spanner](spanner.sql) | STRING(MAX)/BYTES，UTF-8 |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 TEXT/VARCHAR |
| [PolarDB](polardb.sql) | MySQL 兼容字符串类型 |
| [openGauss](opengauss.sql) | PG 兼容 TEXT/VARCHAR |
| [TDSQL](tdsql.sql) | MySQL 兼容字符串类型 |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | VARCHAR/CLOB(Oracle 兼容) |
| [KingbaseES](kingbase.sql) | PG 兼容 |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG TEXT/VARCHAR |
| [TDengine](tdengine.sql) | NCHAR(Unicode)/BINARY/VARCHAR |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | VARCHAR/STRING 类型 |
| [Materialize](materialize.sql) | PG 兼容 TEXT/VARCHAR |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | VARCHAR/CLOB/CHARACTER VARYING |
| [Derby](derby.sql) | VARCHAR/CLOB/CHAR |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2003 CHARACTER/VARCHAR/CLOB |

## 核心差异

1. **VARCHAR 上限**：MySQL 最大 65535 字节（行总长限制），PostgreSQL VARCHAR 最大 1GB，Oracle VARCHAR2 最大 4000 字节（EXTENDED 模式 32767），SQL Server VARCHAR(MAX) 最大 2GB
2. **空字符串 vs NULL**：Oracle 中 `''` 等于 NULL，这是最著名的跨方言陷阱之一，其他所有方言中 `''` 和 NULL 是不同的
3. **字符集/编码**：MySQL 的 utf8 实际只支持 3 字节 UTF-8（不含 emoji），需要 utf8mb4 才完整支持；PostgreSQL 数据库级设置编码，Oracle 用 NCHAR/NVARCHAR2 处理 Unicode
4. **TEXT 类型**：MySQL/PostgreSQL/SQLite 有 TEXT 类型（不限长度），Oracle 用 CLOB，SQL Server 用 VARCHAR(MAX)

## 选型建议

现代应用一律使用 UTF-8 编码（MySQL 必须是 utf8mb4）。VARCHAR 长度应设合理值而非总用最大值（影响内存分配和排序缓冲区）。Oracle 迁移时务必处理空字符串 = NULL 的差异。大数据引擎通常只有 STRING 类型，不区分 CHAR/VARCHAR。

## 版本演进

- MySQL 5.5+：默认字符集从 latin1 改为 utf8（但推荐显式使用 utf8mb4）
- MySQL 8.0：默认字符集改为 utf8mb4，默认排序规则改为 utf8mb4_0900_ai_ci
- Oracle 12c+：VARCHAR2 最大长度可扩展到 32767 字节（MAX_STRING_SIZE=EXTENDED）

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **类型系统** | 动态类型，TEXT 存储任意长度字符串，声明 VARCHAR(n) 不限制实际长度 | String（变长）和 FixedString(N)（定长），列式存储高效压缩 | STRING 类型（无长度限制） | VARCHAR(n)/TEXT/CLOB 各方言上限不同 |
| **字符集** | 默认 UTF-8，无字符集配置概念 | UTF-8 编码 | UTF-8 编码 | MySQL 需显式 utf8mb4 / PG 数据库级 / Oracle NLS |
| **空字符串** | `''` 与 NULL 不同（标准行为） | `''` 与 NULL 不同 | `''` 与 NULL 不同 | Oracle 中 `''` = NULL（独特陷阱） |
| **长度限制** | 无实际限制（受磁盘空间限制） | 无硬性限制，列式压缩高效 | 无硬性限制 | MySQL 65535 字节 / PG 1GB / Oracle 4000/32767 |
| **CHAR 补空格** | CHAR(n) 不补空格（动态类型无此语义） | FixedString(N) 补零字节（非空格） | 无 CHAR 类型 | CHAR(n) 补空格且比较时忽略尾部空格 |

## 引擎开发者视角

**核心设计决策**：字符串类型的内部表示（编码方式、存储格式）和排序规则（collation）系统直接影响引擎的国际化能力和查询性能。

**实现建议**：
- 内部编码推荐统一使用 UTF-8——这是现代系统的事实标准。MySQL 的 utf8（3 字节，不完整 UTF-8）vs utf8mb4（4 字节，完整 UTF-8）的历史包袱是设计教训。新引擎应从第一天就用完整的 UTF-8
- VARCHAR(n) vs TEXT 的选择：推荐 PostgreSQL 的方式——VARCHAR(n) 和 TEXT 在存储上完全相同，VARCHAR(n) 只是增加了长度检查。不要像 MySQL 那样让 VARCHAR 的最大长度影响行格式
- COLLATION（排序规则）是字符串系统中最复杂的部分：决定了比较、排序、LIKE 匹配的行为。推荐默认使用 Unicode Collation Algorithm（UCA），并支持大小写不敏感的排序规则（如 utf8_general_ci）
- 字符串比较的 padding 语义需要明确：SQL 标准定义 CHAR(n) 比较时忽略尾部空格，但 VARCHAR 不忽略。Oracle 的空字符串等于 NULL 是独特的实现选择——新引擎不应采用
- 列式引擎的字符串压缩潜力巨大：字典编码（dictionary encoding）可以将重复字符串压缩为整数索引。ClickHouse 的 LowCardinality(String) 是成功案例
- 固定长度字符串（CHAR/FixedString）在某些场景下更高效（如国家代码、状态码），因为不需要存储长度前缀
- 常见错误：LENGTH 函数在单字节编码（latin1）和多字节编码（UTF-8）下返回不同类型的"长度"——字符数 vs 字节数。引擎必须明确 LENGTH 返回字符数，OCTET_LENGTH 返回字节数
