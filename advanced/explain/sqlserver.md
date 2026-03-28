# SQL Server: 执行计划

> 参考资料:
> - [SQL Server - Execution Plans](https://learn.microsoft.com/en-us/sql/relational-databases/performance/execution-plans)
> - [SQL Server - Query Store](https://learn.microsoft.com/en-us/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store)

## 估算执行计划（不执行查询）

文本格式
```sql
SET SHOWPLAN_TEXT ON;
GO
SELECT * FROM users WHERE username = 'alice';
GO
SET SHOWPLAN_TEXT OFF;
GO
```

XML 格式（最详细，SSMS 可图形化显示）
```sql
SET SHOWPLAN_XML ON;
GO
SELECT * FROM users WHERE age > 25;
GO
SET SHOWPLAN_XML OFF;
GO
```

设计分析（对引擎开发者）:
  SQL Server 使用 SET 命令控制执行计划输出——这需要独立的 GO 批分隔。
  这是 T-SQL 独有的设计——计划显示是会话级设置，不是查询前缀。

横向对比:
  PostgreSQL: EXPLAIN SELECT ...（查询前缀，最简洁）
  MySQL:      EXPLAIN SELECT ...
  Oracle:     EXPLAIN PLAN FOR SELECT ...; SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY)
  SQL Server: 需要 SET + GO + 查询 + GO + SET OFF + GO（最冗长）

对引擎开发者的启示:
  EXPLAIN 作为查询前缀是更好的设计——无状态，无副作用。
  SET 方式的问题: 忘记 SET OFF 会导致后续所有查询都只返回计划不执行。

## 实际执行计划与运行统计

I/O 统计（最常用的性能诊断工具）
```sql
SET STATISTICS IO ON;
SELECT * FROM users WHERE age > 25;
SET STATISTICS IO OFF;
```

输出: Table 'users'. Scan count 1, logical reads 10, physical reads 2...

时间统计
```sql
SET STATISTICS TIME ON;
SELECT * FROM users WHERE age > 25;
SET STATISTICS TIME OFF;
```

logical reads 是衡量查询效率的核心指标——它表示从缓冲池读取的 8KB 页面数。
相同查询的 logical reads 越少，性能越好。

实际执行计划（XML）
```sql
SET STATISTICS XML ON;
SELECT * FROM users WHERE age > 25;
SET STATISTICS XML OFF;
```

## 执行计划关键操作符

Table Scan:           全表扫描（堆表，无聚集索引）
Clustered Index Scan: 聚集索引全扫描（≈ 全表扫描，但数据有序）
Clustered Index Seek: 聚集索引查找（最优的点查）
Index Seek:           非聚集索引查找
Index Scan:           非聚集索引全扫描
Key Lookup:           键查找（从非聚集索引回到聚集索引取额外列）
RID Lookup:           行ID查找（堆表的回表操作）
Nested Loops:         嵌套循环 JOIN（小表驱动大表）
Hash Match:           哈希匹配（大表 JOIN/聚合）
Merge Join:           合并连接（两侧都已排序）
Sort:                 排序（可能溢出 tempdb）
Parallelism:          并行操作（Distribute/Gather/Repartition）

对引擎开发者的启示:
  Key Lookup 是 SQL Server 独有的概念——因为非聚集索引叶节点存储的是聚集索引键
  而非行的物理位置。这与 PostgreSQL 的 Index Scan + Heap Fetch 概念类似，
  但 Key Lookup 需要通过聚集索引 B-tree 导航（O(log N)），
  而 PostgreSQL 的 ctid 定位是 O(1)。
  这是聚集索引 vs 堆表架构的核心 trade-off。

## Query Store: 执行计划追踪（2016+）

```sql
ALTER DATABASE mydb SET QUERY_STORE = ON;
ALTER DATABASE mydb SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    MAX_STORAGE_SIZE_MB = 1000,
    QUERY_CAPTURE_MODE = AUTO
);
```

查看性能最差的查询
```sql
SELECT TOP 10 qt.query_sql_text,
       rs.avg_duration / 1000 AS avg_ms,
       rs.avg_logical_io_reads, rs.count_executions
FROM sys.query_store_query_text qt
JOIN sys.query_store_query q ON qt.query_text_id = q.query_text_id
JOIN sys.query_store_plan qp ON q.query_id = qp.query_id
JOIN sys.query_store_runtime_stats rs ON qp.plan_id = rs.plan_id
ORDER BY rs.avg_duration DESC;
```

强制使用特定计划（计划回归时的应急方案）
```sql
EXEC sp_query_store_force_plan @query_id = 1, @plan_id = 1;
```

横向对比:
  PostgreSQL: pg_stat_statements 扩展（类似，但不存储计划）
  MySQL:      Performance Schema + sys schema
  Oracle:     AWR + ASH（最成熟的性能诊断体系）

## 查询提示（Hints）

索引提示
```sql
SELECT * FROM users WITH (INDEX(IX_users_age)) WHERE age > 25;
```

JOIN 算法提示
```sql
SELECT * FROM users u INNER LOOP JOIN orders o ON u.id = o.user_id;
SELECT * FROM users u INNER HASH JOIN orders o ON u.id = o.user_id;
SELECT * FROM users u INNER MERGE JOIN orders o ON u.id = o.user_id;
```

查询选项
```sql
SELECT * FROM users WHERE age > 25 OPTION (MAXDOP 4);
SELECT * FROM users WHERE age > 25 OPTION (RECOMPILE);
SELECT * FROM users WHERE age > 25 OPTION (OPTIMIZE FOR (@age = 30));
```

## DMV: 动态管理视图（对引擎开发者核心工具）

缓存的执行计划
```sql
SELECT TOP 10 cp.usecounts, t.text AS sql_text
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) t
ORDER BY cp.usecounts DESC;
```

最消耗资源的查询
```sql
SELECT TOP 10 qs.total_logical_reads, qs.execution_count,
       qs.total_logical_reads / qs.execution_count AS avg_reads,
       t.text AS sql_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) t
ORDER BY qs.total_logical_reads DESC;
```

> **注意**: CROSS APPLY + DMV 是 SQL Server 性能诊断的核心模式
这是 CROSS APPLY 在系统管理中的经典应用
