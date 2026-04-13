# 现代 SQL 特性对比目录

本目录收录 94 篇 SQL 方言对比文章，每篇横向对比 40+ 数据库在某一特性上的语法设计与实现差异，面向 SQL 引擎开发者。

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

### 采样
- [TABLESAMPLE 采样语法](sampling-query.md)
- [TABLESAMPLE 子句](tablesample.md)

### 模式匹配
- [MATCH_RECOGNIZE 行模式匹配](match-recognize.md)

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

### 索引
- [索引类型与创建语法](index-types-creation.md)
- [分区策略对比](partition-strategy-comparison.md)

### DDL 事务性 / 在线 DDL
- [DDL 事务性与在线 DDL](ddl-transactionality-online.md)
- [在线 DDL 实现机制](online-ddl-implementation.md)

### 时态表
- [时态表 / 系统版本控制](temporal-tables.md)
- [PERIOD / 范围类型](range-period-types.md)

---

## 数据类型

- [数据类型映射](data-type-mapping.md)
- [类型系统设计](type-system-design.md)
- [数组 / 集合类型 (ARRAY/MAP/STRUCT)](array-collection-types.md)
- [JSON 在 SQL 中的演进](json-in-sql-evolution.md)
- [JSON Path 语法](json-path-syntax.md)
- [JSON_TABLE](json-table.md)
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

---

## 搜索

- [全文检索](full-text-search.md)
- [地理空间函数](geospatial-functions.md)

---

## 视图

- [物化视图](materialized-views.md)
- [物化视图模式](materialized-view-patterns.md)

---

## 事务与并发

- [MVCC 实现机制](mvcc-implementation.md)
- [事务隔离级别对比](transaction-isolation-comparison.md)

---

## 执行与优化

- [EXPLAIN 执行计划](explain-execution-plan.md)
- [优化器演进](optimizer-evolution.md)

---

## 存储过程与编程

- [存储过程与 UDF](stored-procedures-udf.md)
- [触发器](triggers.md)
- [游标](cursors.md)
- [动态 SQL](dynamic-sql.md)
- [错误处理](error-handling.md)
- [安全错误处理](error-handling-safe.md)
- [变量与会话管理](variables-sessions.md)

---

## 数据加载与复制

- [批量导入导出](bulk-import-export.md) · [旧版](copy-bulk-load.md)
- [CDC / Changefeed 变更捕获](cdc-changefeed.md)

---

## 安全

- [权限与安全模型](permission-security-model.md) · [权限模型设计](permission-model-design.md)
- [行级安全 (RLS)](row-level-security.md)

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
