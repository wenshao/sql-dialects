# PostgreSQL

**分类**: 传统关系型数据库
**文件数**: 51 个 SQL 文件
**总行数**: 9047 行

## 概述与定位

PostgreSQL 是当今功能最完善的开源关系型数据库，也是最忠实于 SQL 标准的主流实现。如果说 MySQL 的哲学是"够用就好"，PostgreSQL 的哲学就是**"做就做对"**。它在类型系统、可扩展性、并发控制、查询能力等维度上全面领先，是学术研究成果转化为工业实践的典范。

PostgreSQL 的定位近年发生了显著变化：从"那个功能更强但更难用的 MySQL 替代品"，变成了**数据库领域的事实标准接口**。CockroachDB、YugabyteDB、Greenplum、甚至 DuckDB 都选择兼容 PostgreSQL 而非 MySQL，原因很简单 — PostgreSQL 的类型系统和 SQL 方言更完整、更严谨，兼容它意味着更高的功能覆盖度。

## 历史与演进

- **1986**: Michael Stonebraker 在 UC Berkeley 启动 Postgres 项目（post-Ingres），研究面向对象关系模型
- **1994**: Andrew Yu 和 Jolly Chen 添加 SQL 语言支持，改名 Postgres95
- **1996**: 正式更名 PostgreSQL，采用 BSD 许可证，社区接管开发
- **2000s**: 逐步补齐企业级功能 — WAL（8.0）、自动清理（8.1）、热备份（8.2）
- **2010**: PG 9.0 引入流复制和热备，结束"不适合生产"的偏见
- **2012**: PG 9.2 引入 JSON 类型和索引覆盖扫描
- **2014**: PG 9.4 引入 JSONB — 二进制 JSON 存储，改变了文档数据库的竞争格局
- **2016**: PG 9.6 引入并行查询，分析性能飞跃
- **2017**: PG 10 引入声明式分区、逻辑复制 — 版本号改为主版本制
- **2020**: PG 13 引入增量排序、B-tree 去重
- **2022**: PG 15 引入 MERGE 语句（终于支持标准 SQL MERGE）
- **2024**: PG 17 增量备份、改进 VACUUM
- **2025**: PG 18 预计引入异步 I/O 和进一步并行改进

PostgreSQL 的演进节奏极其稳定：**每年一个大版本，从不跳票**。这种可预测性在开源项目中极为罕见。

## 核心设计思路

**可扩展性至上**是 PostgreSQL 的第一设计原则。几乎所有子系统都可以通过扩展机制定制：
- **Extension 框架**：`CREATE EXTENSION` 一键加载功能模块（PostGIS、pg_trgm、hstore 等），无需重编译
- **自定义类型**：不仅能定义新类型，还能为其定义运算符、索引策略、类型转换规则
- **自定义索引方法**：GiST、GIN、BRIN、SP-GiST 框架允许第三方实现全新索引结构
- **自定义函数语言**：PL/pgSQL 只是起点，可加载 PL/Python、PL/V8（JavaScript）、PL/Rust

**类型严格**：PostgreSQL 不做隐式类型转换。`WHERE int_col = '123'` 在 MySQL 中正常，在 PostgreSQL 中需要显式转换。这避免了大量隐式转换导致的索引失效问题。

**DDL 事务性**：`CREATE TABLE`、`ALTER TABLE`、`DROP TABLE` 都可以在事务中执行并回滚。这是 PostgreSQL 相对于 MySQL 和 Oracle 的重大优势，使得数据库迁移脚本可以做到原子性。

**MVCC 元组版本化**：每个 UPDATE 不是原地修改，而是写入新版本元组并标记旧版本为死亡。这带来了极好的读写并发（读永不阻塞写），但代价是需要 VACUUM 回收死元组。

## 独特特色（其他引擎没有的）

