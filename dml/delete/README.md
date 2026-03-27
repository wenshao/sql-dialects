# 删除 (DELETE)

各数据库 DELETE 语法对比，包括条件删除、多表关联删除、TRUNCATE 等。

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

1. **多表关联删除**：MySQL 用 `DELETE t1 FROM t1 JOIN t2 ON ...`，PostgreSQL 用 `DELETE FROM t1 USING t2 WHERE ...`，SQL Server 用 `DELETE t1 FROM t1 JOIN t2 ON ...`
2. **TRUNCATE vs DELETE**：TRUNCATE 不可回滚（MySQL/Oracle）或可回滚（PostgreSQL），TRUNCATE 不触发触发器，速度远快于 DELETE
3. **DELETE ... RETURNING**：PostgreSQL 支持返回被删除的行，MySQL/Oracle 不支持
4. **DELETE ... ORDER BY LIMIT**：MySQL 支持限制删除行数，适合分批删除大量数据
5. **软删除的替代**：分析型引擎中 DELETE 代价昂贵，ClickHouse 用 TTL 自动清理过期数据更高效

## 选型建议

清空全表用 TRUNCATE（不需要日志和触发器时）。大批量删除建议分批执行或使用分区 DROP。生产环境建议先 SELECT COUNT(*) 确认影响范围。在分析型引擎中避免频繁 DELETE，优先考虑分区过期策略。

## 版本演进

- ClickHouse：DELETE 从异步 mutation 演进到 20.8+ 的轻量级删除（ALTER TABLE DELETE）
- Hive 0.14+：ACID 事务表支持 DELETE
- MySQL 8.0：DELETE 的 WITH CTE 语法支持（更清晰的子查询写法）

## 横向对比

| 特性维度 | SQLite | ClickHouse | BigQuery | 传统 RDBMS (MySQL/PG/Oracle) |
|---|---|---|---|---|
| **DELETE 可用性** | 标准 DELETE 语法 | DELETE 是异步 mutation（ALTER TABLE DELETE），非即时 | 标准 DELETE 语法但有 DML 配额限制 | 标准即时 DELETE |
| **DELETE 哲学** | 即时行级删除 | INSERT-only 哲学：删除通过标记 + 后台合并实现最终一致 | Serverless 执行，DELETE 内部重写受影响的数据文件 | MVCC 即时行级删除 |
| **TRUNCATE** | DELETE FROM table（无 TRUNCATE 关键字），用 sqlite3_reset 或重建 | 支持 TRUNCATE TABLE（立即清空） | 不支持 TRUNCATE（用 DELETE 全表或重建表） | TRUNCATE 高速清空，不可回滚（PG 可回滚） |
| **DELETE RETURNING** | 3.35.0+ 支持 RETURNING | 不支持 | 不支持 | PG 支持 |
| **软删除替代** | 应用层实现 | TTL 自动过期删除是更好的替代方案 | 表/分区过期策略替代手动删除 | 应用层实现或 Oracle VPD |
| **性能代价** | 轻量操作 | 重量级：重写 data part，推荐用 TTL 或分区 DROP 替代 | 消耗 DML 配额，大批量删除建议按分区操作 | 行级操作，大批量建议分批 |

## 引擎开发者视角

**核心设计决策**：DELETE 的实现方式取决于存储引擎的数据组织方式。行存引擎的原地删除与列存/LSM 引擎的标记删除是完全不同的技术路线。

**实现建议**：
- MVCC 引擎中 DELETE 通常是标记删除（标记行为不可见），物理空间回收延迟到 VACUUM/compaction 阶段。这是正确的设计——即时物理删除会破坏并发读事务的快照
- TRUNCATE TABLE 必须与 DELETE FROM table 有本质区别：TRUNCATE 应直接释放数据文件/段，复杂度为 O(1)，不写入行级日志。但 TRUNCATE 的事务性需要明确——PostgreSQL 的 TRUNCATE 可回滚（写入 WAL），MySQL 的不可回滚
- DELETE ... RETURNING（返回被删除的行）实现成本低但对用户很有用——审计、级联操作等场景都需要。推荐从第一天就支持
- 分批删除（DELETE ... ORDER BY ... LIMIT）是 MySQL 的特色语法，对大批量删除避免长事务很有价值。标准方案是用 CTE + DELETE：`WITH to_delete AS (SELECT id FROM t LIMIT 1000) DELETE FROM t WHERE id IN (SELECT id FROM to_delete)`
- 列式/分析型引擎中 DELETE 代价极高（需要重写整个数据块），推荐引导用户使用 TTL 自动过期或分区 DROP 替代。ClickHouse 的轻量级 DELETE（标记删除 + 后台清理）是列式引擎的实用折中
- 常见错误：DELETE 不触发外键的 CASCADE/SET NULL 操作。外键级联删除的递归深度需要有限制以防止意外的大规模数据删除
