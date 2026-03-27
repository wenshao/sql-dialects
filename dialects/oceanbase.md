# OceanBase

**分类**: 分布式数据库（兼容 MySQL/Oracle）
**文件数**: 51 个 SQL 文件
**总行数**: 4951 行

## 概述与定位

OceanBase 是蚂蚁集团自主研发的分布式关系型数据库，定位于金融级核心系统的在线交易处理（OLTP）场景。它以超大规模、高可用和强一致为核心竞争力，同时提供 MySQL 和 Oracle 双兼容模式，降低传统数据库用户的迁移成本。OceanBase 已在支付宝核心交易系统中经受多年双十一验证，连续刷新 TPC-C 和 TPC-H 基准测试世界纪录。

## 历史与演进

- **2010 年**：蚂蚁金服内部立项，目标替换 Oracle 处理海量支付交易。
- **2014 年**：OceanBase 0.5 上线支付宝核心账务系统。
- **2017 年**：1.x 发布，支持多租户和 MySQL 兼容模式。
- **2019 年**：2.x 引入 Oracle 兼容模式，打破 TPC-C 世界纪录。
- **2021 年**：3.x 开源社区版，引入 HTAP 能力和备份恢复增强。
- **2023 年**：4.x 统一架构（单机分布式一体化），大幅降低小规模部署成本。
- **2024-2025 年**：持续强化多模数据处理、向量检索和 AI 集成。

## 核心设计思路

OceanBase 采用 Shared-Nothing 架构，数据按分区（Partition）分布在多个 OBServer 节点上。每个分区通过 Paxos 协议维护多副本强一致，保证 RPO=0。**多租户**是一等公民概念——同一集群可划分多个 Tenant，每个租户拥有独立的资源配额和兼容模式（MySQL 或 Oracle）。存储层采用 LSM-Tree 结构实现高效写入，基线数据与增量数据分离（Major/Minor Compaction）。事务引擎支持两阶段提交实现跨分区事务。

## 独特特色

- **双模兼容**：同一集群中不同租户可分别运行 MySQL 模式和 Oracle 模式，SQL 语法、数据类型、PL 过程语言各自兼容。
- **Tablegroup**：将频繁 JOIN 的表分区绑定到同一节点，减少分布式事务开销。
- **Primary Zone**：控制 Leader 副本的优先分布区域，优化就近读写。
- **LSM-Tree 存储**：写入性能优异，后台 Compaction 合并，支持数据压缩达到高存储效率。
- **原生多租户**：租户间资源硬隔离（CPU/Memory/IO），单集群可服务数百租户。
- **全局时间戳服务 GTS**：确保跨分区读的全局一致性快照。
- **表级恢复与物理备份**：支持细粒度的 PITR（Point-in-Time Recovery）。

## 已知不足

- Oracle 兼容模式虽覆盖面广，但部分高级 PL/SQL 包和特性仍有差异。
- LSM-Tree 的后台 Compaction 可能导致写放大和周期性 IO 抖动。
- 社区版功能相比企业版有所裁剪（如部分高可用和运维工具）。
- 小规模部署（3 节点以下）相比单机数据库仍有一定运维复杂度，4.x 版本正在改善。
- 生态工具和第三方驱动兼容性不如 MySQL/PostgreSQL 原生生态丰富。
- 分区表数量极多时元数据管理开销增大。

## 对引擎开发者的参考价值

