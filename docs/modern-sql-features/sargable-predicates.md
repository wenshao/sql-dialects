# SARGable 谓词与下推 (SARGable Predicates and Pushdown)

把 `WHERE date_col = '2024-01-01'` 写成 `WHERE DATE(date_col) = '2024-01-01'`，性能可能差 1000 倍——前者一次索引 seek，后者扫全表。SARGable（Search ARGument-able）这个 1970 年代 IBM System R 时期发明的术语，至今仍是每个数据库工程师必须理解的核心概念：它决定了一个谓词能否被转化为索引上的范围搜索。本文系统对比 45+ 个数据库引擎对 SARGable 谓词的识别、谓词下推（predicate pushdown）以及"逃生出口"——函数索引（functional / function-based / expression index）和计算列索引（computed column index）——的支持差异。

## SARGable 概念溯源

"SARG" 是 **S**earch **ARG**ument 的缩写，起源于 IBM System R（1974-1979 年的关系数据库原型）。Pat Selinger 与同事在 1979 年的奠基性论文 *"Access Path Selection in a Relational Database Management System"*（SIGMOD 1979）里把谓词分成两类：

- **SARG**（sargable predicate）：可以下推到 RSI（Relational Storage Interface）层、利用索引或顺序扫描时直接过滤的谓词，典型形式是 `column op value`、`column op host_variable`、`column BETWEEN value AND value`、`column IN (value-list)`。
- **Residual predicate**（残余谓词）：必须在元组从存储层取出后、由查询执行器在主内存中评估的谓词，例如 `f(column) op value` 或两列之间的复杂表达式。

Selinger 的优化器只把 SARG 推到访问路径选择上，因为只有 SARG 能直接驱动 B-tree 索引的范围 seek（开始键 + 结束键）。这条 50 年前划下的边界至今支配着所有关系数据库的优化器：一个谓词是不是 SARGable，决定了它是 `Index Seek` 还是 `Index Scan + Filter`，直接决定了 1 行 vs 10 亿行的 I/O 差异。

后来的 System R 文献进一步把 SARG 细分为：
1. **Index sargable**（强 SARG）：谓词可以转换为索引键的范围（start-key, stop-key），驱动 index seek。
2. **Data sargable**（弱 SARG）：谓词不能驱动 seek，但可以在存储引擎扫描行时立即过滤，无需返回到执行器（节省函数调用和 tuple 传递开销）。
3. **Residual**（非 SARG）：必须在执行器的 Filter 算子中评估。

现代优化器（PostgreSQL、SQL Server、Oracle、DB2 等）基本沿用这套三级模型，只是术语略有差异：PostgreSQL 用 `index quals` / `index cond` / `filter`，SQL Server 用 `Seek Predicate` / `Predicate`，Oracle 用 `access` / `filter`。

## SARGable 与非 SARGable 谓词的标准定义

### 标准 SARGable 形式

```sql
-- 强 SARG（可驱动 index seek）
column op constant                   -- col = 5, col > 100, col <= '2024-01-01'
column op host_variable              -- col = ?, col >= :p1
column BETWEEN constant AND constant -- col BETWEEN 10 AND 100
column IN (constant_list)            -- col IN (1, 2, 3)
column IS NULL                       -- 大多数引擎支持 (PG/Oracle/SQL Server)
column IS NOT NULL                   -- 视引擎而定
column LIKE 'literal_prefix%'        -- 前缀通配，可转为 [prefix, prefix末位+1) 范围

-- 弱 SARG（可在存储层过滤，但不能 seek）
column op column                     -- col1 = col2（同表）
NOT (column op constant)             -- 可改写为 col != constant
```

### 标准非 SARGable 形式

```sql
-- 函数包裹列（核心 SARG 杀手）
WHERE UPPER(name) = 'ALICE'              -- 函数应用于列
WHERE DATE(created_at) = '2024-01-01'    -- 时间函数包裹
WHERE SUBSTRING(code, 1, 3) = 'ABC'      -- 字符串函数
WHERE col + 1 = 100                      -- 算术运算包裹
WHERE col * 2 > 50                       -- 同上
WHERE YEAR(birth_date) = 1990            -- 提取年份

-- 通配符前置的 LIKE
WHERE name LIKE '%Smith'                 -- 后缀匹配
WHERE name LIKE '%Smith%'                -- 包含匹配

-- 隐式类型转换（cast on the column）
WHERE varchar_id = 12345                 -- 列被隐式转为 INT
WHERE date_col = '2024-01-01 12:00:00'   -- date 与 timestamp 混用

-- OR 跨多列（部分情况非 SARG）
WHERE col1 = 1 OR col2 = 2               -- 单索引无法直接 seek

-- 否定形式（部分非 SARG）
WHERE col != 5                           -- 通常是全扫描
WHERE col NOT IN (1, 2, 3)               -- 同上
WHERE NOT EXISTS / NOT IN (subquery)     -- 视优化器而定
```

## 支持矩阵（45+ 引擎）

### 函数索引 / 表达式索引基础支持

下表列出 45+ 数据库对 SARGable 关键能力的支持情况，重点关注"函数索引"——也就是把 `f(column)` 形式的非 SARG 谓词重新变 SARG 的"逃生出口"。

| 引擎 | 函数索引 / 表达式索引 | 计算列索引 | 隐式 cast 优化 | LIKE 前缀 SARG | 引入版本 |
|------|---------------------|----------|---------------|---------------|---------|
| PostgreSQL | `CREATE INDEX ON t ((lower(c)))` | -- | 部分 | 是（C locale 或 `text_pattern_ops`） | 7.4 (2003) |
| MySQL | `CREATE INDEX ON t ((lower(c)))` | `GENERATED ALWAYS AS ... STORED` + 索引 | 是（8.0+） | 是 | 8.0.13 (2018) |
| MariaDB | -- | `GENERATED ALWAYS AS ... PERSISTENT` + 索引 | 部分 | 是 | 5.2 (2010) |
| SQLite | `CREATE INDEX ON t (lower(c))` | `GENERATED ALWAYS AS ... STORED` + 索引 | 类型亲和性影响 | 是 | 3.9 (2015) |
| Oracle | `CREATE INDEX i ON t (UPPER(c))` | 虚拟列 + 索引 | 部分 | 是 | 8i (1999) |
| SQL Server | -- | `computed column` PERSISTED + 索引 | 是 | 是 | 2000 |
| DB2 | -- | `expression-based index` | 是 | 是 | 10.5 (LUW) |
| Snowflake | -- | -- | 是（自动） | 部分（无传统索引） | 不适用（micro-partition） |
| BigQuery | -- | -- | 是 | 部分（cluster 列） | 不适用 |
| Redshift | -- | -- | 是 | 部分（sort key） | 不适用 |
| DuckDB | `CREATE INDEX ON t (lower(c))` | -- | 是 | 是 | 0.7+ |
| ClickHouse | 跳数索引 (skip index) | `MATERIALIZED` 列 | 是 | 是 | 19.6+ |
| Trino | -- (依赖连接器) | -- | 是 | 是 | 0.x |
| Presto | -- (依赖连接器) | -- | 是 | 是 | 0.x |
| Spark SQL | -- | -- | 是 | 是（分区裁剪） | 不适用 |
| Hive | -- | -- | 是 | 是（分区） | 不适用 |
| Flink SQL | -- | -- | 是 | 是 | 不适用 |
| Databricks | -- | `GENERATED ALWAYS AS` (Delta) | 是 | 是 | DBR 9+ |
| Teradata | -- | -- | 是 | 是 | V2R5+ |
| Greenplum | `CREATE INDEX ON t ((lower(c)))` | -- | 部分 | 是 | 4.x（继承 PG） |
| CockroachDB | `CREATE INDEX i ON t (lower(c))` | computed column + 索引 | 是 | 是 | 19.2 (2019) |
| TiDB | `CREATE INDEX i ON t ((lower(c)))` | `GENERATED ALWAYS AS` + 索引 | 是 | 是 | 5.0+ (2021) |
| OceanBase | -- | 生成列 + 索引 | 是 | 是 | 4.x |
| YugabyteDB | `CREATE INDEX ON t (lower(c))` | -- | 部分 | 是 | 2.6+ |
| SingleStore | `CREATE INDEX ON t (lower(c))` | persisted computed column | 是 | 是 | 7.0+ |
| Vertica | -- | -- | 是 | 部分 | 9.x |
| Impala | -- | -- | 是 | 是 | 4.x |
| StarRocks | bloom 索引 / bitmap 索引 | 生成列 | 是 | 是 | 2.x+ |
| Doris | bloom 索引 / 倒排索引 | 物化视图替代 | 是 | 是 | 1.2+ |
| MonetDB | -- | -- | 部分 | 是 | -- |
| CrateDB | -- | `GENERATED ALWAYS AS` + 索引 | 是 | 是 | 4.x |
| TimescaleDB | `CREATE INDEX ON t ((lower(c)))` | -- | 部分 | 是 | 继承 PG |
| QuestDB | -- | -- | 是 | 是 | -- |
| Exasol | -- | -- | 是 | 是 | -- |
| SAP HANA | -- | calculated column + 索引 | 是 | 是 | 2.0 |
| Informix | -- | -- | 是 | 是 | -- |
| Firebird | `CREATE INDEX ON t COMPUTED BY (...)` | computed column | 是 | 是 | 2.0+ |
| H2 | `CREATE INDEX ON t (lower(c))` | computed column | 部分 | 是 | -- |
| HSQLDB | -- | -- | 部分 | 是 | -- |
| Derby | -- | -- | 部分 | 是 | -- |
| Amazon Athena | -- | -- | 是 | 部分 | 不适用（继承 Trino） |
| Azure Synapse | -- | computed column + 索引 | 是 | 是 | -- |
| Google Spanner | `CREATE INDEX ON t (lower(c) STORING ...)` (生成列) | 是 | 是 | 是 | GA |
| Materialize | -- | -- | 是 | 是 | -- |
| RisingWave | -- | -- | 是 | 是 | -- |
| InfluxDB (SQL) | -- | -- | 是 | -- | 不适用（时序模型） |
| DatabendDB | -- | -- | 是 | 是 | GA |
| Yellowbrick | -- | -- | 是 | 是 | -- |
| Firebolt | -- | -- | 是 | 是 | -- |

