# TimescaleDB

**分类**: 时序数据库（PostgreSQL 扩展）
**文件数**: 51 个 SQL 文件
**总行数**: 4382 行

## 概述与定位

TimescaleDB 是 Timescale 公司基于 PostgreSQL 扩展机制开发的时序数据库，以 PostgreSQL 扩展（Extension）的形式安装，完整保留 PostgreSQL 的全部 SQL 能力。它定位于 IoT 监控、DevOps 可观测性、金融行情等需要高效时序数据处理的场景。与专有时序数据库不同，TimescaleDB 的核心优势是"时序能力 + 完整 SQL"——用户不需要学习新的查询语言或放弃关系型数据库的事务和 JOIN 能力。

## 历史与演进

- **2017 年**：Timescale 公司成立并开源 TimescaleDB，作为 PG 扩展发布。
- **2018 年**：引入 Continuous Aggregates（持续聚合物化视图）。
- **2019 年**：支持多节点分布式部署（Multi-Node，后续已弃用）。
- **2020 年**：引入原生列式压缩（Compression），大幅降低存储成本。
- **2021 年**：推出 Timescale Cloud 托管服务和数据分层（Data Tiering）。
- **2022 年**：Continuous Aggregates 支持实时刷新和层级嵌套。
- **2023-2025 年**：引入 Hypercore 列存引擎、自动压缩策略优化和向量搜索能力。

## 核心设计思路

TimescaleDB 的核心抽象是 **hypertable**——一个对用户透明的自动分区表。创建 hypertable 后，数据按时间维度自动分成多个 chunk（时间分片），每个 chunk 是一个独立的 PG 表。查询时 TimescaleDB 利用 chunk 排除（类似分区裁剪）只扫描相关时间段。这种设计使插入性能不会随数据量增长而退化。由于完全基于 PG 扩展 API，所有 PG 功能（JOIN、CTE、窗口函数、事务、扩展生态）均可直接使用。

## 独特特色

- **hypertable**：`SELECT create_hypertable('metrics', 'time')` 将普通表转为自动按时间分区的超级表。
- **time_bucket()**：`time_bucket('5 minutes', time)` 灵活的时间桶聚合函数，替代 `date_trunc` 支持任意间隔。
- **Continuous Aggregates**：`CREATE MATERIALIZED VIEW ... WITH (timescaledb.continuous)` 自动增量刷新的物化视图。
- **原生压缩**：`ALTER TABLE metrics SET (timescaledb.compress)` 列式压缩旧数据，压缩率可达 90%+。
- **数据保留策略**：`SELECT add_retention_policy('metrics', INTERVAL '90 days')` 自动删除过期数据。
- **数据分层**：将冷数据自动迁移到低成本对象存储。
- **完整 PG 兼容**：JOIN、子查询、CTE、窗口函数、PostGIS 等全部可用。

## 已知不足

- 仅支持时间维度作为主分区维度，非时序场景收益有限。
- 压缩后的 chunk 不支持直接 UPDATE/DELETE（需先解压）。
- 多节点分布式方案已弃用，水平扩展依赖 Timescale Cloud 的方案。
- Continuous Aggregates 在高基数分组场景下刷新开销较大。
- 与 PG 大版本升级的兼容性需要等待扩展适配。
- 社区版（Apache 2.0）和企业版（Timescale License）功能有差异。

## 对引擎开发者的参考价值

