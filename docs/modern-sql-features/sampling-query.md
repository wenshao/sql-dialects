# 采样查询 (TABLESAMPLE and Sampling)

从百亿行表中只读 1% 的数据就能得到 98% 精度的答案——采样是大数据时代最被低估的 SQL 能力，也是引擎开发者必须理解的核心优化手段。

## SQL:2003 标准定义

SQL:2003 标准（ISO/IEC 9075-2, Section 7.6）正式引入 `TABLESAMPLE` 子句，定义了数据采样的标准语法：

```sql
<table_reference> ::=
    <table_name> TABLESAMPLE <sample_method> ( <sample_percentage> )
        [ REPEATABLE ( <seed> ) ]

<sample_method> ::= BERNOULLI | SYSTEM
<sample_percentage> ::= <numeric_value_expression>  -- 0 到 100
```

标准的关键语义：

1. **位于 FROM 子句中**：逻辑上在 WHERE、GROUP BY 之前执行
2. **百分比参数**：0 到 100 之间的数值，表示期望采样比例
3. **结果是近似的**：10% 采样不保证恰好返回总行数的 10%
4. **BERNOULLI**：行级独立随机采样，每行以给定概率被选中
5. **SYSTEM**：实现相关的采样（通常是块级），允许引擎优化 I/O
6. **REPEATABLE**：可选子句，给定相同种子值，在数据不变时返回相同结果

## 支持矩阵（综合）

### TABLESAMPLE / SAMPLE 基础支持

| 引擎 | 关键字 | BERNOULLI | SYSTEM | BLOCK | 行数采样 | REPEATABLE/SEED | 版本 |
|------|--------|-----------|--------|-------|---------|----------------|------|
| PostgreSQL | `TABLESAMPLE` | 是 | 是 | -- | 扩展 | 是 | 9.5+ |
| SQL Server | `TABLESAMPLE` | -- | 是 | -- | 是 (ROWS) | 是 | 2005+ |
| Oracle | `SAMPLE` | 行级 | 块级 | `SAMPLE BLOCK` | -- | `SEED` | 8i+ |
| MySQL | -- | -- | -- | -- | -- | -- | 不支持 |
| MariaDB | -- | -- | -- | -- | -- | -- | 不支持 |
| SQLite | -- | -- | -- | -- | -- | -- | 不支持 |
| DB2 | `TABLESAMPLE` | 是 | 是 | -- | -- | 是 | 9.1+ |
| Snowflake | `SAMPLE` / `TABLESAMPLE` | 是 | `BLOCK` | 是 | 是 (ROWS) | 是 | GA |
| BigQuery | `TABLESAMPLE` | -- | 是 | -- | -- | -- | GA |
| Redshift | `TABLESAMPLE` | 是 | 是 | -- | -- | -- | GA |
| DuckDB | `TABLESAMPLE` / `USING SAMPLE` | 是 | 是 | -- | 是 | 是 | 0.3+ |
| ClickHouse | `SAMPLE` | -- | -- | -- | 是 | 偏移 | 早期 |
| Trino | `TABLESAMPLE` | 是 | 是 | -- | -- | -- | 早期 |
| Presto | `TABLESAMPLE` | 是 | 是 | -- | -- | -- | 0.148+ |
| Spark SQL | `TABLESAMPLE` | 是 | -- | -- | 是 (ROWS) | `SEED` | 2.0+ |
| Hive | `TABLESAMPLE` | -- | -- | 桶 | 是 | -- | 0.11+ |
| Flink SQL | -- | -- | -- | -- | -- | -- | 不支持 |
| Databricks | `TABLESAMPLE` | 是 | -- | -- | 是 (ROWS) | `SEED` | GA |
| Teradata | `SAMPLE` | 行级 | -- | -- | 是 | -- | V2R5+ |
| Greenplum | `TABLESAMPLE` | 是 | 是 | -- | 扩展 | 是 | 6.0+ |
| CockroachDB | `TABLESAMPLE` | 是 | -- | -- | -- | -- | 20.1+ |
| TiDB | -- | -- | -- | -- | -- | -- | 不支持 |
| OceanBase | -- | -- | -- | -- | -- | -- | 不支持 |
| YugabyteDB | `TABLESAMPLE` | 是 | 是 | -- | -- | 是 | 2.6+ |
| SingleStore (MemSQL) | `TABLESAMPLE` | -- | 是 | -- | -- | -- | 7.5+ |
| Vertica | `TABLESAMPLE` | 是 | 是 | -- | -- | -- | 9.0+ |
| Impala | `TABLESAMPLE SYSTEM` | -- | 是 | -- | -- | 是 | 4.0+ (2023) |
| StarRocks | `TABLESAMPLE` | -- | -- | -- | 是 (ROWS) | -- | 2.5+ |
| Doris | `TABLESAMPLE` | -- | -- | -- | 是 (ROWS) | -- | 1.2+ |
| MonetDB | `SAMPLE` | 行级 | -- | -- | 是 | -- | Jun2020+ |
| Crate DB | -- | -- | -- | -- | -- | -- | 不支持 |
| TimescaleDB | `TABLESAMPLE` | 是 | 是 | -- | 扩展 | 是 | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | -- | -- | -- | 不支持 |
| SAP HANA | `TABLESAMPLE` | 是 | 是 | -- | -- | 是 | 2.0+ |
| Informix | -- | -- | -- | -- | -- | -- | 不支持 |
| Firebird | -- | -- | -- | -- | -- | -- | 不支持 |
| H2 | -- | -- | -- | -- | -- | -- | 不支持 |
| HSQLDB | -- | -- | -- | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | -- | -- | -- | 不支持 |
| Amazon Athena | `TABLESAMPLE` | 是 | 是 | -- | -- | -- | 继承 Trino |
| Azure Synapse | `TABLESAMPLE` | -- | 是 | -- | 是 (ROWS) | 是 | GA |
| Google Spanner | -- | -- | -- | -- | -- | -- | 不支持 |
| Materialize | -- | -- | -- | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | -- | -- | -- | 不支持 |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | -- | 不支持 |
| DatabendDB | `TABLESAMPLE` | 是 | -- | -- | 是 (ROWS) | -- | GA |
| Yellowbrick | `TABLESAMPLE` | 是 | 是 | -- | -- | 是 | GA |
| Firebolt | `TABLESAMPLE` | -- | 是 | -- | -- | -- | GA |