> 注：列存与 MPP 引擎（Snowflake、BigQuery、Redshift、Spark）通常没有传统 B-tree 索引，因此"SARG"概念退化为"是否能下推到存储层做 partition / cluster / zone-map / bloom 过滤"。"是"在这些引擎里指代"谓词被下推到 scanner 层"。

### LIKE 模式 SARGable 性

| 模式 | SARGable | 原因 |
|------|---------|------|
| `LIKE 'abc%'` | 是 | 可改写为 `col >= 'abc' AND col < 'abd'`，开始键 + 结束键 |
| `LIKE 'abc_def'` | 部分 | 可作为 `col >= 'abc'` 的前缀范围，`_` 用残余谓词 |
| `LIKE '%abc'` | 否 | 后缀匹配，B-tree 无法 seek（除非有反向索引） |
| `LIKE '%abc%'` | 否 | 包含匹配，需全表扫描或全文索引 |
| `LIKE 'abc%def'` | 部分 | 仅 `abc` 前缀可 seek，`def` 用残余谓词 |
| `LIKE '_abc'` | 否 | 通配符前置，无法用前缀 |
| `LIKE 'abc'`（无通配） | 是 | 等同于 `=`（部分引擎按等值优化） |
| `ILIKE 'abc%'`（PG）| 部分 | 标准索引不行，需 `text_pattern_ops` 或函数索引 |

### 函数应用导致非 SARG 的常见模式

| 模式 | SARGable | 修正方案 |
|------|---------|---------|
| `UPPER(col) = 'X'` | 否 | 创建函数索引 `((upper(col)))` 或改写 `col = 'X' OR col = 'x'`（小集合） |
| `LOWER(col) = 'x'` | 否 | 同上 |
| `DATE(ts_col) = '2024-01-01'` | 否 | 改写 `ts_col >= '2024-01-01' AND ts_col < '2024-01-02'` |
| `YEAR(col) = 2024` | 否 | 改写 `col >= '2024-01-01' AND col < '2025-01-01'` |
| `MONTH(col) = 4` | 否 | 函数索引 `((extract(month from col)))` 或改写为 12 个范围的 OR |
| `EXTRACT(YEAR FROM col) = 2024` | 否 | 同 `YEAR()` 改写 |
| `SUBSTR(col, 1, 3) = 'ABC'` | 否 | 改写 `col LIKE 'ABC%'` 或函数索引 |
| `col + 0 = 100` | 否 | 改写 `col = 100`（注意：某些 DBA 用 `+0` 故意"杀 SARG" 强制全扫描） |
| `col * 2 > 50` | 否 | 改写 `col > 25`（仅当列类型可推） |
| `col || 'X' = 'aX'` | 否 | 改写为 `col = 'a'`（仅常量后缀） |
| `CAST(col AS INT) = 5` | 否 | 检查列类型，避免不必要的 cast |
| `COALESCE(col, 0) = 5` | 否 | 改写 `col = 5 OR (col IS NULL AND 5 = 0)` |
| `ISNULL(col, 0) = 5` (SQL Server) | 否 | 同 COALESCE |
| `NVL(col, 0) = 5` (Oracle) | 否 | 同 COALESCE |
| `TRIM(col) = 'x'` | 否 | 函数索引或保证写入时已 trim |

### 隐式类型转换（implicit cast）杀 SARG

```sql
-- 表 t.id 是 VARCHAR(20)
WHERE t.id = 12345                 -- 隐式 CAST(t.id AS INT)，杀 SARG
WHERE t.id = '12345'               -- SARG，索引 seek

-- 表 t.dt 是 DATE
WHERE t.dt = '2024-01-01 12:00:00' -- 字符串可能被解析为 TIMESTAMP，杀 SARG
WHERE t.dt = DATE '2024-01-01'     -- SARG

-- 字符集不一致也会触发隐式 cast
WHERE utf8_col = latin1_literal    -- 部分引擎需要 collation 转换
```

| 引擎 | 隐式 cast 处理 |
|------|---------------|
| PostgreSQL | 严格类型，许多 cast 必须显式；隐式 cast 数量少 |
| MySQL | 8.0 之前对字符串 → 数值的隐式 cast 极易杀 SARG；8.0+ 对部分模式优化 |
| Oracle | NUMBER vs VARCHAR2 的隐式 cast 是经典 SARG 杀手；推荐显式 cast 字面量 |
| SQL Server | 数据类型优先级表决定哪一边被 cast；列被 cast 时杀 SARG |
| DB2 | 类似 Oracle，强类型 |
| SQLite | 动态类型亲和性，规则反而比静态类型简单 |

## 各引擎实现详解

### PostgreSQL（函数索引最早成熟）

PostgreSQL 在 7.4 (2003) 引入"表达式索引"（expression index，又称 functional index），是开源数据库中最早提供的实现：

```sql
-- 经典函数索引：大小写不敏感查询
CREATE INDEX users_lower_email_idx ON users (lower(email));

-- 现在以下查询能用索引 seek
SELECT * FROM users WHERE lower(email) = 'alice@example.com';

-- 复合表达式索引
CREATE INDEX orders_year_amount_idx ON orders ((extract(year from created_at)), amount);

-- LIKE 前缀（默认 collation 时需要 text_pattern_ops）
CREATE INDEX products_name_pattern_idx ON products (name text_pattern_ops);
SELECT * FROM products WHERE name LIKE 'Apple%';

-- 部分索引（partial index）+ 表达式
CREATE INDEX active_orders_idx ON orders ((customer_id))
WHERE status = 'active';

-- 注意：索引表达式必须 IMMUTABLE（不可变）
-- 例如 NOW()、CURRENT_TIMESTAMP 不能用作索引表达式
-- LOWER 是 IMMUTABLE，DATE_TRUNC 也是 IMMUTABLE（在固定时区下）
-- 含 timestamptz 时需要小心：CAST(timestamptz AS DATE) 不是 IMMUTABLE
```

PostgreSQL 的优化器在规划查询时会匹配 `WHERE` 中的表达式与索引中的表达式，如果完全一致（按规范化形式），则使用索引。

```sql
-- 检查索引使用
EXPLAIN SELECT * FROM users WHERE lower(email) = 'alice@example.com';
-- Index Scan using users_lower_email_idx
--   Index Cond: (lower(email) = 'alice@example.com'::text)
```

### MySQL（最晚的主流引擎，2018 年才支持）

MySQL 长期没有函数索引，工程师只能依赖**生成列（generated column）+ 索引**的间接方案。直到 8.0.13（2018 年 10 月）才原生支持：

```sql
-- 8.0.13 之前的间接方案：生成列
ALTER TABLE users ADD COLUMN email_lower VARCHAR(255)
    GENERATED ALWAYS AS (LOWER(email)) STORED;
CREATE INDEX users_email_lower_idx ON users (email_lower);

-- 查询必须显式引用生成列
SELECT * FROM users WHERE email_lower = 'alice@example.com';

-- 8.0.13+ 原生函数索引（无需生成列）
CREATE INDEX users_lower_email_idx ON users ((LOWER(email)));

-- 现在直接写函数即可命中索引
SELECT * FROM users WHERE LOWER(email) = 'alice@example.com';

-- JSON 字段是函数索引的常见用途
CREATE INDEX users_city_idx ON users ((CAST(JSON_EXTRACT(profile, '$.city') AS CHAR(50))));
SELECT * FROM users WHERE CAST(JSON_EXTRACT(profile, '$.city') AS CHAR(50)) = 'Beijing';
```

