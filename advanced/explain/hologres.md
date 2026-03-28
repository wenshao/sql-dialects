# Hologres: 执行计划与查询分析

> 参考资料:
> - [Hologres Documentation - EXPLAIN](https://help.aliyun.com/document_detail/410670.html)
> - [Hologres Documentation - 查询优化](https://help.aliyun.com/document_detail/321181.html)
> - ============================================================
> - EXPLAIN 基本用法（兼容 PostgreSQL）
> - ============================================================

```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';
```

## EXPLAIN ANALYZE


```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;
```

## 输出格式


```sql
EXPLAIN (FORMAT TEXT) SELECT * FROM users WHERE age > 25;
EXPLAIN (FORMAT JSON) SELECT * FROM users WHERE age > 25;

EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE)
SELECT * FROM users WHERE age > 25;
```

## Hologres 特有的执行计划操作


Seq Scan on [table]         行存表全扫描
Column Scan on [table]      列存表扫描
Index Scan on [table]       索引扫描（行存表）
Bitmap Scan                 位图扫描
Gather                      汇集（并行查询结果）
Hash Join / Nested Loop     连接操作
Sort / HashAggregate        排序/聚合

## 慢查询日志


## 查看慢查询

```sql
SELECT query_id, query, duration, state
FROM hologres.hg_query_log
WHERE duration > 1000  -- 毫秒
ORDER BY start_time DESC
LIMIT 10;
```

## 行存 vs 列存分析


## 行存表：适合点查询，使用 Index Scan

```sql
EXPLAIN SELECT * FROM users_row WHERE id = 1;
```

## 列存表：适合分析查询，使用 Column Scan

```sql
EXPLAIN SELECT age, COUNT(*) FROM users_column GROUP BY age;
```

## 统计信息


```sql
ANALYZE users;
```

注意：Hologres 兼容 PostgreSQL 语法
注意：行存表和列存表的执行计划不同
注意：列存表的 Column Scan 只读取需要的列
注意：hg_query_log 提供查询日志和性能信息
注意：阿里云控制台提供图形化的查询分析工具
