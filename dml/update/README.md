# 更新 (UPDATE)

各数据库 UPDATE 语法对比，包括单表更新、多表关联更新、CASE 更新等。

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

1. **多表关联更新**：MySQL 用 `UPDATE t1 JOIN t2 ON ... SET t1.col = t2.col`，PostgreSQL 用 `UPDATE t1 SET col = t2.col FROM t2 WHERE ...`，Oracle 用 `UPDATE (SELECT ...) SET ...` 或 MERGE
2. **UPDATE ... RETURNING**：PostgreSQL 支持返回更新后的行，MySQL/Oracle 不支持
3. **ORDER BY + LIMIT 更新**：MySQL 支持 `UPDATE t SET ... ORDER BY ... LIMIT n`，PostgreSQL/Oracle 不支持这种语法
4. **分析型引擎限制**：ClickHouse 的 ALTER TABLE UPDATE 是异步 mutation，Hive 需要 ACID 表才支持 UPDATE，BigQuery 有 DML 配额限制

## 选型建议

生产环境的 UPDATE 务必先用相同 WHERE 条件的 SELECT 验证影响行数。大批量 UPDATE 建议分批执行避免长事务。在分析型引擎中，考虑用 INSERT OVERWRITE 替代 UPDATE（重写整个分区）。

## 版本演进

- Hive 0.14+：支持 ACID 事务表的 UPDATE 操作
- ClickHouse 20.8+：支持轻量级 UPDATE（ALTER TABLE UPDATE），但仍是异步操作
- DuckDB：支持 UPDATE FROM 语法，与 PostgreSQL 类似

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **UPDATE 可用性** | 标准 UPDATE 语法，完整支持 | UPDATE 是异步 mutation（ALTER TABLE UPDATE），非即时生效 | 标准 UPDATE 语法但有 DML 配额限制（每表每天 1500 次） | 标准即时 UPDATE |
| **UPDATE 哲学** | 即时行级修改 | INSERT-only 哲学：数据追加后通过后台合并实现"更新"效果 | Serverless 执行，UPDATE 内部重写受影响的文件 | MVCC 即时行级修改 |
| **多表关联 UPDATE** | 不支持 FROM 子句（需子查询） | 不支持关联 UPDATE | 支持 UPDATE ... FROM 语法 | MySQL 用 JOIN，PG 用 FROM，Oracle 用子查询 |
| **UPDATE RETURNING** | 3.35.0+ 支持 RETURNING | 不支持 | 不支持 | PG 支持，MySQL/Oracle 不支持 |
| **性能影响** | 轻量操作 | 重量级操作：重写整个 data part，不适合频繁小批量更新 | 每次 UPDATE 消耗 DML 配额且扫描受影响分区 | 行级操作，性能高 |
| **并发限制** | 单写模型，UPDATE 时阻塞其他写入 | mutation 队列串行执行 | 同一表的并发 DML 有限制 | 行级锁支持并发 UPDATE |

## 引擎开发者视角

**核心设计决策**：UPDATE 在不同存储架构中的实现差异巨大。行存引擎可以原地更新，列存引擎通常需要 delete + insert（因为同一行的不同列分散存储），LSM 引擎写入新版本等待合并。

**实现建议**：
- MVCC 下的 UPDATE 通常实现为 delete-old-version + insert-new-version：PostgreSQL 的 HOT（Heap-Only Tuple）优化在更新不改变索引列时避免索引更新，这对更新频繁的场景性能提升显著
- UPDATE ... FROM（多表关联更新）的语法选择：PostgreSQL 的 FROM 子句 vs MySQL 的 JOIN 语法 vs SQL 标准的 MERGE。推荐至少支持一种，MERGE 是最灵活的但实现最复杂
- UPDATE ... RETURNING 是 PostgreSQL 的杀手级特性——获取更新前后的值不需要额外查询，对乐观锁实现（version 列）尤其有用
- 列式引擎的 UPDATE 代价极高：整个数据块都需要重写。ClickHouse 的异步 mutation 方式（后台合并时执行）是现实的折中方案。引擎应明确文档化 UPDATE 的成本并引导用户使用替代方案
- 部分列更新的优化：UPDATE 只修改了一个列时，不应该重写整行的所有列数据。PostgreSQL 的 TOAST 机制（大值外部存储，未修改的不动）是参考
- 常见错误：UPDATE 没有正确处理自引用（UPDATE t SET a = a + 1）——同一语句中读取的值应该是更新前的旧值（SQL 标准的 snapshot 语义），而非已经更新的新值
