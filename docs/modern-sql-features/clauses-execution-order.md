# SELECT 子句逻辑执行顺序 (SQL Clause Logical Execution Order)

SELECT 是 SQL 中最常用的语句，但它的书写顺序 (`SELECT ... FROM ... WHERE ... GROUP BY ... HAVING ... ORDER BY ... LIMIT`) 与逻辑执行顺序完全不同。这一差异决定了：哪些列别名能在 WHERE 中使用？为什么 GROUP BY 的某些表达式不能引用 SELECT 列表？为什么 ORDER BY 几乎可以引用任何东西？45+ 引擎中，SQL 标准规定的执行顺序高度一致，但「别名可见性」却出现了惊人的方言分化——PostgreSQL 严格遵循标准、BigQuery / Snowflake / DuckDB 通过 lateral column alias 突破限制、ClickHouse 22.x 之后才有限支持 WHERE 中引用别名。本文系统梳理 SQL:1992 定义的逻辑处理模型，对比 45+ 数据库在执行顺序、别名可见性、WINDOW 子句、QUALIFY、LATERAL 等扩展上的实现差异。

## 标准与背景

### 书写顺序 vs 逻辑执行顺序

```sql
-- 书写顺序 (Lexical Order)
SELECT     <select_list>
FROM       <table_references>
WHERE      <where_predicate>
GROUP BY   <group_by_list>
HAVING     <having_predicate>
ORDER BY   <order_by_list>
LIMIT      <count> OFFSET <offset>;
```

但 SQL 引擎并不按这个顺序执行——`SELECT` 写在最前面，却几乎是最后才被求值。理解逻辑执行顺序是回答以下问题的关键：

- 为什么 `SELECT salary * 12 AS annual_salary FROM employees WHERE annual_salary > 100000;` 在 PostgreSQL 中报错 "column annual_salary does not exist"？
- 为什么 `SELECT department, COUNT(*) AS cnt FROM employees GROUP BY department HAVING cnt > 10;` 在 MySQL 中可行但在 SQL Server 中需要写成 `HAVING COUNT(*) > 10`？
- 为什么 `SELECT id, ROW_NUMBER() OVER (ORDER BY salary) AS rn FROM employees WHERE rn <= 10;` 总是报错？

### SQL:1992 定义的逻辑处理顺序

ISO/IEC 9075:1992 在 §7.10 (query specification) 与相关章节中定义了 SELECT 语句的概念性求值步骤。SQL:1999 与之后的标准继承并扩展了这一模型 (引入 WINDOW 子句、CUBE / ROLLUP 等)。逻辑顺序 (logical order) 与物理执行计划 (physical plan) 不同——后者由优化器重排，但必须保持语义等价。

```
1. FROM       -- 解析表/JOIN/子查询/LATERAL，产生原始虚拟表 (VT1)
2. WHERE      -- 行级过滤 (VT2)
3. GROUP BY   -- 按列分组 (VT3)
4. HAVING     -- 组级过滤 (VT4)
5. SELECT     -- 投影、计算表达式、窗口函数 (VT5)
   5a. 表达式求值
   5b. 窗口函数 (OVER 子句)
6. DISTINCT   -- 去重 (VT6)
7. ORDER BY   -- 排序 (VT7, 已带顺序)
8. LIMIT      -- 截取行数 (VT8)
```

> 注: 标准并未规定窗口函数的精确「时机」，但事实上的共识是 WINDOW 在 WHERE/GROUP BY/HAVING 之后、ORDER BY 之前。SQL:2003 引入的 `WINDOW` 命名子句在所有支持它的引擎中位于 HAVING 之后、ORDER BY 之前。

### 列别名可见性的标准规则

SQL 标准规定 SELECT 列表中定义的列别名 (column alias) 仅在 ORDER BY 子句中可见，因为 ORDER BY 是 SELECT 之后唯一的步骤。其他子句 (WHERE / GROUP BY / HAVING) 在 SELECT 之前求值，因此别名不可见。

```sql
-- 标准合法
SELECT salary * 12 AS annual_salary FROM employees ORDER BY annual_salary;

-- 标准非法 (但部分引擎扩展允许)
SELECT salary * 12 AS annual_salary FROM employees WHERE annual_salary > 100000;
```

这个严格规则在实践中常给用户带来困惑。多个引擎为提升可用性，通过非标准扩展放宽了别名可见性，本文将详细对比。

## 跨引擎支持矩阵

### 标准 SQL:1992 逻辑顺序遵循情况

| 引擎 | 标准顺序 | WINDOW 子句 (SQL:2003) | QUALIFY (Teradata 扩展) | 备注 |
|------|---------|------------------------|------------------------|------|
| PostgreSQL | 严格 | 是 (8.4+) | 否 | 严格遵循标准 |
| MySQL | 标准 | 是 (8.0+) | 否 | 别名扩展 (后述) |
| MariaDB | 标准 | 是 (10.2+) | 否 | 别名扩展 |
| SQLite | 标准 | 否 | 否 | -- |
| Oracle | 标准 | 否 | 否 (用 ROWNUM 子查询) | 12c 起 GROUP BY 接受别名 |
| SQL Server | 标准 | 否 (T-SQL OVER 内联) | 否 | 严格遵循标准 |
| DB2 | 标准 | 否 (LUW 扩展) | 否 | 严格遵循标准 |
| Snowflake | 标准 | 是 | 是 | LATERAL 列别名 (2023+) |
| BigQuery | 标准 | 是 | 是 | LATERAL 列别名 (2022+) |
| Redshift | 标准 | 是 | 是 (2023+) | -- |
| ClickHouse | 标准 | 否 | 是 | 别名 in WHERE 自 22.x |
| DuckDB | 标准 | 是 | 是 | LATERAL 列别名内置 |
| Trino | 标准 | 是 | 否 | -- |
| Presto | 标准 | 是 | 否 | -- |
| Spark SQL | 标准 | 是 | 是 (3.4+) | 别名扩展 |
| Hive | 标准 | 是 | 是 | -- |
| Flink SQL | 标准 | 是 | 否 | -- |
| Databricks | 标准 | 是 | 是 (DBR 11+) | 别名扩展 |
| Teradata | 标准 | 是 | 是 (原生发明者) | -- |
| Greenplum | 标准 | 是 | 否 | 继承 PG |
| CockroachDB | 标准 | 是 | 否 | -- |
| TiDB | 标准 | 是 | 否 | 兼容 MySQL |
| OceanBase | 标准 | 是 | 否 | 兼容 MySQL/Oracle |
| YugabyteDB | 标准 | 是 | 否 | 继承 PG |
| SingleStore | 标准 | 是 | 是 | -- |
| Vertica | 标准 | 是 | 否 | -- |
| Impala | 标准 | 是 | 否 | -- |
| StarRocks | 标准 | 是 | 是 (3.0+) | -- |
| Doris | 标准 | 是 | 是 | -- |
| MonetDB | 标准 | 是 | 否 | -- |
| CrateDB | 标准 | 是 | 否 | -- |
| TimescaleDB | 标准 | 是 | 否 | 继承 PG |
| QuestDB | 标准 | 是 | 否 | -- |
| Exasol | 标准 | 是 | 是 | -- |
| SAP HANA | 标准 | 是 | 否 | -- |
| Informix | 标准 | 否 | 否 | -- |
| Firebird | 标准 | 否 | 否 | -- |
| H2 | 标准 | 是 | 否 | -- |
| HSQLDB | 标准 | 是 | 否 | -- |
| Derby | 标准 | 否 | 否 | -- |
| Amazon Athena | 标准 | 是 | 否 | 继承 Trino |
| Azure Synapse | 标准 | 是 (有限) | 否 | -- |
| Google Spanner | 标准 | 是 | 否 | -- |
| Materialize | 标准 | 是 | 否 | 兼容 PG |
| RisingWave | 标准 | 是 | 否 | 兼容 PG |
| InfluxDB (SQL) | 标准 | 否 | 否 | -- |
| Yellowbrick | 标准 | 是 | 否 | -- |
| Firebolt | 标准 | 是 | 否 | -- |
| DatabendDB | 标准 | 是 | 是 | -- |