OceanBase 是少数将 Paxos 共识协议工程化落地到金融核心场景的数据库，其多租户资源隔离设计、LSM-Tree 在 OLTP 场景的调优经验、以及双模兼容的 SQL 引擎实现（同一优化器框架适配两套语法体系）对数据库内核开发者极具参考价值。Tablegroup 概念展示了分布式数据库中数据协同放置（co-location）对性能的关键影响。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/oceanbase.sql) | MySQL+Oracle 双兼容模式(租户级)，分布式自动分片 |
| [改表](../ddl/alter-table/oceanbase.sql) | Online DDL(无锁)，分布式原子 Schema 变更 |
| [索引](../ddl/indexes/oceanbase.sql) | 全局/局部索引，LSM-Tree 存储，聚集索引(4.x+) |
| [约束](../ddl/constraints/oceanbase.sql) | PK/FK/CHECK/UNIQUE(MySQL/Oracle 兼容) |
| [视图](../ddl/views/oceanbase.sql) | 普通视图(MySQL/Oracle 兼容)，无物化视图 |
| [序列与自增](../ddl/sequences/oceanbase.sql) | AUTO_INCREMENT(MySQL)+SEQUENCE(Oracle)，分布式自增 |
| [数据库/Schema/用户](../ddl/users-databases/oceanbase.sql) | 租户级 MySQL/Oracle 模式切换(独有)，资源隔离 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/oceanbase.sql) | PREPARE/EXECUTE(MySQL)+EXECUTE IMMEDIATE(Oracle) |
| [错误处理](../advanced/error-handling/oceanbase.sql) | DECLARE HANDLER(MySQL)+EXCEPTION(Oracle)，双模式 |
| [执行计划](../advanced/explain/oceanbase.sql) | EXPLAIN 带分布式 Exchange 信息，并行查询 |
| [锁机制](../advanced/locking/oceanbase.sql) | 行级锁+MVCC，分布式两阶段锁 |
| [分区](../advanced/partitioning/oceanbase.sql) | PARTITION BY(MySQL 兼容)，自动分片+手动分区组合 |
| [权限](../advanced/permissions/oceanbase.sql) | MySQL/Oracle 双兼容权限模型 |
| [存储过程](../advanced/stored-procedures/oceanbase.sql) | 存储过程(MySQL/Oracle 双兼容)，PL/SQL Package(Oracle 模式) |
| [临时表](../advanced/temp-tables/oceanbase.sql) | TEMPORARY TABLE(MySQL 兼容) |
| [事务](../advanced/transactions/oceanbase.sql) | 分布式 ACID 事务(Paxos)，强一致性 |
| [触发器](../advanced/triggers/oceanbase.sql) | 触发器支持(MySQL/Oracle 兼容) |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/oceanbase.sql) | DELETE(MySQL/Oracle 兼容)，分布式并行 |
| [插入](../dml/insert/oceanbase.sql) | INSERT(MySQL/Oracle 兼容)，批量导入 |
| [更新](../dml/update/oceanbase.sql) | UPDATE(MySQL/Oracle 兼容)，分布式更新 |
| [Upsert](../dml/upsert/oceanbase.sql) | ON DUPLICATE KEY UPDATE(MySQL)+MERGE(Oracle) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/oceanbase.sql) | MySQL/Oracle 兼容聚合函数 |
| [条件函数](../functions/conditional/oceanbase.sql) | IF(MySQL)/DECODE(Oracle) 双兼容 |
| [日期函数](../functions/date-functions/oceanbase.sql) | MySQL/Oracle 日期函数双兼容 |
| [数学函数](../functions/math-functions/oceanbase.sql) | MySQL/Oracle 兼容数学函数 |
| [字符串函数](../functions/string-functions/oceanbase.sql) | MySQL/Oracle 字符串函数双兼容 |
| [类型转换](../functions/type-conversion/oceanbase.sql) | CAST(MySQL)/TO_NUMBER(Oracle) 双兼容 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/oceanbase.sql) | WITH+递归 CTE 支持 |
| [全文搜索](../query/full-text-search/oceanbase.sql) | 全文索引支持(4.x+) |
| [连接查询](../query/joins/oceanbase.sql) | Hash/Nested Loop/Merge JOIN，分布式 JOIN 优化 |
| [分页](../query/pagination/oceanbase.sql) | LIMIT(MySQL)/ROWNUM+FETCH FIRST(Oracle) |
| [行列转换](../query/pivot-unpivot/oceanbase.sql) | 无原生 PIVOT(MySQL 模式)，PIVOT(Oracle 模式) |
| [集合操作](../query/set-operations/oceanbase.sql) | UNION/INTERSECT/EXCEPT 完整 |
| [子查询](../query/subquery/oceanbase.sql) | 关联子查询(MySQL/Oracle 兼容) |
| [窗口函数](../query/window-functions/oceanbase.sql) | 完整窗口函数(MySQL/Oracle 兼容) |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/oceanbase.sql) | 递归 CTE/CONNECT BY(Oracle 模式) |
| [去重](../scenarios/deduplication/oceanbase.sql) | ROW_NUMBER+CTE 去重 |
| [区间检测](../scenarios/gap-detection/oceanbase.sql) | 窗口函数检测 |
| [层级查询](../scenarios/hierarchical-query/oceanbase.sql) | 递归 CTE+CONNECT BY(Oracle 模式) |
| [JSON 展开](../scenarios/json-flatten/oceanbase.sql) | JSON_TABLE/JSON_EXTRACT(MySQL/Oracle 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/oceanbase.sql) | MySQL/Oracle 双兼容(租户级)是核心卖点，分布式透明 |
| [TopN 查询](../scenarios/ranking-top-n/oceanbase.sql) | ROW_NUMBER+LIMIT/ROWNUM(双兼容) |
| [累计求和](../scenarios/running-total/oceanbase.sql) | SUM() OVER 标准 |
| [缓慢变化维](../scenarios/slowly-changing-dim/oceanbase.sql) | ON DUPLICATE KEY(MySQL)+MERGE(Oracle) |
| [字符串拆分](../scenarios/string-split-to-rows/oceanbase.sql) | JSON_TABLE 或递归 CTE 模拟 |
| [窗口分析](../scenarios/window-analytics/oceanbase.sql) | 完整窗口函数(双兼容) |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/oceanbase.sql) | 无 ARRAY/STRUCT，JSON 替代 |
| [日期时间](../types/datetime/oceanbase.sql) | DATETIME/TIMESTAMP(MySQL)+DATE/TIMESTAMP(Oracle) |
| [JSON](../types/json/oceanbase.sql) | JSON 类型(MySQL 兼容)，JSON_TABLE |
| [数值类型](../types/numeric/oceanbase.sql) | MySQL/Oracle 兼容数值类型 |
| [字符串类型](../types/string/oceanbase.sql) | VARCHAR(MySQL)/VARCHAR2(Oracle) 双兼容 |
