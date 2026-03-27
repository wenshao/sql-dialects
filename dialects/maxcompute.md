# MaxCompute

**分类**: 阿里云大数据平台
**文件数**: 51 个 SQL 文件
**总行数**: 4134 行

## 概述与定位

MaxCompute（原 ODPS）是阿里云自研的 Serverless 大数据计算平台。在阿里内部每天处理 EB 级数据，是双十一数据分析的核心引擎。对外提供按量付费（SQL 扫描量）或预留 CU（计算单元）两种模式。

**定位**：不是通用数据库，而是**批处理为主的数据仓库**。与 BigQuery 定位最接近（Serverless + 按扫描计费），但生态绑定阿里云。

## 历史与演进

| 时间 | 事件 | 技术意义 |
|------|------|---------|
| 2010 | ODPS 在阿里内部启动 | 替代 Hadoop MapReduce 的自研计算平台 |
| 2014 | 作为阿里云服务对外开放 | 与 BigQuery (2010)、Redshift (2012) 同期的云数仓 |
| 2016 | 更名 MaxCompute，SQL 2.0 | 从 Hive 兼容方言升级为更接近标准 SQL |
| 2018 | 事务表 (Transactional Table) | Hive 风格引擎首次支持行级 UPDATE/DELETE |
| 2020 | Delta Table、Schema Evolution | 追赶 Delta Lake/Iceberg 的数据湖能力 |
| 2022 | MCQA 秒级交互查询 | 从纯批处理向交互式分析扩展 |
| 2024 | Lakehouse 集成、JSON 原生类型 | 存算分离、与 Hudi/Delta/Iceberg 互通 |

## 核心架构（对引擎开发者）

MaxCompute 的内部架构分为三层，每层都有值得学习的设计：

### 存储层：盘古 (Pangu) + AliORC

- **盘古**：阿里自研的分布式文件系统（类似 HDFS 但更适合云场景），是 MaxCompute 的存储底座
- **AliORC**：基于 Apache ORC 优化的列式文件格式，增加了：
  - C++ Arrow 内存格式支持（加速向量化计算）
  - 自适应字典编码（根据数据特征自动选择编码方式）
  - 异步预读 + I/O 模式管理（减少存储延迟影响）
  - 增强的谓词下推（在 I/O 层面跳过不需要的数据）
- **对引擎开发者的启示**：列式存储格式的性能差异主要来自编码策略和 I/O 优化，而非格式本身。AliORC 在 ORC 基础上的优化方向值得参考。

### 计算层：伏羲 (Fuxi) 调度 + 向量化引擎

- **伏羲**：阿里自研的分布式资源管理和任务调度系统（类似 YARN 但更轻量），负责将 SQL 编译后的 DAG 分配到计算节点
- **查询优化器**：基于 Apache Calcite 框架实现 RBO + CBO + HBO（History-Based Optimization）三层优化
  - HBO 利用历史执行统计信息优化后续查询——这是超越传统 CBO 的创新点
  - Adaptive Join：运行时在 Hash Join 和 Merge Join 之间动态切换
- **对引擎开发者的启示**：HBO（基于历史执行的优化）在反复执行的 ETL 场景中效果显著，值得投资。

### 元数据层：BigMeta

- 单集群管理上亿张表、上百亿分区和列的元数据
- **对引擎开发者的启示**：大规模元数据管理（千万级表）是大数据引擎的隐藏瓶颈，Hive Metastore 的单点问题在 MaxCompute 中通过自研 BigMeta 解决。

## SQL 方言设计分析

MaxCompute SQL 的设计处于 Hive SQL 和标准 SQL 之间，有几个值得注意的设计选择：

### 类型系统：1.0 vs 2.0

```sql
-- 1.0 类型系统（默认，Hive 兼容）：只有 BIGINT/DOUBLE/STRING/BOOLEAN/DATETIME
-- 2.0 类型系统（需开启）：增加 TINYINT/SMALLINT/INT/FLOAT/VARCHAR/CHAR/DECIMAL/TIMESTAMP/BINARY/ARRAY/MAP/STRUCT/JSON
SET odps.sql.type.system.odps2 = true;
```

**设计分析**：两套类型系统并存是历史包袱。1.0 的极简类型系统（所有整数都是 BIGINT，所有字符串都是 STRING）虽然简化了实现，但导致了：
- 从 MySQL/PostgreSQL 迁移时的类型映射困难
- 精度损失（所有整数占 8 字节，浪费存储）
- 2.0 修正了这个问题，但默认关闭以保持兼容性

### INSERT OVERWRITE：核心写入模式

```sql
-- 这是 MaxCompute 最重要的写入操作（不是 UPDATE/DELETE）
INSERT OVERWRITE TABLE orders PARTITION(dt='2024-01-15')
SELECT * FROM staging_orders WHERE dt = '2024-01-15';
```

**设计分析**：INSERT OVERWRITE 的语义是**原子性替换整个分区的数据**。这是 Hive 族引擎的核心设计——不做行级更新，而是重写整个分区。优势是实现简单（文件级替换）且幂等（重跑不会产生重复数据）。代价是无法做行级变更（2.0 事务表补充了这个能力）。

### 分区列不是普通列

```sql
CREATE TABLE orders (id BIGINT, amount DECIMAL(10,2))
PARTITIONED BY (dt STRING, region STRING);  -- dt 和 region 不在数据文件中！
```

**设计分析**：分区列值编码在目录路径中（`/orders/dt=2024-01-15/region=cn/`），不存储在数据文件中。这与 BigQuery/Snowflake 的分区设计不同——后者的分区列是普通列。MaxCompute 的设计来自 Hive，优势是分区裁剪可以在文件系统层面完成（不需要读取数据文件），代价是分区列和普通列的行为不一致。

