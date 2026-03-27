# TDengine

**分类**: 时序数据库（涛思数据）
**文件数**: 51 个 SQL 文件
**总行数**: 4093 行

## 概述与定位

TDengine 是涛思数据（TAOS Data）于 2019 年开源的高性能时序数据库，专门为 IoT、工业互联网和运维监控等海量时序数据场景设计。与通用关系型数据库不同，TDengine 围绕"一个设备/采集点一张表"的数据模型重新设计了存储引擎和查询语言，追求极致的写入速度和查询性能。它内置了流式计算、缓存和数据订阅能力，目标是替代"时序数据库 + 消息队列 + 缓存"的传统架构组合。

## 历史与演进

- **2017 年**：涛思数据公司成立，启动 TDengine 研发。
- **2019 年 7 月**：TDengine 开源，首日获得 GitHub 数千 Star。
- **2020 年**：2.0 引入集群支持和多副本复制。
- **2021 年**：增强 SQL 兼容性和用户自定义函数（UDF）。
- **2022 年**：3.0 重大重构——引入存储计算分离、流计算引擎和 Vnode/Mnode 新架构。
- **2023-2025 年**：持续优化分布式性能、增强 SQL 兼容性和云服务能力。

## 核心设计思路

TDengine 的数据模型围绕**超级表（Super Table）、子表（Sub Table）和标签（Tag）** 三层抽象设计。超级表定义数据 Schema 和标签 Schema；每个采集点（设备/传感器）对应一张子表，子表通过标签值与超级表关联。查询时可按标签过滤子表（类似维度筛选），也可对超级表做聚合（自动跨所有子表计算）。存储引擎针对时序数据优化——数据按时间戳排序、列式存储、高效压缩，每个子表的最新值自动缓存（替代 Redis 的角色）。

## 独特特色

- **超级表/子表/标签模型**：`CREATE STABLE meters (ts TIMESTAMP, voltage FLOAT) TAGS (location NCHAR(64), groupId INT)` 定义设备模板。
- **INTERVAL/SLIDING/FILL**：`SELECT AVG(voltage) FROM meters INTERVAL(10m) SLIDING(5m) FILL(PREV)` 滑动窗口聚合并自动填充缺失值。
- **CSUM/TWA/IRATE**：内置时序专用函数——累积求和（CSUM）、时间加权平均（TWA）、瞬时变化率（IRATE）。
- **数据订阅**：消费者组模式订阅数据变更，替代外部消息队列。
- **流式计算**：`CREATE STREAM` 定义实时流计算管道，支持滑动窗口和事件窗口。
- **数据保留策略**：`CREATE DATABASE ... KEEP 365` 自动过期删除。
- **最新值缓存**：每个子表的最新一行数据自动缓存在内存中，用 `LAST_ROW()` 查询。

## 已知不足

- SQL 语法与标准 SQL 差异较大——不支持 JOIN（3.0 开始有限支持）、子查询能力有限。
- 不支持事务（ACID），无法用于需要事务保证的通用 OLTP 场景。
- UPDATE 和 DELETE 能力有限（3.0 开始改善，但仍非核心设计目标）。
- 每个数据库所有表必须共享相同的时间精度（毫秒/微秒/纳秒）。
- 标签值修改需要整表操作，动态标签管理不够灵活。
- 非时序查询场景（如全文搜索、复杂关联分析）需要借助外部系统。

## 对引擎开发者的参考价值

