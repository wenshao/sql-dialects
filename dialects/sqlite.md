# SQLite

**分类**: 嵌入式数据库
**文件数**: 51 个 SQL 文件
**总行数**: 6216 行

## 概述与定位

SQLite 是全球部署量最大的数据库引擎，没有之一。每一部智能手机、每一个浏览器、每一个操作系统内核中都嵌入了 SQLite。保守估计全球活跃的 SQLite 数据库超过**万亿个** — 比所有其他数据库的总和多出几个数量级。

SQLite 的定位与 MySQL/PostgreSQL 完全不同：它不是客户端-服务器架构的"数据库服务"，而是一个**嵌入到应用程序进程中的 SQL 引擎**。没有独立的服务进程、没有网络协议、没有用户管理 — 数据库就是一个文件。这种极简主义使 SQLite 成为了"应用程序的文件格式"（官方定位），而非传统意义上的数据库服务器。

## 历史与演进

- **2000**: D. Richard Hipp 在 General Dynamics 为美国海军导弹驱逐舰项目开发 SQLite — 需求是一个不依赖 DBA 的嵌入式数据库
- **2001**: SQLite 1.0 使用 gdbm 作为后端存储
- **2004**: SQLite 3.0 — 完全重写，引入清单类型系统（manifest typing）、BLOB 支持、UTF-8/16
- **2010**: SQLite 3.7.0 — 引入 WAL（Write-Ahead Logging）模式，并发读性能飞跃
- **2013**: SQLite 被美国国会图书馆选为推荐的数字存档格式
- **2015**: SQLite 3.9.0 — 引入 JSON1 扩展和 FTS5（全文搜索第五代）
- **2018**: SQLite 3.25.0 — 引入窗口函数
- **2021**: SQLite 3.37.0 — 引入 STRICT 模式（可选的严格类型检查）
- **2022**: SQLite 3.39.0 — 引入 RIGHT JOIN 和 FULL OUTER JOIN
- **2023**: SQLite 3.41+ — JSONB 格式支持、数学函数内置化

SQLite 的许可模式独特：**公有领域（Public Domain）**。不是 MIT，不是 BSD，不是 GPL — 是完全放弃著作权。这意味着任何人可以用于任何目的，无需署名、无需开源、无任何限制。这是 SQLite 能被嵌入到所有商业产品中的关键原因。

## 核心设计思路

**极简主义**是 SQLite 的第一原则。整个引擎约 15 万行 C 代码（含注释约 20 万行），单一源文件编译（amalgamation），零外部依赖。与 PostgreSQL（约 150 万行）和 MySQL（约 400 万行）相比，SQLite 的代码量小了一到两个数量级。

**文件即数据库**：一个 SQLite 数据库就是一个跨平台的磁盘文件。可以用 `cp` 备份，用 U 盘传输，用 `rsync` 同步。文件格式保证向后兼容 — 2004 年创建的数据库文件在最新版本中仍可读写。

**动态类型**：SQLite 不强制列类型约束。你可以在 INTEGER 列中存入字符串，在 TEXT 列中存入数字。类型是值的属性而非列的属性。这与所有其他 SQL 数据库的静态类型系统根本不同。SQLite 使用**类型亲和性（Type Affinity）**规则决定如何存储值：INTEGER、REAL、TEXT、BLOB、NUMERIC 五种亲和性。

**无服务器**：没有独立的数据库服务进程，引擎直接链接到应用程序中。这消除了进程间通信开销，也消除了 DBA 的角色 — SQLite 的管理成本为零。

## 独特特色（其他引擎没有的）

- **动态类型 / 类型亲和性**：值的类型由值本身决定而非列定义。`CREATE TABLE t(x)` 不指定类型完全合法，x 列可以存储任意类型
- **`INTEGER PRIMARY KEY` = rowid**：声明为 `INTEGER PRIMARY KEY` 的列直接映射到 B-tree 的 rowid，无需额外索引，读写性能最优
- **`WITHOUT ROWID` 表**：覆盖索引式存储，适合复合主键且无需 rowid 的场景，减少存储开销
- **STRICT 模式（3.37+）**：`CREATE TABLE t(...) STRICT` 开启严格类型检查，不再允许类型混存。这是 SQLite 向传统数据库靠拢的可选安全网
- **FTS5 虚拟表**：内置的全文搜索引擎，支持 BM25 排序、前缀查询、近邻搜索，通过虚拟表接口透明集成
- **`ATTACH DATABASE`**：同一连接中挂载多个数据库文件，跨库查询 `SELECT * FROM db2.table1`。这是 SQLite 独有的多库能力
- **WAL 模式**：Write-Ahead Logging 允许并发读不阻塞写，写不阻塞读。性能提升巨大但仍限制为单写者
- **单文件部署**：整个数据库（Schema、数据、索引）存储在一个跨平台文件中，无需安装、配置、启停
- **公有领域许可**：世界上主流软件中少有的完全无版权限制的项目
- **`EXPLAIN` / `EXPLAIN QUERY PLAN`**：两种执行计划输出 — 底层字节码和人类可读的查询计划
- **虚拟表框架**：允许用 C 代码实现任意数据源的 SQL 查询接口（CSV 文件、操作系统信息、外部 API 等）
- **Authorizer API**：在 SQL 解析阶段逐语句审计和拦截，可以精确控制哪些操作被允许

