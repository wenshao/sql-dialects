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

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/snowflake.md) | 计算存储分离，VARIANT 半结构化列，CLUSTER BY 自动微分区 |
| [改表](../ddl/alter-table/snowflake.md) | ALTER 在线执行，元数据操作瞬时，无锁 |
| [索引](../ddl/indexes/snowflake.md) | 无用户创建索引，自动微分区+Search Optimization Service |
| [约束](../ddl/constraints/snowflake.md) | PK/FK/UNIQUE 声明但不强制执行（同 BigQuery），仅元数据 |
| [视图](../ddl/views/snowflake.md) | 物化视图自动维护，Secure View 隐藏定义 |
| [序列与自增](../ddl/sequences/snowflake.md) | AUTOINCREMENT/IDENTITY+SEQUENCE 对象 |
| [数据库/Schema/用户](../ddl/users-databases/snowflake.md) | Database.Schema.Object 三级命名空间，RBAC 完善 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/snowflake.md) | Snowflake Scripting(SQL/JavaScript)，EXECUTE IMMEDIATE |
| [错误处理](../advanced/error-handling/snowflake.md) | EXCEPTION 块(Snowflake Scripting)，SQLCODE/SQLERRM |
| [执行计划](../advanced/explain/snowflake.md) | EXPLAIN 文本+Query Profile 图形化，Warehouse 资源分析 |
| [锁机制](../advanced/locking/snowflake.md) | 自动并发控制，无用户可见锁，乐观并发 |
| [分区](../advanced/partitioning/snowflake.md) | 自动微分区(Micro-Partition)，无需手动管理，CLUSTER BY 优化 |
| [权限](../advanced/permissions/snowflake.md) | RBAC+DAC 双模型，FUTURE GRANTS 自动授权新对象 |
| [存储过程](../advanced/stored-procedures/snowflake.md) | JavaScript/SQL/Python/Scala/Java 多语言存储过程 |
| [临时表](../advanced/temp-tables/snowflake.md) | TEMPORARY+TRANSIENT 表，Time Travel 保留期不同 |
| [事务](../advanced/transactions/snowflake.md) | ACID 事务，自动提交默认开启，AUTOCOMMIT 可关闭 |
| [触发器](../advanced/triggers/snowflake.md) | 无触发器，用 Streams+Tasks 实现变更捕获 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/snowflake.md) | DELETE 标准，Time Travel 可恢复(1-90天)，UNDROP TABLE |
| [插入](../dml/insert/snowflake.md) | INSERT+COPY INTO 批量加载(S3/Azure/GCS)，Snowpipe 流式 |
| [更新](../dml/update/snowflake.md) | UPDATE 标准，多表 UPDATE 支持 |
| [Upsert](../dml/upsert/snowflake.md) | MERGE 标准完整实现，INSERT+ON CONFLICT 不支持 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/snowflake.md) | LISTAGG/ARRAY_AGG，GROUPING SETS/CUBE/ROLLUP 完整 |
| [条件函数](../functions/conditional/snowflake.md) | IFF/IIF 简洁条件，CASE/DECODE/NVL/NVL2 Oracle 风格兼容 |
| [日期函数](../functions/date-functions/snowflake.md) | DATE_TRUNC/DATEADD/DATEDIFF 标准，LAST_DAY，TO_DATE 灵活 |
| [数学函数](../functions/math-functions/snowflake.md) | GREATEST/LEAST 内置，完整数学函数 |
| [字符串函数](../functions/string-functions/snowflake.md) | SPLIT_PART/STRTOK，REGEXP_REPLACE/SUBSTR 正则完整 |
| [类型转换](../functions/type-conversion/snowflake.md) | TRY_CAST 安全转换，:: 运算符(PG 风格)，隐式转换适度 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/snowflake.md) | WITH 标准+递归 CTE，RESULT_SCAN 缓存上一查询结果 |
| [全文搜索](../query/full-text-search/snowflake.md) | 无传统全文索引，LIKE/REGEXP/CONTAINS+Search Optimization |
| [连接查询](../query/joins/snowflake.md) | JOIN 完整，LATERAL FLATTEN 展开半结构化数据 |
| [分页](../query/pagination/snowflake.md) | LIMIT/OFFSET 标准，FETCH FIRST 亦支持 |
| [行列转换](../query/pivot-unpivot/snowflake.md) | PIVOT/UNPIVOT 原生支持 |
| [集合操作](../query/set-operations/snowflake.md) | UNION/INTERSECT/EXCEPT+ALL 完整 |
| [子查询](../query/subquery/snowflake.md) | 关联子查询优化好，标量子查询支持 |
| [窗口函数](../query/window-functions/snowflake.md) | 完整窗口函数，QUALIFY 过滤独有（同 BigQuery） |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/snowflake.md) | GENERATOR+ROW_NUMBER 或 TABLE(GENERATOR(ROWCOUNT=>N)) |
| [去重](../scenarios/deduplication/snowflake.md) | QUALIFY ROW_NUMBER() 最简去重，无需子查询 |
| [区间检测](../scenarios/gap-detection/snowflake.md) | GENERATOR+窗口函数检测间隙 |
| [层级查询](../scenarios/hierarchical-query/snowflake.md) | 递归 CTE 支持，CONNECT BY 兼容(部分) |
| [JSON 展开](../scenarios/json-flatten/snowflake.md) | LATERAL FLATTEN 展开(独有语法)，VARIANT 原生半结构化 |
| [迁移速查](../scenarios/migration-cheatsheet/snowflake.md) | VARIANT 类型+自动微分区+无索引是核心差异 |
| [TopN 查询](../scenarios/ranking-top-n/snowflake.md) | QUALIFY ROW_NUMBER() 最简 TopN，无需嵌套 |
| [累计求和](../scenarios/running-total/snowflake.md) | SUM() OVER 标准，Warehouse 弹性扩展计算 |
| [缓慢变化维](../scenarios/slowly-changing-dim/snowflake.md) | MERGE+Streams 变更捕获，Time Travel 辅助 |
| [字符串拆分](../scenarios/string-split-to-rows/snowflake.md) | SPLIT_TO_TABLE/LATERAL FLATTEN(SPLIT()) 简洁 |
| [窗口分析](../scenarios/window-analytics/snowflake.md) | 完整窗口函数+QUALIFY，WINDOW 命名子句 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/snowflake.md) | VARIANT/ARRAY/OBJECT 半结构化原生支持，无需预定义 Schema |
| [日期时间](../types/datetime/snowflake.md) | DATE/TIME/TIMESTAMP_NTZ/LTZ/TZ 三种时间戳类型 |
| [JSON](../types/json/snowflake.md) | VARIANT 类型原生存储，: 路径访问，FLATTEN 展开，无需解析 |
| [数值类型](../types/numeric/snowflake.md) | NUMBER(38,N) 默认，FLOAT/DOUBLE，整数别名完善 |
| [字符串类型](../types/string/snowflake.md) | VARCHAR 默认 16MB，UTF-8 默认，COLLATE 支持 |