### SELECT 列别名可见性 (45+ 引擎)

> 「别名」专指 SELECT 列表中以 `AS` 命名的列别名 (column alias)，不含表别名。

| 引擎 | WHERE | GROUP BY | HAVING | ORDER BY | 版本 |
|------|-------|----------|--------|----------|------|
| PostgreSQL | 否 | 否 | 否 | 是 | 全版本 |
| MySQL | 否 | 是 | 是 | 是 | 全版本 |
| MariaDB | 否 | 是 | 是 | 是 | 全版本 |
| SQLite | 否 | 是 | 是 | 是 | 全版本 |
| Oracle | 否 | 是 (12c+) | 否 | 是 | 12c 起 GROUP BY 别名 |
| SQL Server | 否 | 否 | 否 | 是 | 全版本 |
| DB2 | 否 | 否 | 否 | 是 | 全版本 |
| Snowflake | 是 (lateral) | 是 (lateral) | 是 | 是 | 2023+ lateral |
| BigQuery | 是 | 是 | 是 | 是 | 2022+ lateral |
| Redshift | 是 (lateral) | 是 (lateral) | 是 (lateral) | 是 | 2023+ lateral |
| ClickHouse | 是 | 是 | 是 | 是 | 22.x+ (设置控制) |
| DuckDB | 是 (lateral) | 是 (lateral) | 是 (lateral) | 是 | 全版本 |
| Trino | 否 | 是 | 是 | 是 | -- |
| Presto | 否 | 是 | 是 | 是 | -- |
| Spark SQL | 是 (lateral, 3.4+) | 是 | 是 | 是 | 3.4+ lateral |
| Hive | 否 | 是 | 是 | 是 | -- |
| Flink SQL | 否 | 否 | 否 | 是 | 严格遵循 ANSI |
| Databricks | 是 (lateral, DBR 13+) | 是 | 是 | 是 | DBR 13+ lateral |
| Teradata | 否 | 是 | 是 | 是 | -- |
| Greenplum | 否 | 否 | 否 | 是 | 继承 PG |
| CockroachDB | 否 | 否 | 否 | 是 | 兼容 PG |
| TiDB | 否 | 是 | 是 | 是 | 兼容 MySQL |
| OceanBase | 否 | 是 | 是 | 是 | 兼容 MySQL |
| YugabyteDB | 否 | 否 | 否 | 是 | 继承 PG |
| SingleStore | 否 | 是 | 是 | 是 | -- |
| Vertica | 否 | 是 | 是 | 是 | -- |
| Impala | 否 | 是 | 是 | 是 | -- |
| StarRocks | 否 | 是 | 是 | 是 | 部分 lateral |
| Doris | 否 | 是 | 是 | 是 | -- |
| MonetDB | 否 | 是 | 是 | 是 | -- |
| CrateDB | 否 | 是 | 是 | 是 | -- |
| TimescaleDB | 否 | 否 | 否 | 是 | 继承 PG |
| QuestDB | 否 | 是 | 是 | 是 | -- |
| Exasol | 否 | 是 | 是 | 是 | -- |
| SAP HANA | 否 | 是 | 是 | 是 | -- |
| Informix | 否 | 否 | 否 | 是 | -- |
| Firebird | 否 | 否 | 否 | 是 | -- |
| H2 | 否 | 是 | 是 | 是 | -- |
| HSQLDB | 否 | 是 | 是 | 是 | -- |
| Derby | 否 | 否 | 否 | 是 | -- |
| Amazon Athena | 否 | 是 | 是 | 是 | 继承 Trino |
| Azure Synapse | 否 | 否 | 否 | 是 | -- |
| Google Spanner | 否 | 是 | 是 | 是 | -- |
| Materialize | 否 | 否 | 否 | 是 | 兼容 PG |
| RisingWave | 否 | 否 | 否 | 是 | 兼容 PG |
| InfluxDB (SQL) | 否 | 否 | 否 | 是 | -- |
| Yellowbrick | 否 | 否 | 否 | 是 | -- |
| Firebolt | 否 | 是 | 是 | 是 | -- |
| DatabendDB | 是 | 是 | 是 | 是 | -- |

> 统计：47 个引擎中，全部支持 ORDER BY 引用列别名；约 35 个支持 GROUP BY 引用别名；约 31 个支持 HAVING 引用别名；仅 8 个支持 WHERE 引用别名 (Snowflake、BigQuery、Redshift、ClickHouse、DuckDB、Spark 3.4+、Databricks DBR 13+、DatabendDB)。

### WINDOW 命名子句执行时机

| 引擎 | WINDOW 子句 | 求值时机 | 备注 |
|------|------------|---------|------|
| PostgreSQL | 是 | HAVING 之后, DISTINCT/ORDER BY 之前 | 标准 |
| MySQL | 是 (8.0+) | 同上 | 标准 |
| Oracle | 否 (内联 OVER) | -- | 仅支持 OVER 内联 |
| SQL Server | 否 (内联 OVER) | -- | -- |
| Snowflake | 是 | 同 PG | -- |
| BigQuery | 是 | 同 PG | -- |
| ClickHouse | 否 (内联 OVER) | -- | -- |
| DuckDB | 是 | 同 PG | -- |
| Trino | 是 | 同 PG | -- |
| Spark SQL | 是 | 同 PG | -- |

## SQL:1992 标准逻辑顺序详解

### 第 1 步: FROM (解析表与 JOIN)

```sql
SELECT name, dept, salary
FROM employees e
INNER JOIN departments d ON e.dept_id = d.id
LEFT JOIN salaries s ON e.id = s.emp_id;
```

执行步骤：

```
1.1 评估第一个表 (cross product 起点)
1.2 应用 ON 条件 (生成连接虚拟表)
1.3 处理 OUTER JOIN (添加保留侧的 NULL 行)
1.4 应用 LATERAL 子查询 (引用左侧表的相关引用)
```

关键点：

- LATERAL 子查询位于 FROM 子句中，可以引用同一 FROM 中位于其左侧的表别名 (PostgreSQL/Oracle/Snowflake/BigQuery 均支持)
- 表别名 (table alias) 在 FROM 解析后立即可见，整个查询的所有子句都可以使用
- ON 条件与 WHERE 不等价：对 OUTER JOIN，ON 中的过滤会保留外表行；WHERE 中的过滤可能丢失它们

### 第 2 步: WHERE (行级过滤)

```sql
WHERE salary > 50000 AND status = 'active'
```

