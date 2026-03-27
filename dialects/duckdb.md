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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/duckdb.sql) | 嵌入式 OLAP，列式存储，PG 兼容语法，类型丰富 |
| [改表](../ddl/alter-table/duckdb.sql) | ALTER 支持有限，ADD/DROP/RENAME COLUMN，无在线 DDL 需求 |
| [索引](../ddl/indexes/duckdb.sql) | ART 索引（自适应基数树），主要靠 Zone Maps 自动过滤 |
| [约束](../ddl/constraints/duckdb.sql) | PK/UNIQUE/CHECK/FK 声明支持，部分约束实际执行 |
| [视图](../ddl/views/duckdb.sql) | 普通视图支持，无物化视图（内存 OLAP 不需要） |
| [序列与自增](../ddl/sequences/duckdb.sql) | SEQUENCE+自动递增（PG 兼容语法） |
| [数据库/Schema/用户](../ddl/users-databases/duckdb.sql) | ATTACH 多数据库，无用户权限（嵌入式定位） |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/duckdb.sql) | 无存储过程/动态 SQL，Python/R 集成替代 |
| [错误处理](../advanced/error-handling/duckdb.sql) | 无过程式错误处理，API 层错误返回 |
| [执行计划](../advanced/explain/duckdb.sql) | EXPLAIN ANALYZE 带实际行数，Profile 可视化 |
| [锁机制](../advanced/locking/duckdb.sql) | MVCC 乐观并发，单写者+多读者，无锁竞争 |
| [分区](../advanced/partitioning/duckdb.sql) | Hive 分区读取支持，内部分区通过 Row Groups |
| [权限](../advanced/permissions/duckdb.sql) | 无权限系统（嵌入式定位），文件级安全 |
| [存储过程](../advanced/stored-procedures/duckdb.sql) | 无存储过程，宏(MACRO) 替代简单逻辑 |
| [临时表](../advanced/temp-tables/duckdb.sql) | CREATE TEMP TABLE 支持，会话级 |
| [事务](../advanced/transactions/duckdb.sql) | ACID 事务，MVCC，单写者模型（类 SQLite） |
| [触发器](../advanced/triggers/duckdb.sql) | 无触发器支持 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/duckdb.sql) | DELETE 标准，批量操作列式引擎高效 |
| [插入](../dml/insert/duckdb.sql) | INSERT+COPY，可直接导入 Parquet/CSV/JSON 文件 |
| [更新](../dml/update/duckdb.sql) | UPDATE 标准，列式存储下更新非最优场景 |
| [Upsert](../dml/upsert/duckdb.sql) | INSERT OR REPLACE/ON CONFLICT(0.9+)，PG 兼容语法 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/duckdb.sql) | FILTER 子句，GROUPING SETS/CUBE/ROLLUP，list_agg |
| [条件函数](../functions/conditional/duckdb.sql) | CASE/COALESCE/NULLIF/IF，PG 兼容 |
| [日期函数](../functions/date-functions/duckdb.sql) | date_trunc/date_part/date_diff，INTERVAL 类型，PG 兼容 |
| [数学函数](../functions/math-functions/duckdb.sql) | 完整数学函数，GREATEST/LEAST 内置 |
| [字符串函数](../functions/string-functions/duckdb.sql) | || 拼接，regexp_extract/replace，string_split |
| [类型转换](../functions/type-conversion/duckdb.sql) | CAST/:: 运算符(PG 风格)，TRY_CAST 安全转换 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/duckdb.sql) | 递归 CTE 完整支持，自动物化/内联优化 |
| [全文搜索](../query/full-text-search/duckdb.sql) | fts 扩展全文搜索，基于 BM25 |
| [连接查询](../query/joins/duckdb.sql) | Hash/Merge/Nested Loop JOIN，LATERAL JOIN，ASOF JOIN 独有 |
| [分页](../query/pagination/duckdb.sql) | LIMIT/OFFSET 标准，FETCH FIRST 亦支持 |
| [行列转换](../query/pivot-unpivot/duckdb.sql) | PIVOT/UNPIVOT 原生支持（0.8+） |
| [集合操作](../query/set-operations/duckdb.sql) | UNION/INTERSECT/EXCEPT+ALL 完整 |
| [子查询](../query/subquery/duckdb.sql) | LATERAL 子查询支持，优化器自动展开 |
| [窗口函数](../query/window-functions/duckdb.sql) | 完整窗口函数，QUALIFY 支持，WINDOW 命名子句 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/duckdb.sql) | generate_series 原生支持（PG 兼容），RANGE 生成 |
| [去重](../scenarios/deduplication/duckdb.sql) | QUALIFY ROW_NUMBER() 或 DISTINCT ON(PG 兼容) |
| [区间检测](../scenarios/gap-detection/duckdb.sql) | generate_series+窗口函数检测 |
| [层级查询](../scenarios/hierarchical-query/duckdb.sql) | 递归 CTE 标准实现 |
| [JSON 展开](../scenarios/json-flatten/duckdb.sql) | json_extract/json_each，可直接查询 JSON 文件 |
| [迁移速查](../scenarios/migration-cheatsheet/duckdb.sql) | PG 兼容语法+列式引擎，适合从 PG 迁移分析负载 |
| [TopN 查询](../scenarios/ranking-top-n/duckdb.sql) | QUALIFY ROW_NUMBER() 或 DISTINCT ON |
| [累计求和](../scenarios/running-total/duckdb.sql) | SUM() OVER 标准，列式引擎聚合极快 |
| [缓慢变化维](../scenarios/slowly-changing-dim/duckdb.sql) | INSERT OR REPLACE+标准 MERGE(0.9+) |
| [字符串拆分](../scenarios/string-split-to-rows/duckdb.sql) | string_split+UNNEST 或 regexp_split_to_table |
| [窗口分析](../scenarios/window-analytics/duckdb.sql) | 完整窗口函数+QUALIFY+WINDOW 子句 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/duckdb.sql) | LIST/STRUCT/MAP/UNION 原生类型，嵌套查询自然 |
| [日期时间](../types/datetime/duckdb.sql) | DATE/TIME/TIMESTAMP/INTERVAL 完整，纳秒精度 |
| [JSON](../types/json/duckdb.sql) | 原生 JSON 类型，可直接查询 JSON 文件，json_extract 路径 |
| [数值类型](../types/numeric/duckdb.sql) | TINYINT-HUGEINT(128位)，DECIMAL 精确，FLOAT/DOUBLE |
| [字符串类型](../types/string/duckdb.sql) | VARCHAR 无长度限制，BLOB 二进制，正则内置 |
