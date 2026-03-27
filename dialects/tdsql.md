# TDSQL

**分类**: 分布式数据库（腾讯云，兼容 MySQL）
**文件数**: 51 个 SQL 文件
**总行数**: 6083 行

## 概述与定位

TDSQL 是腾讯云自主研发的分布式数据库，兼容 MySQL 协议和语法，定位于金融、政务等对数据一致性和高可用要求极高的核心业务场景。TDSQL 脱胎于腾讯内部的分布式数据库实践，已在微信支付、腾讯金融等业务中大规模验证。它提供自动分片、分布式事务和强同步复制能力，支持从单机 MySQL 平滑迁移到分布式架构。

## 历史与演进

- **2007 年**：腾讯内部开始分布式数据库研发，服务于 QQ 和财付通等业务。
- **2014 年**：TDSQL 金融级分布式版本在微信支付上线。
- **2017 年**：作为腾讯云产品对外发布，服务外部金融客户。
- **2019 年**：推出 TDSQL-C（云原生版本，类 Aurora 架构）。
- **2020 年**：引入 Oracle 兼容模式（TDSQL PG 版）。
- **2022 年**：TDSQL 金融版通过多项金融行业认证。
- **2023-2025 年**：统一品牌为 TDSQL，持续增强分布式能力和多模兼容。

## 核心设计思路

TDSQL 分布式版采用 Shared-Nothing 架构，由三个核心组件构成：**SQL 引擎（Proxy）** 负责 SQL 解析、路由和分布式事务协调；**数据节点（SET）** 是 MySQL 实例组，每组通过强同步（半同步增强）复制保证数据不丢失；**管理节点** 负责集群调度。数据通过 **shardkey** 进行水平拆分，SQL 引擎透明地将查询路由到正确的数据节点。分布式事务基于两阶段提交（2PC）+ 全局时间戳实现。

## 独特特色

- **shardkey 分片**：建表时通过 `shardkey = column` 指定分片键，透明水平拆分。
- **广播表**：`CREATE TABLE t (...) shardkey=noshardkey_allset` 将小维度表复制到所有节点，优化 JOIN 性能。
- **强同步复制**：基于 MySQL 半同步改进，保证主备切换时 RPO=0。
- **分布式事务**：跨 SET 事务使用 2PC 保证 ACID，对应用透明。
- **全局唯一字段 (auto_increment)**：分布式场景下保证自增 ID 全局唯一（但不保证连续）。
- **TDSQL-C 云原生版**：计算存储分离的云原生架构，类似 Aurora，支持秒级扩缩容。
- **SQL 审计与合规**：内置完整的 SQL 审计日志和操作审计。

## 已知不足

- 分片表的跨分片 JOIN 和聚合查询性能受限，需要合理设计 shardkey。
- 非分片键查询需要广播到所有节点，性能退化明显。
- 与 MySQL 的兼容性在分布式特性（如全局 AUTO_INCREMENT、跨分片外键）上存在限制。
- 部分 MySQL 存储过程和触发器在分布式场景下行为可能不同。
- 仅在腾讯云上以托管服务方式提供，无法私有化部署开源版。
- 分布式版的运维复杂度高于单机 MySQL，需要理解分片和路由机制。

## 对引擎开发者的参考价值

