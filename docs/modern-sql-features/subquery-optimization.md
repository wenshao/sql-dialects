# 子查询优化与关联子查询

子查询是 SQL 最强大也最容易写出低性能代码的特性之一。各 SQL 引擎在子查询的支持范围、优化策略、执行模式上差异巨大。本文以横向对比矩阵的形式，系统梳理 45+ 方言在子查询相关能力上的异同，供引擎开发者和跨数据库迁移项目快速参考。

**图例**：✅ = 支持 | ❌ = 不支持 | ⚠️ = 部分支持或行为特殊

> **关联文章**: LATERAL JOIN 的详细语法对比见 [lateral-join.md](lateral-join.md)；NULL 在子查询中的陷阱见 [null-handling-behavior.md](null-handling-behavior.md)。

---

## 1. 子查询分类

SQL 子查询按返回结果的形状分为四类：

| 类型 | 返回结果 | 典型位置 | 示例 |
|------|---------|---------|------|
| **标量子查询 (Scalar)** | 单行单列 | SELECT / WHERE / HAVING | `(SELECT MAX(salary) FROM emp)` |
| **列子查询 (Column)** | 多行单列 | WHERE (IN / ANY / ALL) | `(SELECT id FROM dept)` |
| **行子查询 (Row)** | 单行多列 | WHERE (行比较) | `(SELECT min_sal, max_sal FROM ranges WHERE id = 1)` |
| **表子查询 (Table)** | 多行多列 | FROM (派生表) | `(SELECT * FROM emp WHERE ...) AS t` |

### 1.1 各方言支持矩阵

| 方言 | 标量子查询 | 列子查询 | 行子查询 | 表子查询 | 备注 |
|------|-----------|---------|---------|---------|------|
| **MySQL** | ✅ | ✅ | ✅ | ✅ | 行子查询支持 `(a, b) = (SELECT ...)` |
| **MariaDB** | ✅ | ✅ | ✅ | ✅ | 同 MySQL |
| **PostgreSQL** | ✅ | ✅ | ✅ | ✅ | 行子查询支持最完整 |
| **Oracle** | ✅ | ✅ | ❌ | ✅ | 不支持行构造器比较 |
| **SQL Server** | ✅ | ✅ | ❌ | ✅ | 不支持行构造器比较 |
| **SQLite** | ✅ | ✅ | ✅ | ✅ | 3.15+ 支持行值比较 `(a, b) IN (SELECT ...)` |
| **BigQuery** | ✅ | ✅ | ✅ | ✅ | 支持 STRUCT 行比较 |
| **Snowflake** | ✅ | ✅ | ❌ | ✅ | 不支持行构造器 |
| **ClickHouse** | ✅ | ✅ | ✅ | ✅ | 支持元组比较 |
| **Hive** | ✅ | ✅ | ❌ | ✅ | 行子查询不支持 |
| **Spark SQL** | ✅ | ✅ | ✅ | ✅ | 3.0+ 支持行比较 |
| **Trino** | ✅ | ✅ | ✅ | ✅ | 支持行构造器 |
| **DuckDB** | ✅ | ✅ | ✅ | ✅ | 完整支持 |
| **Flink SQL** | ✅ | ✅ | ❌ | ✅ | 流处理下有限制 |
| **Redshift** | ✅ | ✅ | ❌ | ✅ | 基于旧版 PG |
| **DB2** | ✅ | ✅ | ✅ | ✅ | 完整支持 |
| **CockroachDB** | ✅ | ✅ | ✅ | ✅ | 兼容 PostgreSQL |
| **TiDB** | ✅ | ✅ | ✅ | ✅ | 兼容 MySQL |
| **OceanBase** | ✅ | ✅ | ✅ | ✅ | MySQL/Oracle 双模式 |
| **StarRocks** | ✅ | ✅ | ❌ | ✅ | 行子查询不支持 |
| **Doris** | ✅ | ✅ | ❌ | ✅ | 行子查询不支持 |
| **DamengDB** | ✅ | ✅ | ❌ | ✅ | 类 Oracle |
| **KingbaseES** | ✅ | ✅ | ✅ | ✅ | 类 PostgreSQL |
| **openGauss** | ✅ | ✅ | ✅ | ✅ | 类 PostgreSQL |
| **MaxCompute** | ✅ | ✅ | ❌ | ✅ | - |
| **GaussDB** | ✅ | ✅ | ✅ | ✅ | 类 PostgreSQL |
| **YugabyteDB** | ✅ | ✅ | ✅ | ✅ | 兼容 PostgreSQL |
| **SingleStore (MemSQL)** | ✅ | ✅ | ❌ | ✅ | - |
| **Greenplum** | ✅ | ✅ | ✅ | ✅ | 基于 PostgreSQL |
| **Teradata** | ✅ | ✅ | ❌ | ✅ | - |
| **Vertica** | ✅ | ✅ | ❌ | ✅ | - |
| **SAP HANA** | ✅ | ✅ | ❌ | ✅ | - |
| **Informix** | ✅ | ✅ | ❌ | ✅ | - |
| **MonetDB** | ✅ | ✅ | ✅ | ✅ | - |
| **Firebird** | ✅ | ✅ | ❌ | ✅ | - |
| **HSQLDB** | ✅ | ✅ | ✅ | ✅ | 完整支持 SQL 标准 |
| **H2** | ✅ | ✅ | ✅ | ✅ | 完整支持 |
| **Derby** | ✅ | ✅ | ❌ | ✅ | - |
| **Exasol** | ✅ | ✅ | ❌ | ✅ | - |
| **ByConity** | ✅ | ✅ | ✅ | ✅ | 基于 ClickHouse |
| **Presto** | ✅ | ✅ | ✅ | ✅ | 同 Trino |
| **Impala** | ✅ | ✅ | ❌ | ✅ | - |
| **Calcite** | ✅ | ✅ | ✅ | ✅ | 框架层面完整支持 |
| **CrateDB** | ✅ | ✅ | ❌ | ✅ | - |
| **QuestDB** | ✅ | ⚠️ | ❌ | ✅ | IN 子查询有限制 |
| **TimescaleDB** | ✅ | ✅ | ✅ | ✅ | 基于 PostgreSQL |

