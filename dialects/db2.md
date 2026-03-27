# IBM Db2

**分类**: 传统关系型数据库（IBM）
**文件数**: 51 个 SQL 文件
**总行数**: 4539 行

## 概述与定位

IBM Db2 是关系型数据库领域的奠基者之一，其前身 System R 是 SQL 语言的发源地。Db2 涵盖从大型机（z/OS）到分布式系统（LUW: Linux/Unix/Windows）的完整产品线，长期服务于银行、保险、航空等对数据一致性和可靠性要求极高的行业。在 SQL 标准化进程中，Db2 团队深度参与了 ANSI/ISO SQL 标准的制定，许多 SQL 特性（窗口函数、CTE、MERGE）都在 Db2 中率先实现或验证。

## 历史与演进

- **1983 年**：Db2 for MVS（大型机版本）发布，成为第一款商用 SQL 关系数据库之一。
- **1993 年**：Db2 for Common Servers（后更名 Db2 LUW）发布，覆盖 Unix/Windows 平台。
- **2001 年**：Db2 8 引入 MQT（Materialized Query Table）与自动统计信息维护。
- **2006 年**：Db2 9 成为首个同时支持关系型和 XML 原生存储的数据库（pureXML）。
- **2009 年**：Db2 9.7 引入 Oracle 兼容模式，支持 PL/SQL 语法与 Oracle 数据类型映射。
- **2016 年**：Db2 11.1 引入 BLU Acceleration（内存列存加速）、自适应压缩。
- **2019 年**：Db2 11.5 引入 AI 驱动的自优化功能和 Db2 on Cloud 托管服务。
- **2023-2025 年**：持续增强 JSON 支持、REST API 接口、与 watsonx.data 的 Lakehouse 集成。

## 核心设计思路

1. **SQL 标准旗手**：Db2 是 SQL 标准最严格的追随者之一，FETCH FIRST、LATERAL、MERGE、窗口函数等均率先实现标准语法。
2. **平台分层**：z/OS 版本面向大型机事务处理，LUW 版本面向分布式系统，二者 SQL 方言高度一致但底层架构不同。
3. **自动化管理**：自动存储管理（Automatic Storage）、自动内存调优（STMM）、自动统计收集，减少 DBA 手动干预。
4. **混合负载**：BLU Acceleration 使同一张表同时支持行存 OLTP 查询和列存分析查询，无需数据搬运。

## 独特特色

| 特性 | 说明 |
|---|---|
| **FETCH FIRST n ROWS ONLY** | Db2 最早实现的标准分页语法，后被 SQL:2008 标准采纳，现已被 PostgreSQL/Oracle 等广泛支持。 |
| **Labeled Durations** | `CURRENT_DATE + 3 MONTHS` 这样的日期运算语法，比大多数数据库的 INTERVAL 写法更直观。 |
| **MQT（物化查询表）** | 物化视图的 Db2 实现，支持 REFRESH DEFERRED/IMMEDIATE，可被优化器自动路由。 |
| **FINAL TABLE** | `SELECT * FROM FINAL TABLE (INSERT INTO t VALUES (...))` 在 DML 中嵌套取回受影响行，无需 RETURNING。 |
| **pureXML** | 原生 XML 存储引擎，XML 数据以树形结构存储而非 CLOB，支持 XQuery 和 SQL/XML 混合查询。 |
| **Oracle 兼容模式** | 通过 `DB2_COMPATIBILITY_VECTOR` 参数启用，支持 PL/SQL 语法、Oracle 数据类型、NVL/DECODE 等函数。 |
| **时态查询** | 支持 BUSINESS_TIME 和 SYSTEM_TIME 双时态表，可进行 `FOR SYSTEM_TIME AS OF` 时间旅行查询。 |

## 已知不足

- **学习曲线陡峭**：z/OS 与 LUW 版本的差异、复杂的权限模型与 bufferpool 管理对新手不友好。
- **社区活跃度低**：相比 PostgreSQL/MySQL，Db2 的开源社区和第三方工具生态明显薄弱。
- **许可成本高**：企业版许可费用高昂，社区版（Community Edition）有数据容量和核心数限制。
- **JSON 支持起步晚**：原生 JSON 数据类型和 JSON_TABLE 的引入显著落后于 PostgreSQL 和 MySQL。
- **云原生步伐偏慢**：虽有 Db2 on Cloud，但在 Kubernetes 原生部署和 Serverless 模式上落后于云数仓竞品。

## 对引擎开发者的参考价值

