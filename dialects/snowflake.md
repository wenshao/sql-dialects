# Snowflake

**分类**: 云原生数仓
**文件数**: 51 个 SQL 文件
**总行数**: 5306 行

## 概述与定位

Snowflake 是云原生数据仓库的领导者，以**存储与计算完全分离**的架构著称。不同于传统数仓绑定特定硬件或虚拟机，Snowflake 在 AWS/Azure/GCP 之上构建了独立的三层架构，实现了真正的弹性伸缩。其核心理念是"零管理"——用户无需关心索引创建、数据分布、VACUUM 或统计信息收集，引擎自动处理一切物理优化。

Snowflake 的定位已从纯数仓演化为"Data Cloud"平台，通过 Secure Data Sharing、Snowpark、Marketplace 等能力，将自身定义为数据协作与数据应用的基础设施。

## 历史与演进

| 时间 | 里程碑 |
|------|--------|
| 2012 | Benoit Dageville（Oracle 前核心工程师）和 Thierry Cruanes 联合创立 Snowflake |
| 2014 | 产品正式 GA，首次在 AWS 上提供云原生数仓服务 |
| 2018 | 支持 Azure，开启多云战略；推出 Time Travel 和零拷贝 CLONE |
| 2020 | 史上最大软件 IPO（市值一度超 $700 亿）；推出 Data Cloud 概念 |
| 2022 | Snowpark（Python/Java/Scala 编程框架）GA，拓展数据工程和 ML 场景 |
| 2023 | 推出 Snowflake Cortex（AI/LLM 集成）、Unistore（混合事务/分析）、Iceberg Tables |

## 核心设计思路

- **三层分离架构**：Cloud Services 层（优化器、元数据、安全）、Compute 层（Virtual Warehouse）、Storage 层（微分区存储于云对象存储）。三层独立伸缩，互不影响。关闭 Warehouse 时只消耗极少量 Cloud Services 费用。
- **微分区自动管理**：数据自动按插入顺序组织成 50-500 MB 的不可变微分区（Micro-partition），每个分区记录列级 min/max/count 等元数据。查询时通过**分区裁剪**（Pruning）跳过无关分区，效果类似索引但无需手动创建或维护。
- **零管理哲学**：没有索引、没有 VACUUM、没有手动统计信息收集。这降低了运维复杂度，但也意味着用户无法针对特定查询模式做精细的物理优化——必须信任引擎的自动决策。
- **Time Travel**：所有数据变更保留历史版本（Enterprise 版最长 90 天），可以通过 `AT(TIMESTAMP => ...)` 或 `BEFORE(STATEMENT => ...)` 查询任意历史时间点的数据。这一能力建立在微分区不可变性之上。

## 独特特色

- **VARIANT 半结构化类型**：原生支持 JSON/Avro/XML/Parquet 数据加载到 VARIANT 列，查询时用 `:` 和 `[]` 操作符访问嵌套字段（如 `v:user.name::STRING`）。无需预定义 Schema，实现了 Schema-on-Read 与 Schema-on-Write 的平衡。
- **QUALIFY 子句**：在 `WHERE`/`HAVING` 之后直接过滤窗口函数结果，如 `QUALIFY ROW_NUMBER() OVER(...) = 1`。这消除了传统方案中必须用子查询包装的痛点，是 Snowflake 对 SQL 标准的有价值扩展。
- **零拷贝 CLONE**：`CREATE TABLE t2 CLONE t1` 不复制数据，仅复制元数据指针。底层基于 Copy-on-Write（COW）机制，修改 t2 时才产生新分区。可以在秒级别克隆 TB 级表用于测试。
- **Time Travel + UNDROP**：误删表可以用 `UNDROP TABLE t` 恢复；误操作可以 `SELECT ... AT(TIMESTAMP => '...')` 查看历史数据并恢复。这极大降低了人为误操作的风险。
- **FLATTEN 函数**：将 VARIANT 中的数组/对象展开为行，配合 LATERAL 实现嵌套数据的关系化查询。
- **三种 TIMESTAMP 类型**：TIMESTAMP_NTZ（无时区）、TIMESTAMP_LTZ（本地时区）、TIMESTAMP_TZ（带时区偏移量）。虽然语义精确，但增加了认知负担——新用户经常混淆三者。
- **Virtual Warehouse 弹性计算**：计算资源按 T-Shirt 尺寸（XS 到 6XL）配置，可以随时启停和扩缩，不同团队使用不同 Warehouse 实现资源隔离和成本分摊。
- **Secure Data Sharing**：无需复制数据即可跨账户共享表和视图，消费方直接查询提供方的数据，解决了传统 ETL 数据交换的延迟和成本问题。