## 已知的设计不足与历史包袱

- **单写者限制**：同一时刻只允许一个写事务。在 WAL 模式下读写可并发，但多写者仍需排队。这是 SQLite 最大的架构限制，也是它不适合高并发 Web 应用的根本原因
- **无 GRANT/REVOKE**：没有用户系统和权限管理。安全性完全依赖文件系统权限和 Authorizer API
- **无存储过程**：不支持服务端过程式编程（PL/SQL、PL/pgSQL 等）。逻辑必须在应用层实现
- **ALTER TABLE 能力弱**：3.35 前不支持 `DROP COLUMN`，至今不支持修改列类型、修改列名的某些场景。复杂表结构变更需要"建新表→拷贝数据→删旧表→重命名"的标准流程
- **无原生 DECIMAL 类型**：没有精确小数类型。`DECIMAL(10,2)` 语法被接受但实际存储为 REAL（浮点数），金融计算需要用整数（分为单位）或字符串
- **3.39 前无 RIGHT/FULL JOIN**：直到 2022 年才支持 RIGHT JOIN 和 FULL OUTER JOIN，之前只能通过调换表顺序或 UNION 模拟
- **无 LATERAL**：不支持 LATERAL JOIN / LATERAL 子查询
- **并发连接有限**：进程级文件锁限制了并发度，网络文件系统（NFS）上的 SQLite 行为不可靠
- **无 ALTER COLUMN**：不能修改已有列的类型或约束
- **日期时间无原生类型**：日期存储为 TEXT（ISO 8601）、REAL（Julian Day）或 INTEGER（Unix 时间戳），靠函数库处理

## 兼容生态

SQLite 的兼容生态围绕"分布式化"和"OLAP 化"两个方向：
- **DuckDB**：嵌入式 OLAP 引擎，被称为"分析领域的 SQLite"。SQL 方言高度接近 PostgreSQL 但部署模式像 SQLite，可以直接读取 SQLite 文件
- **Turso / libSQL**：SQLite 的分叉，增加了服务器模式、复制、多写者支持，将 SQLite 从嵌入式推向边缘计算
- **LiteFS**（Fly.io）：基于 FUSE 的 SQLite 复制方案，将 SQLite 用于分布式部署
- **rqlite**：基于 Raft 共识的分布式 SQLite
- **Litestream**：SQLite 的连续增量备份到 S3
- **cr-sqlite**：基于 CRDT 的多主 SQLite 复制

这个生态说明了一个趋势：**SQLite 正在从"嵌入式小数据库"扩展到"边缘计算和分布式场景的基础组件"**。

## 对引擎开发者的参考价值

- **类型亲和性系统**：SQLite 的五级亲和性（INTEGER/REAL/TEXT/BLOB/NUMERIC）和类型推断规则是动态类型 SQL 引擎的参考实现。如何在灵活性和安全性之间取舍，SQLite 给出了一个极端答案
- **B-tree 页面格式**：SQLite 的文件格式是数据库存储引擎的教科书案例 — 页面头、单元格指针、溢出页、自由链表，所有细节在官方文档中完全公开
- **WAL 实现**：Write-Ahead Log 的单文件实现，支持 checkpoint、busy-timeout、WAL 索引的共享内存映射。是理解 WAL 机制的最简洁参考
- **Authorizer API**：在 SQL 编译阶段逐操作授权检查的回调机制。这种设计允许宿主应用精确控制 SQL 能力（例如禁止 DELETE、只允许 SELECT 特定表），对多租户嵌入式场景极有价值
- **虚拟表框架**：通过 `xConnect/xBestIndex/xFilter` 等回调接口将任意数据源包装为 SQL 可查询的表。FTS5、JSON、CSV 都基于此框架实现，是可扩展查询引擎的设计模板
- **测试策略**：SQLite 拥有 1 亿行测试代码（测试代码量是产品代码的 600 倍以上），覆盖率达到 100% MC/DC。这是数据库引擎质量保证的极致标杆

## 全部模块

### DDL — 数据定义

