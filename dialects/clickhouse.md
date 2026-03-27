# ClickHouse

**分类**: 列式分析数据库
**文件数**: 51 个 SQL 文件
**总行数**: 6690 行

## 概述与定位

ClickHouse 是一款开源的列式 OLAP 数据库，以**极致的查询性能**闻名。它的设计目标是在商用硬件上实现亿级行数据的亚秒级聚合查询。ClickHouse 不试图成为通用数据库，而是专注于分析场景——大批量写入、低频更新、高速聚合查询。

与 BigQuery/Snowflake 等无服务器云数仓不同，ClickHouse 是一个**可自托管的引擎**，用户需要自行管理集群（虽然 ClickHouse Cloud 提供了托管方案）。这意味着更大的控制权，也意味着更高的运维成本。ClickHouse 在日志分析、用户行为分析、实时监控等场景中被广泛采用。

## 历史与演进

| 时间 | 里程碑 |
|------|--------|
| 2008 | Yandex 为 Metrica（网站分析服务，类似 Google Analytics）启动内部项目 |
| 2016 | 在 Apache 2.0 许可下开源，迅速获得社区关注 |
| 2019 | Yandex 分拆 ClickHouse 团队，后成立 ClickHouse Inc. |
| 2021 | ClickHouse Inc. 获得融资，推出 ClickHouse Cloud 托管服务 |
| 2024 | 持续增强：SharedMergeTree（云原生存储引擎）、实验性事务支持、JSON 类型改进 |

## 核心设计思路

- **INSERT-only 哲学**：ClickHouse 的核心假设是数据主要通过大批量 INSERT 写入，极少更新或删除。传统的 UPDATE/DELETE 在早期版本中是异步 Mutation（后台重写数据分片），而非原地修改。这一哲学使得写入路径极为简单高效，但 OLTP 式的行级修改代价高昂。
- **MergeTree 引擎家族**：MergeTree 是 ClickHouse 的基石存储引擎。数据写入时先进入内存缓冲区，然后 flush 为不可变的有序 Part（数据分片），后台 Merge 线程持续将小 Part 合并为大 Part。这一设计类似 LSM-Tree，但针对列式分析做了大量优化。
- **列式存储 + 向量化执行**：每列独立存储和压缩，查询时只读取必要列。执行引擎采用向量化（Vectorized）模式，一次处理一批行（Block）而非逐行处理，最大化 CPU Cache 和 SIMD 指令的利用率。
- **稀疏索引**：ClickHouse 不使用 B-Tree 索引，而是每隔 N 行（默认 8192）记录一个 ORDER BY 列的索引标记（Mark）。查询时通过二分查找快速定位到包含目标数据的 Granule（颗粒），跳过无关数据。这比 B-Tree 更节省空间，但只对 ORDER BY 前缀列有效。

## 独特特色

- **MergeTree 引擎家族**：不同变体解决不同问题——`ReplacingMergeTree` 在 Merge 时按主键去重；`SummingMergeTree` 自动聚合数值列；`AggregatingMergeTree` 保存预聚合中间状态；`CollapsingMergeTree` 通过 +1/-1 标记实现逻辑删除。引擎选择是 ClickHouse 数据建模的核心决策。
- **ORDER BY = 物理布局**：建表时的 `ORDER BY (col1, col2)` 不仅定义排序，更决定了数据的物理存储顺序和稀疏索引结构。这与 RDBMS 中 ORDER BY 仅影响查询结果截然不同。选择正确的 ORDER BY 是 ClickHouse 性能优化的关键。
- **Nullable 默认关闭**：列默认不允许 NULL，`Nullable(T)` 需要显式声明。非 Nullable 列占用更少存储且查询更快，因为不需要额外的 null bitmap。这是性能优先的设计取舍。
- **LowCardinality 类型**：`LowCardinality(String)` 自动对低基数字符串（如国家、状态码）进行字典编码，通常可将存储和查询性能提升 2-10 倍。这是 ClickHouse 独有的类型级优化。
- **组合函数后缀**：聚合函数支持 `-If`（条件聚合）、`-State`（保存中间状态）、`-Merge`（合并中间状态）等后缀组合。例如 `sumIf(amount, status = 'paid')` 或 `quantileState(0.99)(latency)`。这种组合式设计使得复杂聚合无需子查询。
- **FINAL 关键字**：`SELECT ... FROM t FINAL` 在查询时强制应用 Merge 逻辑（如 ReplacingMergeTree 去重），保证看到最终一致的数据。代价是查询变慢。
- **物化视图 = INSERT 触发器**：ClickHouse 的物化视图在 INSERT 时自动触发，将增量数据写入目标表。它本质上是一个"INSERT 触发器 + 目标表"的组合，用于实时预聚合。
- **WITH FILL / LIMIT BY**：`ORDER BY date WITH FILL FROM ... TO ...` 自动填充缺失的日期行；`LIMIT N BY col` 每组最多返回 N 行——这些是 ClickHouse 独有的 SQL 扩展，简化了常见分析查询。

