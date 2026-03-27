# SQL Server

**分类**: 传统关系型数据库
**文件数**: 51 个 SQL 文件
**总行数**: 7792 行

## 概述与定位

SQL Server 是微软的企业级关系型数据库，也是 Windows 生态中数据库的默认选择。它的核心竞争力在于**与微软技术栈的深度集成** — .NET、Azure、Active Directory、SSIS/SSAS/SSRS、Visual Studio、Power BI。对于已经投入微软生态的企业，SQL Server 几乎是唯一合理的选择。

在技术层面，SQL Server 的优化器和执行引擎长期处于行业顶尖。它在某些领域甚至领先于 Oracle：Columnstore 索引（2012 年引入，早于 Oracle In-Memory）、In-Memory OLTP（Hekaton 引擎）、TRY_CAST/TRY_CONVERT（安全类型转换的先驱）。2017 年 SQL Server 登陆 Linux，标志着微软承认了开源和多平台的不可逆趋势。

## 历史与演进

- **1989**: 微软与 Sybase 合作在 OS/2 上发布 SQL Server 1.0
- **1993**: SQL Server 4.21 移植到 Windows NT，开始与 Sybase 分道扬镳
- **1996**: SQL Server 6.5 — 完全独立于 Sybase 的代码基
- **1998**: SQL Server 7.0 — 全新存储引擎，彻底重写
- **2000**: SQL Server 2000 — 成熟的企业级产品，XML 支持，联合数据库
- **2005**: SQL Server 2005 — 里程碑式重构：CLR 集成、SNAPSHOT 隔离、Service Broker、SSIS 取代 DTS、Management Studio 取代 Enterprise Manager
- **2008**: SQL Server 2008 — MERGE 语句、空间数据类型、数据压缩、Change Data Capture
- **2012**: SQL Server 2012 — Columnstore 索引（只读）、AlwaysOn AG、窗口函数增强（ROWS/RANGE）
- **2014**: SQL Server 2014 — In-Memory OLTP（Hekaton）、可更新 Columnstore
- **2016**: SQL Server 2016 — Temporal Tables、JSON 支持、Dynamic Data Masking、Row-Level Security、R 集成
- **2017**: SQL Server 2017 — **登陆 Linux**，Python 集成，Graph 查询
- **2019**: SQL Server 2019 — Intelligent Query Processing、Big Data Clusters、加速数据库恢复（ADR）
- **2022**: SQL Server 2022 — Ledger 表、GREATEST/LEAST/STRING_AGG、Azure 深度集成

SQL Server 的演进节奏清晰：每 2-3 年一个大版本，每个版本都有明确的主打特性。

## 核心设计思路

**T-SQL 过程语言**：Transact-SQL 是 SQL Server 的过程式扩展，与 Oracle 的 PL/SQL 对应。T-SQL 与标准 SQL 的偏离较大 — `IF...ELSE` 代替 `IF...THEN...END IF`，变量用 `@` 前缀声明，没有 `ELSIF`（需要嵌套 IF 或 CASE）。

**聚集索引=物理排序**：SQL Server 的表默认按聚集索引物理排序（堆表需要显式创建）。这意味着主键查询极快（等同于 InnoDB），但也意味着插入顺序不是物理顺序。与 PostgreSQL 的纯堆表模型形成鲜明对比。

**悲观并发（默认锁式隔离）**：SQL Server 默认的 READ COMMITTED 使用**锁**而非快照 — 读操作会加共享锁，读阻塞写、写阻塞读。这与 Oracle/PostgreSQL 的 MVCC 默认行为截然不同。要获得快照语义需要启用 RCSI（Read Committed Snapshot Isolation）。

**CROSS APPLY 创新**：SQL Server 2005 引入的 `CROSS APPLY` / `OUTER APPLY` 是对标准 `LATERAL JOIN` 的独立创新，允许右侧表表达式引用左侧表的列。这比 SQL:2003 标准的 LATERAL 更早被广泛使用。

## 独特特色（其他引擎没有的）

