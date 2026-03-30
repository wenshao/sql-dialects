# LIMIT/OFFSET/FETCH 分页语法

SQL 分页是最基础也最容易踩坑的功能之一——五大语法家族、各引擎行为差异、性能陷阱，以及 SQL:2008 标准化之路。

## 五大分页语法家族

SQL 分页经历了从专用语法到标准化的漫长演进，形成了五大语法家族：

| 家族 | 语法 | 起源 | 标准化 |
|------|------|------|--------|
| LIMIT/OFFSET | `LIMIT n OFFSET m` | MySQL 3.x (1990s) | 非标准，事实标准 |
| TOP | `SELECT TOP n ...` | SQL Server 7.0 (1998) | 非标准，微软系 |
| FETCH FIRST/NEXT | `FETCH FIRST n ROWS ONLY` | SQL:2008 | ISO 标准 |
| ROWNUM | `WHERE ROWNUM <= n` | Oracle 7 (1992) | Oracle 独有 |
| ROW_NUMBER() | `ROW_NUMBER() OVER (...)` | SQL:2003 | ISO 标准（窗口函数） |

## 支持矩阵：基本分页语法

| 引擎 | LIMIT n | LIMIT n OFFSET m | TOP n | FETCH FIRST n ROWS | ROWNUM | ROW_NUMBER() |
|------|---------|-------------------|-------|---------------------|--------|--------------|
| MySQL | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ (8.0+) |
| PostgreSQL | ✅ | ✅ | ❌ | ✅ (8.4+) | ❌ | ✅ (8.4+) |
| Oracle | ❌ | ❌ | ❌ | ✅ (12c+) | ✅ | ✅ (9i+) |
| SQL Server | ❌ | ❌ | ✅ | ✅ (2012+) | ❌ | ✅ (2005+) |
| SQLite | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ (3.25+) |
| MariaDB | ✅ | ✅ | ❌ | ✅ (10.6+) | ❌ | ✅ (10.2+) |
| DuckDB | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| ClickHouse | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| Snowflake | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| BigQuery | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| Trino | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| Spark SQL | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| Hive | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ |
| Redshift | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Db2 | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ |
| Teradata | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ |
| Vertica | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| CockroachDB | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| TimescaleDB | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| Greenplum | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| YugabyteDB | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| H2 | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| Derby | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ |
| Firebird | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ |
| SAP HANA | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| Impala | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| Doris | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| StarRocks | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| MaxCompute | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| TiDB | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| OceanBase | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ |
| PolarDB | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| openGauss | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| KingBase | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| DM (达梦) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Databricks | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| Flink SQL | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ |
| Materialize | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |
| ksqlDB | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Hologres | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| Synapse | ❌ | ❌ | ✅ | ✅ | ❌ | ✅ |
| TDengine | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ |
| TDSQL | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |
| Spanner | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ |

## SQL:2008 FETCH FIRST 标准合规性

SQL:2008 引入了 `FETCH FIRST` 作为分页的标准语法。以下矩阵展示各引擎对标准特性的支持：

| 引擎 | FETCH FIRST n ROWS ONLY | OFFSET n ROWS | WITH TIES | PERCENT | FIRST/NEXT 等价 | ROW/ROWS 等价 |
|------|------------------------|---------------|-----------|---------|----------------|--------------|
| PostgreSQL | ✅ (8.4+) | ✅ | ✅ (13+) | ❌ | ✅ | ✅ |
| Oracle | ✅ (12c+) | ✅ | ✅ | ✅ | ✅ | ✅ |
| SQL Server | ✅ (2012+) | ✅ | ✅ (需搭配 OFFSET) | ❌ | ✅ | ✅ |
| Db2 | ✅ (7.1+) | ✅ (9.7+) | ✅ (11.1+) | ✅ (11.1+) | ✅ | ✅ |
| MariaDB | ✅ (10.6+) | ✅ | ✅ (10.6+) | ❌ | ✅ | ✅ |
| DuckDB | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| CockroachDB | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| Trino | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| H2 | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| Firebird | ✅ (3.0+) | ✅ | ❌ | ❌ | ✅ | ✅ |
| Derby | ✅ (10.5+) | ✅ | ❌ | ❌ | ✅ | ✅ |
| Vertica | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| openGauss | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| KingBase | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| MySQL | ❌ | ❌ | ❌ | ❌ | - | - |
| ClickHouse | ❌ | ❌ | ❌ | ❌ | - | - |
| BigQuery | ❌ | ❌ | ❌ | ❌ | - | - |
| Snowflake | ❌ | ❌ | ❌ | ❌ | - | - |
| Spark SQL | ❌ | ❌ | ❌ | ❌ | - | - |

