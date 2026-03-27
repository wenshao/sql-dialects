# 字符串函数 (STRING FUNCTIONS)

各数据库字符串函数对比，包括 CONCAT、SUBSTRING、TRIM、REPLACE 等。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 链接 |
|---|---|
| MySQL | [mysql.sql](mysql.sql) |
| PostgreSQL | [postgres.sql](postgres.sql) |
| SQLite | [sqlite.sql](sqlite.sql) |
| Oracle | [oracle.sql](oracle.sql) |
| SQL Server | [sqlserver.sql](sqlserver.sql) |
| MariaDB | [mariadb.sql](mariadb.sql) |
| Firebird | [firebird.sql](firebird.sql) |
| IBM Db2 | [db2.sql](db2.sql) |
| SAP HANA | [saphana.sql](saphana.sql) |

### 大数据 / 分析型引擎
| 方言 | 链接 |
|---|---|
| BigQuery | [bigquery.sql](bigquery.sql) |
| Snowflake | [snowflake.sql](snowflake.sql) |
| ClickHouse | [clickhouse.sql](clickhouse.sql) |
| Hive | [hive.sql](hive.sql) |
| Spark SQL | [spark.sql](spark.sql) |
| Flink SQL | [flink.sql](flink.sql) |
| StarRocks | [starrocks.sql](starrocks.sql) |
| Doris | [doris.sql](doris.sql) |
| Trino | [trino.sql](trino.sql) |
| DuckDB | [duckdb.sql](duckdb.sql) |
| MaxCompute | [maxcompute.sql](maxcompute.sql) |
| Hologres | [hologres.sql](hologres.sql) |

### 云数仓
| 方言 | 链接 |
|---|---|
| Redshift | [redshift.sql](redshift.sql) |
| Azure Synapse | [synapse.sql](synapse.sql) |
| Databricks SQL | [databricks.sql](databricks.sql) |
| Greenplum | [greenplum.sql](greenplum.sql) |
| Impala | [impala.sql](impala.sql) |
| Vertica | [vertica.sql](vertica.sql) |
| Teradata | [teradata.sql](teradata.sql) |

### 分布式 / NewSQL
| 方言 | 链接 |
|---|---|
| TiDB | [tidb.sql](tidb.sql) |
| OceanBase | [oceanbase.sql](oceanbase.sql) |
| CockroachDB | [cockroachdb.sql](cockroachdb.sql) |
| Spanner | [spanner.sql](spanner.sql) |
| YugabyteDB | [yugabytedb.sql](yugabytedb.sql) |
| PolarDB | [polardb.sql](polardb.sql) |
| openGauss | [opengauss.sql](opengauss.sql) |
| TDSQL | [tdsql.sql](tdsql.sql) |

### 国产数据库
| 方言 | 链接 |
|---|---|
| DamengDB | [dameng.sql](dameng.sql) |
| KingbaseES | [kingbase.sql](kingbase.sql) |

### 时序数据库
| 方言 | 链接 |
|---|---|
| TimescaleDB | [timescaledb.sql](timescaledb.sql) |
| TDengine | [tdengine.sql](tdengine.sql) |

### 流处理
| 方言 | 链接 |
|---|---|
| ksqlDB | [ksqldb.sql](ksqldb.sql) |
| Materialize | [materialize.sql](materialize.sql) |

### 嵌入式 / 轻量
| 方言 | 链接 |
|---|---|
| H2 | [h2.sql](h2.sql) |
| Derby | [derby.sql](derby.sql) |

### SQL 标准
| 方言 | 链接 |
|---|---|
| SQL Standard | [sql-standard.sql](sql-standard.sql) |

## 核心差异

