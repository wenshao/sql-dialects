# 现代 SQL 特性对比目录

本目录收录 169 篇 SQL 方言对比文章，每篇横向对比 40+ 数据库在某一特性上的语法设计与实现差异，面向 SQL 引擎开发者。

---

## 查询语法

### 基础查询
- [LIMIT / OFFSET / FETCH 分页语法](limit-offset-fetch.md)
- [FETCH FIRST ... WITH TIES](fetch-with-ties.md)
- [VALUES 子句构造常量表](values-clause.md)
- [SELECT * EXCLUDE / REPLACE 列排除语法](select-exclude-replace.md)

### 集合与分组
- [集合运算 UNION / INTERSECT / EXCEPT](set-operations.md)
- [MULTISET 集合运算](multiset-operations.md)
- [GROUPING SETS / CUBE / ROLLUP](grouping-sets-cube-rollup.md)
- [GROUP BY ALL](group-by-all.md)
- [QUALIFY 子句](qualify.md)
- [FILTER 子句对聚合的条件过滤](filter-clause.md)

### 递归与层次
- [CTE 与递归查询](cte-recursive-query.md)
- [递归 CTE 增强特性（SEARCH/CYCLE）](recursive-cte-enhancements.md)
- [子查询与半连接优化](subquery-optimization.md)

### 行列变换
- [PIVOT / UNPIVOT 行列转换](pivot-unpivot.md)
- [PIVOT / UNPIVOT 原生语法对比](pivot-unpivot-native.md)
- [UNNEST / EXPLODE / 数组展开](unnest-explode.md)
- [LIMIT BY / LATERAL BY 按分组取行](limit-by.md)

### 伪列与元数据
- [伪列 (ROWID / ROWNUM / LEVEL)](pseudo-columns.md)

### 采样
- [TABLESAMPLE 采样语法](sampling-query.md)
- [TABLESAMPLE 子句](tablesample.md)

### 模式匹配
- [MATCH_RECOGNIZE 行模式匹配](match-recognize.md)

### 排序与 Top-K
- [Top-K 查询优化](top-k-optimization.md)
- [NULLS FIRST/LAST 排序](null-ordering.md)

### SQL 解析器
- [SQL 解析器差异（大小写/引用/保留字）](sql-parser-differences.md)

---

## 连接

- [LATERAL JOIN / CROSS APPLY](lateral-join.md)
- [ASOF JOIN 时间点连接](asof-join.md)
- [分布式 JOIN 策略](distributed-join-strategies.md)

---

## 窗口函数

- [窗口函数高级语法](window-function-advanced-syntax.md)
- [窗口函数执行模型](window-function-execution.md)
- [RANGE / ROWS / GROUPS 窗口框架](window-frame-groups.md)
- [WITHIN GROUP 有序集合函数](within-group.md)

---

## DML

- [MERGE INTO / UPSERT 语法](merge-into.md)
- [UPSERT / ON CONFLICT / ON DUPLICATE KEY](upsert-merge-syntax.md)
- [INSERT OVERWRITE](insert-overwrite.md)
- [RETURNING / OUTPUT 子句](returning-output.md)
- [DML RETURNING 与 MERGE 深度对比](dml-returning-merge.md)
- [批处理 INSERT 优化](batch-insert-optimization.md)
- [自增锁与序列并发](auto-increment-locking.md)
- [TRUNCATE vs DELETE 深度对比](truncate-vs-delete.md)

---

## DDL

### 表结构
- [ALTER TABLE 语法对比](alter-table-syntax.md)
- [CREATE OR REPLACE 语法](create-or-replace.md)
- [临时表](temporary-tables.md)
- [约束语法](constraint-syntax.md)
- [生成列与计算列](generated-computed-columns.md) · [旧版](generated-columns.md)
- [AUTO_INCREMENT / SEQUENCE / IDENTITY](auto-increment-sequence-identity.md)
- [外部表](external-tables.md)
- [可更新视图规则](updatable-views.md)

### 存储架构
- [可插拔存储引擎](pluggable-storage-engines.md)
- [表空间与文件布局](tablespace-file-layout.md)
- [表与列压缩](table-column-compression.md)
- [分片键与分布键](shard-key-distribution.md)
- [分层存储 (热/温/冷)](tiered-storage.md)
- [复合主键设计](composite-primary-keys.md)
- [Schema 演进模式](schema-evolution.md)
- [热点写入缓解 (AUTO_RANDOM / UUID v7)](hotspot-write-mitigation.md)

### 索引
- [索引类型与创建语法](index-types-creation.md)
- [覆盖索引 (INCLUDE / STORING)](covering-indexes.md)
- [表达式索引 (函数索引)](expression-indexes.md)
- [部分索引 (WHERE 条件过滤)](partial-indexes.md)
- [布隆过滤器索引](bloom-filter-indexes.md)
- [分区策略对比](partition-strategy-comparison.md)
- [分区裁剪](partition-pruning.md)