SQL Server 的特殊约束：FETCH 必须搭配 OFFSET（即使是 `OFFSET 0 ROWS`）。

## 各家族语法详解

### 家族 1: LIMIT/OFFSET（事实标准）

最广泛使用的分页语法，起源于 MySQL，被大多数引擎采纳：

```sql
-- 基本语法
SELECT * FROM orders ORDER BY id LIMIT 10;

-- 带 OFFSET
SELECT * FROM orders ORDER BY id LIMIT 10 OFFSET 20;

-- MySQL 独有的逗号语法（OFFSET 在前！容易混淆）
SELECT * FROM orders ORDER BY id LIMIT 20, 10;  -- 等价于 LIMIT 10 OFFSET 20
```

MySQL 逗号语法的参数顺序 `LIMIT offset, count` 与 `LIMIT count OFFSET offset` 相反，是常见的错误来源。建议始终使用 `LIMIT ... OFFSET ...` 形式。

### 家族 2: TOP（微软系）

```sql
-- SQL Server / Synapse
SELECT TOP 10 * FROM orders ORDER BY id;

-- TOP 支持表达式
DECLARE @n INT = 10;
SELECT TOP (@n) * FROM orders ORDER BY id;

-- TOP PERCENT
SELECT TOP 10 PERCENT * FROM orders ORDER BY id;

-- TOP WITH TIES（包含并列值）
SELECT TOP 10 WITH TIES * FROM orders ORDER BY created_at;

-- TOP PERCENT WITH TIES
SELECT TOP 10 PERCENT WITH TIES * FROM orders ORDER BY amount DESC;
```

TOP 的位置在 SELECT 之后、列列表之前，这与其他分页子句在末尾的设计不同。

TOP 在以下引擎中可用：

| 引擎 | TOP n | TOP n PERCENT | TOP n WITH TIES | 括号要求 |
|------|-------|---------------|-----------------|---------|
| SQL Server | ✅ | ✅ | ✅ | 表达式需括号 |
| Synapse | ✅ | ✅ | ✅ | 同 SQL Server |
| Snowflake | ✅ | ❌ | ❌ | 不需要 |
| Redshift | ✅ | ❌ | ❌ | 不需要 |
| Teradata | ✅ | ✅ | ✅ | 不需要 |
| SAP HANA | ✅ | ❌ | ❌ | 不需要 |
| H2 | ✅ | ❌ | ❌ | 不需要 |
| Firebird | ❌ | ❌ | ❌ | - |
| DM (达梦) | ✅ | ✅ | ✅ | 不需要 |

### 家族 3: FETCH FIRST/NEXT（SQL:2008 标准）

```sql
-- 标准语法
SELECT * FROM orders
ORDER BY id
OFFSET 20 ROWS
FETCH NEXT 10 ROWS ONLY;

-- FIRST 和 NEXT 语义完全相同
FETCH FIRST 10 ROWS ONLY;   -- 与下行等价
FETCH NEXT 10 ROWS ONLY;

-- ROW 和 ROWS 语义完全相同
FETCH FIRST 1 ROW ONLY;     -- 单数
FETCH FIRST 10 ROWS ONLY;   -- 复数

-- WITH TIES（包含并列）
SELECT * FROM orders
ORDER BY amount DESC
FETCH FIRST 10 ROWS WITH TIES;

-- PERCENT（百分比截取）
SELECT * FROM orders
ORDER BY amount DESC
FETCH FIRST 10 PERCENT ROWS ONLY;
```

### 家族 4: ROWNUM（Oracle 遗留方案）

```sql
-- Oracle 传统分页（12c 之前唯一选择）
SELECT * FROM (
    SELECT t.*, ROWNUM rn FROM (
        SELECT * FROM orders ORDER BY id
    ) t WHERE ROWNUM <= 30  -- offset + limit
) WHERE rn > 20;            -- offset

-- ROWNUM 的陷阱: WHERE ROWNUM > 1 永远返回空结果
-- 因为第一行的 ROWNUM 始终是 1，被过滤后第二行变成新的第一行
SELECT * FROM orders WHERE ROWNUM > 1;  -- 永远返回 0 行！
```