TDengine 的"一设备一表"数据模型是时序数据库领域的独特设计——通过超级表+标签将设备元数据与时序数据绑定，避免了通用数据库中高基数 GROUP BY 的性能问题。其列式存储 + 时间排序 + 针对性压缩的存储引擎设计展示了领域特化的存储优化。内置流计算和数据订阅的"一站式"设计思路也代表了从单一数据库向数据平台演进的趋势。

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [tdengine.sql](../ddl/create-table/tdengine.sql) |
| 改表 | [tdengine.sql](../ddl/alter-table/tdengine.sql) |
| 索引 | [tdengine.sql](../ddl/indexes/tdengine.sql) |
| 约束 | [tdengine.sql](../ddl/constraints/tdengine.sql) |
| 视图 | [tdengine.sql](../ddl/views/tdengine.sql) |
| 序列与自增 | [tdengine.sql](../ddl/sequences/tdengine.sql) |
| 数据库/Schema/用户 | [tdengine.sql](../ddl/users-databases/tdengine.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [tdengine.sql](../advanced/dynamic-sql/tdengine.sql) |
| 错误处理 | [tdengine.sql](../advanced/error-handling/tdengine.sql) |
| 执行计划 | [tdengine.sql](../advanced/explain/tdengine.sql) |
| 锁机制 | [tdengine.sql](../advanced/locking/tdengine.sql) |
| 分区 | [tdengine.sql](../advanced/partitioning/tdengine.sql) |
| 权限 | [tdengine.sql](../advanced/permissions/tdengine.sql) |
| 存储过程 | [tdengine.sql](../advanced/stored-procedures/tdengine.sql) |
| 临时表 | [tdengine.sql](../advanced/temp-tables/tdengine.sql) |
| 事务 | [tdengine.sql](../advanced/transactions/tdengine.sql) |
| 触发器 | [tdengine.sql](../advanced/triggers/tdengine.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [tdengine.sql](../dml/delete/tdengine.sql) |
| 插入 | [tdengine.sql](../dml/insert/tdengine.sql) |
| 更新 | [tdengine.sql](../dml/update/tdengine.sql) |
| Upsert | [tdengine.sql](../dml/upsert/tdengine.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [tdengine.sql](../functions/aggregate/tdengine.sql) |
| 条件函数 | [tdengine.sql](../functions/conditional/tdengine.sql) |
| 日期函数 | [tdengine.sql](../functions/date-functions/tdengine.sql) |
| 数学函数 | [tdengine.sql](../functions/math-functions/tdengine.sql) |
| 字符串函数 | [tdengine.sql](../functions/string-functions/tdengine.sql) |
| 类型转换 | [tdengine.sql](../functions/type-conversion/tdengine.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [tdengine.sql](../query/cte/tdengine.sql) |
| 全文搜索 | [tdengine.sql](../query/full-text-search/tdengine.sql) |
| 连接查询 | [tdengine.sql](../query/joins/tdengine.sql) |
| 分页 | [tdengine.sql](../query/pagination/tdengine.sql) |
| 行列转换 | [tdengine.sql](../query/pivot-unpivot/tdengine.sql) |
| 集合操作 | [tdengine.sql](../query/set-operations/tdengine.sql) |
| 子查询 | [tdengine.sql](../query/subquery/tdengine.sql) |
| 窗口函数 | [tdengine.sql](../query/window-functions/tdengine.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [tdengine.sql](../scenarios/date-series-fill/tdengine.sql) |
| 去重 | [tdengine.sql](../scenarios/deduplication/tdengine.sql) |
| 区间检测 | [tdengine.sql](../scenarios/gap-detection/tdengine.sql) |
| 层级查询 | [tdengine.sql](../scenarios/hierarchical-query/tdengine.sql) |
| JSON 展开 | [tdengine.sql](../scenarios/json-flatten/tdengine.sql) |
| 迁移速查 | [tdengine.sql](../scenarios/migration-cheatsheet/tdengine.sql) |
| TopN 查询 | [tdengine.sql](../scenarios/ranking-top-n/tdengine.sql) |
| 累计求和 | [tdengine.sql](../scenarios/running-total/tdengine.sql) |
| 缓慢变化维 | [tdengine.sql](../scenarios/slowly-changing-dim/tdengine.sql) |
| 字符串拆分 | [tdengine.sql](../scenarios/string-split-to-rows/tdengine.sql) |
| 窗口分析 | [tdengine.sql](../scenarios/window-analytics/tdengine.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [tdengine.sql](../types/array-map-struct/tdengine.sql) |
| 日期时间 | [tdengine.sql](../types/datetime/tdengine.sql) |
| JSON | [tdengine.sql](../types/json/tdengine.sql) |
| 数值类型 | [tdengine.sql](../types/numeric/tdengine.sql) |
| 字符串类型 | [tdengine.sql](../types/string/tdengine.sql) |
