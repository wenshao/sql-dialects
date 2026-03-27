# SQL 方言对比大全 — 全局导航索引

面向 **SQL 引擎开发者**的参考资料。覆盖 45 种数据库方言 × 51 个功能模块，分析各方言的语法设计决策、实现 trade-off、兼容性选择。

---

## 兼容性族谱

设计新的 SQL 引擎（或扩展现有引擎）时，首先要决定的是**兼容性路线**。以下是当前主流的兼容性族谱：

### MySQL 族

兼容 MySQL 协议和语法，用户迁移成本最低。适合 OLTP 和 Web 应用场景。

| 引擎 | 兼容度 | 核心差异 |
|------|--------|---------|
| [MySQL](dialects/mysql.md) | 基准 | — |
| [MariaDB](dialects/mariadb.md) | 高 | 独有: SEQUENCE(10.3+)、系统版本表、RETURNING |
| [TiDB](dialects/tidb.md) | 高 | 分布式: AUTO_RANDOM、TiFlash 列存、无触发器 |
| [OceanBase](dialects/oceanbase.md) | 高 | 双模: MySQL + Oracle，分布式事务 |
| [PolarDB](dialects/polardb.md) | 高 | 云原生: 全局索引、广播表 |
| [TDSQL](dialects/tdsql.md) | 高 | 分布式: shardkey 分片、广播表 |
| [StarRocks](dialects/starrocks.md) | 协议兼容 | OLAP: 4 种数据模型、物化视图、向量化 |
| [Doris](dialects/doris.md) | 协议兼容 | OLAP: 同 StarRocks 同源 |

**引擎开发者参考**: 兼容 MySQL 意味着要处理 AUTO_INCREMENT 语义、ON DUPLICATE KEY UPDATE、DELIMITER 的 parser 支持、以及 utf8/utf8mb4 的历史包袱。

### PostgreSQL 族

兼容 PostgreSQL 协议和语法，功能最丰富。适合需要高级 SQL 特性的场景。

| 引擎 | 兼容度 | 核心差异 |
|------|--------|---------|
| [PostgreSQL](dialects/postgres.md) | 基准 | — |
| [CockroachDB](dialects/cockroachdb.md) | 高 | 分布式: unique_rowid()、CHANGEFEED、默认 SERIALIZABLE |
| [YugabyteDB](dialects/yugabytedb.md) | 高 | 分布式: 哈希分片、tablet splitting |
| [Greenplum](dialects/greenplum.md) | 高 | MPP: DISTRIBUTED BY、列存、gpfdist |
| [Redshift](dialects/redshift.md) | 中 | 基于 PG 8.x，无索引、DISTKEY/SORTKEY |
| [openGauss](dialects/opengauss.md) | 高 | 华为: MOT 内存表、AI 调优 |
| [Hologres](dialects/hologres.md) | 中 | 阿里云: 行列混存、set_table_property |
| [TimescaleDB](dialects/timescaledb.md) | 扩展 | 时序: hypertable、time_bucket、连续聚合 |
| [Materialize](dialects/materialize.md) | 协议兼容 | 流式: 增量物化视图、SUBSCRIBE |
| [DuckDB](dialects/duckdb.md) | 方言兼容 | 嵌入式 OLAP: LIST/STRUCT/MAP、PIVOT |

**引擎开发者参考**: 兼容 PostgreSQL 意味着要支持 :: 类型转换、$$ 函数体、RETURNING 子句、以及更严格的类型系统。PostgreSQL 的 DDL 是事务性的（可回滚 CREATE TABLE），这增加了实现复杂度。

### Oracle 族

兼容 Oracle 语法和 PL/SQL，适合企业级迁移场景。

| 引擎 | 兼容度 | 核心差异 |
|------|--------|---------|
| [Oracle](dialects/oracle.md) | 基准 | — |
| [达梦](dialects/dameng.md) | 高 | 国产: DMSQL、IDENTITY |
| [人大金仓](dialects/kingbase.md) | 中 | 双模: PG 兼容 + Oracle 兼容 |
| [OceanBase](dialects/oceanbase.md) | 中 | Oracle 模式: PL/SQL、CONNECT BY |