### 家族 5: ROW_NUMBER()（通用方案）

```sql
-- 所有支持窗口函数的引擎通用
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM orders
) t
WHERE rn BETWEEN 21 AND 30;  -- 第 3 页，每页 10 行
```

## OFFSET 相关行为差异

### OFFSET 不搭配 LIMIT

部分引擎允许只写 OFFSET 不写 LIMIT，返回跳过 N 行后的所有剩余行：

| 引擎 | OFFSET 不搭配 LIMIT | 行为 |
|------|---------------------|------|
| PostgreSQL | ✅ | 跳过 N 行，返回剩余全部 |
| MySQL | ❌ | 语法错误，OFFSET 必须搭配 LIMIT |
| SQLite | ❌ | OFFSET 必须搭配 LIMIT |
| Oracle | ✅ | 仅 FETCH 语法支持 |
| SQL Server | ✅ | 跳过 N 行，返回剩余全部（2012+，需 ORDER BY） |
| DuckDB | ✅ | 跳过 N 行，返回剩余全部 |
| ClickHouse | ❌ | OFFSET 必须搭配 LIMIT |
| Snowflake | ❌ | OFFSET 必须搭配 LIMIT |
| MariaDB | ❌ | 同 MySQL |
| Trino | ✅ | 跳过 N 行，返回剩余全部 |
| BigQuery | ❌ | OFFSET 必须搭配 LIMIT |

MySQL 的变通方案——使用极大值作为 LIMIT：

```sql
-- MySQL: 跳过前 20 行，取剩余所有
SELECT * FROM orders ORDER BY id LIMIT 18446744073709551615 OFFSET 20;
-- 18446744073709551615 = 2^64 - 1 (BIGINT UNSIGNED 最大值)
```

### 负数和零值 LIMIT/OFFSET

| 引擎 | LIMIT 0 | LIMIT 负数 | OFFSET 0 | OFFSET 负数 |
|------|---------|-----------|----------|------------|
| MySQL | ✅ 返回 0 行 | ❌ 错误 | ✅ 无效果 | ❌ 错误 |
| PostgreSQL | ✅ 返回 0 行 | ❌ 错误 | ✅ 无效果 | ❌ 错误 |
| SQLite | ✅ 返回 0 行 | ✅ 等价于无 LIMIT | ✅ 无效果 | ✅ 等价于 0 |
| Oracle (FETCH) | ✅ 返回 0 行 | ❌ 错误 | ✅ 无效果 | ❌ 错误 |
| SQL Server (FETCH) | ✅ 返回 0 行 | ❌ 错误 | ✅ 无效果 | ❌ 错误 |
| DuckDB | ✅ 返回 0 行 | ❌ 错误 | ✅ 无效果 | ❌ 错误 |
| ClickHouse | ✅ 返回 0 行 | ❌ 错误 | ✅ 无效果 | ❌ 错误 |
| Snowflake | ✅ 返回 0 行 | ❌ 错误 | ✅ 无效果 | ❌ 错误 |
| Spark SQL | ✅ 返回 0 行 | ❌ 错误 | ✅ 无效果 | ❌ 错误 |

SQLite 在边界值处理上最为宽松——负数 LIMIT 被解释为"无限制"，负数 OFFSET 被解释为 0。这是 SQLite "尽量不报错"的设计哲学的体现。

### LIMIT 中的变量与参数绑定

| 引擎 | 字面量 | 预处理语句参数 `?` | 变量/表达式 | 子查询 |
|------|--------|-------------------|------------|--------|
| MySQL | ✅ | ✅ (5.6+) | ❌ | ❌ |
| PostgreSQL | ✅ | ✅ | ✅ | ❌ |
| SQLite | ✅ | ✅ | ✅ (表达式) | ✅ (表达式) |
| Oracle (FETCH) | ✅ | ✅ | ✅ | ❌ |
| SQL Server (TOP) | ✅ | ✅ | ✅ (括号内) | ✅ |
| SQL Server (FETCH) | ✅ | ✅ | ✅ | ❌ |
| DuckDB | ✅ | ✅ | ✅ | ❌ |
| ClickHouse | ✅ | ✅ | ❌ | ❌ |
| Snowflake | ✅ | ✅ | ❌ | ❌ |
| Spark SQL | ✅ | ✅ | ❌ | ❌ |

MySQL 的历史遗留问题：早期版本（5.5 及更早）的 LIMIT 不支持预处理语句参数，只能拼接 SQL 字符串，这是 SQL 注入的重灾区。5.6+ 解决了该限制。