1. **字符串拼接**：MySQL 用 CONCAT()，PostgreSQL/Oracle 用 `||` 运算符（也支持 CONCAT()），SQL Server 用 `+` 运算符或 CONCAT()。注意：Oracle 的 `||` 对 NULL 透明（NULL || 'a' = 'a'），PostgreSQL 的 `||` 遇 NULL 返回 NULL
2. **SUBSTRING 语法**：标准语法 `SUBSTRING(s FROM pos FOR len)`，MySQL 也支持 `SUBSTRING(s, pos, len)`，Oracle 用 SUBSTR()
3. **长度函数**：MySQL/PostgreSQL 用 LENGTH()（字符数）/CHAR_LENGTH()，Oracle 用 LENGTH()（字符数），SQL Server 用 LEN()（去尾部空格）/DATALENGTH()（字节数）
4. **正则表达式**：PostgreSQL 支持 `~` 运算符和 REGEXP_REPLACE/MATCH，MySQL 8.0+ 支持 REGEXP_REPLACE()，Oracle 用 REGEXP_LIKE/REGEXP_REPLACE
5. **TRIM 语法**：标准 `TRIM(LEADING/TRAILING/BOTH 'x' FROM s)` 被大多数方言支持，MySQL/PostgreSQL 也有简化的 LTRIM/RTRIM

## 选型建议

字符串拼接优先用 CONCAT() 函数（跨方言最安全，且 MySQL 的 CONCAT 对 NULL 参数返回 NULL 但 SQL Server 的 CONCAT 将 NULL 视为空字符串）。正则表达式功能强大但性能差，大数据量场景慎用。LENGTH() 的字节 vs 字符语义在多字节编码下差异显著。

## 版本演进

- MySQL 8.0+：引入 REGEXP_REPLACE()、REGEXP_SUBSTR() 等正则函数（5.7 只有 REGEXP/RLIKE 匹配）
- PostgreSQL：正则支持一直很完善，包括命名捕获组等高级特性
- SQL Server 2017+：引入 STRING_AGG()、CONCAT_WS()、TRIM() 等现代字符串函数

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **字符串拼接** | `||` 运算符（与 PG/Oracle 相同） | concat() 函数或 `||` | CONCAT() 函数或 `||` | MySQL CONCAT() / PG `||` / SQL Server `+` |
| **字符串类型** | 动态类型，TEXT 是主要字符串存储 | String/FixedString 列式存储，处理高效 | STRING 类型 | VARCHAR/TEXT/CLOB 等 |
| **正则表达式** | 不内置（需加载 regexp 扩展） | 丰富的正则函数（match/extract/replaceRegexpAll） | REGEXP_CONTAINS/REGEXP_EXTRACT/REGEXP_REPLACE | PG 内置强大正则 / MySQL 8.0+ 支持 |
| **LIKE 性能** | 无全文索引，LIKE '%x%' 全表扫描 | 列式存储下 LIKE 可利用跳数索引优化 | LIKE 按扫描量计费 | 可利用索引优化前缀 LIKE |
| **动态类型影响** | 任何类型可存入 TEXT 列，字符串函数容错性高 | 严格类型，非 String 需先转换 | 严格类型 | 严格类型 |

## 引擎开发者视角

**核心设计决策**：字符串函数的实现需要处理编码、排序规则（collation）和多字节字符等复杂性。函数的 NULL 传播行为和字符串拼接运算符的选择影响兼容性。

**实现建议**：
- 字符串拼接推荐同时支持 `||` 运算符（SQL 标准）和 CONCAT() 函数（MySQL 兼容）。关键决策：`NULL || 'abc'` 返回 NULL（SQL 标准/PostgreSQL）还是 'abc'（Oracle）？推荐遵循 SQL 标准
- LENGTH vs CHAR_LENGTH vs OCTET_LENGTH 三个函数必须同时提供且语义清晰：LENGTH 返回字符数（UTF-8 中一个中文字符 = 1），OCTET_LENGTH 返回字节数（UTF-8 中一个中文字符 = 3）
- 正则表达式支持是高价值特性：REGEXP_REPLACE/REGEXP_EXTRACT/REGEXP_MATCH 覆盖复杂文本处理需求。推荐使用 RE2 或 PCRE 库而非自研正则引擎——正则引擎的性能和正确性极难保证
- COLLATION（排序规则）是字符串系统的深层复杂性：决定了字符串比较、排序和 LIKE 匹配的行为。推荐默认使用 Unicode 排序算法（UCA），并支持大小写不敏感的排序规则
- LIKE 的优化至关重要：前缀匹配（`LIKE 'abc%'`）应能利用 B-Tree 索引，但通配符开头（`LIKE '%abc'`）只能全表扫描——引擎应在 EXPLAIN 中明确标注这一点
- 常见错误：SUBSTRING 的索引是从 1 开始（SQL 标准）还是从 0 开始（编程语言惯例）。SQL 标准明确从 1 开始——不要偏离标准
