# Spanner: 集合操作

> 参考资料:
> - [Spanner Documentation - Query Syntax](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax#set_operators)
> - [Spanner Documentation - SELECT](https://cloud.google.com/spanner/docs/reference/standard-sql/query-syntax)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

## UNION / UNION ALL

```sql
SELECT id, name FROM employees
UNION DISTINCT
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

```

**注意:** Spanner 推荐使用 UNION DISTINCT 而非 UNION

## INTERSECT

```sql
SELECT id FROM employees
INTERSECT DISTINCT
SELECT id FROM project_members;

```

**注意:** Spanner 不支持 INTERSECT ALL

## EXCEPT

```sql
SELECT id FROM employees
EXCEPT DISTINCT
SELECT id FROM terminated_employees;

```

**注意:** Spanner 不支持 EXCEPT ALL

## 嵌套与组合集合操作

```sql
(SELECT id FROM employees
 UNION ALL
 SELECT id FROM contractors)
INTERSECT DISTINCT
SELECT id FROM project_members;

```

## ORDER BY 与集合操作

```sql
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC;

```

## LIMIT / OFFSET 与集合操作

```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10;

SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10 OFFSET 20;

```

## 注意事项

Spanner 使用 GoogleSQL 方言（类似 BigQuery）
要求使用 DISTINCT 后缀（UNION DISTINCT 而非 UNION）
不支持 ALL 变体的 INTERSECT ALL 和 EXCEPT ALL
ARRAY / STRUCT 类型可用于集合操作
