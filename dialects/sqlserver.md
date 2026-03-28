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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/sqlserver.md) | 聚集索引=物理排序，IDENTITY，Temporal Tables(2016+) 自动历史版本 |
| [改表](../ddl/alter-table/sqlserver.md) | DDL 不可回滚（同 Oracle），在线操作需 Enterprise Edition |
| [索引](../ddl/indexes/sqlserver.md) | Columnstore(2012+) 列存先驱，Filtered Index，INCLUDE 覆盖列 |
| [约束](../ddl/constraints/sqlserver.md) | WITH CHECK/NOCHECK 可暂停约束检查，灵活但易滥用 |
| [视图](../ddl/views/sqlserver.md) | Indexed View 物化视图，SCHEMABINDING 保护依赖 |
| [序列与自增](../ddl/sequences/sqlserver.md) | IDENTITY+SEQUENCE(2012+)，SCOPE_IDENTITY() 获取自增值 |
| [数据库/Schema/用户](../ddl/users-databases/sqlserver.md) | DENY 显式拒绝权限独有，AD 集成身份验证 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/sqlserver.md) | sp_executesql 参数化查询防注入，比 EXEC() 安全 |
| [错误处理](../advanced/error-handling/sqlserver.md) | TRY...CATCH 不能嵌套 TRANSACTION 回滚点，需配合 XACT_ABORT |
| [执行计划](../advanced/explain/sqlserver.md) | 图形化执行计划+Live Query Statistics 实时监控 |
| [锁机制](../advanced/locking/sqlserver.md) | 默认锁式并发，锁升级行→页→表，WITH(NOLOCK) 文化盛行 |
| [分区](../advanced/partitioning/sqlserver.md) | Partition Function+Scheme 设计清晰，但需 Enterprise Edition |
| [权限](../advanced/permissions/sqlserver.md) | DENY 独有（优先级高于 GRANT），Dynamic Data Masking(2016+) |
| [存储过程](../advanced/stored-procedures/sqlserver.md) | T-SQL 过程式完整，Natively Compiled(Hekaton) 极致性能 |
| [临时表](../advanced/temp-tables/sqlserver.md) | #temp 本地+##temp 全局+表变量 @t，tempdb 是核心资源 |
| [事务](../advanced/transactions/sqlserver.md) | XACT_ABORT 必须设 ON，默认锁式并发，RCSI 推荐开启 |
| [触发器](../advanced/triggers/sqlserver.md) | 无 BEFORE 触发器，只有 AFTER+INSTEAD OF |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/sqlserver.md) | OUTPUT DELETED.* 返回被删行，TOP(N) 限制删除行数 |
| [插入](../dml/insert/sqlserver.md) | OUTPUT INSERTED.* 返回含自增值，BULK INSERT 批量导入 |
| [更新](../dml/update/sqlserver.md) | OUTPUT INSERTED/DELETED 同时获取更新前后值 |
| [Upsert](../dml/upsert/sqlserver.md) | MERGE 有已知竞态条件 Bug，专家建议避免使用 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/sqlserver.md) | STRING_AGG 2017 才有，之前需 FOR XML PATH 黑魔法 |
| [条件函数](../functions/conditional/sqlserver.md) | IIF(2012+) 简洁条件，CHOOSE 按位置选值 |
| [日期函数](../functions/date-functions/sqlserver.md) | DATEADD/DATEDIFF/EOMONTH 语义清晰，FORMAT() 依赖 CLR 性能差 |
| [数学函数](../functions/math-functions/sqlserver.md) | GREATEST/LEAST 2022 才有，之前需 CASE 模拟 |
| [字符串函数](../functions/string-functions/sqlserver.md) | STRING_SPLIT(2016+)，CONCAT_WS，TRANSLATE(2017+) |
| [类型转换](../functions/type-conversion/sqlserver.md) | TRY_CAST/TRY_CONVERT 安全转换先驱，失败返回 NULL |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/sqlserver.md) | WITH 标准支持，MAXRECURSION 防无限递归 |
| [全文搜索](../query/full-text-search/sqlserver.md) | CONTAINS/FREETEXT+全文索引，需配置 Full-Text Catalog |
| [连接查询](../query/joins/sqlserver.md) | CROSS APPLY/OUTER APPLY（比 LATERAL 更早），WITH(NOLOCK) 文化 |
| [分页](../query/pagination/sqlserver.md) | OFFSET...FETCH(2012+) 标准语法，TOP WITH TIES |
| [行列转换](../query/pivot-unpivot/sqlserver.md) | 原生 PIVOT/UNPIVOT，列名需静态指定 |
| [集合操作](../query/set-operations/sqlserver.md) | UNION/INTERSECT/EXCEPT 完整支持 |
| [子查询](../query/subquery/sqlserver.md) | 优化器自动展开关联子查询，Adaptive Join(2017+) |
| [窗口函数](../query/window-functions/sqlserver.md) | Batch Mode(2019+) 性能提升 2-10x，无 NTH_VALUE |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/sqlserver.md) | 无 generate_series，需递归 CTE 或数字表模拟 |
| [去重](../scenarios/deduplication/sqlserver.md) | ROW_NUMBER+CTE DELETE 直接去重，语法简洁 |
| [区间检测](../scenarios/gap-detection/sqlserver.md) | 窗口函数+数字表填充 |
| [层级查询](../scenarios/hierarchical-query/sqlserver.md) | WITH RECURSIVE+hierarchyid 数据类型独有 |
| [JSON 展开](../scenarios/json-flatten/sqlserver.md) | OPENJSON+CROSS APPLY 展开，FOR JSON 生成 |
| [迁移速查](../scenarios/migration-cheatsheet/sqlserver.md) | T-SQL 偏离标准大，Collation 差异是迁移痛点 |
| [TopN 查询](../scenarios/ranking-top-n/sqlserver.md) | TOP WITH TIES 独有，CROSS APPLY 分组 TopN |
| [累计求和](../scenarios/running-total/sqlserver.md) | Batch Mode(2019+) 窗口函数性能飞跃 |
| [缓慢变化维](../scenarios/slowly-changing-dim/sqlserver.md) | Temporal Tables(2016+) 系统自动维护历史版本 |
| [字符串拆分](../scenarios/string-split-to-rows/sqlserver.md) | STRING_SPLIT(2016+) 原生支持，enable_ordinal(2022+) |
| [窗口分析](../scenarios/window-analytics/sqlserver.md) | Batch Mode 大幅提速，GROUPS 帧和 NTH_VALUE 缺失 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/sqlserver.md) | 无原生数组，需 Table-Valued Parameter 或 JSON 模拟 |
| [日期时间](../types/datetime/sqlserver.md) | 旧 datetime 精度仅 3.33ms，datetime2 100ns 精度 |
| [JSON](../types/json/sqlserver.md) | JSON 存为 NVARCHAR 无专用类型，OPENJSON 解析，无 JSON 索引 |
| [数值类型](../types/numeric/sqlserver.md) | DECIMAL/NUMERIC 精确，MONEY 类型便捷但有精度陷阱 |
| [字符串类型](../types/string/sqlserver.md) | Collation 影响比较和索引，不同 Collation 列 JOIN 报错 |