- **JSONB + GIN 索引**：二进制 JSON 存储 + 倒排索引，使 PostgreSQL 成为唯一能与 MongoDB 正面竞争的关系型数据库
- **`::` 类型转换运算符**：`'2024-01-01'::date`，比 `CAST(x AS date)` 简洁得多
- **`$$` Dollar Quoting**：`$$函数体$$`，彻底解决字符串中单引号转义问题
- **`RETURNING` 子句**：INSERT/UPDATE/DELETE 直接返回被影响的行，避免额外查询
- **`FILTER` 子句**：`COUNT(*) FILTER (WHERE status = 'active')`，条件聚合的优雅写法
- **`generate_series()`**：生成整数/时间序列的表函数，填充日期维度的利器
- **部分索引**：`CREATE INDEX ON t(col) WHERE status = 'active'`，只索引满足条件的行
- **EXCLUDE 约束**：基于 GiST 索引的排斥约束，可表达"时间区间不重叠"等复杂业务规则
- **Row Level Security (RLS)**：行级安全策略，多租户数据隔离的内核级方案
- **Advisory Locks**：应用层分布式锁，无需额外中间件
- **可写 CTE**：`WITH deleted AS (DELETE FROM t RETURNING *) INSERT INTO archive SELECT * FROM deleted`
- **`DISTINCT ON`**：按指定列去重并保留整行，比 `ROW_NUMBER()` 子查询简洁

## 已知的设计不足与历史包袱

- **VACUUM 是永恒的话题**：元组版本化的 MVCC 要求定期回收死元组。虽然 autovacuum 已经很成熟，但大表的 VACUUM 仍会消耗显著 I/O，长事务会阻止 VACUUM 回收
- **无原生连接池**：PostgreSQL 的进程模型（每连接一个进程）在高并发短连接场景下需要 PgBouncer 等外部连接池。MySQL 的线程模型在这方面天然优势
- **无 PACKAGE（Oracle 有）**：PL/pgSQL 没有 Package 概念，无法将相关函数/过程/类型打包为一个逻辑单元
- **PG 11 前 ADD COLUMN WITH DEFAULT 需重写全表**：这个问题持续了 20 年，直到 PG 11 才修复。在此之前，给大表加有默认值的列是噩梦
- **无 TRY_CAST**：直到目前仍无内置的安全类型转换函数，需要自定义函数包装异常处理
- **XID 回卷风险**：32 位事务 ID 在极高写入量下可能回卷，需要定期 VACUUM FREEZE。PG 近年版本持续改进这个问题
- **逻辑复制限制**：不复制 DDL、不支持所有数据类型，仍在逐版本完善
- **升级需要 pg_upgrade 或逻辑复制**：不支持小版本间的原地滚动升级（与 MySQL 类似）

## 兼容生态

PostgreSQL 协议已成为新一代数据库的"通用语言"：
- **CockroachDB**：分布式 SQL，PostgreSQL 协议兼容，强一致性
- **YugabyteDB**：分布式 SQL，PostgreSQL 兼容，Google Spanner 开源替代
- **Greenplum**：基于 PostgreSQL 的 MPP 分析型数据库
- **Amazon Redshift**：最早基于 PostgreSQL 8.x 分叉的云数据仓库
- **openGauss**（华为）：基于 PostgreSQL 的国产数据库
- **Hologres**（阿里云）：HSAP 引擎，PostgreSQL 协议
- **TimescaleDB**：PostgreSQL Extension，时序数据专用
- **Materialize**：流式物化视图，PostgreSQL 协议
- **DuckDB**：嵌入式 OLAP，SQL 方言高度接近 PostgreSQL
- **Supabase**：基于 PostgreSQL 的 Firebase 替代品

## 对引擎开发者的参考价值

