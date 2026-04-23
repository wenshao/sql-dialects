# 不可见索引 (Invisible/Unusable Indexes)

删除一个使用中的索引可能是 DBA 最紧张的操作——一旦错误，生产系统瞬间退化。不可见索引让你先"假删除"再"真删除"，在不可逆的 DDL 面前构建可回滚的验证路径。

## 没有 SQL 标准定义

与 `TABLESAMPLE`、`MERGE`、`PIVOT` 等语法不同，**SQL 标准 (ISO/IEC 9075) 从未定义不可见索引 (invisible indexes) 概念**。这是一个由商业数据库厂商独立发明、各自演化的特性：

- Oracle 11g Release 1 (2007) 首次引入 `INVISIBLE` 关键字
- MySQL 8.0 (2018) 借鉴 Oracle 语法，同样使用 `INVISIBLE`
- MariaDB 10.6 (2021) 使用不同关键字 `IGNORED`（避免与 MySQL 未来扩展语义冲突）
- PostgreSQL 至今没有原生支持，需借助第三方扩展 (pg_hint_plan + HypoPG)

由于缺少标准约束，各引擎的语法、语义、粒度、与其他特性的交互都不一致。工程师跨引擎迁移时，必须逐一验证。

## 核心概念

### 什么是不可见索引？

**不可见索引 (Invisible Index)**：索引物理存在于磁盘上，DML 操作（INSERT/UPDATE/DELETE）会维护它，但查询优化器默认**不会选择**它来生成执行计划。

典型应用场景：

1. **安全删除模拟**：把索引设为不可见，观察一段时间，确认没有查询退化后再 DROP
2. **索引调优实验**：创建新索引但先设为不可见，用 hint 强制测试，避免影响生产
3. **临时禁用**：某个索引在维护窗口期性能退化，先禁用再重建
4. **多租户/AB 测试**：同一表的不同索引组合在不同查询路径下测试效果

### 与相关概念的区别

| 概念 | 物理存在 | DML 维护 | 优化器可见 | 可通过 Hint 使用 | 典型引擎 |
|------|---------|---------|-----------|----------------|---------|
| INVISIBLE | 是 | 是 | 否（默认） | 是 | Oracle, MySQL, TiDB, OceanBase |
| UNUSABLE | 是（头块） | **否** | 否 | 否 | Oracle |
| DISABLED | **否**（物理删除） | -- | 否 | 否 | SQL Server |
| IGNORED | 是 | 是 | 否 | **否** | MariaDB |
| INACTIVE | 是 | 是 | 否 | 否 | DB2 |
| Hypothetical | **否**（仅统计） | 否 | 是（仅 EXPLAIN） | -- | PostgreSQL (HypoPG) |

关键差异：**DML 维护成本**和**可通过 hint 强制使用**是区分各种"非活跃索引"状态的核心维度。

## 支持矩阵（综合）

### INVISIBLE / 等价语法支持

| 引擎 | 关键字 | DDL 语法 | DML 维护 | 版本 |
|------|--------|----------|---------|------|
| Oracle | `INVISIBLE` | `CREATE/ALTER INDEX ... INVISIBLE` | 是 | 11g R1 (2007) |
| MySQL | `INVISIBLE` | `CREATE/ALTER INDEX ... INVISIBLE` | 是 | 8.0 (2018) |
| MariaDB | `IGNORED` | `ALTER INDEX ... IGNORED` | 是 | 10.6 (2021) |
| PostgreSQL | -- | 需扩展 (HypoPG 假索引) | -- | 不原生支持 |
| SQL Server | -- | `ALTER INDEX ... DISABLE` 是**物理禁用** | 否 | -- |
| DB2 | `INACTIVE` | `ALTER INDEX ... INACTIVE` | 是 | LUW 11.5 |
| Snowflake | -- | 无索引概念 | -- | 不适用 |
| BigQuery | -- | 无传统索引（仅 search index） | -- | 不适用 |
| Redshift | -- | 无索引概念（sort key / dist key） | -- | 不适用 |
| DuckDB | -- | 不支持 | -- | -- |
| ClickHouse | -- | 不支持（skipping index 不适用） | -- | -- |
| Trino | -- | 无索引概念（存算分离） | -- | 不适用 |
| Presto | -- | 同 Trino | -- | 不适用 |
| Spark SQL | -- | 不支持 | -- | -- |
| Hive | -- | 历史索引已废弃 | -- | 不适用 |
| Flink SQL | -- | 无索引概念（流处理） | -- | 不适用 |
| Databricks | -- | 不支持（bloom filter index 不适用） | -- | -- |
| Teradata | -- | 不支持 | -- | -- |
| Greenplum | -- | 继承 PG，不原生支持 | -- | -- |
| CockroachDB | `NOT VISIBLE` | `CREATE/ALTER INDEX ... NOT VISIBLE` | 是 | 22.2+ |
| TiDB | `INVISIBLE` | `CREATE/ALTER INDEX ... INVISIBLE` | 是 | 8.0+ |
| OceanBase | `INVISIBLE` | `ALTER INDEX ... INVISIBLE`（MySQL 模式） | 是 | 4.0+ |
| YugabyteDB | -- | 不支持（继承 PG） | -- | -- |
| SingleStore | -- | 不支持 | -- | -- |
| Vertica | -- | 无传统 B-tree 索引 | -- | 不适用 |
| Impala | -- | 无索引概念 | -- | 不适用 |
| StarRocks | -- | 不支持（有 bloom filter 但不涉及可见性） | -- | -- |
| Doris | -- | 不支持 | -- | -- |
| MonetDB | -- | 不支持 | -- | -- |
| CrateDB | -- | 不支持 | -- | -- |
| TimescaleDB | -- | 继承 PG，不原生支持 | -- | -- |
| QuestDB | -- | 无索引概念（列存） | -- | 不适用 |
| Exasol | -- | 不支持（索引自动管理） | -- | 不适用 |
| SAP HANA | -- | 不支持 | -- | -- |
| Informix | -- | 不支持 | -- | -- |
| Firebird | -- | `ALTER INDEX ... INACTIVE` 是物理禁用 | 否 | -- |
| H2 | -- | 不支持 | -- | -- |
| HSQLDB | -- | 不支持 | -- | -- |
| Derby | -- | 不支持 | -- | -- |
| Amazon Athena | -- | 继承 Trino，无索引 | -- | 不适用 |
| Azure Synapse | -- | `ALTER INDEX ... DISABLE` 物理禁用 | 否 | -- |
| Google Spanner | -- | 不支持 | -- | -- |
| Materialize | -- | 索引自动，无可见性概念 | -- | 不适用 |
| RisingWave | -- | 不支持 | -- | -- |
| InfluxDB | -- | 无传统索引 | -- | 不适用 |
| DatabendDB | -- | 不支持 | -- | -- |
| Yellowbrick | -- | 不支持 | -- | -- |
| Firebolt | -- | 无传统索引（aggregating index 特殊） | -- | 不适用 |