```sql
-- SQL Server: TOP 支持子查询（独有能力）
SELECT TOP (SELECT setting_value FROM config WHERE key = 'page_size')
    * FROM orders ORDER BY id;

-- SQL Server: TOP 支持变量（需要括号）
DECLARE @n INT = 10;
SELECT TOP (@n) * FROM orders ORDER BY id;
-- 没有括号的写法仅支持字面量:
SELECT TOP 10 * FROM orders ORDER BY id;
```

## ORDER BY 与确定性分页

### 没有 ORDER BY 的分页是不确定的

```sql
-- 危险: 无 ORDER BY 的分页
SELECT * FROM orders LIMIT 10 OFFSET 20;
-- 每次执行可能返回不同的行！
-- 不同引擎可能使用不同的物理扫描顺序
```

各引擎对 LIMIT 不搭配 ORDER BY 的态度：

| 引擎 | 无 ORDER BY 时行为 | 是否警告 |
|------|-------------------|---------|
| MySQL | 顺序不确定，不可依赖 | 不警告 |
| PostgreSQL | 按物理存储顺序（不稳定） | 不警告 |
| Oracle | 不确定 | 不警告 |
| SQL Server | FETCH 要求必须有 ORDER BY | 强制报错 |
| SQLite | 按 rowid 顺序 | 不警告 |
| DuckDB | 不确定 | 不警告 |
| ClickHouse | 不确定（分布式更严重） | 不警告 |
| BigQuery | 不确定 | 不警告 |
| Spark SQL | 不确定（分区间无序） | 不警告 |

SQL Server 是唯一强制要求 FETCH 搭配 ORDER BY 的引擎。其他引擎默许无 ORDER BY 的分页，但结果不可预测。

### ORDER BY 不唯一时的分页重叠问题

```sql
-- 问题: ORDER BY 列有重复值
SELECT * FROM orders ORDER BY status LIMIT 10 OFFSET 0;   -- 第 1 页
SELECT * FROM orders ORDER BY status LIMIT 10 OFFSET 10;  -- 第 2 页
-- status 相同的行可能在两页之间随机分布，甚至出现在两页中或都不出现

-- 解决: 加入唯一列打破平局
SELECT * FROM orders ORDER BY status, id LIMIT 10 OFFSET 0;
SELECT * FROM orders ORDER BY status, id LIMIT 10 OFFSET 10;
-- id 是唯一的，排序完全确定，分页无重叠
```

## Keyset 分页 vs OFFSET 分页

### OFFSET 分页的性能问题

```sql
-- 第 1000 页，每页 10 条
SELECT * FROM orders ORDER BY id LIMIT 10 OFFSET 9990;
-- 引擎实际上需要扫描并排序前 10000 行，然后丢弃前 9990 行
-- OFFSET 越大，性能越差——O(offset + limit) 复杂度
```

### Keyset 分页（游标分页）

```sql
-- 第 1 页
SELECT * FROM orders ORDER BY id LIMIT 10;
-- 假设最后一行的 id = 42

-- 第 2 页（使用上一页最后的 id）
SELECT * FROM orders WHERE id > 42 ORDER BY id LIMIT 10;
-- 利用索引直接定位到 id=42 之后，O(limit) 复杂度

-- 多列排序的 Keyset 分页
-- 上一页最后一行: created_at = '2024-01-15', id = 42
SELECT * FROM orders
WHERE (created_at, id) > ('2024-01-15', 42)
ORDER BY created_at, id
LIMIT 10;

-- 不支持行值比较的引擎（如 MySQL 5.7）需要展开:
SELECT * FROM orders
WHERE created_at > '2024-01-15'
   OR (created_at = '2024-01-15' AND id > 42)
ORDER BY created_at, id
LIMIT 10;
```

### 两种分页方式对比

| 特性 | OFFSET 分页 | Keyset 分页 |
|------|------------|------------|
| 实现复杂度 | 简单 | 中等 |
| 深页性能 | 差（线性退化） | 稳定 |
| 是否能跳页 | 可以 | 不可以 |
| 总页数 | 需要 COUNT(*) | 不易获取 |
| 数据一致性 | 插入/删除会导致行跳过或重复 | 无此问题 |
| 适用场景 | 后台管理、数据量小 | 信息流、API 分页、大数据量 |
| 索引要求 | ORDER BY 列有索引可优化 | 必须有索引 |

