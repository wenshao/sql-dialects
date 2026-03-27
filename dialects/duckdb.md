# DuckDB

**分类**: 嵌入式 OLAP
**文件数**: 51 个 SQL 文件
**总行数**: 4880 行

## 概述与定位

DuckDB 是一款嵌入式列式分析数据库，常被称为"分析领域的 SQLite"。由 CWI（荷兰国家数学与计算机科学研究中心）的 Mark Raasveldt 和 Hannes Muhleisen 于 2018 年创建，DuckDB 以进程内嵌入方式运行——无需安装服务器、无需配置网络，直接作为库链接到 Python/R/Java/Node.js 应用中。它采用 PostgreSQL 兼容的 SQL 方言，并在此基础上引入了大量便利的语法糖，使交互式数据分析极为高效。

## 历史与演进

- **2018 年**：DuckDB 项目在 CWI 启动，目标是创建一个嵌入式 OLAP 数据库（对标 SQLite 之于 OLTP）。
- **2019 年**：DuckDB 0.1 发布，初步实现列式存储和向量化执行引擎。
- **2020 年**：DuckDB Labs 公司成立，0.2 版本增加 Parquet 读写、Python API 集成。
- **2021 年**：引入扩展（Extension）系统，支持 httpfs（远程文件读取）、spatial（地理空间）等扩展。
- **2022 年**：0.5+ 版本引入 PIVOT/UNPIVOT、GROUP BY ALL、COLUMNS(*) 等语法创新。
- **2023 年**：0.9 版本引入新的存储格式（v2）、增强并行执行、Iceberg/Delta Lake 扩展。
- **2024-2025 年**：1.0 稳定版发布，存储格式冻结，增强多线程、大于内存的数据集支持、社区扩展生态。

## 核心设计思路

1. **嵌入式进程内**：DuckDB 作为库运行在应用进程中，零网络开销、零配置部署，适合数据科学家、分析师和 CI/CD 管道。
2. **向量化引擎**：采用 Morsel-Driven Parallelism 的向量化执行模型，数据以 Vector（向量）为单位在算子间流动，充分利用 CPU 缓存。
3. **PostgreSQL 方言 + 语法糖**：基础 SQL 语法兼容 PostgreSQL，同时添加了大量分析友好的创新语法。
4. **外部数据直查**：可直接查询 CSV/Parquet/JSON 文件（本地或 S3），无需先导入，`SELECT * FROM 'data.parquet'` 即可工作。

## 独特特色

| 特性 | 说明 |
|---|---|
| **PIVOT / UNPIVOT** | 原生的行列转换语法，`PIVOT t ON year USING SUM(amount)` 比手写 CASE WHEN 简洁数倍。 |
| **GROUP BY ALL** | 自动将 SELECT 中非聚合列加入 GROUP BY，`SELECT dept, SUM(salary) FROM t GROUP BY ALL` 无需重复列出分组列。 |
| **COLUMNS(*)** | 对所有列或匹配的列批量应用表达式：`SELECT MIN(COLUMNS(*)) FROM t` 计算每列的最小值。 |
| **直接文件查询** | `SELECT * FROM 'file.parquet'` 或 `FROM read_csv('data.csv')` 直接查询外部文件，无需建表。 |
| **FROM-first 语法** | 支持 `FROM t SELECT col` 的语法顺序，以及省略 SELECT 的 `FROM t`（等价于 `SELECT * FROM t`）。 |
| **List/Struct/Map 类型** | 原生支持复合类型，`[1, 2, 3]` 为 LIST，`{'a': 1}` 为 STRUCT，配合 Lambda 函数进行元素级操作。 |
| **扩展系统** | 可通过 `INSTALL ext; LOAD ext;` 动态加载扩展（httpfs、spatial、postgres_scanner、sqlite_scanner 等）。 |

## 已知不足

- **单机限制**：DuckDB 是单进程数据库，不支持分布式查询和多节点扩展，数据规模受限于单机资源。
- **并发写入受限**：同一时刻仅支持一个写入连接（多读单写），不适合多用户并发写入场景。
- **无服务端模式**：不提供网络服务器，不能作为独立的数据库服务部署（需嵌入到应用中）。
- **存储过程缺失**：不支持存储过程和触发器，复杂的过程化逻辑需通过宿主语言（Python/Java 等）实现。
- **生态尚在发展**：虽然增长迅速，但与 PostgreSQL/MySQL 相比，企业级工具链（备份、监控、权限管理）仍不完善。

## 对引擎开发者的参考价值