- 仅引用基表列 (无别名扩展时)
- 不可包含聚合函数 (因为 GROUP BY 还未执行)
- 不可包含窗口函数 (因为 SELECT 还未执行)

非法示例：

```sql
-- 错误: WHERE 不可包含聚合函数
SELECT dept, AVG(salary) FROM employees
WHERE AVG(salary) > 50000 GROUP BY dept;

-- 错误: WHERE 不可包含窗口函数
SELECT dept, salary, ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary) rn
FROM employees WHERE rn <= 3;
```

### 第 3 步: GROUP BY (分组)

```sql
GROUP BY dept, EXTRACT(YEAR FROM hire_date)
```

- 标准要求：SELECT 列表中的非聚合列必须出现在 GROUP BY 中 (functional dependency 例外)
- 标准下 GROUP BY 仅可引用 FROM 中的基表列，不可引用 SELECT 列表别名
- MySQL/Oracle 12c+/BigQuery 等放宽了这一限制

### 第 4 步: HAVING (组级过滤)

```sql
HAVING COUNT(*) > 10 AND AVG(salary) > 50000
```

- 仅可引用 GROUP BY 列与聚合函数结果
- 标准下不可引用 SELECT 列表别名
- 不同于 WHERE：WHERE 在分组前过滤行，HAVING 在分组后过滤组

### 第 5 步: SELECT (投影与窗口函数)

```sql
SELECT dept, COUNT(*) AS cnt,
       ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
```

求值顺序细化：

```
5.1 评估非聚合表达式
5.2 评估聚合函数 (实际在 GROUP BY 阶段完成，此处仅引用结果)
5.3 评估窗口函数 (OVER 子句)
5.4 应用 AS 列别名 (此后别名才可见)
```

关键观察：窗口函数在 SELECT 阶段求值，因此可以引用 GROUP BY 后的聚合结果——`ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC)` 是合法的。

### 第 6 步: DISTINCT (去重)

```sql
SELECT DISTINCT dept FROM employees;
```

- 在 SELECT 计算之后执行
- 因此 DISTINCT 看到的是已计算的表达式值
- `SELECT DISTINCT salary * 12 AS annual FROM employees` 中 DISTINCT 基于 `salary * 12` 的结果

### 第 7 步: ORDER BY (排序)

```sql
ORDER BY annual_salary DESC, dept ASC
```

- 标准下唯一可以引用 SELECT 列别名的子句
- 也可以引用列序号 (如 `ORDER BY 1, 2`)
- 可以包含未在 SELECT 中出现的基表列 (但 DISTINCT/UNION 后的查询有限制)

### 第 8 步: LIMIT / OFFSET (截取)

```sql
LIMIT 10 OFFSET 20
```

- 在排序后取行
- 因此 `ORDER BY ... LIMIT N` 必须组合使用才能保证确定性结果
- SQL:2008 标准语法是 `OFFSET m ROWS FETCH NEXT n ROWS ONLY`，部分引擎仍只支持 `LIMIT n OFFSET m`

## 各引擎深度对比

### PostgreSQL (严格遵循标准)

PostgreSQL 是最严格遵循 SQL:1992 别名规则的主流引擎之一。SELECT 列别名仅在 ORDER BY 中可见。

```sql
-- 合法: ORDER BY 可引用别名
SELECT salary * 12 AS annual_salary
FROM employees
ORDER BY annual_salary DESC;

-- 错误: WHERE 不可引用别名 (column "annual_salary" does not exist)
SELECT salary * 12 AS annual_salary
FROM employees
WHERE annual_salary > 100000;

-- 错误: GROUP BY 不可引用别名
SELECT EXTRACT(YEAR FROM hire_date) AS hire_year, COUNT(*)
FROM employees
GROUP BY hire_year;  -- 错误

-- 正确: 重复表达式
SELECT EXTRACT(YEAR FROM hire_date) AS hire_year, COUNT(*)
FROM employees
GROUP BY EXTRACT(YEAR FROM hire_date);

-- 也可以用列序号 (PG 9.6+ 弃用警告但仍可用)
SELECT EXTRACT(YEAR FROM hire_date) AS hire_year, COUNT(*)
FROM employees
GROUP BY 1;

-- 错误: HAVING 不可引用别名
SELECT dept, COUNT(*) AS cnt FROM employees
GROUP BY dept HAVING cnt > 10;  -- 错误

-- 正确
SELECT dept, COUNT(*) AS cnt FROM employees
GROUP BY dept HAVING COUNT(*) > 10;
```

PostgreSQL 选择严格遵循标准的理由：避免歧义。例如 `SELECT a + 1 AS a FROM t WHERE a > 0` 中 `a` 究竟指基表 `a` 还是别名 `a`？标准规定基表，PG 严格执行；MySQL 允许但有解析歧义风险。

### MySQL / MariaDB (GROUP BY / HAVING 别名扩展)

MySQL 在 GROUP BY 与 HAVING 中允许引用 SELECT 列表的别名，但 WHERE 中仍然不允许。

```sql
-- 合法: GROUP BY 引用别名
SELECT YEAR(hire_date) AS hire_year, COUNT(*)
FROM employees GROUP BY hire_year;

-- 合法: HAVING 引用别名
SELECT dept, COUNT(*) AS cnt FROM employees
GROUP BY dept HAVING cnt > 10;

-- 不合法: WHERE 不可引用别名
SELECT salary * 12 AS annual_salary FROM employees
WHERE annual_salary > 100000;  -- Unknown column 'annual_salary'

-- 解决方案: 子查询包装
SELECT * FROM (
    SELECT salary * 12 AS annual_salary FROM employees
) t WHERE annual_salary > 100000;
```

为什么 WHERE 不允许？因为 WHERE 在 GROUP BY 之前求值，而别名定义在 SELECT 中。MySQL 文档明确说明：「The MySQL extension permits references to qualified column names, including aliases, in HAVING clauses, but not in WHERE clauses, because WHERE is evaluated before SELECT.」

### SQL Server (严格遵循标准)

SQL Server 与 PostgreSQL 一样严格——别名仅在 ORDER BY 中可见。

```sql
-- 合法
SELECT Salary * 12 AS AnnualSalary FROM Employees
ORDER BY AnnualSalary DESC;

-- 错误: Invalid column name 'AnnualSalary'
SELECT Salary * 12 AS AnnualSalary FROM Employees
WHERE AnnualSalary > 100000;

-- 错误: GROUP BY 不可引用别名
SELECT YEAR(HireDate) AS HireYear, COUNT(*)
FROM Employees GROUP BY HireYear;

-- 错误: HAVING 不可引用别名
SELECT Dept, COUNT(*) AS Cnt FROM Employees
GROUP BY Dept HAVING Cnt > 10;

-- 正确写法
SELECT YEAR(HireDate) AS HireYear, COUNT(*)
FROM Employees
GROUP BY YEAR(HireDate)
HAVING COUNT(*) > 10
ORDER BY HireYear;

-- 子查询/CTE 解决方案
WITH cte AS (
    SELECT Salary * 12 AS AnnualSalary FROM Employees
)
SELECT * FROM cte WHERE AnnualSalary > 100000;
```

### Oracle (12c 起 GROUP BY 接受别名)

Oracle 在 12c (12.1) 之前完全严格——别名仅在 ORDER BY 中可见。12c 起对 GROUP BY 放宽。