> 统计：约 7 个引擎原生支持"不可见但 DML 维护"的索引（Oracle、MySQL、MariaDB、DB2、CockroachDB、TiDB、OceanBase）；约 3 个引擎的"禁用"实际是物理删除（SQL Server、Firebird、Azure Synapse）；多数现代分析引擎（Snowflake、BigQuery、Redshift、ClickHouse 等）因无传统索引概念而不适用。

### UNUSABLE / DISABLED / 物理禁用状态

| 引擎 | 关键字 | 物理状态 | DML 行为 | 重新可用方式 |
|------|--------|---------|---------|-------------|
| Oracle | `UNUSABLE` | 头块保留，段标记不可用 | DML 不维护；对唯一索引的 DML 报错 | `ALTER INDEX ... REBUILD` |
| SQL Server | `DISABLE` | **B-tree 物理移除**（仅元数据） | 对聚簇索引会使表不可查询 | `ALTER INDEX ... REBUILD` |
| Azure Synapse | `DISABLE` | 同 SQL Server | 同 SQL Server | `REBUILD` |
| Firebird | `INACTIVE` | 索引元数据保留，内部结构丢弃 | 不维护 | `ALTER INDEX ... ACTIVE` |
| DB2 LUW | -- | 不支持物理禁用 | -- | -- |
| MySQL | -- | 不支持（只有 INVISIBLE） | -- | -- |
| MariaDB | -- | 不支持 | -- | -- |
| PostgreSQL | -- | 不支持（可手动 DROP 重建） | -- | -- |

### Hint / 强制使用支持

| 引擎 | Hint 强制使用不可见索引 | 语法 |
|------|----------------------|------|
| Oracle | 是（会话/语句级） | `ALTER SESSION SET OPTIMIZER_USE_INVISIBLE_INDEXES = TRUE` 或 Hint |
| MySQL | 是（会话级） | `SET SESSION optimizer_switch = 'use_invisible_indexes=on'` |
| MariaDB | **否**（IGNORED 完全被忽略） | 无法通过任何 Hint 启用 |
| TiDB | 是 | `/*+ USE_INDEX(...) */` Hint 对 INVISIBLE 有效 |
| OceanBase | 是 | Hint 强制使用 |
| CockroachDB | 是（视参数） | `optimizer_use_not_visible_indexes` |
| DB2 | 否 | INACTIVE 完全不参与优化 |
| PostgreSQL (HypoPG) | 仅 EXPLAIN | 假索引只影响代价估算 |

### 优化器行为与可观测性

| 引擎 | 状态查询视图 | EXPLAIN 显示 | 统计信息维护 |
|------|-------------|-------------|-------------|
| Oracle | `USER_INDEXES.VISIBILITY` | 默认忽略，Hint 后显示 | 是（继续 GATHER_INDEX_STATS） |
| MySQL | `INFORMATION_SCHEMA.STATISTICS.IS_VISIBLE` | 默认忽略 | 是 |
| MariaDB | `INFORMATION_SCHEMA.STATISTICS.IGNORED` | 完全忽略 | 是 |
| TiDB | `INFORMATION_SCHEMA.TIDB_INDEXES.IS_VISIBLE` | 默认忽略 | 是 |
| DB2 | `SYSCAT.INDEXES.INDEX_STATUS` | 完全忽略 | 冻结（除非重新激活） |
| CockroachDB | `information_schema.statistics.is_visible` | 默认忽略 | 是 |

## Oracle：INVISIBLE 与 UNUSABLE 的本质区别

Oracle 是唯一清晰区分这两种状态的主流数据库，理解它们的差异是掌握索引管理的关键。

### INVISIBLE（11g R1 起）

```sql
-- 创建不可见索引
CREATE INDEX idx_emp_salary ON employees(salary) INVISIBLE;

-- 将现有索引设为不可见
ALTER INDEX idx_emp_dept INVISIBLE;

-- 恢复可见
ALTER INDEX idx_emp_dept VISIBLE;

-- 查询当前状态
SELECT index_name, visibility
FROM user_indexes
WHERE table_name = 'EMPLOYEES';
```

**语义要点**：
- 索引段（segment）完整保留
- 所有 DML 操作继续维护索引
- 优化器默认不考虑此索引
- 可通过参数或 Hint 强制使用
- 统计信息继续自动收集

### 启用 INVISIBLE 索引的三种方式

```sql
-- 方式 1：会话级参数
ALTER SESSION SET OPTIMIZER_USE_INVISIBLE_INDEXES = TRUE;

-- 方式 2：系统级参数（不推荐，违背设计初衷）
ALTER SYSTEM SET OPTIMIZER_USE_INVISIBLE_INDEXES = TRUE;

-- 方式 3：SQL Hint（最精确）
SELECT /*+ INDEX(e idx_emp_salary) */ *
FROM employees e
WHERE salary > 5000;
-- 注意：Oracle 12c 起，Hint 引用 INVISIBLE 索引需要同时打开参数
-- 或使用特殊 Hint USE_INVISIBLE_INDEXES
```

### UNUSABLE（更早就存在，8i 起）

```sql
-- 将索引设为不可用
ALTER INDEX idx_emp_dept UNUSABLE;

-- 对分区索引的单个分区
ALTER INDEX idx_sales_date UNUSABLE PARTITION p2024;

-- 重建后恢复
ALTER INDEX idx_emp_dept REBUILD;
```

**关键差异对比**：

| 维度 | INVISIBLE | UNUSABLE |
|------|-----------|----------|
| 索引段状态 | 完整保留 | 仅保留头块（metadata） |
| DML 维护开销 | **有**（与可见索引相同） | **无**（DML 跳过此索引） |
| 唯一索引的 INSERT | 正常（维护唯一性） | **报错 ORA-01502** |
| 非唯一索引的 DML | 正常 | 跳过，DML 成功 |
| 恢复方式 | `VISIBLE` 即可 | 必须 `REBUILD`（重建成本高） |
| 占用磁盘空间 | 几乎全部 | 仅头块 |
| 优化器行为 | 默认忽略 | 永远忽略 |
| 可 Hint 强制使用 | 是 | **否** |
| 典型用途 | 模拟删除、实验 | 大批量 ETL 前临时禁用 |