### DDL 事务性 / 在线 DDL
- [DDL 事务性与在线 DDL](ddl-transactionality-online.md)
- [在线 DDL 实现机制](online-ddl-implementation.md)

### 时态表
- [时态表 / 系统版本控制](temporal-tables.md)
- [系统版本查询 (FOR SYSTEM_TIME AS OF / Time Travel)](system-versioned-queries.md)
- [PERIOD / 范围类型](range-period-types.md)

### 元数据
- [COMMENT 与描述元数据](comment-metadata.md)

---

## 数据类型

- [数据类型映射](data-type-mapping.md)
- [类型系统设计](type-system-design.md)
- [域类型与用户定义类型 (CREATE DOMAIN / UDT)](domain-types.md)
- [BLOB/CLOB 大对象处理](blob-clob-handling.md)
- [数组 / 集合类型 (ARRAY/MAP/STRUCT)](array-collection-types.md)
- [行类型与复合类型 (ROW / STRUCT)](row-composite-types.md)
- [JSON 在 SQL 中的演进](json-in-sql-evolution.md)
- [JSON Path 语法](json-path-syntax.md)
- [JSON_TABLE](json-table.md)
- [JSON 模式验证 (IS JSON / JSON Schema)](json-schema-validation.md)
- [半结构化数据支持](semi-structured-data.md)

### 类型转换与 NULL
- [隐式 / 显式类型转换](implicit-explicit-type-conversion.md)
- [NULL 语义](null-semantics.md)
- [NULL 处理行为](null-handling-behavior.md)
- [NULL 安全比较](null-safe-comparison.md)
- [算术溢出与除零](arithmetic-overflow-division.md)

### 字符集与排序
- [字符集与排序规则](charset-collation.md)
- [字符串比较与 COLLATE](string-comparison-collation.md)
- [字符集转换函数](charset-conversion-functions.md)

### 时区
- [时区处理 (TIMESTAMPTZ / AT TIME ZONE)](timezone-handling.md)

---

## 函数

### 核心函数映射
- [字符串函数映射](string-functions-mapping.md)
- [日期时间函数映射](datetime-functions-mapping.md)
- [聚合函数对比](aggregate-functions-comparison.md)
- [条件表达式 CASE / IF / COALESCE](conditional-expressions.md)

### 专用聚合
- [近似聚合函数（APPROX_*）](approx-functions.md)
- [ARG_MIN / ARG_MAX](argmin-argmax.md)
- [ANY_VALUE / 非分组列](any-value-grouping.md)
- [STRING_AGG 演进](string-agg-evolution.md)

### 生成与展开
- [集合返回函数](set-returning-functions.md)

### 高级函数
- [正则表达式语法](regex-syntax.md)
- [Lambda 表达式](lambda-expressions.md)
- [函数与操作符重载](function-operator-overloading.md)

---

## 搜索

- [全文检索](full-text-search.md)
- [分词器与文本分析器](tokenization-analyzers.md)
- [地理空间函数](geospatial-functions.md)
- [向量类型与相似性搜索](vector-similarity-search.md)

---

## 视图

- [物化视图](materialized-views.md)
- [物化视图模式](materialized-view-patterns.md)
- [物化视图刷新策略](materialized-view-refresh.md)

---

## 事务与并发

- [MVCC 实现机制](mvcc-implementation.md)
- [事务隔离级别对比](transaction-isolation-comparison.md)
- [锁机制与死锁检测](locks-deadlocks.md)
- [元数据锁 (MDL / Schema Lock)](metadata-locks.md)
- [WAL / Redo 日志与持久化配置](wal-checkpoint-durability.md)
- [WAL 归档与 PITR](wal-archiving.md)
- [崩溃恢复 (ARIES)](crash-recovery.md)
- [VACUUM 与垃圾回收](vacuum-gc.md)
- [SAVEPOINT 保存点](savepoints.md)
- [分布式事务 XA / 2PC](distributed-transactions-xa.md)

---

## 执行与优化

