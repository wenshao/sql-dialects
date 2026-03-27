# SAP HANA

**分类**: 内存数据库（SAP）
**文件数**: 51 个 SQL 文件
**总行数**: 4410 行

## 概述与定位

SAP HANA 是 SAP 推出的内存计算平台，其核心是一个以列式存储为主、行列混存的关系数据库引擎。HANA 最初为加速 SAP 商业套件（ERP、BW）的实时分析而设计，后逐步发展为独立的通用数据库平台。它将 OLTP 与 OLAP 统一在同一引擎中，消除传统架构中从操作型系统到分析型系统的 ETL 延迟，是"实时企业"理念的技术支撑。

## 历史与演进

- **2010 年**：SAP HANA 1.0 发布，定位为 BW（Business Warehouse）加速器，纯内存列式存储。
- **2013 年**：HANA SPS06 引入行存引擎和应用服务器（XS Engine），从纯分析扩展到 OLTP 场景。
- **2015 年**：SAP S/4HANA 发布，HANA 成为 SAP 新一代 ERP 套件的唯一数据库平台。
- **2016 年**：HANA 2.0 引入多租户数据库容器（MDC）、动态分层（Dynamic Tiering）、SQLScript 增强。
- **2019 年**：引入 HANA Cloud，提供完全托管的云端 HANA 实例，支持数据湖和联邦查询。
- **2022 年**：增强 JSON Document Store、Graph Engine、空间数据处理与机器学习集成（PAL/APL）。
- **2024-2025 年**：持续推进向量引擎（用于 AI 应用）、改进多模型处理和云原生弹性。

## 核心设计思路

1. **内存优先**：热数据常驻内存，列式压缩使内存利用率极高；冷数据可下沉到磁盘或 Native Storage Extension。
2. **行列混存**：行存引擎（Row Store）处理事务型写密集负载，列存引擎（Column Store）处理分析型读密集负载，同一数据库共存。
3. **计算下推**：通过 SQLScript 将业务逻辑下推到数据库层执行，减少应用层与数据库之间的数据搬运。
4. **多模型引擎**：在同一平台上提供关系、图（Graph）、文档（JSON）、空间（Spatial）和文本搜索能力。

## 独特特色

| 特性 | 说明 |
|---|---|
| **SQLScript** | HANA 专有的过程化语言，强调声明式逻辑（表变量、CE 函数），编译器可自动并行化执行。 |
| **行列混存** | 建表时通过 `COLUMN` 或 `ROW` 关键字选择存储类型，也可在运行时为列存表添加行存二级索引。 |
| **FUZZY Search** | 内置模糊搜索引擎，`CONTAINS(..., FUZZY(0.8))` 支持拼写容错、语义相似度匹配，无需外部搜索引擎。 |
| **Hierarchy Functions** | 原生层级导航函数 `HIERARCHY()`、`HIERARCHY_DESCENDANTS()`，可直接对 parent-child 关系进行递归展开和聚合。 |
| **Calculation View** | 可视化建模工具定义的虚拟视图，底层由列引擎优化执行，是 SAP BW/4HANA 的核心数据模型。 |
| **系列数据处理** | 内置时间序列分析函数（`SERIES_GENERATE`、`SERIES_FILTER`），支持等间距时间序列的自动对齐与插值。 |
| **多租户容器（MDC）** | 一个 HANA 系统可包含多个独立数据库容器，共享内存和进程，实现资源隔离。 |

## 已知不足

- **SAP 生态深度绑定**：HANA 的最佳实践和工具链高度依赖 SAP 生态系统，非 SAP 用户的独立使用体验相对薄弱。
- **许可成本极高**：HANA 的内存许可模式按 GB 计费，是市场上最昂贵的数据库之一。
- **第三方生态有限**：虽然提供 ODBC/JDBC 驱动，但 ORM 框架、BI 工具对 HANA 方言的支持不如主流数据库完善。
- **SQLScript 学习成本**：其声明式风格（表变量、无游标设计）与传统 PL/SQL 差异大，迁移存量代码需大量重写。
- **开源社区缺失**：HANA 是闭源商业产品，缺少社区版和开源替代方案，技术讨论和知识分享集中在 SAP 官方渠道。

## 对引擎开发者的参考价值