**引擎开发者参考**: 兼容 Oracle 最大的坑是 `'' = NULL` 语义。此外需要支持 CONNECT BY 层级查询、PL/SQL 包（Package）、以及 DUAL 表。

### Hive/Spark 族

兼容 HiveQL 语法，面向大数据生态。

| 引擎 | 兼容度 | 核心差异 |
|------|--------|---------|
| [Hive](dialects/hive.md) | 基准 | STORED AS、SerDe、INSERT OVERWRITE |
| [Spark SQL](dialects/spark.md) | 高 | 批处理: USING format、Delta Lake |
| [Databricks SQL](dialects/databricks.md) | 高 | Lakehouse: Delta Lake、Unity Catalog |
| [MaxCompute](dialects/maxcompute.md) | 中 | 阿里云: 自有扩展、事务表 |
| [Impala](dialects/impala.md) | 中 | 实时查询: Kudu 表支持 UPDATE |
| [Flink SQL](dialects/flink.md) | 部分 | 流处理: WATERMARK、时间窗口 TVF |

**引擎开发者参考**: Hive 族的核心概念是"分区是目录"、"INSERT OVERWRITE 是主要写入模式"。传统 RDBMS 的 UPDATE/DELETE 在 Hive 族中是后期才加入的（需要 ACID 支持）。

### 独立方言

不属于任何兼容族，有自己独特的语法设计。

| 引擎 | 定位 | 语法特点 |
|------|------|---------|
| [SQL Server](dialects/sqlserver.md) | 企业 OLTP | T-SQL、IDENTITY、CROSS APPLY、聚集索引 |
| [ClickHouse](dialects/clickhouse.md) | 列式分析 | MergeTree 引擎族、INSERT-only、异步 mutation |
| [BigQuery](dialects/bigquery.md) | 云数仓 | INT64/STRING 类型名、无索引、按扫描计费 |
| [Snowflake](dialects/snowflake.md) | 云数仓 | VARIANT 半结构化、QUALIFY、零拷贝 CLONE |
| [Teradata](dialects/teradata.md) | MPP 数仓 | PRIMARY INDEX 分布、QUALIFY（首创）、COLLECT STATISTICS |
| [Vertica](dialects/vertica.md) | 列式分析 | Projections 代替索引、SEGMENTED BY |
| [Spanner](dialects/spanner.md) | 全球分布 | INTERLEAVE IN PARENT、无自增 |
| [SQLite](dialects/sqlite.md) | 嵌入式 | 动态类型、文件级锁、WITHOUT ROWID |
| [TDengine](dialects/tdengine.md) | 时序 IoT | 超级表/子表/标签、INTERVAL/FILL |
| [ksqlDB](dialects/ksqldb.md) | 流处理 | STREAM vs TABLE、EMIT CHANGES |
| [SQL 标准](dialects/sql-standard.md) | 参考标准 | SQL-86 ~ SQL:2023 演进 |

---

## 按设计主题导航

以下按 SQL 引擎开发者最关心的设计主题组织，每个主题链接到最相关的模块。

### 数据模型与存储