各引擎对行值比较（Row Value Comparison）的支持——Keyset 分页的关键能力：

| 引擎 | `(a, b) > (x, y)` 语法 | 索引利用 |
|------|------------------------|---------|
| PostgreSQL | ✅ | ✅ 优化器可用组合索引 |
| MySQL | ✅ (8.0.16+ 优化) | ✅ (8.0.16+ 才走索引) |
| SQLite | ✅ | ✅ |
| Oracle | ✅ | ✅ |
| SQL Server | ❌ | 需展开为 AND/OR |
| DuckDB | ✅ | ✅ |
| CockroachDB | ✅ | ✅ |
| MariaDB | ✅ | 部分优化 |
| ClickHouse | ✅ | 有限 |
| BigQuery | ✅ | 内部优化 |

## 各引擎语法速查

### MySQL

```sql
-- 唯一语法
SELECT * FROM t ORDER BY id LIMIT 10;
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;
SELECT * FROM t ORDER BY id LIMIT 20, 10;  -- 逗号语法 (offset, count)
```

### PostgreSQL

```sql
-- LIMIT（传统语法）
SELECT * FROM t ORDER BY id LIMIT 10;
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

-- FETCH（SQL:2008 标准）
SELECT * FROM t ORDER BY id FETCH FIRST 10 ROWS ONLY;
SELECT * FROM t ORDER BY id OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- LIMIT ALL 等价于无 LIMIT
SELECT * FROM t ORDER BY id LIMIT ALL;
```

### Oracle

```sql
-- 12c+ FETCH 语法（推荐）
SELECT * FROM orders ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- Oracle 不支持 LIMIT 语法
-- 传统 ROWNUM 方案（12c 之前）
SELECT * FROM (
    SELECT t.*, ROWNUM rn FROM (
        SELECT * FROM orders ORDER BY id
    ) t WHERE ROWNUM <= 30
) WHERE rn > 20;
```

### SQL Server

```sql
-- TOP（所有版本）
SELECT TOP 10 * FROM orders ORDER BY id;

-- OFFSET FETCH（2012+，必须有 ORDER BY，且 FETCH 必须搭配 OFFSET）
SELECT * FROM orders ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- OFFSET 0 用于从第一行开始
SELECT * FROM orders ORDER BY id
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
```

### SQLite

```sql
-- 仅支持 LIMIT/OFFSET
SELECT * FROM t ORDER BY id LIMIT 10;
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

-- LIMIT 接受表达式
SELECT * FROM t ORDER BY id LIMIT 5 + 5;
SELECT * FROM t ORDER BY id LIMIT (SELECT page_size FROM config);
```

### ClickHouse

```sql
-- LIMIT/OFFSET
SELECT * FROM t ORDER BY id LIMIT 10;
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

-- LIMIT BY（按组分页，ClickHouse 独有）
SELECT * FROM t ORDER BY ts DESC LIMIT 3 BY user_id;
```

### Snowflake

```sql
-- LIMIT/OFFSET
SELECT * FROM t ORDER BY id LIMIT 10;
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

-- TOP（兼容 SQL Server 迁移）
SELECT TOP 10 * FROM t ORDER BY id;
```

### BigQuery

```sql
-- 仅支持 LIMIT/OFFSET
SELECT * FROM t ORDER BY id LIMIT 10;
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;
-- OFFSET 必须搭配 LIMIT，且 LIMIT 和 OFFSET 仅接受字面量或参数
```

### Spark SQL

```sql
-- LIMIT
SELECT * FROM t ORDER BY id LIMIT 10;

-- OFFSET（Spark 3.4+）
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 20;

-- 旧版本用窗口函数替代 OFFSET
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM t
) WHERE rn BETWEEN 21 AND 30;
```

### Db2

```sql
-- 仅支持 FETCH FIRST（标准语法）
SELECT * FROM t ORDER BY id
FETCH FIRST 10 ROWS ONLY;

-- 带 OFFSET
SELECT * FROM t ORDER BY id
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY;

-- OPTIMIZE FOR n ROWS（查询优化提示，非分页语法）
SELECT * FROM t ORDER BY id
FETCH FIRST 10 ROWS ONLY
OPTIMIZE FOR 10 ROWS;
```

### Teradata

```sql
-- TOP
SELECT TOP 10 * FROM t ORDER BY id;

-- FETCH FIRST（标准语法）
SELECT * FROM t ORDER BY id FETCH FIRST 10 ROWS ONLY;

-- SAMPLE（随机采样，非精确分页）
SELECT * FROM t SAMPLE 10;
```

