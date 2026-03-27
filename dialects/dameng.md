# 达梦 (DamengDB)

**分类**: 国产数据库（兼容 Oracle）
**文件数**: 51 个 SQL 文件
**总行数**: 4829 行

## 概述与定位

达梦数据库（DamengDB/DM）是武汉达梦数据库股份有限公司研发的国产商业关系型数据库，始于中国最早的数据库学术研究。达梦定位于替代 Oracle 的国产化场景，高度兼容 Oracle SQL 语法、PL/SQL 过程语言和数据字典视图。它是中国信创产业中份额领先的国产数据库之一，广泛应用于政府、金融、电力、交通等关键行业。

## 历史与演进

- **1988 年**：华中科技大学冯裕才教授启动中国第一个自主数据库研究项目。
- **2000 年**：达梦公司成立，将学术成果产品化。
- **2005 年**：DM4 发布，具备企业级 RDBMS 基本能力。
- **2010 年**：DM6 增强集群和高可用支持。
- **2014 年**：DM7 发布，全面引入 Oracle 兼容能力，支持 PL/SQL。
- **2019 年**：DM8 发布，引入列存、读写分离集群和分布式支持。
- **2022-2025 年**：随信创政策推进快速增长，持续完善分布式和云化能力。

## 核心设计思路

达梦采用单机为主的传统 RDBMS 架构，支持多种部署形态：单机、主备、读写分离集群（DM MPP Cluster）和数据守护（Data Guard）。SQL 引擎以 Oracle 兼容为首要目标，实现了 DMSQL 过程语言（兼容 PL/SQL）、包（Package）、同义词（Synonym）、DBLink 等 Oracle 核心特性。存储引擎支持行存和列存两种格式。安全方面通过了多项国家安全认证，支持透明数据加密和强制访问控制。

## 独特特色

- **Oracle 高度兼容**：支持 PL/SQL（DMSQL 方言）、Package、同义词、DBLink、MERGE INTO、序列和伪列（ROWNUM/ROWID）。
- **IDENTITY 列**：类似 SQL Server 的自增列语法 `IDENTITY(1, 1)`，也支持序列。
- **DMSQL 过程语言**：兼容 PL/SQL 的存储过程、函数、触发器和包。
- **兼容多种数据字典视图**：实现 DBA_TABLES、DBA_COLUMNS 等 Oracle 风格的系统视图。
- **达梦数据守护**：类似 Oracle Data Guard 的主备同步方案。
- **HUGE TABLE**：列存引擎用于分析型查询，支持 MPP 并行计算。
- **国密算法支持**：内置 SM2/SM3/SM4 国密加密算法。

## 已知不足

- 闭源商业软件，社区版功能受限，许可证费用较高。
- Oracle 兼容虽广但并非 100%，复杂 PL/SQL 程序迁移仍需调整。
- 生态工具和第三方驱动支持不如 MySQL/PostgreSQL 丰富。
- 分布式部署（DM MPP）的成熟度和易用性与专门的分布式数据库有差距。
- 国际化程度低，文档和社区以中文为主，海外几乎无用户基础。
- 性能调优工具和诊断能力相比 Oracle 原生产品仍有差距。

## 对引擎开发者的参考价值

