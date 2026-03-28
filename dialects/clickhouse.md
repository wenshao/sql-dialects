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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/clickhouse.md) | MergeTree 引擎家族，ORDER BY=物理布局，Nullable 默认关闭 |
| [改表](../ddl/alter-table/clickhouse.md) | ALTER 异步执行(Mutation)，ADD/DROP COLUMN 轻量，MODIFY 重写 |
| [索引](../ddl/indexes/clickhouse.md) | 稀疏索引(8192行一标记)替代B-Tree，跳数索引(minmax/set/bloom) |
| [约束](../ddl/constraints/clickhouse.md) | ASSUME 约束仅优化器提示不校验，CHECK 有限支持 |
| [视图](../ddl/views/clickhouse.md) | 物化视图=INSERT 触发器+目标表，实时预聚合利器 |
| [序列与自增](../ddl/sequences/clickhouse.md) | 无 SEQUENCE/AUTO_INCREMENT，UUID 或外部生成 |
| [数据库/Schema/用户](../ddl/users-databases/clickhouse.md) | RBAC 权限模型，ON CLUSTER 分布式 DDL |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/clickhouse.md) | 无存储过程/动态 SQL，逻辑在应用层实现 |
| [错误处理](../advanced/error-handling/clickhouse.md) | 无过程式错误处理，查询级别错误返回 |
| [执行计划](../advanced/explain/clickhouse.md) | EXPLAIN PIPELINE/AST/SYNTAX，可视化执行管道 |
| [锁机制](../advanced/locking/clickhouse.md) | 无行级锁，Part 级别原子写入，最终一致性 |
| [分区](../advanced/partitioning/clickhouse.md) | PARTITION BY 按月/日分区，Part 管理透明，TTL 自动过期 |
| [权限](../advanced/permissions/clickhouse.md) | RBAC(20.x+)，GRANT/REVOKE 标准语法，Row Policy 行级过滤 |
| [存储过程](../advanced/stored-procedures/clickhouse.md) | 无存储过程/触发器，逻辑在应用层或调度系统实现 |
| [临时表](../advanced/temp-tables/clickhouse.md) | 无传统临时表，用 Memory 引擎表或 CTE 替代 |
| [事务](../advanced/transactions/clickhouse.md) | 无传统事务，最终一致性，实验性事务支持(25.x+) |
| [触发器](../advanced/triggers/clickhouse.md) | 无触发器，物化视图充当 INSERT 触发器角色 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/clickhouse.md) | Lightweight Delete(22.8+)，旧版异步 Mutation 删除 |
| [插入](../dml/insert/clickhouse.md) | 大批量 INSERT 为设计核心，Buffer 表缓冲小写入 |
| [更新](../dml/update/clickhouse.md) | ALTER TABLE UPDATE 异步 Mutation，非原地修改 |
| [Upsert](../dml/upsert/clickhouse.md) | ReplacingMergeTree 去重(合并时)，FINAL 保证一致性 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/clickhouse.md) | -If/-State/-Merge 组合后缀独有，quantile 系列丰富 |
| [条件函数](../functions/conditional/clickhouse.md) | if/multiIf 函数式语法，无 CASE WHEN（用 multiIf 替代） |
| [日期函数](../functions/date-functions/clickhouse.md) | toYYYYMM/toStartOfMonth 等便捷函数，时区处理完善 |
| [数学函数](../functions/math-functions/clickhouse.md) | 完整数学函数，向量化执行极快 |
| [字符串函数](../functions/string-functions/clickhouse.md) | 丰富字符串函数，extractAll 正则提取，replaceRegexpAll |
| [类型转换](../functions/type-conversion/clickhouse.md) | toInt32/toString 显式转换，accurateCast 严格模式 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/clickhouse.md) | WITH 子句支持，默认内联展开非物化 |
| [全文搜索](../query/full-text-search/clickhouse.md) | tokenbf_v1/ngrambf_v1 布隆过滤索引，非传统全文搜索 |
| [连接查询](../query/joins/clickhouse.md) | Hash/Sort Merge JOIN，大表 JOIN 易 OOM，推荐 Dictionary |
| [分页](../query/pagination/clickhouse.md) | LIMIT N OFFSET M，LIMIT N BY col 每组限行（独有） |
| [行列转换](../query/pivot-unpivot/clickhouse.md) | 无原生 PIVOT，用 sumIf/countIf+组合函数后缀实现 |
| [集合操作](../query/set-operations/clickhouse.md) | UNION ALL 完整，INTERSECT/EXCEPT 支持 |
| [子查询](../query/subquery/clickhouse.md) | IN 子查询+JOIN 子查询，Global IN 分布式场景 |
| [窗口函数](../query/window-functions/clickhouse.md) | 21.1+ 支持，功能逐版本完善，性能不如聚合函数 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/clickhouse.md) | WITH FILL 独有语法自动填充缺失行，最简方案 |
| [去重](../scenarios/deduplication/clickhouse.md) | ReplacingMergeTree 自动去重(合并时)，FINAL 查询保证 |
| [区间检测](../scenarios/gap-detection/clickhouse.md) | WITH FILL+窗口函数检测，numbers() 辅助生成序列 |
| [层级查询](../scenarios/hierarchical-query/clickhouse.md) | 无递归 CTE(旧版)，24.x+ 支持递归 CTE |
| [JSON 展开](../scenarios/json-flatten/clickhouse.md) | JSONExtract 系列函数，JSON 类型(实验性)，嵌套数据用 Nested |
| [迁移速查](../scenarios/migration-cheatsheet/clickhouse.md) | ENGINE 选择是核心，ORDER BY 决定性能，无事务需适应 |
| [TopN 查询](../scenarios/ranking-top-n/clickhouse.md) | LIMIT BY 每组取 TopN（独有语法），ROW_NUMBER 亦可 |
| [累计求和](../scenarios/running-total/clickhouse.md) | 窗口函数(21.1+)，或 runningAccumulate 状态函数 |
| [缓慢变化维](../scenarios/slowly-changing-dim/clickhouse.md) | ReplacingMergeTree 版本字段实现 SCD，无 MERGE 语句 |
| [字符串拆分](../scenarios/string-split-to-rows/clickhouse.md) | splitByChar/splitByString+arrayJoin 展开，简洁 |
| [窗口分析](../scenarios/window-analytics/clickhouse.md) | 21.1+ 窗口函数，ROWS/RANGE 帧支持，逐版本增强 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/clickhouse.md) | Array/Map/Tuple/Nested 原生支持，arrayJoin 展开 |
| [日期时间](../types/datetime/clickhouse.md) | Date/Date32/DateTime/DateTime64 分级精度，时区内置 |
| [JSON](../types/json/clickhouse.md) | JSONExtract 函数族，实验性 JSON 类型，Nested 列更高效 |
| [数值类型](../types/numeric/clickhouse.md) | Int8-256/UInt8-256 丰富整数，Decimal32/64/128/256 精确 |
| [字符串类型](../types/string/clickhouse.md) | String 无长度限制，FixedString 定长，LowCardinality 字典编码 |