### Hive

```sql
-- 仅支持 LIMIT（不支持 OFFSET）
SELECT * FROM t ORDER BY id LIMIT 10;

-- 分页需要窗口函数
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn FROM t
) sub WHERE rn BETWEEN 21 AND 30;
```

### Flink SQL

```sql
-- LIMIT（不支持 OFFSET）
SELECT * FROM t ORDER BY id LIMIT 10;

-- FETCH FIRST（标准语法）
SELECT * FROM t ORDER BY id FETCH FIRST 10 ROWS ONLY;
```

## 等价改写速查表

在不支持目标语法的引擎中实现等价分页：

| 目标语法 | 等价改写 | 适用场景 |
|---------|---------|---------|
| `LIMIT 10 OFFSET 20` | `OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY` | 支持 FETCH 的引擎 |
| `LIMIT 10 OFFSET 20` | ROW_NUMBER() + WHERE rn BETWEEN 21 AND 30 | 所有引擎 |
| `TOP 10` | `LIMIT 10` 或 `FETCH FIRST 10 ROWS ONLY` | 非 SQL Server 引擎 |
| `ROWNUM <= 10` | `LIMIT 10` 或 `FETCH FIRST 10 ROWS ONLY` | 非 Oracle 引擎 |
| `FETCH FIRST 10 ROWS WITH TIES` | RANK() OVER (...) + WHERE rk <= 10 | 无 WITH TIES 的引擎 |
| `TOP 10 PERCENT` | 先 COUNT(*) 算出 N，再 LIMIT N | 无 PERCENT 的引擎 |

## 实现语义差异汇总

### LIMIT 0 vs FETCH FIRST 0 ROWS

```sql
-- 大多数引擎: 返回 0 行（空结果集）
SELECT * FROM t LIMIT 0;
SELECT * FROM t FETCH FIRST 0 ROWS ONLY;

-- 用途: 用于获取列元数据而不返回数据
-- ORM 框架常用这个技巧来获取表结构
```

### NULL 作为 LIMIT 值

```sql
-- PostgreSQL: LIMIT NULL 等价于无 LIMIT
SELECT * FROM t LIMIT NULL;  -- 返回所有行

-- MySQL: LIMIT NULL 语法错误
-- SQL Server: TOP NULL 语法错误
```

### OFFSET 超过总行数

所有引擎的行为一致：返回空结果集（0 行），不报错。

```sql
-- 表中只有 100 行
SELECT * FROM t ORDER BY id LIMIT 10 OFFSET 200;
-- 所有引擎: 返回 0 行
```

## 性能优化要点

### 1. 深页 OFFSET 优化

```sql
-- 慢: 全排序后丢弃大量行
SELECT * FROM orders ORDER BY id LIMIT 10 OFFSET 100000;

-- 快: 延迟关联（Deferred Join）
SELECT o.* FROM orders o
JOIN (SELECT id FROM orders ORDER BY id LIMIT 10 OFFSET 100000) t
ON o.id = t.id;
-- 子查询只扫描索引（覆盖索引），主查询只取 10 行的完整数据
```

### 2. COUNT(*) 与分页的分离

```sql
-- 常见错误: 分页查询和 COUNT 用相同的复杂查询
-- 第 1 次查询: 取总数
SELECT COUNT(*) FROM orders WHERE status = 'active' AND ...;
-- 第 2 次查询: 取分页数据
SELECT * FROM orders WHERE status = 'active' AND ... ORDER BY id LIMIT 10 OFFSET 20;

-- 优化: 对于大数据量，考虑:
-- 1. 估算总数（EXPLAIN 或统计表）
-- 2. 只显示"下一页"按钮（不显示总页数）
-- 3. 缓存 COUNT 结果
```

### 3. 各引擎 LIMIT 下推优化

| 引擎 | Sort 提前终止 | 索引扫描替代排序 | LIMIT 下推到存储层 | LIMIT 下推到子查询 |
|------|-------------|----------------|-------------------|------------------|
| MySQL | ✅ | ✅ | - | 有限 |
| PostgreSQL | ✅ | ✅ | - | ✅ |
| Oracle | ✅ | ✅ | - | ✅ |
| SQL Server | ✅ | ✅ | - | ✅ |
| ClickHouse | ✅ | ❌ | ✅ (分布式) | ✅ |
| Spark SQL | ✅ | ❌ | ✅ (数据源) | ✅ |
| BigQuery | ✅ | ❌ | ✅ (分布式) | ✅ |
| Trino | ✅ | ❌ | ✅ (连接器) | ✅ |