TDSQL 展示了基于 MySQL 生态构建分布式数据库的工程路径：SQL Proxy 透明路由层的设计、shardkey 分片策略与广播表的组合优化、以及强同步复制在金融场景的实践。其从中间件模式（分库分表）演进到统一分布式数据库的历程，对理解分布式数据库架构演进有参考意义。TDSQL-C 的存算分离设计则展示了另一条云原生路径。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/tdsql.sql) | MySQL 兼容(腾讯)，分布式分片透明，ShardKey 指定分片键 |
| [改表](../ddl/alter-table/tdsql.sql) | Online DDL(MySQL 兼容)，分布式 DDL 原子 |
| [索引](../ddl/indexes/tdsql.sql) | InnoDB 索引(MySQL 兼容)，全局二级索引 |
| [约束](../ddl/constraints/tdsql.sql) | PK/FK/CHECK(MySQL 兼容)，分布式约束有限制 |
| [视图](../ddl/views/tdsql.sql) | MySQL 兼容视图 |
| [序列与自增](../ddl/sequences/tdsql.sql) | AUTO_INCREMENT(MySQL 兼容)，全局唯一自增 |
| [数据库/Schema/用户](../ddl/users-databases/tdsql.sql) | MySQL 兼容权限，分片实例管理 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/tdsql.sql) | PREPARE/EXECUTE(MySQL 兼容) |
| [错误处理](../advanced/error-handling/tdsql.sql) | DECLARE HANDLER(MySQL 兼容) |
| [执行计划](../advanced/explain/tdsql.sql) | EXPLAIN(MySQL 兼容)，分布式执行计划 |
| [锁机制](../advanced/locking/tdsql.sql) | InnoDB 行锁(MySQL 兼容)，分布式锁管理 |
| [分区](../advanced/partitioning/tdsql.sql) | ShardKey 分片(分布式)+PARTITION(MySQL 兼容) 双层 |
| [权限](../advanced/permissions/tdsql.sql) | MySQL 兼容权限模型 |
| [存储过程](../advanced/stored-procedures/tdsql.sql) | MySQL 兼容存储过程(分片限制) |
| [临时表](../advanced/temp-tables/tdsql.sql) | TEMPORARY TABLE(MySQL 兼容) |
| [事务](../advanced/transactions/tdsql.sql) | 分布式事务(XA/TCC)，强一致性，MySQL 兼容 |
| [触发器](../advanced/triggers/tdsql.sql) | MySQL 兼容触发器(分片限制) |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/tdsql.sql) | DELETE(MySQL 兼容)，分布式路由 |
| [插入](../dml/insert/tdsql.sql) | INSERT(MySQL 兼容)，ShardKey 路由写入 |
| [更新](../dml/update/tdsql.sql) | UPDATE(MySQL 兼容)，跨分片更新透明 |
| [Upsert](../dml/upsert/tdsql.sql) | ON DUPLICATE KEY UPDATE(MySQL 兼容) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/tdsql.sql) | MySQL 兼容聚合，分布式聚合下推 |
| [条件函数](../functions/conditional/tdsql.sql) | IF/CASE(MySQL 兼容) |
| [日期函数](../functions/date-functions/tdsql.sql) | MySQL 兼容日期函数 |
| [数学函数](../functions/math-functions/tdsql.sql) | MySQL 兼容数学函数 |
| [字符串函数](../functions/string-functions/tdsql.sql) | MySQL 兼容字符串函数 |
| [类型转换](../functions/type-conversion/tdsql.sql) | CAST/CONVERT(MySQL 兼容) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/tdsql.sql) | 递归 CTE(MySQL 8.0 兼容) |
| [全文搜索](../query/full-text-search/tdsql.sql) | InnoDB FULLTEXT(MySQL 兼容) |
| [连接查询](../query/joins/tdsql.sql) | MySQL 兼容 JOIN，跨分片 JOIN 自动路由 |
| [分页](../query/pagination/tdsql.sql) | LIMIT/OFFSET(MySQL 兼容) |
| [行列转换](../query/pivot-unpivot/tdsql.sql) | 无原生 PIVOT(同 MySQL) |
| [集合操作](../query/set-operations/tdsql.sql) | UNION(MySQL 兼容)，分布式 UNION |
| [子查询](../query/subquery/tdsql.sql) | MySQL 兼容子查询，分布式下推优化 |
| [窗口函数](../query/window-functions/tdsql.sql) | MySQL 8.0 兼容窗口函数 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/tdsql.sql) | 递归 CTE(MySQL 兼容) |
| [去重](../scenarios/deduplication/tdsql.sql) | ROW_NUMBER+CTE(MySQL 兼容) |
| [区间检测](../scenarios/gap-detection/tdsql.sql) | 窗口函数(MySQL 兼容) |
| [层级查询](../scenarios/hierarchical-query/tdsql.sql) | 递归 CTE(MySQL 兼容) |
| [JSON 展开](../scenarios/json-flatten/tdsql.sql) | JSON_TABLE(MySQL 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/tdsql.sql) | MySQL 兼容，ShardKey 分片设计是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/tdsql.sql) | ROW_NUMBER+LIMIT(MySQL 兼容) |
| [累计求和](../scenarios/running-total/tdsql.sql) | SUM() OVER(MySQL 兼容) |
| [缓慢变化维](../scenarios/slowly-changing-dim/tdsql.sql) | ON DUPLICATE KEY UPDATE(MySQL 兼容) |
| [字符串拆分](../scenarios/string-split-to-rows/tdsql.sql) | JSON_TABLE 或递归 CTE(MySQL 兼容) |
| [窗口分析](../scenarios/window-analytics/tdsql.sql) | MySQL 8.0 兼容窗口函数 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/tdsql.sql) | 无 ARRAY/STRUCT，JSON 替代(MySQL 兼容) |
| [日期时间](../types/datetime/tdsql.sql) | DATETIME/TIMESTAMP(MySQL 兼容) |
| [JSON](../types/json/tdsql.sql) | JSON(MySQL 兼容)，JSON_TABLE |
| [数值类型](../types/numeric/tdsql.sql) | MySQL 兼容数值类型 |
| [字符串类型](../types/string/tdsql.sql) | utf8mb4 推荐(MySQL 兼容) |