## 已知的设计不足与历史包袱

- **无传统事务**：ClickHouse 长期没有 ACID 事务支持。直到 25.x 版本引入实验性事务，但仍不适合 OLTP 场景。多表原子写入（"要么全成功要么全失败"）在生产中仍需谨慎。
- **UPDATE/DELETE 的历史包袱**：早期 UPDATE/DELETE 是异步 Mutation，提交后后台执行，不保证即时可见。25.7 版本引入了"轻量级删除"（Lightweight Delete）和标准 UPDATE 语法，但底层仍是重写 Part，不是原地修改。
- **无 JOIN 索引**：ClickHouse 的 JOIN 性能有限，大表 JOIN 大表容易 OOM。推荐做法是将维表加载到内存（Dictionary）或预 JOIN 后写入宽表。
- **最终一致性**：在 ReplacingMergeTree 等引擎中，Merge 完成前可能看到重复数据。必须使用 FINAL 或手动去重来保证查询正确性，这增加了应用层复杂度。
- **无存储过程/触发器**：不支持过程式编程，复杂逻辑必须在应用层或调度系统中实现。

## 兼容生态

ClickHouse 有自己的 SQL 方言，语法与 MySQL/PostgreSQL 有较多差异。但提供了 MySQL/PostgreSQL 兼容协议端口，支持 JDBC/ODBC 连接。内置多种外部表引擎（MySQL、PostgreSQL、S3、HDFS、Kafka）可直接查询外部数据源。

## 对引擎开发者的参考价值

- **稀疏索引设计**：每 8192 行一个 Mark 的稀疏索引，在存储开销和查询加速之间取得了极佳平衡。这一设计证明了 OLAP 场景下不需要 B-Tree 级别的精确索引。
- **Codec 压缩链**：支持多种编解码器的链式组合（如 `CODEC(Delta, ZSTD)`），先做 Delta 编码再压缩，针对时序数据可获得极高压缩比。这种可组合压缩架构值得借鉴。
- **向量化执行引擎**：Block-based 批处理 + SIMD 指令利用，是现代分析引擎的标准实践。ClickHouse 的实现是这一领域的重要参考。
- **MergeTree 合并策略**：不同 MergeTree 变体在 Merge 时执行不同语义（去重/求和/聚合/折叠），将业务逻辑嵌入存储层。这种"存储引擎即业务逻辑"的设计思路独具特色。