```sql
-- Oracle 12c+ 合法
SELECT EXTRACT(YEAR FROM hire_date) AS hire_year, COUNT(*)
FROM employees GROUP BY hire_year;

-- Oracle 11g 及之前 必须重复表达式
SELECT EXTRACT(YEAR FROM hire_date) AS hire_year, COUNT(*)
FROM employees GROUP BY EXTRACT(YEAR FROM hire_date);

-- HAVING 始终不可引用别名 (即使 12c+)
SELECT dept, COUNT(*) AS cnt FROM employees
GROUP BY dept HAVING cnt > 10;  -- Oracle 报错

-- 正确
SELECT dept, COUNT(*) AS cnt FROM employees
GROUP BY dept HAVING COUNT(*) > 10;

-- ROWNUM 用于 LIMIT 模拟
SELECT * FROM (
    SELECT * FROM employees ORDER BY salary DESC
) WHERE ROWNUM <= 10;

-- 12c+ 标准 OFFSET/FETCH
SELECT * FROM employees
ORDER BY salary DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;
```

### ClickHouse (22.x 起 WHERE 中支持别名)

ClickHouse 是少数支持 WHERE 中引用 SELECT 列表别名的引擎。该能力依赖配置项 `enable_optimize_predicate_expression`（默认开启）以及 `prefer_column_name_to_alias`（默认 0，即 alias 优先）。22.x 之后该行为更加稳定。

```sql
-- ClickHouse 合法
SELECT salary * 12 AS annual_salary
FROM employees
WHERE annual_salary > 100000;
-- 内部执行: 优化器将 annual_salary 替换为 salary * 12

-- 等价改写
SELECT salary * 12 AS annual_salary
FROM employees
WHERE salary * 12 > 100000;

-- GROUP BY/HAVING 也支持别名
SELECT toYear(hire_date) AS hire_year, count() AS cnt
FROM employees
GROUP BY hire_year
HAVING cnt > 10;

-- WITH 子句的别名作用域更广 (ClickHouse 扩展)
WITH salary * 12 AS annual_salary
SELECT * FROM employees
WHERE annual_salary > 100000;

-- 配置项控制
SET prefer_column_name_to_alias = 0;  -- alias 优先 (默认)
SET prefer_column_name_to_alias = 1;  -- 列名优先 (与标准对齐)
```

ClickHouse 在 SELECT 列表中定义的别名作为「逻辑列」处理——优化器在抽象语法树 (AST) 阶段将其替换为表达式。这使得别名几乎在所有子句中都可见。

### BigQuery (LATERAL 列别名)

BigQuery 在 2022 年正式 GA 了「LATERAL column alias」（也称 lateral aliasing），允许 SELECT 列表中早定义的别名被同一 SELECT 列表中后定义的表达式以及 WHERE / GROUP BY / HAVING 引用。

```sql
-- BigQuery 合法: WHERE 引用别名
SELECT salary * 12 AS annual_salary
FROM `project.dataset.employees`
WHERE annual_salary > 100000;

-- 同一 SELECT 列表中后续表达式可引用前面的别名
SELECT salary * 12 AS annual_salary,
       annual_salary * 0.3 AS estimated_tax,
       estimated_tax / annual_salary AS tax_rate
FROM employees;

-- GROUP BY 引用别名
SELECT EXTRACT(YEAR FROM hire_date) AS hire_year, COUNT(*) AS cnt
FROM employees
GROUP BY hire_year
HAVING cnt > 10
ORDER BY hire_year;

-- 与 QUALIFY 配合使用 (窗口函数过滤)
SELECT name, dept, salary,
       ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC) AS rn
FROM employees
QUALIFY rn <= 3;
```

LATERAL 列别名规则：

- 同一 SELECT 列表中，可以引用前面定义的别名
- 不能形成循环引用 (`a AS x, x AS a` 错误)
- 别名优先级高于基表列名 (避免歧义可加表前缀)

### Snowflake (2023 起 LATERAL 列别名)

Snowflake 在 2023 年通过预览版引入 lateral column reference，2024 年初 GA。

```sql
-- Snowflake 合法
SELECT salary * 12 AS annual_salary
FROM employees
WHERE annual_salary > 100000;

-- 同 SELECT 列表内引用
SELECT amount AS gross,
       amount * 0.85 AS net,
       gross - net AS tax
FROM invoices;

-- 与 QUALIFY 结合
SELECT name, dept, salary,
       ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC) AS rn
FROM employees
QUALIFY rn <= 5;

-- 配置项: 控制别名优先级
ALTER SESSION SET ENABLE_LATERAL_COLUMN_ALIAS = TRUE;  -- 启用
```

> 注：在 Snowflake 启用 lateral column alias 之前，用户必须用 CTE 或子查询包装才能在 WHERE 中引用别名。

### DuckDB (内置 LATERAL 列别名)

DuckDB 从早期版本就支持 lateral column reference，是别名可见性最宽松的引擎之一。

```sql
-- DuckDB 全部合法
SELECT salary * 12 AS annual_salary,
       annual_salary * 0.85 AS post_tax
FROM employees
WHERE annual_salary > 100000
GROUP BY post_tax > 50000
HAVING COUNT(*) > 5
QUALIFY ROW_NUMBER() OVER () < 100
ORDER BY annual_salary DESC;

-- 在子查询中也可使用
SELECT * FROM (
    SELECT date_trunc('month', order_date) AS month,
           SUM(amount) AS total,
           total / COUNT(*) AS avg_per_order
    FROM orders
    GROUP BY month
) t WHERE total > 10000;
```

DuckDB 设计哲学：「可读性优先」，遵循「最小惊讶原则」。

### Spark SQL / Databricks (3.4+ LATERAL 列别名)

Apache Spark 3.4 (2023 年 4 月) 引入 lateral column alias 解析。Databricks DBR 11+ 也支持 QUALIFY，DBR 13+ 支持 WHERE 中的 lateral alias。

```sql
-- Spark 3.4+ / Databricks DBR 13+ 合法
SELECT salary * 12 AS annual_salary
FROM employees
WHERE annual_salary > 100000;

-- 多别名链式引用
SELECT col1 + col2 AS total,
       total * 1.08 AS with_tax,
       with_tax - col1 AS markup
FROM sales;

-- 与 QUALIFY 配合
SELECT *, ROW_NUMBER() OVER (ORDER BY ts) AS rn
FROM events QUALIFY rn = 1;

-- 配置项: spark.sql.lateralColumnAlias.enableImplicitResolution = true
SET spark.sql.lateralColumnAlias.enableImplicitResolution = true;
```

### Redshift (2023 起 LATERAL 列别名)

Amazon Redshift 在 2023 年加入了 lateral column alias 支持，需要确保集群版本足够新。

```sql
-- Redshift 合法 (2023+)
SELECT order_total * 0.05 AS tax,
       order_total + tax AS total_with_tax
FROM orders
WHERE total_with_tax > 1000;

-- 与 QUALIFY 结合
SELECT user_id, login_ts,
       ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY login_ts DESC) AS rn
FROM logins
QUALIFY rn = 1;
```

### Trino / Presto (GROUP BY/HAVING 但 WHERE 否)

Trino 在 GROUP BY 与 HAVING 中接受 SELECT 列别名，但 WHERE 不允许。