| 模块 | 链接 | 简评 |
|---|---|---|
| 建表 | [sqlite.sql](../ddl/create-table/sqlite.sql) | ✗ 动态类型（FLUFFY BUNNY 也是合法类型名）；✦ STRICT(3.37+) 可选严格模式 |
| 改表 | [sqlite.sql](../ddl/alter-table/sqlite.sql) | ✗ 不支持修改列类型/ALTER COLUMN，复杂变更需建新表拷贝数据 |
| 索引 | [sqlite.sql](../ddl/indexes/sqlite.sql) | ✦ 部分索引 + 表达式索引支持，INTEGER PRIMARY KEY = rowid 零开销 |
| 约束 | [sqlite.sql](../ddl/constraints/sqlite.sql) | ✗ 外键默认关闭需 PRAGMA foreign_keys = ON，CHECK 约束基本 |
| 视图 | [sqlite.sql](../ddl/views/sqlite.sql) | ✗ 无物化视图，视图仅虚拟 |
| 序列与自增 | [sqlite.sql](../ddl/sequences/sqlite.sql) | ✦ AUTOINCREMENT 保证单调递增但有性能开销，rowid 默认自增 |
| 数据库/Schema/用户 | [sqlite.sql](../ddl/users-databases/sqlite.sql) | ✗ 无用户/权限系统；✦ ATTACH DATABASE 跨库查询独有 |

### Advanced — 高级特性

| 模块 | 链接 | 简评 |
|---|---|---|
| 动态 SQL | [sqlite.sql](../advanced/dynamic-sql/sqlite.sql) | ✗ 无服务端动态 SQL，需在应用层拼接 |
| 错误处理 | [sqlite.sql](../advanced/error-handling/sqlite.sql) | ✗ 无 TRY...CATCH，错误处理完全依赖宿主语言 |
| 执行计划 | [sqlite.sql](../advanced/explain/sqlite.sql) | ✦ EXPLAIN 输出字节码，EXPLAIN QUERY PLAN 人类可读，极致透明 |
| 锁机制 | [sqlite.sql](../advanced/locking/sqlite.sql) | ✗ 文件级锁，单写者限制；✦ WAL 模式读写并发 |
| 分区 | [sqlite.sql](../advanced/partitioning/sqlite.sql) | ✗ 不支持表分区（嵌入式定位不需要） |
| 权限 | [sqlite.sql](../advanced/permissions/sqlite.sql) | ✗ 无 GRANT/REVOKE；✦ Authorizer API 在编译阶段逐语句拦截 |
| 存储过程 | [sqlite.sql](../advanced/stored-procedures/sqlite.sql) | ✗ 不支持存储过程（嵌入式定位），逻辑在应用层实现 |
| 临时表 | [sqlite.sql](../advanced/temp-tables/sqlite.sql) | ✦ TEMP 表存于独立临时文件，ATTACH ':memory:' 内存库 |
| 事务 | [sqlite.sql](../advanced/transactions/sqlite.sql) | ✗ 文件级锁，BEGIN IMMEDIATE 避免死锁；✦ WAL 模式是关键优化 |
| 触发器 | [sqlite.sql](../advanced/triggers/sqlite.sql) | ✦ BEFORE/AFTER/INSTEAD OF 完整支持，RAISE() 抛出错误 |

### DML — 数据操作

| 模块 | 链接 | 简评 |
|---|---|---|
| 删除 | [sqlite.sql](../dml/delete/sqlite.sql) | ✦ RETURNING(3.35+) 返回被删行，VACUUM 回收空间 |
| 插入 | [sqlite.sql](../dml/insert/sqlite.sql) | ✦ RETURNING(3.35+)，INSERT OR REPLACE/IGNORE 冲突处理 |
| 更新 | [sqlite.sql](../dml/update/sqlite.sql) | ✦ RETURNING(3.35+)；✗ 无 UPDATE FROM 多表更新(3.33+才有) |
| Upsert | [sqlite.sql](../dml/upsert/sqlite.sql) | ✦ ON CONFLICT(3.24+) 语法与 PostgreSQL 兼容 |

### Functions — 内置函数

| 模块 | 链接 | 简评 |
|---|---|---|
| 聚合函数 | [sqlite.sql](../functions/aggregate/sqlite.sql) | ✗ 内置聚合函数较少，无 FILTER 子句；✦ group_concat 可用 |
| 条件函数 | [sqlite.sql](../functions/conditional/sqlite.sql) | ✦ IIF(3.32+)，标准 CASE/COALESCE/NULLIF 完整 |
| 日期函数 | [sqlite.sql](../functions/date-functions/sqlite.sql) | ✗ 无原生日期类型，date()/time()/datetime() 函数操作字符串 |
| 数学函数 | [sqlite.sql](../functions/math-functions/sqlite.sql) | ✦ 数学函数(3.35+)内置化，之前需编译扩展 |
| 字符串函数 | [sqlite.sql](../functions/string-functions/sqlite.sql) | ✗ 无正则替换，LIKE 不区分大小写默认行为因编译选项而异 |
| 类型转换 | [sqlite.sql](../functions/type-conversion/sqlite.sql) | ✗ CAST 基本可用，动态类型下类型转换语义与其他数据库不同 |