MySQL 8.0 的函数索引限制：
- 表达式必须是确定性的（DETERMINISTIC）
- 不能引用其他列以外的对象
- 索引表达式必须用括号包裹：`((expression))`，单层括号会被解释为列名
- 主键、外键、空间索引、全文索引不支持函数索引

### Oracle（开创函数索引概念）

Oracle 8i (1999) 是第一个支持函数索引的主流商业数据库（早 PostgreSQL 4 年）：

```sql
-- 经典函数索引
CREATE INDEX emp_upper_name_idx ON employees (UPPER(last_name));

-- 现在大小写不敏感查询能用索引
SELECT * FROM employees WHERE UPPER(last_name) = 'SMITH';

-- 必须设置 QUERY_REWRITE_ENABLED = TRUE 和 QUERY_REWRITE_INTEGRITY = TRUSTED
-- 默认值在 9i 之后已改为 TRUE/ENFORCED

-- 函数必须确定性（DETERMINISTIC）
CREATE OR REPLACE FUNCTION get_year(d DATE) RETURN NUMBER
DETERMINISTIC IS BEGIN RETURN EXTRACT(YEAR FROM d); END;

CREATE INDEX orders_year_idx ON orders (get_year(order_date));

-- Oracle 11g+ 推荐使用虚拟列（virtual column）替代函数索引
ALTER TABLE orders ADD (order_year NUMBER GENERATED ALWAYS AS (EXTRACT(YEAR FROM order_date)));
CREATE INDEX orders_virtual_year_idx ON orders (order_year);

-- 注意：Oracle 函数索引会带来统计信息复杂性
-- 需要单独收集索引列的统计信息
EXEC DBMS_STATS.GATHER_TABLE_STATS('SCHEMA', 'EMPLOYEES', METHOD_OPT => 'FOR COLUMNS UPPER(LAST_NAME) SIZE AUTO');
```

### SQL Server（计算列索引，2000 年）

SQL Server 没有真正的"函数索引"，而是通过**计算列（computed column）**间接实现。SQL Server 2000 引入持久化计算列上建索引的能力：

```sql
-- 添加持久化计算列
ALTER TABLE Customers ADD UpperName AS UPPER(LastName) PERSISTED;
CREATE INDEX IX_Customers_UpperName ON Customers (UpperName);

-- 查询时可以直接用 UPPER(LastName) 或 UpperName，优化器会匹配
SELECT * FROM Customers WHERE UPPER(LastName) = 'SMITH';
SELECT * FROM Customers WHERE UpperName = 'SMITH';

-- 计算列的限制
-- 1. 表达式必须确定性
-- 2. 必须 PERSISTED 才能被索引（除非满足 PRECISE 等更复杂条件）
-- 3. 函数必须是 PRECISE（不涉及 float 不确定性）
-- 4. 表达式必须满足 SCHEMABINDING（如果引用了用户函数）

-- 验证表达式是否可索引
SELECT name, is_persisted, is_computed
FROM sys.columns WHERE object_id = OBJECT_ID('Customers');

-- SQL Server 2017+ 改进：自动匹配表达式
-- 即使不创建持久化计算列，优化器也能识别一些等价表达式
-- 但函数包裹列仍然需要计算列 + 索引才能 seek
```

### DB2（表达式索引）

DB2 LUW 10.5+ 提供"表达式索引"（expression-based index）：

```sql
CREATE INDEX emp_upper_name_idx ON employees (UPPER(last_name));

-- 优化器在查询包含相同表达式时使用索引
SELECT * FROM employees WHERE UPPER(last_name) = 'SMITH';
```

DB2 z/OS 长期使用"虚拟列"+索引模式，与 Oracle 类似。

### SQLite（轻量但完整）

SQLite 3.9 (2015) 引入函数索引（在 SQLite 文档中称为"index on expression"）：

```sql
CREATE INDEX users_lower_email_idx ON users (lower(email));
SELECT * FROM users WHERE lower(email) = 'alice@example.com';

-- SQLite 的类型亲和性（type affinity）会影响 SARG 行为
-- INTEGER 列存字符串 '5' 时，WHERE col = 5 会做隐式转换并仍可用索引
-- 但 WHERE col = '5' 与 col = 5 在 affinity 不同的列上结果可能不同

-- 生成列 + 索引（3.31+, 2020）
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    email TEXT,
    email_domain TEXT GENERATED ALWAYS AS (substr(email, instr(email, '@')+1)) STORED
);
CREATE INDEX users_domain_idx ON users (email_domain);
```

### CockroachDB / TiDB（分布式 NewSQL）

CockroachDB 19.2 和 TiDB 5.0 跟进了函数索引：

```sql
-- CockroachDB
CREATE INDEX users_lower_email_idx ON users (lower(email));

-- TiDB
CREATE INDEX users_lower_email_idx ON users ((LOWER(email)));
-- TiDB 语法与 MySQL 完全一致
```

分布式数据库的函数索引面临额外挑战：跨节点的表达式确定性、索引和表的范围分区一致性、统计信息的收集成本。

### ClickHouse（跳数索引而非传统索引）

ClickHouse 没有传统 B-tree 索引（除主键外），而是用**跳数索引（data skipping index）**：

```sql
-- 主键就是聚簇键，列存 + 排序保证范围查询效率
CREATE TABLE events (
    event_time DateTime,
    user_id UInt64,
    event_type String,
    INDEX idx_event_type event_type TYPE bloom_filter GRANULARITY 4,
    INDEX idx_user_id user_id TYPE minmax GRANULARITY 4
) ENGINE = MergeTree()
ORDER BY (event_time, user_id);

-- 这些跳数索引让如下查询跳过整个 granule
SELECT * FROM events WHERE event_type = 'click';        -- bloom filter 跳过
SELECT * FROM events WHERE user_id BETWEEN 100 AND 200; -- minmax 跳过

-- ClickHouse 也支持物化列（MATERIALIZED）模拟函数索引
CREATE TABLE events (
    event_time DateTime,
    user_id UInt64,
    event_date Date MATERIALIZED toDate(event_time)
) ENGINE = MergeTree()
ORDER BY (event_date, event_time);

-- 现在按日期过滤可以用主键
SELECT * FROM events WHERE event_date = '2024-04-01';
```

ClickHouse 跳数索引类型：
- `minmax`：每个 granule 记录最小/最大值
- `set(N)`：每个 granule 记录前 N 个不同值
- `bloom_filter`：bloom 过滤器
- `ngrambf_v1` / `tokenbf_v1`：n-gram bloom 过滤器，支持 `LIKE '%abc%'` 这类非 SARG 的子串匹配

### Snowflake / BigQuery / Redshift（无索引、依赖元数据剪枝）

云数据仓库通常没有传统索引，"SARG"概念退化为：

```sql
-- Snowflake：micro-partition pruning
-- 每个 micro-partition (~16MB) 维护列的 min/max
-- WHERE 子句中的 SARG 谓词触发 partition 裁剪
SELECT * FROM events WHERE event_date = '2024-04-01';
-- 自动跳过不含此日期的 micro-partition

-- BigQuery：分区表 + cluster
CREATE TABLE events
PARTITION BY DATE(event_time)
CLUSTER BY user_id, event_type
AS SELECT ... FROM source;

-- 这两条查询都触发分区/cluster 剪枝
SELECT * FROM events WHERE event_time >= '2024-04-01';
SELECT * FROM events WHERE user_id = 12345;

-- 但函数包裹分区列会失败（同传统 SARG 规则）
SELECT * FROM events WHERE DATE(event_time) = '2024-04-01';
-- 在 BigQuery 中通常仍可裁剪（DATE() 是分区函数），但
-- WHERE EXTRACT(MONTH FROM event_time) = 4 不会裁剪

-- Redshift：sort key + zone map
-- 与 Snowflake 类似，每个 1MB 块有 min/max
```

云数仓的"SARGable"等价于"能够触发 partition pruning / cluster pruning / micro-partition skip"。规则与传统索引基本一致：函数包裹列会破坏裁剪能力。

## 谓词下推（Predicate Pushdown）

谓词下推是 SARG 概念在执行计划层的体现：把 `WHERE` 谓词从执行树上层"下推"到数据扫描层（甚至存储引擎层），尽早过滤行以减少 I/O 和后续算子的工作量。

