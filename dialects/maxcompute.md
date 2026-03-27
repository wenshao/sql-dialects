# MaxCompute

**分类**: 阿里云大数据平台
**文件数**: 51 个 SQL 文件
**总行数**: 4134 行

## 概述与定位

MaxCompute（原 ODPS，Open Data Processing Service）是阿里云自主研发的大数据计算平台，面向 EB 级数据仓库和批量分析场景。它提供 Serverless 的计算体验——用户无需管理集群，按 SQL 扫描量或预留 CU（计算单元）付费。MaxCompute 是阿里巴巴内部数据中台的技术底座，每天处理 EB 级数据量，支撑了双十一等超大规模数据分析场景。

## 历史与演进

- **2010 年**：ODPS 在阿里巴巴内部启动，作为统一的大数据计算平台。
- **2014 年**：ODPS 作为阿里云公共云服务对外开放。
- **2016 年**：更名为 MaxCompute，强调"最大化计算"的定位，引入 SQL 2.0 语法增强。
- **2018 年**：引入事务表（Transactional Table）支持 ACID 语义、UPDATE/DELETE 操作。
- **2020 年**：增强 Python UDF/UDTF 支持、Schema Evolution、增量数据处理（Delta Table）。
- **2022 年**：引入 MCQA（MaxCompute Query Acceleration）实现秒级交互查询、外部表支持增强。
- **2024-2025 年**：推进存算分离、Lakehouse 集成（Hudi/Delta Lake/Iceberg）、增强 JSON 处理和半结构化数据分析能力。

## 核心设计思路

1. **Serverless 大数据**：用户提交 SQL 后，系统自动调度计算资源执行，无需预置集群，按需扩缩。
2. **分区即目录**：表分区在底层对应存储目录，`PARTITION(dt='2024-01-01')` 直接映射为物理目录路径，数据管理和生命周期管理以分区为粒度。
3. **LIFECYCLE 管理**：通过 `LIFECYCLE n` 设定表/分区的生存天数，到期自动删除，解决大数据场景下的存储成本治理问题。
4. **统一 SQL 引擎**：ODPS SQL 兼容大部分 Hive SQL 语法，同时增强了标准 SQL 支持（窗口函数、CTE、GROUPING SETS）。

## 独特特色

| 特性 | 说明 |
|---|---|
| **ODPS SQL** | MaxCompute 自有的 SQL 方言，兼容 Hive SQL 并增加标准 SQL 扩展，支持 CTE、窗口函数、SEMI JOIN。 |
| **事务表** | 支持 ACID 事务的表类型，允许 UPDATE/DELETE/MERGE 操作，支持 Time Travel 查询历史快照。 |
| **LIFECYCLE** | `CREATE TABLE t (...) LIFECYCLE 90` 设定数据生存周期（天），到期自动回收，是大数据存储治理的核心手段。 |
| **分区=目录** | 分区值直接映射为 HDFS/Pangu 存储目录，`ALTER TABLE ADD PARTITION` 等价于创建存储目录。 |
| **Tunnel 批量导入** | MaxCompute Tunnel 提供高吞吐批量数据上传下载通道，支持断点续传和并行传输。 |
| **MCQA 加速** | MaxCompute Query Acceleration 对小规模数据集提供秒级交互式查询，无需额外配置。 |
| **资源管理（Quota）** | 通过配额组（Quota Group）管理计算资源分配，支持预留模式和按量付费模式并存。 |

## 已知不足

- **生态局限于阿里云**：MaxCompute 是阿里云专有服务，无法在其他云平台或本地部署，存在供应商锁定。
- **延迟较高**：传统批处理模式下查询延迟在秒到分钟级，不适合在线实时查询场景（MCQA 部分缓解）。
- **SQL 兼容性差异**：ODPS SQL 与标准 SQL/PostgreSQL/MySQL 有诸多差异（如 INSERT 必须用 INSERT INTO/OVERWRITE），迁移有学习成本。
- **UPDATE/DELETE 限制**：仅事务表支持行级变更，普通表不支持 UPDATE/DELETE，只能 INSERT OVERWRITE 整个分区。
- **存储过程受限**：MaxCompute 的过程化编程依赖 Script Mode 或 PyODPS，传统存储过程支持不如 RDBMS 完善。
- **调试困难**：作为 Serverless 服务，查询执行过程不透明，性能调优和错误排查依赖 Logview 工具。

