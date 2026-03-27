# 人大金仓 (KingbaseES)

**分类**: 国产数据库（兼容 PostgreSQL/Oracle）
**文件数**: 51 个 SQL 文件
**总行数**: 5407 行

## 概述与定位

人大金仓（KingbaseES）是北京人大金仓信息技术股份有限公司研发的国产商业关系型数据库，基于 PostgreSQL 内核开发并大幅扩展。KingbaseES 的核心定位是同时兼容 PostgreSQL 和 Oracle 两种生态，帮助用户从 Oracle 或 PostgreSQL 平滑迁移。它是中国信创产业的核心数据库产品之一，在政府、军工、金融、能源等安全敏感领域有广泛部署，特别强调安全合规能力。

## 历史与演进

- **1999 年**：中国人民大学数据库研究团队启动金仓数据库项目。
- **2003 年**：人大金仓公司成立，产品化开发加速。
- **2008 年**：KingbaseES V6 通过国家信息安全认证。
- **2012 年**：V7 引入 Oracle 兼容模式增强。
- **2017 年**：V8 基于 PostgreSQL 9.6 内核重构，大幅提升 PG/Oracle 双兼容能力。
- **2020 年**：随信创政策推动，市场份额快速增长。
- **2022-2025 年**：持续增强分布式能力、安全特性和 ARM 平台支持。

## 核心设计思路

KingbaseES 基于 PostgreSQL 内核深度改造，核心设计目标是**双模兼容**——在 PG 兼容的基础上额外提供 Oracle 兼容层。通过设置 `ora_compatible` 参数可在 PG 模式和 Oracle 模式之间切换，Oracle 模式下支持 PL/SQL（KES PL/SQL 方言）、Package、同义词和 Oracle 风格数据字典。安全方面实现了**三权分立**（系统管理员、安全管理员、审计管理员权限分离）和**强制访问控制**（MAC），满足国家等级保护要求。

## 独特特色

- **PG/Oracle 双模兼容**：通过兼容模式开关，同一内核支持 PostgreSQL 和 Oracle 两套 SQL 方言。
- **三权分立安全模型**：系统管理员（sso）、安全管理员（sao）、审计管理员（aud）权限完全分离，防止权限滥用。
- **强制访问控制 (MAC)**：支持基于安全标签的行级强制访问控制，满足国家等级保护三级/四级要求。
- **PL/SQL 兼容**：Oracle 模式下支持 Package、Cursor、动态 SQL、异常处理等 PL/SQL 核心特性。
- **透明数据加密 (TDE)**：支持表空间级和列级透明加密。
- **国密算法支持**：内置 SM2/SM3/SM4 国密加密算法。
- **审计增强**：细粒度审计到语句级别，支持审计策略的灵活配置。

## 已知不足

- 闭源商业软件，社区版功能受限，开发者获取和试用不够便捷。
- Oracle 兼容模式覆盖面有限，复杂 PL/SQL 程序（特别是高级包和类型）迁移可能需要调整。
- 基于较早版本 PostgreSQL 分叉，部分 PG 新版本特性缺失。
- 国际化程度低，文档和技术支持以中文为主。
- 性能调优和监控工具成熟度与 PostgreSQL 原生生态有差距。
- 分布式方案的成熟度相比专门的分布式数据库有待提升。

## 对引擎开发者的参考价值