```sql
-- Trino 合法
SELECT EXTRACT(YEAR FROM hire_date) AS hire_year, COUNT(*) AS cnt
FROM employees
GROUP BY hire_year
HAVING cnt > 10
ORDER BY hire_year;

-- Trino 错误
SELECT salary * 12 AS annual_salary FROM employees
WHERE annual_salary > 100000;  -- column not found

-- 解决方案: 子查询
SELECT * FROM (
    SELECT salary * 12 AS annual_salary FROM employees
) WHERE annual_salary > 100000;

-- 或 CTE
WITH t AS (SELECT salary * 12 AS annual_salary FROM employees)
SELECT * FROM t WHERE annual_salary > 100000;
```

## LATERAL 列别名深度剖析

LATERAL 列别名 (lateral column alias)，又称 lateral column reference，是对标准的扩展，允许 SELECT 列表中早定义的别名被同一列表中后续表达式以及其他子句引用。

### 名称由来

「LATERAL」一词借自 SQL 标准的 `LATERAL` 关键字（用于 FROM 子句中的相关子查询），形象地描述了「向左侧已定义的列引用」这一特性。但请注意：FROM 子句的 `LATERAL` 与 SELECT 列别名是两个不同的概念，只是命名上的类比。

### 标准 SQL 不支持的根因

```sql
-- 假设 PG 支持 lateral alias
SELECT a + 1 AS a, a * 2 AS b FROM t;
-- a * 2 中的 a 究竟指：
--   (1) 基表 t.a？
--   (2) 别名 a (即 t.a + 1)？
-- 标准选择 (1)，避免歧义
```

为消除歧义，标准要求别名仅在 ORDER BY 中可见——因为 ORDER BY 在 SELECT 之后，不存在这种歧义。但代价是：用户必须在多处重复同样的复杂表达式。

### 实现策略

引擎通过下列策略支持 lateral alias：

```
1. 名称解析阶段:
   优先在 FROM 子句的列中查找
   找不到时，查找 SELECT 列表中已定义的别名
   仍找不到才报错

2. 替换阶段:
   将 SELECT 列别名引用替换为对应表达式
   保留对基表列的引用

3. 循环检测:
   构建别名依赖图
   检测循环引用并报错
```

### BigQuery 的实现

```sql
-- 步骤 1: 表达式 a 解析为 col1 + 1
-- 步骤 2: 表达式 b 解析为 a * 2，
--          其中 a 被替换为 (col1 + 1)
-- 步骤 3: WHERE 中的 a 也被替换为 (col1 + 1)
SELECT col1 + 1 AS a, a * 2 AS b FROM t WHERE a > 0;

-- 等价于
SELECT col1 + 1 AS a, (col1 + 1) * 2 AS b FROM t WHERE (col1 + 1) > 0;
```

### Snowflake 的实现

Snowflake 通过会话级配置 `ENABLE_LATERAL_COLUMN_ALIAS` 控制：

```sql
ALTER SESSION SET ENABLE_LATERAL_COLUMN_ALIAS = TRUE;

SELECT amount * 1.1 AS marked_up,
       marked_up - amount AS markup_amount,
       markup_amount / amount AS markup_rate
FROM products;
```

启用后，引擎在解析 AST 时将后续表达式中的别名引用替换为前置表达式，并在 WHERE/GROUP BY/HAVING 中应用相同规则。

### DuckDB 的处理

DuckDB 默认启用 lateral alias，没有专门配置项：

```sql
-- DuckDB 直接可用
SELECT date_trunc('month', ts) AS month,
       SUM(amount) AS total,
       total - LAG(total) OVER (ORDER BY month) AS mom_change
FROM transactions
WHERE month > '2024-01-01'
GROUP BY month;
```

### 循环引用检测

```sql
-- 错误: 循环引用
SELECT a + 1 AS x, x + 1 AS a FROM t;
-- 多数引擎报错: circular alias reference

-- 错误: 自引用
SELECT col1 AS col1 FROM t;  -- 严格模式下歧义
-- 大多数引擎将 col1 解析为基表列, 别名同名
```

## WINDOW 子句执行时机

SQL:2003 引入命名 `WINDOW` 子句，允许将窗口定义提取出来供多个窗口函数复用。

### 语法

```sql
SELECT
    name,
    AVG(salary) OVER w1 AS dept_avg,
    MAX(salary) OVER w1 AS dept_max,
    SUM(salary) OVER w2 AS company_total
FROM employees
WHERE status = 'active'
GROUP BY dept, name, salary, status
HAVING COUNT(*) >= 1
WINDOW
    w1 AS (PARTITION BY dept ORDER BY hire_date),
    w2 AS ()
ORDER BY name;
```

### 执行时机

WINDOW 子句虽然书写在 HAVING 之后、ORDER BY 之前，但其求值时机紧随 SELECT 阶段：

```
1. FROM
2. WHERE       (基表过滤)
3. GROUP BY    (分组聚合)
4. HAVING      (组级过滤)
5. SELECT
   5a. 标量表达式
   5b. 聚合函数 (引用 GROUP BY 结果)
   5c. 窗口函数 (使用 WINDOW 子句中的命名定义)
   5d. 别名分配
6. DISTINCT
7. ORDER BY    (可引用别名 + 窗口函数结果)
8. LIMIT
```

### 各引擎支持

```sql
-- PostgreSQL 完整支持
SELECT
    dept, name, salary,
    AVG(salary) OVER (w) AS avg_salary,
    RANK() OVER (w) AS rank_within_dept
FROM employees
WINDOW w AS (PARTITION BY dept ORDER BY salary DESC);

-- MySQL 8.0+ 支持
SELECT
    dept, name, salary,
    AVG(salary) OVER w AS avg_salary
FROM employees
WINDOW w AS (PARTITION BY dept);

-- BigQuery 支持
SELECT
    dept, name, salary,
    AVG(salary) OVER w AS avg_salary
FROM employees
WINDOW w AS (PARTITION BY dept ORDER BY salary);

-- DuckDB 支持
SELECT
    *, ROW_NUMBER() OVER w AS rn,
    LAG(salary, 1) OVER w AS prev_salary
FROM employees
WINDOW w AS (PARTITION BY dept ORDER BY hire_date);

-- Snowflake 支持
SELECT name,
       SUM(amount) OVER w1 AS running_total,
       AVG(amount) OVER w1 AS running_avg
FROM transactions
WINDOW w1 AS (PARTITION BY user_id ORDER BY ts);

-- SQL Server 不支持命名 WINDOW
-- 必须内联 OVER 子句
SELECT name,
       SUM(amount) OVER (PARTITION BY user_id ORDER BY ts) AS running_total,
       AVG(amount) OVER (PARTITION BY user_id ORDER BY ts) AS running_avg
FROM transactions;

-- Oracle 不支持命名 WINDOW (截至 23ai 仍未实现)
-- ClickHouse 不支持命名 WINDOW
```

### WINDOW 链式继承

支持命名 WINDOW 的引擎大多允许窗口定义之间的部分继承：

```sql
-- PostgreSQL / MySQL 8.0+
SELECT
    dept, name, salary,
    SUM(salary) OVER w_dept AS dept_total,
    SUM(salary) OVER w_dept_year AS dept_year_total
FROM employees
WINDOW
    w_dept AS (PARTITION BY dept),
    w_dept_year AS (w_dept ORDER BY EXTRACT(YEAR FROM hire_date) RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);
```