TimescaleDB 展示了如何在不修改数据库内核的情况下通过扩展机制实现专有场景优化——这是 PostgreSQL 扩展生态的极致体现。hypertable 的自动分区和 chunk 管理设计、Continuous Aggregates 的增量物化视图实现、以及列式压缩在 PG 行存引擎上的叠加方式对扩展开发者有直接参考价值。time_bucket 函数的设计也启发了其他数据库的时间聚合函数实现。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [timescaledb.sql](../ddl/create-table/timescaledb.sql) |
| 改表 | [timescaledb.sql](../ddl/alter-table/timescaledb.sql) |
| 索引 | [timescaledb.sql](../ddl/indexes/timescaledb.sql) |
| 约束 | [timescaledb.sql](../ddl/constraints/timescaledb.sql) |
| 视图 | [timescaledb.sql](../ddl/views/timescaledb.sql) |
| 序列与自增 | [timescaledb.sql](../ddl/sequences/timescaledb.sql) |
| 数据库/Schema/用户 | [timescaledb.sql](../ddl/users-databases/timescaledb.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [timescaledb.sql](../advanced/dynamic-sql/timescaledb.sql) |
| 错误处理 | [timescaledb.sql](../advanced/error-handling/timescaledb.sql) |
| 执行计划 | [timescaledb.sql](../advanced/explain/timescaledb.sql) |
| 锁机制 | [timescaledb.sql](../advanced/locking/timescaledb.sql) |
| 分区 | [timescaledb.sql](../advanced/partitioning/timescaledb.sql) |
| 权限 | [timescaledb.sql](../advanced/permissions/timescaledb.sql) |
| 存储过程 | [timescaledb.sql](../advanced/stored-procedures/timescaledb.sql) |
| 临时表 | [timescaledb.sql](../advanced/temp-tables/timescaledb.sql) |
| 事务 | [timescaledb.sql](../advanced/transactions/timescaledb.sql) |
| 触发器 | [timescaledb.sql](../advanced/triggers/timescaledb.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [timescaledb.sql](../dml/delete/timescaledb.sql) |
| 插入 | [timescaledb.sql](../dml/insert/timescaledb.sql) |
| 更新 | [timescaledb.sql](../dml/update/timescaledb.sql) |
| Upsert | [timescaledb.sql](../dml/upsert/timescaledb.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [timescaledb.sql](../functions/aggregate/timescaledb.sql) |
| 条件函数 | [timescaledb.sql](../functions/conditional/timescaledb.sql) |
| 日期函数 | [timescaledb.sql](../functions/date-functions/timescaledb.sql) |
| 数学函数 | [timescaledb.sql](../functions/math-functions/timescaledb.sql) |
| 字符串函数 | [timescaledb.sql](../functions/string-functions/timescaledb.sql) |
| 类型转换 | [timescaledb.sql](../functions/type-conversion/timescaledb.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [timescaledb.sql](../query/cte/timescaledb.sql) |
| 全文搜索 | [timescaledb.sql](../query/full-text-search/timescaledb.sql) |
| 连接查询 | [timescaledb.sql](../query/joins/timescaledb.sql) |
| 分页 | [timescaledb.sql](../query/pagination/timescaledb.sql) |
| 行列转换 | [timescaledb.sql](../query/pivot-unpivot/timescaledb.sql) |
| 集合操作 | [timescaledb.sql](../query/set-operations/timescaledb.sql) |
| 子查询 | [timescaledb.sql](../query/subquery/timescaledb.sql) |
| 窗口函数 | [timescaledb.sql](../query/window-functions/timescaledb.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [timescaledb.sql](../scenarios/date-series-fill/timescaledb.sql) |
| 去重 | [timescaledb.sql](../scenarios/deduplication/timescaledb.sql) |
| 区间检测 | [timescaledb.sql](../scenarios/gap-detection/timescaledb.sql) |
| 层级查询 | [timescaledb.sql](../scenarios/hierarchical-query/timescaledb.sql) |
| JSON 展开 | [timescaledb.sql](../scenarios/json-flatten/timescaledb.sql) |
| 迁移速查 | [timescaledb.sql](../scenarios/migration-cheatsheet/timescaledb.sql) |
| TopN 查询 | [timescaledb.sql](../scenarios/ranking-top-n/timescaledb.sql) |
| 累计求和 | [timescaledb.sql](../scenarios/running-total/timescaledb.sql) |
| 缓慢变化维 | [timescaledb.sql](../scenarios/slowly-changing-dim/timescaledb.sql) |
| 字符串拆分 | [timescaledb.sql](../scenarios/string-split-to-rows/timescaledb.sql) |
| 窗口分析 | [timescaledb.sql](../scenarios/window-analytics/timescaledb.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [timescaledb.sql](../types/array-map-struct/timescaledb.sql) |
| 日期时间 | [timescaledb.sql](../types/datetime/timescaledb.sql) |
| JSON | [timescaledb.sql](../types/json/timescaledb.sql) |
| 数值类型 | [timescaledb.sql](../types/numeric/timescaledb.sql) |
| 字符串类型 | [timescaledb.sql](../types/string/timescaledb.sql) |