- **聚集索引（Clustered Index）**：表数据按聚集索引物理存储的架构，使 SQL Server 的主键范围扫描极快
- **`CROSS APPLY` / `OUTER APPLY`**：比 LATERAL JOIN 更早普及的关联表表达式，拆分 JSON、调用表值函数的标准手段
- **`OUTPUT` 子句**：INSERT/UPDATE/DELETE/MERGE 返回被影响的行，支持 `INSERTED` 和 `DELETED` 伪表（可同时获取修改前后的值）
- **`SET XACT_ABORT ON`**：错误自动回滚整个事务，避免部分提交。其他数据库需要手动处理
- **`TRY_CAST` / `TRY_CONVERT`**：转换失败返回 NULL 而非报错 — SQL Server 在安全类型转换上领先其他数据库多年
- **Temporal Tables（系统版本化时态表）**：自动记录行的历史版本，`FOR SYSTEM_TIME AS OF` 查询任意时间点数据
- **In-Memory OLTP（Hekaton）**：无锁、无 latch 的内存优化表和原生编译存储过程
- **Columnstore 索引**：列式存储与行式存储在同一引擎中共存，HTAP 的先驱实现
- **`DENY` 权限**：显式拒绝权限（优先级高于 GRANT），其他数据库只有 GRANT/REVOKE，缺少显式否定
- **Dynamic Data Masking**：列级数据脱敏，无需修改查询即可隐藏敏感数据
- **`GO` 批分隔符**：不是 SQL 语句而是客户端指令，将脚本分割为独立执行批次
- **`TOP` + `WITH TIES`**：`SELECT TOP 5 WITH TIES` 包含排名并列的额外行
- **`@@IDENTITY` / `SCOPE_IDENTITY()` / `@@ROWCOUNT`**：会话级别的元数据变量体系

## 已知的设计不足与历史包袱

- **默认锁式并发**：READ COMMITTED 默认用锁实现，读阻塞写、写阻塞读。新项目应始终启用 RCSI，但大量遗留系统未启用，导致阻塞和死锁频发
- **无 BEFORE 触发器**：只有 AFTER 和 INSTEAD OF 触发器，无法在操作前拦截并修改数据（Oracle/PostgreSQL 都有 BEFORE 触发器）
- **MERGE 有已知 Bug**：SQL Server 的 MERGE 语句有多个文档记录的竞态条件 Bug，微软多年未修复。生产环境中许多 DBA 建议避免使用 MERGE
- **`FORMAT()` 依赖 CLR 性能差**：`FORMAT(date, 'yyyy-MM-dd')` 内部调用 .NET CLR，性能比 `CONVERT` 差 10-50 倍
- **无 USING 子句**：JOIN 不支持 `USING(col)`，必须写完整的 `ON a.col = b.col`
- **`GREATEST` / `LEAST` 来得太晚**：2022 才加入，之前需要用 CASE 或 IIF 模拟
- **WINDOW 子句支持晚**：命名窗口定义（`WINDOW w AS (...)`) 支持较晚
- **字符串聚合晚到**：`STRING_AGG` 在 2017 才引入，之前需要 `FOR XML PATH` 的黑魔法
- **排序规则（Collation）混乱**：数据库级别的默认排序规则会影响字符串比较和索引行为，不同排序规则的列 JOIN 会报错
- **`datetime` 精度问题**：旧的 `datetime` 类型精度只有 3.33ms，必须用 `datetime2` 才有 100ns 精度

## 兼容生态

SQL Server 的兼容生态相对封闭：
- **Azure SQL Database**：SQL Server 的云托管版本，功能子集
- **Azure SQL Managed Instance**：更完整的云上 SQL Server，支持跨数据库查询
- **Azure Synapse Analytics**：SQL Server 方言的云数据仓库，MPP 架构
- **Amazon RDS for SQL Server**：AWS 上托管的 SQL Server 实例
- **Babelfish for Aurora PostgreSQL**：AWS 的 T-SQL 兼容层，运行在 PostgreSQL 之上 — 一个有趣的逆向兼容尝试

SQL Server 兼容生态窄的原因：T-SQL 与标准 SQL 的偏离度较大，且微软的许可模式不鼓励第三方兼容。

## 对引擎开发者的参考价值