## 对引擎开发者的实现建议

### 1. LIMIT/OFFSET 算子设计

分页语法在逻辑计划中应拆分为独立的 Limit 算子和 Offset 算子（或合并为 LimitOffset 算子）：

```
执行计划:
  TableScan → Sort → Offset(20) → Limit(10) → Project

合并算子:
  TableScan → Sort → LimitOffset(limit=10, offset=20) → Project
```

实现要点：

```
LimitOffset 算子:
  state: skipped = 0, emitted = 0

  next_row():
    while skipped < offset:
      row = child.next()
      if row == EOF: return EOF
      skipped++
    if emitted < limit:
      row = child.next()
      if row == EOF: return EOF
      emitted++
      return row
    else:
      return EOF  // 可主动关闭子算子释放资源
```

### 2. Sort + Limit 融合优化（Top-N 排序）

当 Sort 和 Limit 相邻时，可以融合为 Top-N 排序算子，使用堆排序将空间复杂度从 O(全表) 降至 O(N)：

```
优化前: Sort(全表排序) → Limit(10)         空间: O(全表)
优化后: TopNSort(N=10, 堆排序)              空间: O(10)

TopNSort 算法:
  维护一个大小为 N 的最大堆/最小堆
  遍历输入:
    if heap.size < N:
      heap.push(row)
    else if row < heap.top:
      heap.replace_top(row)
  输出堆中排序后的 N 行
```

有 OFFSET 时，堆大小为 `offset + limit`，空间为 O(offset + limit)。深 OFFSET 时优势减弱。

### 3. 分布式引擎的 LIMIT 下推

分布式查询中，LIMIT 需要在每个分片上先执行局部 LIMIT，再在协调节点合并：

```
无 OFFSET:
  各分片: ORDER BY col LIMIT N
  协调节点: 归并排序取全局 Top N

有 OFFSET:
  各分片: ORDER BY col LIMIT (offset + limit)
  协调节点: 归并排序 → 全局 OFFSET → 全局 LIMIT
```

注意：分布式 OFFSET 分页无法避免在每个分片上多取数据。这是 OFFSET 在分布式系统中性能更差的根本原因。

### 4. FETCH WITH TIES 实现

WITH TIES 要求在达到 N 行后继续检查后续行是否与第 N 行的 ORDER BY 值相同：

```
LimitWithTies 算子:
  state: emitted = 0, last_values = NULL

  next_row():
    row = child.next()
    if row == EOF: return EOF
    if emitted < limit:
      emitted++
      last_values = extract_order_keys(row)
      return row
    else:
      current = extract_order_keys(row)
      if current == last_values:  // 并列值
        return row                // 不增加计数
      else:
        return EOF
```

比较时需注意 NULL 语义：两个 NULL 在 ORDER BY 上下文中视为"相等"（与 WHERE 中 NULL != NULL 不同）。

### 5. SQL Server 的 OFFSET 必须搭配 ORDER BY 设计

SQL Server 要求 OFFSET/FETCH 必须与 ORDER BY 一起使用，这是正确的设计选择。建议新引擎至少在无 ORDER BY 时发出警告：

```
解析器层面:
  if has_offset_fetch && !has_order_by:
    // 方案 A: 报错（SQL Server 选择）
    raise SyntaxError("OFFSET/FETCH requires ORDER BY")
    // 方案 B: 警告（推荐）
    emit Warning("OFFSET without ORDER BY produces non-deterministic results")
```

### 6. 预处理语句中的 LIMIT 参数绑定

LIMIT/OFFSET 值的参数化对于防止 SQL 注入和查询计划复用都很重要：

```sql
-- 建议支持的形式
PREPARE stmt FROM 'SELECT * FROM t ORDER BY id LIMIT ? OFFSET ?';
EXECUTE stmt USING 10, 20;
```

实现时需要在语法解析阶段允许参数占位符出现在 LIMIT/OFFSET 位置。参数值应在绑定阶段验证为非负整数。

### 7. LIMIT 0 优化

`LIMIT 0` 查询可在计划优化阶段直接短路为空结果集，保留列元数据但跳过所有数据访问：