> 注: ClickHouse 的 SAMPLE 基于哈希采样键（sampling key），与 SQL 标准 BERNOULLI（逐行随机）是不同的采样模型，因此 BERNOULLI 列标记为 "--"。
>
> 统计：约 24 个引擎支持某种形式的采样语法，约 21 个引擎完全不支持或需要替代方案模拟。

### ORDER BY RANDOM() LIMIT N 替代方案

对于不支持 TABLESAMPLE 的引擎，最常见的替代方案：

| 引擎 | 替代语法 | 性能特点 |
|------|---------|---------|
| MySQL | `ORDER BY RAND() LIMIT N` | 全表扫描 + 排序，极慢 |
| MariaDB | `ORDER BY RAND() LIMIT N` | 同 MySQL |
| SQLite | `ORDER BY RANDOM() LIMIT N` | 全表扫描 + 排序 |
| TiDB | `ORDER BY RAND() LIMIT N` | 分布式排序，更慢 |
| OceanBase | `ORDER BY DBMS_RANDOM.VALUE LIMIT N` | 全表扫描 |
| Flink SQL | 不适用（流处理） | -- |
| CrateDB | `ORDER BY RANDOM() LIMIT N` | 全表扫描 |
| H2 | `ORDER BY RANDOM() LIMIT N` | 全表扫描 |

## BERNOULLI vs SYSTEM：两种采样方法的深入对比

### BERNOULLI（行级随机采样）

```sql
-- PostgreSQL / Trino / DuckDB / Snowflake / Redshift / DB2
SELECT * FROM orders TABLESAMPLE BERNOULLI(10);
```

实现原理：逐行扫描全表，每行以独立概率 p 决定是否保留。结果行数服从二项分布 B(N, p)。

特点：随机性极好（行级独立），但必须全表扫描（I/O 无法减少）。适合对随机性要求高的统计分析。

### SYSTEM（块级随机采样）

```sql
-- PostgreSQL / SQL Server / Vertica / SAP HANA
SELECT * FROM orders TABLESAMPLE SYSTEM(10);
```

实现原理：随机选择数据块（page/block），被选中的块中所有行都返回。

特点：I/O 大幅减少（只读选中的块），但随机性差（同块内行通常相邻插入，有聚集偏差），方差大。适合快速数据探索和粗略估计。

### 性能对比示例

1 亿行 200GB 表：BERNOULLI(1) 读全部 200GB 约 120 秒，随机性好；SYSTEM(1) 只读 ~2GB 约 1.5 秒，但样本可能聚集。速度差 ~80 倍。

## 各引擎语法详解

### PostgreSQL（最完整的标准实现）

```sql
-- BERNOULLI: 行级采样
SELECT * FROM large_table TABLESAMPLE BERNOULLI(5);

-- SYSTEM: 块级采样
SELECT * FROM large_table TABLESAMPLE SYSTEM(5);

-- REPEATABLE: 可重复采样
SELECT * FROM large_table TABLESAMPLE BERNOULLI(10) REPEATABLE(42);

-- 扩展采样方法（需安装扩展）
CREATE EXTENSION tsm_system_rows;
SELECT * FROM large_table TABLESAMPLE SYSTEM_ROWS(1000);  -- 精确返回 1000 行

CREATE EXTENSION tsm_system_time;
SELECT * FROM large_table TABLESAMPLE SYSTEM_TIME(1000);  -- 在 1000ms 内返回尽可能多行

-- 采样 + 聚合
SELECT COUNT(*) * 100 AS estimated_total,
       AVG(amount) AS avg_amount
FROM orders TABLESAMPLE BERNOULLI(1);

-- 注意：TABLESAMPLE 只能用于基表，不能用于子查询
-- 先过滤再采样需要使用临时表或 CTE 具体化后再采样
-- 下面的写法在 PostgreSQL 中会报错：
-- SELECT * FROM (SELECT ...) sub TABLESAMPLE BERNOULLI(10);  -- 错误
```

### SQL Server（仅 SYSTEM，支持 ROWS）

```sql
-- 块级采样（百分比）
SELECT * FROM Sales.SalesOrderDetail TABLESAMPLE (10 PERCENT);

-- 指定近似行数
SELECT * FROM Sales.SalesOrderDetail TABLESAMPLE (1000 ROWS);

-- REPEATABLE
SELECT * FROM Sales.SalesOrderDetail
    TABLESAMPLE (10 PERCENT) REPEATABLE (42);

-- 注意：SQL Server 不支持 BERNOULLI
-- ROWS 模式内部也是块级的，只是根据行数反推百分比
-- 实际返回行数可能与指定值有较大偏差
```

