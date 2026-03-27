# Firebird

**分类**: 传统关系型数据库（InterBase 开源分支）
**文件数**: 51 个 SQL 文件
**总行数**: 4276 行

## 概述与定位

Firebird 是一款源自 Borland InterBase 6.0 开源代码的关系型数据库管理系统。它以"零管理"著称——单个数据库文件即可运行，无需专职 DBA，特别适合嵌入式应用、中小型业务系统与 ISV（独立软件供应商）分发场景。Firebird 同时提供嵌入式（Embedded）和客户端/服务器两种部署模式，是少数能在桌面应用到企业服务之间平滑切换的数据库。

## 历史与演进

- **2000 年**：Borland 将 InterBase 6.0 以开源许可发布，Firebird 社区随即分叉并独立开发。
- **2004 年**：Firebird 1.5 引入新的执行架构（Super Server / Classic Server 双模式），显著提升并发能力。
- **2008 年**：Firebird 2.1 支持全局临时表（Global Temporary Tables）、EXECUTE BLOCK、递归 CTE。
- **2012 年**：Firebird 2.5 引入完善的监控表（MON$* 系统表），可实时查看连接、事务与 SQL 统计。
- **2016 年**：Firebird 3.0 实现多线程 SuperServer、对称多处理（SMP）支持、包（Package）与窗口函数。
- **2023 年**：Firebird 4.0 增加 INT128/DECFLOAT 类型、时区支持、内联窗口帧、复制（Replication）功能。
- **2024 年**：Firebird 5.0 引入并行查询执行、多租户支持（Multi-tenancy）、改进的优化器统计。

## 核心设计思路

1. **MGA 架构**：采用多版本并发控制（Multi-Generational Architecture），每个事务看到一致的数据库快照，读不阻塞写。
2. **单文件数据库**：整个数据库存储在一个或少数几个文件中（.fdb/.gdb），便于备份、迁移和分发。
3. **嵌入式与服务器双模**：同一份数据库文件可被嵌入式库（fbembed）直接打开，也可通过网络服务端访问。
4. **SQL 标准导向**：Firebird 的 SQL 方言高度遵循 SQL 标准，PSQL（过程化 SQL）语法简洁且功能完备。

## 独特特色

| 特性 | 说明 |
|---|---|
| **EXECUTE BLOCK** | 在不创建存储过程的前提下，直接在客户端执行一段 PSQL 代码块，等同于匿名块。 |
| **Generators（序列）** | Firebird 的 Generator 是服务器级原子序列，通过 `GEN_ID()` / `NEXT VALUE FOR` 获取值，事务回滚不影响序列值。 |
| **FIRST/SKIP** | Firebird 早期分页语法，`SELECT FIRST 10 SKIP 20 ...`，先于 SQL 标准的 FETCH/OFFSET 实现。 |
| **UPDATE OR INSERT** | 原生的 upsert 语句，根据 MATCHING 子句自动判断更新或插入，语法比标准 MERGE 更简洁。 |
| **可选式触发器** | 触发器可同时绑定多个事件（BEFORE INSERT OR UPDATE OR DELETE），用一个触发器体处理多种操作。 |
| **PSQL 包（Package）** | 3.0+ 支持包头（Header）和包体（Body）分离，提供模块化封装与接口抽象。 |
| **监控虚拟表** | `MON$STATEMENTS`、`MON$TRANSACTIONS` 等虚拟表可实时查询当前 SQL 执行状态，无需外部工具。 |

## 已知不足

- **社区体量小**：相比主流数据库，Firebird 的用户社区与第三方生态（ORM、连接池、云托管）明显偏小。
- **分区表缺失**：至 5.0 仍无原生表分区功能，大表管理需依赖手动拆表或外部方案。
- **并行查询起步晚**：5.0 才引入并行查询执行，早期版本仅支持单线程查询。
- **JSON 支持有限**：Firebird 目前没有原生 JSON 数据类型，JSON 操作需通过 UDF 或字符串函数模拟。
- **集群与高可用**：原生复制功能（4.0+）仍相对基础，缺乏自动故障转移与读写分离的成熟方案。
- **云生态薄弱**：主流云平台未提供 Firebird 托管服务，部署和运维需自行管理。

## 对引擎开发者的参考价值

