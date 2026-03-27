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

| 模块 | 链接 |
|---|---|
| 建表 | [tdsql.sql](../ddl/create-table/tdsql.sql) |
| 改表 | [tdsql.sql](../ddl/alter-table/tdsql.sql) |
| 索引 | [tdsql.sql](../ddl/indexes/tdsql.sql) |
| 约束 | [tdsql.sql](../ddl/constraints/tdsql.sql) |
| 视图 | [tdsql.sql](../ddl/views/tdsql.sql) |
| 序列与自增 | [tdsql.sql](../ddl/sequences/tdsql.sql) |
| 数据库/Schema/用户 | [tdsql.sql](../ddl/users-databases/tdsql.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [tdsql.sql](../advanced/dynamic-sql/tdsql.sql) |
| 错误处理 | [tdsql.sql](../advanced/error-handling/tdsql.sql) |
| 执行计划 | [tdsql.sql](../advanced/explain/tdsql.sql) |
| 锁机制 | [tdsql.sql](../advanced/locking/tdsql.sql) |
| 分区 | [tdsql.sql](../advanced/partitioning/tdsql.sql) |
| 权限 | [tdsql.sql](../advanced/permissions/tdsql.sql) |
| 存储过程 | [tdsql.sql](../advanced/stored-procedures/tdsql.sql) |
| 临时表 | [tdsql.sql](../advanced/temp-tables/tdsql.sql) |
| 事务 | [tdsql.sql](../advanced/transactions/tdsql.sql) |
| 触发器 | [tdsql.sql](../advanced/triggers/tdsql.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [tdsql.sql](../dml/delete/tdsql.sql) |
| 插入 | [tdsql.sql](../dml/insert/tdsql.sql) |
| 更新 | [tdsql.sql](../dml/update/tdsql.sql) |
| Upsert | [tdsql.sql](../dml/upsert/tdsql.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [tdsql.sql](../functions/aggregate/tdsql.sql) |
| 条件函数 | [tdsql.sql](../functions/conditional/tdsql.sql) |
| 日期函数 | [tdsql.sql](../functions/date-functions/tdsql.sql) |
| 数学函数 | [tdsql.sql](../functions/math-functions/tdsql.sql) |
| 字符串函数 | [tdsql.sql](../functions/string-functions/tdsql.sql) |
| 类型转换 | [tdsql.sql](../functions/type-conversion/tdsql.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [tdsql.sql](../query/cte/tdsql.sql) |
| 全文搜索 | [tdsql.sql](../query/full-text-search/tdsql.sql) |
| 连接查询 | [tdsql.sql](../query/joins/tdsql.sql) |
| 分页 | [tdsql.sql](../query/pagination/tdsql.sql) |
| 行列转换 | [tdsql.sql](../query/pivot-unpivot/tdsql.sql) |
| 集合操作 | [tdsql.sql](../query/set-operations/tdsql.sql) |
| 子查询 | [tdsql.sql](../query/subquery/tdsql.sql) |
| 窗口函数 | [tdsql.sql](../query/window-functions/tdsql.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [tdsql.sql](../scenarios/date-series-fill/tdsql.sql) |
| 去重 | [tdsql.sql](../scenarios/deduplication/tdsql.sql) |
| 区间检测 | [tdsql.sql](../scenarios/gap-detection/tdsql.sql) |
| 层级查询 | [tdsql.sql](../scenarios/hierarchical-query/tdsql.sql) |
| JSON 展开 | [tdsql.sql](../scenarios/json-flatten/tdsql.sql) |
| 迁移速查 | [tdsql.sql](../scenarios/migration-cheatsheet/tdsql.sql) |
| TopN 查询 | [tdsql.sql](../scenarios/ranking-top-n/tdsql.sql) |
| 累计求和 | [tdsql.sql](../scenarios/running-total/tdsql.sql) |
| 缓慢变化维 | [tdsql.sql](../scenarios/slowly-changing-dim/tdsql.sql) |
| 字符串拆分 | [tdsql.sql](../scenarios/string-split-to-rows/tdsql.sql) |
| 窗口分析 | [tdsql.sql](../scenarios/window-analytics/tdsql.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [tdsql.sql](../types/array-map-struct/tdsql.sql) |
| 日期时间 | [tdsql.sql](../types/datetime/tdsql.sql) |
| JSON | [tdsql.sql](../types/json/tdsql.sql) |
| 数值类型 | [tdsql.sql](../types/numeric/tdsql.sql) |
| 字符串类型 | [tdsql.sql](../types/string/tdsql.sql) |