---

## 2. 关联子查询 vs 非关联子查询

### 2.1 概念区分

```sql
-- 非关联子查询: 子查询独立执行一次，结果被外层复用
SELECT * FROM emp WHERE salary > (SELECT AVG(salary) FROM emp);

-- 关联子查询: 子查询引用外层表的列，对外层每行重新求值
SELECT * FROM emp e WHERE salary > (SELECT AVG(salary) FROM emp WHERE dept_id = e.dept_id);
```

非关联子查询可以先执行一次、缓存结果；关联子查询在朴素实现中需要对外层每行执行一次内层查询，性能代价巨大。

### 2.2 关联子查询允许的位置

| 方言 | SELECT 列 | WHERE | HAVING | FROM (LATERAL) | ON (JOIN 条件) |
|------|----------|-------|--------|----------------|----------------|
| **PostgreSQL** | ✅ | ✅ | ✅ | ✅ (9.3+) | ✅ |
| **MySQL** | ✅ | ✅ | ✅ | ✅ (8.0.14+) | ✅ |
| **Oracle** | ✅ | ✅ | ✅ | ✅ (12c+) | ✅ |
| **SQL Server** | ✅ | ✅ | ✅ | ✅ (APPLY, 2005+) | ✅ |
| **SQLite** | ✅ | ✅ | ✅ | ❌ | ✅ |
| **BigQuery** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Snowflake** | ✅ | ✅ | ✅ | ⚠️ (FLATTEN) | ✅ |
| **ClickHouse** | ✅ | ✅ | ✅ | ❌ | ⚠️ |
| **Hive** | ⚠️ | ✅ | ❌ | ⚠️ | ❌ |
| **Spark SQL** | ✅ | ✅ | ✅ | ✅ (3.3+) | ✅ |
| **DuckDB** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Trino** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Flink SQL** | ⚠️ | ✅ | ❌ | ❌ | ❌ |

**引擎开发者要点**：关联子查询在 SELECT 列表中最常见（用于计算派生列），在 HAVING 中最少见。如果资源有限，优先支持 WHERE 中的关联子查询，其次是 SELECT 列表。

---

## 3. EXISTS vs IN vs ANY/SOME/ALL

### 3.1 语义对比

```sql
-- EXISTS: 判断子查询是否返回至少一行
SELECT * FROM dept d WHERE EXISTS (SELECT 1 FROM emp WHERE dept_id = d.dept_id);

-- IN: 判断值是否在子查询结果集中
SELECT * FROM dept WHERE dept_id IN (SELECT dept_id FROM emp);

-- ANY/SOME: 与子查询中任意一行比较为真
SELECT * FROM emp WHERE salary > ANY (SELECT salary FROM emp WHERE dept_id = 10);

-- ALL: 与子查询中所有行比较为真
SELECT * FROM emp WHERE salary > ALL (SELECT salary FROM emp WHERE dept_id = 10);
```

### 3.2 NOT IN 的 NULL 陷阱

这是 SQL 中最危险的陷阱之一：

```sql
-- 子查询返回 {10, 20, NULL}
SELECT * FROM dept WHERE dept_id NOT IN (SELECT dept_id FROM emp);
-- 结果: 空集! 即使有 dept_id = 30 的行也不会返回
```

**原因**：`30 NOT IN (10, 20, NULL)` 等价于 `30 <> 10 AND 30 <> 20 AND 30 <> NULL`。最后一项 `30 <> NULL` 返回 `UNKNOWN`，整个 AND 表达式结果为 `UNKNOWN`，不满足 WHERE 条件。

**安全替代方案**：

```sql
-- 方案 1: 用 NOT EXISTS 代替 NOT IN
SELECT * FROM dept d WHERE NOT EXISTS (SELECT 1 FROM emp WHERE dept_id = d.dept_id);

-- 方案 2: 排除 NULL
SELECT * FROM dept WHERE dept_id NOT IN (SELECT dept_id FROM emp WHERE dept_id IS NOT NULL);
```