### 组合使用场景：ETL 批量加载

```sql
-- 场景：向 10 亿行表加载 1 亿行新数据
-- 如果索引维护开销占加载时间的 60%，可以：

-- 方案 A：UNUSABLE（最大化加载速度）
ALTER INDEX idx_facts_product UNUSABLE;
ALTER INDEX idx_facts_date UNUSABLE;
ALTER INDEX idx_facts_customer UNUSABLE;

-- 执行批量加载（此时 DML 完全不维护索引）
INSERT /*+ APPEND */ INTO facts SELECT * FROM staging;

-- 重建索引（并行加速）
ALTER INDEX idx_facts_product REBUILD PARALLEL 8;
ALTER INDEX idx_facts_date REBUILD PARALLEL 8;
ALTER INDEX idx_facts_customer REBUILD PARALLEL 8;

-- 方案 B：INVISIBLE（不推荐用于 ETL）
-- DML 依然维护索引，没有加速效果
-- INVISIBLE 的目的是"对优化器隐藏"，不是"跳过 DML"
```

### 分区索引的细粒度控制

```sql
-- 可对分区索引的单个分区应用 UNUSABLE
CREATE INDEX idx_sales_region ON sales(region) LOCAL;

ALTER INDEX idx_sales_region UNUSABLE PARTITION sales_2020;
-- 2020 分区的索引不可用，其他分区正常

-- 查询分区状态
SELECT partition_name, status
FROM user_ind_partitions
WHERE index_name = 'IDX_SALES_REGION';
```

## MySQL 8.0：首个开源实现

MySQL 8.0 (2018 年 4 月 GA) 借鉴 Oracle 引入 INVISIBLE，是主流开源数据库首次提供此能力。

### 基础语法

```sql
-- 创建时指定
CREATE TABLE t1 (
    i INT,
    j INT,
    k INT,
    INDEX idx_i (i),
    INDEX idx_j (j) INVISIBLE,
    INDEX idx_k (k)
);

-- 建表后添加
CREATE INDEX idx_test ON t1(j, k) INVISIBLE;

-- 切换可见性
ALTER TABLE t1 ALTER INDEX idx_j VISIBLE;
ALTER TABLE t1 ALTER INDEX idx_j INVISIBLE;

-- 查询状态
SELECT INDEX_NAME, IS_VISIBLE
FROM INFORMATION_SCHEMA.STATISTICS
WHERE TABLE_SCHEMA = 'test' AND TABLE_NAME = 't1';
```

### 启用 INVISIBLE 索引的开关

```sql
-- 会话级启用
SET SESSION optimizer_switch = 'use_invisible_indexes=on';

-- 查看当前开关
SHOW VARIABLES LIKE 'optimizer_switch';

-- 验证效果
EXPLAIN SELECT * FROM t1 WHERE j = 5;
-- 默认：不会使用 idx_j
-- 开关打开后：可能使用 idx_j
```

### MySQL 的限制

```sql
-- 1. 主键不能设为 INVISIBLE
-- ALTER TABLE t1 ALTER INDEX PRIMARY INVISIBLE;  -- 错误

-- 2. 唯一约束对应的隐式索引不能设为 INVISIBLE
CREATE TABLE t2 (
    id INT PRIMARY KEY,
    email VARCHAR(100) UNIQUE
);
-- ALTER TABLE t2 ALTER INDEX email INVISIBLE;  -- MySQL 8.0 限制

-- 3. 外键依赖的索引可以设为 INVISIBLE（但不推荐）
-- 外键约束依然生效，但约束检查可能退化为全表扫描

-- 4. 不支持物理禁用（不像 Oracle 的 UNUSABLE）
-- MySQL 没有"不维护但保留元数据"的状态
```

### 实战模式：安全删除索引

```sql
-- Step 1: 观察索引的使用情况
SELECT index_name, rows_read
FROM sys.schema_index_statistics
WHERE table_schema = 'production'
  AND table_name = 'orders'
  AND index_name = 'idx_order_status';

-- Step 2: 设为不可见
ALTER TABLE orders ALTER INDEX idx_order_status INVISIBLE;

-- Step 3: 监控 24-48 小时
-- - 观察慢查询日志
-- - 监控应用延迟指标
-- - 检查 EXPLAIN 计划是否退化

-- Step 4a: 如果无异常，安全删除
ALTER TABLE orders DROP INDEX idx_order_status;

-- Step 4b: 如果发现退化，快速恢复
ALTER TABLE orders ALTER INDEX idx_order_status VISIBLE;
-- 注意：VISIBLE 是瞬间元数据变更，无需重建索引
```

### MySQL 8.0 vs Oracle 的语义差异

```sql
-- MySQL: 维护 INVISIBLE 索引是强制行为，不可关闭
-- Oracle: 同样维护 INVISIBLE 索引

-- MySQL: 通过 optimizer_switch 全局开关启用
-- Oracle: 通过会话参数或 Hint 启用（更细粒度）

-- MySQL: 不区分 INVISIBLE 与 UNUSABLE
-- Oracle: 有清晰的二分

-- MySQL: 隐式索引（PK/UK）不能设为 INVISIBLE
-- Oracle: 限制更宽松，但有其他约束
```

## MariaDB 10.6：有意为之的语义分叉

MariaDB 从 10.6 (2021) 开始支持此特性，但选择了不同的关键字 `IGNORED` 而非 MySQL 的 `INVISIBLE`。这是**有意的设计选择**，值得单独讨论。

### 语法

```sql
-- MariaDB 10.6+
ALTER TABLE t1 ALTER INDEX idx_j IGNORED;
ALTER TABLE t1 ALTER INDEX idx_j NOT IGNORED;

-- 查询状态
SELECT INDEX_NAME, IGNORED
FROM INFORMATION_SCHEMA.STATISTICS
WHERE TABLE_SCHEMA = 'test' AND TABLE_NAME = 't1';
```

### IGNORED 与 INVISIBLE 的语义差异

