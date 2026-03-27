# Teradata

**分类**: 老牌 MPP 数仓
**文件数**: 51 个 SQL 文件
**总行数**: 4474 行

## 概述与定位

Teradata 是数据仓库领域的先驱和老牌领导者，自 1979 年以来专注于大规模并行处理（MPP）数据仓库。其核心理念是"一切靠 SQL"——通过强大的优化器和数据分布策略在 TB/PB 级数据上实现高性能分析查询。Teradata 在全球大型企业（银行、电信、零售、航空）中拥有深厚的客户基础，许多 SQL 分析特性（如 QUALIFY 子句）源自 Teradata 的首创。

## 历史与演进

- **1979 年**：Teradata Corporation 成立，是最早的 MPP 关系数据库公司之一。
- **1984 年**：Teradata DBC/1012 发布，是第一款商用并行数据库系统。
- **1999 年**：Teradata V2R3 引入 QUALIFY 子句，比 SQL 标准的类似功能早了十余年。
- **2007 年**：从 NCR 独立上市，引入 Teradata Active Data Warehousing 概念。
- **2010 年**：引入列分区（Column Partitioning）、时态表（Temporal Tables）与 PERIOD 数据类型。
- **2016 年**：Teradata 16.x 引入 QueryGrid（跨平台联邦查询）、JSON 数据类型。
- **2019 年**：Vantage 品牌发布，统一数据仓库、数据湖和分析功能在一个平台上。
- **2023-2025 年**：VantageCloud Lake（云原生对象存储架构）、ClearScape Analytics（内置 AI/ML 函数）、增强开放格式支持。

## 核心设计思路

1. **PRIMARY INDEX 分布**：每张表必须有 Primary Index（PI），数据通过 PI 的哈希值均匀分布到 AMP（Access Module Processor）节点上，PI 的选择是 Teradata 调优的核心。
2. **Shared-Nothing MPP**：每个 AMP 拥有独立的 CPU、内存和磁盘，完全不共享，通过 BYNET 高速互联网络交换数据。
3. **优化器驱动**：Teradata 优化器以其对复杂查询（多表 JOIN、嵌套子查询、窗口函数）的高质量计划生成著称。
4. **工作负载管理（TASM）**：Teradata Active System Management 提供细粒度的工作负载分类、优先级和资源分配。

## 独特特色

| 特性 | 说明 |
|---|---|
| **PRIMARY INDEX** | `CREATE TABLE t (...) PRIMARY INDEX (col)` 控制数据在 AMP 上的哈希分布，是性能调优的第一要素。 |
| **QUALIFY（首创）** | `QUALIFY ROW_NUMBER() OVER(...) = 1` 直接过滤窗口函数结果，无需嵌套子查询——Teradata 最早实现此语法。 |
| **COLLECT STATISTICS** | 收集列和索引的详细统计信息，Teradata 优化器高度依赖统计信息来选择最优执行计划。 |
| **PERIOD 类型** | 原生的时间区间数据类型 `PERIOD(DATE, DATE)` 和 `PERIOD(TIMESTAMP, TIMESTAMP)`，支持区间交集、包含等操作。 |
| **时态表** | 支持 VALIDTIME（业务时间）和 TRANSACTIONTIME（系统时间）双时态表，原生支持 `AS OF`、`BETWEEN...AND` 时态查询。 |
| **NORMALIZE** | `NORMALIZE` 语句可自动合并重叠或相邻的 PERIOD 区间，是 Teradata 独有的区间操作语法。 |
| **QueryGrid** | 跨平台联邦查询框架，可在 Teradata SQL 中直接查询 Hadoop/Spark/Oracle/Azure 等外部数据源。 |

## 已知不足

- **许可成本极高**：Teradata 是市场上最昂贵的数仓解决方案之一，按 TCore（Teradata Core）或 TB 计费。
- **供应商锁定严重**：PI 分布模型、QUALIFY、PERIOD 等特有语法使迁移到其他平台的成本很高。
- **云原生步伐偏慢**：虽然推出了 VantageCloud，但在弹性扩缩容和 Serverless 体验上落后于 Snowflake/Databricks。
- **学习曲线陡峭**：PI 选择、JOIN 策略（Product Join、Merge Join、Hash Join）、空间管理对初学者要求较高。
- **社区和生态薄弱**：闭源产品，技术资料主要来自 Teradata 官方，中文社区和第三方工具生态明显不足。
- **JSON/半结构化支持较晚**：原生 JSON 类型和 JSON 函数的引入落后于竞品。

## 对引擎开发者的参考价值