```
优化规则: EliminateLimitZero
  if limit == 0:
    替换整个子树为 EmptyRelation(schema=original_schema)
    // 无需访问表、无需排序
```

### 8. ORDER BY 唯一性保证与确定性分页

分页查询的 ORDER BY 必须包含唯一性的 tie-breaker 列（通常是主键或唯一 ID），否则相同排序值的行在不同页之间的分配是不确定的：

```sql
-- 错误: created_at 不唯一，相同时间戳的行可能在翻页时重复或丢失
SELECT * FROM orders ORDER BY created_at LIMIT 10 OFFSET 20;

-- 正确: 追加主键作为 tie-breaker，保证全局唯一排序
SELECT * FROM orders ORDER BY created_at, id LIMIT 10 OFFSET 20;
```

实现建议：
- 在 planner 或 analyzer 阶段检测分页查询的 ORDER BY 是否包含唯一键
- 如果 ORDER BY 列不能保证唯一性且存在 OFFSET，发出优化器警告（Warning）
- 文档和错误提示中引导用户添加 tie-breaker 列

### 9. 大 OFFSET 的 I/O 开销陷阱

OFFSET 分页的本质缺陷在于数据库必须先扫描并丢弃 OFFSET 行，然后才返回 LIMIT 行。OFFSET 越大，浪费的 I/O 越多：

```
OFFSET 0,    LIMIT 10 → 扫描 10 行,     返回 10 行
OFFSET 1000, LIMIT 10 → 扫描 1010 行,   返回 10 行
OFFSET 100000, LIMIT 10 → 扫描 100010 行, 返回 10 行

代价模型:
  实际 I/O = O(offset + limit)
  返回数据 = O(limit)
  浪费比   = offset / (offset + limit) → 接近 100%（深页时）
```

这一问题在分布式引擎中更加严重，因为每个分片都必须返回 `offset + limit` 行到协调节点。对于深页场景，应明确向用户推荐 Seek/Keyset 分页方案。

### 10. Seek/Keyset 分页推荐与索引利用

Seek（又称 Keyset）分页通过记住上一页最后一行的排序键值来定位下一页的起始位置，完全避免了 OFFSET 的扫描浪费：

```sql
-- OFFSET 分页 (第 N 页): 必须扫描前 N×page_size 行
SELECT * FROM orders ORDER BY created_at, id
LIMIT 10 OFFSET 10000;

-- Keyset 分页 (同等效果): 利用索引直接定位起始点
SELECT * FROM orders
WHERE (created_at, id) > (:last_created_at, :last_id)
ORDER BY created_at, id
LIMIT 10;
```

Keyset 分页的优势与实现要点：

```
性能对比:
  OFFSET 分页: I/O = O(offset + limit), 随页数线性增长
  Keyset 分页: I/O = O(limit),           恒定代价

前提条件:
  1. ORDER BY 列上必须有覆盖索引 (如 INDEX(created_at, id))
  2. 排序键必须唯一 (需 tie-breaker)
  3. 客户端需持有上一页最后一行的排序键值

局限性:
  - 不支持直接跳转到第 N 页 (只能向前/向后翻)
  - 不适用于需要精确 total count 的 UI 场景
  - 排序键变更时需要重新校准游标

引擎层面建议:
  - 优化器识别 WHERE (a, b) > (?, ?) ORDER BY a, b LIMIT N 模式
  - 利用复合索引的 range scan 直接定位起始行
  - 避免走全表排序路径
```

## 参考资料

- ISO/IEC 9075-2:2008 Section 7.17 (query expression - FETCH clause)
- ISO/IEC 9075-2:2003 Section 7.11 (window function - ROW_NUMBER)
- MySQL: [LIMIT Clause](https://dev.mysql.com/doc/refman/8.0/en/select.html)
- PostgreSQL: [LIMIT and OFFSET](https://www.postgresql.org/docs/current/queries-limit.html)
- SQL Server: [TOP / OFFSET FETCH](https://learn.microsoft.com/en-us/sql/t-sql/queries/top-transact-sql)
- Oracle: [Row Limiting Clause](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SELECT.html)
- SQLite: [LIMIT](https://www.sqlite.org/lang_select.html#limitoffset)
- ClickHouse: [LIMIT Clause](https://clickhouse.com/docs/en/sql-reference/statements/select/limit)
- Use The Index, Luke: [Pagination Done the Right Way](https://use-the-index-luke.com/sql/partial-results/fetch-next-page)
