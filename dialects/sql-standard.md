# SQL 标准

**分类**: ISO/IEC 9075 SQL 标准
**文件数**: 51 个 SQL 文件
**总行数**: 4736 行

## 概述与定位

SQL 标准（ISO/IEC 9075）是由国际标准化组织（ISO）和国际电工委员会（IEC）联合发布的关系型数据库查询语言规范。它定义了 SQL 语言的语法、语义和数据模型，是所有关系型数据库实现的共同参考基准。SQL 标准不是一个数据库产品，而是一份规范性文档——各数据库厂商在此基础上实现自己的 SQL 方言，同时添加各自的扩展。理解 SQL 标准对于跨数据库迁移和引擎开发至关重要。

## 历史与演进

- **SQL-86 (SQL-1)**：首个 SQL 标准，定义了基本的 SELECT、INSERT、UPDATE、DELETE 和表定义语法。
- **SQL-89**：小幅修订，增强完整性约束（主键、外键、CHECK）。
- **SQL-92 (SQL2)**：重大扩展——引入 JOIN 语法（INNER/LEFT/RIGHT/FULL）、CASE 表达式、CAST 类型转换、子查询增强、UNION/INTERSECT/EXCEPT 和 LIKE 通配符。定义了三个合规级别（Entry/Intermediate/Full）。
- **SQL:1999 (SQL3)**：引入递归 CTE（WITH RECURSIVE）、触发器（TRIGGER）、存储过程（SQL/PSM）、用户自定义类型（UDT）、BOOLEAN 类型、正则表达式（SIMILAR TO）和 OLAP 函数。
- **SQL:2003**：引入窗口函数（OVER/PARTITION BY/ROW_NUMBER 等）、MERGE 语句、SEQUENCE 生成器、XML 数据类型（SQL/XML）和自增列（GENERATED ALWAYS AS IDENTITY）。
- **SQL:2006**：增强 SQL/XML，引入 XMLQUERY 和 XMLTABLE。
- **SQL:2008**：引入 TRUNCATE TABLE、FETCH FIRST（标准分页）、增强 MERGE 和 INSTEAD OF 触发器。
- **SQL:2011**：引入时态数据库支持（PERIOD、SYSTEM_TIME、FOR SYSTEM_TIME AS OF）和管道函数。
- **SQL:2016**：引入 JSON 支持（JSON_VALUE/JSON_QUERY/JSON_TABLE/IS JSON）、行模式匹配（MATCH_RECOGNIZE）和多态表函数（PTF）。
- **SQL:2023**：引入 ANY VALUE 聚合、图查询（SQL/PGQ with GRAPH_TABLE）、JSON 增强（JSON_SERIALIZE 等）、GREATEST/LEAST 函数和数据类型格式化。

## 核心设计思路

SQL 标准基于**关系模型**（E.F. Codd 1970 年提出）设计，核心思想是用声明式语言描述"要什么数据"而非"如何获取数据"。标准分为多个部分（Part）：Part 1 是框架概述，Part 2（Foundation）是核心 SQL 语法，Part 4 是 SQL/PSM（存储过程），Part 9 是 SQL/MED（外部数据管理），Part 10 是 SQL/OLB（对象语言绑定），Part 14 是 SQL/XML，Part 15 是多维数组，Part 16 是 SQL/PGQ（属性图查询）。标准通过"Feature ID"（如 F302 = INTERSECT、T611 = Elementary OLAP operations）精确标识每个特性。

## 独特特色

- **窗口函数框架**（SQL:2003）：`ROW_NUMBER() / RANK() / DENSE_RANK() / NTILE() OVER (PARTITION BY ... ORDER BY ... ROWS/RANGE BETWEEN ...)`——这一完整框架被几乎所有现代数据库采纳。
- **CTE 与递归**（SQL:1999）：`WITH RECURSIVE cte AS (...)` 为层级查询提供了标准化方案。
- **MERGE 语句**（SQL:2003）：`MERGE INTO ... USING ... WHEN MATCHED/NOT MATCHED` 标准化的 Upsert 操作。
- **时态表**（SQL:2011）：`FOR SYSTEM_TIME AS OF timestamp` 查询历史数据的标准语法。
- **JSON 支持**（SQL:2016）：`JSON_VALUE()`, `JSON_QUERY()`, `JSON_TABLE()` 标准化 JSON 处理。
- **FETCH FIRST 分页**（SQL:2008）：`OFFSET n ROWS FETCH FIRST m ROWS ONLY` 替代各方言的 LIMIT/TOP 语法。
- **图查询 SQL/PGQ**（SQL:2023）：`GRAPH_TABLE` 和路径模式匹配，将图查询纳入 SQL 标准。

## 已知不足

- 标准文档不免费公开（ISO 标准需付费购买），限制了开发者的直接参考。
- 各数据库对标准的实现程度差异巨大——没有任何数据库完整实现了 Full SQL 标准。
- 标准的演进速度远慢于行业需求——许多重要特性（如 LIMIT、UPSERT、JSON）在标准化前已被各方言广泛实现。
- 部分标准特性（如 SIMILAR TO、时态表、多态表函数）采纳率极低，实际工程参考价值有限。
- 标准未涵盖许多实际重要的领域：分布式事务、分区表、全文搜索、向量类型等。
- SQL/PGQ（图查询）的采纳仍处于极早期，主流数据库尚未完整实现。