### 3.3 各方言对 NOT IN NULL 行为的一致性

**所有方言**都遵循 SQL 标准的三值逻辑，NOT IN 遇到 NULL 时返回空集。没有任何方言对此做"安全修正"。这意味着 NOT IN + 可空列在所有引擎上都是同样危险的。

| 方言 | `NOT IN` NULL 陷阱 | 优化器警告 | 备注 |
|------|-------------------|-----------|------|
| **PostgreSQL** | ✅ 存在 | ❌ | - |
| **MySQL** | ✅ 存在 | ❌ | - |
| **Oracle** | ✅ 存在 | ❌ | - |
| **SQL Server** | ✅ 存在 | ❌ | - |
| **SQLite** | ✅ 存在 | ❌ | - |
| **BigQuery** | ✅ 存在 | ❌ | - |
| **Snowflake** | ✅ 存在 | ❌ | - |
| **ClickHouse** | ✅ 存在 | ❌ | - |
| **DuckDB** | ✅ 存在 | ❌ | - |
| **所有其他方言** | ✅ 存在 | ❌ | SQL 标准行为，无例外 |

**引擎开发者要点**：考虑在优化器或 linter 层面检测 `NOT IN` + 可空列的组合，并发出警告。这个陷阱每年导致大量生产事故。

### 3.4 ANY/SOME/ALL 支持矩阵

| 方言 | `ANY` / `SOME` | `ALL` | `= ANY` 等价 `IN` | 备注 |
|------|---------------|-------|-------------------|------|
| **PostgreSQL** | ✅ | ✅ | ✅ | 还支持 `ANY(array)` |
| **MySQL** | ✅ | ✅ | ✅ | - |
| **MariaDB** | ✅ | ✅ | ✅ | - |
| **Oracle** | ✅ | ✅ | ✅ | - |
| **SQL Server** | ✅ | ✅ | ✅ | - |
| **SQLite** | ❌ | ❌ | - | 不支持 ANY/ALL 子查询 |
| **BigQuery** | ❌ | ❌ | - | 不支持，用 IN 或 EXISTS 替代 |
| **Snowflake** | ✅ | ✅ | ✅ | - |
| **ClickHouse** | ✅ | ✅ | ✅ | - |
| **Hive** | ✅ (0.13+) | ✅ (0.13+) | ✅ | - |
| **Spark SQL** | ✅ | ✅ | ✅ | - |
| **Trino** | ✅ | ✅ | ✅ | - |
| **DuckDB** | ✅ | ✅ | ✅ | - |
| **Flink SQL** | ✅ | ❌ | ✅ | 不支持 ALL |
| **DB2** | ✅ | ✅ | ✅ | - |
| **TiDB** | ✅ | ✅ | ✅ | - |
| **CockroachDB** | ✅ | ✅ | ✅ | 兼容 PostgreSQL |
| **Redshift** | ✅ | ✅ | ✅ | - |
| **Teradata** | ✅ | ✅ | ✅ | - |

---

## 4. 子查询去关联化 (Decorrelation / Unnesting)

子查询去关联化是查询优化器最重要的变换之一。它将关联子查询改写为等价的 JOIN，避免逐行执行内层查询。

### 4.1 改写示例

```sql
-- 原始: 关联标量子查询 (逐行执行)
SELECT e.name, e.salary,
       (SELECT d.dept_name FROM dept d WHERE d.dept_id = e.dept_id) AS dept_name
FROM emp e;

-- 去关联化后: 改写为 LEFT JOIN
SELECT e.name, e.salary, d.dept_name
FROM emp e LEFT JOIN dept d ON d.dept_id = e.dept_id;
```

```sql
-- 原始: EXISTS 关联子查询
SELECT * FROM dept d WHERE EXISTS (SELECT 1 FROM emp WHERE dept_id = d.dept_id);

-- 去关联化后: 改写为 Semi-Join
SELECT d.* FROM dept d SEMI JOIN emp e ON e.dept_id = d.dept_id;
```

```sql
-- 原始: NOT EXISTS 关联子查询
SELECT * FROM dept d WHERE NOT EXISTS (SELECT 1 FROM emp WHERE dept_id = d.dept_id);

-- 去关联化后: 改写为 Anti-Join
SELECT d.* FROM dept d ANTI JOIN emp e ON e.dept_id = d.dept_id;
```

### 4.2 去关联化能力矩阵