- [EXPLAIN 执行计划](explain-execution-plan.md)
- [EXPLAIN 输出格式 (TEXT/JSON/XML)](explain-output-formats.md)
- [查询执行阶段 (Parser → Optimizer → Executor)](query-execution-phases.md)
- [优化器演进](optimizer-evolution.md)
- [预编译语句与计划缓存](prepared-statement-cache.md)
- [查询结果缓存](query-result-caching.md)
- [缓冲池管理](buffer-pool-management.md)
- [资源管理与工作负载管理 (WLM)](resource-management-wlm.md)
- [并行查询执行](parallel-query-execution.md)
- [查询提示 (Query Hints)](query-hints.md)
- [查询重写规则](query-rewrite-rules.md)
- [查询取消与超时控制](query-cancellation-timeouts.md)
- [Hash Join 算法变体](hash-join-algorithms.md)
- [列裁剪与投影下推](column-pruning-pushdown.md)
- [统计信息与直方图](statistics-histograms.md)
- [慢查询日志与性能监控](slow-query-log.md)
- [I/O 监控与读写统计](io-monitoring.md)
- [内存使用监控](memory-usage-monitoring.md)
- [查询计划稳定性 (SPM / Query Store)](query-plan-stability.md)
- [临时空间管理 (spill to disk)](temp-space-management.md)

---

## 存储过程与编程

- [存储过程与 UDF](stored-procedures-udf.md)
- [外部 UDF 与原生扩展 (C/Java/Python/JS/Rust/WASM)](udf-external-functions.md)
- [触发器](triggers.md)
- [游标](cursors.md)
- [动态 SQL](dynamic-sql.md)
- [错误处理](error-handling.md)
- [安全错误处理](error-handling-safe.md)
- [变量与会话管理](variables-sessions.md)
- [连接池与会话管理](connection-pooling.md)
- [数据库 Wire 协议](wire-protocols.md)

---

## 数据加载与复制

- [批量导入导出](bulk-import-export.md) · [旧版](copy-bulk-load.md)
- [CDC / Changefeed 变更捕获](cdc-changefeed.md)
- [逻辑复制与 GTID](logical-replication-gtid.md)
- [跨区域地理复制](geo-replication.md)
- [外部数据源与数据库链接 (FDW / dblink)](foreign-data-wrappers.md)
- [备份与恢复语法](backup-restore-syntax.md)
- [数据库事件通知 (LISTEN/NOTIFY / Service Broker)](database-events-notify.md)

---

## 安全

- [权限与安全模型](permission-security-model.md) · [权限模型设计](permission-model-design.md)
- [角色与授权粒度 (CREATE ROLE / GRANT)](roles-grants-permissions.md)
- [行级安全 (RLS)](row-level-security.md)
- [审计日志](audit-logging.md)
- [数据血缘与查询溯源](data-lineage.md)
- [透明数据加密 (TDE)](transparent-data-encryption.md)
- [数据遮罩与脱敏](data-masking.md)
- [SSL/TLS 连接加密](ssl-tls-encryption.md)

---

## 元数据与系统目录

- [系统目录与信息模式 (INFORMATION_SCHEMA / pg_catalog / sys.*)](information-schema-catalogs.md)

---

## 存储引擎基础

- [B+Tree vs LSM-Tree 存储引擎对比](btree-vs-lsm.md)

---

## 领域专题

- [图查询 (SQL/PGQ)](graph-queries.md)
- [时序数据处理](time-series-functions.md)
- [湖仓表格式 (Iceberg/Delta/Hudi)](lakehouse-table-formats.md)

---

## 阅读建议

按目标场景推荐阅读顺序：

**做 SQL 引擎兼容层设计** → 先读 [数据类型映射](data-type-mapping.md)、[NULL 语义](null-semantics.md)、[字符串函数映射](string-functions-mapping.md)、[类型转换](implicit-explicit-type-conversion.md)，这四篇覆盖了跨方言迁移 80% 的坑。

**实现查询优化器** → [子查询优化](subquery-optimization.md)、[分布式 JOIN](distributed-join-strategies.md)、[窗口函数执行](window-function-execution.md)、[EXPLAIN](explain-execution-plan.md)、[优化器演进](optimizer-evolution.md)。

**设计 DDL / Catalog** → [ALTER TABLE](alter-table-syntax.md)、[约束语法](constraint-syntax.md)、[索引类型](index-types-creation.md)、[分区策略](partition-strategy-comparison.md)、[DDL 事务性](ddl-transactionality-online.md)。

**做 OLAP 引擎** → [GROUPING SETS](grouping-sets-cube-rollup.md)、[PIVOT](pivot-unpivot.md)、[采样](sampling-query.md)、[近似聚合](approx-functions.md)、[QUALIFY](qualify.md)、[物化视图](materialized-views.md)。

**做流处理 / 时序引擎** → [时序函数](time-series-functions.md)、[MATCH_RECOGNIZE](match-recognize.md)、[ASOF JOIN](asof-join.md)、[CDC](cdc-changefeed.md)、[时态表](temporal-tables.md)。

**做 OLTP 引擎** → [MVCC](mvcc-implementation.md)、[事务隔离](transaction-isolation-comparison.md)、[UPSERT](upsert-merge-syntax.md)、[生成列](generated-computed-columns.md)、[触发器](triggers.md)、[错误处理](error-handling.md)。