### 下推层级

```
查询语义层      WHERE col = 5
   ↓
逻辑优化层      把 WHERE 推到 Scan 之上（视图展开、子查询展开）
   ↓
物理优化层      转化为 Index Cond（如果列上有索引）
   ↓
存储引擎层      转化为存储读取的 SARG（直接 seek 索引）
   ↓
存储格式层      列存 zone-map / parquet row group filter / bloom
```

### 下推支持矩阵

| 引擎 | 视图下推 | 子查询下推 | UNION ALL 下推 | OUTER JOIN 下推 | 存储层下推 |
|------|---------|-----------|---------------|----------------|----------|
| PostgreSQL | 是 | 是 | 是 | 部分 | FDW 协议 |
| MySQL | 是（8.0+） | 是（8.0+） | 是 | 部分 | InnoDB ICP |
| Oracle | 是 | 是 | 是 | 是 | -- |
| SQL Server | 是 | 是 | 是 | 是 | columnstore segment |
| DB2 | 是 | 是 | 是 | 是 | -- |
| Snowflake | 是 | 是 | 是 | 是 | micro-partition |
| BigQuery | 是 | 是 | 是 | 是 | partition / cluster |
| Redshift | 是 | 是 | 是 | 是 | zone map |
| Trino | 是 | 是 | 是 | 是 | 是（连接器） |
| Spark SQL | 是 | 是 | 是 | 是 | 是（数据源 API） |
| ClickHouse | 是 | 部分 | 是 | 部分 | 跳数索引 |
| DuckDB | 是 | 是 | 是 | 是 | parquet/arrow |
| CockroachDB | 是 | 是 | 是 | 是 | KV 层 |
| TiDB | 是 | 是 | 是 | 是 | TiKV coprocessor |

### Index Condition Pushdown（ICP）

MySQL InnoDB 的 ICP（5.6+）是一种特殊的下推：把次级索引上无法 seek 但可以判断的谓词推到存储引擎，避免在执行器层做回表扫描后再过滤：

```sql
-- 索引：(last_name, first_name)
SELECT * FROM employees
WHERE last_name LIKE 'S%' AND first_name LIKE 'J%';

-- 不开启 ICP：last_name LIKE 'S%' seek，回表后再过滤 first_name
-- 开启 ICP（默认）：first_name 也下推到 InnoDB 层，在索引上判断

-- EXPLAIN 中 Extra 列显示 'Using index condition' 即为 ICP 生效
EXPLAIN SELECT * FROM employees WHERE last_name LIKE 'S%' AND first_name LIKE 'J%';
```

### 跨连接器下推（Trino / Presto / Spark）

```sql
-- Trino 把谓词推到 PostgreSQL 连接器
SELECT * FROM postgres.public.orders WHERE order_date = DATE '2024-04-01';
-- Trino 把 order_date = DATE '2024-04-01' 翻译为 PG 的 SQL 推下去

-- 但函数包裹会阻止下推
SELECT * FROM postgres.public.orders WHERE EXTRACT(MONTH FROM order_date) = 4;
-- Trino 可能拉取所有数据后再过滤（取决于连接器能力）

-- Spark JDBC 类似，pushedFilters 选项可以查看推下去的过滤
```

## SARG 杀手模式（SARG-Killing Patterns）大全

### 1. 函数包裹列

```sql
-- 杀 SARG
WHERE UPPER(name) = 'ALICE'
WHERE LOWER(email) = 'alice@example.com'
WHERE LENGTH(code) = 5
WHERE TRIM(name) = 'Alice'
WHERE REPLACE(phone, '-', '') = '12345678'
WHERE CONCAT(first, last) = 'AliceSmith'
WHERE ABS(amount) > 100
WHERE ROUND(price, 2) = 9.99

-- 修正：函数索引
CREATE INDEX users_lower_email_idx ON users ((LOWER(email)));

-- 修正：写时归一化
ALTER TABLE users ADD COLUMN email_normalized VARCHAR(255);
UPDATE users SET email_normalized = LOWER(TRIM(email));
CREATE INDEX users_email_normalized_idx ON users (email_normalized);
```

### 2. 时间函数

```sql
-- 杀 SARG
WHERE DATE(created_at) = '2024-04-01'
WHERE YEAR(birth_date) = 1990
WHERE MONTH(created_at) = 4
WHERE EXTRACT(YEAR FROM ts) = 2024
WHERE TO_CHAR(dt, 'YYYY-MM') = '2024-04'

-- 修正：等价范围（最重要！）
WHERE created_at >= '2024-04-01' AND created_at < '2024-04-02'
WHERE birth_date >= '1990-01-01' AND birth_date < '1991-01-01'
WHERE created_at >= '2024-04-01' AND created_at < '2024-05-01'

-- 修正：函数索引
CREATE INDEX events_date_idx ON events ((DATE(created_at)));
CREATE INDEX events_year_idx ON events ((EXTRACT(YEAR FROM ts)));
```

### 3. 算术运算

```sql
-- 杀 SARG
WHERE col + 1 = 100
WHERE col * 2 > 50
WHERE col / 100 = 5
WHERE col - other_col = 10  -- 也无法 seek 单列索引

-- 修正：移项
WHERE col = 99
WHERE col > 25
WHERE col = 500
-- 第四种需要重写为 col = other_col + 10

-- 注意：DBA 经常用 col + 0 故意"杀 SARG" 强制全扫描
WHERE col + 0 = 5  -- 故意不走索引（用于强制查询计划）
```

### 4. 字符串操作

```sql
-- 杀 SARG
WHERE SUBSTR(code, 1, 3) = 'ABC'
WHERE LEFT(code, 3) = 'ABC'
WHERE name || '_suffix' = 'Alice_suffix'

-- 修正：使用 LIKE 前缀
WHERE code LIKE 'ABC%'    -- 当且仅当固定长度时等价
WHERE name = 'Alice'      -- 字符串拼接的情况通常可以化简
```

### 5. NULL 处理函数

```sql
-- 杀 SARG
WHERE COALESCE(col, 0) > 10
WHERE NVL(col, 0) > 10
WHERE ISNULL(col, 0) > 10
WHERE IFNULL(col, 0) > 10

-- 修正：拆分为 OR
WHERE col > 10 OR (col IS NULL AND 0 > 10)
-- 第二个分支为常量 false，简化为：
WHERE col > 10
```

### 6. 隐式类型转换

```sql
-- 表 user_id 是 VARCHAR，杀 SARG
WHERE user_id = 12345

-- 修正：使用字面量字符串
WHERE user_id = '12345'

-- 表 created_at 是 DATE，杀 SARG（部分引擎）
WHERE created_at = '2024-04-01 00:00:00'

-- 修正：保持类型一致
WHERE created_at = DATE '2024-04-01'
```

### 7. OR 条件跨多列

```sql
-- 单一索引无法 seek（除非用 index merge / OR-to-UNION）
WHERE col1 = 1 OR col2 = 2

-- 修正：UNION ALL（如果需要去重用 UNION）
SELECT * FROM t WHERE col1 = 1
UNION ALL
SELECT * FROM t WHERE col2 = 2 AND col1 != 1;

-- 修正：覆盖式复合索引（仅适用部分场景）
CREATE INDEX idx_col1_col2 ON t (col1, col2);
-- 但这个索引依然无法直接 seek "col1 = 1 OR col2 = 2"

-- MySQL 的 index_merge 优化能合并多个单列索引扫描
-- 但效果通常不如等价 UNION
```

### 8. NOT / != / NOT IN

```sql
-- 杀 SARG（无法用索引 seek，只能扫描）
WHERE col != 5
WHERE col NOT IN (1, 2, 3)
WHERE NOT (col = 5)

-- 修正：思考语义
-- 通常 != 和 NOT IN 不应该用索引（覆盖大部分行）
-- 如果列只有少数几个值，可以正面列举：
WHERE col IN (其他所有值)

-- 部分引擎对 NOT NULL 优化
WHERE col IS NOT NULL  -- 部分引擎可以用索引（PG, Oracle）
```

### 9. 子查询缺失关联

```sql
-- 杀 SARG（取决于优化器）
WHERE id IN (SELECT user_id FROM events WHERE event_type = 'login')

-- 优化器通常会改写为 semi join
-- 但如果子查询有复杂表达式或聚合，无法转换：
WHERE id IN (SELECT user_id FROM events GROUP BY user_id HAVING COUNT(*) > 10)

-- 修正：物化子查询
WITH active_users AS (
    SELECT user_id FROM events GROUP BY user_id HAVING COUNT(*) > 10
)
SELECT * FROM users u JOIN active_users a ON u.id = a.user_id;
```