### 窗口函数与 WHERE/GROUP BY 的交互

窗口函数在 SELECT 阶段求值，因此：

- 窗口函数无法在 WHERE 中使用 (WHERE 在 SELECT 之前)
- 窗口函数无法在 GROUP BY 中使用 (同上)
- 窗口函数无法在 HAVING 中使用 (在 SELECT 之前)
- 窗口函数可以在 ORDER BY 中使用 (在 SELECT 之后)
- 引擎专门发明了 QUALIFY 子句来过滤窗口函数结果

```sql
-- 错误: WHERE 中使用窗口函数
SELECT name, ROW_NUMBER() OVER (ORDER BY salary) AS rn
FROM employees
WHERE rn <= 10;

-- 正确: 子查询包装
SELECT * FROM (
    SELECT name, salary,
           ROW_NUMBER() OVER (ORDER BY salary) AS rn
    FROM employees
) t WHERE rn <= 10;

-- 更优雅: QUALIFY (Teradata/BigQuery/Snowflake/DuckDB/Spark/ClickHouse)
SELECT name, salary,
       ROW_NUMBER() OVER (ORDER BY salary) AS rn
FROM employees
QUALIFY rn <= 10;
```

### QUALIFY 子句的执行时机

QUALIFY 由 Teradata 发明，逻辑上位于 SELECT 与 ORDER BY 之间，与 HAVING 类似但作用于窗口函数：

```
1. FROM
2. WHERE
3. GROUP BY
4. HAVING
5. SELECT (包含窗口函数)
6. QUALIFY     <- 在此过滤窗口函数结果
7. DISTINCT
8. ORDER BY
9. LIMIT
```

```sql
-- Teradata / BigQuery / Snowflake / DuckDB / Spark 3.4+ / ClickHouse
SELECT product_id, sale_date, amount,
       ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY sale_date DESC) AS rn,
       SUM(amount) OVER (PARTITION BY product_id) AS product_total
FROM sales
QUALIFY rn = 1 AND product_total > 1000;
```

## 别名作用域的深层语义

### 列别名 vs 表别名

```sql
SELECT e.name AS employee_name,         -- 列别名
       d.name AS department_name        -- 列别名
FROM employees AS e                      -- 表别名
JOIN departments AS d ON e.dept_id = d.id;
```

- 表别名 (e, d) 在 FROM 之后立即对所有子句可见
- 列别名 (employee_name, department_name) 仅在 SELECT 之后可见 (标准下仅 ORDER BY)

### CTE 别名 vs 派生表别名

```sql
-- CTE 列别名: 类似表别名，对整个查询可见
WITH summary AS (
    SELECT dept, AVG(salary) AS avg_salary FROM employees GROUP BY dept
)
SELECT * FROM summary WHERE avg_salary > 50000;
-- ^^^ summary 与 avg_salary 都可在 WHERE 中使用

-- 派生表（子查询）的列别名也类似
SELECT * FROM (
    SELECT dept, AVG(salary) AS avg_salary FROM employees GROUP BY dept
) t WHERE avg_salary > 50000;
```

为什么 CTE 与派生表内部的别名可以被外层 WHERE 使用？因为它们已经物化（或被视为）一个完整的虚拟表，其列对外层来说是「基表列」。

### USING 与 JOIN 中的别名

```sql
-- USING 子句创建的隐式列, 对整个查询可见
SELECT id, name, salary  -- id 来自 USING(id)
FROM employees
JOIN salaries USING(id);

-- NATURAL JOIN 同理
```

## 设计争议与实现差异

### 为什么 PostgreSQL 不支持 WHERE 中的别名？

PostgreSQL 团队多次拒绝支持 WHERE 中的别名扩展，理由：

1. **歧义风险**: `SELECT a + 1 AS a FROM t WHERE a > 0` 中 a 指什么？
2. **可移植性**: 标准 SQL 强制使用基表列，添加扩展会让用户写出不可移植的查询
3. **替代方案**: 子查询 / CTE / LATERAL 已能优雅解决
4. **优化器复杂度**: 别名引用需要在多个阶段维护「展开」状态

### MySQL 的妥协

MySQL 对 WHERE 不放宽，但允许 GROUP BY/HAVING——因为：

- GROUP BY 后聚合函数已计算，引用 SELECT 别名（如 `cnt`）有明确语义（指 SELECT 中的 COUNT）
- HAVING 同理
- WHERE 在 GROUP BY 之前，引用 `AVG(salary) AS avg_s` 别名会引发「聚合函数在 WHERE 中」的错误

### BigQuery / Snowflake 的现代化扩展

云原生分析型数据库选择放宽 WHERE 中的别名限制，理由：

1. **用户体验**: 大量 SQL 用户期望「书写顺序 = 视觉顺序」
2. **简化复杂查询**: 减少嵌套子查询/CTE 的需要
3. **与现代分析工作流契合**: dbt / Looker 等工具生成的 SQL 大量使用别名链
4. **优化器在 SQL → 物理计划之间的语义保持**: 替换为表达式后语义不变

### ClickHouse 的设计哲学

ClickHouse 将 SELECT 别名视为「逻辑列」——这与传统 OLTP 引擎的「Project 算子在 Filter 之后」不同。在 ClickHouse 中，SELECT 列表更像 SQL 的「列定义」，可以在任何子句中引用。代价：必须做谨慎的歧义处理（通过 `prefer_column_name_to_alias` 配置）。

### Apache Spark 的演进

Spark 3.4 (2023.04) 引入 lateral column alias 是社区长期讨论的结果。SPARK-27551 [Common subexpression elimination] 与 SPARK-40925 [Add lateral alias] 推动了这一变化。背景：Spark SQL 用户大量使用 dbt 等工具，dbt 的「Jinja 模板 → SQL」生成模式高度依赖别名重用。

## 实际场景中的「错误」与「正确」对比

### 场景 1: 计算列过滤

```sql
-- 错误 (PG/SQL Server/Oracle/Trino/MySQL): WHERE 中使用别名
SELECT order_id, amount * 1.1 AS amount_with_tax
FROM orders
WHERE amount_with_tax > 100;
```

```sql
-- 正确: 重复表达式
SELECT order_id, amount * 1.1 AS amount_with_tax
FROM orders
WHERE amount * 1.1 > 100;

-- 正确: 子查询
SELECT * FROM (
    SELECT order_id, amount * 1.1 AS amount_with_tax FROM orders
) t WHERE amount_with_tax > 100;

-- 正确: CTE (清晰但稍复杂)
WITH t AS (SELECT order_id, amount * 1.1 AS amount_with_tax FROM orders)
SELECT * FROM t WHERE amount_with_tax > 100;
```

```sql
-- BigQuery / Snowflake / Redshift / DuckDB / Spark 3.4+ / ClickHouse
SELECT order_id, amount * 1.1 AS amount_with_tax
FROM orders
WHERE amount_with_tax > 100;  -- 直接可用
```

### 场景 2: 分组列别名