| 维度 | MySQL INVISIBLE | MariaDB IGNORED |
|------|----------------|-----------------|
| DML 维护 | 是 | 是 |
| 优化器默认行为 | 忽略 | 忽略 |
| 通过开关启用优化器使用 | 是 (`use_invisible_indexes=on`) | **否** |
| 通过 Hint 强制使用 | 是 | **否** |
| 唯一约束强制执行 | 是 | 是 |
| 外键约束检查 | 是 | 是 |

**核心差异**：MariaDB 的 IGNORED 是**完全彻底的**——没有任何办法让优化器使用它。这是一个"纯粹的模拟删除"状态。

### MariaDB 为何选择不同关键字？

官方设计文档解释：
1. **避免语义混淆**：如果使用 `INVISIBLE`，用户可能期望能像 MySQL/Oracle 那样通过 Hint 启用
2. **语义更严格**：`IGNORED` 明确表达"这个索引被忽略，没有开关"
3. **保留未来扩展空间**：如果未来需要支持 Hint 启用，可以单独加 `INVISIBLE` 关键字

### 实战：更纯粹的安全删除模拟

```sql
-- MariaDB 的 IGNORED 更接近真实 DROP INDEX 的行为
-- 因为即使 DBA 手误用 Hint，也不会"意外启用"

ALTER TABLE orders ALTER INDEX idx_order_status IGNORED;

-- 无论应用代码里是否有 FORCE INDEX / USE INDEX hints
-- 此索引都不会被使用
-- 完全模拟 DROP 后的效果
```

## PostgreSQL：没有原生支持，但有强大的生态

**截至 PostgreSQL 17（2024）仍没有原生的"不可见索引"语法**。这是 PG 社区长期以来的一个功能缺口，但生态提供了多种替代方案。

### pg_hint_plan + HypoPG 组合

**HypoPG** 是 PostgreSQL 的一个扩展，支持"假索引"（hypothetical indexes）——索引在优化器看来存在，但实际没有物理创建。

```sql
-- 安装扩展
CREATE EXTENSION hypopg;

-- 创建假索引
SELECT * FROM hypopg_create_index('CREATE INDEX ON orders (customer_id)');
-- 返回虚拟索引 OID 和名称

-- 查看当前所有假索引
SELECT * FROM hypopg_list_indexes();

-- 测试：优化器是否会使用这个索引？
EXPLAIN SELECT * FROM orders WHERE customer_id = 12345;
-- 如果假索引被选中，说明真创建此索引会改善性能

-- 测试完毕，删除假索引（不涉及磁盘）
SELECT hypopg_drop_index((SELECT indexrelid FROM hypopg_list_indexes()));

-- 或清空所有
SELECT hypopg_reset();
```

**HypoPG 的独特价值**：
- 评估"如果创建这个索引会怎样"，无需真实 CREATE INDEX 的 I/O 开销
- 可在只读副本上测试索引效果
- 大表创建索引可能耗时数小时，HypoPG 让决策变得"零成本"

### HypoPG 与 INVISIBLE 索引的对比

| 场景 | HypoPG (假索引) | INVISIBLE (真索引) |
|------|----------------|-------------------|
| 索引是否物理存在 | 否 | 是 |
| 是否维护 DML | 否（无法维护） | 是 |
| EXPLAIN 能看到 | 是（伪装选中） | 是（若 Hint 启用） |
| EXPLAIN ANALYZE | 否（无法真实执行） | 是 |
| 占用磁盘 | 零 | 全量 |
| 用途 | **决策：是否创建** | **决策：是否删除** |
| 反向用途 | -- | **反向**：模拟删除 |

关键观察：HypoPG 和 INVISIBLE 其实解决的是**相反的问题**——前者是"添加前验证"，后者是"删除前验证"。

### 模拟删除索引的 PostgreSQL 方案

```sql
-- 方案 1：使用 enable_indexscan / enable_bitmapscan 参数
-- 会话级禁用所有索引扫描（粒度太粗）
SET enable_indexscan = OFF;
SET enable_bitmapscan = OFF;

-- 方案 2：使用 pg_hint_plan 禁用特定索引
-- 需要安装 pg_hint_plan 扩展
/*+ NoIndexScan(orders idx_orders_customer) */
SELECT * FROM orders WHERE customer_id = 123;

-- 方案 3：利用 SET SESSION 修改 planner 开关
-- 仅影响当前会话
SET pg_hint_plan.enable_hint = on;

-- 方案 4：物理 DROP 然后准备快速重建脚本（高风险）
-- 不推荐，因为 DROP 后重建大索引可能需数小时
```

### 社区提案：原生支持的讨论

PostgreSQL 社区多次讨论原生支持 INVISIBLE 索引：
- 2019: 初步提案，争议"是否违背 PG 简约设计哲学"
- 2021: 再次提案，关注与 pg_hint_plan 的整合
- 2023: 提案暂停，核心开发者倾向"通过扩展解决"

截至 2026 年 4 月，仍无路线图承诺。

## SQL Server：DISABLE 是物理删除

SQL Server 的 `ALTER INDEX ... DISABLE` 经常被误认为是"不可见索引"的等价物，但**本质完全不同**。

### DISABLE 的真实行为

```sql
-- 禁用索引
ALTER INDEX idx_orders_customer ON orders DISABLE;

-- 此时发生了什么？
-- 1. 索引的 B-tree 结构被物理删除（节省空间）
-- 2. 仅保留 sys.indexes 中的元数据定义
-- 3. 所有 DML 操作都不维护此索引
-- 4. 优化器完全忽略此索引
```

### 危险场景：聚簇索引的 DISABLE

```sql
-- 聚簇索引 = 表的物理存储结构
CREATE CLUSTERED INDEX PK_Orders ON orders(order_id);

-- 如果禁用聚簇索引
ALTER INDEX PK_Orders ON orders DISABLE;

-- 后果：
-- 1. 整个表变得不可查询（SELECT 直接报错）
-- 2. 所有 DML 都会失败
-- 3. 依赖此表的 FK 约束、视图、存储过程全部失效
-- 4. 必须 REBUILD 才能恢复，耗时可能极长
```

### 恢复方式

```sql
-- 恢复：必须 REBUILD（重新构建整个索引）
ALTER INDEX idx_orders_customer ON orders REBUILD;

-- 对大表，重建可能耗时数小时
-- 对比：Oracle INVISIBLE → VISIBLE 是瞬时元数据变更
```

### SQL Server 的替代方案

