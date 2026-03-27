# TiDB

**分类**: 分布式数据库（兼容 MySQL）
**文件数**: 51 个 SQL 文件
**总行数**: 4374 行

## 概述与定位

TiDB 是 PingCAP 于 2015 年开源的分布式关系型数据库，目标是在一套系统中同时满足 OLTP 与 OLAP 工作负载（HTAP）。它在 SQL 层高度兼容 MySQL 协议与语法，使现有 MySQL 应用可以低成本迁移；在存储层则采用分布式 KV 引擎 TiKV 和列存引擎 TiFlash 实现水平扩展与实时分析。TiDB 定位于需要弹性伸缩、强一致事务和实时分析的互联网与金融场景。

## 历史与演进

- **2015 年**：PingCAP 成立并启动 TiDB 项目，受 Google Spanner/F1 论文启发。
- **2017 年**：TiDB 1.0 GA，基本实现 MySQL 兼容与分布式事务。
- **2019 年**：3.0 引入 TiFlash 列存引擎，正式支持 HTAP 场景。
- **2020 年**：4.0 推出 TiDB Dashboard、Placement Rules、BR 备份恢复。
- **2021 年**：5.0 引入 MPP 计算框架，TiFlash 可独立承担分析查询。
- **2022 年**：6.0 引入 Placement Rules in SQL、热点小表缓存、Top SQL。
- **2023-2024 年**：7.x 持续增强资源管控（Resource Control）、全局排序、TiDB Serverless。
- **2025 年**：8.x 强化多租户隔离、向量搜索和 AI 集成能力。

## 核心设计思路

TiDB 采用计算与存储分离的分层架构：**TiDB Server** 负责 SQL 解析和优化（无状态，可水平扩展）；**TiKV** 以 Region 为单位管理数据、通过 Multi-Raft 协议实现强一致复制；**PD (Placement Driver)** 负责元数据管理和调度。事务模型基于 Percolator（乐观/悲观两种模式），提供 Snapshot Isolation 默认隔离级别。TiFlash 作为列存副本通过 Raft Learner 实时同步数据，查询优化器可自动选择行存或列存路径。

## 独特特色

- **AUTO_RANDOM**：用随机位替代自增 ID 的高位，避免写热点集中在单一 Region。
- **TiFlash 列存引擎**：通过 `ALTER TABLE t SET TIFLASH REPLICA 1` 即可为任意表创建列存副本，优化器自动路由分析查询。
- **MPP 框架**：TiFlash 节点之间可协作完成分布式 Join 和聚合，无需额外 OLAP 引擎。
- **Placement Rules in SQL**：用 `ALTER TABLE ... PLACEMENT POLICY` 控制数据的地域分布与副本策略。
- **资源管控**：通过 Resource Control 实现多租户间 CPU/IO 配额管理。
- **AUTO_ID_CACHE**：控制自增 ID 缓存粒度，在分布式场景下平衡性能与连续性。
- **TTL 表**：支持行级 TTL，到期数据自动清理。

## 已知不足

- 与 MySQL 的兼容性仍有差异：不支持存储过程（仅实验性）、外键约束为实验特性、触发器不支持。
- 自增 ID 不保证全局连续，跨 TiDB 实例可能出现间隙和乱序。
- 全文索引不支持（需借助外部搜索引擎）。
- 单行大事务有大小限制（默认 6 MB TxnTotalSizeLimit）。
- 部分 MySQL 内置函数和系统变量尚未实现。
- TiFlash 同步存在短暂延迟，对实时性要求极高的分析场景需注意。

## 对引擎开发者的参考价值

