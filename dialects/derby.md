# Apache Derby

**分类**: Java 嵌入式数据库（Apache）
**文件数**: 51 个 SQL 文件
**总行数**: 4021 行

## 概述与定位

Apache Derby 是一个纯 Java 实现的开源关系型数据库，是 Apache 软件基金会的顶级项目。Derby 的设计目标是提供零管理、零配置的嵌入式数据库体验——只需将一个 JAR 文件加入 Java 应用的 classpath 即可使用。它同时支持嵌入式模式和网络服务器模式。Derby 的另一个身份是 Java DB——曾随 JDK 6-8 捆绑发布，使其成为 Java 开发者最容易获取的数据库。

## 历史与演进

- **1996 年**：Cloudscape 公司开发 JBMS 数据库（Derby 的前身）。
- **1999 年**：Informix 收购 Cloudscape。
- **2001 年**：IBM 收购 Informix，将 Cloudscape 纳入 IBM 产品线。
- **2004 年**：IBM 将 Cloudscape 代码捐赠给 Apache 基金会，命名为 Derby。
- **2006 年**：Sun 将 Derby 以"Java DB"身份捆绑在 JDK 6 中。
- **2011 年**：10.8 版本引入 BOOLEAN 类型和增强的 SQL 标准支持。
- **2019 年**：10.15 引入 SEQUENCE 和 OFFSET/FETCH 分页。
- **2022-2025 年**：10.16/10.17 持续维护，保持与新 JDK 版本的兼容性。

## 核心设计思路

Derby 的核心设计哲学是**简单和标准**。它严格遵循 SQL 标准和 JDBC 规范，不追求扩展性而追求正确性。存储引擎基于传统的 B-Tree 索引和堆文件（Heap File）组织，使用 WAL（Write-Ahead Logging）保证事务持久性。并发控制支持行级锁和表级锁。Derby 可通过**Java 存储过程**扩展——用户可以用 Java 方法实现存储过程和函数，通过 `CALL` 语句调用。

## 独特特色

- **MERGE 语句**（10.11+）：支持标准 SQL MERGE（UPSERT），`MERGE INTO target USING source ON condition WHEN MATCHED/NOT MATCHED`。
- **Java 存储过程**：`CREATE PROCEDURE procName ... LANGUAGE JAVA PARAMETER STYLE JAVA EXTERNAL NAME 'pkg.Class.method'` 用 Java 类实现存储过程。
- **SYSCS_UTIL 系统工具**：`CALL SYSCS_UTIL.SYSCS_SET_DATABASE_PROPERTY(...)` 等系统过程管理数据库属性。
- **零配置嵌入**：`jdbc:derby:mydb;create=true` 自动创建并连接数据库，无需安装或配置。
- **内置网络服务器**：可选启动 Derby Network Server 提供远程 JDBC 访问。
- **GENERATED ALWAYS AS IDENTITY**：标准 SQL 自增列语法。
- **XML 数据类型**：内置 XML 类型和 XMLPARSE/XMLSERIALIZE/XMLEXISTS 函数。

## 已知不足

- SQL 功能集相比现代数据库较为保守——窗口函数支持有限，不支持 CTE 的递归形式。
- 不支持 JSON 数据类型和相关函数。
- 性能不适合高并发或大数据量的生产场景。
- 社区活跃度低，版本更新缓慢，新特性引入非常保守。
- 不支持 FULL OUTER JOIN（仅在较新版本中部分支持）。
- 不支持 CREATE TABLE AS SELECT（CTAS）。
- 从 JDK 9 开始不再随 JDK 捆绑，获取便利性下降。

## 对引擎开发者的参考价值