### Oracle（非标准 SAMPLE 语法）

```sql
-- 行级采样（默认）
SELECT * FROM orders SAMPLE (10);               -- 约 10% 的行

-- 块级采样
SELECT * FROM orders SAMPLE BLOCK (10);          -- 约 10% 的块

-- 指定种子
SELECT * FROM orders SAMPLE (10) SEED (42);

-- 与分析函数结合
SELECT department_id,
       AVG(salary) OVER (PARTITION BY department_id) AS dept_avg
FROM employees SAMPLE (20);

-- 注意：Oracle 的 SAMPLE 不遵循 SQL 标准的 TABLESAMPLE 语法
-- 百分比范围是 0.000001 到 99.999999（不包括 0 和 100）
```

### Snowflake（双关键字，功能丰富）

```sql
-- SAMPLE 和 TABLESAMPLE 完全等价
SELECT * FROM large_table SAMPLE (10);
SELECT * FROM large_table TABLESAMPLE (10);

-- 指定方法
SELECT * FROM large_table SAMPLE BERNOULLI (10);    -- 行级
SELECT * FROM large_table SAMPLE ROW (10);           -- ROW = BERNOULLI
SELECT * FROM large_table SAMPLE BLOCK (10);         -- 块级
SELECT * FROM large_table SAMPLE SYSTEM (10);        -- SYSTEM = BLOCK

-- 固定行数采样
SELECT * FROM large_table SAMPLE (1000 ROWS);

-- SEED / REPEATABLE（两者等价）
SELECT * FROM large_table SAMPLE (10) SEED (42);
SELECT * FROM large_table SAMPLE (10) REPEATABLE (42);

-- 在子查询中采样
SELECT * FROM (
    SELECT * FROM orders WHERE region = 'APAC'
) SAMPLE (5);
```

### ClickHouse（基于采样键的哈希采样）

```sql
-- 前提：建表时声明采样键
CREATE TABLE events (
    event_id UInt64,
    user_id UInt64,
    event_time DateTime
) ENGINE = MergeTree()
ORDER BY (user_id, event_time)
SAMPLE BY user_id;

-- 按比例采样（基于采样键的哈希值范围）
SELECT count() FROM events SAMPLE 0.1;              -- 约 10%

-- 按行数采样
SELECT count() FROM events SAMPLE 10000;             -- 约 10000 行

-- 带偏移的采样（用于不同分片取不同样本）
SELECT count() FROM events SAMPLE 1/10 OFFSET 3/10;

-- 重要限制：
-- 1. 没有 SAMPLE BY 子句的表不能使用 SAMPLE
-- 2. 基于哈希值范围，不是真正的随机
-- 3. 同一 user_id 的所有行要么全选中要么全不选中
```

### Hive（最丰富的采样方式）

```sql
-- 分桶采样：从 10 个桶中取第 1 个桶
SELECT * FROM large_table TABLESAMPLE(BUCKET 1 OUT OF 10 ON user_id);

-- 按百分比采样
SELECT * FROM large_table TABLESAMPLE(10 PERCENT);

-- 按行数采样
SELECT * FROM large_table TABLESAMPLE(1000 ROWS);

-- 按数据量采样
SELECT * FROM large_table TABLESAMPLE(100M);        -- 约 100MB 的数据

-- 分桶采样在 JOIN 中的应用
SELECT a.*, b.*
FROM table_a TABLESAMPLE(BUCKET 1 OUT OF 10 ON id) a
JOIN table_b TABLESAMPLE(BUCKET 1 OUT OF 10 ON id) b
ON a.id = b.id;
-- 两表用相同的分桶策略，确保 JOIN 键对齐
```

### Spark SQL / Databricks

```sql
-- 百分比采样（行级）
SELECT * FROM large_table TABLESAMPLE (10 PERCENT);

-- 行数采样
SELECT * FROM large_table TABLESAMPLE (1000 ROWS);

-- 分桶采样
SELECT * FROM large_table TABLESAMPLE (BUCKET 3 OUT OF 10 ON id);

-- 使用 SEED 保证可重复
SELECT * FROM large_table TABLESAMPLE (10 PERCENT) SEED (42);

-- DataFrame API（更灵活）
-- df.sample(withReplacement=False, fraction=0.1, seed=42)
```

### DuckDB（最灵活，支持 RESERVOIR）

```sql
-- 标准语法
SELECT * FROM large_table TABLESAMPLE BERNOULLI(10);
SELECT * FROM large_table TABLESAMPLE SYSTEM(10);

-- USING SAMPLE 语法（DuckDB 扩展）
SELECT * FROM large_table USING SAMPLE 10%;
SELECT * FROM large_table USING SAMPLE 1000;
SELECT * FROM large_table USING SAMPLE 10% (BERNOULLI);
SELECT * FROM large_table USING SAMPLE 10% (SYSTEM);

-- RESERVOIR 采样：精确返回 N 行
SELECT * FROM large_table USING SAMPLE 1000 (RESERVOIR);

-- REPEATABLE（种子作为方法的第二个参数）
SELECT * FROM large_table USING SAMPLE 10% (BERNOULLI, 42);
SELECT * FROM large_table USING SAMPLE 500 (RESERVOIR, 42);

-- USING SAMPLE 可以出现在 SELECT 末尾
SELECT col_a, col_b FROM large_table WHERE x > 10 USING SAMPLE 5%;
```

