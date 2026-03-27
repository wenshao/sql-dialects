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

| 模块 | 链接 |
|---|---|
| 建表 | [dameng.sql](../ddl/create-table/dameng.sql) |
| 改表 | [dameng.sql](../ddl/alter-table/dameng.sql) |
| 索引 | [dameng.sql](../ddl/indexes/dameng.sql) |
| 约束 | [dameng.sql](../ddl/constraints/dameng.sql) |
| 视图 | [dameng.sql](../ddl/views/dameng.sql) |
| 序列与自增 | [dameng.sql](../ddl/sequences/dameng.sql) |
| 数据库/Schema/用户 | [dameng.sql](../ddl/users-databases/dameng.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [dameng.sql](../advanced/dynamic-sql/dameng.sql) |
| 错误处理 | [dameng.sql](../advanced/error-handling/dameng.sql) |
| 执行计划 | [dameng.sql](../advanced/explain/dameng.sql) |
| 锁机制 | [dameng.sql](../advanced/locking/dameng.sql) |
| 分区 | [dameng.sql](../advanced/partitioning/dameng.sql) |
| 权限 | [dameng.sql](../advanced/permissions/dameng.sql) |
| 存储过程 | [dameng.sql](../advanced/stored-procedures/dameng.sql) |
| 临时表 | [dameng.sql](../advanced/temp-tables/dameng.sql) |
| 事务 | [dameng.sql](../advanced/transactions/dameng.sql) |
| 触发器 | [dameng.sql](../advanced/triggers/dameng.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [dameng.sql](../dml/delete/dameng.sql) |
| 插入 | [dameng.sql](../dml/insert/dameng.sql) |
| 更新 | [dameng.sql](../dml/update/dameng.sql) |
| Upsert | [dameng.sql](../dml/upsert/dameng.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [dameng.sql](../functions/aggregate/dameng.sql) |
| 条件函数 | [dameng.sql](../functions/conditional/dameng.sql) |
| 日期函数 | [dameng.sql](../functions/date-functions/dameng.sql) |
| 数学函数 | [dameng.sql](../functions/math-functions/dameng.sql) |
| 字符串函数 | [dameng.sql](../functions/string-functions/dameng.sql) |
| 类型转换 | [dameng.sql](../functions/type-conversion/dameng.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [dameng.sql](../query/cte/dameng.sql) |
| 全文搜索 | [dameng.sql](../query/full-text-search/dameng.sql) |
| 连接查询 | [dameng.sql](../query/joins/dameng.sql) |
| 分页 | [dameng.sql](../query/pagination/dameng.sql) |
| 行列转换 | [dameng.sql](../query/pivot-unpivot/dameng.sql) |
| 集合操作 | [dameng.sql](../query/set-operations/dameng.sql) |
| 子查询 | [dameng.sql](../query/subquery/dameng.sql) |
| 窗口函数 | [dameng.sql](../query/window-functions/dameng.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [dameng.sql](../scenarios/date-series-fill/dameng.sql) |
| 去重 | [dameng.sql](../scenarios/deduplication/dameng.sql) |
| 区间检测 | [dameng.sql](../scenarios/gap-detection/dameng.sql) |
| 层级查询 | [dameng.sql](../scenarios/hierarchical-query/dameng.sql) |
| JSON 展开 | [dameng.sql](../scenarios/json-flatten/dameng.sql) |
| 迁移速查 | [dameng.sql](../scenarios/migration-cheatsheet/dameng.sql) |
| TopN 查询 | [dameng.sql](../scenarios/ranking-top-n/dameng.sql) |
| 累计求和 | [dameng.sql](../scenarios/running-total/dameng.sql) |
| 缓慢变化维 | [dameng.sql](../scenarios/slowly-changing-dim/dameng.sql) |
| 字符串拆分 | [dameng.sql](../scenarios/string-split-to-rows/dameng.sql) |
| 窗口分析 | [dameng.sql](../scenarios/window-analytics/dameng.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [dameng.sql](../types/array-map-struct/dameng.sql) |
| 日期时间 | [dameng.sql](../types/datetime/dameng.sql) |
| JSON | [dameng.sql](../types/json/dameng.sql) |
| 数值类型 | [dameng.sql](../types/numeric/dameng.sql) |
| 字符串类型 | [dameng.sql](../types/string/dameng.sql) |
