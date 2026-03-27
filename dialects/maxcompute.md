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

| 模块 | 链接 |
|---|---|
| 建表 | [maxcompute.sql](../ddl/create-table/maxcompute.sql) |
| 改表 | [maxcompute.sql](../ddl/alter-table/maxcompute.sql) |
| 索引 | [maxcompute.sql](../ddl/indexes/maxcompute.sql) |
| 约束 | [maxcompute.sql](../ddl/constraints/maxcompute.sql) |
| 视图 | [maxcompute.sql](../ddl/views/maxcompute.sql) |
| 序列与自增 | [maxcompute.sql](../ddl/sequences/maxcompute.sql) |
| 数据库/Schema/用户 | [maxcompute.sql](../ddl/users-databases/maxcompute.sql) |

### Advanced — 高级特性

| 模块 | 链接 |
|---|---|
| 动态 SQL | [maxcompute.sql](../advanced/dynamic-sql/maxcompute.sql) |
| 错误处理 | [maxcompute.sql](../advanced/error-handling/maxcompute.sql) |
| 执行计划 | [maxcompute.sql](../advanced/explain/maxcompute.sql) |
| 锁机制 | [maxcompute.sql](../advanced/locking/maxcompute.sql) |
| 分区 | [maxcompute.sql](../advanced/partitioning/maxcompute.sql) |
| 权限 | [maxcompute.sql](../advanced/permissions/maxcompute.sql) |
| 存储过程 | [maxcompute.sql](../advanced/stored-procedures/maxcompute.sql) |
| 临时表 | [maxcompute.sql](../advanced/temp-tables/maxcompute.sql) |
| 事务 | [maxcompute.sql](../advanced/transactions/maxcompute.sql) |
| 触发器 | [maxcompute.sql](../advanced/triggers/maxcompute.sql) |

### DML — 数据操作

| 模块 | 链接 |
|---|---|
| 删除 | [maxcompute.sql](../dml/delete/maxcompute.sql) |
| 插入 | [maxcompute.sql](../dml/insert/maxcompute.sql) |
| 更新 | [maxcompute.sql](../dml/update/maxcompute.sql) |
| Upsert | [maxcompute.sql](../dml/upsert/maxcompute.sql) |

### Functions — 内置函数

| 模块 | 链接 |
|---|---|
| 聚合函数 | [maxcompute.sql](../functions/aggregate/maxcompute.sql) |
| 条件函数 | [maxcompute.sql](../functions/conditional/maxcompute.sql) |
| 日期函数 | [maxcompute.sql](../functions/date-functions/maxcompute.sql) |
| 数学函数 | [maxcompute.sql](../functions/math-functions/maxcompute.sql) |
| 字符串函数 | [maxcompute.sql](../functions/string-functions/maxcompute.sql) |
| 类型转换 | [maxcompute.sql](../functions/type-conversion/maxcompute.sql) |

### Query — 查询

| 模块 | 链接 |
|---|---|
| CTE | [maxcompute.sql](../query/cte/maxcompute.sql) |
| 全文搜索 | [maxcompute.sql](../query/full-text-search/maxcompute.sql) |
| 连接查询 | [maxcompute.sql](../query/joins/maxcompute.sql) |
| 分页 | [maxcompute.sql](../query/pagination/maxcompute.sql) |
| 行列转换 | [maxcompute.sql](../query/pivot-unpivot/maxcompute.sql) |
| 集合操作 | [maxcompute.sql](../query/set-operations/maxcompute.sql) |
| 子查询 | [maxcompute.sql](../query/subquery/maxcompute.sql) |
| 窗口函数 | [maxcompute.sql](../query/window-functions/maxcompute.sql) |

### Scenarios — 实战场景

| 模块 | 链接 |
|---|---|
| 日期填充 | [maxcompute.sql](../scenarios/date-series-fill/maxcompute.sql) |
| 去重 | [maxcompute.sql](../scenarios/deduplication/maxcompute.sql) |
| 区间检测 | [maxcompute.sql](../scenarios/gap-detection/maxcompute.sql) |
| 层级查询 | [maxcompute.sql](../scenarios/hierarchical-query/maxcompute.sql) |
| JSON 展开 | [maxcompute.sql](../scenarios/json-flatten/maxcompute.sql) |
| 迁移速查 | [maxcompute.sql](../scenarios/migration-cheatsheet/maxcompute.sql) |
| TopN 查询 | [maxcompute.sql](../scenarios/ranking-top-n/maxcompute.sql) |
| 累计求和 | [maxcompute.sql](../scenarios/running-total/maxcompute.sql) |
| 缓慢变化维 | [maxcompute.sql](../scenarios/slowly-changing-dim/maxcompute.sql) |
| 字符串拆分 | [maxcompute.sql](../scenarios/string-split-to-rows/maxcompute.sql) |
| 窗口分析 | [maxcompute.sql](../scenarios/window-analytics/maxcompute.sql) |

### Types — 数据类型

| 模块 | 链接 |
|---|---|
| 复合类型 | [maxcompute.sql](../types/array-map-struct/maxcompute.sql) |
| 日期时间 | [maxcompute.sql](../types/datetime/maxcompute.sql) |
| JSON | [maxcompute.sql](../types/json/maxcompute.sql) |
| 数值类型 | [maxcompute.sql](../types/numeric/maxcompute.sql) |
| 字符串类型 | [maxcompute.sql](../types/string/maxcompute.sql) |