### Trino / Presto

```sql
-- 标准 TABLESAMPLE 语法
SELECT * FROM orders TABLESAMPLE BERNOULLI(10);
SELECT * FROM orders TABLESAMPLE SYSTEM(10);

-- 注意：Trino 的 SYSTEM 采样是连接器相关的
-- Hive 连接器：按 split 采样
-- JDBC 连接器：可能不支持

-- Trino 不支持 REPEATABLE 子句
-- Trino 不支持按行数采样
```

### Teradata（SAMPLE 语法，支持分层采样）

```sql
-- 固定行数采样
SELECT * FROM large_table SAMPLE 1000;

-- 百分比采样
SELECT * FROM large_table SAMPLE 0.10;              -- 10%

-- 多样本同时提取（Teradata 独有）
SELECT sampleid, * FROM large_table SAMPLE 1000, 1000, 1000;
-- 返回 3 个独立的 1000 行样本，用 sampleid (1,2,3) 区分

-- 分层采样（按分组）
SELECT * FROM large_table
SAMPLE WITH REPLACEMENT
    WHEN department = 'Sales' THEN 100
    WHEN department = 'Engineering' THEN 200
    ELSE 50
END;

-- 按比例分层采样
SELECT * FROM large_table
SAMPLE
    WHEN region = 'US' THEN 0.05
    WHEN region = 'EU' THEN 0.10
    ELSE 0.20
END;
```

### 其他引擎

```sql
-- BigQuery（支持 TABLESAMPLE SYSTEM）
SELECT * FROM dataset.large_table TABLESAMPLE SYSTEM (10 PERCENT);  -- 约 10%

-- DB2（标准语法，支持 REPEATABLE）
SELECT * FROM orders TABLESAMPLE BERNOULLI(5) REPEATABLE(42);

-- MonetDB（SAMPLE 子句，支持行数和比例）
SELECT * FROM large_table SAMPLE 1000;              -- 固定行数
SELECT * FROM large_table SAMPLE 0.1;               -- 10%

-- Redshift（标准语法，按 1MB 块采样，不支持 REPEATABLE）
SELECT * FROM events TABLESAMPLE BERNOULLI(10);

-- StarRocks / Doris（仅行数采样，用于数据预览）
SELECT * FROM large_table TABLESAMPLE (1000 ROWS);

-- Azure Synapse（块级，支持 ROWS 和 REPEATABLE）
SELECT * FROM dbo.large_table TABLESAMPLE (10 PERCENT) REPEATABLE (42);
```

## REPEATABLE 子句：可重复的确定性采样

### 语义与用途

```sql
-- REPEATABLE(seed) 确保：相同种子 + 相同数据 → 相同结果
-- 典型用途：
--   A/B 测试分组（确保同一用户始终在同一组）
--   可复现的实验
--   调试和单元测试

-- PostgreSQL
SELECT * FROM users TABLESAMPLE BERNOULLI(5) REPEATABLE(12345);
-- 多次执行返回完全相同的行集合（前提：表数据未变化）
```

### 各引擎 REPEATABLE/SEED 支持对比

| 引擎 | 语法 | 备注 |
|------|------|------|
| PostgreSQL | `REPEATABLE(seed)` | 标准语法，BERNOULLI 和 SYSTEM 均支持 |
| SQL Server | `REPEATABLE(seed)` | 仅 SYSTEM 方法 |
| Oracle | `SEED(seed)` | 非标准关键字 |
| Snowflake | `SEED(seed)` 或 `REPEATABLE(seed)` | 两者等价 |
| DuckDB | 方法参数中传入种子 | `SAMPLE 10% (BERNOULLI, 42)` |
| Spark SQL | `SEED(seed)` | 仅在 TABLESAMPLE 百分比模式下 |
| DB2 | `REPEATABLE(seed)` | 标准语法 |
| SAP HANA | `REPEATABLE(seed)` | 标准语法 |
| Impala | `REPEATABLE(seed)` | 仅 SYSTEM 方法 |
| Trino | -- | 不支持 |
| BigQuery | -- | TABLESAMPLE SYSTEM 支持，但无 REPEATABLE |
| Redshift | -- | 不支持 |
| ClickHouse | `OFFSET` | 非标准，通过偏移实现不同分片 |

局限性：数据变化后失效；跨引擎不可复现（随机数算法不同）；SYSTEM 的 REPEATABLE 对物理布局敏感；并行度变化可能影响结果。

## Reservoir Sampling（蓄水池采样）

### 算法原理

当需要从未知大小的数据流中精确采样 k 行时，Reservoir Sampling 是经典解法：

```
算法（Vitter's Algorithm R）：
1. 将前 k 行放入"蓄水池"
2. 对第 i 行（i > k）：
   以概率 k/i 替换蓄水池中的一个随机行
3. 遍历结束后，蓄水池中的 k 行即为均匀随机样本

空间复杂度：O(k)，与数据总量无关
时间复杂度：O(N)，需遍历全部数据
```

### 引擎支持

| 引擎 | 语法 | 备注 |
|------|------|------|
| DuckDB | `USING SAMPLE 1000 (RESERVOIR)` | 原生支持 |
| PostgreSQL | `TABLESAMPLE SYSTEM_ROWS(1000)` | 扩展实现，非严格 Reservoir |
| Teradata | `SAMPLE 1000` | 内部使用类似算法 |
| MonetDB | `SAMPLE 1000` | 固定行数采样 |
| 其他引擎 | -- | 多数不直接支持 |

