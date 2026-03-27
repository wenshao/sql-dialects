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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/tdengine.sql) | 时序数据库，超级表+子表模型(Tag 标签分类)，自动建表 |
| [改表](../ddl/alter-table/tdengine.sql) | ALTER ADD TAG/COLUMN，超级表结构变更自动同步子表 |
| [索引](../ddl/indexes/tdengine.sql) | SMA 预计算索引(独有)，Tag 索引，时间列自动索引 |
| [约束](../ddl/constraints/tdengine.sql) | 无传统约束(时序引擎)，TIMESTAMP 主键必须 |
| [视图](../ddl/views/tdengine.sql) | Stream 流式计算替代视图(无传统 VIEW) |
| [序列与自增](../ddl/sequences/tdengine.sql) | 无 SEQUENCE，TIMESTAMP 主键天然有序 |
| [数据库/Schema/用户](../ddl/users-databases/tdengine.sql) | Database 级别隔离+VNODE 分片，用户权限 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/tdengine.sql) | 无动态 SQL(时序引擎定位) |
| [错误处理](../advanced/error-handling/tdengine.sql) | 无过程式错误处理 |
| [执行计划](../advanced/explain/tdengine.sql) | EXPLAIN 查看执行计划 |
| [锁机制](../advanced/locking/tdengine.sql) | 无行级锁(时序追加写入)，VNODE 级别并发 |
| [分区](../advanced/partitioning/tdengine.sql) | 自动按时间分 VNODE(核心)，超级表按 Tag 分组 |
| [权限](../advanced/permissions/tdengine.sql) | 用户+权限管理，READ/WRITE/ALL |
| [存储过程](../advanced/stored-procedures/tdengine.sql) | 无存储过程，UDF(C/Python) 支持 |
| [临时表](../advanced/temp-tables/tdengine.sql) | 无临时表(时序引擎) |
| [事务](../advanced/transactions/tdengine.sql) | 无传统事务(时序追加写入，最终一致性) |
| [触发器](../advanced/triggers/tdengine.sql) | Stream 流式计算替代触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/tdengine.sql) | DELETE 按时间范围删除，不支持条件删除单行 |
| [插入](../dml/insert/tdengine.sql) | INSERT 多行/多表批量写入(独有高效语法) |
| [更新](../dml/update/tdengine.sql) | 相同时间戳 INSERT 覆盖(时序 Upsert 语义) |
| [Upsert](../dml/upsert/tdengine.sql) | INSERT 相同时间戳自动覆盖(时序天然 Upsert) |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/tdengine.sql) | APERTURE/CSUM/DERIVATIVE/IRATE 时序聚合(独有) |
| [条件函数](../functions/conditional/tdengine.sql) | IF/CASE 基础支持 |
| [日期函数](../functions/date-functions/tdengine.sql) | NOW/TIMETRUNCATE/TIMEDIFF 时序时间函数 |
| [数学函数](../functions/math-functions/tdengine.sql) | 基础数学函数+SPREAD/TWA 时序计算(独有) |
| [字符串函数](../functions/string-functions/tdengine.sql) | CONCAT/SUBSTR/LENGTH 基础函数 |
| [类型转换](../functions/type-conversion/tdengine.sql) | CAST 基础转换 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/tdengine.sql) | 不支持 CTE |
| [全文搜索](../query/full-text-search/tdengine.sql) | 不支持全文搜索(时序引擎) |
| [连接查询](../query/joins/tdengine.sql) | JOIN 有限支持(超级表+子表)，无复杂 JOIN |
| [分页](../query/pagination/tdengine.sql) | LIMIT/OFFSET 标准，SLIMIT/SOFFSET 超级表分组分页(独有) |
| [行列转换](../query/pivot-unpivot/tdengine.sql) | 无 PIVOT 支持 |
| [集合操作](../query/set-operations/tdengine.sql) | UNION/UNION ALL 支持 |
| [子查询](../query/subquery/tdengine.sql) | 嵌套子查询支持(有限) |
| [窗口函数](../query/window-functions/tdengine.sql) | STATE_WINDOW/SESSION_WINDOW/EVENT_WINDOW 时序窗口(独有) |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/tdengine.sql) | FILL(PREV/NEXT/LINEAR/VALUE) 时序填充(独有核心功能) |
| [去重](../scenarios/deduplication/tdengine.sql) | UNIQUE 函数(独有)，按列去重取最新 |
| [区间检测](../scenarios/gap-detection/tdengine.sql) | INTERVAL+FILL 检测时序间隙(独有) |
| [层级查询](../scenarios/hierarchical-query/tdengine.sql) | 不支持(时序引擎) |
| [JSON 展开](../scenarios/json-flatten/tdengine.sql) | TAG 为 JSON 类型时可查询，JSON_EXTRACT |
| [迁移速查](../scenarios/migration-cheatsheet/tdengine.sql) | 超级表/子表模型+时序语法+无事务是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/tdengine.sql) | TOP/BOTTOM 函数(独有)，取极值行 |
| [累计求和](../scenarios/running-total/tdengine.sql) | CSUM 累计求和函数(独有) |
| [缓慢变化维](../scenarios/slowly-changing-dim/tdengine.sql) | 不适用(时序引擎) |
| [字符串拆分](../scenarios/string-split-to-rows/tdengine.sql) | 不支持字符串拆分展开 |
| [窗口分析](../scenarios/window-analytics/tdengine.sql) | INTERVAL/STATE/SESSION/EVENT_WINDOW 时序窗口(独有) |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/tdengine.sql) | 无 ARRAY/STRUCT，TAG 支持 JSON |
| [日期时间](../types/datetime/tdengine.sql) | TIMESTAMP 纳秒精度(核心类型)，无 DATE/TIME |
| [JSON](../types/json/tdengine.sql) | JSON TAG 类型，json_extract 查询 |
| [数值类型](../types/numeric/tdengine.sql) | TINYINT-BIGINT/FLOAT/DOUBLE/BOOL，无 DECIMAL |
| [字符串类型](../types/string/tdengine.sql) | NCHAR(Unicode)/BINARY/VARCHAR(3.0+) |