| 主题 | 核心模块 | 设计决策 |
|------|---------|---------|
| 表结构定义 | [create-table](ddl/create-table/) | ENGINE 子句？分区语法？约束执行还是信息性？ |
| 数据类型系统 | [string](types/string/), [numeric](types/numeric/), [datetime](types/datetime/) | 严格类型还是动态类型？VARCHAR(n) 的 n 是字符还是字节？ |
| 复合类型 | [array-map-struct](types/array-map-struct/) | 原生 ARRAY/MAP/STRUCT 还是用 JSON 替代？ |
| JSON 支持 | [json](types/json/) | 原生 JSON 类型 vs JSONB vs VARCHAR 存储？路径表达式语法？ |
| 自增/序列 | [sequences](ddl/sequences/) | AUTO_INCREMENT vs IDENTITY vs SEQUENCE？分布式怎么办？ |
| 约束系统 | [constraints](ddl/constraints/) | CHECK 执行还是忽略？外键在分布式环境下怎么办？ |
| 索引系统 | [indexes](ddl/indexes/) | B-tree/Hash/GIN/GiST？函数索引？不可见索引？ |
| 视图 | [views](ddl/views/) | 物化视图刷新策略？可更新视图规则？ |
| 分区 | [partitioning](advanced/partitioning/) | RANGE/LIST/HASH？分区键必须在主键中吗？ |

### DML 语义

| 主题 | 核心模块 | 设计决策 |
|------|---------|---------|
| UPSERT | [upsert](dml/upsert/) | MERGE vs ON CONFLICT vs ON DUPLICATE KEY？并发安全性？ |
| 批量写入 | [insert](dml/insert/) | INSERT OVERWRITE？COPY/LOAD？流式写入？ |
| 更新/删除 | [update](dml/update/), [delete](dml/delete/) | 分析引擎支持吗？异步 mutation？ |

### 查询能力

| 主题 | 核心模块 | 设计决策 |
|------|---------|---------|
| 窗口函数 | [window-functions](query/window-functions/) | ROWS vs RANGE vs GROUPS 帧？QUALIFY 子句？FILTER？ |
| 递归查询 | [cte](query/cte/) | 递归 CTE vs CONNECT BY？MATERIALIZED 提示？ |
| 分页 | [pagination](query/pagination/) | LIMIT vs FETCH FIRST vs TOP vs ROWNUM？ |
| 集合操作 | [set-operations](query/set-operations/) | EXCEPT vs MINUS？INTERSECT ALL？ |
| PIVOT | [pivot-unpivot](query/pivot-unpivot/) | 原生 PIVOT 语法 vs CASE WHEN + GROUP BY？ |
| 全文搜索 | [full-text-search](query/full-text-search/) | 内置 vs 扩展？倒排索引实现？ |
| JOIN | [joins](query/joins/) | LATERAL？CROSS APPLY？ARRAY JOIN？SEMI/ANTI JOIN？ |
| 子查询 | [subquery](query/subquery/) | 相关子查询优化（semijoin）？LATERAL 支持？ |

### 事务与并发

| 主题 | 核心模块 | 设计决策 |
|------|---------|---------|
| 事务模型 | [transactions](advanced/transactions/) | MVCC vs 锁？SSI vs 2PL？DDL 事务性？ |
| 锁机制 | [locking](advanced/locking/) | 行锁/表锁/间隙锁？NOWAIT/SKIP LOCKED？ |
| 隔离级别 | [transactions](advanced/transactions/) | 默认 READ COMMITTED 还是 REPEATABLE READ？ |

### 可编程性

| 主题 | 核心模块 | 设计决策 |
|------|---------|---------|
| 存储过程 | [stored-procedures](advanced/stored-procedures/) | PL/pgSQL vs PL/SQL vs T-SQL vs SQLScript？多语言 UDF？ |
| 触发器 | [triggers](advanced/triggers/) | BEFORE/AFTER/INSTEAD OF？行级/语句级？ |
| 动态 SQL | [dynamic-sql](advanced/dynamic-sql/) | PREPARE/EXECUTE vs EXECUTE IMMEDIATE？ |
| 错误处理 | [error-handling](advanced/error-handling/) | TRY/CATCH vs EXCEPTION WHEN vs DECLARE HANDLER？ |

### 运维与管理

