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

| 模块 | 链接 |
|---|---|
| 建表 | [kingbase.sql](../ddl/create-table/kingbase.sql) |
| 改表 | [kingbase.sql](../ddl/alter-table/kingbase.sql) |
| 索引 | [kingbase.sql](../ddl/indexes/kingbase.sql) |
| 约束 | [kingbase.sql](../ddl/constraints/kingbase.sql) |
| 视图 | [kingbase.sql](../ddl/views/kingbase.sql) |
| 序列与自增 | [kingbase.sql](../ddl/sequences/kingbase.sql) |
| 数据库/Schema/用户 | [kingbase.sql](../ddl/users-databases/kingbase.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [kingbase.sql](../advanced/dynamic-sql/kingbase.sql) |
| 错误处理 | [kingbase.sql](../advanced/error-handling/kingbase.sql) |
| 执行计划 | [kingbase.sql](../advanced/explain/kingbase.sql) |
| 锁机制 | [kingbase.sql](../advanced/locking/kingbase.sql) |
| 分区 | [kingbase.sql](../advanced/partitioning/kingbase.sql) |
| 权限 | [kingbase.sql](../advanced/permissions/kingbase.sql) |
| 存储过程 | [kingbase.sql](../advanced/stored-procedures/kingbase.sql) |
| 临时表 | [kingbase.sql](../advanced/temp-tables/kingbase.sql) |
| 事务 | [kingbase.sql](../advanced/transactions/kingbase.sql) |
| 触发器 | [kingbase.sql](../advanced/triggers/kingbase.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [kingbase.sql](../dml/delete/kingbase.sql) |
| 插入 | [kingbase.sql](../dml/insert/kingbase.sql) |
| 更新 | [kingbase.sql](../dml/update/kingbase.sql) |
| Upsert | [kingbase.sql](../dml/upsert/kingbase.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [kingbase.sql](../functions/aggregate/kingbase.sql) |
| 条件函数 | [kingbase.sql](../functions/conditional/kingbase.sql) |
| 日期函数 | [kingbase.sql](../functions/date-functions/kingbase.sql) |
| 数学函数 | [kingbase.sql](../functions/math-functions/kingbase.sql) |
| 字符串函数 | [kingbase.sql](../functions/string-functions/kingbase.sql) |
| 类型转换 | [kingbase.sql](../functions/type-conversion/kingbase.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [kingbase.sql](../query/cte/kingbase.sql) |
| 全文搜索 | [kingbase.sql](../query/full-text-search/kingbase.sql) |
| 连接查询 | [kingbase.sql](../query/joins/kingbase.sql) |
| 分页 | [kingbase.sql](../query/pagination/kingbase.sql) |
| 行列转换 | [kingbase.sql](../query/pivot-unpivot/kingbase.sql) |
| 集合操作 | [kingbase.sql](../query/set-operations/kingbase.sql) |
| 子查询 | [kingbase.sql](../query/subquery/kingbase.sql) |
| 窗口函数 | [kingbase.sql](../query/window-functions/kingbase.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [kingbase.sql](../scenarios/date-series-fill/kingbase.sql) |
| 去重 | [kingbase.sql](../scenarios/deduplication/kingbase.sql) |
| 区间检测 | [kingbase.sql](../scenarios/gap-detection/kingbase.sql) |
| 层级查询 | [kingbase.sql](../scenarios/hierarchical-query/kingbase.sql) |
| JSON 展开 | [kingbase.sql](../scenarios/json-flatten/kingbase.sql) |
| 迁移速查 | [kingbase.sql](../scenarios/migration-cheatsheet/kingbase.sql) |
| TopN 查询 | [kingbase.sql](../scenarios/ranking-top-n/kingbase.sql) |
| 累计求和 | [kingbase.sql](../scenarios/running-total/kingbase.sql) |
| 缓慢变化维 | [kingbase.sql](../scenarios/slowly-changing-dim/kingbase.sql) |
| 字符串拆分 | [kingbase.sql](../scenarios/string-split-to-rows/kingbase.sql) |
| 窗口分析 | [kingbase.sql](../scenarios/window-analytics/kingbase.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [kingbase.sql](../types/array-map-struct/kingbase.sql) |
| 日期时间 | [kingbase.sql](../types/datetime/kingbase.sql) |
| JSON | [kingbase.sql](../types/json/kingbase.sql) |
| 数值类型 | [kingbase.sql](../types/numeric/kingbase.sql) |
| 字符串类型 | [kingbase.sql](../types/string/kingbase.sql) |