## 已知的设计不足与历史包袱

- **约束不执行**：PRIMARY KEY、FOREIGN KEY、UNIQUE 均声明为 `NOT ENFORCED`，仅用于文档和优化器提示。这与 BigQuery 类似，是云数仓在高吞吐写入与约束校验之间的取舍。
- **无索引**：完全依赖微分区裁剪。对于高基数列（如 UUID）的点查询，无法通过索引加速，只能靠 CLUSTER BY 改善数据布局。但 CLUSTER BY 是后台异步操作，不保证即时生效。
- **事务隔离仅 READ COMMITTED**：不支持 REPEATABLE READ 或 SERIALIZABLE。对于需要强隔离级别的场景，应用层必须自行处理。
- **存储过程能力有限**：支持 JavaScript、SQL Script、Python、Java 编写存储过程，但功能和调试体验远不及 Oracle PL/SQL 或 SQL Server T-SQL。缺乏包（Package）、物化变量等高级抽象。
- **三种 TIMESTAMP 增加认知负担**：TIMESTAMP_NTZ/LTZ/TZ 的隐式转换规则复杂，TIMESTAMP_TYPE_MAPPING 参数影响默认行为，经常导致时区相关的 bug。

## 兼容生态

Snowflake SQL 语法主体兼容 ANSI SQL，同时借鉴了 Oracle（如 QUALIFY）、PostgreSQL（如 :: 类型转换）等方言的特性。支持 ODBC/JDBC/Python Connector/Go Driver。通过 External Functions 可调用 AWS Lambda/Azure Functions，通过 Snowpark 支持 Python/Java/Scala DataFrame API。

## 对引擎开发者的参考价值

- **微分区架构**：不可变微分区 + 列级元数据（min/max/count/null_count）的设计，证明了在云对象存储之上可以实现高效的分区裁剪，无需传统索引。这一思路被后来的 Delta Lake、Iceberg 等 Lakehouse 格式借鉴。
- **Metadata-based 查询优化**：`COUNT(*)`、`MIN()`、`MAX()` 等聚合在分区元数据层直接完成，无需扫描数据。这种"元数据即索引"的策略是零管理架构的核心支撑。
- **CLONE 的 COW 实现**：基于不可变分区的 Copy-on-Write 克隆机制，在存储层实现 O(1) 复制。这一技术对数据库分支（Database Branching）功能有重要参考意义。

---

## 全部模块

### DDL — 数据定义

