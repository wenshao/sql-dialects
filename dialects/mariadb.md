# MariaDB

**分类**: MySQL 兼容分支
**文件数**: 51 个 SQL 文件
**总行数**: 4792 行

## 概述与定位

MariaDB 是 MySQL 的社区驱动分叉，由 MySQL 原始创始人 Michael "Monty" Widenius 于 2009 年创建。它定位为 MySQL 的"增强型替代品"（drop-in replacement），在保持协议级和 SQL 级兼容的前提下，独立推进许多 MySQL 未能实现或推迟实现的特性。MariaDB 既适用于 OLTP 场景，也通过 ColumnStore 存储引擎涵盖分析型负载，形成了"一个内核、多引擎"的混合定位。

## 历史与演进

- **2009 年**：Monty 在 Oracle 收购 Sun/MySQL 之前启动 MariaDB 分叉，初始代码基于 MySQL 5.1。
- **2012 年**：MariaDB 5.5 成为第一个被多数 Linux 发行版默认采用的版本（替换 MySQL）。
- **2013 年**：10.0 引入多源复制（multi-source replication）与并行复制，开始与 MySQL 版本号脱钩。
- **2017 年**：10.2 支持窗口函数与 CTE，比 MySQL 8.0 更早交付。
- **2018 年**：10.3 引入 SEQUENCE 引擎、系统版本表（System-Versioned Tables）与 INTERSECT/EXCEPT。
- **2021 年**：10.5+ 引入 RETURNING 子句、INVISIBLE 列、IF NOT EXISTS 对更多语句的支持。
- **2023 年**：10.11 成为长期支持版本，引入 WITHOUT OVERLAPS 约束、UUID v7 函数。
- **2024-2025 年**：11.x 系列持续推进原子 DDL、向量索引预研、增强 JSON 表函数。

## 核心设计思路

1. **引擎可插拔**：InnoDB（默认）、Aria（崩溃安全 MyISAM 替代）、Spider（分片联邦）、ColumnStore（列存分析）、SEQUENCE（虚拟序列引擎）等多引擎共存。
2. **SQL 标准优先**：在 MySQL 滞后时率先实现标准语法——窗口函数、CTE、INTERSECT/EXCEPT、NATURAL FULL OUTER JOIN。
3. **向后兼容**：协议、复制格式与 MySQL 保持最大程度兼容，方便用户无缝切换。
4. **社区开放**：所有新特性默认贡献到开源主干；不存在仅商业版可用的功能。

## 独特特色

| 特性 | 说明 |
|---|---|
| **SEQUENCE 引擎（10.3+）** | `SELECT * FROM seq_1_to_100` 即可生成序列，无需建表，用于日期填充、批量测试极为方便。 |
| **系统版本表** | `WITH SYSTEM VERSIONING` 使表自动记录所有行的历史版本，支持 `FOR SYSTEM_TIME AS OF` 时间旅行查询。 |
| **RETURNING** | INSERT/DELETE/REPLACE 语句可附加 `RETURNING` 子句，一步返回受影响行，减少额外 SELECT。 |
| **INVISIBLE 列** | 列可标记为 `INVISIBLE`，`SELECT *` 不返回，但可显式引用，适合审计字段与内部字段。 |
| **WITHOUT OVERLAPS** | 主键/唯一键中使用 `WITHOUT OVERLAPS` 即可在数据库层面防止时间区间重叠，原生实现 temporal 约束。 |
| **Oracle 兼容模式** | `SET sql_mode='ORACLE'` 后可直接执行 PL/SQL 风格代码，包括 `%ROWTYPE`、包变量、异常处理。 |
| **多源复制** | 一个从库同时从多个主库复制，适合数据汇聚场景。 |

## 已知不足

- **生态分裂**：与 MySQL 的差异逐版本扩大，部分 ORM/驱动（如特定版本的 MySQL Connector）可能出现兼容问题。
- **Group Replication 缺失**：MariaDB 使用 Galera Cluster 实现多主同步复制，但与 MySQL 的 Group Replication/InnoDB Cluster 不兼容。
- **文档与社区体量**：相比 MySQL/PostgreSQL，中文技术社区资料相对较少。
- **ColumnStore 成熟度**：列存引擎功能在快速迭代中，与专业 OLAP 引擎相比仍有差距。
- **JSON 函数滞后**：部分 JSON 路径操作（如 JSON_TABLE）引入晚于 MySQL 8.0。

## 对引擎开发者的参考价值