TiDB 的架构设计为 SQL 引擎开发提供了重要参考：Raft 共识在数据库中的工程实现（Multi-Raft 分裂/合并/调度）、Percolator 分布式事务模型的生产化改进（悲观锁扩展）、行列混存的 HTAP 路由决策、以及计算层无状态设计对弹性伸缩的支撑。AUTO_RANDOM 的热点打散思路和 Placement Rules 的数据放置抽象对分布式系统设计有普遍借鉴意义。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/tidb.sql) | MySQL 兼容语法，分布式自动分片(Region)，AUTO_RANDOM 分散热点 |
| [改表](../ddl/alter-table/tidb.sql) | Online DDL 无锁(分布式)，与 MySQL 语法兼容 |
| [索引](../ddl/indexes/tidb.sql) | TiKV 分布式索引，全局/局部索引概念，聚簇索引(5.0+) |
| [约束](../ddl/constraints/tidb.sql) | PK/UNIQUE/FK(实验性) 支持，外键支持弱于 MySQL |
| [视图](../ddl/views/tidb.sql) | 普通视图(MySQL 兼容)，TiFlash 列存副本替代物化视图 |
| [序列与自增](../ddl/sequences/tidb.sql) | AUTO_INCREMENT 兼容但不保证连续，AUTO_RANDOM 分散写入热点 |
| [数据库/Schema/用户](../ddl/users-databases/tidb.sql) | MySQL 兼容权限模型，RBAC 角色支持 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/tidb.sql) | PREPARE/EXECUTE(MySQL 兼容) |
| [错误处理](../advanced/error-handling/tidb.sql) | DECLARE HANDLER(MySQL 兼容)，分布式事务错误重试 |
| [执行计划](../advanced/explain/tidb.sql) | EXPLAIN ANALYZE 带分布式算子，TiDB Dashboard 图形化 |
| [锁机制](../advanced/locking/tidb.sql) | 乐观/悲观事务(5.0+ 默认悲观)，分布式锁(TiKV) |
| [分区](../advanced/partitioning/tidb.sql) | RANGE/LIST/HASH 分区(MySQL 兼容)，与 Region 分片互补 |
| [权限](../advanced/permissions/tidb.sql) | MySQL 兼容权限+RBAC，GRANT/REVOKE 标准 |
| [存储过程](../advanced/stored-procedures/tidb.sql) | 不支持存储过程/触发器/自定义函数(MySQL 兼容差异) |
| [临时表](../advanced/temp-tables/tidb.sql) | LOCAL/GLOBAL TEMPORARY TABLE(5.3+) |
| [事务](../advanced/transactions/tidb.sql) | 分布式 ACID(Percolator 协议)，乐观/悲观模式可选 |
| [触发器](../advanced/triggers/tidb.sql) | 不支持触发器(MySQL 兼容差异点) |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/tidb.sql) | DELETE(MySQL 兼容)，分布式批量删除高效 |
| [插入](../dml/insert/tidb.sql) | INSERT/REPLACE/LOAD DATA(MySQL 兼容)，分布式并行写入 |
| [更新](../dml/update/tidb.sql) | UPDATE(MySQL 兼容)，分布式事务更新 |
| [Upsert](../dml/upsert/tidb.sql) | ON DUPLICATE KEY UPDATE/REPLACE INTO(MySQL 兼容) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/tidb.sql) | MySQL 兼容聚合，TiFlash 列存加速聚合查询 |
| [条件函数](../functions/conditional/tidb.sql) | IF/CASE/COALESCE(MySQL 兼容) |
| [日期函数](../functions/date-functions/tidb.sql) | MySQL 兼容日期函数 |
| [数学函数](../functions/math-functions/tidb.sql) | MySQL 兼容数学函数 |
| [字符串函数](../functions/string-functions/tidb.sql) | MySQL 兼容字符串函数 |
| [类型转换](../functions/type-conversion/tidb.sql) | CAST/CONVERT(MySQL 兼容)，隐式转换行为同 MySQL |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/tidb.sql) | 递归 CTE(5.1+)，WITH 标准语法 |
| [全文搜索](../query/full-text-search/tidb.sql) | 不支持 FULLTEXT 索引(MySQL 兼容差异) |
| [连接查询](../query/joins/tidb.sql) | Hash/Index/Merge JOIN，TiFlash MPP 加速大表 JOIN |
| [分页](../query/pagination/tidb.sql) | LIMIT/OFFSET(MySQL 兼容)，分布式分页有额外开销 |
| [行列转换](../query/pivot-unpivot/tidb.sql) | 无原生 PIVOT，CASE+GROUP BY(同 MySQL) |
| [集合操作](../query/set-operations/tidb.sql) | UNION/INTERSECT/EXCEPT 完整 |
| [子查询](../query/subquery/tidb.sql) | 关联子查询优化(MySQL 兼容)，分布式下推 |
| [窗口函数](../query/window-functions/tidb.sql) | 完整窗口函数支持(MySQL 兼容) |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/tidb.sql) | 递归 CTE(5.1+) 生成日期序列 |
| [去重](../scenarios/deduplication/tidb.sql) | ROW_NUMBER+CTE 去重，分布式并行 |
| [区间检测](../scenarios/gap-detection/tidb.sql) | 窗口函数检测(MySQL 兼容) |
| [层级查询](../scenarios/hierarchical-query/tidb.sql) | 递归 CTE(5.1+)，无 CONNECT BY |
| [JSON 展开](../scenarios/json-flatten/tidb.sql) | JSON_TABLE(7.0+)，JSON_EXTRACT(MySQL 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/tidb.sql) | MySQL 高度兼容，但无存储过程/触发器/FULLTEXT 是差异 |
| [TopN 查询](../scenarios/ranking-top-n/tidb.sql) | ROW_NUMBER+CTE，LIMIT(MySQL 兼容) |
| [累计求和](../scenarios/running-total/tidb.sql) | SUM() OVER 标准，TiFlash 加速分析 |
| [缓慢变化维](../scenarios/slowly-changing-dim/tidb.sql) | ON DUPLICATE KEY UPDATE(MySQL 兼容)，无 MERGE |
| [字符串拆分](../scenarios/string-split-to-rows/tidb.sql) | JSON_TABLE(7.0+) 或递归 CTE 模拟 |
| [窗口分析](../scenarios/window-analytics/tidb.sql) | 完整窗口函数(MySQL 兼容)，TiFlash 加速 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/tidb.sql) | 无 ARRAY/STRUCT，JSON 替代(MySQL 兼容) |
| [日期时间](../types/datetime/tidb.sql) | DATETIME/TIMESTAMP(MySQL 兼容)，微秒精度 |
| [JSON](../types/json/tidb.sql) | JSON 二进制存储(MySQL 兼容)，多值索引(6.6+) |
| [数值类型](../types/numeric/tidb.sql) | MySQL 兼容数值类型，DECIMAL 精确 |
| [字符串类型](../types/string/tidb.sql) | utf8mb4 推荐(同 MySQL)，CHARSET/COLLATE 兼容 |