| 方言 | 标量子查询→JOIN | EXISTS→Semi-Join | NOT EXISTS→Anti-Join | IN→Semi-Join | NOT IN→Anti-Join | 嵌套关联子查询 | 备注 |
|------|---------------|-----------------|---------------------|-------------|-----------------|-------------|------|
| **PostgreSQL** | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | 多层嵌套时有限 |
| **MySQL** | ✅ (8.0+) | ✅ (5.6+) | ✅ (8.0.17+) | ✅ (5.6+) | ✅ (8.0.17+) | ⚠️ | 5.6 引入 Semi-Join；Anti-Join 8.0.17 引入 |
| **MariaDB** | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | 10.0+ 优化大幅改进 |
| **Oracle** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **最成熟的子查询优化器** |
| **SQL Server** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 优化器非常成熟 |
| **SQLite** | ❌ | ✅ (3.35+) | ✅ (3.35+) | ✅ | ❌ | ❌ | 优化能力有限 |
| **BigQuery** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 自动去关联化大多数关联子查询 |
| **Snowflake** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 同上 |
| **ClickHouse** | ⚠️ | ✅ | ✅ | ✅ | ✅ | ❌ | 关联子查询整体支持较弱 |
| **Hive** | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ | 依赖 MapReduce 模型 |
| **Spark SQL** | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | Catalyst 优化器 |
| **Trino** | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | - |
| **DuckDB** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 基于论文的先进去关联化 (Mark Join) |
| **Flink SQL** | ⚠️ | ✅ | ✅ | ✅ | ❌ | ❌ | 流处理限制 |
| **DB2** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 成熟优化器 |
| **TiDB** | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | 基于 Calcite 理论 |
| **CockroachDB** | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | - |
| **Redshift** | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | - |
| **Teradata** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 成熟优化器 |
| **Calcite** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 框架层面提供去关联规则 |

**关键发现**：Oracle、SQL Server、DB2、Teradata 等传统商业数据库拥有最成熟的子查询去关联化能力。新兴引擎中，DuckDB 基于学术论文实现了非常先进的去关联化算法。

---

## 5. LATERAL 子查询 / CROSS APPLY / OUTER APPLY

LATERAL 允许 FROM 子句中的子查询引用同一 FROM 中前面表的列。详细语法对比见 [lateral-join.md](lateral-join.md)，这里仅列出支持矩阵。

| 方言 | 语法 | 版本 | 等价关系 |
|------|------|------|---------|
| **PostgreSQL** | `LATERAL` | 9.3+ | SQL 标准 |
| **MySQL** | `LATERAL` | 8.0.14+ | SQL 标准 |
| **MariaDB** | `LATERAL` | 10.6+ | SQL 标准 |
| **Oracle** | `LATERAL` / `CROSS APPLY` / `OUTER APPLY` | 12c+ | 双语法支持 |
| **SQL Server** | `CROSS APPLY` / `OUTER APPLY` | 2005+ | 最早实现 |
| **SQLite** | ❌ | - | 需改写为关联子查询 |
| **BigQuery** | 隐式 (UNNEST) | GA | `CROSS JOIN UNNEST(...)` |
| **Snowflake** | `LATERAL FLATTEN` | GA | 主要配合 FLATTEN |
| **ClickHouse** | `ARRAY JOIN` | 早期 | 非标准语法 |
| **Hive** | `LATERAL VIEW` | 早期 | 专用于 UDTF |
| **Spark SQL** | `LATERAL VIEW` / `LATERAL` | 3.3+ | 3.3 引入标准 LATERAL；LATERAL VIEW 早期已有 |
| **DuckDB** | `LATERAL` | 0.6.0+ | SQL 标准 |
| **Trino** | 隐式 (UNNEST) | 早期 | `CROSS JOIN UNNEST(...)` |
| **Flink SQL** | `LATERAL TABLE(...)` | 早期 | 配合 UDTF |
| **DB2** | `LATERAL` | 9.1+ | SQL 标准 |
| **CockroachDB** | `LATERAL` | 20.1+ | 兼容 PostgreSQL |
| **TiDB** | ❌ | - | 不支持 |
| **StarRocks** | ❌ | - | 不支持 |
| **Doris** | `LATERAL VIEW` | 早期 | Hive 兼容 |
| **Greenplum** | `LATERAL` | 6.0+ | 兼容 PostgreSQL |
| **Teradata** | ❌ | - | 不支持 |
| **SAP HANA** | `LATERAL` | 2.0+ | - |

---

## 6. 子查询可出现的位置

### 6.1 各位置的语义和限制

```sql
-- SELECT 列表中的子查询 (必须是标量子查询)
SELECT e.name,
       (SELECT d.name FROM dept d WHERE d.id = e.dept_id) AS dept_name
FROM emp e;

-- FROM 子句中的子查询 (派生表 / derived table)
SELECT t.avg_sal
FROM (SELECT dept_id, AVG(salary) AS avg_sal FROM emp GROUP BY dept_id) t;

-- WHERE 子句中的子查询
SELECT * FROM emp WHERE dept_id IN (SELECT id FROM dept WHERE location = 'Beijing');

-- HAVING 子句中的子查询
SELECT dept_id, COUNT(*)
FROM emp
GROUP BY dept_id
HAVING COUNT(*) > (SELECT AVG(emp_count) FROM dept_stats);
```

### 6.2 派生表限制对比