## 对引擎开发者的参考价值

- **LIFECYCLE 自动回收**：将数据 TTL 作为表级 DDL 属性的设计，对大数据引擎的存储治理有直接参考，避免了外部定时任务清理的复杂性。
- **分区=目录映射**：将逻辑分区直接映射为物理存储路径的设计，简化了分区管理和数据加载，对 Hive 兼容引擎有参考。
- **Serverless 计算调度**：按 SQL 提交动态分配计算资源的架构，对云原生查询引擎的资源弹性设计有参考。
- **事务表的实现**：在 Hive 风格的分区表之上叠加 ACID 事务（类似 Hive ACID / Delta Lake），对数据湖引擎的事务化改造有借鉴。
- **Quota Group 资源管理**：多租户计算资源配额管理的实践，对大数据平台的资源隔离设计有参考。

## 全部模块

### DDL — 数据定义

| 模块 | 简评 |
|---|---|
| [建表](../ddl/create-table/maxcompute.sql) | 阿里云大数据平台(原 ODPS)，STORED AS ALIORC，项目级隔离 |
| [改表](../ddl/alter-table/maxcompute.sql) | ALTER ADD COLUMNS/PARTITION，Schema 变更有限 |
| [索引](../ddl/indexes/maxcompute.sql) | 无索引(批处理引擎)，依赖分区裁剪 |
| [约束](../ddl/constraints/maxcompute.sql) | PK(2.0+) 声明不强制，无 FK/CHECK |
| [视图](../ddl/views/maxcompute.sql) | VIEW 支持，物化视图(2.0+) |
| [序列与自增](../ddl/sequences/maxcompute.sql) | 无 SEQUENCE/自增，UUID 或 ROW_NUMBER 生成 |
| [数据库/Schema/用户](../ddl/users-databases/maxcompute.sql) | Project→Schema(3.0+)→Table，RAM 权限 |

### Advanced — 高级特性

| 模块 | 简评 |
|---|---|
| [动态 SQL](../advanced/dynamic-sql/maxcompute.sql) | Script Mode(2.0+) 多语句脚本 |
| [错误处理](../advanced/error-handling/maxcompute.sql) | 无过程式错误处理，作业级失败 |
| [执行计划](../advanced/explain/maxcompute.sql) | EXPLAIN 展示 Fuxi DAG 执行计划 |
| [锁机制](../advanced/locking/maxcompute.sql) | 无行级锁(批处理引擎)，表/分区级并发 |
| [分区](../advanced/partitioning/maxcompute.sql) | PARTITIONED BY(同 Hive)，分区是成本控制核心 |
| [权限](../advanced/permissions/maxcompute.sql) | RAM+ACL+Policy 三层权限，Label Security 列级 |
| [存储过程](../advanced/stored-procedures/maxcompute.sql) | Script Mode 脚本(非传统存储过程) |
| [临时表](../advanced/temp-tables/maxcompute.sql) | TEMPORARY TABLE(会话级)，VOLATILE TABLE |
| [事务](../advanced/transactions/maxcompute.sql) | ACID 事务(2.0+)，TimeTravel 时间旅行查询 |
| [触发器](../advanced/triggers/maxcompute.sql) | 无触发器 |

### DML — 数据操作

| 模块 | 简评 |
|---|---|
| [删除](../dml/delete/maxcompute.sql) | DELETE(ACID 表 2.0+)，非 ACID 表 DROP PARTITION |
| [插入](../dml/insert/maxcompute.sql) | INSERT INTO/OVERWRITE(同 Hive)，Tunnel 批量上传 |
| [更新](../dml/update/maxcompute.sql) | UPDATE(ACID 表 2.0+)，非 ACID 表不支持 |
| [Upsert](../dml/upsert/maxcompute.sql) | MERGE(ACID 表 2.0+)，INSERT OVERWRITE 替代 |

### Functions — 内置函数