- **行列混存架构**：在同一引擎中协调行存和列存的事务一致性，对 HTAP 数据库设计有核心参考意义。
- **SQLScript 的声明式编译**：将过程化代码中的表变量操作自动转化为关系代数并行执行图，是"将逻辑下推到引擎"的典范。
- **FUZZY 搜索引擎集成**：将模糊文本搜索作为 SQL 谓词的一部分而非独立服务，展示了搜索与查询引擎融合的可能性。
- **Hierarchy 函数设计**：以函数而非递归 CTE 的方式处理层级数据，减少了递归查询的优化难度。
- **内存管理策略**：HANA 的列存压缩算法（字典编码、游程编码、聚类编码）和 Delta/Main 合并策略对内存引擎设计有直接借鉴。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [saphana.sql](../ddl/create-table/saphana.sql) |
| 改表 | [saphana.sql](../ddl/alter-table/saphana.sql) |
| 索引 | [saphana.sql](../ddl/indexes/saphana.sql) |
| 约束 | [saphana.sql](../ddl/constraints/saphana.sql) |
| 视图 | [saphana.sql](../ddl/views/saphana.sql) |
| 序列与自增 | [saphana.sql](../ddl/sequences/saphana.sql) |
| 数据库/Schema/用户 | [saphana.sql](../ddl/users-databases/saphana.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [saphana.sql](../advanced/dynamic-sql/saphana.sql) |
| 错误处理 | [saphana.sql](../advanced/error-handling/saphana.sql) |
| 执行计划 | [saphana.sql](../advanced/explain/saphana.sql) |
| 锁机制 | [saphana.sql](../advanced/locking/saphana.sql) |
| 分区 | [saphana.sql](../advanced/partitioning/saphana.sql) |
| 权限 | [saphana.sql](../advanced/permissions/saphana.sql) |
| 存储过程 | [saphana.sql](../advanced/stored-procedures/saphana.sql) |
| 临时表 | [saphana.sql](../advanced/temp-tables/saphana.sql) |
| 事务 | [saphana.sql](../advanced/transactions/saphana.sql) |
| 触发器 | [saphana.sql](../advanced/triggers/saphana.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [saphana.sql](../dml/delete/saphana.sql) |
| 插入 | [saphana.sql](../dml/insert/saphana.sql) |
| 更新 | [saphana.sql](../dml/update/saphana.sql) |
| Upsert | [saphana.sql](../dml/upsert/saphana.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [saphana.sql](../functions/aggregate/saphana.sql) |
| 条件函数 | [saphana.sql](../functions/conditional/saphana.sql) |
| 日期函数 | [saphana.sql](../functions/date-functions/saphana.sql) |
| 数学函数 | [saphana.sql](../functions/math-functions/saphana.sql) |
| 字符串函数 | [saphana.sql](../functions/string-functions/saphana.sql) |
| 类型转换 | [saphana.sql](../functions/type-conversion/saphana.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [saphana.sql](../query/cte/saphana.sql) |
| 全文搜索 | [saphana.sql](../query/full-text-search/saphana.sql) |
| 连接查询 | [saphana.sql](../query/joins/saphana.sql) |
| 分页 | [saphana.sql](../query/pagination/saphana.sql) |
| 行列转换 | [saphana.sql](../query/pivot-unpivot/saphana.sql) |
| 集合操作 | [saphana.sql](../query/set-operations/saphana.sql) |
| 子查询 | [saphana.sql](../query/subquery/saphana.sql) |
| 窗口函数 | [saphana.sql](../query/window-functions/saphana.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [saphana.sql](../scenarios/date-series-fill/saphana.sql) |
| 去重 | [saphana.sql](../scenarios/deduplication/saphana.sql) |
| 区间检测 | [saphana.sql](../scenarios/gap-detection/saphana.sql) |
| 层级查询 | [saphana.sql](../scenarios/hierarchical-query/saphana.sql) |
| JSON 展开 | [saphana.sql](../scenarios/json-flatten/saphana.sql) |
| 迁移速查 | [saphana.sql](../scenarios/migration-cheatsheet/saphana.sql) |
| TopN 查询 | [saphana.sql](../scenarios/ranking-top-n/saphana.sql) |
| 累计求和 | [saphana.sql](../scenarios/running-total/saphana.sql) |
| 缓慢变化维 | [saphana.sql](../scenarios/slowly-changing-dim/saphana.sql) |
| 字符串拆分 | [saphana.sql](../scenarios/string-split-to-rows/saphana.sql) |
| 窗口分析 | [saphana.sql](../scenarios/window-analytics/saphana.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [saphana.sql](../types/array-map-struct/saphana.sql) |
| 日期时间 | [saphana.sql](../types/datetime/saphana.sql) |
| JSON | [saphana.sql](../types/json/saphana.sql) |
| 数值类型 | [saphana.sql](../types/numeric/saphana.sql) |
| 字符串类型 | [saphana.sql](../types/string/saphana.sql) |