## 对引擎开发者的参考价值

SQL 标准是数据库引擎开发的首要参考文档。窗口函数的框架规范（ROWS vs RANGE vs GROUPS、EXCLUDE 子句、frame 边界规则）为实现提供了精确的语义定义。SQL:2011 的时态表规范（SYSTEM_TIME 和 APPLICATION_TIME 的双时态模型）为时态数据库引擎设计提供了理论框架。Feature ID 体系为引擎的合规性测试提供了清晰的检查清单。理解标准与各方言的差异也是构建跨数据库兼容层（如 ORM、SQL 转换器）的基础。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [sql-standard.sql](../ddl/create-table/sql-standard.sql) |
| 改表 | [sql-standard.sql](../ddl/alter-table/sql-standard.sql) |
| 索引 | [sql-standard.sql](../ddl/indexes/sql-standard.sql) |
| 约束 | [sql-standard.sql](../ddl/constraints/sql-standard.sql) |
| 视图 | [sql-standard.sql](../ddl/views/sql-standard.sql) |
| 序列与自增 | [sql-standard.sql](../ddl/sequences/sql-standard.sql) |
| 数据库/Schema/用户 | [sql-standard.sql](../ddl/users-databases/sql-standard.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [sql-standard.sql](../advanced/dynamic-sql/sql-standard.sql) |
| 错误处理 | [sql-standard.sql](../advanced/error-handling/sql-standard.sql) |
| 执行计划 | [sql-standard.sql](../advanced/explain/sql-standard.sql) |
| 锁机制 | [sql-standard.sql](../advanced/locking/sql-standard.sql) |
| 分区 | [sql-standard.sql](../advanced/partitioning/sql-standard.sql) |
| 权限 | [sql-standard.sql](../advanced/permissions/sql-standard.sql) |
| 存储过程 | [sql-standard.sql](../advanced/stored-procedures/sql-standard.sql) |
| 临时表 | [sql-standard.sql](../advanced/temp-tables/sql-standard.sql) |
| 事务 | [sql-standard.sql](../advanced/transactions/sql-standard.sql) |
| 触发器 | [sql-standard.sql](../advanced/triggers/sql-standard.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [sql-standard.sql](../dml/delete/sql-standard.sql) |
| 插入 | [sql-standard.sql](../dml/insert/sql-standard.sql) |
| 更新 | [sql-standard.sql](../dml/update/sql-standard.sql) |
| Upsert | [sql-standard.sql](../dml/upsert/sql-standard.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [sql-standard.sql](../functions/aggregate/sql-standard.sql) |
| 条件函数 | [sql-standard.sql](../functions/conditional/sql-standard.sql) |
| 日期函数 | [sql-standard.sql](../functions/date-functions/sql-standard.sql) |
| 数学函数 | [sql-standard.sql](../functions/math-functions/sql-standard.sql) |
| 字符串函数 | [sql-standard.sql](../functions/string-functions/sql-standard.sql) |
| 类型转换 | [sql-standard.sql](../functions/type-conversion/sql-standard.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [sql-standard.sql](../query/cte/sql-standard.sql) |
| 全文搜索 | [sql-standard.sql](../query/full-text-search/sql-standard.sql) |
| 连接查询 | [sql-standard.sql](../query/joins/sql-standard.sql) |
| 分页 | [sql-standard.sql](../query/pagination/sql-standard.sql) |
| 行列转换 | [sql-standard.sql](../query/pivot-unpivot/sql-standard.sql) |
| 集合操作 | [sql-standard.sql](../query/set-operations/sql-standard.sql) |
| 子查询 | [sql-standard.sql](../query/subquery/sql-standard.sql) |
| 窗口函数 | [sql-standard.sql](../query/window-functions/sql-standard.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [sql-standard.sql](../scenarios/date-series-fill/sql-standard.sql) |
| 去重 | [sql-standard.sql](../scenarios/deduplication/sql-standard.sql) |
| 区间检测 | [sql-standard.sql](../scenarios/gap-detection/sql-standard.sql) |
| 层级查询 | [sql-standard.sql](../scenarios/hierarchical-query/sql-standard.sql) |
| JSON 展开 | [sql-standard.sql](../scenarios/json-flatten/sql-standard.sql) |
| 迁移速查 | [sql-standard.sql](../scenarios/migration-cheatsheet/sql-standard.sql) |
| TopN 查询 | [sql-standard.sql](../scenarios/ranking-top-n/sql-standard.sql) |
| 累计求和 | [sql-standard.sql](../scenarios/running-total/sql-standard.sql) |
| 缓慢变化维 | [sql-standard.sql](../scenarios/slowly-changing-dim/sql-standard.sql) |
| 字符串拆分 | [sql-standard.sql](../scenarios/string-split-to-rows/sql-standard.sql) |
| 窗口分析 | [sql-standard.sql](../scenarios/window-analytics/sql-standard.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [sql-standard.sql](../types/array-map-struct/sql-standard.sql) |
| 日期时间 | [sql-standard.sql](../types/datetime/sql-standard.sql) |
| JSON | [sql-standard.sql](../types/json/sql-standard.sql) |
| 数值类型 | [sql-standard.sql](../types/numeric/sql-standard.sql) |
| 字符串类型 | [sql-standard.sql](../types/string/sql-standard.sql) |
