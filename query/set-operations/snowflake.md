# Snowflake: 集合操作

> 参考资料:
> - [1] Snowflake SQL Reference - Set Operators
>   https://docs.snowflake.com/en/sql-reference/operators-query


## 1. 基本语法


UNION（去重）

```sql
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

```

UNION ALL（保留重复）

```sql
SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

```

INTERSECT

```sql
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

```

EXCEPT / MINUS（两者等价，MINUS 是 Oracle 兼容语法）

```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

SELECT id FROM employees
MINUS
SELECT id FROM terminated_employees;

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 不支持 INTERSECT ALL / EXCEPT ALL

 SQL 标准定义了 INTERSECT ALL 和 EXCEPT ALL（保留重复行的集合操作），
 但 Snowflake 不支持。

 对比:
   PostgreSQL: 支持 INTERSECT ALL / EXCEPT ALL（最完整的标准实现）
   MySQL:      8.0.31+ 支持 INTERSECT / EXCEPT（但无 ALL 变体）
   Oracle:     支持 MINUS（= EXCEPT），不支持 MINUS ALL
   BigQuery:   支持 INTERSECT DISTINCT / EXCEPT DISTINCT（无 ALL）
   Redshift:   支持 INTERSECT / EXCEPT（无 ALL）

 对引擎开发者的启示:
   INTERSECT ALL / EXCEPT ALL 的实现需要跟踪行的重复计数，
   比去重版本更复杂。大多数云数仓认为 ALL 变体的使用频率太低，不值得实现。

### 2.2 MINUS vs EXCEPT

 MINUS 是 Oracle 的命名（Oracle 不支持 EXCEPT 关键字）
 EXCEPT 是 SQL 标准命名
 Snowflake 两者都支持，完全等价
对比: PostgreSQL 只支持 EXCEPT | MySQL 只支持 EXCEPT

### 2.3 VARIANT 列的集合操作限制

 VARIANT / OBJECT / ARRAY 类型不能直接用于集合操作:
   SELECT data FROM t1 UNION SELECT data FROM t2;  -- 可能报错
 需要先转换: SELECT data::VARCHAR FROM t1 UNION SELECT data::VARCHAR FROM t2;

## 3. 组合与排序


括号控制优先级

```sql
(SELECT id FROM employees
 UNION
 SELECT id FROM contractors)
INTERSECT
SELECT id FROM project_members;

```

ORDER BY + LIMIT 应用于整个集合操作结果

```sql
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC
LIMIT 10 OFFSET 20;

```

FETCH FIRST 也支持

```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
FETCH FIRST 10 ROWS ONLY;

```

## 4. 与 CTE 结合


```sql
WITH active AS (
    SELECT id, name FROM employees WHERE active = TRUE
)
SELECT id, name FROM active
UNION ALL
SELECT id, name FROM contractors
ORDER BY name;

```

## 横向对比: 集合操作能力

| 能力            | Snowflake  | BigQuery  | PostgreSQL | MySQL    | Oracle |
|------|------|------|------|------|------|
| UNION ALL       | 支持       | 支持      | 支持       | 支持     | 支持 |
| INTERSECT       | 支持       | 支持      | 支持       | 8.0.31+  | 支持 |
| EXCEPT          | 支持       | 支持      | 支持       | 8.0.31+  | 不支持 |
| MINUS           | 支持       | 不支持    | 不支持     | 不支持   | 支持 |
| INTERSECT ALL   | 不支持     | 不支持    | 支持       | 不支持   | 不支持 |
| EXCEPT ALL      | 不支持     | 不支持    | 支持       | 不支持   | 不支持 |
| 括号优先级      | 支持       | 支持      | 支持       | 支持     | 支持 |