- **SEQUENCE 引擎的实现**：通过虚拟存储引擎生成序列值，是"引擎即函数"设计的优秀范例，值得嵌入式引擎参考。
- **系统版本表架构**：在存储引擎层透明维护行版本，对实现时间旅行查询（temporal query）的引擎有直接借鉴意义。
- **WITHOUT OVERLAPS 约束**：将区间不重叠校验下沉到索引层，展示了约束检查与索引结构耦合的设计路径。
- **Oracle 兼容模式**：通过 sql_mode 切换语法解析器行为，是多方言兼容的可行实现方案。
- **RETURNING 子句实现**：在 DML 执行路径中插入结果集返回节点，对减少客户端往返有参考价值。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [mariadb.sql](../ddl/create-table/mariadb.sql) |
| 改表 | [mariadb.sql](../ddl/alter-table/mariadb.sql) |
| 索引 | [mariadb.sql](../ddl/indexes/mariadb.sql) |
| 约束 | [mariadb.sql](../ddl/constraints/mariadb.sql) |
| 视图 | [mariadb.sql](../ddl/views/mariadb.sql) |
| 序列与自增 | [mariadb.sql](../ddl/sequences/mariadb.sql) |
| 数据库/Schema/用户 | [mariadb.sql](../ddl/users-databases/mariadb.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [mariadb.sql](../advanced/dynamic-sql/mariadb.sql) |
| 错误处理 | [mariadb.sql](../advanced/error-handling/mariadb.sql) |
| 执行计划 | [mariadb.sql](../advanced/explain/mariadb.sql) |
| 锁机制 | [mariadb.sql](../advanced/locking/mariadb.sql) |
| 分区 | [mariadb.sql](../advanced/partitioning/mariadb.sql) |
| 权限 | [mariadb.sql](../advanced/permissions/mariadb.sql) |
| 存储过程 | [mariadb.sql](../advanced/stored-procedures/mariadb.sql) |
| 临时表 | [mariadb.sql](../advanced/temp-tables/mariadb.sql) |
| 事务 | [mariadb.sql](../advanced/transactions/mariadb.sql) |
| 触发器 | [mariadb.sql](../advanced/triggers/mariadb.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [mariadb.sql](../dml/delete/mariadb.sql) |
| 插入 | [mariadb.sql](../dml/insert/mariadb.sql) |
| 更新 | [mariadb.sql](../dml/update/mariadb.sql) |
| Upsert | [mariadb.sql](../dml/upsert/mariadb.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [mariadb.sql](../functions/aggregate/mariadb.sql) |
| 条件函数 | [mariadb.sql](../functions/conditional/mariadb.sql) |
| 日期函数 | [mariadb.sql](../functions/date-functions/mariadb.sql) |
| 数学函数 | [mariadb.sql](../functions/math-functions/mariadb.sql) |
| 字符串函数 | [mariadb.sql](../functions/string-functions/mariadb.sql) |
| 类型转换 | [mariadb.sql](../functions/type-conversion/mariadb.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [mariadb.sql](../query/cte/mariadb.sql) |
| 全文搜索 | [mariadb.sql](../query/full-text-search/mariadb.sql) |
| 连接查询 | [mariadb.sql](../query/joins/mariadb.sql) |
| 分页 | [mariadb.sql](../query/pagination/mariadb.sql) |
| 行列转换 | [mariadb.sql](../query/pivot-unpivot/mariadb.sql) |
| 集合操作 | [mariadb.sql](../query/set-operations/mariadb.sql) |
| 子查询 | [mariadb.sql](../query/subquery/mariadb.sql) |
| 窗口函数 | [mariadb.sql](../query/window-functions/mariadb.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [mariadb.sql](../scenarios/date-series-fill/mariadb.sql) |
| 去重 | [mariadb.sql](../scenarios/deduplication/mariadb.sql) |
| 区间检测 | [mariadb.sql](../scenarios/gap-detection/mariadb.sql) |
| 层级查询 | [mariadb.sql](../scenarios/hierarchical-query/mariadb.sql) |
| JSON 展开 | [mariadb.sql](../scenarios/json-flatten/mariadb.sql) |
| 迁移速查 | [mariadb.sql](../scenarios/migration-cheatsheet/mariadb.sql) |
| TopN 查询 | [mariadb.sql](../scenarios/ranking-top-n/mariadb.sql) |
| 累计求和 | [mariadb.sql](../scenarios/running-total/mariadb.sql) |
| 缓慢变化维 | [mariadb.sql](../scenarios/slowly-changing-dim/mariadb.sql) |
| 字符串拆分 | [mariadb.sql](../scenarios/string-split-to-rows/mariadb.sql) |
| 窗口分析 | [mariadb.sql](../scenarios/window-analytics/mariadb.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [mariadb.sql](../types/array-map-struct/mariadb.sql) |
| 日期时间 | [mariadb.sql](../types/datetime/mariadb.sql) |
| JSON | [mariadb.sql](../types/json/mariadb.sql) |
| 数值类型 | [mariadb.sql](../types/numeric/mariadb.sql) |
| 字符串类型 | [mariadb.sql](../types/string/mariadb.sql) |