Reservoir Sampling 的核心优势是**精确返回指定行数**，而 BERNOULLI/SYSTEM 只能返回近似行数。

## 分层采样（Stratified Sampling）

按分组/分区独立采样，确保每个子群体都有足够代表性。

### Teradata（原生支持）

```sql
-- 按条件分层，每层不同采样数
SELECT * FROM customers
SAMPLE
    WHEN region = 'North' THEN 500
    WHEN region = 'South' THEN 300
    WHEN region = 'East'  THEN 200
    WHEN region = 'West'  THEN 400
END;
```

### 其他引擎的模拟方案

```sql
-- 通用方案：窗口函数 + 随机排序
-- PostgreSQL / Trino / DuckDB / Snowflake 等
SELECT * FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY region ORDER BY RANDOM()) AS rn
    FROM customers
) t
WHERE rn <= 100;   -- 每个 region 取 100 行

-- Snowflake：利用 QUALIFY 简化
SELECT *
FROM customers
QUALIFY ROW_NUMBER() OVER (PARTITION BY region ORDER BY RANDOM()) <= 100;

-- ClickHouse：使用 LIMIT BY
SELECT * FROM customers
ORDER BY rand()
LIMIT 100 BY region;
```

注意：BERNOULLI 天然保持原始分布比例（行独立采样），无需额外处理。如需过采样少数群体，可用窗口函数按组控制比例。

## 采样在子查询和视图中的行为

### 子查询中的采样

```sql
-- 先过滤再采样（缩小采样范围）
-- 重要：对子查询结果使用 TABLESAMPLE 并非通用能力，各引擎差异很大：
-- PostgreSQL: 仅支持基表，不能对子查询使用 TABLESAMPLE（会报语法错误）
-- SQL Server: 仅支持基表和简单视图，对子查询使用会报错
-- DuckDB: 支持对子查询结果采样
-- Snowflake: 支持对子查询结果采样（使用 SAMPLE 语法）
-- Trino/Presto: 仅支持基表
-- 下面的写法仅在部分引擎中合法，请勿作为通用模式使用：
SELECT * FROM (
    SELECT * FROM orders WHERE status = 'completed'
) completed_orders TABLESAMPLE BERNOULLI(10);
-- 如果目标引擎不支持子查询采样，推荐方案：先将子查询结果写入临时表，再对临时表采样

-- 先采样再过滤（标准语义：TABLESAMPLE 在 FROM 中，所有引擎通用）
SELECT * FROM orders TABLESAMPLE BERNOULLI(10)
WHERE status = 'completed';
-- 注意：这里是从全表采样 10% 后再过滤 status
-- 如果 status = 'completed' 只占 5%，最终只有约 0.5% 的数据
```

### 视图与 JOIN 中的采样

```sql
-- 视图采样（仅部分引擎支持）
CREATE VIEW active_users AS SELECT * FROM users WHERE last_login > CURRENT_DATE - 30;
SELECT * FROM active_users TABLESAMPLE BERNOULLI(5);
-- 注意：PostgreSQL/Oracle/Db2 支持视图采样；SQL Server 对复杂视图可能报错；
-- MySQL/MariaDB/SQLite/ClickHouse 不支持 TABLESAMPLE，更无视图采样。

-- JOIN 中对单表采样
SELECT o.*, c.name
FROM orders TABLESAMPLE BERNOULLI(5) o
JOIN customers c ON o.customer_id = c.id;
-- 只有 orders 被采样，customers 全表扫描
```

## ORDER BY RANDOM() LIMIT N：通用替代方案

### 基本用法

```sql
-- MySQL
SELECT * FROM large_table ORDER BY RAND() LIMIT 1000;

-- PostgreSQL
SELECT * FROM large_table ORDER BY RANDOM() LIMIT 1000;

-- SQLite
SELECT * FROM large_table ORDER BY RANDOM() LIMIT 1000;

-- SQL Server
SELECT TOP 1000 * FROM large_table ORDER BY NEWID();
```

执行过程：全表扫描 + 为每行生成随机数 + 全量排序 + 取前 N 行。1 亿行表约 60 秒，而 TABLESAMPLE SYSTEM(0.001) 只需 ~0.1 秒。

### MySQL 优化替代方案

```sql
-- 方案 1：基于主键范围随机（快但主键有空洞时分布不均）
SELECT * FROM large_table
WHERE id >= FLOOR(RAND() * (SELECT MAX(id) FROM large_table))
LIMIT 1000;

-- 方案 2：哈希取模（可重复但非随机）
SELECT * FROM large_table WHERE MOD(id, 100) = 0;   -- 约 1%

-- 方案 3：应用层生成随机 ID 后 WHERE id IN (...)
```

## 近似查询处理与采样的关系

采样与近似查询处理（Approximate Query Processing, AQP）紧密相关。

### 基于采样的近似聚合

```sql
-- 采样 1% 后估算：COUNT 乘以 100，AVG 直接使用（无偏），SUM 乘以 100
SELECT COUNT(*) * 100 AS estimated_total,
       AVG(amount) AS avg_amount,
       SUM(amount) * 100 AS estimated_sum
FROM orders TABLESAMPLE BERNOULLI(1);
```

### HyperLogLog 与采样的互补

