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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/derby.sql) | Java 嵌入式(Apache)，纯 Java，ANSI SQL 子集 |
| [改表](../ddl/alter-table/derby.sql) | ALTER ADD/DROP COLUMN，无 MODIFY/CHANGE COLUMN |
| [索引](../ddl/indexes/derby.sql) | B-tree 索引，无其他索引类型 |
| [约束](../ddl/constraints/derby.sql) | PK/FK/CHECK/UNIQUE 标准支持 |
| [视图](../ddl/views/derby.sql) | 普通视图，无物化视图 |
| [序列与自增](../ddl/sequences/derby.sql) | IDENTITY+SEQUENCE(10.6+)，GENERATED ALWAYS/BY DEFAULT |
| [数据库/Schema/用户](../ddl/users-databases/derby.sql) | Schema=用户，内置身份验证，LDAP 集成 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/derby.sql) | 无动态 SQL，Java JDBC PreparedStatement |
| [错误处理](../advanced/error-handling/derby.sql) | 无过程式错误处理，SQL 异常由 Java 处理 |
| [执行计划](../advanced/explain/derby.sql) | EXPLAIN 通过 derby.language.logStatementText 属性 |
| [锁机制](../advanced/locking/derby.sql) | 行级锁+表级锁，锁升级，死锁检测 |
| [分区](../advanced/partitioning/derby.sql) | 无分区支持 |
| [权限](../advanced/permissions/derby.sql) | GRANT/REVOKE 标准，内置身份验证 |
| [存储过程](../advanced/stored-procedures/derby.sql) | Java 存储过程(EXTERNAL NAME)，无 SQL 过程语言 |
| [临时表](../advanced/temp-tables/derby.sql) | DECLARE GLOBAL TEMPORARY TABLE 会话级 |
| [事务](../advanced/transactions/derby.sql) | ACID 完整，READ COMMITTED 默认，Savepoint |
| [触发器](../advanced/triggers/derby.sql) | BEFORE/AFTER 行/语句级触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/derby.sql) | DELETE 标准，TRUNCATE(10.11+) |
| [插入](../dml/insert/derby.sql) | INSERT 标准，批量 INSERT |
| [更新](../dml/update/derby.sql) | UPDATE 标准 |
| [Upsert](../dml/upsert/derby.sql) | MERGE 标准(10.11+)，之前需 INSERT+UPDATE |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/derby.sql) | 基础聚合(COUNT/SUM/AVG/MIN/MAX)，无 STRING_AGG/LISTAGG |
| [条件函数](../functions/conditional/derby.sql) | CASE/COALESCE/NULLIF 标准 |
| [日期函数](../functions/date-functions/derby.sql) | YEAR/MONTH/DAY 提取函数，TIMESTAMPADD/TIMESTAMPDIFF |
| [数学函数](../functions/math-functions/derby.sql) | 基础数学函数(ABS/MOD/SQRT 等) |
| [字符串函数](../functions/string-functions/derby.sql) | || 拼接，SUBSTR/LENGTH/TRIM 标准 |
| [类型转换](../functions/type-conversion/derby.sql) | CAST 标准，无 TRY_CAST |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/derby.sql) | 不支持 CTE(最大局限之一) |
| [全文搜索](../query/full-text-search/derby.sql) | 无全文搜索 |
| [连接查询](../query/joins/derby.sql) | INNER/LEFT/RIGHT/FULL JOIN 标准，无 LATERAL |
| [分页](../query/pagination/derby.sql) | FETCH FIRST N ROWS ONLY，无 LIMIT 语法，OFFSET(10.5+) |
| [行列转换](../query/pivot-unpivot/derby.sql) | 无原生 PIVOT |
| [集合操作](../query/set-operations/derby.sql) | UNION/INTERSECT/EXCEPT 完整 |
| [子查询](../query/subquery/derby.sql) | 关联子查询+IN/EXISTS 标准 |
| [窗口函数](../query/window-functions/derby.sql) | ROW_NUMBER(10.4+)，窗口函数支持有限 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/derby.sql) | 无 generate_series，无 CTE，需辅助表 |
| [去重](../scenarios/deduplication/derby.sql) | ROW_NUMBER(10.4+)+子查询去重 |
| [区间检测](../scenarios/gap-detection/derby.sql) | 自连接检测(无窗口函数完整支持) |
| [层级查询](../scenarios/hierarchical-query/derby.sql) | 无递归 CTE(最大限制) |
| [JSON 展开](../scenarios/json-flatten/derby.sql) | 无 JSON 支持(功能缺失) |
| [迁移速查](../scenarios/migration-cheatsheet/derby.sql) | Java 嵌入式，功能较少，无 CTE/JSON 是主要限制 |
| [TopN 查询](../scenarios/ranking-top-n/derby.sql) | ROW_NUMBER(10.4+)+FETCH FIRST |
| [累计求和](../scenarios/running-total/derby.sql) | 有限窗口函数支持 |
| [缓慢变化维](../scenarios/slowly-changing-dim/derby.sql) | MERGE(10.11+) |
| [字符串拆分](../scenarios/string-split-to-rows/derby.sql) | 无拆分函数，需 Java UDF |
| [窗口分析](../scenarios/window-analytics/derby.sql) | 窗口函数支持有限(ROW_NUMBER/RANK 等基本函数) |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/derby.sql) | 无 ARRAY/STRUCT/MAP 类型 |
| [日期时间](../types/datetime/derby.sql) | DATE/TIME/TIMESTAMP 标准，无 INTERVAL |
| [JSON](../types/json/derby.sql) | 无 JSON 支持 |
| [数值类型](../types/numeric/derby.sql) | SMALLINT/INTEGER/BIGINT/DECIMAL/FLOAT/DOUBLE 标准 |
| [字符串类型](../types/string/derby.sql) | VARCHAR/CHAR/CLOB 标准，UTF-8 |