---

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [clickhouse.sql](../ddl/create-table/clickhouse.sql) |
| 改表 | [clickhouse.sql](../ddl/alter-table/clickhouse.sql) |
| 索引 | [clickhouse.sql](../ddl/indexes/clickhouse.sql) |
| 约束 | [clickhouse.sql](../ddl/constraints/clickhouse.sql) |
| 视图 | [clickhouse.sql](../ddl/views/clickhouse.sql) |
| 序列与自增 | [clickhouse.sql](../ddl/sequences/clickhouse.sql) |
| 数据库/Schema/用户 | [clickhouse.sql](../ddl/users-databases/clickhouse.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [clickhouse.sql](../advanced/dynamic-sql/clickhouse.sql) |
| 错误处理 | [clickhouse.sql](../advanced/error-handling/clickhouse.sql) |
| 执行计划 | [clickhouse.sql](../advanced/explain/clickhouse.sql) |
| 锁机制 | [clickhouse.sql](../advanced/locking/clickhouse.sql) |
| 分区 | [clickhouse.sql](../advanced/partitioning/clickhouse.sql) |
| 权限 | [clickhouse.sql](../advanced/permissions/clickhouse.sql) |
| 存储过程 | [clickhouse.sql](../advanced/stored-procedures/clickhouse.sql) |
| 临时表 | [clickhouse.sql](../advanced/temp-tables/clickhouse.sql) |
| 事务 | [clickhouse.sql](../advanced/transactions/clickhouse.sql) |
| 触发器 | [clickhouse.sql](../advanced/triggers/clickhouse.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [clickhouse.sql](../dml/delete/clickhouse.sql) |
| 插入 | [clickhouse.sql](../dml/insert/clickhouse.sql) |
| 更新 | [clickhouse.sql](../dml/update/clickhouse.sql) |
| Upsert | [clickhouse.sql](../dml/upsert/clickhouse.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [clickhouse.sql](../functions/aggregate/clickhouse.sql) |
| 条件函数 | [clickhouse.sql](../functions/conditional/clickhouse.sql) |
| 日期函数 | [clickhouse.sql](../functions/date-functions/clickhouse.sql) |
| 数学函数 | [clickhouse.sql](../functions/math-functions/clickhouse.sql) |
| 字符串函数 | [clickhouse.sql](../functions/string-functions/clickhouse.sql) |
| 类型转换 | [clickhouse.sql](../functions/type-conversion/clickhouse.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [clickhouse.sql](../query/cte/clickhouse.sql) |
| 全文搜索 | [clickhouse.sql](../query/full-text-search/clickhouse.sql) |
| 连接查询 | [clickhouse.sql](../query/joins/clickhouse.sql) |
| 分页 | [clickhouse.sql](../query/pagination/clickhouse.sql) |
| 行列转换 | [clickhouse.sql](../query/pivot-unpivot/clickhouse.sql) |
| 集合操作 | [clickhouse.sql](../query/set-operations/clickhouse.sql) |
| 子查询 | [clickhouse.sql](../query/subquery/clickhouse.sql) |
| 窗口函数 | [clickhouse.sql](../query/window-functions/clickhouse.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [clickhouse.sql](../scenarios/date-series-fill/clickhouse.sql) |
| 去重 | [clickhouse.sql](../scenarios/deduplication/clickhouse.sql) |
| 区间检测 | [clickhouse.sql](../scenarios/gap-detection/clickhouse.sql) |
| 层级查询 | [clickhouse.sql](../scenarios/hierarchical-query/clickhouse.sql) |
| JSON 展开 | [clickhouse.sql](../scenarios/json-flatten/clickhouse.sql) |
| 迁移速查 | [clickhouse.sql](../scenarios/migration-cheatsheet/clickhouse.sql) |
| TopN 查询 | [clickhouse.sql](../scenarios/ranking-top-n/clickhouse.sql) |
| 累计求和 | [clickhouse.sql](../scenarios/running-total/clickhouse.sql) |
| 缓慢变化维 | [clickhouse.sql](../scenarios/slowly-changing-dim/clickhouse.sql) |
| 字符串拆分 | [clickhouse.sql](../scenarios/string-split-to-rows/clickhouse.sql) |
| 窗口分析 | [clickhouse.sql](../scenarios/window-analytics/clickhouse.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [clickhouse.sql](../types/array-map-struct/clickhouse.sql) |
| 日期时间 | [clickhouse.sql](../types/datetime/clickhouse.sql) |
| JSON | [clickhouse.sql](../types/json/clickhouse.sql) |
| 数值类型 | [clickhouse.sql](../types/numeric/clickhouse.sql) |
| 字符串类型 | [clickhouse.sql](../types/string/clickhouse.sql) |