```sql
-- 方案 1：使用 optimizer hint 禁止特定索引
SELECT *
FROM orders WITH (INDEX(0))    -- INDEX(0) 禁用索引扫描
WHERE customer_id = 123;

SELECT *
FROM orders WITH (FORCESCAN)   -- 强制全表扫描
WHERE customer_id = 123;

-- 方案 2：使用 Query Store 和 Plan Guide
-- 可以在不改 SQL 的情况下干预优化器
-- 但无法"对整个索引隐藏"

-- 方案 3：使用 RESUMABLE 索引（SQL Server 2017+）
-- 创建时可暂停/恢复，但不是可见性控制
ALTER INDEX idx_x ON t REBUILD WITH (RESUMABLE = ON);
ALTER INDEX idx_x ON t PAUSE;
ALTER INDEX idx_x ON t RESUME;
```

### SQL Server 与 Oracle 的对比总结

| 维度 | SQL Server DISABLE | Oracle UNUSABLE | Oracle INVISIBLE |
|------|-------------------|-----------------|-----------------|
| 物理结构 | **被删除** | 仅头块 | 完整保留 |
| 恢复成本 | REBUILD（大索引数小时） | REBUILD | 瞬时元数据变更 |
| 典型用途 | 节省空间、完全禁用 | ETL 前临时禁用 | 模拟删除、实验 |
| 聚簇索引影响 | 表不可用 | N/A（Oracle 无聚簇索引概念同） | 影响有限 |

## DB2 LUW：INACTIVE 状态

DB2 LUW (Linux/Unix/Windows) 从 11.5 开始支持 INACTIVE 索引状态。

```sql
-- 设为 INACTIVE
ALTER INDEX idx_salary INACTIVE;

-- 查询状态
SELECT INDNAME, INDSCHEMA, INDEX_STATUS
FROM SYSCAT.INDEXES
WHERE TABNAME = 'EMPLOYEES';

-- 状态值：
-- 'N' = Normal (active, visible)
-- 'I' = Inactive (维护但不可见)
-- 'R' = Recomputation required
```

### DB2 INACTIVE 的特点

- DML 继续维护（与 Oracle INVISIBLE 一致）
- 优化器完全忽略（不像 Oracle/MySQL 可通过开关启用）
- 没有 Hint 可以强制使用（与 MariaDB IGNORED 类似）
- 统计信息会冻结，不自动更新
- 恢复方式：`ALTER INDEX ... ACTIVE`

```sql
-- 恢复激活
ALTER INDEX idx_salary ACTIVE;
```

### DB2 for z/OS 的差异

DB2 for z/OS 有不同的机制：
- 使用 `ALTER INDEX ... NOT PADDED` 和其他模式
- `REBUILD INDEX` 工具可处理 RBDP (Rebuild Pending) 状态
- 更复杂的分区索引管理

## TiDB：分布式场景下的 INVISIBLE

TiDB 从 8.0 (2024) 开始支持 INVISIBLE 索引，语法与 MySQL 兼容。

```sql
-- TiDB 8.0+
CREATE INDEX idx_user_name ON users(name) INVISIBLE;

ALTER TABLE users ALTER INDEX idx_user_name VISIBLE;

-- 查询状态（TiDB 专有视图）
SELECT TABLE_NAME, INDEX_NAME, IS_VISIBLE
FROM INFORMATION_SCHEMA.TIDB_INDEXES
WHERE TABLE_SCHEMA = 'test';
```

### TiDB 的分布式特性对 INVISIBLE 的影响

```sql
-- TiDB 索引是分布式存储在 TiKV 上的
-- INVISIBLE 状态通过 TiDB server 的 metadata 管理

-- 特殊考虑：
-- 1. 多 TiDB server 的 schema 同步
--    INVISIBLE 变更需要 schema version 广播
--    约 2 * lease 时间（默认 45s * 2 = 90s）后所有节点生效

-- 2. 与 TiFlash 的交互
--    TiFlash 副本不受 INVISIBLE 影响（TiFlash 不使用二级索引）
--    如果查询走 TiFlash，INVISIBLE 可能无效

-- 3. 大表索引的管理
--    DROP INDEX 可能触发大量 TiKV 数据清理
--    INVISIBLE 后观察再 DROP 更安全
```

### TiDB 的 Hint 支持

```sql
-- TiDB 支持通过 Hint 强制使用 INVISIBLE 索引
SELECT /*+ USE_INDEX(users, idx_user_name) */ *
FROM users WHERE name = 'Alice';

-- 全局变量控制
SET @@tidb_opt_use_invisible_indexes = 1;
```

## OceanBase：MySQL 模式下的支持

OceanBase 从 4.0 开始在 MySQL 模式下支持 INVISIBLE 索引，语法与 MySQL 8.0 完全兼容。

```sql
-- OceanBase 4.0+ MySQL 模式
CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,
    customer_id BIGINT,
    order_date DATE,
    INDEX idx_customer (customer_id) INVISIBLE
);

ALTER TABLE orders ALTER INDEX idx_customer VISIBLE;

-- Oracle 模式（4.x）
-- OceanBase Oracle 模式也逐步支持 INVISIBLE，语法兼容 Oracle
```

### 分布式优化器的考量

```sql
-- OceanBase 是分布式数据库，INVISIBLE 的语义需要协调：
-- 1. Primary/Standby 的 DDL 同步
-- 2. 分区索引的全局一致性
-- 3. 多租户隔离（每租户独立的优化器开关）

-- 开关控制
SET @@session.optimizer_switch = 'use_invisible_indexes=on';
```

## CockroachDB：NOT VISIBLE

CockroachDB 从 22.2 (2022) 开始支持，使用与其他引擎不同的 `NOT VISIBLE` 关键字。

```sql
-- CockroachDB 22.2+
CREATE INDEX idx_user_email ON users(email) NOT VISIBLE;

ALTER INDEX idx_user_email VISIBLE;
ALTER INDEX idx_user_email NOT VISIBLE;

-- 也支持部分可见（VISIBILITY 百分比，实验性）
CREATE INDEX idx_experimental ON t(x) VISIBILITY 0.5;
-- 0.5 = 50% 的查询会看到这个索引（A/B 测试）
-- VISIBILITY 1.0 = 完全可见（默认）
-- VISIBILITY 0.0 = NOT VISIBLE 等价
```

### 独特的 VISIBILITY 百分比

CockroachDB 是目前唯一支持**渐进式可见性**的引擎：

