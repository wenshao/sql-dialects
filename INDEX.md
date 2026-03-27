# SQL 方言对比大全 -- 全局导航索引

本项目系统性地收集和对比 **45 种数据库** SQL 方言的写法差异，覆盖 **51 个功能模块**、**2,295+ SQL 文件**。每个文件均附带官方文档参考资料，方便查阅和迁移。

---

## 模块总览

### DDL -- 数据定义（7 个模块）

| 模块 | 说明 |
|------|------|
| [建表](ddl/create-table/) | CREATE TABLE 语法、列定义、约束内联写法 |
| [改表](ddl/alter-table/) | ALTER TABLE 添加/删除/修改列、重命名 |
| [索引](ddl/indexes/) | 索引创建、类型（B-tree、Hash、GIN 等）、部分索引 |
| [约束](ddl/constraints/) | PRIMARY KEY、FOREIGN KEY、UNIQUE、CHECK、DEFAULT |
| [视图](ddl/views/) | 普通视图、物化视图、可更新视图 |
| [序列](ddl/sequences/) | 序列对象、自增列、IDENTITY 策略 |
| [用户与数据库](ddl/users-databases/) | CREATE DATABASE、CREATE USER、SCHEMA 管理 |

### DML -- 数据操作（4 个模块）

| 模块 | 说明 |
|------|------|
| [插入](dml/insert/) | INSERT INTO、批量插入、INSERT ... SELECT |
| [更新](dml/update/) | UPDATE SET、多表更新、条件更新 |
| [删除](dml/delete/) | DELETE FROM、TRUNCATE、条件删除 |
| [插入或更新](dml/upsert/) | UPSERT / MERGE / ON CONFLICT / ON DUPLICATE KEY |

### Query -- 查询（8 个模块）

| 模块 | 说明 |
|------|------|
| [连接查询](query/joins/) | INNER / LEFT / RIGHT / FULL / CROSS JOIN |
| [子查询](query/subquery/) | 标量子查询、EXISTS、IN、关联子查询 |
| [窗口函数](query/window-functions/) | ROW_NUMBER、RANK、LEAD/LAG、NTILE |
| [公共表表达式](query/cte/) | WITH 子句、递归 CTE |
| [分页](query/pagination/) | LIMIT/OFFSET、FETCH FIRST、游标分页 |
| [全文搜索](query/full-text-search/) | 全文索引、MATCH AGAINST、tsvector |
| [集合操作](query/set-operations/) | UNION / INTERSECT / EXCEPT (ALL) |
| [行列转换](query/pivot-unpivot/) | PIVOT / UNPIVOT、条件聚合实现转置 |

### Types -- 数据类型（5 个模块）

| 模块 | 说明 |
|------|------|
| [字符串类型](types/string/) | CHAR、VARCHAR、TEXT、CLOB、编码 |
| [数值类型](types/numeric/) | INT、DECIMAL、FLOAT、DOUBLE、NUMERIC |
| [日期时间类型](types/datetime/) | DATE、TIME、TIMESTAMP、INTERVAL、时区处理 |
| [JSON 类型](types/json/) | JSON / JSONB 存储、查询、路径表达式 |
| [复合类型](types/array-map-struct/) | ARRAY、MAP、STRUCT、嵌套类型 |

### Functions -- 内置函数（6 个模块）

| 模块 | 说明 |
|------|------|
| [字符串函数](functions/string-functions/) | CONCAT、SUBSTRING、REPLACE、TRIM、正则 |
| [日期函数](functions/date-functions/) | DATE_ADD、DATEDIFF、EXTRACT、格式化 |
| [聚合函数](functions/aggregate/) | COUNT、SUM、AVG、GROUP_CONCAT、ARRAY_AGG |
| [条件函数](functions/conditional/) | CASE WHEN、COALESCE、NULLIF、IIF、DECODE |
| [数学函数](functions/math-functions/) | ABS、ROUND、CEIL、FLOOR、MOD、POWER |
| [类型转换](functions/type-conversion/) | CAST、CONVERT、隐式转换规则 |

### Advanced -- 高级特性（10 个模块）

| 模块 | 说明 |
|------|------|
| [存储过程](advanced/stored-procedures/) | CREATE PROCEDURE / FUNCTION、参数、流程控制 |
| [触发器](advanced/triggers/) | BEFORE / AFTER / INSTEAD OF 触发器 |
| [事务](advanced/transactions/) | BEGIN / COMMIT / ROLLBACK、隔离级别、SAVEPOINT |
| [权限管理](advanced/permissions/) | GRANT / REVOKE、角色、行级安全 |
| [执行计划](advanced/explain/) | EXPLAIN / EXPLAIN ANALYZE、查询优化分析 |
| [临时表](advanced/temp-tables/) | 临时表、表变量、WITH 临时结果集 |
| [分区](advanced/partitioning/) | RANGE / LIST / HASH 分区策略 |
| [动态 SQL](advanced/dynamic-sql/) | EXECUTE IMMEDIATE、PREPARE、参数化 |
| [错误处理](advanced/error-handling/) | TRY...CATCH、EXCEPTION、SIGNAL/RESIGNAL |
| [锁机制](advanced/locking/) | FOR UPDATE、表锁、乐观锁、死锁处理 |

