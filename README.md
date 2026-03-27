# sql-dialects

收集和对比各种数据库 SQL 方言的语法设计差异，面向 SQL 引擎开发者。

## 项目规模

- **2,295+ SQL 文件**，覆盖 **45 种方言** × **51 个功能模块**
- **11 个实战场景**，每个场景 45 种方言的最佳实践
- **47 个对比总览表**，横向对比各方言特性支持
- **191,000+ 行代码**，每个文件附官方文档参考资料
- 经过多轮全量审计，修正 154+ 个问题

## 面向 SQL 引擎开发者

本项目面向 SQL 引擎开发者（如 MaxCompute、StarRocks、Doris 的语法设计和开发人员），分析各引擎的语法设计决策、实现 trade-off、兼容性选择。

> **新手开始** → [`docs/how-to-use.md`](docs/how-to-use.md) — 引擎开发者阅读指南
>
> **做 MySQL 兼容？** → [`docs/mysql-compat-guide.md`](docs/mysql-compat-guide.md) — MySQL 兼容引擎开发指南
>
> **设计新特性？** → [`docs/feature-design-checklist.md`](docs/feature-design-checklist.md) — SQL 特性设计清单

## 快速导航

> **按方言浏览** → [`dialects/`](dialects/) — 选择一个数据库，查看它在所有模块中的写法
>
> **按功能浏览** → 点击下方目录链接，查看所有方言在该功能上的对比
>
> **全局索引** → [`INDEX.md`](INDEX.md) — 设计主题导航 + 决策速查表

## 覆盖的数据库（[45 种](dialects/)）

### 传统关系型数据库
[MySQL](dialects/mysql.md), [PostgreSQL](dialects/postgres.md), [SQLite](dialects/sqlite.md), [Oracle](dialects/oracle.md), [SQL Server](dialects/sqlserver.md), [MariaDB](dialects/mariadb.md), [Firebird](dialects/firebird.md), [IBM Db2](dialects/db2.md), [SAP HANA](dialects/saphana.md)

### 大数据 / 分析型引擎
[BigQuery](dialects/bigquery.md), [Snowflake](dialects/snowflake.md), [MaxCompute](dialects/maxcompute.md), [Hive](dialects/hive.md), [ClickHouse](dialects/clickhouse.md), [StarRocks](dialects/starrocks.md), [Trino](dialects/trino.md), [Hologres](dialects/hologres.md), [Apache Doris](dialects/doris.md), [DuckDB](dialects/duckdb.md), [Spark SQL](dialects/spark.md), [Flink SQL](dialects/flink.md)

### 云数仓
[Amazon Redshift](dialects/redshift.md), [Azure Synapse](dialects/synapse.md), [Databricks SQL](dialects/databricks.md), [Greenplum](dialects/greenplum.md), [Apache Impala](dialects/impala.md), [Vertica](dialects/vertica.md), [Teradata](dialects/teradata.md)

### 分布式 / NewSQL
[TiDB](dialects/tidb.md), [OceanBase](dialects/oceanbase.md), [CockroachDB](dialects/cockroachdb.md), [Google Cloud Spanner](dialects/spanner.md), [YugabyteDB](dialects/yugabytedb.md), [PolarDB](dialects/polardb.md), [openGauss](dialects/opengauss.md), [TDSQL](dialects/tdsql.md)

### 国产数据库
[达梦 (DamengDB)](dialects/dameng.md), [人大金仓 (KingbaseES)](dialects/kingbase.md)

### 流处理
[Flink SQL](dialects/flink.md), [ksqlDB](dialects/ksqldb.md), [Materialize](dialects/materialize.md)

### 时序数据库
[TimescaleDB](dialects/timescaledb.md), [TDengine](dialects/tdengine.md)

### 嵌入式 / 轻量
[H2](dialects/h2.md), [Apache Derby](dialects/derby.md)

### SQL 标准
[SQL-86 ~ SQL:2023](dialects/sql-standard.md)

## 目录结构

