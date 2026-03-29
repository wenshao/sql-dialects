# NULL 处理行为：各 SQL 方言全对比

> 参考资料:
> - [SQL:1999 IS NOT DISTINCT FROM](https://wiki.postgresql.org/wiki/Is_distinct_from)
> - [MySQL 8.0 - NULL-safe Equal Operator](https://dev.mysql.com/doc/refman/8.0/en/comparison-operators.html#operator_equal-to)
> - [PostgreSQL - Comparison Functions and Operators](https://www.postgresql.org/docs/current/functions-comparison.html)
> - [Oracle - NULL Handling](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/Nulls.html)
> - [SQL Server - IS [NOT] DISTINCT FROM](https://learn.microsoft.com/en-us/sql/t-sql/queries/is-distinct-from-transact-sql)
> - [BigQuery - IS DISTINCT FROM](https://cloud.google.com/bigquery/docs/reference/standard-sql/operators#is_distinct)
> - [Snowflake - EQUAL_NULL](https://docs.snowflake.com/en/sql-reference/functions/equal_null)
> - [ClickHouse - NULL Handling](https://clickhouse.com/docs/sql-reference/statements/select/order-by#sorting-of-special-values)

NULL 是 SQL 三值逻辑的核心，但各方言在 NULL 的处理细节上存在大量差异。本文以横向对比矩阵的形式，系统梳理 17+ 方言在 NULL 相关行为上的异同，供引擎开发者和跨数据库迁移项目快速参考。

**图例**：✅ = 支持 | ❌ = 不支持 | ⚠️ = 部分支持或行为特殊

> **关联文章**: 本文侧重横向对比矩阵。NULL 的三值逻辑数学基础见 [null-semantics.md](null-semantics.md)；NULL 安全比较运算符的详细用法见 [null-safe-comparison.md](null-safe-comparison.md)。

---

## 1. NULL 等值比较

### 1.1 NULL = NULL 的结果

**所有** SQL 方言遵循 SQL 标准三值逻辑：`NULL = NULL` 返回 `UNKNOWN`（非 TRUE，非 FALSE）。

```sql
-- 所有方言：
SELECT NULL = NULL;    -- 结果: NULL (UNKNOWN)
SELECT NULL <> NULL;   -- 结果: NULL (UNKNOWN)
SELECT NULL > 0;       -- 结果: NULL (UNKNOWN)

-- 正确判断方式：
SELECT x IS NULL;      -- TRUE 或 FALSE
SELECT x IS NOT NULL;  -- TRUE 或 FALSE
```

这是 SQL 最基础也最容易踩坑的特性——**没有任何方言例外**。

### 1.2 NULL 安全等值比较运算符

标准 SQL:1999 定义了 `IS NOT DISTINCT FROM`，但各方言采纳程度差异很大。

| 方言 | `IS NOT DISTINCT FROM` | `<=>` 运算符 | 其他替代方案 | 备注 |
|------|---|---|---|---|
| **MySQL** | ❌ | ✅ (3.23+) | - | 最早实现 NULL 安全比较 |
| **MariaDB** | ✅ (10.3+) | ✅ | - | 两种语法都支持 |
| **PostgreSQL** | ✅ (8.0+) | ❌ | - | 完全符合 SQL 标准 |
| **Oracle** | ✅ (23c+) | ❌ | `DECODE(a,b,1,0)=1`（23c 前） | 23c 引入 IS [NOT] DISTINCT FROM；23c 前用 DECODE 变通 |
| **SQL Server** | ✅ (2022+) | ❌ | - | 2022 版才支持标准语法 |
| **SQLite** | ❌ | ❌ | `a IS b` | SQLite 的 `IS` 相当于 NULL 安全等于 |
| **BigQuery** | ✅ | ❌ | - | 完整支持标准语法 |
| **Snowflake** | ✅ | ❌ | `EQUAL_NULL(a, b)` | 还提供函数形式 |
| **ClickHouse** | ❌ | ❌ | `isNotDistinctFrom(a,b)` (23.2+) | 仅函数形式 |
| **Hive** | ❌ | ✅ | - | 与 MySQL 相同语法 |
| **Spark SQL** | ✅ (3.2+) | ✅ (2.0+) | - | 两种都支持 |
| **Trino** | ✅ | ❌ | - | 完整支持标准语法 |
| **DuckDB** | ✅ (0.3+) | ❌ | - | 完整支持标准语法 |
| **Flink SQL** | ✅ (1.11+, 经 Calcite) | ❌ | - | 通过 Calcite 引擎支持 |
| **Redshift** | ❌ | ❌ | 手写复合条件 | 基于旧版 PG，尚未引入 |
| **MaxCompute** | ❌ | ❌ | 手写复合条件 | 不支持 |
| **StarRocks** | ✅ | ✅ | - | 两种都支持 |
| **Doris** | ✅ | ✅ | - | 两种都支持 |
| **TiDB** | ❌ | ✅ | - | 兼容 MySQL |
| **OceanBase (MySQL)** | ❌ | ✅ | - | 兼容 MySQL |
| **DamengDB** | ❌ | ❌ | `DECODE` 变通 | 类 Oracle |
| **KingbaseES** | ✅ | ❌ | - | 类 PostgreSQL |
| **openGauss** | ✅ | ❌ | - | 类 PostgreSQL |
| **CockroachDB** | ✅ | ❌ | - | 兼容 PostgreSQL |
| **DB2** | ✅ (9.7+) | ❌ | - | 标准语法 |

**引擎开发者要点**：NULL 安全比较是 JOIN 条件和 MERGE 匹配中的刚需。如果你正在构建新引擎，优先实现 `IS NOT DISTINCT FROM`（SQL 标准），同时考虑兼容 `<=>` 以便 MySQL 用户迁移。

---

## 2. NULL 与字符串拼接

### 2.1 `||` 拼接运算符中的 NULL

| 方言 | `NULL \|\| 'text'` 结果 | 备注 |
|------|---|---|
| **MySQL** | `NULL`（`\|\|` 是逻辑 OR：`NULL OR 0 = NULL`） | `\|\|` 默认是逻辑 OR，不是拼接！ |
| **MariaDB** | `NULL` | 10.2+ 默认启用 `PIPES_AS_CONCAT`（`\|\|` 是拼接）；10.2 前同 MySQL 为逻辑 OR |
| **PostgreSQL** | `NULL` | NULL 传播 |
| **Oracle** | `'text'` | **特殊**: Oracle 把 NULL 当空字符串处理 |
| **SQL Server** | 不支持 `\|\|` | 用 `+` 运算符，`NULL + 'text'` = `NULL` |
| **SQLite** | `NULL` | NULL 传播 |
| **BigQuery** | `NULL` | NULL 传播 |
| **Snowflake** | `NULL` | NULL 传播 |
| **ClickHouse** | `NULL` | `\|\|` 映射到 `concat()`，NULL 传播 |
| **Hive** | `NULL` | NULL 传播 |
| **Spark SQL** | `NULL` | NULL 传播 |
| **Trino** | `NULL` | NULL 传播 |
| **DuckDB** | `NULL` | NULL 传播 |
| **Flink SQL** | `NULL` | NULL 传播 |
| **Redshift** | `NULL` | NULL 传播（同 PostgreSQL） |
| **MaxCompute** | `NULL` | NULL 传播 |
| **StarRocks** | `NULL` | NULL 传播 |
| **Doris** | `NULL` | NULL 传播 |

**关键陷阱**：
- **MySQL**: `SELECT 'hello' || 'world'` 返回 `0`（逻辑 OR），不是 `'helloworld'`！需设置 `sql_mode=PIPES_AS_CONCAT` 或用 `CONCAT()` 函数
- **Oracle**: `SELECT NULL || 'text'` 返回 `'text'`——Oracle 将 NULL 视为空字符串，这是 **Oracle 独有行为**，其他所有方言都返回 NULL

### 2.2 `CONCAT()` 函数中的 NULL

各方言的 `CONCAT()` 函数对 NULL 参数的处理分为两大阵营：

| 方言 | `CONCAT(NULL, 'text')` 结果 | 行为类型 |
|------|---|---|
| **MySQL** | `NULL` | NULL 传播 |
| **MariaDB** | `NULL` | NULL 传播 |
| **PostgreSQL** | `'text'` | NULL 跳过 |
| **Oracle** | `'text'` | NULL 跳过（仅两参数版本，等价于 `\|\|`） |
| **SQL Server** | `'text'` | NULL 跳过 |
| **SQLite** | `NULL` | NULL 传播 |
| **BigQuery** | `NULL` | NULL 传播 |
| **Snowflake** | `NULL` | NULL 传播 |
| **ClickHouse** | `NULL` | NULL 传播 |
| **Hive** | `NULL` | NULL 传播 |
| **Spark SQL** | `NULL` | NULL 传播（`concat_ws()` 才跳过 NULL） |
| **Trino** | `NULL` | NULL 传播 |
| **DuckDB** | `'text'` | NULL 跳过 |
| **Flink SQL** | `NULL` | NULL 传播 |
| **Redshift** | `NULL` | NULL 传播（与 PG 不同！） |
| **MaxCompute** | `NULL` | NULL 传播 |
| **StarRocks** | `NULL` | NULL 传播 |
| **Doris** | `NULL` | NULL 传播 |

**总结**：

| 行为 | 方言 |
|------|------|
| **NULL 传播**（返回 NULL） | MySQL, MariaDB, Spark, SQLite, BigQuery, Snowflake, Trino, Hive, ClickHouse, Flink, Redshift, MaxCompute, StarRocks, Doris |
| **NULL 跳过**（忽略 NULL） | PostgreSQL, Oracle, SQL Server, DuckDB |

**引擎开发者要点**：跨引擎迁移时，`CONCAT()` 的 NULL 行为差异是最常见的静默 bug 来源之一。如果你的引擎是 NULL 传播型，应提供 `CONCAT_WS` 或类似函数让用户选择跳过 NULL。

---

## 3. COALESCE / NVL / IFNULL / ISNULL 可用性矩阵

这四个函数都用于"遇到 NULL 时返回替代值"，但各方言支持范围不同。

| 方言 | `COALESCE` | `NVL` | `IFNULL` | `ISNULL` | `IF(x IS NULL, ...)` | 备注 |
|------|---|---|---|---|---|---|
| **MySQL** | ✅ | ❌ | ✅ | ❌ | ✅ | `ISNULL()` 存在但返回 0/1，不是替代值 |
| **MariaDB** | ✅ | ❌ | ✅ | ❌ | ✅ | 同 MySQL |
| **PostgreSQL** | ✅ | ❌ | ❌ | ❌ | ❌ | 只有标准 COALESCE |
| **Oracle** | ✅ | ✅ | ❌ | ❌ | ❌ | NVL 是 Oracle 首创 |
| **SQL Server** | ✅ | ❌ | ❌ | ✅ | ❌ | `ISNULL(x, default)` 替代值语义 |
| **SQLite** | ✅ | ❌ | ✅ | ❌ | ❌ | IFNULL 是两参数 COALESCE |
| **BigQuery** | ✅ | ❌ | ✅ | ❌ | ✅ | 支持 IFNULL 和 IF |
| **Snowflake** | ✅ | ✅ | ✅ | ❌ | ✅ | 三种都支持 |
| **ClickHouse** | ✅ | ❌ | ✅ | ❌ | ✅ | ifNull 函数 |
| **Hive** | ✅ | ✅ | ❌ | ❌ | ✅ | 支持 NVL |
| **Spark SQL** | ✅ | ✅ | ✅ | ❌ | ✅ | NVL + IFNULL 都支持 |
| **Trino** | ✅ | ❌ | ❌ | ❌ | ✅ | 只有标准 COALESCE |
| **DuckDB** | ✅ | ❌ | ✅ | ❌ | ✅ | IFNULL 是别名 |
| **Flink SQL** | ✅ | ❌ | ✅ | ❌ | ✅ | 支持 IFNULL |
| **Redshift** | ✅ | ✅ | ❌ | ❌ | ❌ | 支持 NVL 和 NVL2 |
| **MaxCompute** | ✅ | ✅ | ❌ | ❌ | ✅ | 支持 NVL |
| **StarRocks** | ✅ | ❌ | ✅ | ❌ | ✅ | 同 MySQL 系 |
| **Doris** | ✅ | ✅ | ✅ | ❌ | ✅ | NVL + IFNULL |
| **TiDB** | ✅ | ❌ | ✅ | ❌ | ✅ | 兼容 MySQL |
| **OceanBase (MySQL)** | ✅ | ❌ | ✅ | ❌ | ✅ | 兼容 MySQL |
| **OceanBase (Oracle)** | ✅ | ✅ | ❌ | ❌ | ❌ | 兼容 Oracle |
| **DamengDB** | ✅ | ✅ | ❌ | ❌ | ❌ | 类 Oracle |
| **KingbaseES** | ✅ | ❌ | ❌ | ❌ | ❌ | 类 PostgreSQL |
| **openGauss** | ✅ | ✅ | ❌ | ❌ | ❌ | NVL 扩展（A 兼容模式） |
| **CockroachDB** | ✅ | ❌ | ✅ | ❌ | ✅ | 兼容 PostgreSQL + IFNULL 扩展 |
| **DB2** | ✅ | ✅ | ❌ | ❌ | ❌ | NVL 兼容支持 |

**安全建议**：`COALESCE` 是 **唯一在所有方言都可用** 的 NULL 替代函数。跨数据库项目应统一使用 `COALESCE`，避免 `NVL` / `IFNULL` / `ISNULL`。

**关键区别**：
- `COALESCE(a, b, c, ...)` — SQL 标准，接受任意多参数，返回第一个非 NULL 值
- `NVL(a, b)` — Oracle 传统，仅两参数
- `IFNULL(a, b)` — MySQL 传统，仅两参数，语义等同 `COALESCE(a, b)`
- `ISNULL(a, b)` — SQL Server 专有，仅两参数，且返回类型取决于第一个参数（与 COALESCE 不同）

---

## 4. NULL 在聚合函数中的行为

### 4.1 基本规则

所有 SQL 方言在聚合函数中对 NULL 的处理**高度一致**，遵循 SQL 标准：

| 场景 | 结果 | 是否所有方言一致 |
|------|------|---|
| `COUNT(*)` | 计算所有行（含 NULL） | ✅ 全部一致 |
| `COUNT(col)` | 跳过 NULL 行 | ✅ 全部一致 |
| `SUM(col)` 所有值为 NULL | 返回 `NULL`（不是 0） | ✅ 全部一致 |
| `AVG(col)` 跳过 NULL | NULL 行不参与计算 | ✅ 全部一致 |
| `MIN(col)` / `MAX(col)` | 跳过 NULL | ✅ 全部一致 |
| `COUNT(DISTINCT col)` | 跳过 NULL | ✅ 全部一致 |

```sql
-- 示例数据: col = [1, NULL, 3, NULL, 5]

SELECT COUNT(*)    FROM t;  -- 5    (含 NULL 行)
SELECT COUNT(col)  FROM t;  -- 3    (跳过 2 个 NULL)
SELECT SUM(col)    FROM t;  -- 9    (1+3+5, 跳过 NULL)
SELECT AVG(col)    FROM t;  -- 3.0  (9/3, 不是 9/5)
```

### 4.2 SUM 全 NULL 陷阱

```sql
-- 表为空或所有值为 NULL:
SELECT SUM(col) FROM empty_table;  -- NULL (不是 0!)
SELECT SUM(col) FROM t WHERE 1=0;  -- NULL (不是 0!)

-- 安全写法:
SELECT COALESCE(SUM(col), 0) FROM t;
```

这是初学者最常踩的坑之一：`SUM` 在没有非 NULL 值时返回 NULL 而非 0。**所有方言行为一致**，但这并不意味着它符合直觉。

### 4.3 COUNT(*) vs COUNT(col) 的差异

```sql
CREATE TABLE demo (id INT, name VARCHAR(20));
INSERT INTO demo VALUES (1, 'Alice'), (2, NULL), (3, 'Charlie');

SELECT COUNT(*)    FROM demo;  -- 3
SELECT COUNT(name) FROM demo;  -- 2 (跳过 NULL)
SELECT COUNT(id)   FROM demo;  -- 3 (id 没有 NULL)
```

**引擎开发者要点**：如果你的引擎优化器在处理 `COUNT(col)` 时没有正确区分 NULL，会导致与 `COUNT(*)` 不一致的错误结果。这两者必须在执行层有不同的代码路径。

---

## 5. NULL 排序位置

### 5.1 默认排序中 NULL 的位置

不同方言在 `ORDER BY` 时对 NULL 的默认排位差异巨大：

| 方言 | `ASC` 时 NULL 位置 | `DESC` 时 NULL 位置 | 等价于视 NULL 为 |
|------|---|---|---|
| **MySQL** | FIRST（最前） | LAST（最后） | 最小值 |
| **MariaDB** | FIRST | LAST | 最小值 |
| **PostgreSQL** | LAST（最后） | FIRST（最前） | 最大值 |
| **Oracle** | LAST | FIRST | 最大值 |
| **SQL Server** | FIRST | LAST | 最小值 |
| **SQLite** | FIRST | LAST | 最小值 |
| **BigQuery** | LAST | FIRST | 最大值 |
| **Snowflake** | LAST | FIRST | 最大值 |
| **ClickHouse** | FIRST | LAST | 最小值 |
| **Hive** | LAST | FIRST | 最大值 |
| **Spark SQL** | LAST | FIRST | 最大值 |
| **Trino** | LAST | FIRST | 最大值 |
| **DuckDB** | LAST | FIRST | 最大值 |
| **Flink SQL** | LAST | FIRST | 最大值 |
| **Redshift** | LAST | FIRST | 最大值 |
| **MaxCompute** | LAST | FIRST | 最大值 |
| **StarRocks** | FIRST | LAST | 最小值 |
| **Doris** | FIRST | LAST | 最小值 |
| **TiDB** | FIRST | LAST | 最小值（同 MySQL） |
| **OceanBase (MySQL)** | FIRST | LAST | 最小值（同 MySQL） |
| **DamengDB** | LAST | FIRST | 最大值（同 Oracle） |
| **KingbaseES** | LAST | FIRST | 最大值（同 PostgreSQL） |
| **openGauss** | LAST | FIRST | 最大值（同 PostgreSQL） |
| **CockroachDB** | LAST | FIRST | 最大值（v20.2+ 同 PostgreSQL） |
| **DB2** | LAST | FIRST | 最大值 |

**总结**：

| NULL 排序行为 | 方言 |
|---|---|
| **NULL = 最小值**（ASC 时在最前） | MySQL, MariaDB, SQL Server, SQLite, ClickHouse, StarRocks, Doris, TiDB, OceanBase(MySQL) |
| **NULL = 最大值**（ASC 时在最后） | PostgreSQL, CockroachDB (v20.2+), Oracle, Snowflake, BigQuery, Hive, Spark, Trino, DuckDB, Flink, Redshift, MaxCompute, DamengDB, KingbaseES, openGauss, DB2 |

### 5.2 `NULLS FIRST` / `NULLS LAST` 语法支持

| 方言 | `NULLS FIRST` / `NULLS LAST` | 备注 |
|------|---|---|
| **MySQL** | ❌ | 需用 `ORDER BY ISNULL(col), col` 变通 |
| **MariaDB** | ✅ (10.3+) | 比 MySQL 多出的特性 |
| **PostgreSQL** | ✅ | 完整支持 |
| **Oracle** | ✅ | 完整支持 |
| **SQL Server** | ❌ | 需用 `ORDER BY CASE WHEN col IS NULL THEN 0 ELSE 1 END, col` |
| **SQLite** | ✅ (3.30.0+) | 2019 年加入 |
| **BigQuery** | ✅ | 完整支持 |
| **Snowflake** | ✅ | 完整支持 |
| **ClickHouse** | ✅ | `NULLS FIRST` / `NULLS LAST` |
| **Hive** | ✅ | 完整支持 |
| **Spark SQL** | ✅ | 完整支持 |
| **Trino** | ✅ | 完整支持 |
| **DuckDB** | ✅ | 完整支持 |
| **Flink SQL** | ✅ | 完整支持 |
| **Redshift** | ✅ | 完整支持 |
| **MaxCompute** | ✅ | 完整支持 |
| **StarRocks** | ✅ | 完整支持 |
| **Doris** | ✅ | 完整支持 |
| **TiDB** | ❌ | 同 MySQL，不支持 |
| **OceanBase (MySQL)** | ❌ | 同 MySQL |
| **DamengDB** | ✅ | 同 Oracle |
| **KingbaseES** | ✅ | 同 PostgreSQL |
| **openGauss** | ✅ | 同 PostgreSQL |
| **CockroachDB** | ✅ | 同 PostgreSQL |
| **DB2** | ✅ | 完整支持 |

**不支持 `NULLS FIRST/LAST` 的方言**：MySQL、SQL Server、TiDB、OceanBase(MySQL 模式)。这四个方言需要 CASE/ISNULL 变通方案。

---

## 6. NULL 在 DISTINCT / GROUP BY / UNION 中的行为

### 6.1 一致性规则

在 `DISTINCT`、`GROUP BY` 和 `UNION`（去重）操作中，所有方言都**将多个 NULL 视为相等（归为同一组/去重为一个）**。这与 `NULL = NULL` 返回 UNKNOWN 的等值比较行为形成了有趣的对比。

```sql
-- 所有方言行为一致:

-- DISTINCT: 多个 NULL 只保留一个
SELECT DISTINCT col FROM t;
-- 若 col = [1, NULL, 2, NULL, 3]
-- 结果: [1, NULL, 2, 3]  (两个 NULL 合并为一个)

-- GROUP BY: NULL 归为一组
SELECT col, COUNT(*) FROM t GROUP BY col;
-- 若 col = [1, NULL, 2, NULL, 3]
-- 结果: (1, 1), (NULL, 2), (2, 1), (3, 1)

-- UNION: NULL 参与去重
SELECT col FROM t1 UNION SELECT col FROM t2;
-- 两个表中的 NULL 会被合并为一个

-- UNION ALL: 不去重，NULL 全部保留
SELECT col FROM t1 UNION ALL SELECT col FROM t2;
-- NULL 全部保留，不合并
```

| 特性 | 所有方言一致？ | 行为 |
|------|---|---|
| `SELECT DISTINCT` 对 NULL 去重 | ✅ 全部一致 | 多个 NULL 合并为一个 |
| `GROUP BY` 对 NULL 分组 | ✅ 全部一致 | 所有 NULL 归为同一组 |
| `UNION` 对 NULL 去重 | ✅ 全部一致 | 多个 NULL 合并为一个 |
| `UNION ALL` 保留所有 NULL | ✅ 全部一致 | 所有 NULL 全部保留 |

**为什么 DISTINCT/GROUP BY 把 NULL 当相等，而 `=` 不行？**

这是 SQL 标准的有意设计。`=` 运算符遵循三值逻辑（`NULL = NULL` → UNKNOWN），但 `DISTINCT` 和 `GROUP BY` 使用的是"不可区分性"（IS NOT DISTINCT FROM）语义，而非等值比较语义。SQL 标准明确规定了这一区别。

---

## 7. 空字符串 = NULL

### 7.1 Oracle 的独特行为

在绝大多数 SQL 方言中，空字符串 `''` 和 `NULL` 是两个完全不同的值。但 **Oracle 将空字符串视为 NULL**——这是最著名的 Oracle "特性"之一。

```sql
-- Oracle:
SELECT CASE WHEN '' IS NULL THEN 'YES' ELSE 'NO' END FROM dual;
-- 结果: 'YES'

SELECT LENGTH('') FROM dual;
-- 结果: NULL (不是 0!)

SELECT '' || 'hello' FROM dual;
-- 结果: 'hello' (因为 '' 就是 NULL，而 NULL||'hello' 在 Oracle 中返回 'hello')

-- 其他所有方言:
SELECT CASE WHEN '' IS NULL THEN 'YES' ELSE 'NO' END;
-- 结果: 'NO'

SELECT LENGTH('');
-- 结果: 0
```

### 7.2 各方言对比

| 方言 | `'' IS NULL` | `LENGTH('')` | 空字符串与 NULL 等价 |
|------|---|---|---|
| **MySQL** | `FALSE` | `0` | ❌ 不等价 |
| **MariaDB** | `FALSE` | `0` | ❌ 不等价 |
| **PostgreSQL** | `FALSE` | `0` | ❌ 不等价 |
| **Oracle** | `TRUE` | `NULL` | ✅ **等价** |
| **SQL Server** | `FALSE` | `0` | ❌ 不等价 |
| **SQLite** | `FALSE` | `0` | ❌ 不等价 |
| **BigQuery** | `FALSE` | `0` | ❌ 不等价 |
| **Snowflake** | `FALSE` | `0` | ❌ 不等价 |
| **ClickHouse** | `FALSE` | `0` | ❌ 不等价 |
| **Hive** | `FALSE` | `0` | ❌ 不等价 |
| **Spark SQL** | `FALSE` | `0` | ❌ 不等价 |
| **Trino** | `FALSE` | `0` | ❌ 不等价 |
| **DuckDB** | `FALSE` | `0` | ❌ 不等价 |
| **DamengDB** | `TRUE` | `NULL` | ✅ **等价**（Oracle 兼容模式） |
| **OceanBase (Oracle 模式)** | `TRUE` | `NULL` | ✅ **等价** |
| **KingbaseES (Oracle 模式)** | `TRUE` | `NULL` | ✅ **等价** |
| **openGauss (A 兼容模式)** | `TRUE` | `NULL` | ✅ **等价** |

**等价组**：只有 Oracle 及其兼容模式引擎（DamengDB、OceanBase Oracle 模式、KingbaseES Oracle 模式、openGauss A 兼容模式）将空字符串视为 NULL。所有其他方言都严格区分二者。

**迁移影响**：从 Oracle 迁移到 PostgreSQL/MySQL 时，所有依赖 `'' IS NULL` 为 TRUE 的逻辑都会失败。必须审计每个涉及空字符串的条件判断和 NVL/COALESCE 调用。

---

## 8. NOT IN 陷阱

### 8.1 三值逻辑的致命后果

`NOT IN` 在包含 NULL 时的行为是 SQL 中最危险的陷阱之一，**所有方言行为一致**——但这个一致的行为对初学者来说是毁灭性的。

```sql
-- 场景: 查找不在列表中的值
SELECT * FROM t WHERE col NOT IN (1, 2, NULL);

-- 你以为: 返回 col 不是 1 且不是 2 的行
-- 实际:   返回空集！永远没有结果！
```

**原理推导**：

```sql
col NOT IN (1, 2, NULL)
-- 展开为:
col <> 1 AND col <> 2 AND col <> NULL
-- col <> NULL 永远返回 UNKNOWN
-- 根据三值逻辑: TRUE AND TRUE AND UNKNOWN = UNKNOWN
-- WHERE 子句需要 TRUE 才返回行
-- 所以: 所有行都被过滤掉
```

### 8.2 所有方言行为一致

| 方言 | `WHERE 1 NOT IN (2, 3, NULL)` 结果 | 返回行？ |
|------|---|---|
| **MySQL** | `UNKNOWN` | ❌ 不返回 |
| **PostgreSQL** | `UNKNOWN` | ❌ 不返回 |
| **Oracle** | `UNKNOWN` | ❌ 不返回 |
| **SQL Server** | `UNKNOWN` | ❌ 不返回 |
| **SQLite** | `UNKNOWN` | ❌ 不返回 |
| **BigQuery** | `UNKNOWN` | ❌ 不返回 |
| **Snowflake** | `UNKNOWN` | ❌ 不返回 |
| **ClickHouse** | `UNKNOWN` | ❌ 不返回 |
| **Hive** | `UNKNOWN` | ❌ 不返回 |
| **Spark SQL** | `UNKNOWN` | ❌ 不返回 |
| **Trino** | `UNKNOWN` | ❌ 不返回 |
| **DuckDB** | `UNKNOWN` | ❌ 不返回 |
| 所有其他方言 | `UNKNOWN` | ❌ 不返回 |

**100% 一致**：没有任何方言对此做了特殊处理。这是 SQL 标准三值逻辑的直接后果。

### 8.3 安全替代方案

```sql
-- 危险写法 (NOT IN 子查询可能包含 NULL):
SELECT * FROM orders
WHERE customer_id NOT IN (SELECT id FROM blocked_customers);
-- 如果 blocked_customers.id 有任何 NULL 值，结果永远为空！

-- 安全写法 1: 用 NOT EXISTS
SELECT * FROM orders o
WHERE NOT EXISTS (
    SELECT 1 FROM blocked_customers b WHERE b.id = o.customer_id
);

-- 安全写法 2: 显式排除 NULL
SELECT * FROM orders
WHERE customer_id NOT IN (
    SELECT id FROM blocked_customers WHERE id IS NOT NULL
);

-- 安全写法 3: 用 LEFT JOIN + IS NULL
SELECT o.* FROM orders o
LEFT JOIN blocked_customers b ON o.customer_id = b.id
WHERE b.id IS NULL;
```

**引擎开发者要点**：一些引擎的查询优化器会自动将 `NOT IN (subquery)` 重写为 `NOT EXISTS` 以规避此陷阱，但这只是优化，不改变语义。考虑在你的引擎中加入 lint 警告，当 `NOT IN` 子查询的列允许 NULL 时提示用户。

---

## 9. 横向总结和对引擎开发者的建议

### 9.1 各方言 NULL 行为差异速查

| 维度 | 差异大小 | 主要分裂点 |
|------|---|---|
| NULL = NULL | 无差异 | 全部返回 UNKNOWN |
| IS NOT DISTINCT FROM | **大** | 标准语法 vs `<=>` vs 不支持 |
| `\|\|` 拼接中的 NULL | **大** | Oracle 跳过 NULL vs 其他传播 NULL vs MySQL `\|\|` 是 OR |
| CONCAT() 中的 NULL | **大** | NULL 传播阵营 vs NULL 跳过阵营 |
| COALESCE 可用性 | 无差异 | 全部支持 |
| NVL/IFNULL/ISNULL | **中** | Oracle 系 NVL vs MySQL 系 IFNULL vs SQL Server ISNULL |
| 聚合跳过 NULL | 无差异 | 全部一致 |
| NULL 排序位置 | **大** | 最小值阵营 vs 最大值阵营 |
| NULLS FIRST/LAST 语法 | **中** | MySQL/SQL Server 不支持 |
| DISTINCT/GROUP BY 中 NULL | 无差异 | 全部视 NULL 为相等 |
| 空字符串 = NULL | **大** | 仅 Oracle 及其兼容引擎 |
| NOT IN 陷阱 | 无差异 | 全部一致（全部中招） |

### 9.2 对引擎开发者的建议

1. **必须实现 `IS NOT DISTINCT FROM`**：这是 SQL:1999 标准，是 MERGE/JOIN 中 NULL 安全匹配的基础。如果目标用户群包含 MySQL 用户，同时支持 `<=>` 语法。

2. **CONCAT() 行为必须明确文档化**：NULL 传播还是 NULL 跳过，这是迁移时最容易出现静默错误的地方。建议同时提供两种语义的函数（如 `CONCAT` + `CONCAT_WS`）。

3. **NULL 排序行为必须可控**：
   - 默认行为可以选择任一阵营，但**必须支持 `NULLS FIRST/LAST` 语法**让用户控制
   - MySQL 和 SQL Server 不支持此语法是历史遗留问题，新引擎不应重蹈覆辙

4. **空字符串 vs NULL 决策**：除非你的引擎明确定位为 Oracle 兼容，否则**不要**将空字符串等同于 NULL。这个设计决策会影响整个类型系统和比较逻辑。

5. **NOT IN 子查询的 lint 警告**：当 `NOT IN (subquery)` 中的子查询列允许 NULL 时，在查询分析阶段发出警告。这比任何文档教育都有效。

6. **SUM 全 NULL 返回 NULL 的文档**：虽然这是标准行为，但大量用户预期返回 0。在文档中重点标注，并在教程中推荐 `COALESCE(SUM(col), 0)` 写法。