```sql
-- 采样后 COUNT DISTINCT 会低估（遗漏低频值），推荐用 HLL：
SELECT APPROX_COUNT_DISTINCT(user_id) FROM events;    -- BigQuery/Snowflake
SELECT uniq(user_id) FROM events;                      -- ClickHouse

-- 极端大数据量：采样 + HLL 双重近似（Snowflake / PostgreSQL 等支持 TABLESAMPLE 的引擎）
SELECT APPROX_COUNT_DISTINCT(user_id) FROM events TABLESAMPLE SYSTEM(10);
```

### 近似函数支持矩阵（与采样互补）

| 引擎 | APPROX_COUNT_DISTINCT | 近似分位数 | 算法 |
|------|----------------------|-----------|------|
| BigQuery | `APPROX_COUNT_DISTINCT` | `APPROX_QUANTILES` | HLL++, GK |
| Snowflake | `APPROX_COUNT_DISTINCT` | `APPROX_PERCENTILE` | HLL, t-digest |
| ClickHouse | `uniq` / `uniqHLL12` | `quantile` | 自适应, t-digest |
| Trino | `approx_distinct` | `approx_percentile` | HLL, qdigest |
| Spark SQL | `approx_count_distinct` | `percentile_approx` | HLL, GK |
| DuckDB | `approx_count_distinct` | `approx_quantile` | HLL, t-digest |
| Oracle | `APPROX_COUNT_DISTINCT` | `APPROX_PERCENTILE` | HLL, t-digest |
| PostgreSQL | 扩展 (pg_hll) | -- | HLL |
| Redshift | `APPROXIMATE COUNT(DISTINCT)` | `APPROXIMATE PERCENTILE_DISC` | HLL |
| SQL Server | -- | -- | 不支持 |
| MySQL | -- | -- | 不支持 |

## 性能：全扫描的避免策略

### 各采样方法的 I/O 行为

| 方法 | 全表扫描 | I/O 减少 | 实现要求 |
|------|---------|---------|---------|
| BERNOULLI | 是（逐行判断） | 无 | 无特殊要求 |
| SYSTEM | 否（按块跳过） | 显著（与采样率成比例） | 存储层支持块级跳过 |
| RESERVOIR | 是（需遍历全部数据） | 无 | 无特殊要求 |
| ClickHouse SAMPLE | 否（哈希范围裁剪） | 显著 | 需要采样键索引 |
| ORDER BY RAND() | 是 + 排序开销 | 无，反而更慢 | 无特殊要求 |

### 存储格式对采样性能的影响

| 存储类型 | SYSTEM 跳过粒度 | 典型大小 | 采样精度 |
|---------|----------------|---------|---------|
| 行存储（PG, SQL Server） | page | 8KB | 高（粒度细） |
| 列存储（ClickHouse, Parquet） | row group | 几十 MB | 中等 |
| 分布式存储（HDFS/S3） | split / 文件 | 64-256MB | 低（粒度粗） |
| 向量化引擎（DuckDB, Velox） | batch | 可配置 | 中高 |

## 设计争议

### 采样在 SQL 执行管道中的位置

SQL 标准将 TABLESAMPLE 定义在 FROM 子句中，逻辑上在 WHERE 之前执行。这意味着 `SELECT * FROM orders TABLESAMPLE BERNOULLI(1) WHERE status = 'A'` 是先采样 1% 再过滤，而非先过滤再采样。如需后者，须用子查询包装。

### 谓词下推与采样的交互

BERNOULLI 与 WHERE 可交换顺序（行独立，语义等价）；SYSTEM 不可交换（块组成会因过滤改变）。PostgreSQL 保持标准语义不做此优化，部分分析引擎可能优化。

### 为什么 MySQL 至今不支持？

InnoDB 的 B+ 树聚簇索引不容易做块级跳过（叶子页链表相连）。BERNOULLI 实现虽简单但团队未优先实现。社区多次请求，截至 MySQL 9.0 仍未支持。

### 采样结果缓存

无 REPEATABLE 时每次执行应返回不同行（标准语义）。注意某些 MPP 引擎的查询缓存可能意外返回相同结果。

## 对引擎开发者的实现建议

### 1. BERNOULLI 采样算子

行级概率过滤，实现最简单：

```
BernoulliSampleScan {
    child: TableScan
    probability: f64          // 0.0 ~ 1.0
    rng: RandomGenerator      // 可用 seed 初始化

    fn next() -> Option<Row>:
        loop:
            row = child.next()?
            if rng.next_f64() < probability:
                return Some(row)
}
```

关键点：
- 必须扫描全表，无法跳过 I/O
- 优化器不应将 BERNOULLI 采样推到存储层做 I/O 裁剪
- 向量化实现：对整个 batch 生成随机数数组，用 SIMD 比较后生成选择向量

### 2. SYSTEM 采样算子

块级跳过，可大幅减少 I/O：

```
SystemSampleScan {
    child: TableScan
    probability: f64
    rng: RandomGenerator
    current_block_selected: bool

    fn next_block() -> bool:
        current_block_selected = rng.next_f64() < probability
        return current_block_selected

    fn next() -> Option<Row>:
        while !current_block_selected:
            child.skip_block()     // 关键：跳过整个块的 I/O
            if !child.has_next_block(): return None
            next_block()
        return child.next()
}
```

关键点：
- 需要存储层支持 `skip_block()` 操作，否则退化为 BERNOULLI
- 块大小直接影响采样粒度和方差
- 列存引擎可按 row group 跳过，行存引擎按 page 跳过

### 3. RESERVOIR 采样算子