```sql
-- PG 错误, MySQL/Oracle 12c+/BigQuery/Snowflake 合法
SELECT EXTRACT(YEAR FROM created_at) AS yr, COUNT(*) AS cnt
FROM events GROUP BY yr;

-- 通用正确写法
SELECT EXTRACT(YEAR FROM created_at) AS yr, COUNT(*) AS cnt
FROM events GROUP BY EXTRACT(YEAR FROM created_at);

-- 列序号 (大多数引擎支持但已弃用警告)
SELECT EXTRACT(YEAR FROM created_at) AS yr, COUNT(*) AS cnt
FROM events GROUP BY 1;
```

### 场景 3: 窗口函数过滤

```sql
-- 错误 (所有引擎): WHERE 中使用窗口函数
SELECT *, ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC) AS rn
FROM employees WHERE rn <= 3;
```

```sql
-- 通用正确: 子查询
SELECT * FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC) AS rn
    FROM employees
) t WHERE rn <= 3;

-- 或 CTE
WITH ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC) AS rn
    FROM employees
)
SELECT * FROM ranked WHERE rn <= 3;

-- QUALIFY (Teradata/BigQuery/Snowflake/DuckDB/Spark 3.4+/ClickHouse/StarRocks 3.0+)
SELECT *, ROW_NUMBER() OVER (PARTITION BY dept ORDER BY salary DESC) AS rn
FROM employees QUALIFY rn <= 3;
```

### 场景 4: 多次引用同一表达式

```sql
-- 标准 SQL 必须重复
SELECT date_trunc('month', ts) AS month, COUNT(*) AS cnt
FROM events
WHERE date_trunc('month', ts) >= '2024-01-01'
  AND date_trunc('month', ts) <  '2025-01-01'
GROUP BY date_trunc('month', ts)
ORDER BY date_trunc('month', ts);

-- 支持别名扩展的引擎: 简洁
SELECT date_trunc('month', ts) AS month, COUNT(*) AS cnt
FROM events
WHERE month >= '2024-01-01' AND month < '2025-01-01'
GROUP BY month
ORDER BY month;
```

## 对引擎开发者的实现建议

### 1. 解析阶段的别名注册

```
SELECT 列表解析时:
  for expr, alias in select_list:
    register_alias(alias, expr)        // 别名 -> AST 节点

WHERE/GROUP BY/HAVING 解析时:
  if engine 支持 lateral alias:
    在 column_resolution 阶段:
      1. 优先在 FROM 列中查找
      2. 找不到则在 alias map 中查找
      3. 仍找不到才报错
  else:
    严格在 FROM 列中查找
```

### 2. 替换策略

```
名称解析后, 在生成逻辑计划前:
  for ref in references_to_aliases:
    替换 ref 为 alias_map[ref.name] 的副本

注意:
  - 必须深拷贝表达式树 (避免共享导致的优化错误)
  - 处理嵌套别名引用 (a -> b -> c 的链)
  - 检测并报错循环引用
```

### 3. 循环引用检测

```
构建别名依赖图:
  for alias, expr in select_list_aliases:
    for ref in expr.column_refs:
      if ref.name in alias_map:
        edges.add(alias -> ref.name)

if has_cycle(edges):
  raise "circular alias reference"

否则: 拓扑排序后按顺序展开
```

### 4. 优化器的下推规则

```
WHERE 中引用别名时:
  - 替换为表达式后再考虑下推到 SCAN 算子
  - 只有当替换后的表达式仅引用基表列时才能下推
  - 如果表达式包含子查询或 LATERAL, 不可下推

GROUP BY 中引用别名时:
  - 必须在分组前完成替换
  - 替换后的表达式参与分组键计算

ORDER BY 中引用别名时:
  - 别名指向 SELECT 输出列, 直接复用计算结果
  - 无需下推或重新计算
```

### 5. WINDOW 子句的执行管道

```
执行计划构建:
  Scan -> Filter (WHERE) -> Aggregate (GROUP BY) -> Filter (HAVING)
        -> Project (聚合表达式) -> Window (窗口函数)
        -> Filter (QUALIFY) -> Distinct -> Sort (ORDER BY) -> Limit

WINDOW 命名子句:
  在 Project 阶段将 OVER w 引用替换为命名定义
  多个引用同一窗口可共享 Window 算子 (节省排序成本)

链式继承 (PG/MySQL):
  WINDOW w1 AS (...), w2 AS (w1 ...) {
    解析 w2 时, 合并 w1 的 PARTITION/ORDER, 添加 w2 的新增子句
  }
```

### 6. QUALIFY 的实现

```
QUALIFY 在逻辑上位于 Window 算子之后:
  Project (含窗口函数) -> Filter (QUALIFY 谓词) -> ...

实际优化:
  - 当 QUALIFY 谓词仅依赖窗口函数结果时, 可与 Window 算子合并
  - 当谓词形式为 ROW_NUMBER() <= K 时, 可优化为 Top-K 算子
  - PARTITION BY 子句允许分区级 Top-K 并行
```

### 7. 错误信息的友好性

```
当用户在 WHERE 中引用 SELECT 别名而引擎不支持时:
  优秀的引擎应:
    1. 检测到 SELECT 列表中存在同名别名
    2. 错误信息提示: "column not found, did you mean to reference SELECT alias 'X'?
       In this engine, aliases are only visible in ORDER BY. Use a subquery or CTE."
    3. 区分 "完全未知的列" 与 "别名误用" 两种情况

PostgreSQL 错误示例:
  ERROR: column "annual_salary" does not exist
  HINT: There is a column named "annual_salary" in the SELECT list, but
        it cannot be referenced from here. Use the underlying expression instead.
```

### 8. 测试要点

```
- 标准顺序: 验证 SQL:1992 定义的 8 步逻辑顺序
- 别名可见性: 4 个子句 × 引擎特性 = 完整测试矩阵
- 同名歧义: 别名与基表列同名时的解析优先级
- 循环引用: a → b, b → a 必须报错
- 嵌套引用: a → b → c → d 链式展开
- WINDOW 执行时机: 验证窗口函数在 HAVING 之后求值
- QUALIFY 测试: 验证窗口函数过滤的正确性
- 子查询/CTE 中别名作用域: 内层别名不应泄漏到外层
- LATERAL 子查询: 验证 FROM 中相关引用的解析
```

## 性能影响分析

### 表达式重复计算

```sql
-- 不支持 lateral alias 的引擎需重复表达式
SELECT date_trunc('day', ts) AS day, COUNT(*)
FROM events
WHERE date_trunc('day', ts) >= '2024-01-01'
GROUP BY date_trunc('day', ts);
-- 优化器多数能识别公共子表达式 (CSE), 仅计算一次
```

```sql
-- 支持 lateral alias 的引擎: 别名替换后等价
SELECT date_trunc('day', ts) AS day, COUNT(*)
FROM events
WHERE day >= '2024-01-01'
GROUP BY day;
-- 解析后等价于上面, 性能相同
```

### 子查询包装的开销

```sql
-- 大多数引擎将派生表「展平」(view inlining/subquery unfolding)
-- 不会真正物化中间结果
SELECT * FROM (
    SELECT salary * 12 AS annual FROM employees
) t WHERE annual > 100000;

-- 等价于
SELECT salary * 12 AS annual FROM employees WHERE salary * 12 > 100000;
```

### CTE 的语义边界

