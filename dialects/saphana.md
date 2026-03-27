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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/saphana.sql) | 内存列存默认(ROW/COLUMN 可选)，实时 OLAP+OLTP |
| [改表](../ddl/alter-table/saphana.sql) | ALTER 在线执行，列存/行存表各有限制 |
| [索引](../ddl/indexes/saphana.sql) | 列存自动索引(无需手动)，行存 B-tree/Fulltext 索引 |
| [约束](../ddl/constraints/saphana.sql) | PK/FK/UNIQUE/CHECK 完整支持 |
| [视图](../ddl/views/saphana.sql) | Calculation View(图形化建模) + SQL View，无传统物化视图 |
| [序列与自增](../ddl/sequences/saphana.sql) | SEQUENCE+GENERATED ALWAYS AS IDENTITY |
| [数据库/Schema/用户](../ddl/users-databases/saphana.sql) | Multi-Tenant(MDC)，Schema=用户命名空间，XS Advanced |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/saphana.sql) | EXEC/EXECUTE IMMEDIATE，SQLScript 过程语言 |
| [错误处理](../advanced/error-handling/saphana.sql) | DECLARE EXIT HANDLER，SIGNAL/RESIGNAL，SQLScript 异常处理 |
| [执行计划](../advanced/explain/saphana.sql) | EXPLAIN PLAN+PlanViz 图形化(SAP 特色)，Calculation Engine |
| [锁机制](../advanced/locking/saphana.sql) | MVCC(列存)+行锁(行存)，Snapshot Isolation 默认 |
| [分区](../advanced/partitioning/saphana.sql) | HASH/RANGE/ROUND_ROBIN 分区，大表自动分区推荐 |
| [权限](../advanced/permissions/saphana.sql) | 细粒度 Privilege 体系，Analytic Privilege 行级安全 |
| [存储过程](../advanced/stored-procedures/saphana.sql) | SQLScript 过程语言(CE 函数/SQL)，并行执行优化 |
| [临时表](../advanced/temp-tables/saphana.sql) | LOCAL/GLOBAL TEMPORARY TABLE，列存/行存可选 |
| [事务](../advanced/transactions/saphana.sql) | MVCC Snapshot Isolation，READ COMMITTED 默认，ACID |
| [触发器](../advanced/triggers/saphana.sql) | BEFORE/AFTER 行级触发器，无语句级 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/saphana.sql) | DELETE 标准，TRUNCATE 即时 |
| [插入](../dml/insert/saphana.sql) | INSERT+UPSERT 标准，IMPORT FROM 批量加载 |
| [更新](../dml/update/saphana.sql) | UPDATE 标准，UPSERT(REPLACE) 支持 |
| [Upsert](../dml/upsert/saphana.sql) | UPSERT/REPLACE 语句原生支持(非 MERGE) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/saphana.sql) | STRING_AGG/GROUPING SETS/CUBE/ROLLUP 完整 |
| [条件函数](../functions/conditional/saphana.sql) | CASE/IFNULL/NULLIF/COALESCE/MAP(类似 DECODE) |
| [日期函数](../functions/date-functions/saphana.sql) | ADD_DAYS/ADD_MONTHS/DAYS_BETWEEN，日期函数丰富 |
| [数学函数](../functions/math-functions/saphana.sql) | 完整数学函数 |
| [字符串函数](../functions/string-functions/saphana.sql) | || 拼接，LOCATE/SUBSTR/REPLACE 标准 |
| [类型转换](../functions/type-conversion/saphana.sql) | CAST/TO_DATE/TO_DECIMAL 显式转换 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/saphana.sql) | WITH 标准+递归 CTE 支持 |
| [全文搜索](../query/full-text-search/saphana.sql) | FULLTEXT INDEX 内置(列存)，CONTAINS/FUZZY/近邻搜索 |
| [连接查询](../query/joins/saphana.sql) | JOIN 完整，LATERAL(2.0+)，内存计算加速 |
| [分页](../query/pagination/saphana.sql) | LIMIT/OFFSET 标准 |
| [行列转换](../query/pivot-unpivot/saphana.sql) | 无原生 PIVOT，CASE+GROUP BY 或 MAP 函数 |
| [集合操作](../query/set-operations/saphana.sql) | UNION/INTERSECT/EXCEPT 完整 |
| [子查询](../query/subquery/saphana.sql) | 关联子查询+标量子查询优化 |
| [窗口函数](../query/window-functions/saphana.sql) | 完整窗口函数，ROWS/RANGE/GROUPS 帧 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/saphana.sql) | SERIES_GENERATE_DATE 序列生成(独有函数) |
| [去重](../scenarios/deduplication/saphana.sql) | ROW_NUMBER+CTE 去重 |
| [区间检测](../scenarios/gap-detection/saphana.sql) | SERIES_GENERATE+窗口函数 |
| [层级查询](../scenarios/hierarchical-query/saphana.sql) | HIERARCHY 函数(独有)，递归 CTE 亦支持 |
| [JSON 展开](../scenarios/json-flatten/saphana.sql) | JSON_TABLE/JSON_QUERY/JSON_VALUE 标准 |
| [迁移速查](../scenarios/migration-cheatsheet/saphana.sql) | 内存列存+SQLScript+Calculation View 是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/saphana.sql) | ROW_NUMBER+LIMIT 标准 |
| [累计求和](../scenarios/running-total/saphana.sql) | SUM() OVER 标准，内存计算极快 |
| [缓慢变化维](../scenarios/slowly-changing-dim/saphana.sql) | MERGE+系统版本化表(Temporal Table) |
| [字符串拆分](../scenarios/string-split-to-rows/saphana.sql) | SERIES_GENERATE+SUBSTR 或 JSON_TABLE |
| [窗口分析](../scenarios/window-analytics/saphana.sql) | 完整窗口函数，SERIES 时序分析能力 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/saphana.sql) | 无原生 ARRAY/STRUCT 列类型，用表类型替代 |
| [日期时间](../types/datetime/saphana.sql) | DATE/TIME/TIMESTAMP/SECONDDATE 四类型，精度到纳秒 |
| [JSON](../types/json/saphana.sql) | JSON Document Store+JSON_TABLE 标准，内存加速 |
| [数值类型](../types/numeric/saphana.sql) | TINYINT-BIGINT/DECIMAL/FLOAT/DOUBLE/SMALLDECIMAL |
| [字符串类型](../types/string/saphana.sql) | NVARCHAR(UTF-8 默认)，VARCHAR/NCLOB，无 TEXT 别名 |