| 主题 | 核心模块 | 设计决策 |
|------|---------|---------|
| 执行计划 | [explain](advanced/explain/) | EXPLAIN 输出格式？ANALYZE 实际执行？ |
| 权限系统 | [permissions](advanced/permissions/) | RBAC？行级安全？IAM 集成？ |
| 临时表 | [temp-tables](advanced/temp-tables/) | 会话级 vs 事务级？全局 vs 本地？ |
| 数据库/Schema | [users-databases](ddl/users-databases/) | 两级命名(db.table) vs 三级(catalog.schema.table)？ |
| 类型转换 | [type-conversion](functions/type-conversion/) | 隐式转换规则？TRY_CAST/SAFE_CAST 安全转换？ |

### 实战场景

这些场景展示了相同业务需求在不同引擎中的最佳实现方式：

| 场景 | 模块 | 引擎差异最大的点 |
|------|------|----------------|
| TopN 查询 | [ranking-top-n](scenarios/ranking-top-n/) | QUALIFY vs ROW_NUMBER 子查询 vs LATERAL |
| 累计求和 | [running-total](scenarios/running-total/) | 窗口帧语义、RANGE INTERVAL 支持 |
| 数据去重 | [deduplication](scenarios/deduplication/) | DISTINCT ON vs ROW_NUMBER vs ReplacingMergeTree |
| 层级查询 | [hierarchical-query](scenarios/hierarchical-query/) | 递归 CTE vs CONNECT BY vs ltree |
| 日期填充 | [date-series-fill](scenarios/date-series-fill/) | generate_series vs CONNECT BY LEVEL vs WITH FILL |
| 字符串拆分 | [string-split-to-rows](scenarios/string-split-to-rows/) | STRING_SPLIT vs UNNEST vs LATERAL VIEW explode |
| JSON 展开 | [json-flatten](scenarios/json-flatten/) | JSON_TABLE vs OPENJSON vs jsonb_array_elements vs FLATTEN |
| 迁移速查 | [migration-cheatsheet](scenarios/migration-cheatsheet/) | 类型映射、函数对照、语法差异 |
| 缓慢变化维 | [slowly-changing-dim](scenarios/slowly-changing-dim/) | MERGE vs 时态表 vs INSERT OVERWRITE |
| 窗口分析 | [window-analytics](scenarios/window-analytics/) | 移动平均、同环比、PERCENT_RANK |
| 区间检测 | [gap-detection](scenarios/gap-detection/) | LAG/LEAD vs generate_series vs WITH FILL |

---

## 关键设计决策速查

引擎开发中最常遇到的设计决策，以及各方言的选择：

| 决策 | MySQL | PostgreSQL | Oracle | SQL Server | BigQuery | ClickHouse |
|------|-------|-----------|--------|-----------|---------|-----------|
| 默认隔离级别 | REPEATABLE READ | READ COMMITTED | READ COMMITTED | READ COMMITTED | SNAPSHOT | 无事务 |
| DDL 可回滚 | 否 | **是** | 否 | **是** | 否 | 否 |
| '' = NULL | 否 | 否 | **是** | 否 | 否 | 否 |
| 类型严格度 | 宽松 | **严格** | 中等 | 中等 | 严格 | 严格 |
| UPSERT 语法 | ON DUPLICATE KEY | ON CONFLICT | MERGE | MERGE | MERGE | 无（引擎级去重） |
| 自增方式 | AUTO_INCREMENT | IDENTITY | SEQUENCE/IDENTITY | IDENTITY | 无 | 无 |
| 分页语法 | LIMIT | LIMIT/FETCH | FETCH(12c+) | OFFSET/FETCH | LIMIT | LIMIT |
| 递归查询 | CTE(8.0+) | CTE | CTE/CONNECT BY | CTE | CTE | CTE(有限) |
| 约束执行 | 8.0.16+ CHECK | 全部执行 | 全部执行 | 全部执行 | **不执行** | **不执行** |

---

## 相关文档

- [README.md](README.md) — 项目介绍与目录结构
- [dialects/](dialects/) — 按方言浏览（45 个方言索引页）
- [REFERENCES.md](REFERENCES.md) — 全方言官方文档链接索引
- [CONTRIBUTING.md](CONTRIBUTING.md) — 贡献指南
