# 数学函数 (MATH FUNCTIONS)

各数据库数学函数对比，包括 ABS、ROUND、CEIL、FLOOR、MOD、POWER 等。

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

1. **ROUND 舍入规则**：PostgreSQL/Oracle 使用四舍五入，SQL Server 使用四舍五入，MySQL 使用四舍五入，但某些方言的 ROUND 对 .5 的处理可能采用银行家舍入（round half to even）
2. **取模运算符**：MySQL/PostgreSQL 支持 `%` 运算符和 MOD() 函数，Oracle 只有 MOD() 函数（不支持 `%`），SQL Server 支持 `%`
3. **整数除法**：MySQL 的 `5/2=2.5`，PostgreSQL 的 `5/2=2`（整数除法），Oracle 的 `5/2=2.5`，这个差异在迁移时极易出错
4. **随机数**：MySQL 用 RAND()，PostgreSQL 用 RANDOM()，Oracle 用 DBMS_RANDOM.VALUE，SQL Server 用 RAND() 或 NEWID()
5. **数学常量**：MySQL 有 PI()，PostgreSQL 有 PI()，Oracle 需要 `ACOS(-1)` 计算 PI，SQL Server 有 PI()

## 选型建议

数学函数是跨方言差异较小的领域（ABS/CEIL/FLOOR/POWER/SQRT 几乎通用），但整数除法行为差异是重大陷阱。涉及精确数值计算时始终使用 DECIMAL 类型避免浮点误差。随机排序（ORDER BY RAND()/RANDOM()）在大表上性能极差。

## 版本演进

- 数学函数在各方言中变化极少，属于最稳定的语法领域
- PostgreSQL 16+：增强统计函数支持
- ClickHouse：拥有极其丰富的数学函数库（含近似计算和统计函数）

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **内置函数** | 基本函数（ABS/ROUND/MAX/MIN），3.35.0+ 增加更多数学函数 | 极其丰富的数学函数库（含统计、近似计算） | 完整的数学函数集 | 各方言完整支持 |
| **整数除法** | 5/2=2（整数除法，与 PG 相同） | 5/2=2（整数除法） | 5/2=2.5（浮点除法） | PG 5/2=2 / MySQL 5/2=2.5 / Oracle 5/2=2.5 |
| **ROUND 行为** | 四舍五入 | 四舍五入 | 银行家舍入（round half to even） | 各方言略有不同 |
| **随机数** | RANDOM()（返回整数） | rand()/randUniform() 等 | RAND() | MySQL RAND() / PG RANDOM() / Oracle DBMS_RANDOM |
| **动态类型影响** | 动态类型使数值运算可能出现意外结果（字符串参与运算） | 严格类型确保数值运算正确 | 严格类型 | 严格类型 |

## 引擎开发者视角

**核心设计决策**：数学函数在各方言中差异最小，但整数除法行为和舍入规则的设计决策影响深远且一旦确定很难更改。

**实现建议**：
- 整数除法行为必须在引擎设计之初明确：PostgreSQL 方式（5/2=2，整数除整数返回整数）更符合编程语言惯例，MySQL 方式（5/2=2.5，返回浮点数）更符合数学直觉。推荐 PostgreSQL 方式——避免意外的精度问题，需要浮点结果时用户可以显式 CAST
- ROUND 的银行家舍入（round half to even）vs 传统四舍五入：金融场景偏好银行家舍入（减少累积偏差），一般场景用户期望传统四舍五入。推荐默认四舍五入并提供函数参数控制舍入策略
- 溢出行为的设计需要一致性：整数运算溢出是报错（PostgreSQL）还是回绕（ClickHouse）还是静默截断（MySQL 非严格模式）？推荐报错——安全性优先，ClickHouse 的回绕行为可能导致数据静默损坏
- DECIMAL/NUMERIC 的运算规则要遵循 SQL 标准的精度和标度传播规则（如两个 DECIMAL(10,2) 相乘结果的精度和标度如何确定）
- 随机数函数（RANDOM/RAND）应使用密码学安全的随机数生成器，或至少提供密码学安全版本——不安全的随机数在安全敏感场景（如 token 生成）中是隐患
- 常见错误：MOD（取模）对负数的行为不一致。SQL 标准定义结果的符号与被除数相同，但有些实现跟随除数的符号——需要明确并测试
