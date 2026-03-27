# Apache Doris

**分类**: MPP 分析数据库（Apache）
**文件数**: 51 个 SQL 文件
**总行数**: 4391 行

## 概述与定位

Apache Doris 是一款开源的 MPP 分析数据库，源自百度内部的 Palo 项目，2018 年捐赠给 Apache 基金会。Doris 定位于实时分析场景——亚秒级查询响应、高并发低延迟的 OLAP 查询，兼顾批量数据导入和实时数据摄取。它与 StarRocks 同源（StarRocks 是 2020 年从 Doris 分叉），二者在架构和 SQL 方言上有大量相似之处。Doris 在中国互联网、金融、电信行业有广泛应用。

## 历史与演进

- **2012 年**：百度内部启动 Palo 项目，面向广告报表等实时分析场景。
- **2018 年**：Palo 捐赠给 Apache 基金会，更名为 Apache Doris（孵化器项目）。
- **2020 年**：StarRocks（原 DorisDB）从 Doris 分叉，开始独立发展。
- **2022 年**：Apache Doris 毕业成为顶级项目，1.x 版本引入向量化执行引擎、Bitmap 索引增强。
- **2023 年**：Doris 2.0 引入倒排索引、存算分离架构（预览）、Merge-on-Write 优化 Unique 模型。
- **2024-2025 年**：增强存算分离（Cloud-Native）、自动物化视图、多目录联邦查询（Multi-Catalog）、半结构化数据变体类型（Variant）。

## 核心设计思路

1. **FE + BE 架构**：Frontend（FE）负责 SQL 解析、优化和元数据管理，Backend（BE）负责数据存储和查询执行，二者均可水平扩展。
2. **四种数据模型**：Duplicate（明细）、Aggregate（预聚合）、Unique（唯一键去重）、Primary Key（主键实时更新），根据业务场景选择。
3. **MPP 向量化执行**：基于列式内存布局的向量化执行引擎，配合 Pipeline 执行模型，充分利用 CPU 缓存和 SIMD 指令。
4. **MySQL 协议兼容**：使用 MySQL 客户端/驱动即可连接 Doris，降低了迁移和接入成本。

## 独特特色

| 特性 | 说明 |
|---|---|
| **四种数据模型** | Duplicate（全量明细）、Aggregate（写入时预聚合）、Unique（唯一键最新值）——根据查询模式选择最优模型。 |
| **ROLLUP** | 在基础表上创建 ROLLUP 物化索引，预计算特定维度组合的聚合结果，优化器自动命中最优 ROLLUP。 |
| **物化视图** | 支持同步和异步物化视图，优化器可透明路由查询到物化视图，加速聚合类查询。 |
| **Multi-Catalog** | 通过 Catalog 机制直接查询 Hive/Iceberg/Hudi/Elasticsearch/MySQL/PostgreSQL 等外部数据源，无需 ETL。 |
| **Stream Load** | 通过 HTTP PUT 接口实时推送 JSON/CSV 数据到 Doris，支持事务性写入和 exactly-once 语义。 |
| **Light Schema Change** | 列的增删改可在秒级完成，无需数据重写，对在线业务友好。 |
| **Runtime Filter** | 运行时动态生成 Bloom Filter / IN 谓词下推到扫描侧，减少 JOIN 的数据量，对星型模型查询效果显著。 |

## 已知不足

- **事务能力有限**：不支持标准的 BEGIN/COMMIT/ROLLBACK 多语句事务，每个导入任务是一个原子操作。
- **存储过程/触发器缺失**：不支持传统 RDBMS 的存储过程、触发器和游标，过程化逻辑需在应用层实现。
- **UPDATE/DELETE 限制**：仅 Unique/Primary Key 模型支持行级更新和删除，Aggregate/Duplicate 模型不支持。
- **单表数据规模**：虽然支持分区和分桶，但单表超过数百亿行时性能调优难度增加。
- **与 StarRocks 的差异化**：二者功能高度重合，社区和用户在选型时容易产生困惑。

## 对引擎开发者的参考价值