| 模块 | 简评 |
|---|---|
| [聚合函数](../functions/aggregate/maxcompute.sql) | GROUPING SETS/CUBE/ROLLUP，COLLECT_LIST/COLLECT_SET |
| [条件函数](../functions/conditional/maxcompute.sql) | IF/CASE/COALESCE/NVL(Hive 兼容) |
| [日期函数](../functions/date-functions/maxcompute.sql) | DATEADD/DATEDIFF/DATE_FORMAT(Hive 兼容+扩展) |
| [数学函数](../functions/math-functions/maxcompute.sql) | 完整数学函数 |
| [字符串函数](../functions/string-functions/maxcompute.sql) | CONCAT/SUBSTR/REGEXP(Hive 兼容) |
| [类型转换](../functions/type-conversion/maxcompute.sql) | CAST/TRY_CAST(2.0+) 安全转换 |

### Query — 查询

| 模块 | 简评 |
|---|---|
| [CTE](../query/cte/maxcompute.sql) | WITH+递归 CTE 支持 |
| [全文搜索](../query/full-text-search/maxcompute.sql) | 无全文搜索 |
| [连接查询](../query/joins/maxcompute.sql) | Map/Reduce/Broadcast JOIN(同 Hive)，MAPJOIN 提示 |
| [分页](../query/pagination/maxcompute.sql) | LIMIT+ORDER BY，无 OFFSET |
| [行列转换](../query/pivot-unpivot/maxcompute.sql) | LATERAL VIEW EXPLODE(Hive 兼容)，无 PIVOT |
| [集合操作](../query/set-operations/maxcompute.sql) | UNION/INTERSECT/EXCEPT 完整 |
| [子查询](../query/subquery/maxcompute.sql) | IN/EXISTS 子查询支持 |
| [窗口函数](../query/window-functions/maxcompute.sql) | 完整窗口函数(Hive 兼容) |

### Scenarios — 实战场景

| 模块 | 简评 |
|---|---|
| [日期填充](../scenarios/date-series-fill/maxcompute.sql) | 无 generate_series，辅助表或 LATERAL VIEW |
| [去重](../scenarios/deduplication/maxcompute.sql) | ROW_NUMBER+窗口函数去重 |
| [区间检测](../scenarios/gap-detection/maxcompute.sql) | 窗口函数检测 |
| [层级查询](../scenarios/hierarchical-query/maxcompute.sql) | 递归 CTE 支持 |
| [JSON 展开](../scenarios/json-flatten/maxcompute.sql) | GET_JSON_OBJECT/JSON_EXTRACT(Hive 兼容) |
| [迁移速查](../scenarios/migration-cheatsheet/maxcompute.sql) | Hive 兼容+阿里云生态+ACID 2.0 是核心特色 |
| [TopN 查询](../scenarios/ranking-top-n/maxcompute.sql) | ROW_NUMBER+LIMIT |
| [累计求和](../scenarios/running-total/maxcompute.sql) | SUM() OVER 标准 |
| [缓慢变化维](../scenarios/slowly-changing-dim/maxcompute.sql) | MERGE(ACID 表)+INSERT OVERWRITE |
| [字符串拆分](../scenarios/string-split-to-rows/maxcompute.sql) | SPLIT+LATERAL VIEW EXPLODE(Hive 兼容) |
| [窗口分析](../scenarios/window-analytics/maxcompute.sql) | 完整窗口函数(Hive 兼容) |

### Types — 数据类型

| 模块 | 简评 |
|---|---|
| [复合类型](../types/array-map-struct/maxcompute.sql) | ARRAY/MAP/STRUCT 原生(Hive 兼容)，LATERAL VIEW |
| [日期时间](../types/datetime/maxcompute.sql) | DATE/DATETIME/TIMESTAMP(Hive 兼容+扩展) |
| [JSON](../types/json/maxcompute.sql) | GET_JSON_OBJECT 路径查询，无 JSON 类型 |
| [数值类型](../types/numeric/maxcompute.sql) | TINYINT-BIGINT/FLOAT/DOUBLE/DECIMAL 标准 |
| [字符串类型](../types/string/maxcompute.sql) | STRING/VARCHAR(Hive 兼容)，UTF-8 |