- **QUALIFY 子句设计**：将窗口函数结果过滤提升为一等子句（与 WHERE/HAVING 平级），消除了嵌套子查询的需要，对 SQL 方言设计有重要启发。
- **PRIMARY INDEX 哈希分布**：将数据分布策略作为 DDL 的核心部分（而非可选属性），展示了数据放置对查询性能的决定性影响。
- **PERIOD 类型与 NORMALIZE**：原生的时间区间类型和区间合并操作，对时态数据建模和时序数据库的类型系统有直接参考。
- **COLLECT STATISTICS 模型**：精细化的统计信息收集（支持列组合、采样统计、直方图）对基于成本的优化器的统计子系统设计有参考。
- **TASM 工作负载管理**：基于规则的查询分类 + 优先级队列 + 资源限制的多维度工作负载管理，对多租户引擎的调度设计有参考价值。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [teradata.sql](../ddl/create-table/teradata.sql) |
| 改表 | [teradata.sql](../ddl/alter-table/teradata.sql) |
| 索引 | [teradata.sql](../ddl/indexes/teradata.sql) |
| 约束 | [teradata.sql](../ddl/constraints/teradata.sql) |
| 视图 | [teradata.sql](../ddl/views/teradata.sql) |
| 序列与自增 | [teradata.sql](../ddl/sequences/teradata.sql) |
| 数据库/Schema/用户 | [teradata.sql](../ddl/users-databases/teradata.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [teradata.sql](../advanced/dynamic-sql/teradata.sql) |
| 错误处理 | [teradata.sql](../advanced/error-handling/teradata.sql) |
| 执行计划 | [teradata.sql](../advanced/explain/teradata.sql) |
| 锁机制 | [teradata.sql](../advanced/locking/teradata.sql) |
| 分区 | [teradata.sql](../advanced/partitioning/teradata.sql) |
| 权限 | [teradata.sql](../advanced/permissions/teradata.sql) |
| 存储过程 | [teradata.sql](../advanced/stored-procedures/teradata.sql) |
| 临时表 | [teradata.sql](../advanced/temp-tables/teradata.sql) |
| 事务 | [teradata.sql](../advanced/transactions/teradata.sql) |
| 触发器 | [teradata.sql](../advanced/triggers/teradata.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [teradata.sql](../dml/delete/teradata.sql) |
| 插入 | [teradata.sql](../dml/insert/teradata.sql) |
| 更新 | [teradata.sql](../dml/update/teradata.sql) |
| Upsert | [teradata.sql](../dml/upsert/teradata.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [teradata.sql](../functions/aggregate/teradata.sql) |
| 条件函数 | [teradata.sql](../functions/conditional/teradata.sql) |
| 日期函数 | [teradata.sql](../functions/date-functions/teradata.sql) |
| 数学函数 | [teradata.sql](../functions/math-functions/teradata.sql) |
| 字符串函数 | [teradata.sql](../functions/string-functions/teradata.sql) |
| 类型转换 | [teradata.sql](../functions/type-conversion/teradata.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [teradata.sql](../query/cte/teradata.sql) |
| 全文搜索 | [teradata.sql](../query/full-text-search/teradata.sql) |
| 连接查询 | [teradata.sql](../query/joins/teradata.sql) |
| 分页 | [teradata.sql](../query/pagination/teradata.sql) |
| 行列转换 | [teradata.sql](../query/pivot-unpivot/teradata.sql) |
| 集合操作 | [teradata.sql](../query/set-operations/teradata.sql) |
| 子查询 | [teradata.sql](../query/subquery/teradata.sql) |
| 窗口函数 | [teradata.sql](../query/window-functions/teradata.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [teradata.sql](../scenarios/date-series-fill/teradata.sql) |
| 去重 | [teradata.sql](../scenarios/deduplication/teradata.sql) |
| 区间检测 | [teradata.sql](../scenarios/gap-detection/teradata.sql) |
| 层级查询 | [teradata.sql](../scenarios/hierarchical-query/teradata.sql) |
| JSON 展开 | [teradata.sql](../scenarios/json-flatten/teradata.sql) |
| 迁移速查 | [teradata.sql](../scenarios/migration-cheatsheet/teradata.sql) |
| TopN 查询 | [teradata.sql](../scenarios/ranking-top-n/teradata.sql) |
| 累计求和 | [teradata.sql](../scenarios/running-total/teradata.sql) |
| 缓慢变化维 | [teradata.sql](../scenarios/slowly-changing-dim/teradata.sql) |
| 字符串拆分 | [teradata.sql](../scenarios/string-split-to-rows/teradata.sql) |
| 窗口分析 | [teradata.sql](../scenarios/window-analytics/teradata.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [teradata.sql](../types/array-map-struct/teradata.sql) |
| 日期时间 | [teradata.sql](../types/datetime/teradata.sql) |
| JSON | [teradata.sql](../types/json/teradata.sql) |
| 数值类型 | [teradata.sql](../types/numeric/teradata.sql) |
| 字符串类型 | [teradata.sql](../types/string/teradata.sql) |