### DDL — 数据定义（7 个模块）
- [`ddl/create-table/`](ddl/create-table/) — 建表
- [`ddl/alter-table/`](ddl/alter-table/) — 改表
- [`ddl/indexes/`](ddl/indexes/) — 索引
- [`ddl/constraints/`](ddl/constraints/) — 约束
- [`ddl/views/`](ddl/views/) — 视图（普通视图、物化视图）
- [`ddl/sequences/`](ddl/sequences/) — 序列与自增策略
- [`ddl/users-databases/`](ddl/users-databases/) — 数据库、Schema、用户管理

### DML — 数据操作（4 个模块）
- [`dml/insert/`](dml/insert/) — 插入
- [`dml/update/`](dml/update/) — 更新
- [`dml/delete/`](dml/delete/) — 删除
- [`dml/upsert/`](dml/upsert/) — 插入或更新

### Query — 查询（8 个模块）
- [`query/joins/`](query/joins/) — 连接查询
- [`query/subquery/`](query/subquery/) — 子查询
- [`query/window-functions/`](query/window-functions/) — 窗口函数
- [`query/cte/`](query/cte/) — 公共表表达式
- [`query/pagination/`](query/pagination/) — 分页
- [`query/full-text-search/`](query/full-text-search/) — 全文搜索
- [`query/set-operations/`](query/set-operations/) — 集合操作（UNION / INTERSECT / EXCEPT）
- [`query/pivot-unpivot/`](query/pivot-unpivot/) — 行列转换

### Types — 数据类型（5 个模块）
- [`types/string/`](types/string/) — 字符串类型
- [`types/numeric/`](types/numeric/) — 数值类型
- [`types/datetime/`](types/datetime/) — 日期时间类型
- [`types/json/`](types/json/) — JSON 类型
- [`types/array-map-struct/`](types/array-map-struct/) — 复合类型（ARRAY / MAP / STRUCT）

### Functions — 内置函数（6 个模块）
- [`functions/string-functions/`](functions/string-functions/) — 字符串函数
- [`functions/date-functions/`](functions/date-functions/) — 日期函数
- [`functions/aggregate/`](functions/aggregate/) — 聚合函数
- [`functions/conditional/`](functions/conditional/) — 条件函数
- [`functions/math-functions/`](functions/math-functions/) — 数学函数
- [`functions/type-conversion/`](functions/type-conversion/) — 类型转换

### Advanced — 高级特性（10 个模块）
- [`advanced/stored-procedures/`](advanced/stored-procedures/) — 存储过程
- [`advanced/triggers/`](advanced/triggers/) — 触发器
- [`advanced/transactions/`](advanced/transactions/) — 事务
- [`advanced/permissions/`](advanced/permissions/) — 权限管理
- [`advanced/explain/`](advanced/explain/) — 执行计划
- [`advanced/temp-tables/`](advanced/temp-tables/) — 临时表
- [`advanced/partitioning/`](advanced/partitioning/) — 分区
- [`advanced/dynamic-sql/`](advanced/dynamic-sql/) — 动态 SQL
- [`advanced/error-handling/`](advanced/error-handling/) — 错误处理
- [`advanced/locking/`](advanced/locking/) — 锁机制

### Scenarios — 实战场景（11 个模块）
- [`scenarios/ranking-top-n/`](scenarios/ranking-top-n/) — TopN 查询
- [`scenarios/running-total/`](scenarios/running-total/) — 累计求和
- [`scenarios/deduplication/`](scenarios/deduplication/) — 数据去重
- [`scenarios/gap-detection/`](scenarios/gap-detection/) — 区间缺失检测
- [`scenarios/hierarchical-query/`](scenarios/hierarchical-query/) — 层级查询
- [`scenarios/date-series-fill/`](scenarios/date-series-fill/) — 日期序列填充
- [`scenarios/string-split-to-rows/`](scenarios/string-split-to-rows/) — 字符串拆分
- [`scenarios/json-flatten/`](scenarios/json-flatten/) — JSON 展开
- [`scenarios/slowly-changing-dim/`](scenarios/slowly-changing-dim/) — 缓慢变化维
- [`scenarios/migration-cheatsheet/`](scenarios/migration-cheatsheet/) — 迁移速查
- [`scenarios/window-analytics/`](scenarios/window-analytics/) — 窗口分析（移动平均、同环比、占比）