精确返回 k 行：

```
ReservoirSampleScan {
    child: TableScan
    k: usize                  // 目标行数
    reservoir: Vec<Row>       // 蓄水池，容量 k
    count: usize              // 已见行数
    rng: RandomGenerator

    fn execute() -> Vec<Row>:
        // 阶段 1：填充蓄水池
        for i in 0..k:
            row = child.next()?
            reservoir.push(row)
            count += 1

        // 阶段 2：随机替换
        while let Some(row) = child.next():
            count += 1
            j = rng.gen_range(0, count)   // [0, count)
            if j < k:
                reservoir[j] = row

        return reservoir
}
```

关键点：
- 必须遍历全部数据，但空间复杂度 O(k)
- 可用 Vitter 的 Algorithm L 优化随机数生成次数

### 4. REPEATABLE 的实现

```
核心要点：
1. 使用确定性 PRNG（如 PCG, Xoshiro256）初始化: rng = new PRNG(seed)
2. 保证可重复性需固定：随机数算法、数据物理顺序、块大小、并行度
3. 并行查询的种子分配：seed_i = hash(user_seed, thread_id)
```

### 5. 与优化器的交互

```
1. 行数估计：BERNOULLI(1) → 预估 N * 0.01 行
2. 谓词交换：BERNOULLI 可与 WHERE 交换顺序（语义等价），SYSTEM 不可
3. 索引：TABLESAMPLE 通常强制全表扫描，ClickHouse SAMPLE 基于索引例外
4. 分布式：BERNOULLI 各节点独立采样；RESERVOIR(k) 需全局协调
```

### 6. BERNOULLI 的 O(N) 全扫描本质

BERNOULLI 采样经常被误认为可以减少 I/O，但它的本质是**全表扫描 + 逐行概率过滤**:

```
BERNOULLI(1) 对 1 亿行表的执行过程:
  1. 读取第 1 行 → 生成随机数 → 1% 概率保留 → 继续
  2. 读取第 2 行 → 生成随机数 → 1% 概率保留 → 继续
  ...
  100,000,000. 读取最后一行 → 生成随机数 → 判断

总 I/O: 读取全部 100M 行 = 全表扫描
总 CPU: 100M 次随机数生成 + 比较
输出: ~1M 行 (预期)

对比 SYSTEM(1):
  总 I/O: 仅读取 ~1% 的数据页 = 大幅减少 I/O
  总 CPU: 每个块一次随机数生成
  输出: ~1M 行 (预期, 但方差更大)
```

**引擎实现建议**:
- 优化器的代价估算中，BERNOULLI 的 I/O 代价 = 全表扫描代价 (不可减少)
- 仅在输出行数估计上使用 `N * probability`，不可在 I/O 估计上使用
- 在 EXPLAIN 输出中明确标注 "Full Scan (Bernoulli filter)" 避免用户误解
- 如果用户只需要快速预览，应推荐 SYSTEM 采样而非 BERNOULLI

### 7. 谓词下推与采样的交互悖论

采样与 WHERE 过滤的执行顺序对 SYSTEM（块级）采样会显著影响结果，但对 BERNOULLI（行级）采样语义等价:

```
BERNOULLI (行独立采样): 与 WHERE 可交换
  -- 以下两种写法语义等价（每行独立以 10% 概率选中，与过滤顺序无关）:
  SELECT * FROM orders TABLESAMPLE BERNOULLI(10) WHERE status = 'completed';
  SELECT * FROM (SELECT * FROM orders WHERE status = 'completed') TABLESAMPLE BERNOULLI(10);

SYSTEM (块级采样): 与 WHERE 不可交换
  方案 A: 先采样后过滤
    SELECT * FROM orders TABLESAMPLE SYSTEM(10) WHERE status = 'completed';
    -- 先选 10% 的数据块，再从中过滤 status
    -- 如果 completed 行在块间分布不均匀，结果有偏

  方案 B: 先过滤后采样
    SELECT * FROM (SELECT * FROM orders WHERE status = 'completed')
    TABLESAMPLE SYSTEM(10);
    -- 先过滤 completed 行，再从结果的块中选 10%
    -- 块的组成不同，采样结果不同
```

**关键区别**:
- BERNOULLI: 逐行独立概率，WHERE 前后交换不影响结果分布（语义等价）
- SYSTEM: 块级选择，WHERE 过滤改变了块的组成，两种顺序结果不同
- 当使用 SYSTEM 采样且 WHERE 过滤条件与分析目标相关时，两种方案的统计推断结论可能不同

**引擎实现建议**:
- SQL 标准规定 TABLESAMPLE 在 FROM 子句中，语义上在 WHERE 之前执行
- 优化器**不应**将 WHERE 谓词下推到采样算子之前 (会改变语义)
- BERNOULLI 是特例: 可以交换 (因为逐行独立概率)，但仅限于不影响采样概率的谓词
- SYSTEM 不可交换: 块级选择与行级过滤不可互换

### 8. 块级采样的 I/O 优化与高并发 PRNG 调优

**块级采样 (SYSTEM) 的 I/O 优化**:
```
行存引擎 (页级跳过):
  - InnoDB: B+ 树叶子页链表连接 → 可以跳过未选中的页
  - PostgreSQL heap: 直接按页号跳过 → 随机 I/O 变为稀疏顺序 I/O
  - 关键: skip_block() 必须是真正的 I/O 跳过，不能读取后丢弃

列存引擎 (row group 级跳过):
  - Parquet/ORC: 每个 row group 有独立的元数据 → 跳过整个 row group 的 I/O
  - 效率: 单个 row group 通常 1M 行 → SYSTEM(1) 在 100M 行表上仅读 ~1 个 row group
  - 优势: 列存的 row group 粒度天然适合 SYSTEM 采样
```