### Query — 查询

| 模块 | 链接 | 简评 |
|---|---|---|
| CTE | [sqlite.sql](../query/cte/sqlite.sql) | ✦ WITH RECURSIVE 完整支持(3.8.3+)，MATERIALIZED 提示(3.35+) |
| 全文搜索 | [sqlite.sql](../query/full-text-search/sqlite.sql) | ✦ FTS5 虚拟表内置，BM25 排序，嵌入式全文搜索最佳方案 |
| 连接查询 | [sqlite.sql](../query/joins/sqlite.sql) | ✗ 无 LATERAL JOIN；RIGHT/FULL JOIN 3.39+ 才支持 |
| 分页 | [sqlite.sql](../query/pagination/sqlite.sql) | ✦ LIMIT/OFFSET 语法最简洁 |
| 行列转换 | [sqlite.sql](../query/pivot-unpivot/sqlite.sql) | ✗ 无原生 PIVOT/UNPIVOT，需 CASE + 聚合手动模拟 |
| 集合操作 | [sqlite.sql](../query/set-operations/sqlite.sql) | ✦ UNION/INTERSECT/EXCEPT 完整支持 |
| 子查询 | [sqlite.sql](../query/subquery/sqlite.sql) | ✦ 关联子查询 + EXISTS，优化器自动展开 |
| 窗口函数 | [sqlite.sql](../query/window-functions/sqlite.sql) | ✦ 3.25+ 完整支持窗口函数，包括 NTH_VALUE 和 FILTER(3.30+) |

### Scenarios — 实战场景

| 模块 | 链接 | 简评 |
|---|---|---|
| 日期填充 | [sqlite.sql](../scenarios/date-series-fill/sqlite.sql) | ✗ 无 generate_series，需递归 CTE 模拟日期序列 |
| 去重 | [sqlite.sql](../scenarios/deduplication/sqlite.sql) | ✦ rowid 直接定位行，DELETE WHERE rowid NOT IN 简洁 |
| 区间检测 | [sqlite.sql](../scenarios/gap-detection/sqlite.sql) | ✦ 窗口函数 + 递归 CTE 配合 |
| 层级查询 | [sqlite.sql](../scenarios/hierarchical-query/sqlite.sql) | ✦ WITH RECURSIVE 标准实现 |
| JSON 展开 | [sqlite.sql](../scenarios/json-flatten/sqlite.sql) | ✗ json_each/json_tree 函数展开，无 JSON 索引；✦ JSONB(3.45+) |
| 迁移速查 | [sqlite.sql](../scenarios/migration-cheatsheet/sqlite.sql) | ✗ 动态类型 + ALTER TABLE 限制是迁移主要障碍 |
| TopN 查询 | [sqlite.sql](../scenarios/ranking-top-n/sqlite.sql) | ✦ LIMIT + 窗口函数，简洁够用 |
| 累计求和 | [sqlite.sql](../scenarios/running-total/sqlite.sql) | ✦ 窗口函数(3.25+) ROWS/RANGE 帧 |
| 缓慢变化维 | [sqlite.sql](../scenarios/slowly-changing-dim/sqlite.sql) | ✗ 无 MERGE，需 INSERT OR REPLACE + 触发器模拟 |
| 字符串拆分 | [sqlite.sql](../scenarios/string-split-to-rows/sqlite.sql) | ✗ 无原生 split 函数，需递归 CTE + substr 逐字符拆分 |
| 窗口分析 | [sqlite.sql](../scenarios/window-analytics/sqlite.sql) | ✦ 窗口函数完整支持(3.25+)，嵌入式中功能最强 |

### Types — 数据类型

| 模块 | 链接 | 简评 |
|---|---|---|
| 复合类型 | [sqlite.sql](../types/array-map-struct/sqlite.sql) | ✗ 无原生数组/结构体类型，需 JSON 模拟 |
| 日期时间 | [sqlite.sql](../types/datetime/sqlite.sql) | ✗ 无原生日期类型，TEXT/REAL/INTEGER 三种存储方式 |
| JSON | [sqlite.sql](../types/json/sqlite.sql) | ✗ TEXT 存储 + 函数查询，无索引；✦ JSONB(3.45+) 二进制格式 |
| 数值类型 | [sqlite.sql](../types/numeric/sqlite.sql) | ✗ 无精确 DECIMAL 类型，REAL 是 IEEE 754 浮点 |
| 字符串类型 | [sqlite.sql](../types/string/sqlite.sql) | ✦ TEXT 无长度限制，UTF-8 原生；✗ 排序规则有限(BINARY/NOCASE/RTRIM) |