- **Morsel-Driven Parallelism**：DuckDB 的论文级向量化执行模型——将数据切分为 Morsel（小批量），由多线程工作者动态获取并处理——是现代 OLAP 引擎并行执行的标杆实现。
- **语法创新（GROUP BY ALL / COLUMNS）**：展示了在不破坏标准兼容性的前提下通过语法糖大幅提升开发者体验的可能性，对 SQL 方言设计有重要参考。
- **嵌入式架构设计**：零配置、单文件存储、进程内运行的设计模式，对嵌入式数据库引擎的架构选型有直接参考。
- **外部数据直查管道**：将文件路径作为表引用直接解析的设计，简化了数据导入流程，对查询引擎的数据源抽象有启发。
- **扩展系统设计**：通过动态加载共享库扩展引擎功能（新数据源、新函数、新文件格式）的插件架构，对引擎的可扩展性设计有参考价值。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [duckdb.sql](../ddl/create-table/duckdb.sql) |
| 改表 | [duckdb.sql](../ddl/alter-table/duckdb.sql) |
| 索引 | [duckdb.sql](../ddl/indexes/duckdb.sql) |
| 约束 | [duckdb.sql](../ddl/constraints/duckdb.sql) |
| 视图 | [duckdb.sql](../ddl/views/duckdb.sql) |
| 序列与自增 | [duckdb.sql](../ddl/sequences/duckdb.sql) |
| 数据库/Schema/用户 | [duckdb.sql](../ddl/users-databases/duckdb.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [duckdb.sql](../advanced/dynamic-sql/duckdb.sql) |
| 错误处理 | [duckdb.sql](../advanced/error-handling/duckdb.sql) |
| 执行计划 | [duckdb.sql](../advanced/explain/duckdb.sql) |
| 锁机制 | [duckdb.sql](../advanced/locking/duckdb.sql) |
| 分区 | [duckdb.sql](../advanced/partitioning/duckdb.sql) |
| 权限 | [duckdb.sql](../advanced/permissions/duckdb.sql) |
| 存储过程 | [duckdb.sql](../advanced/stored-procedures/duckdb.sql) |
| 临时表 | [duckdb.sql](../advanced/temp-tables/duckdb.sql) |
| 事务 | [duckdb.sql](../advanced/transactions/duckdb.sql) |
| 触发器 | [duckdb.sql](../advanced/triggers/duckdb.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [duckdb.sql](../dml/delete/duckdb.sql) |
| 插入 | [duckdb.sql](../dml/insert/duckdb.sql) |
| 更新 | [duckdb.sql](../dml/update/duckdb.sql) |
| Upsert | [duckdb.sql](../dml/upsert/duckdb.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [duckdb.sql](../functions/aggregate/duckdb.sql) |
| 条件函数 | [duckdb.sql](../functions/conditional/duckdb.sql) |
| 日期函数 | [duckdb.sql](../functions/date-functions/duckdb.sql) |
| 数学函数 | [duckdb.sql](../functions/math-functions/duckdb.sql) |
| 字符串函数 | [duckdb.sql](../functions/string-functions/duckdb.sql) |
| 类型转换 | [duckdb.sql](../functions/type-conversion/duckdb.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [duckdb.sql](../query/cte/duckdb.sql) |
| 全文搜索 | [duckdb.sql](../query/full-text-search/duckdb.sql) |
| 连接查询 | [duckdb.sql](../query/joins/duckdb.sql) |
| 分页 | [duckdb.sql](../query/pagination/duckdb.sql) |
| 行列转换 | [duckdb.sql](../query/pivot-unpivot/duckdb.sql) |
| 集合操作 | [duckdb.sql](../query/set-operations/duckdb.sql) |
| 子查询 | [duckdb.sql](../query/subquery/duckdb.sql) |
| 窗口函数 | [duckdb.sql](../query/window-functions/duckdb.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [duckdb.sql](../scenarios/date-series-fill/duckdb.sql) |
| 去重 | [duckdb.sql](../scenarios/deduplication/duckdb.sql) |
| 区间检测 | [duckdb.sql](../scenarios/gap-detection/duckdb.sql) |
| 层级查询 | [duckdb.sql](../scenarios/hierarchical-query/duckdb.sql) |
| JSON 展开 | [duckdb.sql](../scenarios/json-flatten/duckdb.sql) |
| 迁移速查 | [duckdb.sql](../scenarios/migration-cheatsheet/duckdb.sql) |
| TopN 查询 | [duckdb.sql](../scenarios/ranking-top-n/duckdb.sql) |
| 累计求和 | [duckdb.sql](../scenarios/running-total/duckdb.sql) |
| 缓慢变化维 | [duckdb.sql](../scenarios/slowly-changing-dim/duckdb.sql) |
| 字符串拆分 | [duckdb.sql](../scenarios/string-split-to-rows/duckdb.sql) |
| 窗口分析 | [duckdb.sql](../scenarios/window-analytics/duckdb.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [duckdb.sql](../types/array-map-struct/duckdb.sql) |
| 日期时间 | [duckdb.sql](../types/datetime/duckdb.sql) |
| JSON | [duckdb.sql](../types/json/duckdb.sql) |
| 数值类型 | [duckdb.sql](../types/numeric/duckdb.sql) |
| 字符串类型 | [duckdb.sql](../types/string/duckdb.sql) |