Derby 的代码库是学习传统 RDBMS 实现的良好教材——完整的 SQL 解析器（基于 JavaCC）、基于成本的查询优化器、B-Tree 存储引擎、WAL 日志管理和锁管理器都在一个纯 Java 代码库中清晰实现。Java 存储过程的集成方式展示了如何将宿主语言方法嵌入 SQL 引擎。SYSCS_UTIL 系统过程的设计为数据库管理接口提供了一种内省式的参考模式。Derby 对 SQL 标准的严格遵循也使其成为 SQL 标准合规性测试的良好参考。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [derby.sql](../ddl/create-table/derby.sql) |
| 改表 | [derby.sql](../ddl/alter-table/derby.sql) |
| 索引 | [derby.sql](../ddl/indexes/derby.sql) |
| 约束 | [derby.sql](../ddl/constraints/derby.sql) |
| 视图 | [derby.sql](../ddl/views/derby.sql) |
| 序列与自增 | [derby.sql](../ddl/sequences/derby.sql) |
| 数据库/Schema/用户 | [derby.sql](../ddl/users-databases/derby.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [derby.sql](../advanced/dynamic-sql/derby.sql) |
| 错误处理 | [derby.sql](../advanced/error-handling/derby.sql) |
| 执行计划 | [derby.sql](../advanced/explain/derby.sql) |
| 锁机制 | [derby.sql](../advanced/locking/derby.sql) |
| 分区 | [derby.sql](../advanced/partitioning/derby.sql) |
| 权限 | [derby.sql](../advanced/permissions/derby.sql) |
| 存储过程 | [derby.sql](../advanced/stored-procedures/derby.sql) |
| 临时表 | [derby.sql](../advanced/temp-tables/derby.sql) |
| 事务 | [derby.sql](../advanced/transactions/derby.sql) |
| 触发器 | [derby.sql](../advanced/triggers/derby.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [derby.sql](../dml/delete/derby.sql) |
| 插入 | [derby.sql](../dml/insert/derby.sql) |
| 更新 | [derby.sql](../dml/update/derby.sql) |
| Upsert | [derby.sql](../dml/upsert/derby.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [derby.sql](../functions/aggregate/derby.sql) |
| 条件函数 | [derby.sql](../functions/conditional/derby.sql) |
| 日期函数 | [derby.sql](../functions/date-functions/derby.sql) |
| 数学函数 | [derby.sql](../functions/math-functions/derby.sql) |
| 字符串函数 | [derby.sql](../functions/string-functions/derby.sql) |
| 类型转换 | [derby.sql](../functions/type-conversion/derby.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [derby.sql](../query/cte/derby.sql) |
| 全文搜索 | [derby.sql](../query/full-text-search/derby.sql) |
| 连接查询 | [derby.sql](../query/joins/derby.sql) |
| 分页 | [derby.sql](../query/pagination/derby.sql) |
| 行列转换 | [derby.sql](../query/pivot-unpivot/derby.sql) |
| 集合操作 | [derby.sql](../query/set-operations/derby.sql) |
| 子查询 | [derby.sql](../query/subquery/derby.sql) |
| 窗口函数 | [derby.sql](../query/window-functions/derby.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [derby.sql](../scenarios/date-series-fill/derby.sql) |
| 去重 | [derby.sql](../scenarios/deduplication/derby.sql) |
| 区间检测 | [derby.sql](../scenarios/gap-detection/derby.sql) |
| 层级查询 | [derby.sql](../scenarios/hierarchical-query/derby.sql) |
| JSON 展开 | [derby.sql](../scenarios/json-flatten/derby.sql) |
| 迁移速查 | [derby.sql](../scenarios/migration-cheatsheet/derby.sql) |
| TopN 查询 | [derby.sql](../scenarios/ranking-top-n/derby.sql) |
| 累计求和 | [derby.sql](../scenarios/running-total/derby.sql) |
| 缓慢变化维 | [derby.sql](../scenarios/slowly-changing-dim/derby.sql) |
| 字符串拆分 | [derby.sql](../scenarios/string-split-to-rows/derby.sql) |
| 窗口分析 | [derby.sql](../scenarios/window-analytics/derby.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [derby.sql](../types/array-map-struct/derby.sql) |
| 日期时间 | [derby.sql](../types/datetime/derby.sql) |
| JSON | [derby.sql](../types/json/derby.sql) |
| 数值类型 | [derby.sql](../types/numeric/derby.sql) |
| 字符串类型 | [derby.sql](../types/string/derby.sql) |