```sql
-- 场景：上线新索引，灰度验证
-- Day 1: 10% 流量使用新索引
CREATE INDEX idx_new ON orders(new_column) VISIBILITY 0.1;

-- Day 2-3: 逐步扩大
ALTER INDEX idx_new VISIBILITY 0.5;

-- Day 4: 全量
ALTER INDEX idx_new VISIBLE;

-- 如果发现问题，快速回退
ALTER INDEX idx_new NOT VISIBLE;
```

### 会话级开关

```sql
-- 启用所有 NOT VISIBLE 索引（会话级）
SET optimizer_use_not_visible_indexes = true;

-- 查询状态
SELECT index_name, is_visible, visibility
FROM crdb_internal.index_columns
WHERE descriptor_name = 'orders';
```

## Snowflake / BigQuery / Redshift：没有索引概念

现代云数据仓库通常没有传统的 B-tree 索引，因此"不可见索引"的概念也不适用。

### Snowflake

```sql
-- Snowflake 没有 CREATE INDEX 语法
-- 依赖：
-- 1. Micro-partition 自动裁剪（基于 min/max metadata）
-- 2. Clustering keys（类似 sort key）
-- 3. Search Optimization Service（类似倒排索引，付费特性）
-- 4. Materialized views

-- "模拟隐藏索引"的最接近方案：
-- 暂停 Search Optimization
ALTER TABLE orders SUSPEND SEARCH OPTIMIZATION;
-- 恢复
ALTER TABLE orders RESUME SEARCH OPTIMIZATION;
```

### BigQuery

```sql
-- BigQuery 的 Search Index 是有限的索引概念（2022+）
CREATE SEARCH INDEX idx_logs ON logs(message);

-- Search Index 可以 DROP 但没有"隐藏"概念
DROP SEARCH INDEX idx_logs ON logs;

-- 集群和分区不涉及可见性
CREATE TABLE orders
PARTITION BY order_date
CLUSTER BY customer_id
AS SELECT ...;
```

### Redshift

```sql
-- Redshift 没有索引（依赖 sort key 和 dist key）
CREATE TABLE orders (
    order_id BIGINT,
    customer_id BIGINT,
    order_date DATE
)
DISTKEY(customer_id)
SORTKEY(order_date);

-- "不可见"不适用：sort key 是物理布局，不能"隐藏"
```

## 其他引擎的简要总结

### Greenplum / TimescaleDB
继承自 PostgreSQL，不原生支持 INVISIBLE。可使用 HypoPG 或 pg_hint_plan 扩展。

### Vertica
列存分析引擎，没有传统 B-tree 索引。依赖投影（projections）和编码。无可见性概念。

### ClickHouse
MergeTree 引擎的 primary key 是强制物理顺序，不可隐藏。Skipping Index（跳数索引）是可选的辅助结构，可以 DROP 但没有"隐藏"状态。

```sql
-- ClickHouse 可以删除 skipping index
ALTER TABLE events DROP INDEX idx_user_id;
-- 没有 INVISIBLE 等价语法
```

### Trino / Presto / Athena
存算分离架构，无索引概念。

### Spark SQL / Databricks / Hive
没有传统二级索引。Databricks 的 bloom filter 索引和 Delta Lake 的 z-order 属于数据布局优化，无可见性控制。

### SAP HANA
虽有索引，但不支持 INVISIBLE。依赖实时分析性能，传统索引使用较少。

### Firebird
有 `ALTER INDEX ... INACTIVE` 语法，但**不维护 DML**（类似 SQL Server DISABLE）。

```sql
-- Firebird: INACTIVE 是物理禁用
ALTER INDEX idx_employee_name INACTIVE;
-- 恢复
ALTER INDEX idx_employee_name ACTIVE;
```

### H2 / HSQLDB / Derby
这些嵌入式 Java 数据库都不支持不可见索引。典型使用场景（开发/测试）也很少需要此特性。

## HypoPG 深度：PostgreSQL 的假索引生态

HypoPG 是 PostgreSQL 生态中最具创新的扩展之一，提供了一套"纯元数据索引"的完整能力。

### 工作原理

```
HypoPG 通过 PostgreSQL 的 Planner Hook 机制：
1. 在 CREATE 假索引时，仅写入 HypoPG 的内部表
2. Planner Hook 截获优化器的"索引枚举"阶段
3. 将假索引作为候选加入（但 cost 估算需要估计）
4. 如果假索引被选中，EXPLAIN 显示它（标记 <hypothetical>）
5. 实际执行时，Planner 会回退到真实路径
```

### 完整工作流

```sql
-- 步骤 1: 安装扩展（首次）
CREATE EXTENSION IF NOT EXISTS hypopg;

-- 步骤 2: 分析慢查询
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE customer_id = 12345 AND status = 'pending';
-- 发现：Seq Scan + filter，慢

-- 步骤 3: 创建假索引测试
SELECT hypopg_create_index('CREATE INDEX ON orders (customer_id, status)');
-- 返回：(101, <13101>btree_orders_customer_id_status)

-- 步骤 4: 再次 EXPLAIN（不加 ANALYZE，因为索引实际不存在）
EXPLAIN SELECT * FROM orders
WHERE customer_id = 12345 AND status = 'pending';
-- 结果：Index Scan using <13101>btree_orders_customer_id_status

-- 步骤 5: 如果 cost 下降明显，真实创建索引
CREATE INDEX idx_orders_customer_status ON orders (customer_id, status);

-- 步骤 6: 清理假索引
SELECT hypopg_reset();
```

### HypoPG 支持的索引类型

```sql
-- B-tree（默认）
SELECT hypopg_create_index('CREATE INDEX ON t (col)');

-- Hash
SELECT hypopg_create_index('CREATE INDEX ON t USING hash (col)');

-- BRIN
SELECT hypopg_create_index('CREATE INDEX ON t USING brin (col)');

-- GIN（有限支持）
SELECT hypopg_create_index('CREATE INDEX ON t USING gin (col)');

-- 部分索引
SELECT hypopg_create_index('CREATE INDEX ON t (col) WHERE status = ''active''');

-- 多列索引
SELECT hypopg_create_index('CREATE INDEX ON t (col1, col2, col3)');
```

### HypoPG 的限制

1. **不能真实执行 EXPLAIN ANALYZE**：因为索引不存在
2. **BitmapScan 支持有限**：某些复杂场景下估算不准
3. **并发查询的隔离问题**：假索引是会话级的
4. **不支持表达式索引的所有特性**：某些函数索引无法模拟
5. **不支持 UNIQUE 约束**：无法模拟唯一索引的行为