| 模块 | 链接 |
|---|---|
| 建表 | [snowflake.sql](../ddl/create-table/snowflake.sql) |
| 改表 | [snowflake.sql](../ddl/alter-table/snowflake.sql) |
| 索引 | [snowflake.sql](../ddl/indexes/snowflake.sql) |
| 约束 | [snowflake.sql](../ddl/constraints/snowflake.sql) |
| 视图 | [snowflake.sql](../ddl/views/snowflake.sql) |
| 序列与自增 | [snowflake.sql](../ddl/sequences/snowflake.sql) |
| 数据库/Schema/用户 | [snowflake.sql](../ddl/users-databases/snowflake.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [snowflake.sql](../advanced/dynamic-sql/snowflake.sql) |
| 错误处理 | [snowflake.sql](../advanced/error-handling/snowflake.sql) |
| 执行计划 | [snowflake.sql](../advanced/explain/snowflake.sql) |
| 锁机制 | [snowflake.sql](../advanced/locking/snowflake.sql) |
| 分区 | [snowflake.sql](../advanced/partitioning/snowflake.sql) |
| 权限 | [snowflake.sql](../advanced/permissions/snowflake.sql) |
| 存储过程 | [snowflake.sql](../advanced/stored-procedures/snowflake.sql) |
| 临时表 | [snowflake.sql](../advanced/temp-tables/snowflake.sql) |
| 事务 | [snowflake.sql](../advanced/transactions/snowflake.sql) |
| 触发器 | [snowflake.sql](../advanced/triggers/snowflake.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [snowflake.sql](../dml/delete/snowflake.sql) |
| 插入 | [snowflake.sql](../dml/insert/snowflake.sql) |
| 更新 | [snowflake.sql](../dml/update/snowflake.sql) |
| Upsert | [snowflake.sql](../dml/upsert/snowflake.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [snowflake.sql](../functions/aggregate/snowflake.sql) |
| 条件函数 | [snowflake.sql](../functions/conditional/snowflake.sql) |
| 日期函数 | [snowflake.sql](../functions/date-functions/snowflake.sql) |
| 数学函数 | [snowflake.sql](../functions/math-functions/snowflake.sql) |
| 字符串函数 | [snowflake.sql](../functions/string-functions/snowflake.sql) |
| 类型转换 | [snowflake.sql](../functions/type-conversion/snowflake.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [snowflake.sql](../query/cte/snowflake.sql) |
| 全文搜索 | [snowflake.sql](../query/full-text-search/snowflake.sql) |
| 连接查询 | [snowflake.sql](../query/joins/snowflake.sql) |
| 分页 | [snowflake.sql](../query/pagination/snowflake.sql) |
| 行列转换 | [snowflake.sql](../query/pivot-unpivot/snowflake.sql) |
| 集合操作 | [snowflake.sql](../query/set-operations/snowflake.sql) |
| 子查询 | [snowflake.sql](../query/subquery/snowflake.sql) |
| 窗口函数 | [snowflake.sql](../query/window-functions/snowflake.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [snowflake.sql](../scenarios/date-series-fill/snowflake.sql) |
| 去重 | [snowflake.sql](../scenarios/deduplication/snowflake.sql) |
| 区间检测 | [snowflake.sql](../scenarios/gap-detection/snowflake.sql) |
| 层级查询 | [snowflake.sql](../scenarios/hierarchical-query/snowflake.sql) |
| JSON 展开 | [snowflake.sql](../scenarios/json-flatten/snowflake.sql) |
| 迁移速查 | [snowflake.sql](../scenarios/migration-cheatsheet/snowflake.sql) |
| TopN 查询 | [snowflake.sql](../scenarios/ranking-top-n/snowflake.sql) |
| 累计求和 | [snowflake.sql](../scenarios/running-total/snowflake.sql) |
| 缓慢变化维 | [snowflake.sql](../scenarios/slowly-changing-dim/snowflake.sql) |
| 字符串拆分 | [snowflake.sql](../scenarios/string-split-to-rows/snowflake.sql) |
| 窗口分析 | [snowflake.sql](../scenarios/window-analytics/snowflake.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [snowflake.sql](../types/array-map-struct/snowflake.sql) |
| 日期时间 | [snowflake.sql](../types/datetime/snowflake.sql) |
| JSON | [snowflake.sql](../types/json/snowflake.sql) |
| 数值类型 | [snowflake.sql](../types/numeric/snowflake.sql) |
| 字符串类型 | [snowflake.sql](../types/string/snowflake.sql) |