### Scenarios -- 实战场景（11 个模块）

| 模块 | 说明 |
|------|------|
| [TopN 查询](scenarios/ranking-top-n/) | 分组取前 N 条记录、排名并列处理 |
| [累计求和](scenarios/running-total/) | 窗口累加、滚动平均、移动聚合 |
| [数据去重](scenarios/deduplication/) | ROW_NUMBER 去重、DISTINCT ON、自连接 |
| [区间缺失检测](scenarios/gap-detection/) | 序号断层、日期间隙、岛屿问题 |
| [层级查询](scenarios/hierarchical-query/) | 递归 CTE、CONNECT BY、树形遍历 |
| [日期序列填充](scenarios/date-series-fill/) | 生成连续日期、补零填充、时间序列 |
| [字符串拆分](scenarios/string-split-to-rows/) | 逗号分隔转多行、正则拆分 |
| [JSON 展开](scenarios/json-flatten/) | JSON 数组展开为行、嵌套对象提取 |
| [缓慢变化维](scenarios/slowly-changing-dim/) | SCD Type 1/2/3、历史版本追踪 |
| [迁移速查](scenarios/migration-cheatsheet/) | 跨方言迁移语法对照、兼容性映射 |
| [窗口分析实战](scenarios/window-analytics/) | 窗口函数综合分析场景、多指标计算 |

---

## 方言速查表（45 种）

### 传统关系型数据库

| 方言 | 基础兼容性 |
|------|-----------|
| MySQL | MySQL 原生语法 |
| PostgreSQL | PostgreSQL 原生语法 |
| SQLite | 轻量级嵌入式，语法精简子集 |
| Oracle | Oracle 原生语法（PL/SQL） |
| SQL Server | T-SQL 原生语法 |
| MariaDB | MySQL 兼容，扩展增强 |
| Firebird | 独立语法体系，兼容 SQL 标准 |
| DB2 | IBM DB2 原生语法 |
| SAP HANA | 独立语法体系，支持 SQL 标准 |

### 大数据 / 分析型引擎

| 方言 | 基础兼容性 |
|------|-----------|
| BigQuery | Google 标准 SQL |
| Snowflake | 独立语法，接近 SQL 标准 |
| MaxCompute | 独立语法（ODPS SQL） |
| Hive | HiveQL，MapReduce SQL 化 |
| ClickHouse | 独立语法，部分兼容 SQL 标准 |
| StarRocks | MySQL 协议兼容 |
| Trino | ANSI SQL 兼容 |
| Hologres | PostgreSQL 兼容 |
| Apache Doris | MySQL 协议兼容 |
| DuckDB | PostgreSQL 方言兼容 |
| Spark SQL | HiveQL 兼容，扩展 SQL 标准 |
| Flink SQL | ANSI SQL 兼容，流处理扩展 |

### 云数仓

| 方言 | 基础兼容性 |
|------|-----------|
| Amazon Redshift | PostgreSQL 兼容（8.x 子集） |
| Azure Synapse | T-SQL 兼容（SQL Server 子集） |
| Databricks SQL | Spark SQL / Hive 兼容 |
| Greenplum | PostgreSQL 兼容 |
| Apache Impala | HiveQL 兼容，支持部分 SQL-92 |
| Vertica | 独立语法，接近 SQL-99 标准 |
| Teradata | 独立语法体系 |

### 分布式 / NewSQL

| 方言 | 基础兼容性 |
|------|-----------|
| TiDB | MySQL 兼容 |
| OceanBase | MySQL / Oracle 双模兼容 |
| CockroachDB | PostgreSQL 兼容 |
| Google Cloud Spanner | 独立语法，部分兼容 SQL 标准 |
| YugabyteDB | PostgreSQL 兼容 |
| PolarDB | MySQL / PostgreSQL 兼容（视版本） |
| openGauss | PostgreSQL 兼容 |
| TDSQL | MySQL 兼容 |

### 国产数据库

| 方言 | 基础兼容性 |
|------|-----------|
| 达梦 (DamengDB) | Oracle 兼容 |
| 人大金仓 (KingbaseES) | PostgreSQL / Oracle 双模兼容 |

### 流处理

| 方言 | 基础兼容性 |
|------|-----------|
| ksqlDB | 独立语法，基于 Kafka Streams |
| Materialize | PostgreSQL 兼容，流式物化视图 |

### 时序数据库

| 方言 | 基础兼容性 |
|------|-----------|
| TimescaleDB | PostgreSQL 扩展 |
| TDengine | 独立语法，类 SQL 接口 |

### 嵌入式 / 轻量

| 方言 | 基础兼容性 |
|------|-----------|
| H2 | 多模式兼容（MySQL / PostgreSQL / Oracle / SQL Server） |
| Apache Derby | SQL 标准子集，接近 DB2 |

### SQL 标准

| 方言 | 基础兼容性 |
|------|-----------|
| SQL Standard | ISO/IEC 9075 标准参考（SQL-86 至 SQL:2023） |

---

## 相关文档

- [README.md](README.md) -- 项目介绍与目录结构
- [CONTRIBUTING.md](CONTRIBUTING.md) -- 贡献指南
- [REFERENCES.md](REFERENCES.md) -- 全方言官方文档链接索引