达梦是中国持续时间最长的自主数据库项目，其 Oracle 兼容层的实现（从 SQL 语法到 PL/SQL 解释器到数据字典视图的完整复现）对理解数据库兼容性工程有重要参考。DMSQL 过程语言引擎的设计展示了如何在自研内核上兼容 PL/SQL 的控制流、异常处理和包机制。IDENTITY 与 SEQUENCE 并存的 ID 生成策略也体现了多方言兼容的设计取舍。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/dameng.sql) | Oracle 高度兼容，NUMBER/VARCHAR2，IDENTITY 自增，国产替代首选 |
| [改表](../ddl/alter-table/dameng.sql) | Oracle 兼容 ALTER 语法，DDL 自动提交(同 Oracle) |
| [索引](../ddl/indexes/dameng.sql) | B-tree/Bitmap/函数索引(Oracle 兼容) |
| [约束](../ddl/constraints/dameng.sql) | PK/FK/CHECK/UNIQUE(Oracle 兼容)，延迟约束 |
| [视图](../ddl/views/dameng.sql) | 物化视图(Oracle 兼容)，刷新策略 |
| [序列与自增](../ddl/sequences/dameng.sql) | SEQUENCE+IDENTITY(Oracle 兼容) |
| [数据库/Schema/用户](../ddl/users-databases/dameng.sql) | Schema=用户(Oracle 兼容)，多租户支持 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/dameng.sql) | EXECUTE IMMEDIATE(Oracle 兼容 PL/SQL) |
| [错误处理](../advanced/error-handling/dameng.sql) | EXCEPTION WHEN(Oracle 兼容 PL/SQL 异常处理) |
| [执行计划](../advanced/explain/dameng.sql) | EXPLAIN 文本+图形化工具 |
| [锁机制](../advanced/locking/dameng.sql) | MVCC+行级锁(Oracle 兼容)，读不阻塞写 |
| [分区](../advanced/partitioning/dameng.sql) | RANGE/LIST/HASH 分区(Oracle 兼容) |
| [权限](../advanced/permissions/dameng.sql) | GRANT/REVOKE(Oracle 兼容)，三权分立安全策略(国产特色) |
| [存储过程](../advanced/stored-procedures/dameng.sql) | PL/SQL 兼容(Package/存储过程/函数)，迁移友好 |
| [临时表](../advanced/temp-tables/dameng.sql) | 全局临时表(Oracle 兼容)，ON COMMIT 子句 |
| [事务](../advanced/transactions/dameng.sql) | MVCC，READ COMMITTED 默认(Oracle 兼容)，ACID |
| [触发器](../advanced/triggers/dameng.sql) | BEFORE/AFTER/INSTEAD OF(Oracle 兼容) |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/dameng.sql) | DELETE 标准(Oracle 兼容)，TRUNCATE |
| [插入](../dml/insert/dameng.sql) | INSERT INTO/INSERT ALL(Oracle 兼容多表插入) |
| [更新](../dml/update/dameng.sql) | UPDATE 标准(Oracle 兼容) |
| [Upsert](../dml/upsert/dameng.sql) | MERGE(Oracle 兼容)，标准实现 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/dameng.sql) | LISTAGG/GROUPING SETS(Oracle 兼容) |
| [条件函数](../functions/conditional/dameng.sql) | DECODE/CASE/NVL/NVL2(Oracle 兼容) |
| [日期函数](../functions/date-functions/dameng.sql) | TO_DATE/TO_CHAR(Oracle 兼容格式模型) |
| [数学函数](../functions/math-functions/dameng.sql) | Oracle 兼容数学函数 |
| [字符串函数](../functions/string-functions/dameng.sql) | || 拼接(Oracle 兼容)，''=NULL 行为需确认 |
| [类型转换](../functions/type-conversion/dameng.sql) | CAST/TO_NUMBER/TO_DATE(Oracle 兼容) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/dameng.sql) | WITH+递归 CTE 支持 |
| [全文搜索](../query/full-text-search/dameng.sql) | 全文索引支持(内置) |
| [连接查询](../query/joins/dameng.sql) | JOIN 完整(Oracle 兼容)，(+) 外连接语法 |
| [分页](../query/pagination/dameng.sql) | ROWNUM(Oracle 兼容)+LIMIT/OFFSET(扩展) |
| [行列转换](../query/pivot-unpivot/dameng.sql) | PIVOT/UNPIVOT(Oracle 兼容) |
| [集合操作](../query/set-operations/dameng.sql) | UNION/INTERSECT/MINUS(Oracle 兼容用 MINUS) |
| [子查询](../query/subquery/dameng.sql) | 关联子查询(Oracle 兼容) |
| [窗口函数](../query/window-functions/dameng.sql) | 完整窗口函数(Oracle 兼容) |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/dameng.sql) | CONNECT BY LEVEL(Oracle 兼容) 或递归 CTE |
| [去重](../scenarios/deduplication/dameng.sql) | ROW_NUMBER+ROWID(Oracle 兼容) |
| [区间检测](../scenarios/gap-detection/dameng.sql) | 窗口函数+CONNECT BY 辅助 |
| [层级查询](../scenarios/hierarchical-query/dameng.sql) | CONNECT BY/递归 CTE(Oracle 兼容) |
| [JSON 展开](../scenarios/json-flatten/dameng.sql) | JSON_TABLE/JSON_VALUE(标准) |
| [迁移速查](../scenarios/migration-cheatsheet/dameng.sql) | Oracle 高度兼容是核心卖点，PL/SQL 迁移成本低 |
| [TopN 查询](../scenarios/ranking-top-n/dameng.sql) | ROWNUM/ROW_NUMBER(Oracle 兼容) |
| [累计求和](../scenarios/running-total/dameng.sql) | SUM() OVER(Oracle 兼容) |
| [缓慢变化维](../scenarios/slowly-changing-dim/dameng.sql) | MERGE(Oracle 兼容) |
| [字符串拆分](../scenarios/string-split-to-rows/dameng.sql) | CONNECT BY+REGEXP_SUBSTR(Oracle 兼容) |
| [窗口分析](../scenarios/window-analytics/dameng.sql) | 完整窗口函数(Oracle 兼容) |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/dameng.sql) | VARRAY/嵌套表(Oracle 兼容) |
| [日期时间](../types/datetime/dameng.sql) | DATE 含时间(Oracle 兼容)，TIMESTAMP 精确 |
| [JSON](../types/json/dameng.sql) | JSON 类型+JSON_TABLE(标准实现) |
| [数值类型](../types/numeric/dameng.sql) | NUMBER/INTEGER/DECIMAL(Oracle 兼容) |
| [字符串类型](../types/string/dameng.sql) | VARCHAR/VARCHAR2/CLOB(Oracle 兼容)，UTF-8 |
