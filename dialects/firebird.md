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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/firebird.sql) | 嵌入式/服务器双模式，IDENTITY(3.0+)，单文件数据库 |
| [改表](../ddl/alter-table/firebird.sql) | ALTER 标准，在线操作大部分支持 |
| [索引](../ddl/indexes/firebird.sql) | B-tree 索引，表达式索引(3.0+) |
| [约束](../ddl/constraints/firebird.sql) | PK/FK/CHECK/UNIQUE 完整，延迟约束(3.0+) |
| [视图](../ddl/views/firebird.sql) | 普通视图+可更新视图，无物化视图 |
| [序列与自增](../ddl/sequences/firebird.sql) | GENERATOR(传统)=SEQUENCE(SQL 标准别名)，IDENTITY(3.0+) |
| [数据库/Schema/用户](../ddl/users-databases/firebird.sql) | 单 Schema(无多 Schema)，ROLE 权限，SEC$USERS |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/firebird.sql) | EXECUTE STATEMENT 动态 SQL(PSQL 内) |
| [错误处理](../advanced/error-handling/firebird.sql) | WHEN...DO 异常处理(PSQL)，GDSCODE/SQLCODE |
| [执行计划](../advanced/explain/firebird.sql) | EXPLAIN/SET PLAN ON 显示执行计划 |
| [锁机制](../advanced/locking/firebird.sql) | MVCC(Multi-Generational Architecture)，版本链，读不阻塞写 |
| [分区](../advanced/partitioning/firebird.sql) | 无分区支持 |
| [权限](../advanced/permissions/firebird.sql) | GRANT/REVOKE 标准，ROLE，对象级权限精细 |
| [存储过程](../advanced/stored-procedures/firebird.sql) | PSQL 过程语言，Selectable Stored Procedures(返回结果集) |
| [临时表](../advanced/temp-tables/firebird.sql) | GTT 全局临时表(2.1+)，ON COMMIT |
| [事务](../advanced/transactions/firebird.sql) | MVCC 先驱(版本链存储)，快照隔离，读一致性强 |
| [触发器](../advanced/triggers/firebird.sql) | BEFORE/AFTER 行级触发器，Database 级触发器(DDL 事件) |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/firebird.sql) | DELETE 标准，RETURNING 支持(2.1+) |
| [插入](../dml/insert/firebird.sql) | INSERT/RETURNING(2.1+)，MERGE(3.0+) |
| [更新](../dml/update/firebird.sql) | UPDATE/RETURNING(2.1+)，UPDATE OR INSERT(2.1+) |
| [Upsert](../dml/upsert/firebird.sql) | UPDATE OR INSERT(2.1+，独有语法)+MERGE(3.0+) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/firebird.sql) | LIST() 聚合(=STRING_AGG)，基本聚合完整 |
| [条件函数](../functions/conditional/firebird.sql) | CASE/COALESCE/NULLIF/IIF(2.0+) 标准 |
| [日期函数](../functions/date-functions/firebird.sql) | DATEADD/DATEDIFF，EXTRACT 标准，CURRENT_TIMESTAMP |
| [数学函数](../functions/math-functions/firebird.sql) | 完整数学函数 |
| [字符串函数](../functions/string-functions/firebird.sql) | || 拼接，SUBSTRING/POSITION/TRIM 标准 |
| [类型转换](../functions/type-conversion/firebird.sql) | CAST 标准，无 TRY_CAST |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/firebird.sql) | WITH+递归 CTE(2.1+)，早期支持 |
| [全文搜索](../query/full-text-search/firebird.sql) | 无内置全文搜索 |
| [连接查询](../query/joins/firebird.sql) | JOIN 完整(INNER/LEFT/RIGHT/FULL)，NATURAL JOIN |
| [分页](../query/pagination/firebird.sql) | FIRST/SKIP(独有语法)，FETCH FIRST/OFFSET(3.0+) |
| [行列转换](../query/pivot-unpivot/firebird.sql) | 无原生 PIVOT |
| [集合操作](../query/set-operations/firebird.sql) | UNION/INTERSECT/EXCEPT 完整 |
| [子查询](../query/subquery/firebird.sql) | 关联子查询+IN/EXISTS 标准 |
| [窗口函数](../query/window-functions/firebird.sql) | 完整窗口函数(3.0+)，ROWS/RANGE 帧 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/firebird.sql) | 递归 CTE 生成日期序列 |
| [去重](../scenarios/deduplication/firebird.sql) | ROW_NUMBER(3.0+)+CTE 去重 |
| [区间检测](../scenarios/gap-detection/firebird.sql) | 窗口函数(3.0+)+递归 CTE |
| [层级查询](../scenarios/hierarchical-query/firebird.sql) | 递归 CTE(2.1+) |
| [JSON 展开](../scenarios/json-flatten/firebird.sql) | 无原生 JSON 支持(5.0 计划中) |
| [迁移速查](../scenarios/migration-cheatsheet/firebird.sql) | MVCC 先驱+PSQL+单文件部署是核心特色 |
| [TopN 查询](../scenarios/ranking-top-n/firebird.sql) | ROW_NUMBER(3.0+)+FIRST/SKIP |
| [累计求和](../scenarios/running-total/firebird.sql) | SUM() OVER(3.0+) |
| [缓慢变化维](../scenarios/slowly-changing-dim/firebird.sql) | MERGE(3.0+)+UPDATE OR INSERT |
| [字符串拆分](../scenarios/string-split-to-rows/firebird.sql) | 递归 CTE+SUBSTRING 模拟 |
| [窗口分析](../scenarios/window-analytics/firebird.sql) | 完整窗口函数(3.0+) |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/firebird.sql) | 无 ARRAY/STRUCT 类型 |
| [日期时间](../types/datetime/firebird.sql) | DATE/TIME/TIMESTAMP 标准，无 INTERVAL 类型 |
| [JSON](../types/json/firebird.sql) | 无原生 JSON 支持(5.0 计划中) |
| [数值类型](../types/numeric/firebird.sql) | SMALLINT/INTEGER/BIGINT/DECIMAL/FLOAT/DOUBLE 标准 |
| [字符串类型](../types/string/firebird.sql) | VARCHAR/CHAR/BLOB SUB_TYPE TEXT，字符集声明 |