### 相关扩展：pg_qualstats + hypopg

```sql
-- pg_qualstats 统计查询中的谓词
CREATE EXTENSION pg_qualstats;

-- 结合 HypoPG，自动推荐索引
-- 典型工具：PoWA (PostgreSQL Workload Analyzer)
```

## 关键发现与设计模式总结

### 1. 不可见索引的本质是风险对冲

删除索引是**不可逆**的重操作：
- 大索引 DROP 后重建可能耗时数小时
- 生产环境的错误 DROP 可能导致查询退化几十倍
- 事后回滚窗口短

INVISIBLE 提供了**低成本的回滚保险**：
- 状态切换是秒级元数据变更
- DML 依然维护，数据不损失
- 观察期内可随时恢复

### 2. 三种"禁用"状态的本质区别

```
INVISIBLE (Oracle/MySQL/TiDB/OceanBase/CockroachDB NOT VISIBLE):
  ├── 物理完整
  ├── DML 维护
  ├── 优化器忽略（可 Hint 强制）
  └── 用途: 模拟删除、实验验证

IGNORED (MariaDB):
  ├── 物理完整
  ├── DML 维护
  ├── 优化器完全忽略（Hint 无效）
  └── 用途: 纯粹模拟删除

UNUSABLE (Oracle 专有):
  ├── 仅头块保留
  ├── DML 跳过维护
  ├── 优化器忽略
  └── 用途: 批量 ETL 前临时禁用

DISABLED (SQL Server/Firebird/Synapse):
  ├── B-tree 物理删除
  ├── DML 跳过
  ├── 优化器忽略
  └── 用途: 节省空间 / 聚簇索引会导致表不可用

INACTIVE (DB2):
  ├── 物理完整
  ├── DML 维护
  ├── 优化器完全忽略（Hint 无效）
  └── 用途: 类似 MariaDB IGNORED

Hypothetical (PostgreSQL + HypoPG):
  ├── 不存在（仅元数据）
  ├── 无 DML 维护可能
  ├── 优化器在假装存在的情况下估算
  └── 用途: 验证"是否应该创建"
```

### 3. Hint 语义的哲学差异

引擎对"INVISIBLE 是否应该能被 Hint 强制使用"有两派：

**自由派**（Oracle、MySQL、TiDB、OceanBase、CockroachDB）：
- 允许 Hint 强制使用
- 哲学："INVISIBLE 只是默认不选，用户想用可以用"
- 风险：误用 Hint 可能让"假删除"的索引意外进入生产计划

**严格派**（MariaDB IGNORED、DB2 INACTIVE）：
- 完全禁止任何启用
- 哲学："既然叫 IGNORED/INACTIVE，就彻底忽略"
- 优势：更纯粹的"模拟删除"语义

### 4. 分析型引擎为何普遍不支持？

现代分析引擎（Snowflake、BigQuery、Redshift、ClickHouse、Databricks 等）普遍不支持 INVISIBLE，原因：

1. **没有传统二级索引**：依赖列存布局、分区、聚类键、min/max metadata
2. **"隐藏"概念不适用**：分区和布局是物理属性，不是优化器选项
3. **优化器选择空间小**：通常只有几种扫描策略，不需要"隐藏某个索引"
4. **工作负载假设**：分析查询通常扫描大量数据，单点索引价值有限

### 5. PostgreSQL 的生态补偿

PostgreSQL 虽无原生支持，但生态提供了**更强大的工具**：
- HypoPG：反向思考，"验证添加"而非"验证删除"
- pg_hint_plan：细粒度的优化器控制
- pg_qualstats：基于工作负载的自动推荐

这反映了 PG 社区的哲学："用扩展保持核心的简约"。

### 6. 何时使用哪种状态？

```
需求: 安全删除一个旧索引
  ├── Oracle/MySQL/TiDB/OceanBase → INVISIBLE
  ├── MariaDB → IGNORED (更纯粹)
  ├── DB2 → INACTIVE
  ├── CockroachDB → NOT VISIBLE (或 VISIBILITY 0.0)
  ├── SQL Server → 不要用 DISABLE（物理删除），手动 DROP 前充分测试
  └── PostgreSQL → 无原生支持，考虑 pg_stat_user_indexes 监控 + 直接 DROP

需求: 批量 ETL 前禁用索引加速
  ├── Oracle → UNUSABLE（真正跳过 DML 维护）
  ├── MySQL → 无等价方案，DROP + CREATE
  └── PostgreSQL → DROP INDEX CONCURRENTLY, 加载后 CREATE INDEX CONCURRENTLY

需求: 实验性索引，不影响生产计划
  ├── Oracle → CREATE ... INVISIBLE
  ├── MySQL → CREATE ... INVISIBLE
  ├── PostgreSQL → HypoPG 假索引
  └── CockroachDB → CREATE ... VISIBILITY 0.1 (灰度)

需求: 验证"如果有这个索引会怎样"
  └── PostgreSQL + HypoPG（唯一原生支持此场景的主流引擎）

需求: A/B 测试索引变更
  └── CockroachDB VISIBILITY 百分比
```

### 7. 运维的最佳实践

```
删除索引的标准流程:

Step 1: 监控 (7 天以上)
  - 查看索引使用统计
  - PostgreSQL: pg_stat_user_indexes.idx_scan
  - MySQL: sys.schema_unused_indexes
  - Oracle: v$object_usage

Step 2: 设为不可见 (如引擎支持)
  - Oracle/MySQL/TiDB/OceanBase: INVISIBLE
  - MariaDB: IGNORED
  - DB2: INACTIVE

Step 3: 观察 (14-30 天)
  - 慢查询日志变化
  - 应用 P99 延迟
  - 业务关键 SQL 的 EXPLAIN 计划

Step 4: 决策
  - 无异常 → DROP INDEX
  - 有异常 → 恢复 VISIBLE + 调查原因

Step 5: 最终清理
  - DROP INDEX
  - 更新文档与架构图
```

### 8. 对引擎开发者的实现建议

**元数据设计**：
```
索引状态枚举（推荐支持）:
- VISIBLE / ACTIVE: 正常使用
- INVISIBLE: 维护但优化器忽略
- UNUSABLE: 不维护（Oracle 风格）
- DISABLED: 物理删除（SQL Server 风格，不推荐新设计）
- HYPOTHETICAL: 假索引（HypoPG 风格）
- DROPPING: 删除中（软删除过渡态）
```