| 方言 | 必须别名 | 支持列别名 | 支持 ORDER BY | 支持 LIMIT | 备注 |
|------|---------|-----------|-------------|-----------|------|
| **PostgreSQL** | ✅ | ✅ | ✅ | ✅ | - |
| **MySQL** | ✅ | ✅ | ✅ | ✅ | - |
| **Oracle** | ❌ (可选) | ✅ | ✅ | ✅ (FETCH) | Oracle 别名可省略 |
| **SQL Server** | ✅ | ✅ | ⚠️ | ⚠️ | 无 TOP/OFFSET 时不允许 ORDER BY |
| **SQLite** | ❌ (可选) | ✅ | ✅ | ✅ | - |
| **BigQuery** | ✅ | ✅ | ✅ | ✅ | - |
| **Snowflake** | ✅ | ✅ | ✅ | ✅ | - |
| **DuckDB** | ❌ (可选) | ✅ | ✅ | ✅ | - |

**SQL Server 特殊行为**：派生表中如果没有 `TOP`、`OFFSET...FETCH` 或 `FOR XML`，则不允许使用 `ORDER BY`。这是因为 SQL Server 认为派生表是集合、没有顺序。

---

## 7. 子查询物化策略 (Materialization)

子查询物化是指将子查询结果缓存到临时结构中，避免重复计算。

### 7.1 物化策略对比

| 方言 | 自动物化 | 手动物化 (CTE) | IN 子查询物化 | Hint 控制 | 备注 |
|------|---------|--------------|-------------|----------|------|
| **PostgreSQL** | ✅ | ✅ (`MATERIALIZED`) | ✅ (Hash) | ❌ | CTE 12+ 可控制是否物化 |
| **MySQL** | ✅ (5.6+) | ✅ (8.0+, 默认物化) | ✅ | ⚠️ | `SUBQUERY=MATERIALIZATION` 优化器开关 |
| **MariaDB** | ✅ | ❌ | ✅ | ⚠️ | 类似 MySQL |
| **Oracle** | ✅ | ✅ (`MATERIALIZE` hint) | ✅ | ✅ | `/*+ MATERIALIZE */` / `/*+ INLINE */` |
| **SQL Server** | ✅ | ❌ | ✅ | ❌ | 自动决策 |
| **SQLite** | ⚠️ | ❌ | ⚠️ | ❌ | 有限的物化能力 |
| **BigQuery** | ✅ | ✅ | ✅ | ❌ | 自动优化 |
| **Snowflake** | ✅ | ✅ | ✅ | ❌ | 自动优化 |
| **ClickHouse** | ⚠️ | ❌ | ✅ | ❌ | CTE 总是内联 |
| **DuckDB** | ✅ | ✅ | ✅ | ❌ | 自适应物化 |
| **Spark SQL** | ✅ | ⚠️ | ✅ | ❌ | Broadcast / Shuffle 策略 |
| **Trino** | ✅ | ❌ | ✅ | ❌ | CTE 总是内联 |

### 7.2 IN 子查询的两种执行策略

```
策略 1: 物化 + Hash 查找
  1. 执行 IN 子查询，将结果存入 Hash Table
  2. 对外层每行，在 Hash Table 中查找
  时间复杂度: O(M) 构建 + O(N) 查找 = O(M + N)

策略 2: 转换为 Semi-Join
  1. 将 IN 改写为 Semi-Join
  2. 选择最优 JOIN 算法 (Hash / Merge / Nested Loop)
  时间复杂度: 取决于 JOIN 算法
```

大多数现代优化器会根据子查询结果集大小选择策略：结果集小时物化 + Hash 查找，结果集大时转换为 Semi-Join。

---

## 8. Semi-Join 与 Anti-Join 优化

Semi-Join 和 Anti-Join 是关系代数中的特殊连接操作，不在 SQL 标准中直接暴露语法，但优化器在处理 EXISTS / IN / NOT EXISTS / NOT IN 时广泛使用。

### 8.1 概念

```
Semi-Join (半连接): 左表中的行，只要在右表中找到至少一个匹配就保留
  等价于: WHERE EXISTS / IN
  特点: 右表的匹配行不出现在结果中，左表行不会因多个匹配而重复

Anti-Join (反连接): 左表中的行，在右表中找不到任何匹配才保留
  等价于: WHERE NOT EXISTS / NOT IN (无 NULL)
  特点: 与 Semi-Join 相反
```

### 8.2 支持矩阵

