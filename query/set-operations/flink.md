# Flink SQL: 集合操作

> 参考资料:
> - [Apache Flink Documentation - Set Operations](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/set-operations/)
> - [Apache Flink Documentation - Queries](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/overview/)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

## UNION / UNION ALL

```sql
SELECT id, name FROM employees
UNION
SELECT id, name FROM contractors;

SELECT id, name FROM employees
UNION ALL
SELECT id, name FROM contractors;

```

## INTERSECT / INTERSECT ALL

```sql
SELECT id FROM employees
INTERSECT
SELECT id FROM project_members;

SELECT id FROM employees
INTERSECT ALL
SELECT id FROM project_members;

```

## EXCEPT / EXCEPT ALL

```sql
SELECT id FROM employees
EXCEPT
SELECT id FROM terminated_employees;

SELECT id FROM employees
EXCEPT ALL
SELECT id FROM terminated_employees;

```

## 嵌套与组合集合操作

```sql
(SELECT id FROM employees
 UNION
 SELECT id FROM contractors)
INTERSECT
SELECT id FROM project_members;

```

## ORDER BY 与集合操作

```sql
SELECT name, salary FROM employees
UNION ALL
SELECT name, salary FROM contractors
ORDER BY salary DESC;

```

## LIMIT 与集合操作

```sql
SELECT name FROM employees
UNION ALL
SELECT name FROM contractors
ORDER BY name
LIMIT 10;

```

## 流处理中的集合操作

合并多个流
```sql
SELECT event_time, event_type, payload FROM click_events
UNION ALL
SELECT event_time, event_type, payload FROM page_view_events;

```

## 注意事项

Flink SQL 完整支持 SQL 标准集合操作
在流模式下，UNION ALL 是最常用的集合操作
UNION（去重）在流模式下需要维护状态，资源消耗大
INTERSECT/EXCEPT 在流模式下同样需要状态维护
建议流模式下尽量使用 UNION ALL