KingbaseES 的 PG/Oracle 双模兼容实现展示了在同一查询引擎内通过兼容模式开关适配不同 SQL 方言的工程方法。其三权分立安全模型和强制访问控制（MAC）的实现对数据库安全子系统设计有直接参考意义——这些安全特性在商用数据库中并不常见但在政企场景中至关重要。在 PG 内核上叠加 Oracle 兼容层的实践也为理解数据库内核扩展提供了一个有价值的案例。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/kingbase.sql) | PG+Oracle 双兼容模式，IDENTITY/SERIAL 均支持 |
| [改表](../ddl/alter-table/kingbase.sql) | PG 兼容 ALTER 语法，Oracle 模式兼容 DDL |
| [索引](../ddl/indexes/kingbase.sql) | B-tree/GIN/GiST(PG 兼容)+位图索引(Oracle 兼容) |
| [约束](../ddl/constraints/kingbase.sql) | PK/FK/CHECK/UNIQUE(PG 兼容)，延迟约束 |
| [视图](../ddl/views/kingbase.sql) | 物化视图(PG 兼容)，REFRESH CONCURRENTLY |
| [序列与自增](../ddl/sequences/kingbase.sql) | SEQUENCE/SERIAL/IDENTITY(PG+Oracle 双兼容) |
| [数据库/Schema/用户](../ddl/users-databases/kingbase.sql) | PG 兼容权限+三权分立(国产安全特色) |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/kingbase.sql) | EXECUTE(PL/pgSQL)+EXECUTE IMMEDIATE(Oracle 模式) |
| [错误处理](../advanced/error-handling/kingbase.sql) | EXCEPTION WHEN(PL/pgSQL)，Oracle 模式异常处理 |
| [执行计划](../advanced/explain/kingbase.sql) | EXPLAIN ANALYZE(PG 兼容) |
| [锁机制](../advanced/locking/kingbase.sql) | MVCC(PG 兼容)，行级锁，读不阻塞写 |
| [分区](../advanced/partitioning/kingbase.sql) | 声明式分区(PG 兼容)，RANGE/LIST/HASH |
| [权限](../advanced/permissions/kingbase.sql) | PG 兼容 RBAC+三权分立+强制访问控制(国产安全) |
| [存储过程](../advanced/stored-procedures/kingbase.sql) | PL/pgSQL+PL/SQL 双模式(核心卖点)，Package 支持 |
| [临时表](../advanced/temp-tables/kingbase.sql) | TEMPORARY TABLE(PG 兼容) |
| [事务](../advanced/transactions/kingbase.sql) | MVCC(PG 兼容)，DDL 事务性(PG 优势保留) |
| [触发器](../advanced/triggers/kingbase.sql) | BEFORE/AFTER/INSTEAD OF(PG 兼容)+行/语句级 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/kingbase.sql) | DELETE/RETURNING(PG 兼容) |
| [插入](../dml/insert/kingbase.sql) | INSERT/RETURNING(PG 兼容)，ON CONFLICT Upsert |
| [更新](../dml/update/kingbase.sql) | UPDATE/RETURNING(PG 兼容) |
| [Upsert](../dml/upsert/kingbase.sql) | ON CONFLICT(PG 兼容)+MERGE(Oracle 兼容) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/kingbase.sql) | string_agg/LISTAGG(双兼容)，GROUPING SETS |
| [条件函数](../functions/conditional/kingbase.sql) | CASE/COALESCE(PG)+DECODE/NVL(Oracle 模式) |
| [日期函数](../functions/date-functions/kingbase.sql) | PG+Oracle 日期函数双兼容 |
| [数学函数](../functions/math-functions/kingbase.sql) | PG 兼容数学函数 |
| [字符串函数](../functions/string-functions/kingbase.sql) | || 拼接(PG 标准)，Oracle 兼容函数 |
| [类型转换](../functions/type-conversion/kingbase.sql) | CAST/::(PG)+TO_NUMBER/TO_DATE(Oracle 兼容) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/kingbase.sql) | WITH+递归 CTE(PG 兼容) |
| [全文搜索](../query/full-text-search/kingbase.sql) | tsvector/tsquery(PG 兼容) |
| [连接查询](../query/joins/kingbase.sql) | JOIN 完整(PG 兼容)，LATERAL 支持 |
| [分页](../query/pagination/kingbase.sql) | LIMIT/OFFSET(PG)+ROWNUM(Oracle 兼容) |
| [行列转换](../query/pivot-unpivot/kingbase.sql) | crosstab(PG 兼容)+PIVOT(Oracle 兼容模式) |
| [集合操作](../query/set-operations/kingbase.sql) | UNION/INTERSECT/EXCEPT(PG 兼容) |
| [子查询](../query/subquery/kingbase.sql) | 关联子查询(PG 兼容)，优化器 |
| [窗口函数](../query/window-functions/kingbase.sql) | 完整窗口函数(PG 兼容) |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/kingbase.sql) | generate_series(PG 兼容) |
| [去重](../scenarios/deduplication/kingbase.sql) | DISTINCT ON(PG 兼容)+ROW_NUMBER |
| [区间检测](../scenarios/gap-detection/kingbase.sql) | generate_series+窗口函数(PG 兼容) |
| [层级查询](../scenarios/hierarchical-query/kingbase.sql) | 递归 CTE(PG)+CONNECT BY(Oracle 兼容模式) |
| [JSON 展开](../scenarios/json-flatten/kingbase.sql) | json_each/json_array_elements(PG 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/kingbase.sql) | PG+Oracle 双兼容是核心卖点，国产安全认证 |
| [TopN 查询](../scenarios/ranking-top-n/kingbase.sql) | ROW_NUMBER+LIMIT(PG 兼容) |
| [累计求和](../scenarios/running-total/kingbase.sql) | SUM() OVER(PG 兼容) |
| [缓慢变化维](../scenarios/slowly-changing-dim/kingbase.sql) | ON CONFLICT(PG)+MERGE(Oracle 兼容) |
| [字符串拆分](../scenarios/string-split-to-rows/kingbase.sql) | string_to_array+unnest(PG 兼容) |
| [窗口分析](../scenarios/window-analytics/kingbase.sql) | 完整窗口函数(PG 兼容) |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/kingbase.sql) | ARRAY/复合类型(PG 兼容) |
| [日期时间](../types/datetime/kingbase.sql) | DATE/TIMESTAMP/INTERVAL(PG 兼容) |
| [JSON](../types/json/kingbase.sql) | JSON/JSONB(PG 兼容)，GIN 索引 |
| [数值类型](../types/numeric/kingbase.sql) | INTEGER/NUMERIC(PG)+NUMBER(Oracle 兼容) |
| [字符串类型](../types/string/kingbase.sql) | TEXT/VARCHAR(PG)+VARCHAR2(Oracle 兼容) |