**优化器钩子**：
```rust
fn is_index_usable(
    idx: &Index,
    session_config: &SessionConfig,
    hints: &[Hint],
) -> bool {
    match idx.visibility {
        Visibility::Visible => true,
        Visibility::Invisible => {
            // 允许 session 开关或 hint 启用
            session_config.use_invisible_indexes
                || hints.iter().any(|h| h.forces_index(idx.id))
        }
        Visibility::Ignored => false,  // 严格语义
        Visibility::Unusable => false,
    }
}
```

**统计信息维护**：
- INVISIBLE 索引应继续自动收集统计（便于切换后立即可用）
- UNUSABLE/DISABLED 索引的统计可以冻结（节省开销）

**DDL 幂等性**：
- `ALTER INDEX ... INVISIBLE` 应是幂等操作
- 连续两次 INVISIBLE 不应报错
- 考虑 `ALTER INDEX ... IF EXISTS` 的处理

**分布式协调**：
- 元数据变更需要通知所有计算节点
- 考虑 schema version 租约机制
- 变更生效时间需要明确（TiDB 的 2 * lease 是参考实现）

### 9. 与其他 DDL 的交互

```sql
-- INVISIBLE 索引参与的特殊场景:

-- 1. REINDEX / REBUILD
ALTER INDEX idx_x REBUILD;
-- Oracle: 会保持 VISIBILITY 状态不变
-- MySQL: 类似 OPTIMIZE TABLE 时保持 INVISIBLE

-- 2. 表分区/重分区
-- INVISIBLE 索引跟随表结构变化

-- 3. 表空间迁移
-- Oracle: ALTER INDEX ... MOVE TABLESPACE 保持 VISIBILITY

-- 4. 外键约束
-- MySQL: 外键依赖的索引可以 INVISIBLE，但约束检查可能退化
-- Oracle: 外键支持索引可以 INVISIBLE，但如果没有可见替代会影响 DML

-- 5. 唯一约束
-- 支持唯一约束的索引设为 INVISIBLE 后，唯一性依然强制执行
```

### 10. 性能影响的量化

**INVISIBLE 索引的维护开销**（与可见索引相同）：
- INSERT: 每插入一行，更新所有索引（包括 INVISIBLE）
- UPDATE: 影响索引键时更新
- DELETE: 索引也被删除对应项
- 典型开销: 每个索引增加 5-15% 的 DML 时间

**UNUSABLE 索引的收益**（Oracle 专有）：
- 大批量 INSERT: 节省 60-90% 的维护时间（取决于索引数量）
- ETL 场景: 常比 CREATE INDEX 后重建快数倍

**HypoPG 假索引的开销**：
- CREATE: 毫秒级
- 查询规划: 增加 5-20% planner 时间
- EXPLAIN: 正常输出，标记 <hypothetical>

## 总结对比矩阵

### 主流引擎能力对比

| 能力 | Oracle | MySQL 8.0 | MariaDB 10.6 | PostgreSQL | SQL Server | DB2 | TiDB | CockroachDB |
|------|--------|-----------|-------------|-----------|------------|-----|------|------------|
| 不可见但维护 | INVISIBLE | INVISIBLE | IGNORED | HypoPG(无DML) | -- | INACTIVE | INVISIBLE | NOT VISIBLE |
| 不维护状态 | UNUSABLE | -- | -- | -- | DISABLE(物理删除) | -- | -- | -- |
| Hint 强制启用 | 是 | 是 | 否 | HypoPG 自动 | -- | 否 | 是 | 是 |
| 全局开关 | 是 | 是 | 否 | 扩展 | -- | 否 | 是 | 是 |
| 恢复成本 | 瞬时 | 瞬时 | 瞬时 | N/A | REBUILD | 瞬时 | 瞬时 | 瞬时 |
| 分区级粒度 | 是 | 否 | 否 | N/A | 是 | 是 | 是 | 否 |
| 渐进可见性 | 否 | 否 | 否 | 否 | 否 | 否 | 否 | **是**（VISIBILITY 0.0~1.0） |
| 首次引入 | 2007 (11g) | 2018 (8.0) | 2021 (10.6) | 无原生 | 无原生 | 11.5 | 2024 (8.0) | 2022 (22.2) |

### 场景推荐

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| 安全删除索引 | Oracle/MySQL INVISIBLE | 最成熟的实现 |
| 最纯粹的模拟删除 | MariaDB IGNORED | Hint 也无法意外启用 |
| 批量 ETL 加速 | Oracle UNUSABLE | 唯一跳过 DML 维护的标准方案 |
| 索引添加前验证 | PostgreSQL + HypoPG | 独一无二的"假索引"能力 |
| A/B 测试 / 灰度 | CockroachDB VISIBILITY | 唯一支持百分比可见性 |
| 分布式数据库 | TiDB / OceanBase INVISIBLE | 分布式场景下的标准实现 |
| SQL Server 场景 | 手动 DROP + 充分测试 | DISABLE 是物理删除，有风险 |
| 云数仓 (Snowflake/BQ) | 不适用 | 无传统索引概念 |

## 参考资料

- Oracle: [Indexes and Index-Organized Tables - INVISIBLE/UNUSABLE](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/indexes-and-index-organized-tables.html)
- MySQL: [Invisible Indexes](https://dev.mysql.com/doc/refman/8.0/en/invisible-indexes.html)
- MariaDB: [Ignored Indexes](https://mariadb.com/kb/en/ignored-indexes/)
- PostgreSQL HypoPG: [HypoPG Extension](https://hypopg.readthedocs.io/)
- PostgreSQL pg_hint_plan: [pg_hint_plan Documentation](https://github.com/ossc-db/pg_hint_plan)
- SQL Server: [ALTER INDEX ... DISABLE](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-index-transact-sql)
- DB2 LUW: [ALTER INDEX ... INACTIVE](https://www.ibm.com/docs/en/db2)
- TiDB: [Invisible Indexes](https://docs.pingcap.com/tidb/stable/sql-statement-alter-index)
- OceanBase: [索引管理](https://en.oceanbase.com/docs/)
- CockroachDB: [Not Visible Indexes](https://www.cockroachlabs.com/docs/stable/create-index#not-visible)
- Firebird: [ALTER INDEX Statement](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/firebird-40-language-reference.html)
- 相关论文: Selinger et al., "Access Path Selection in a Relational Database Management System" (1979), SIGMOD
- 索引调优经典: Markus Winand, "Use the Index, Luke!" (2013)