## 文件格式

每个功能目录下，按方言命名 SQL 文件，并附有对比总览表：

```
query/pagination/
├── mysql.sql
├── postgres.sql
├── sqlite.sql
├── oracle.sql
├── sqlserver.sql
├── bigquery.sql
├── snowflake.sql
├── ... (45 种方言)
├── sql-standard.sql
└── _comparison.md        ← 横向对比表
```

每个 SQL 文件格式：
```sql
-- MySQL: 分页
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - SELECT
--       https://dev.mysql.com/doc/refman/8.0/en/select.html
--   [2] ...

-- LIMIT / OFFSET（所有版本）
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 8.0+: 窗口函数辅助分页
...
```

## 其他文档

- [`INDEX.md`](INDEX.md) — 全局导航索引（模块矩阵 + 方言速查）
- [`REFERENCES.md`](REFERENCES.md) — 所有方言的官方文档链接索引
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — 贡献指南

## 学习路径建议

**入门阶段**：先学 `query/joins/` + `dml/insert/` + `ddl/create-table/`，掌握最基础的增删改查。
然后学 `functions/` 下的字符串函数和日期函数，这两类在日常开发中使用频率最高。

**进阶阶段**：重点攻克 `query/window-functions/` 和 `query/cte/`，它们是现代 SQL 的核心能力分水岭。
配合 `scenarios/` 下的实战场景练习，尤其是 TopN、去重、累计求和三个高频场景。

**高级阶段**：学习 `advanced/transactions/` + `advanced/explain/` + `advanced/partitioning/`，
这三者直接关系到生产环境的数据一致性和查询性能。

## 跨方言核心差异

45 种方言可以归纳为几个"兼容族"：**MySQL 族**（MySQL、MariaDB、TiDB、OceanBase、PolarDB、TDSQL、StarRocks、Doris）、
**PostgreSQL 族**（PostgreSQL、CockroachDB、YugabyteDB、Greenplum、Redshift、TimescaleDB、Materialize）、
**Oracle 族**（Oracle、达梦、人大金仓、OceanBase Oracle 模式）、**Hive/Spark 族**（Hive、Spark SQL、Databricks、Flink SQL、MaxCompute）。
掌握一个族的代表方言后，同族内的迁移成本较低，跨族迁移才是真正的挑战。

最大的坑通常在三个地方：**NULL 处理**（Oracle 中空字符串等于 NULL，其他方言不是）、
**隐式类型转换**（MySQL 极为宽松，PostgreSQL 极为严格）、
**事务行为**（分析型引擎大多不支持完整 ACID 事务）。

## 横向对比 -- 三大特殊方言速查

下表总结 SQLite、ClickHouse、BigQuery 与传统 RDBMS 的核心架构差异。跨方言迁移时，这些差异比语法差异影响更大。

| 维度 | SQLite | ClickHouse | BigQuery |
|---|---|---|---|
| **架构** | 文件级嵌入式，单写多读 | 分布式列式存储，多节点集群 | Serverless 云数仓，按需扩展 |
| **类型系统** | 动态类型（声明类型仅为亲和性） | 严格类型（丰富的数值和日期类型） | 严格类型（INT64/STRING 等有限类型集） |
| **事务模型** | 完整 ACID（文件级锁保证） | 无传统事务，最终一致 | 无跨语句事务，每条 DML 原子执行 |
| **DML 特点** | 标准 CRUD | INSERT-only 哲学，UPDATE/DELETE 是异步 mutation | 标准语法但有 DML 配额限制 |
| **索引策略** | B-Tree 索引 | 排序键 + 跳数索引 | 无索引（分区 + 聚簇替代） |
| **约束执行** | 支持（外键需手动启用） | 不强制执行 | 信息性约束（NOT ENFORCED） |
| **权限系统** | 无 GRANT/REVOKE（依赖文件权限） | 完整 GRANT/REVOKE | IAM 权限管理 |
| **DDL 限制** | 3.35.0 前无 DROP COLUMN | ALTER 为异步 mutation | 在线 DDL，无锁表 |
| **计费模型** | 免费 | 开源/按资源计费 | 按扫描数据量计费 |