- **FINAL TABLE 设计**：将 DML 语句当作表表达式使用的概念（"数据变更即查询"）比 RETURNING 更通用，对引擎的执行计划树设计有深刻启发。
- **SQL 标准实现参考**：Db2 的窗口函数、MERGE、LATERAL 实现几乎严格对齐 ISO SQL 标准文本，可作为标准合规性测试的基准。
- **Labeled Durations 解析**：将时间单位关键字（DAYS/MONTHS/YEARS）作为后缀运算符处理的解析器设计，比 INTERVAL 字面量更灵活。
- **BLU 列存加速**：在同一表上同时维护行存和列存副本的混合存储引擎设计，对 HTAP 引擎有重要参考。
- **pureXML 存储模型**：将层次化数据以原生树结构存储（而非序列化为文本）的做法，对 JSON 原生存储引擎的设计有借鉴意义。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [db2.sql](../ddl/create-table/db2.sql) |
| 改表 | [db2.sql](../ddl/alter-table/db2.sql) |
| 索引 | [db2.sql](../ddl/indexes/db2.sql) |
| 约束 | [db2.sql](../ddl/constraints/db2.sql) |
| 视图 | [db2.sql](../ddl/views/db2.sql) |
| 序列与自增 | [db2.sql](../ddl/sequences/db2.sql) |
| 数据库/Schema/用户 | [db2.sql](../ddl/users-databases/db2.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [db2.sql](../advanced/dynamic-sql/db2.sql) |
| 错误处理 | [db2.sql](../advanced/error-handling/db2.sql) |
| 执行计划 | [db2.sql](../advanced/explain/db2.sql) |
| 锁机制 | [db2.sql](../advanced/locking/db2.sql) |
| 分区 | [db2.sql](../advanced/partitioning/db2.sql) |
| 权限 | [db2.sql](../advanced/permissions/db2.sql) |
| 存储过程 | [db2.sql](../advanced/stored-procedures/db2.sql) |
| 临时表 | [db2.sql](../advanced/temp-tables/db2.sql) |
| 事务 | [db2.sql](../advanced/transactions/db2.sql) |
| 触发器 | [db2.sql](../advanced/triggers/db2.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [db2.sql](../dml/delete/db2.sql) |
| 插入 | [db2.sql](../dml/insert/db2.sql) |
| 更新 | [db2.sql](../dml/update/db2.sql) |
| Upsert | [db2.sql](../dml/upsert/db2.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [db2.sql](../functions/aggregate/db2.sql) |
| 条件函数 | [db2.sql](../functions/conditional/db2.sql) |
| 日期函数 | [db2.sql](../functions/date-functions/db2.sql) |
| 数学函数 | [db2.sql](../functions/math-functions/db2.sql) |
| 字符串函数 | [db2.sql](../functions/string-functions/db2.sql) |
| 类型转换 | [db2.sql](../functions/type-conversion/db2.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [db2.sql](../query/cte/db2.sql) |
| 全文搜索 | [db2.sql](../query/full-text-search/db2.sql) |
| 连接查询 | [db2.sql](../query/joins/db2.sql) |
| 分页 | [db2.sql](../query/pagination/db2.sql) |
| 行列转换 | [db2.sql](../query/pivot-unpivot/db2.sql) |
| 集合操作 | [db2.sql](../query/set-operations/db2.sql) |
| 子查询 | [db2.sql](../query/subquery/db2.sql) |
| 窗口函数 | [db2.sql](../query/window-functions/db2.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [db2.sql](../scenarios/date-series-fill/db2.sql) |
| 去重 | [db2.sql](../scenarios/deduplication/db2.sql) |
| 区间检测 | [db2.sql](../scenarios/gap-detection/db2.sql) |
| 层级查询 | [db2.sql](../scenarios/hierarchical-query/db2.sql) |
| JSON 展开 | [db2.sql](../scenarios/json-flatten/db2.sql) |
| 迁移速查 | [db2.sql](../scenarios/migration-cheatsheet/db2.sql) |
| TopN 查询 | [db2.sql](../scenarios/ranking-top-n/db2.sql) |
| 累计求和 | [db2.sql](../scenarios/running-total/db2.sql) |
| 缓慢变化维 | [db2.sql](../scenarios/slowly-changing-dim/db2.sql) |
| 字符串拆分 | [db2.sql](../scenarios/string-split-to-rows/db2.sql) |
| 窗口分析 | [db2.sql](../scenarios/window-analytics/db2.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [db2.sql](../types/array-map-struct/db2.sql) |
| 日期时间 | [db2.sql](../types/datetime/db2.sql) |
| JSON | [db2.sql](../types/json/db2.sql) |
| 数值类型 | [db2.sql](../types/numeric/db2.sql) |
| 字符串类型 | [db2.sql](../types/string/db2.sql) |