- **TOAST（The Oversized-Attribute Storage Technique）**：大值自动压缩/离线存储，对应用完全透明。这是处理变长大字段的优雅方案
- **GIN/GiST 索引框架**：通用倒排索引（GIN）和通用搜索树（GiST）是可扩展索引的教科书实现，支撑了全文搜索、JSONB 查询、地理空间等完全不同的索引需求
- **SSI（Serializable Snapshot Isolation）**：PostgreSQL 9.1 实现了基于快照隔离的可串行化，无需传统的两阶段锁，性能远优于锁式 SERIALIZABLE
- **Extension 架构**：hook 机制 + 共享内存 + SPI（Server Programming Interface）组成的扩展框架，允许在不修改内核的情况下添加新数据类型、索引方法、查询计划节点甚至安全策略
- **进程模型 vs 线程模型**：PostgreSQL 坚持多进程架构（每连接一进程），稳定性极强但内存开销大。这与 MySQL 的多线程模型形成对照，是数据库架构设计的经典权衡
- **规则系统（Rule System）**：虽然实际中已被触发器取代，但其"查询重写"的设计思想影响了物化视图刷新等后续特性

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/postgres.md) | IDENTITY(10+) 替代 SERIAL，TEXT=VARCHAR 无性能差异，DDL 可回滚 |
| [改表](../ddl/alter-table/postgres.md) | DDL 事务性可回滚（最大优势），ADD COLUMN WITH DEFAULT 11+ 秒级 |
| [索引](../ddl/indexes/postgres.md) | GiST/GIN/BRIN/SP-GiST 四框架，部分索引，CONCURRENTLY 不锁表 |
| [约束](../ddl/constraints/postgres.md) | EXCLUDE 排斥约束独有，CHECK/FK 完整，延迟约束支持 |
| [视图](../ddl/views/postgres.md) | 物化视图 REFRESH CONCURRENTLY，无自动增量刷新 |
| [序列与自增](../ddl/sequences/postgres.md) | IDENTITY(10+) 推荐，传统 SERIAL 仍可用，SEQUENCE 灵活 |
| [数据库/Schema/用户](../ddl/users-databases/postgres.md) | Schema 多租户隔离，RLS 行级安全策略，pg_hba.conf 认证 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/postgres.md) | EXECUTE format() 防注入，PL/pgSQL 内嵌动态 SQL |
| [错误处理](../advanced/error-handling/postgres.md) | EXCEPTION WHEN 块，SQLSTATE 标准错误码，GET STACKED DIAGNOSTICS |
| [执行计划](../advanced/explain/postgres.md) | EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)，pg_stat_statements 统计 |
| [锁机制](../advanced/locking/postgres.md) | Advisory Locks 独有，行锁+表锁，无锁升级，读不阻塞写 |
| [分区](../advanced/partitioning/postgres.md) | 声明式分区(10+)，支持 RANGE/LIST/HASH，分区可独立索引 |
| [权限](../advanced/permissions/postgres.md) | RLS 行级安全策略，GRANT/REVOKE 标准，pg_hba.conf 认证链 |
| [存储过程](../advanced/stored-procedures/postgres.md) | PL/pgSQL + PL/Python/PL/V8 多语言，无 Package，$$ 引用 |
| [临时表](../advanced/temp-tables/postgres.md) | ON COMMIT DROP/DELETE ROWS，会话级临时表，不需预定义 |
| [事务](../advanced/transactions/postgres.md) | SSI 可串行化(9.1+)，DDL 事务性，Advisory Locks，Savepoint |
| [触发器](../advanced/triggers/postgres.md) | BEFORE/AFTER/INSTEAD OF 完整，行级+语句级，事件触发器(9.3+) |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/postgres.md) | RETURNING 返回被删行，USING 多表删除，可事务回滚 |
| [插入](../dml/insert/postgres.md) | RETURNING 子句独有优势，COPY 批量导入，INSERT...SELECT |
| [更新](../dml/update/postgres.md) | UPDATE...FROM 多表更新，RETURNING 返回更新后行 |
| [Upsert](../dml/upsert/postgres.md) | ON CONFLICT DO UPDATE(9.5+)，可指定冲突列或约束名 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/postgres.md) | FILTER 子句独有优雅，GROUPING SETS/CUBE/ROLLUP 完整 |
| [条件函数](../functions/conditional/postgres.md) | 标准 CASE，COALESCE/NULLIF，布尔类型原生支持 |
| [日期函数](../functions/date-functions/postgres.md) | INTERVAL 类型丰富，generate_series 生成时间序列，age() 计算差值 |
| [数学函数](../functions/math-functions/postgres.md) | 完整数学函数库，NUMERIC 任意精度 |
| [字符串函数](../functions/string-functions/postgres.md) | || 拼接标准，regexp_match/replace，string_agg 聚合 |
| [类型转换](../functions/type-conversion/postgres.md) | :: 运算符简洁，严格类型不做隐式转换，无 TRY_CAST |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/postgres.md) | 可写 CTE 独有(INSERT/UPDATE/DELETE)，MATERIALIZED 提示(12+) |
| [全文搜索](../query/full-text-search/postgres.md) | tsvector/tsquery+GIN 内置，pg_trgm 模糊匹配，多语言分词 |
| [连接查询](../query/joins/postgres.md) | LATERAL JOIN 标准支持，全连接类型，Hash/Merge/Nested Loop |
| [分页](../query/pagination/postgres.md) | LIMIT/OFFSET 标准，Keyset 分页性能更优 |
| [行列转换](../query/pivot-unpivot/postgres.md) | crosstab(tablefunc 扩展)，无原生 PIVOT 语法 |
| [集合操作](../query/set-operations/postgres.md) | UNION/INTERSECT/EXCEPT 完整，支持 ALL 变体 |
| [子查询](../query/subquery/postgres.md) | LATERAL 子查询(9.3+)，ANY/ALL/EXISTS 标准 |
| [窗口函数](../query/window-functions/postgres.md) | 8.4 起支持，FILTER 子句，GROUPS 帧类型(11+)，完整实现 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/postgres.md) | generate_series(date,date,interval) 原生支持，最简方案 |
| [去重](../scenarios/deduplication/postgres.md) | DISTINCT ON 独有简洁写法，或 ROW_NUMBER+CTE |
| [区间检测](../scenarios/gap-detection/postgres.md) | generate_series 填充+LEFT JOIN 检测，窗口函数辅助 |
| [层级查询](../scenarios/hierarchical-query/postgres.md) | 递归 CTE 标准实现，无 CONNECT BY，ltree 扩展可用 |
| [JSON 展开](../scenarios/json-flatten/postgres.md) | JSONB+GIN 索引（最强实现），json_to_recordset，JSON_TABLE(17+) |
| [迁移速查](../scenarios/migration-cheatsheet/postgres.md) | 类型严格需注意隐式转换差异，DDL 可回滚是优势 |
| [TopN 查询](../scenarios/ranking-top-n/postgres.md) | DISTINCT ON 分组取一，FETCH FIRST WITH TIES(13+) |
| [累计求和](../scenarios/running-total/postgres.md) | SUM() OVER 标准，8.4 起即支持窗口函数 |
| [缓慢变化维](../scenarios/slowly-changing-dim/postgres.md) | MERGE(15+) 较晚到达，之前用 INSERT...ON CONFLICT |
| [字符串拆分](../scenarios/string-split-to-rows/postgres.md) | string_to_table(14+)，regexp_split_to_table，unnest+string_to_array |
| [窗口分析](../scenarios/window-analytics/postgres.md) | 窗口函数完整，FILTER 子句，GROUPS 帧(11+)，NTH_VALUE 支持 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/postgres.md) | 原生 ARRAY 类型+运算符，自定义复合类型，hstore 扩展 |
| [日期时间](../types/datetime/postgres.md) | TIMESTAMP WITH/WITHOUT TZ，INTERVAL 类型丰富，无 2038 问题 |
| [JSON](../types/json/postgres.md) | JSONB+GIN 索引（最强实现），JSON_TABLE(17+)，jsonpath 查询 |
| [数值类型](../types/numeric/postgres.md) | NUMERIC 任意精度，SMALLINT/INT/BIGINT 标准，无 UNSIGNED |
| [字符串类型](../types/string/postgres.md) | TEXT=VARCHAR 无性能差异，字符语义默认，排序规则灵活 |