### 10. 集合运算前的过滤

```sql
-- 杀 SARG（部分引擎）
SELECT * FROM (
    SELECT id, name FROM users
    UNION ALL
    SELECT id, name FROM archived_users
) t WHERE id = 12345;

-- 现代优化器会自动下推（见前面的"下推支持矩阵"）
-- 但部分老引擎或受限制的视图需要显式改写：
SELECT id, name FROM users WHERE id = 12345
UNION ALL
SELECT id, name FROM archived_users WHERE id = 12345;
```

## 重写非 SARG 谓词的实战手册

### 时间过滤的等价范围改写

最常见也最重要的重写。把"年/月/日截取"换成范围条件：

```sql
-- 改写前（杀 SARG）
SELECT * FROM orders WHERE YEAR(order_date) = 2024;

-- 改写后（SARGable）
SELECT * FROM orders
WHERE order_date >= '2024-01-01'
  AND order_date < '2025-01-01';

-- 注意闭/开区间：始用 >=（包含），止用 <（不包含），避免边界问题

-- 跨多个月份：
SELECT * FROM orders WHERE MONTH(order_date) IN (4, 5, 6) AND YEAR(order_date) = 2024;
-- 改写为：
SELECT * FROM orders
WHERE order_date >= '2024-04-01' AND order_date < '2024-07-01';

-- 时区注意：如果列是 timestamptz 而字面量是 date，引擎可能做时区转换
-- PostgreSQL: WHERE ts_col >= '2024-04-01'::timestamptz AT TIME ZONE 'Asia/Shanghai'
```

### 大小写不敏感查询

```sql
-- 改写前（杀 SARG）
SELECT * FROM users WHERE LOWER(email) = 'alice@example.com';

-- 方案 A：函数索引
CREATE INDEX users_lower_email_idx ON users ((LOWER(email)));

-- 方案 B：写时归一化（PostgreSQL CITEXT 扩展）
CREATE EXTENSION citext;
ALTER TABLE users ALTER COLUMN email TYPE CITEXT;
SELECT * FROM users WHERE email = 'alice@example.com';  -- 自动大小写不敏感

-- 方案 C：MySQL 的 collation
-- 默认 utf8mb4_general_ci 已经是大小写不敏感的：
SELECT * FROM users WHERE email = 'alice@example.com';  -- 不区分大小写

-- 方案 D：重复双谓词（仅适用少数情况）
SELECT * FROM users WHERE email = 'alice@example.com' OR email = 'ALICE@EXAMPLE.COM';
```

### LIKE 模式优化

```sql
-- 后缀匹配（杀 SARG）
WHERE name LIKE '%Smith';

-- 解决方案 1：反向列 + 索引
ALTER TABLE users ADD COLUMN name_reversed VARCHAR(255)
    GENERATED ALWAYS AS (REVERSE(name)) STORED;
CREATE INDEX users_name_reversed_idx ON users (name_reversed);
SELECT * FROM users WHERE name_reversed LIKE 'htimS%';

-- 解决方案 2：trigram 索引（PG 的 pg_trgm 扩展）
CREATE EXTENSION pg_trgm;
CREATE INDEX users_name_trgm_idx ON users USING gin (name gin_trgm_ops);
SELECT * FROM users WHERE name LIKE '%Smith%';  -- 可以用 trigram 索引

-- 解决方案 3：全文索引
-- MySQL: FULLTEXT INDEX
-- PostgreSQL: tsvector + GIN
-- ClickHouse: ngrambf_v1
```

### 隐式 cast 的预防

```sql
-- 数据建模时统一类型
-- 避免：
CREATE TABLE orders (
    id BIGINT,
    user_id VARCHAR(32)  -- 用户表的 id 是 BIGINT，但这里用 VARCHAR
);
-- 这样写 join 时会触发隐式 cast：
SELECT * FROM orders o JOIN users u ON o.user_id = u.id;
-- 隐式 CAST(o.user_id AS BIGINT)，杀 SARG

-- 推荐：统一类型，必要时用 CAST 字面量而非列
SELECT * FROM orders WHERE user_id = '12345';  -- 字面量做 cast，列保持原值
```

## 引擎特定的 SARG 杀手陷阱

### MySQL 的字符串 → 数字隐式 cast

```sql
-- t.code 是 VARCHAR，索引 idx_code 在 code 上
SELECT * FROM t WHERE code = 100;
-- MySQL 5.x：列被隐式转换为数字，杀 SARG
-- MySQL 8.0+：部分情况优化器会反向推断

-- 推荐写法
SELECT * FROM t WHERE code = '100';
```

### Oracle 的 NVL 与 NULL 处理

```sql
-- 杀 SARG
SELECT * FROM employees WHERE NVL(department_id, -1) = 10;

-- 改写
SELECT * FROM employees WHERE department_id = 10;
-- 显式处理 NULL 仅在需要时
```

### SQL Server 的 ISNUMERIC / ISDATE

```sql
-- 杀 SARG
SELECT * FROM logs WHERE ISDATE(log_date_str) = 1;

-- 改写：保证写入时类型正确，避免运行时验证
ALTER TABLE logs ADD log_date DATE;
UPDATE logs SET log_date = TRY_CAST(log_date_str AS DATE);
CREATE INDEX logs_date_idx ON logs (log_date);
```

### PostgreSQL 的 IMMUTABLE 标记

```sql
-- 不工作（NOW() 不是 IMMUTABLE）：
CREATE INDEX events_recent_idx ON events ((created_at > NOW() - INTERVAL '7 days'));
-- ERROR: functions in index expression must be marked IMMUTABLE

-- 改写为部分索引 + 定期重建
CREATE INDEX events_recent_idx ON events (created_at)
WHERE created_at > '2024-04-22';  -- 字面量
-- 或用普通索引：
CREATE INDEX events_created_idx ON events (created_at);
SELECT * FROM events WHERE created_at > NOW() - INTERVAL '7 days';
```

### MySQL InnoDB 的字符集 collation

```sql
-- t.name COLLATE utf8mb4_general_ci，索引 idx_name
SELECT * FROM t WHERE name = _utf8mb4'Alice' COLLATE utf8mb4_bin;
-- collation 不一致会触发隐式转换，杀 SARG

-- 推荐：保持字面量的 collation 与列一致（默认即可）
```

### Snowflake 的查询压缩与 SARG

```sql
-- Snowflake 默认会做表达式 simplification
-- 但对函数包裹列仍然无法触发 micro-partition pruning
SELECT * FROM events WHERE DATE_TRUNC('day', event_time) = '2024-04-01';
-- 改写：
SELECT * FROM events WHERE event_time >= '2024-04-01' AND event_time < '2024-04-02';
```

## EXPLAIN：识别 SARG 是否生效

```sql
-- PostgreSQL
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM users WHERE lower(email) = 'a@b.com';
-- 看 "Index Cond:" 还是 "Filter:"
-- Index Cond: (lower(email) = 'a@b.com'::text)         <- SARG 生效
-- Seq Scan + Filter: (lower(email) = 'a@b.com')         <- SARG 失效

-- MySQL
EXPLAIN SELECT * FROM users WHERE LOWER(email) = 'a@b.com';
-- 看 type 列：
-- 'ref' / 'range' / 'eq_ref' / 'const': SARG 生效
-- 'ALL' (全表) / 'index' (索引全扫描): SARG 失效
-- Extra 列 'Using where' + type ALL: 残余谓词

-- Oracle
EXPLAIN PLAN FOR SELECT * FROM employees WHERE UPPER(last_name) = 'SMITH';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- 看 access_predicates / filter_predicates：
-- access("UPPER(LAST_NAME)" = 'SMITH')                   <- SARG 生效（函数索引）
-- filter("UPPER(LAST_NAME)" = 'SMITH')                   <- SARG 失效

-- SQL Server
SET SHOWPLAN_XML ON;
SELECT * FROM Employees WHERE UPPER(LastName) = 'SMITH';
SET SHOWPLAN_XML OFF;
-- 看 SeekPredicateNew (Index Seek) 还是 IndexScan + Predicate

-- DuckDB
EXPLAIN SELECT * FROM users WHERE lower(email) = 'a@b.com';
-- 看是否出现 INDEX_SCAN（带函数索引）

-- Trino
EXPLAIN (TYPE DISTRIBUTED) SELECT * FROM hive.db.events WHERE date = '2024-04-01';
-- 看 ScanFilterProject 中的 filterPredicate 与 layoutString
-- layoutString 列出了下推到连接器的过滤条件
```

## 复合索引的最左前缀规则与 SARG

复合索引的"最左前缀"也属于 SARG 范畴：