| 方言 | Semi-Join 物理算子 | Anti-Join 物理算子 | EXPLAIN 可见 | 显式语法 | 备注 |
|------|------------------|------------------|-------------|---------|------|
| **PostgreSQL** | ✅ | ✅ | ✅ | ❌ | EXPLAIN 显示 "Semi Join" / "Anti Join" |
| **MySQL** | ✅ (5.6+) | ✅ (8.0.17+) | ✅ | ❌ | `semijoin=on` / `antijoin=on` |
| **MariaDB** | ✅ | ✅ | ✅ | ❌ | - |
| **Oracle** | ✅ | ✅ | ✅ | ❌ | `/*+ SEMIJOIN */` / `/*+ ANTI_JOIN */` hint |
| **SQL Server** | ✅ | ✅ | ✅ | ❌ | EXPLAIN 显示 "Left Semi Join" 等 |
| **SQLite** | ⚠️ | ⚠️ | ❌ | ❌ | 隐式实现，不显式暴露 |
| **BigQuery** | ✅ | ✅ | ✅ | ❌ | - |
| **Snowflake** | ✅ | ✅ | ✅ | ❌ | EXPLAIN 中可见 |
| **ClickHouse** | ✅ | ✅ | ✅ | ✅ | 支持 `LEFT SEMI JOIN` / `LEFT ANTI JOIN` 语法 |
| **Hive** | ✅ | ❌ | ⚠️ | ✅ | 支持 `LEFT SEMI JOIN` 语法 |
| **Spark SQL** | ✅ | ✅ | ✅ | ✅ | `LEFT SEMI JOIN` / `LEFT ANTI JOIN` |
| **DuckDB** | ✅ | ✅ | ✅ | ✅ | `SEMI JOIN` / `ANTI JOIN` |
| **Trino** | ✅ | ✅ | ✅ | ❌ | - |
| **Flink SQL** | ✅ | ✅ | ✅ | ❌ | 通过优化器自动变换 |
| **DB2** | ✅ | ✅ | ✅ | ❌ | - |
| **TiDB** | ✅ | ✅ | ✅ | ❌ | - |
| **CockroachDB** | ✅ | ✅ | ✅ | ❌ | - |
| **StarRocks** | ✅ | ✅ | ✅ | ✅ | `LEFT SEMI JOIN` / `LEFT ANTI JOIN` |
| **Doris** | ✅ | ✅ | ✅ | ✅ | `LEFT SEMI JOIN` / `LEFT ANTI JOIN` |
| **Greenplum** | ✅ | ✅ | ✅ | ❌ | 基于 PostgreSQL |
| **Calcite** | ✅ | ✅ | ✅ | ❌ | 框架层提供优化规则 |

**显式 Semi-Join/Anti-Join 语法**是部分引擎（ClickHouse、DuckDB、Spark SQL、StarRocks、Doris、Hive）的扩展，不属于 SQL 标准。但在这些引擎中，显式语法可以让用户绕过优化器的判断，直接指定执行策略。

---

## 9. EXISTS vs IN vs JOIN 性能对比

这是 SQL 性能优化中最经典的讨论之一。

### 9.1 理论等价性

```sql
-- 以下三种写法逻辑等价（当子查询列非 NULL 时）
-- 写法 1: IN
SELECT * FROM dept WHERE dept_id IN (SELECT dept_id FROM emp);

-- 写法 2: EXISTS
SELECT * FROM dept d WHERE EXISTS (SELECT 1 FROM emp WHERE dept_id = d.dept_id);

-- 写法 3: JOIN (去重)
SELECT DISTINCT d.* FROM dept d JOIN emp e ON d.dept_id = e.dept_id;
```

### 9.2 各引擎实际行为

| 场景 | MySQL 5.x | MySQL 8.0+ | PostgreSQL | Oracle | SQL Server |
|------|-----------|------------|------------|--------|------------|
| IN (小子查询) | ⚠️ 慢 | ✅ 物化 | ✅ Hash | ✅ Hash | ✅ Hash |
| IN (大子查询) | ⚠️ 慢 | ✅ Semi-Join | ✅ Semi-Join | ✅ Semi-Join | ✅ Semi-Join |
| EXISTS | ✅ | ✅ | ✅ | ✅ | ✅ |
| JOIN + DISTINCT | ✅ | ✅ | ✅ | ✅ | ✅ |

**MySQL 5.x 的历史问题**：在 5.6 之前，MySQL 对 IN 子查询的处理极差——会将其转换为 EXISTS 关联子查询逐行执行，导致 O(N*M) 复杂度。这是当年"IN 比 EXISTS 慢"的来源。从 5.6 开始引入子查询物化，8.0 进一步引入 Semi-Join 优化，这个问题已基本解决。

### 9.3 现代引擎的推荐做法

| 场景 | 推荐写法 | 原因 |
|------|---------|------|
| 列可能为 NULL | `EXISTS` / `NOT EXISTS` | 避免 NOT IN 的 NULL 陷阱 |
| 列确定非 NULL | `IN` / `NOT IN` 或 `EXISTS` | 现代优化器等价处理 |
| 需要右表的列 | `JOIN` | 只有 JOIN 能返回右表列 |
| 需要去重 | `EXISTS` 或 `IN` | 比 `JOIN + DISTINCT` 更清晰 |
| 分布式引擎 | `EXISTS` 优先 | 一些分布式引擎对 IN 大列表优化不够 |

---

## 10. 子查询的特殊限制与方言差异

### 10.1 UPDATE/DELETE 中的子查询限制

| 方言 | UPDATE 子查询可引用目标表 | DELETE 子查询可引用目标表 | 备注 |
|------|----------------------|----------------------|------|
| **PostgreSQL** | ✅ | ✅ | - |
| **MySQL** | ❌ (8.0 前) / ✅ (8.0.19+) | ❌ (8.0 前) / ✅ (8.0.19+) | 8.0 前需用 JOIN 改写 |
| **MariaDB** | ✅ (10.3+) | ✅ (10.3+) | - |
| **Oracle** | ✅ | ✅ | - |
| **SQL Server** | ✅ | ✅ | - |
| **SQLite** | ⚠️ | ⚠️ | 某些情况下不允许 |