```sql
-- 标准 CTE 是 optimization fence (Oracle/PG <= 11)
WITH cte AS (SELECT * FROM huge_table WHERE x > 0)
SELECT * FROM cte WHERE y > 100;
-- 老版本 PG 可能物化 cte, 性能差

-- PG 12+ 支持 NOT MATERIALIZED 提示
WITH cte AS NOT MATERIALIZED (...) SELECT ...;
-- 优化器可将 cte 内联展开
```

## 与其他语言/标准的对比

### 数据流式语言 (PRQL / Malloy)

PRQL 与 Malloy 等新兴查询语言的设计目标之一就是让书写顺序 = 执行顺序：

```
# PRQL
from employees
filter salary > 50000               # 类似 WHERE
group department (
    aggregate avg_salary = average salary
)
filter avg_salary > 80000           # 类似 HAVING (但用别名直接)
sort -avg_salary                    # 类似 ORDER BY
take 10                             # 类似 LIMIT
```

PRQL 编译为标准 SQL，在编译过程中处理别名作用域问题。

### Pandas 风格 (Method Chaining)

```python
df.query("salary > 50000")
  .groupby("department")
  .agg(avg_salary=("salary", "mean"))
  .query("avg_salary > 80000")
  .sort_values("avg_salary", ascending=False)
  .head(10)
```

DataFrame API 也是「书写顺序 = 执行顺序」，且每一步都可以引用前一步定义的列名。这正是 SQL 的别名扩展所要追赶的体验。

## 关键发现

1. **SQL:1992 定义的 8 步逻辑顺序在所有 47 个引擎中保持一致**——这是 SQL 长期稳定的最重要根基。物理计划可重排，但语义必须保持。

2. **别名可见性是引擎差异最大的扩展点**：
   - 全部引擎在 ORDER BY 中支持别名 (标准要求)
   - 约 35 个引擎在 GROUP BY 中支持别名 (大多数 OLAP 引擎放宽)
   - 约 31 个引擎在 HAVING 中支持别名
   - 仅 7 个引擎在 WHERE 中支持别名 (BigQuery/Snowflake/Redshift/ClickHouse/DuckDB/Spark 3.4+/Databricks DBR 13+)

3. **PostgreSQL 与 SQL Server 是「最严格」的代表**：仅 ORDER BY 支持别名，其他子句必须重复表达式。这种严格性源于对标准的尊重和对歧义的规避。

4. **MySQL 走「中间路线」**：GROUP BY/HAVING 接受别名，但 WHERE 不接受——因为 WHERE 在 GROUP BY 之前。这是 MySQL 用户常踩的坑。

5. **云原生分析数据库 (BigQuery/Snowflake/Databricks) 集体放宽 WHERE 中的别名限制**——「LATERAL column alias」是 2022-2024 年的明显趋势，反映了用户对开发体验的强烈需求。

6. **ClickHouse 的设计独特**——别名几乎在所有子句中可见，源于其「SELECT 列表是逻辑列定义」的语义模型。配置项 `prefer_column_name_to_alias` 可控制歧义解析。

7. **DuckDB 是「现代 SQL」体验的标杆**：默认启用 lateral alias、QUALIFY、SELECT * EXCLUDE/REPLACE 等特性，体现了「最小惊讶原则」。

8. **WINDOW 命名子句是 SQL:2003 中被严重低估的特性**——能显著简化窗口函数的复用。但 SQL Server / Oracle / ClickHouse 至今仍未支持。

9. **QUALIFY 由 Teradata 发明 (1990 年代)，2020 年后被云数据库集体采纳**——它优雅解决了「窗口函数过滤」的痛点，是 SQL 演进的成功案例。

10. **Apache Spark 3.4 (2023) 与 Snowflake (2023) 同时引入 lateral column alias** 表明云数据仓库竞争压力推动了 SQL 方言的现代化。

11. **Oracle 12c (2013) 在 GROUP BY 中接受别名，但 HAVING 至今仍不接受**——折射出 Oracle 在版本兼容性与现代化之间的谨慎平衡。

12. **错误信息的友好程度差异很大**：PostgreSQL 给出明确的 "column does not exist" 提示但不主动提示用户检查 SELECT 别名；现代引擎应增强错误诊断，提示用户使用子查询或 CTE。

13. **CTE/派生表是最通用的「别名作用域升级」工具**——将子查询的 SELECT 列别名提升为「外层基表列」，从而可以在外层 WHERE/GROUP BY 中使用。这一模式跨所有引擎通用。

14. **EXISTS/IN 子查询中的相关引用** 不属于 SELECT 别名作用域问题，而是 LATERAL 语义。所有支持子查询的引擎都允许子查询引用外层 FROM 中的表别名。

15. **流处理引擎 (Flink SQL) 严格遵循 ANSI 标准**——别名仅 ORDER BY 可见，因为流处理对语义确定性的要求更严格。

16. **配置驱动的别名行为** 是新兴模式：Snowflake 的 `ENABLE_LATERAL_COLUMN_ALIAS`、ClickHouse 的 `prefer_column_name_to_alias`、Spark 的 `spark.sql.lateralColumnAlias.enableImplicitResolution` 都允许用户/管理员调整解析行为。

17. **方言迁移的最大陷阱往往是别名可见性差异**：从 BigQuery / Snowflake 迁移到 PostgreSQL / SQL Server 时，大量「WHERE 引用别名」的查询会突然失败。

18. **SQL 标准委员会尚未将 lateral column alias 纳入标准**（截至 SQL:2023），但实际使用率已超过半数主流引擎。这可能是下一个标准化目标。

## 参考资料

- ISO/IEC 9075:1992 第 7.10 节 (query specification)
- ISO/IEC 9075:2003 第 7.11 节 (window clause)
- PostgreSQL 文档: [SELECT](https://www.postgresql.org/docs/current/sql-select.html)
- MySQL 文档: [SELECT Statement](https://dev.mysql.com/doc/refman/8.0/en/select.html)
- MariaDB Knowledge Base: [SELECT](https://mariadb.com/kb/en/select/)
- Microsoft Learn: [SELECT - Transact-SQL](https://learn.microsoft.com/en-us/sql/t-sql/queries/select-transact-sql)
- Oracle Database SQL Language Reference: [SELECT](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SELECT.html)
- BigQuery Reference: [Lateral Column Alias](https://cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax)
- Snowflake Documentation: [Lateral Column Aliases](https://docs.snowflake.com/en/release-notes/2023/7_29#lateral-column-aliases)
- ClickHouse: [Aliases](https://clickhouse.com/docs/en/sql-reference/syntax)
- DuckDB: [SELECT clause](https://duckdb.org/docs/sql/query_syntax/select)
- Trino Documentation: [SELECT](https://trino.io/docs/current/sql/select.html)
- Spark SQL SPARK-40925: Add Lateral Alias support
- Itzik Ben-Gan, "T-SQL Querying" (Microsoft Press, 2015) — Chapter 1: Logical Query Processing
- Joe Celko, "SQL for Smarties: Advanced SQL Programming" (Morgan Kaufmann, 5th ed.)
- Don Chamberlin, "SQL: A Practical Introduction to Database Languages" — IBM Research
- C.J. Date, "SQL and Relational Theory" (O'Reilly, 3rd ed., 2015)
- Markus Winand, "Modern SQL" (https://modern-sql.com)
- W3C SQL standards working group materials, SQL:2023 draft
