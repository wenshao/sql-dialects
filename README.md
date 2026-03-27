# sql-dialects

收集和对比各种数据库 SQL 方言的写法差异。全网最全的 SQL 方言对比大全。

## 项目规模

- **2,295+ SQL 文件**，覆盖 **45 种方言** × **51 个功能模块**
- **11 个实战场景**，每个场景 45 种方言的最佳实践
- **47 个对比总览表**，横向对比各方言特性支持
- **191,000+ 行代码**，每个文件附官方文档参考资料
- 经过多轮全量审计，修正 154+ 个问题

## 覆盖的数据库（45 种）

### 传统关系型数据库
MySQL, PostgreSQL, SQLite, Oracle, SQL Server, MariaDB, Firebird, IBM Db2, SAP HANA

### 大数据 / 分析型引擎
BigQuery, Snowflake, MaxCompute, Hive, ClickHouse, StarRocks, Trino, Hologres, Apache Doris, DuckDB, Spark SQL, Flink SQL

### 云数仓
Amazon Redshift, Azure Synapse, Databricks SQL, Greenplum, Apache Impala, Vertica, Teradata

### 分布式 / NewSQL
TiDB, OceanBase, CockroachDB, Google Cloud Spanner, YugabyteDB, PolarDB, openGauss, TDSQL

### 国产数据库
达梦 (DamengDB), 人大金仓 (KingbaseES)

### 流处理
Flink SQL, ksqlDB, Materialize

### 时序数据库
TimescaleDB, TDengine

### 嵌入式 / 轻量
H2, Apache Derby

### SQL 标准
SQL-86 / SQL-89 / SQL-92 / SQL:1999 / SQL:2003 / SQL:2008 / SQL:2011 / SQL:2016 / SQL:2023

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