**MySQL 8.0 前的经典限制**：

```sql
-- MySQL 5.x 报错: You can't specify target table for update in FROM clause
UPDATE emp SET salary = salary * 1.1
WHERE dept_id IN (SELECT dept_id FROM emp WHERE salary > 10000);

-- 变通方案: 多包一层
UPDATE emp SET salary = salary * 1.1
WHERE dept_id IN (SELECT dept_id FROM (SELECT dept_id FROM emp WHERE salary > 10000) t);
```

### 10.2 关联深度限制

| 方言 | 最大关联嵌套深度 | 备注 |
|------|---------------|------|
| **PostgreSQL** | 无硬限制 | 受栈大小限制 |
| **MySQL** | 无硬限制 | 受 `thread_stack` 大小限制 |
| **Oracle** | 255 层 | 实际受优化器能力限制 |
| **SQL Server** | 32 层 | 嵌套超过 32 层报错 |
| **SQLite** | 无硬限制 | 受编译选项限制 |
| **BigQuery** | 无文档限制 | 实际约 50 层 |
| **ClickHouse** | 较浅 | 关联子查询支持本身有限 |

---

## 11. 子查询优化的执行计划分析

### 11.1 如何在 EXPLAIN 中识别子查询执行策略

```sql
-- PostgreSQL
EXPLAIN ANALYZE
SELECT * FROM dept d WHERE EXISTS (SELECT 1 FROM emp WHERE dept_id = d.dept_id);
-- 查看输出中是否有 "Semi Join"、"Hash Semi Join"、"Nested Loop Semi Join"

-- MySQL
EXPLAIN FORMAT=TREE
SELECT * FROM dept WHERE dept_id IN (SELECT dept_id FROM emp);
-- 查看输出中是否有 "semijoin"、"materialized_subquery"

-- Oracle
EXPLAIN PLAN FOR
SELECT * FROM dept WHERE dept_id IN (SELECT dept_id FROM emp);
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- 查看输出中是否有 "HASH JOIN SEMI"、"NESTED LOOPS SEMI"
```

### 11.2 EXPLAIN 输出对比

| 优化策略 | PostgreSQL | MySQL 8.0+ | Oracle | SQL Server |
|---------|------------|------------|--------|------------|
| Semi-Join (Hash) | `Hash Semi Join` | `Hash semijoin` | `HASH JOIN SEMI` | `Hash Match (Left Semi Join)` |
| Semi-Join (NL) | `Nested Loop Semi Join` | `Nested loop semijoin` | `NESTED LOOPS SEMI` | `Nested Loops (Left Semi Join)` |
| Anti-Join (Hash) | `Hash Anti Join` | `Hash antijoin` | `HASH JOIN ANTI` | `Hash Match (Left Anti Semi Join)` |
| 物化 | `Materialize` | `Materialize` | `VIEW` (内部物化) | `Table Spool` |
| 子查询扫描 | `SubPlan` | `Subquery` | `FILTER` | `Compute Scalar` |

---

## 12. 对引擎开发者的实现建议

### 12.1 子查询处理的分层架构

```
┌─────────────────────────────────────────────┐
│ Parser                                       │
│  识别子查询类型 (标量/列/行/表)                  │
│  标记关联 vs 非关联                             │
└──────────────────────┬──────────────────────┘
                       │
┌──────────────────────▼──────────────────────┐
│ Binder / Resolver                            │
│  解析关联列引用                                 │
│  确定关联深度                                   │
│  验证子查询出现位置的合法性                        │
└──────────────────────┬──────────────────────┘
                       │
┌──────────────────────▼──────────────────────┐
│ Optimizer: 子查询去关联化                       │
│  1. EXISTS → Semi-Join                       │
│  2. NOT EXISTS → Anti-Join                   │
│  3. IN → Semi-Join (或物化 + Hash 查找)        │
│  4. 标量子查询 → Left Join + 断言(最多一行)       │
│  5. 嵌套关联 → 递归去关联化                      │
└──────────────────────┬──────────────────────┘
                       │
┌──────────────────────▼──────────────────────┐
│ Executor                                     │
│  Semi-Join / Anti-Join 物理算子                 │
│  物化算子 (缓存子查询结果)                        │
│  嵌套循环回退 (无法去关联化时)                     │
└─────────────────────────────────────────────┘
```

### 12.2 实现优先级建议

如果你正在构建一个新的 SQL 引擎，以下是子查询支持的推荐实现顺序：