**高并发场景的 PRNG 性能调优**:
```
问题: 多线程并行扫描时，共享 PRNG 成为热点
  - 锁竞争: 全局 PRNG + mutex → 采样算子成为瓶颈
  - 线程安全: AtomicU64 CAS 循环 → 高竞争下性能退化

解决方案:
  1. 线程本地 PRNG: 每个扫描线程独立的 PRNG 实例
     seed_i = hash(user_seed, thread_id)  -- 确保可重复性
  2. 批量生成: 一次生成整个 batch 的随机数 (如 1024 个)
     减少 PRNG 调用频率，利于 CPU 流水线和分支预测
  3. PRNG 算法选择:
     - PCG/Xoshiro256: 高性能，适合采样 (非密码学安全)
     - 避免 Mersenne Twister: 状态大 (2.5KB)，缓存不友好
     - 避免 /dev/urandom: 系统调用开销过高
```

### 9. 向量化与测试建议

向量化实现：对整个 batch 生成随机数数组，用 SIMD 比较生成选择向量。SYSTEM 方法可按 batch 级别决定是否跳过 I/O。

测试要点：
- 统计检验：BERNOULLI(10) 多次执行，验证均值 ~ N*0.1，标准差 ~ sqrt(N*0.1*0.9)
- REPEATABLE：同一种子多次执行结果完全相同
- 边界：BERNOULLI(0) → 0 行，BERNOULLI(100) → 全部行，空表 → 0 行
- 组合：验证 TABLESAMPLE + WHERE / JOIN / GROUP BY / LIMIT / 窗口函数

## 总结对比矩阵

### 采样能力总览

| 能力 | PostgreSQL | SQL Server | Oracle | Snowflake | ClickHouse | DuckDB | Hive | Trino | Teradata | BigQuery |
|------|-----------|------------|--------|-----------|------------|--------|------|-------|----------|----------|
| BERNOULLI | 是 | -- | 行级 | 是 | 哈希 | 是 | -- | 是 | 行级 | -- |
| SYSTEM/BLOCK | 是 | 是 | BLOCK | 是 | -- | 是 | -- | 是 | -- | 是 |
| 固定行数 | 扩展 | ROWS | -- | ROWS | 是 | 是 | ROWS | -- | 是 | -- |
| REPEATABLE | 是 | 是 | SEED | 是 | 偏移 | 是 | -- | -- | -- | -- |
| RESERVOIR | -- | -- | -- | -- | -- | 是 | -- | -- | -- | -- |
| 分层采样 | 模拟 | 模拟 | 模拟 | 模拟 | LIMIT BY | 模拟 | 桶 | 模拟 | 原生 | -- |
| 按数据量采样 | -- | -- | -- | -- | -- | -- | 是 | -- | -- | -- |
| 近似聚合函数 | 扩展 | -- | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 |

### 引擎选型建议

| 场景 | 推荐引擎/方法 | 原因 |
|------|-------------|------|
| 高精度统计采样 | PostgreSQL BERNOULLI | 行级随机，标准兼容 |
| 超大表快速预览 | Snowflake SYSTEM | 块级跳过，秒级响应 |
| 精确 N 行采样 | DuckDB RESERVOIR | 精确行数，均匀分布 |
| 可重复实验 | PostgreSQL/Snowflake + REPEATABLE | 确定性种子 |
| 分层采样 | Teradata SAMPLE WHEN | 原生分层支持 |
| 流数据/无采样引擎 | ORDER BY RANDOM() LIMIT N | 通用但慢 |
| 超大规模去重估算 | 采样 + HLL（任一支持引擎） | 双重近似，极快 |

## 参考资料

- SQL:2003 标准: ISO/IEC 9075-2, Section 7.6 (table reference - TABLESAMPLE)
- PostgreSQL: [TABLESAMPLE](https://www.postgresql.org/docs/current/sql-select.html#SQL-FROM)
- PostgreSQL: [tsm_system_rows / tsm_system_time](https://www.postgresql.org/docs/current/tsm-system-rows.html)
- SQL Server: [TABLESAMPLE](https://learn.microsoft.com/en-us/sql/t-sql/queries/from-transact-sql#tablesample-clause)
- Oracle: [SAMPLE Clause](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SELECT.html)
- Snowflake: [SAMPLE / TABLESAMPLE](https://docs.snowflake.com/en/sql-reference/constructs/sample)
- DuckDB: [Samples](https://duckdb.org/docs/sql/samples)
- ClickHouse: [SAMPLE Clause](https://clickhouse.com/docs/en/sql-reference/statements/select/sample)
- Hive: [TABLESAMPLE](https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Sampling)
- Trino: [TABLESAMPLE](https://trino.io/docs/current/sql/select.html#tablesample)
- Teradata: [SAMPLE](https://docs.teradata.com/r/Teradata-Database-SQL-Data-Manipulation-Language)
- Spark SQL: [TABLESAMPLE](https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-sampling.html)
- Vitter, J.S. "Random Sampling with a Reservoir" (1985), ACM Transactions on Mathematical Software
- Olken, F. "Random Sampling from Databases" (1993), UC Berkeley PhD Thesis