### LIFECYCLE：存储治理的 DDL 化

```sql
CREATE TABLE logs (...) LIFECYCLE 90;  -- 90 天后自动删除
```

**设计分析**：将 TTL 作为表级 DDL 属性是 MaxCompute 的独创。对比其他引擎：
- ClickHouse：TTL 在表引擎中定义（`TTL timestamp + INTERVAL 90 DAY`）
- BigQuery：`partition_expiration_days` 选项
- Hive：无内置 TTL，依赖外部调度删除旧分区
- MaxCompute 的 LIFECYCLE 对整个表或分区生效，是数据治理最简洁的方案

## 独特特色

| 特性 | 说明 | 对比其他引擎 |
|---|---|---|
| **LIFECYCLE** | `CREATE TABLE t (...) LIFECYCLE 90` | ClickHouse TTL、BigQuery partition_expiration 的简化版 |
| **事务表 + Time Travel** | ACID 表支持 `SELECT * FROM t TIMESTAMP AS OF '...'` | 类似 Delta Lake / Iceberg |
| **Tunnel 批量导入** | 高吞吐 SDK 级数据通道，支持断点续传 | 类似 BigQuery Storage Write API |
| **MCQA 加速** | 对小查询自动使用交互式引擎 | 类似 BigQuery BI Engine |
| **Quota Group** | 多租户计算资源配额隔离 | 类似 Snowflake Virtual Warehouse |
| **Script Mode** | 多语句脚本模式，支持变量和流程控制 | 类似 BigQuery Scripting |
| **AliORC + 谓词下推** | 存储层自适应编码 + I/O 优化 | 超越标准 ORC 的读取性能 |

## 已知的设计不足与历史包袱

### 1. 两套类型系统并存
1.0 类型系统（BIGINT/STRING 为主）和 2.0 类型系统需要手动切换，导致同一项目内不同表可能使用不同类型系统，类型转换行为不一致。

### 2. SQL 兼容性差异大
- `INSERT INTO table VALUES(...)` 的 VALUES 子句在某些场景下行为与标准 SQL 不同
- `SELECT 1;` 不合法（需要 `SELECT 1 FROM dual;` 或使用 VALUES 语法）
- 字符串比较默认大小写敏感（与 MySQL 默认不敏感相反）
- 这些差异使得从 MySQL/PostgreSQL 迁移有较高学习成本

### 3. 普通表不支持 UPDATE/DELETE
只有事务表（Transactional Table）才支持行级变更。普通表（绝大多数存量表）只能用 INSERT OVERWRITE 整个分区来"更新"数据。对 CDC 和实时数据湖场景不友好。

### 4. 生态绑定阿里云
无法在其他云或本地部署。对比 Snowflake（多云）、BigQuery（GCP 专有但有 Omni）、Databricks（多云），MaxCompute 的供应商锁定更强。

### 5. 批处理延迟
传统作业模式下最快也需要数秒启动，不适合毫秒级交互查询。MCQA 在一定程度上缓解了这个问题，但仍不如 Hologres（同是阿里云产品，定位实时数仓）。

### 6. 存储过程支持弱
Script Mode 提供了变量和流程控制，但远不如 PL/SQL 或 PL/pgSQL 强大。复杂的 ETL 流程通常需要依赖 DataWorks 调度平台。

## 与同类引擎的关键对比

| 维度 | MaxCompute | BigQuery | Snowflake | Hive | Databricks |
|------|-----------|---------|-----------|------|-----------|
| 部署模式 | 阿里云专有 | GCP 专有 | 多云 | 开源 | 多云 |
| 计费模式 | CU 预留/按量 | 按扫描量 | 按 Warehouse 时间 | 集群资源 | DBU |
| 存储格式 | AliORC | Capacitor | 微分区 | ORC/Parquet | Delta Lake |
| 行级 UPDATE | 事务表(2018+) | 支持 | 支持 | ACID 表(0.14+) | Delta(2017+) |
| LIFECYCLE/TTL | ✅ 原生 | ✅ partition_expiration | ❌ 需手动 | ❌ 需调度 | ❌ 需手动 |
| 交互式查询 | MCQA | BI Engine | 默认交互式 | LLAP | Photon |
| 元数据规模 | 亿级表 | 大规模 | 大规模 | MetaStore 瓶颈 | Unity Catalog |

## 对引擎开发者的参考价值

### 1. LIFECYCLE（TTL）作为 DDL 属性
将数据过期策略声明在建表语句中，是目前最简洁的存储治理方案。避免了维护外部定时任务的运维成本。建议新引擎在 CREATE TABLE 语法中原生支持 TTL/LIFECYCLE。

### 2. HBO（History-Based Optimization）
基于历史执行统计优化后续查询，是对 CBO 的有力补充。在 ETL 管线中同一查询反复执行，HBO 可以利用上一次的 runtime statistics 生成更优的执行计划。

### 3. 两套类型系统的教训
类型系统一旦发布就极难更改。MaxCompute 1.0 的极简类型（一切整数都是 BIGINT）简化了早期实现，但 2.0 需要引入第二套类型系统来修正，增加了长期维护成本。**新引擎应从第一天就使用完整的类型系统**。

### 4. 事务表的增量实现
在 Hive 风格的不可变文件之上叠加事务能力（delta file + compaction），是数据湖引擎事务化的通用模式。MaxCompute、Hive ACID、Delta Lake、Iceberg 都采用了类似架构。

### 5. 分区与数据治理的深度绑定
MaxCompute 的分区不只是查询优化手段，还是数据治理的核心单元——LIFECYCLE、INSERT OVERWRITE、权限控制都以分区为粒度。这种"分区即管理单元"的设计在大数据场景中非常实用。

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