```sql
-- 索引 (a, b, c)
WHERE a = 1                       -- SARG，使用 a
WHERE a = 1 AND b = 2             -- SARG，使用 (a, b)
WHERE a = 1 AND b = 2 AND c = 3   -- SARG，使用 (a, b, c)
WHERE a = 1 AND c = 3             -- 部分 SARG，使用 a，c 作为残余
WHERE b = 2 AND c = 3             -- 非 SARG（缺最左 a）
WHERE a = 1 AND b > 0 AND c = 3   -- 部分 SARG（b 是范围后 c 不能 seek）
WHERE a IN (1,2,3) AND b = 5      -- SARG（IN 等同于多次 = 跳跃 seek）
```

PostgreSQL / MySQL / Oracle 的复合索引最左前缀规则基本一致。SQL Server 的"index seek + key lookup"也遵循同样的逻辑。

## 列存与 zone-map / 跳数索引下的 SARG

列存引擎没有 B-tree 索引，但 zone-map / cluster / partition / micro-partition 提供了类似的 SARG 机制：

```sql
-- Snowflake micro-partition (16MB)
-- 自动收集每列的 min, max, distinct count
SELECT * FROM events WHERE event_date >= '2024-04-01';
-- min/max 谓词可裁剪 partition

-- BigQuery 分区表
CREATE TABLE events PARTITION BY DATE(event_time)
CLUSTER BY user_id, country;

SELECT * FROM events WHERE event_time = '2024-04-01';      -- 分区裁剪
SELECT * FROM events WHERE user_id = 12345;                -- cluster 裁剪
SELECT * FROM events WHERE EXTRACT(MONTH FROM event_time) = 4;  -- 函数包裹，无法裁剪

-- ClickHouse 跳数索引
SELECT * FROM events WHERE event_type = 'click';
-- bloom filter 跳过整个 granule

-- DuckDB / Parquet row group statistics
SELECT * FROM read_parquet('events.parquet') WHERE date = '2024-04-01';
-- 利用 row group min/max
```

列存的 SARG 规则：
1. 函数包裹依然破坏 SARG
2. 隐式 cast 同样杀 SARG（但列存的"cast on literal"通常会被优化）
3. 复合 partition 同样有最左前缀规则
4. zone-map 是粗粒度的（分区或行组级），比 B-tree 索引精度低

## 与查询重写、选择性估计的交互

参见 [查询重写规则 (Query Rewrite Rules)](query-rewrite-rules.md) 和 [选择性估计 (Selectivity Estimation)](selectivity-estimation.md)。

### 查询重写阶段的 SARG 改善

部分非 SARG 谓词可以通过查询重写自动转换为 SARG：

```sql
-- 优化器自动改写
WHERE col + 1 = 100   →   WHERE col = 99           -- 常量传播
WHERE col BETWEEN 1 AND 1   →   WHERE col = 1     -- BETWEEN 化简
WHERE col >= 1 AND col <= 1   →   WHERE col = 1   -- 范围合并
```

但函数包裹的列在大多数引擎中不能自动改写：优化器无法保证 `f(col) = v` 等价于 `col = f^-1(v)`，因为函数可能不是单调或可逆。Oracle 在 12c+ 提供 `OPTIMIZER_DYNAMIC_SAMPLING` 时尝试通过抽样估算非 SARG 谓词的选择性，但仍然无法变 SARG。

### 选择性估计与 SARG

非 SARG 谓词的选择性估计往往不准：优化器没有函数 `f(col)` 的直方图，只能用默认值（如 1%）。这进一步导致计划错误：

```sql
-- 假设 t 有 100 万行，col 唯一
SELECT * FROM t WHERE UPPER(name) = 'X';
-- 优化器估计 1% × 1M = 10000 行（默认非 SARG 选择性）
-- 实际可能只有 1 行
-- 结果：错误估计可能选择了哈希连接而非嵌套循环
```

修正：函数索引会附带统计信息收集，让优化器准确估计选择性。

## SARG 与并行查询、索引下推

### 并行扫描中的 SARG

并行扫描（parallel scan）依然遵循 SARG 规则：

```
非 SARG: 全表扫描 + 并行 + Filter
SARG:    Index Seek + 并行 + 取窄范围
```

并行通常不能弥补 SARG 失效带来的代价差。一个被并行 16 路加速的全表扫描，依然慢于一个单线程的 index seek 100 倍。

### 索引覆盖（Covering Index）与 SARG

```sql
-- 索引 (last_name) INCLUDE (first_name, salary)
SELECT first_name, salary FROM employees WHERE last_name = 'Smith';
-- 完全在索引上完成（index-only scan），不回表
```

覆盖索引依赖 SARG 找到候选行；INCLUDE 列只是把"需要的非 key 列"打包进叶节点。如果 SARG 失效，覆盖索引也无效。

## 设计争议与历史决策

### 为什么 MySQL 直到 2018 年才支持函数索引？

MySQL 长期依靠 InnoDB 的简单 B-tree 模型，而函数索引需要：
1. 优化器能够匹配查询表达式与索引表达式（需要表达式规范化、确定性证明）
2. 写入时计算并维护表达式值
3. 统计信息收集要扩展到表达式

Oracle 1999 年就有了，PostgreSQL 2003 年跟进，MySQL 拖到 2018 年——主要是因为 8.0 之前的优化器极简、没有规范化的查询树。8.0 引入新的优化器框架（histograms、索引提示改革、CTE 等）后才补齐。

### 为什么 SQL Server 没有真正的函数索引？

SQL Server 走"计算列 + 索引"路线，而非函数索引。两者实质等价，但用户体验有差异：
- 计算列对存储有副作用（PERSISTED 列占空间、维护成本）
- 函数索引对表结构无侵入

SQL Server 团队认为 PERSISTED computed column 在执行计划匹配时更易于实现，且与 SCHEMABINDING、UDT 等特性一致性更好。

### 为什么 PostgreSQL IMMUTABLE 函数限制如此严格？

PostgreSQL 要求索引表达式 IMMUTABLE，即"输入相同永远输出相同"。这排除了：
- `NOW()`, `CURRENT_TIMESTAMP`：随时间变化
- `RANDOM()`：每次调用结果不同
- 涉及时区的 `cast(timestamptz AS date)`：依赖会话时区
- 调用了 `STABLE` 或 `VOLATILE` 函数的复合表达式

理由：索引值在写入时计算并存储，读取时不重新计算。非 IMMUTABLE 的表达式会导致索引值与查询时计算的值不一致，破坏正确性。

### LIKE 'prefix%' 是否一定 SARGable？

不一定！取决于列的 collation：
- C locale 或 binary collation：自然按字典序排序，前缀范围 seek 直接可用
- 区域 collation（如 zh_CN.UTF-8）：排序规则复杂，前缀语义可能不等同字典序
- PostgreSQL 解决方案：`text_pattern_ops` 索引按字节比较，专门处理 LIKE 前缀

```sql
-- PostgreSQL 在非 C locale 下需要：
CREATE INDEX users_email_pattern_idx ON users (email text_pattern_ops);
-- 这个索引专门用于 LIKE 'prefix%'
-- 普通 = 查询仍可用普通索引
```

### NULL 与 SARG

`IS NULL` 是否 SARGable 因引擎而异：
- PostgreSQL：是（B-tree 索引存储 NULL，可以 seek）
- Oracle：否（B-tree 索引不存储 NULL，需要 bitmap index 或函数索引 `((CASE WHEN col IS NULL THEN 1 END))`）
- SQL Server：是（B-tree 索引存储 NULL）
- MySQL InnoDB：是

### 为什么有时 DBA 故意"杀 SARG"？

```sql
WHERE col + 0 = 5    -- 故意非 SARG
WHERE id || '' = '5' -- 故意非 SARG
```

用例：
1. 强制全表扫描（统计信息错误时绕过坏计划）
2. 防止索引被锁定或竞争
3. 验证全表扫描的正确性（与索引扫描对比）

这是反模式，但在生产应急时偶尔出现。现代引擎更推荐用 `optimizer_hint` 而非这种 hack。

## 引擎选型建议

| 场景 | 推荐方案 | 原因 |
|------|---------|------|
| 大小写不敏感搜索 | PG `CITEXT` 或 MySQL `_ci` collation | 写时归一化，零运行时函数 |
| 灵活函数索引 | PostgreSQL / Oracle | 表达式索引最完整，函数最灵活 |
| 计算列模型 | SQL Server / DB2 | PERSISTED 列对优化器更友好 |
| 子串匹配 | PG `pg_trgm` / ClickHouse `ngrambf_v1` | 专门处理 `LIKE '%abc%'` |
| 时序表 | ClickHouse / TimescaleDB | 排序键 + 物化日期列 |
| JSON 谓词 | MySQL 8 / PG GIN / Oracle JSON_TABLE 索引 | 函数索引提取 JSON 字段 |
| 纯列存分析 | Snowflake / BigQuery | micro-partition + cluster 自动 SARG |
| 跨引擎下推 | Trino + 函数索引 | Trino 翻译谓词到底层连接器 |