- **MGA 并发模型**：Firebird 的多版本实现比 PostgreSQL 更早成熟，其"记录级版本链"设计对嵌入式 MVCC 引擎有直接借鉴价值。
- **嵌入式部署架构**：单文件数据库 + 零配置运行的设计，是 DuckDB、SQLite 等嵌入式数据库的先行者。
- **EXECUTE BLOCK 实现**：在不注册持久对象的情况下执行过程化代码，其解析-编译-执行的管道设计值得参考。
- **Generator 的事务无关性**：序列值在事务回滚后不回收的设计，是实现全局唯一 ID 生成器的经典方案。
- **UPDATE OR INSERT 语义**：MATCHING 子句驱动的冲突检测逻辑比 MERGE 更轻量，对简化 upsert 实现有启发。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [firebird.sql](../ddl/create-table/firebird.sql) |
| 改表 | [firebird.sql](../ddl/alter-table/firebird.sql) |
| 索引 | [firebird.sql](../ddl/indexes/firebird.sql) |
| 约束 | [firebird.sql](../ddl/constraints/firebird.sql) |
| 视图 | [firebird.sql](../ddl/views/firebird.sql) |
| 序列与自增 | [firebird.sql](../ddl/sequences/firebird.sql) |
| 数据库/Schema/用户 | [firebird.sql](../ddl/users-databases/firebird.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [firebird.sql](../advanced/dynamic-sql/firebird.sql) |
| 错误处理 | [firebird.sql](../advanced/error-handling/firebird.sql) |
| 执行计划 | [firebird.sql](../advanced/explain/firebird.sql) |
| 锁机制 | [firebird.sql](../advanced/locking/firebird.sql) |
| 分区 | [firebird.sql](../advanced/partitioning/firebird.sql) |
| 权限 | [firebird.sql](../advanced/permissions/firebird.sql) |
| 存储过程 | [firebird.sql](../advanced/stored-procedures/firebird.sql) |
| 临时表 | [firebird.sql](../advanced/temp-tables/firebird.sql) |
| 事务 | [firebird.sql](../advanced/transactions/firebird.sql) |
| 触发器 | [firebird.sql](../advanced/triggers/firebird.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [firebird.sql](../dml/delete/firebird.sql) |
| 插入 | [firebird.sql](../dml/insert/firebird.sql) |
| 更新 | [firebird.sql](../dml/update/firebird.sql) |
| Upsert | [firebird.sql](../dml/upsert/firebird.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [firebird.sql](../functions/aggregate/firebird.sql) |
| 条件函数 | [firebird.sql](../functions/conditional/firebird.sql) |
| 日期函数 | [firebird.sql](../functions/date-functions/firebird.sql) |
| 数学函数 | [firebird.sql](../functions/math-functions/firebird.sql) |
| 字符串函数 | [firebird.sql](../functions/string-functions/firebird.sql) |
| 类型转换 | [firebird.sql](../functions/type-conversion/firebird.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [firebird.sql](../query/cte/firebird.sql) |
| 全文搜索 | [firebird.sql](../query/full-text-search/firebird.sql) |
| 连接查询 | [firebird.sql](../query/joins/firebird.sql) |
| 分页 | [firebird.sql](../query/pagination/firebird.sql) |
| 行列转换 | [firebird.sql](../query/pivot-unpivot/firebird.sql) |
| 集合操作 | [firebird.sql](../query/set-operations/firebird.sql) |
| 子查询 | [firebird.sql](../query/subquery/firebird.sql) |
| 窗口函数 | [firebird.sql](../query/window-functions/firebird.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [firebird.sql](../scenarios/date-series-fill/firebird.sql) |
| 去重 | [firebird.sql](../scenarios/deduplication/firebird.sql) |
| 区间检测 | [firebird.sql](../scenarios/gap-detection/firebird.sql) |
| 层级查询 | [firebird.sql](../scenarios/hierarchical-query/firebird.sql) |
| JSON 展开 | [firebird.sql](../scenarios/json-flatten/firebird.sql) |
| 迁移速查 | [firebird.sql](../scenarios/migration-cheatsheet/firebird.sql) |
| TopN 查询 | [firebird.sql](../scenarios/ranking-top-n/firebird.sql) |
| 累计求和 | [firebird.sql](../scenarios/running-total/firebird.sql) |
| 缓慢变化维 | [firebird.sql](../scenarios/slowly-changing-dim/firebird.sql) |
| 字符串拆分 | [firebird.sql](../scenarios/string-split-to-rows/firebird.sql) |
| 窗口分析 | [firebird.sql](../scenarios/window-analytics/firebird.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [firebird.sql](../types/array-map-struct/firebird.sql) |
| 日期时间 | [firebird.sql](../types/datetime/firebird.sql) |
| JSON | [firebird.sql](../types/json/firebird.sql) |
| 数值类型 | [firebird.sql](../types/numeric/firebird.sql) |
| 字符串类型 | [firebird.sql](../types/string/firebird.sql) |
