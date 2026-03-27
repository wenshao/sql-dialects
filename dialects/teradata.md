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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/teradata.sql) | MPP 架构先驱，PRIMARY INDEX 决定数据分布(Hash)，SET/MULTISET 表 |
| [改表](../ddl/alter-table/teradata.sql) | ALTER 在线，PRIMARY INDEX 变更需重建表 |
| [索引](../ddl/indexes/teradata.sql) | PI(Primary Index) 决定分布，SI(Secondary Index)，Join Index |
| [约束](../ddl/constraints/teradata.sql) | PK/FK/UNIQUE/CHECK 完整，NOT NULL 默认(与其他 DB 相反) |
| [视图](../ddl/views/teradata.sql) | Join Index 物化连接视图(独有)，Hash Index |
| [序列与自增](../ddl/sequences/teradata.sql) | IDENTITY 自增列，无 SEQUENCE 对象 |
| [数据库/Schema/用户](../ddl/users-databases/teradata.sql) | Database=Schema=权限容器，Space 配额管理 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/teradata.sql) | CALL DBC.SYSEXECSQL 或应用层 BTEQ/TPT |
| [错误处理](../advanced/error-handling/teradata.sql) | HANDLER 声明，SIGNAL/RESIGNAL 标准 |
| [执行计划](../advanced/explain/teradata.sql) | EXPLAIN 文本(详尽英文描述)，Query Log 分析 |
| [锁机制](../advanced/locking/teradata.sql) | 行级哈希锁，LOCKING 子句显式指定(独有语法) |
| [分区](../advanced/partitioning/teradata.sql) | PPI(Partitioned Primary Index)，RANGE_N/CASE_N 函数分区 |
| [权限](../advanced/permissions/teradata.sql) | 数据库级权限继承，Profile 管理，Access Logging |
| [存储过程](../advanced/stored-procedures/teradata.sql) | SPL(Stored Procedure Language)，编译式过程 |
| [临时表](../advanced/temp-tables/teradata.sql) | VOLATILE(会话级)/GLOBAL TEMPORARY 表 |
| [事务](../advanced/transactions/teradata.sql) | ANSI/Teradata 两种事务模式，BT/ET 显式事务(Teradata 模式) |
| [触发器](../advanced/triggers/teradata.sql) | BEFORE/AFTER 行/语句级完整 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/teradata.sql) | DELETE/DEL 标准，FastPath DELETE 批量高效 |
| [插入](../dml/insert/teradata.sql) | INSERT/INS 标准，FastLoad/TPT 批量导入 |
| [更新](../dml/update/teradata.sql) | UPDATE/UPD 标准，MERGE 支持 |
| [Upsert](../dml/upsert/teradata.sql) | MERGE 标准实现+UPDATE...ELSE INSERT(独有语法) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/teradata.sql) | GROUPING SETS/CUBE/ROLLUP，QUALIFY 子句(首创) |
| [条件函数](../functions/conditional/teradata.sql) | CASE/NULLIF/COALESCE/NVL/ZEROIFNULL(独有) |
| [日期函数](../functions/date-functions/teradata.sql) | DATE 格式 YYYMMDD 整数存储(独有)，INTERVAL 类型 |
| [数学函数](../functions/math-functions/teradata.sql) | 完整数学函数 |
| [字符串函数](../functions/string-functions/teradata.sql) | || 拼接，REGEXP_REPLACE/SUBSTR 标准 |
| [类型转换](../functions/type-conversion/teradata.sql) | CAST 标准，FORMAT 格式化(独有关键字) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/teradata.sql) | WITH 标准+递归 CTE，QUALIFY 子句过滤(首创) |
| [全文搜索](../query/full-text-search/teradata.sql) | 无内置全文搜索 |
| [连接查询](../query/joins/teradata.sql) | Hash/Merge/Product JOIN，All-AMP 操作分析 |
| [分页](../query/pagination/teradata.sql) | QUALIFY ROW_NUMBER()+TOP(独有) 或 SAMPLE |
| [行列转换](../query/pivot-unpivot/teradata.sql) | 无原生 PIVOT，CASE+GROUP BY 模拟 |
| [集合操作](../query/set-operations/teradata.sql) | UNION/INTERSECT/EXCEPT/MINUS 完整 |
| [子查询](../query/subquery/teradata.sql) | 关联子查询优化好，Teradata 优化器是强项 |
| [窗口函数](../query/window-functions/teradata.sql) | 早期支持，QUALIFY 首创过滤行(后被 BigQuery/Snowflake 借鉴) |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/teradata.sql) | sys_calendar.calendar 系统日历表(独有) |
| [去重](../scenarios/deduplication/teradata.sql) | QUALIFY ROW_NUMBER()=1 首创写法 |
| [区间检测](../scenarios/gap-detection/teradata.sql) | 窗口函数+sys_calendar 日历表 |
| [层级查询](../scenarios/hierarchical-query/teradata.sql) | 递归 CTE 标准 |
| [JSON 展开](../scenarios/json-flatten/teradata.sql) | JSON_TABLE/JSON Shredding(16.20+)，JSON 存储类型 |
| [迁移速查](../scenarios/migration-cheatsheet/teradata.sql) | PI 数据分布+QUALIFY+日期整数存储是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/teradata.sql) | QUALIFY ROW_NUMBER() 首创，TOP N 支持 |
| [累计求和](../scenarios/running-total/teradata.sql) | SUM() OVER 标准，MPP 并行计算 |
| [缓慢变化维](../scenarios/slowly-changing-dim/teradata.sql) | MERGE+Temporal 表(Temporal Qualifier) |
| [字符串拆分](../scenarios/string-split-to-rows/teradata.sql) | STRTOK/REGEXP_SPLIT+CROSS JOIN 展开 |
| [窗口分析](../scenarios/window-analytics/teradata.sql) | 窗口函数完整+QUALIFY 首创，MPP 并行 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/teradata.sql) | PERIOD(时态区间) 类型独有，JSON/XML 半结构化 |
| [日期时间](../types/datetime/teradata.sql) | DATE 整数存储(YYYMMDD)，TIMESTAMP，PERIOD 时态类型 |
| [JSON](../types/json/teradata.sql) | JSON/JSON_TABLE(16.20+)，Teradata JSON Shredding |
| [数值类型](../types/numeric/teradata.sql) | BYTEINT/SMALLINT/INTEGER/BIGINT/DECIMAL/FLOAT/NUMBER |
| [字符串类型](../types/string/teradata.sql) | VARCHAR/CHAR/CLOB，CHARACTER SET 指定字符集 |