- **多数据模型设计**：在建表时选择 Duplicate/Aggregate/Unique 模型的设计，将查询优化前置到 DDL 阶段，对分析引擎的数据建模有启发。
- **ROLLUP 自动路由**：优化器根据查询的维度和度量自动选择最优 ROLLUP 的实现，对物化视图匹配算法有参考。
- **Runtime Filter 实现**：在 Hash Join 的 Build 侧动态生成 Filter 并下推到 Probe 侧扫描的机制，是分布式 JOIN 优化的实用技术。
- **FE/BE 分离架构**：元数据和计算的解耦设计（FE 管理 + BE 执行），对分布式数据库的架构分层有参考。
- **Light Schema Change**：列元数据变更不触发数据重写的实现（仅修改 FE 元数据 + BE 文件 Footer），对在线 DDL 设计有借鉴。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/doris.sql) | MPP 列式存储，数据模型=Duplicate/Unique/Aggregate(核心选择) |
| [改表](../ddl/alter-table/doris.sql) | Light Schema Change(1.2+) 轻量变更，Rollup 物化索引 |
| [索引](../ddl/indexes/doris.sql) | Short Key 前缀索引+Bloom Filter+Bitmap+倒排索引(2.0+) |
| [约束](../ddl/constraints/doris.sql) | 无传统约束，数据模型替代(Unique 去重/Aggregate 聚合) |
| [视图](../ddl/views/doris.sql) | 物化视图(Rollup) 自动路由，同步物化视图 |
| [序列与自增](../ddl/sequences/doris.sql) | AUTO_INCREMENT(2.1+)，UUID 替代 |
| [数据库/Schema/用户](../ddl/users-databases/doris.sql) | MySQL 协议兼容，RBAC 权限，WorkloadGroup 资源隔离 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/doris.sql) | 无存储过程/动态 SQL(MySQL 协议查询入口) |
| [错误处理](../advanced/error-handling/doris.sql) | 无过程式错误处理 |
| [执行计划](../advanced/explain/doris.sql) | EXPLAIN 带 Fragment/Exchange 分布式信息 |
| [锁机制](../advanced/locking/doris.sql) | 无行级锁，MVCC 版本管理(Unique 模型) |
| [分区](../advanced/partitioning/doris.sql) | PARTITION BY RANGE+DISTRIBUTED BY HASH 双层数据管理 |
| [权限](../advanced/permissions/doris.sql) | MySQL 兼容权限，RBAC 角色 |
| [存储过程](../advanced/stored-procedures/doris.sql) | 无存储过程(OLAP 引擎定位) |
| [临时表](../advanced/temp-tables/doris.sql) | 无临时表(OLAP 引擎) |
| [事务](../advanced/transactions/doris.sql) | Import 事务(Stream Load 原子性)，非传统 OLTP 事务 |
| [触发器](../advanced/triggers/doris.sql) | 无触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/doris.sql) | DELETE 标准(Unique 模型)，Batch Delete 批量 |
| [插入](../dml/insert/doris.sql) | INSERT INTO+Stream Load/Broker Load 批量导入(推荐) |
| [更新](../dml/update/doris.sql) | UPDATE(Unique 模型)，Partial Column Update(2.0+) |
| [Upsert](../dml/upsert/doris.sql) | Unique 模型天然 Upsert(按 Key 替换)，INSERT INTO |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/doris.sql) | GROUPING SETS/CUBE/ROLLUP，BITMAP_UNION 精确去重 |
| [条件函数](../functions/conditional/doris.sql) | IF/CASE/COALESCE/NVL(MySQL 兼容) |
| [日期函数](../functions/date-functions/doris.sql) | DATE_FORMAT/DATE_ADD/DATEDIFF(MySQL 兼容) |
| [数学函数](../functions/math-functions/doris.sql) | 完整数学函数 |
| [字符串函数](../functions/string-functions/doris.sql) | CONCAT/SUBSTR/REGEXP(MySQL 兼容) |
| [类型转换](../functions/type-conversion/doris.sql) | CAST 标准(MySQL 兼容) |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/doris.sql) | WITH 标准+递归 CTE(2.1+) |
| [全文搜索](../query/full-text-search/doris.sql) | 倒排索引(2.0+) 全文搜索，MATCH_ANY/MATCH_ALL |
| [连接查询](../query/joins/doris.sql) | Broadcast/Shuffle/Bucket Shuffle JOIN，Colocate Join 优化 |
| [分页](../query/pagination/doris.sql) | LIMIT/OFFSET(MySQL 兼容) |
| [行列转换](../query/pivot-unpivot/doris.sql) | 无原生 PIVOT，CASE+GROUP BY |
| [集合操作](../query/set-operations/doris.sql) | UNION/INTERSECT/EXCEPT 完整 |
| [子查询](../query/subquery/doris.sql) | IN/EXISTS 子查询，关联子查询支持 |
| [窗口函数](../query/window-functions/doris.sql) | 完整窗口函数支持 |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/doris.sql) | 无 generate_series，需辅助表或应用层 |
| [去重](../scenarios/deduplication/doris.sql) | Unique 模型天然去重，ROW_NUMBER+CTE 亦可 |
| [区间检测](../scenarios/gap-detection/doris.sql) | 窗口函数检测 |
| [层级查询](../scenarios/hierarchical-query/doris.sql) | 递归 CTE(2.1+) |
| [JSON 展开](../scenarios/json-flatten/doris.sql) | JSON_EXTRACT/JSONB 类型，LATERAL VIEW EXPLODE(1.2+) |
| [迁移速查](../scenarios/migration-cheatsheet/doris.sql) | MySQL 协议兼容，数据模型选择+分区分桶是核心概念 |
| [TopN 查询](../scenarios/ranking-top-n/doris.sql) | ROW_NUMBER+窗口函数，LIMIT 直接 |
| [累计求和](../scenarios/running-total/doris.sql) | SUM() OVER 标准，MPP 并行 |
| [缓慢变化维](../scenarios/slowly-changing-dim/doris.sql) | Unique 模型 Upsert 替代 MERGE |
| [字符串拆分](../scenarios/string-split-to-rows/doris.sql) | EXPLODE_SPLIT+LATERAL VIEW(1.2+) |
| [窗口分析](../scenarios/window-analytics/doris.sql) | 完整窗口函数，MPP 并行分析 |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/doris.sql) | ARRAY/MAP/STRUCT(2.0+)，EXPLODE+LATERAL VIEW |
| [日期时间](../types/datetime/doris.sql) | DATE/DATETIME(微秒)/DATEV2(推荐)，无 TIME/INTERVAL |
| [JSON](../types/json/doris.sql) | JSON/JSONB(2.1+) 二进制，倒排索引加速 JSON 查询 |
| [数值类型](../types/numeric/doris.sql) | TINYINT-LARGEINT(128位)/FLOAT/DOUBLE/DECIMAL(27/9) |
| [字符串类型](../types/string/doris.sql) | VARCHAR(65533)/CHAR/STRING(2.1+)，UTF-8 |