- **锁升级机制**：SQL Server 的锁从行锁→页锁→表锁的自动升级策略是并发控制的经典实现。当单个事务锁定超过阈值（默认 5000 行）时自动升级，平衡了并发度和锁管理开销
- **Batch Mode 执行**：Columnstore 索引引入的批处理执行模式一次处理约 900 行而非逐行处理，CPU 效率提升 10-100 倍。2019 起 Batch Mode 可用于行存储表（Batch Mode on Rowstore）
- **RCSI / SNAPSHOT 隔离**：在传统锁式引擎上叠加 MVCC 的实现方案 — tempdb 作为版本存储。这展示了如何在不重写存储引擎的情况下添加快照隔离
- **Always Encrypted**：客户端加密、服务端无法解密的列级加密方案。密钥只在客户端驱动中存在，DBA 也无法看到明文。这是数据库安全的前沿设计
- **Intelligent Query Processing（IQP）**：自适应连接（Adaptive Join）、内存授予反馈（Memory Grant Feedback）、交错执行（Interleaved Execution）— SQL Server 2019 的查询优化器在运行时动态调整执行策略
- **Accelerated Database Recovery（ADR）**：基于持久化版本存储的快速恢复方案，将崩溃恢复时间从"与长事务成正比"降低到常数级别

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [sqlserver.sql](../ddl/create-table/sqlserver.sql) |
| 改表 | [sqlserver.sql](../ddl/alter-table/sqlserver.sql) |
| 索引 | [sqlserver.sql](../ddl/indexes/sqlserver.sql) |
| 约束 | [sqlserver.sql](../ddl/constraints/sqlserver.sql) |
| 视图 | [sqlserver.sql](../ddl/views/sqlserver.sql) |
| 序列与自增 | [sqlserver.sql](../ddl/sequences/sqlserver.sql) |
| 数据库/Schema/用户 | [sqlserver.sql](../ddl/users-databases/sqlserver.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [sqlserver.sql](../advanced/dynamic-sql/sqlserver.sql) |
| 错误处理 | [sqlserver.sql](../advanced/error-handling/sqlserver.sql) |
| 执行计划 | [sqlserver.sql](../advanced/explain/sqlserver.sql) |
| 锁机制 | [sqlserver.sql](../advanced/locking/sqlserver.sql) |
| 分区 | [sqlserver.sql](../advanced/partitioning/sqlserver.sql) |
| 权限 | [sqlserver.sql](../advanced/permissions/sqlserver.sql) |
| 存储过程 | [sqlserver.sql](../advanced/stored-procedures/sqlserver.sql) |
| 临时表 | [sqlserver.sql](../advanced/temp-tables/sqlserver.sql) |
| 事务 | [sqlserver.sql](../advanced/transactions/sqlserver.sql) |
| 触发器 | [sqlserver.sql](../advanced/triggers/sqlserver.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [sqlserver.sql](../dml/delete/sqlserver.sql) |
| 插入 | [sqlserver.sql](../dml/insert/sqlserver.sql) |
| 更新 | [sqlserver.sql](../dml/update/sqlserver.sql) |
| Upsert | [sqlserver.sql](../dml/upsert/sqlserver.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [sqlserver.sql](../functions/aggregate/sqlserver.sql) |
| 条件函数 | [sqlserver.sql](../functions/conditional/sqlserver.sql) |
| 日期函数 | [sqlserver.sql](../functions/date-functions/sqlserver.sql) |
| 数学函数 | [sqlserver.sql](../functions/math-functions/sqlserver.sql) |
| 字符串函数 | [sqlserver.sql](../functions/string-functions/sqlserver.sql) |
| 类型转换 | [sqlserver.sql](../functions/type-conversion/sqlserver.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [sqlserver.sql](../query/cte/sqlserver.sql) |
| 全文搜索 | [sqlserver.sql](../query/full-text-search/sqlserver.sql) |
| 连接查询 | [sqlserver.sql](../query/joins/sqlserver.sql) |
| 分页 | [sqlserver.sql](../query/pagination/sqlserver.sql) |
| 行列转换 | [sqlserver.sql](../query/pivot-unpivot/sqlserver.sql) |
| 集合操作 | [sqlserver.sql](../query/set-operations/sqlserver.sql) |
| 子查询 | [sqlserver.sql](../query/subquery/sqlserver.sql) |
| 窗口函数 | [sqlserver.sql](../query/window-functions/sqlserver.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [sqlserver.sql](../scenarios/date-series-fill/sqlserver.sql) |
| 去重 | [sqlserver.sql](../scenarios/deduplication/sqlserver.sql) |
| 区间检测 | [sqlserver.sql](../scenarios/gap-detection/sqlserver.sql) |
| 层级查询 | [sqlserver.sql](../scenarios/hierarchical-query/sqlserver.sql) |
| JSON 展开 | [sqlserver.sql](../scenarios/json-flatten/sqlserver.sql) |
| 迁移速查 | [sqlserver.sql](../scenarios/migration-cheatsheet/sqlserver.sql) |
| TopN 查询 | [sqlserver.sql](../scenarios/ranking-top-n/sqlserver.sql) |
| 累计求和 | [sqlserver.sql](../scenarios/running-total/sqlserver.sql) |
| 缓慢变化维 | [sqlserver.sql](../scenarios/slowly-changing-dim/sqlserver.sql) |
| 字符串拆分 | [sqlserver.sql](../scenarios/string-split-to-rows/sqlserver.sql) |
| 窗口分析 | [sqlserver.sql](../scenarios/window-analytics/sqlserver.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [sqlserver.sql](../types/array-map-struct/sqlserver.sql) |
| 日期时间 | [sqlserver.sql](../types/datetime/sqlserver.sql) |
| JSON | [sqlserver.sql](../types/json/sqlserver.sql) |
| 数值类型 | [sqlserver.sql](../types/numeric/sqlserver.sql) |
| 字符串类型 | [sqlserver.sql](../types/string/sqlserver.sql) |