| 优先级 | 特性 | 原因 |
|-------|------|------|
| P0 | 非关联标量/列/表子查询 | 基础功能，用户最常用 |
| P0 | WHERE 中的 IN / EXISTS | 最常见的子查询模式 |
| P1 | EXISTS → Semi-Join 变换 | 关键性能优化 |
| P1 | IN → Semi-Join / 物化 | 关键性能优化 |
| P1 | NOT EXISTS → Anti-Join | NOT IN 的安全替代 |
| P2 | 关联标量子查询 → Left Join | SELECT 列表中的常见用法 |
| P2 | Semi-Join / Anti-Join 物理算子 | Hash / Merge / NL 三种实现 |
| P3 | 行子查询 | 使用频率较低 |
| P3 | LATERAL / CROSS APPLY | 高级特性 |
| P3 | 嵌套多层去关联化 | 复杂但罕见 |
| P4 | NOT IN → Anti-Join (NULL 安全) | NULL 处理复杂度高 |
| P4 | ANY / SOME / ALL | 使用频率最低 |

### 12.3 去关联化的关键算法

推荐参考以下学术论文和工程实践：

1. **Neumann & Kemper (2015)**: "Unnesting Arbitrary Queries" — DuckDB 的去关联化算法基于此论文，是目前最通用的方案
2. **Galindo-Legaria & Joshi (2001)**: "Orthogonal Optimization of Subqueries and Aggregation" — SQL Server 的子查询优化理论基础
3. **Seshadri et al. (1996)**: "Cost-Based Optimization for Magic: Algebra and Implementation" — 经典的 Magic Set 方法
4. **Calcite SubqueryRemoveRule**: Apache Calcite 开源实现，可直接参考代码

### 12.4 NOT IN → Anti-Join 的 NULL 安全实现

这是去关联化中最棘手的问题。NOT IN 在存在 NULL 时不能简单地转换为 Anti-Join：

```
-- NOT IN 语义 (左侧非 NULL):
x NOT IN (a, b, NULL)  =  x<>a AND x<>b AND x<>NULL  =  UNKNOWN

-- Anti-Join 语义:
左表行在右表中无匹配 → 保留

-- 差异: Anti-Join 不考虑 NULL，NOT IN 考虑
```

**正确实现**：

```
方案 1: 转换为 NOT EXISTS (推荐)
  NOT IN (SELECT col FROM t)
  → NOT EXISTS (SELECT 1 FROM t WHERE t.col = outer.col)
  前提: 如果 col 可能为 NULL，NOT EXISTS 与 NOT IN 语义不同!
  需要额外条件: NOT EXISTS (SELECT 1 FROM t WHERE t.col = outer.col)
                AND NOT EXISTS (SELECT 1 FROM t WHERE t.col IS NULL)

方案 2: Anti-Join + NULL 检查
  Anti-Join(outer.col = t.col)
  + 额外条件: 右表不含 NULL (COUNT(*) WHERE col IS NULL = 0)
  如果右表含 NULL → 直接返回空集
```

### 12.5 子查询物化的实现考虑

```
何时物化:
  - 子查询结果集小 (< 阈值行数)
  - 子查询被多次引用
  - 子查询计算代价高

何时不物化:
  - 结果集大到内存放不下
  - 子查询只执行一次
  - 可以被改写为更优的 JOIN

物化数据结构:
  - Hash Table: 适用于 IN / EXISTS 查找，O(1) 查找
  - 排序数组: 适用于 ALL / ANY 比较
  - Bloom Filter: 适用于大数据集的近似过滤 (先过滤后精确匹配)
```

### 12.6 常见实现陷阱

1. **标量子查询多行错误**：标量子查询应返回恰好一行。如果返回多行，必须报运行时错误。不要默默取第一行——这是 MySQL 早期版本的历史问题。

2. **关联列解析的作用域**：关联列引用应向外逐层查找，且只能引用直接外层或更外层的表，不能引用同层的其他子查询。

3. **去关联化的正确性验证**：每种去关联化变换都需要严格的正确性证明。特别注意：
   - NULL 值的处理
   - 空集情况下的行为（COUNT 返回 0 vs NULL）
   - 重复行的影响

4. **性能回退机制**：当去关联化后的计划比原始关联子查询更差时（例如右表极小但左表极大），应有回退机制。Oracle 和 SQL Server 的优化器会通过代价模型比较两种方案。

---

## 参考资料

- SQL:2023 标准: ISO/IEC 9075-2:2023 Section 7 (Query expressions)
- Neumann, T. & Kemper, A. (2015). "Unnesting Arbitrary Queries". BTW 2015
- Galindo-Legaria, C. & Joshi, M. (2001). "Orthogonal Optimization of Subqueries and Aggregation". SIGMOD 2001
- PostgreSQL: [Subquery Expressions](https://www.postgresql.org/docs/current/functions-subquery.html)
- MySQL: [Optimizing Subqueries](https://dev.mysql.com/doc/refman/8.0/en/subquery-optimization.html)
- Oracle: [Transforming Subqueries](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/subquery-unnesting.html)
- SQL Server: [Subquery Fundamentals](https://learn.microsoft.com/en-us/sql/relational-databases/performance/subqueries)
- DuckDB: [Correlated Subqueries](https://duckdb.org/2023/05/26/correlated-subqueries-in-sql.html)
- Apache Calcite: [SubqueryRemoveRule](https://github.com/apache/calcite/blob/main/core/src/main/java/org/apache/calcite/rel/rules/SubQueryRemoveRule.java)