## 对引擎开发者的实现建议

### 1. SARG 识别算子

```
fn classify_predicate(expr: &Expr, table_columns: &[Column]) -> SargClass {
    match expr {
        // column op constant
        Expr::Op(Op::Eq | Op::Lt | Op::Gt | Op::Le | Op::Ge,
                lhs @ Expr::Column(_), rhs) if rhs.is_constant() =>
            SargClass::IndexSarg,

        // column BETWEEN const AND const
        Expr::Between(col, low, high) if col.is_column() && low.is_constant() && high.is_constant() =>
            SargClass::IndexSarg,

        // column IN (const_list)
        Expr::In(col, list) if col.is_column() && list.iter().all(|e| e.is_constant()) =>
            SargClass::IndexSarg,

        // f(column) op constant -- 检查表达式索引匹配
        Expr::Op(_, Expr::Function(f, args), rhs)
            if rhs.is_constant() &&
               has_index_on_expression(table_columns, &Expr::Function(f.clone(), args.clone())) =>
            SargClass::IndexSarg,

        // f(column) op constant -- 无表达式索引
        Expr::Op(_, Expr::Function(_, _), _) =>
            SargClass::Residual,

        // column op column (same table)
        Expr::Op(_, lhs @ Expr::Column(_), rhs @ Expr::Column(_)) =>
            SargClass::DataSarg,  // 弱 SARG，可在存储层过滤

        // LIKE 'prefix%'
        Expr::Like(col, Expr::Constant(s)) if has_literal_prefix(s) =>
            SargClass::IndexSarg,

        _ => SargClass::Residual,
    }
}
```

### 2. SARG 谓词转换为索引范围

```
fn predicate_to_range(pred: &Expr, index: &Index) -> Option<KeyRange> {
    match pred {
        // col = v -> [v, v]
        Eq(col, v) if matches_index_key(col, index) =>
            Some(KeyRange { start: Bound::Inclusive(v), end: Bound::Inclusive(v) }),

        // col > v -> (v, +inf]
        Gt(col, v) if matches_index_key(col, index) =>
            Some(KeyRange { start: Bound::Exclusive(v), end: Bound::Unbounded }),

        // col BETWEEN a AND b -> [a, b]
        Between(col, a, b) if matches_index_key(col, index) =>
            Some(KeyRange { start: Bound::Inclusive(a), end: Bound::Inclusive(b) }),

        // col IN (v1, v2, ...) -> 多个点查询（jump scan）
        In(col, list) if matches_index_key(col, index) =>
            Some(KeyRange::Multiple(list.iter().map(|v|
                KeyRange { start: Bound::Inclusive(v), end: Bound::Inclusive(v) }
            ).collect())),

        // LIKE 'prefix%' -> [prefix, prefix++]
        Like(col, s) if matches_index_key(col, index) && has_literal_prefix(s) => {
            let (prefix, _) = split_at_wildcard(s);
            Some(KeyRange {
                start: Bound::Inclusive(prefix),
                end: Bound::Exclusive(next_string(prefix)),
            })
        },

        _ => None,
    }
}
```

### 3. 表达式索引的匹配规范化

表达式索引匹配的核心是**规范化**：

```
// 输入：用户写的 WHERE LOWER(email) = 'a@b.com'
// 索引：CREATE INDEX i ON users (LOWER(email))

fn match_index_expression(query_expr: &Expr, index_expr: &Expr) -> bool {
    let query_canon = normalize(query_expr);
    let index_canon = normalize(index_expr);
    structurally_equal(&query_canon, &index_canon)
}

fn normalize(expr: &Expr) -> Expr {
    match expr {
        // 函数名小写
        Function(name, args) => Function(name.to_lowercase(), args.iter().map(normalize).collect()),
        // 数值常量统一为同一类型
        Const(c) => Const(unify_const_type(c)),
        // 操作符规范（如 a + b vs a - (-b)）
        Op(Op::Add, lhs, rhs) if rhs.is_negative() =>
            Op::Sub(normalize(lhs), normalize(&negate(rhs))),
        ...
    }
}
```

### 4. 隐式 cast 的处理

```
// 检查谓词中的 cast 是否在列侧（杀 SARG）还是在常量侧（保留 SARG）
fn detect_cast_on_column(expr: &Expr) -> bool {
    match expr {
        // CAST(col AS X) op v 杀 SARG
        Op(_, Cast(_, col @ Column(_)), Const(_)) => true,
        // col op CAST(v AS X) 保留 SARG
        Op(_, col @ Column(_), Cast(_, Const(_))) => false,
        ...
    }
}

// 优化器试图把 cast 从列侧移到常量侧
// 例如：CAST(varchar_col AS INT) = 5
//   -> varchar_col = CAST(5 AS VARCHAR) = '5'
// 但仅在类型转换是双向无损的情况下安全
fn try_invert_cast(expr: &Expr) -> Option<Expr> {
    match expr {
        Op(Op::Eq, Cast(target_ty, col @ Column(_)), Const(v))
            if is_lossless_invertible(col.data_type(), target_ty) =>
        {
            Some(Op::Eq(col.clone(), Cast(col.data_type().clone(), Const(v.clone()))))
        },
        _ => None,
    }
}
```

### 5. SARG 与代价估计

```
fn estimate_cardinality(pred: &Expr, table_stats: &TableStats) -> f64 {
    match classify_predicate(pred, &table_stats.columns) {
        SargClass::IndexSarg => {
            // 用 histogram 估计选择性
            estimate_with_histogram(pred, table_stats)
        },
        SargClass::DataSarg => {
            // 同样用 histogram，但 I/O 代价更高（全表扫描）
            estimate_with_histogram(pred, table_stats)
        },
        SargClass::Residual => {
            // 默认选择性（无 histogram）
            table_stats.row_count as f64 * 0.01
        },
    }
}
```

### 6. 跨引擎下推接口

```
// 数据源 API（Spark / Trino / Presto 通用模式）
trait DataSource {
    fn supported_filters(&self) -> Vec<FilterKind>;

    fn pushed_filters(&self) -> Vec<Expr>;

    fn build_scan(&self, filters: Vec<Expr>) -> Box<dyn Scan>;
}

// 优化器在规划时检查每个谓词
fn push_predicates_to_source(plan: &mut Plan, ds: &dyn DataSource) {
    let mut pushed = vec![];
    let mut residual = vec![];
    for pred in plan.predicates() {
        if ds.supported_filters().contains(&kind_of(pred)) {
            pushed.push(pred);
        } else {
            residual.push(pred);
        }
    }
    plan.set_pushed(pushed);
    plan.set_residual(residual);
}
```

### 7. EXPLAIN 输出的清晰度

让用户能识别 SARG 是否生效是 EXPLAIN 设计的核心目标：

```
PostgreSQL 风格：
  Index Cond: (lower(email) = 'a@b.com'::text)    <- SARG 生效（index seek）
  Filter: (extract(year from created_at) = 2024)  <- 残余谓词（非 SARG）

SQL Server 风格：
  [Seek Predicate]: (...)      <- SARG 生效
  [Predicate]: (...)            <- 残余谓词

Oracle 风格：
  access("UPPER(LAST_NAME)" = 'SMITH')   <- SARG 生效
  filter("UPPER(LAST_NAME)" = 'SMITH')   <- 残余谓词
```

引擎实现者应当：
- 区分 access predicate 和 filter predicate
- 在文本计划中明确标注 "Index Seek" / "Index Scan" / "Seq Scan + Filter"
- 在 JSON / XML 计划中区分 `seek_predicate` / `index_predicate` / `filter_predicate`

### 8. 与查询重写的协同

SARG 识别应当在查询重写之后进行：

```
1. Parser → AST
2. 查询重写（constant folding、predicate simplification、view inlining）
3. 此时可能产生新的 SARG（例如 a + 0 -> a）
4. 优化器（access path selection）
5. 物理计划生成
```

例如 `WHERE col + 0 = 5` 在常量折叠后变成 `WHERE col = 5`（部分引擎），从而恢复 SARG。

### 9. 常见的优化器陷阱

1. **多列索引下推顺序**：(a, b, c) 索引上 `WHERE a = 1 AND b > 0 AND c = 3`，c 不能 seek（因为 b 是范围），但可以作为存储层 filter（弱 SARG）。优化器需正确生成 `Index Cond: (a = 1 AND b > 0)` + `Filter: (c = 3)` 而不是把 c 推到 seek 里。

