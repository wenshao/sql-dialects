# JSON 展开 (JSON FLATTEN)

各数据库 JSON 数组/对象展开为行的最佳实践。

> [对比总览表](_comparison.md) -- 横向对比各方言特性支持

## 方言列表

### 传统关系型数据库
| 方言 | 简评 |
|---|---|
| [MySQL](mysql.sql) | JSON_TABLE(8.0+)，JSON_EXTRACT/JSON_UNQUOTE |
| [PostgreSQL](postgres.sql) | jsonb_each/jsonb_array_elements/json_to_record |
| [SQLite](sqlite.sql) | json_each()/json_tree() 展开 |
| [Oracle](oracle.sql) | JSON_TABLE(12c+) 原生展开 |
| [SQL Server](sqlserver.sql) | OPENJSON/CROSS APPLY 展开 |
| [MariaDB](mariadb.sql) | JSON_TABLE(10.6+)，JSON_EXTRACT |
| [Firebird](firebird.sql) | 无 JSON 展开函数 |
| [IBM Db2](db2.sql) | JSON_TABLE(11.1+) 展开 |
| [SAP HANA](saphana.sql) | JSON_TABLE/JSON_QUERY 支持 |

### 大数据 / 分析型引擎
| 方言 | 简评 |
|---|---|
| [BigQuery](bigquery.sql) | JSON_EXTRACT_ARRAY + UNNEST 展开 |
| [Snowflake](snowflake.sql) | LATERAL FLATTEN 展开 VARIANT/ARRAY |
| [ClickHouse](clickhouse.sql) | JSONExtract + arrayJoin 展开 |
| [Hive](hive.sql) | get_json_object + LATERAL VIEW explode |
| [Spark SQL](spark.sql) | from_json + explode 或 json_tuple |
| [Flink SQL](flink.sql) | JSON_QUERY + UNNEST 展开 |
| [StarRocks](starrocks.sql) | json_each/get_json_string + UNNEST |
| [Doris](doris.sql) | jsonb_extract + LATERAL VIEW explode |
| [Trino](trino.sql) | json_extract + UNNEST 展开 |
| [DuckDB](duckdb.sql) | json_extract + UNNEST 或 JSON 结构化 |
| [MaxCompute](maxcompute.sql) | GET_JSON_OBJECT + LATERAL VIEW |
| [Hologres](hologres.sql) | jsonb_array_elements(PG 兼容) |

### 云数仓
| 方言 | 简评 |
|---|---|
| [Redshift](redshift.sql) | JSON_EXTRACT_PATH_TEXT + UNION 模拟 |
| [Azure Synapse](synapse.sql) | OPENJSON 展开(T-SQL 兼容) |
| [Databricks SQL](databricks.sql) | from_json + explode 展开 |
| [Greenplum](greenplum.sql) | PG 兼容 json_each/jsonb_each |
| [Impala](impala.sql) | GET_JSON_OBJECT + 手动展开 |
| [Vertica](vertica.sql) | MAPJSONEXTRACTOR + Flex Table |
| [Teradata](teradata.sql) | JSON_TABLE(JSON Shredding) |

### 分布式 / NewSQL
| 方言 | 简评 |
|---|---|
| [TiDB](tidb.sql) | JSON_TABLE(7.0+) 展开 |
| [OceanBase](oceanbase.sql) | MySQL 兼容 JSON_TABLE |
| [CockroachDB](cockroachdb.sql) | jsonb_each/jsonb_array_elements(PG) |
| [Spanner](spanner.sql) | JSON_QUERY_ARRAY + UNNEST |
| [YugabyteDB](yugabytedb.sql) | PG 兼容 jsonb_each |
| [PolarDB](polardb.sql) | MySQL 兼容 JSON_TABLE |
| [openGauss](opengauss.sql) | PG 兼容 jsonb_each |
| [TDSQL](tdsql.sql) | MySQL 兼容 JSON_EXTRACT |

### 国产数据库
| 方言 | 简评 |
|---|---|
| [DamengDB](dameng.sql) | JSON 函数支持 |
| [KingbaseES](kingbase.sql) | PG 兼容 jsonb_each |

### 时序数据库
| 方言 | 简评 |
|---|---|
| [TimescaleDB](timescaledb.sql) | 继承 PG JSON 展开函数 |
| [TDengine](tdengine.sql) | 不支持 JSON 展开 |

### 流处理
| 方言 | 简评 |
|---|---|
| [ksqlDB](ksqldb.sql) | EXTRACTJSONFIELD/STRUCT 访问 |
| [Materialize](materialize.sql) | PG 兼容 jsonb_each |

### 嵌入式 / 轻量
| 方言 | 简评 |
|---|---|
| [H2](h2.sql) | 无 JSON 展开函数 |
| [Derby](derby.sql) | 无 JSON 支持 |

### SQL 标准
| 方言 | 简评 |
|---|---|
| [SQL Standard](sql-standard.sql) | SQL:2016 JSON_TABLE 规范 |

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **JSON 展开** | json_each()/json_tree() 虚拟表（3.38.0+） | JSONExtract 系列函数提取字段，推荐 ETL 时展开为列 | JSON_VALUE/JSON_QUERY + UNNEST 展开 JSON 数组 | PG jsonb_to_recordset / MySQL JSON_TABLE / Oracle JSON_TABLE |
| **嵌套数据** | json_tree() 可递归遍历 | 推荐预展开为 STRUCT/Array 列（列式存储更高效） | STRUCT/ARRAY 原生支持嵌套数据 | PG JSONB 最灵活 / MySQL 8.0 JSON_TABLE |
| **索引支持** | 无 JSON 索引 | 列式存储天然高效查询展开后的列 | 无索引（分区+聚簇替代） | PG JSONB GIN 索引 / MySQL 虚拟列索引 |
| **性能** | TEXT 存储 JSON，查询性能一般 | 展开为独立列后查询极快 | STRUCT 比 JSON 字符串查询更高效 | PG JSONB 查询性能良好 |

## 引擎开发者视角

**核心设计决策**：JSON 展开（将嵌套 JSON 数组/对象转换为关系表行）是半结构化数据处理的核心操作。引擎需要决定在 SQL 层还是存储层处理嵌套数据。

**实现建议**：
- JSON_TABLE（SQL:2016 标准）是最强大的 JSON 展开方案——将 JSON 路径表达式映射为关系表的列。MySQL 8.0 和 Oracle 12c 的实现可做参考。实现上等价于参数化的表值函数
- UNNEST（展开数组为行）+ JSON 路径提取是 BigQuery/Trino 的方案——如果引擎有原生 ARRAY 类型支持，这种组合更自然
- PostgreSQL 的 jsonb_to_recordset/jsonb_array_elements 函数族设计灵活但命名不统一——新引擎推荐统一使用 UNNEST 作为所有展开操作的入口
- 列式引擎的最佳实践是在 ETL 阶段将 JSON 展开为独立列存储（ClickHouse 的推荐方式）。引擎可以提供建表时的 JSON 自动展开功能（如 ClickHouse 的 JSONAsObject 实验性特性）
- 嵌套 JSON 的递归展开（如 json_tree 在 SQLite 中）是高级特性——对于深度嵌套的文档数据很有用但实现复杂
- 常见错误：JSON 展开后的类型推导不正确。JSON 的 number 类型可能是整数也可能是浮点数——引擎应按用户的 CAST 目标类型处理，而非自动推断