2. **相关子查询的提升**：`WHERE col IN (SELECT ...)` 被优化器提升为 semi join 后，原本的非 SARG 谓词可能变为 SARG。但如果子查询有聚合或 LIMIT，提升不可行，谓词只能在 join 后过滤。

3. **下推到分区**：分区表的分区列上的 SARG 可以触发分区裁剪（partition pruning）。函数包裹分区列会破坏裁剪，但部分引擎对 `DATE_TRUNC` 等"分区函数"做了特例支持。

4. **集合并的下推**：`WHERE id = 5` 应当下推到 UNION ALL 的每个分支：
   ```sql
   SELECT * FROM (SELECT * FROM t1 UNION ALL SELECT * FROM t2) u WHERE id = 5;
   -- 优化为：
   SELECT * FROM t1 WHERE id = 5 UNION ALL SELECT * FROM t2 WHERE id = 5;
   ```

5. **OR 条件的 union 改写**：`WHERE col1 = 1 OR col2 = 2` 可以转换为两个 IndexSeek 的 union（MySQL `index_merge` / SQL Server / PostgreSQL bitmap index scan 都支持）。但 union 改写后必须去重（如果不能保证 disjoint）。

### 10. SARG 的端到端测试

```
测试要点：
- 函数索引 + 函数包裹列：EXPLAIN 必须显示 Index Cond
- 函数索引 + 等价改写：EXPLAIN 应优先选择直接列谓词
- 隐式 cast：列类型 vs 字面量类型不一致时检查计划
- 复合索引最左前缀：每种前缀组合检查 seek 范围
- LIKE 前缀：unicode、转义、%/_ 边界
- NULL 处理：IS NULL / IS NOT NULL / NULL 作为字面量
- 分区表：分区列的 SARG 是否触发裁剪
- 表达式索引的匹配规范化（同一表达式的不同写法）
```

## 总结对比矩阵

### 核心能力对比

| 能力 | PostgreSQL | MySQL 8 | Oracle | SQL Server | DB2 | Snowflake | ClickHouse | DuckDB |
|------|-----------|---------|--------|-----------|-----|-----------|-----------|--------|
| 函数索引 | 是 (7.4+) | 是 (8.0.13+) | 是 (8i+) | 计算列 | 是 | -- | 物化列 | 是 |
| 计算列索引 | -- | 是 | 虚拟列 | 是 (2000+) | 是 | -- | -- | -- |
| LIKE 前缀 SARG | text_pattern_ops | 是 | 是 | 是 | 是 | 部分 | 是 | 是 |
| LIKE 后缀 SARG | trigram | -- | reverse 索引 | -- | -- | -- | ngram | -- |
| 隐式 cast 优化 | 严格 | 8.0+ 部分 | 部分 | 是 | 部分 | 自动 | 是 | 是 |
| ICP / 残余下推 | 是 | InnoDB ICP | 是 | 是 | 是 | 是 | 是 | 是 |
| 跨连接器下推 | FDW | -- | gateway | linked server | federated | -- | -- | parquet |
| 函数索引统计 | 是 | 是 | 是 | 是（计算列） | 是 | -- | -- | -- |

### 实战决策表

| 问题 | 解法 |
|------|------|
| 函数包裹列查询 | 创建函数/表达式/计算列索引 |
| 时间字段 YEAR/DATE 比较 | 改写为范围（最有价值的优化） |
| 大小写不敏感 | 函数索引或 case-insensitive collation |
| 子串包含查询 | trigram / ngram / 全文索引 |
| OR 跨多列 | UNION ALL 改写或 index_merge |
| NOT / != / NOT IN | 通常不应使用索引（选择性低） |
| 隐式 cast | 数据建模层面统一类型 |
| 跨表函数 | 物化视图或写时归一化 |
| 多列复合查询 | 复合索引 + 最左前缀规则 |
| 分区表查询 | 保持分区列 SARGable |

## 关键发现

1. **SARGable 概念有 50 年历史**：从 IBM System R (1979) 到现代云数仓，三级模型（IndexSarg / DataSarg / Residual）始终未变，只是术语在不同引擎中略有差异。

2. **函数索引是逃生出口**：所有支持 OLTP 的数据库都提供"函数索引"或等价的"计算列 + 索引"机制，让 `f(col) = v` 可以重新变 SARG。Oracle (1999) > PostgreSQL (2003) > SQLite (2015) > MySQL (2018) 是主要引擎的实现先后顺序。

3. **MySQL 是迟到者**：尽管市场份额最大，MySQL 直到 8.0.13 (2018) 才原生支持函数索引，比 Oracle 晚 19 年。这与 MySQL 长期优化器极简的历史决策相关。

4. **SQL Server 走了不同的路**：用持久化计算列 + 索引代替函数索引，从优化器视角等价但用户体验略繁琐。

5. **隐式 cast 是隐藏杀手**：列类型与字面量不一致引发的隐式 cast 是最常见的"看不见的"SARG 失效原因，尤其是 `VARCHAR id = 整数字面量` 这种模式。

6. **LIKE 前缀的 collation 陷阱**：`LIKE 'abc%'` 在非 C locale 下可能依然非 SARG，需要专门的 `text_pattern_ops` 或类似机制。

7. **时间过滤的范围改写是最高 ROI 的优化**：把 `YEAR(col) = 2024` 改成 `col >= '2024-01-01' AND col < '2025-01-01'` 通常能将查询从 O(N) 降到 O(log N)，是 DBA 培训的第一课。

8. **列存的 SARG 退化为 partition pruning**：Snowflake / BigQuery / Redshift 的"SARG"等价于"能否触发 micro-partition / cluster / zone-map 裁剪"。规则与 B-tree 索引的 SARG 基本一致：函数包裹依然破坏裁剪。

9. **ClickHouse 走了独立的路**：用跳数索引（minmax / bloom / ngram）取代传统 B-tree，让一些传统非 SARG 模式（如 `LIKE '%abc%'`）也能有效率裁剪。

10. **跨引擎下推是分布式优化器的核心**：Trino / Spark / Presto 把 SARG 谓词翻译为底层连接器（PostgreSQL / Hive / S3 + Parquet）的原生过滤语法，是云时代 federated query 性能的关键。

11. **EXPLAIN 是诊断 SARG 的唯一可靠方式**：access predicate vs filter predicate、Index Cond vs Filter、Seek Predicate vs Predicate——每个引擎都有独立的术语，但本质都是区分"驱动 seek"与"扫描后过滤"。

12. **优化器自动改写有限度**：常量折叠、BETWEEN 化简能恢复部分 SARG，但函数包裹列的反向推导（如 `f(col) = v` → `col = f^-1(v)`）需要函数可逆 + 单调，绝大多数引擎不会做。

## 参考资料

- IBM System R: Selinger et al., "Access Path Selection in a Relational Database Management System", SIGMOD 1979
- PostgreSQL: [Indexes on Expressions](https://www.postgresql.org/docs/current/indexes-expressional.html)
- PostgreSQL: [Operator Classes for text_pattern_ops](https://www.postgresql.org/docs/current/indexes-opclass.html)
- MySQL: [Functional Key Parts](https://dev.mysql.com/doc/refman/8.0/en/create-index.html#create-index-functional-key-parts)
- MySQL: [Index Condition Pushdown Optimization](https://dev.mysql.com/doc/refman/8.0/en/index-condition-pushdown-optimization.html)
- Oracle: [Function-Based Indexes](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/indexes-and-index-organized-tables.html)
- SQL Server: [Indexes on Computed Columns](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/indexes-on-computed-columns)
- SQL Server: [Create indexed views](https://learn.microsoft.com/en-us/sql/relational-databases/views/create-indexed-views)
- DB2: [Expression-based indexes](https://www.ibm.com/docs/en/db2/11.5?topic=indexes-expression-based)
- SQLite: [Indexes On Expressions](https://www.sqlite.org/expridx.html)
- ClickHouse: [Data Skipping Indexes](https://clickhouse.com/docs/en/optimize/skipping-indexes)
- Snowflake: [Understanding Snowflake Table Structures](https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions)
- BigQuery: [Partitioned tables](https://cloud.google.com/bigquery/docs/partitioned-tables)
- Trino: [Pushdown](https://trino.io/docs/current/optimizer/pushdown.html)
- Spark SQL: [Data Source V2 Filter Pushdown](https://spark.apache.org/docs/latest/sql-data-sources.html)
- "Use the Index, Luke!" by Markus Winand: <https://use-the-index-luke.com/>
- 相关文章: [查询重写规则](query-rewrite-rules.md)、[选择性估计](selectivity-estimation.md)
