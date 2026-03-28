# openGauss: 执行计划与查询分析

> 参考资料:
> - [openGauss Documentation - EXPLAIN](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/EXPLAIN.html)
> - [openGauss Documentation - Performance Tuning](https://docs.opengauss.org/zh/docs/latest/docs/PerformanceTuningGuide/)


## EXPLAIN 基本用法（兼容 PostgreSQL）


```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';
```

## EXPLAIN ANALYZE


```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;
```

## EXPLAIN PERFORMANCE（openGauss 特有）


## 显示详细的性能信息

```sql
EXPLAIN PERFORMANCE SELECT * FROM users WHERE age > 25;
```

输出包含：
各操作符的 CPU 时间
内存使用
I/O 统计
各数据节点的执行信息（分布式部署时）

## 输出格式


```sql
EXPLAIN (FORMAT TEXT) SELECT * FROM users WHERE age > 25;
EXPLAIN (FORMAT JSON) SELECT * FROM users WHERE age > 25;
EXPLAIN (FORMAT YAML) SELECT * FROM users WHERE age > 25;
EXPLAIN (FORMAT XML) SELECT * FROM users WHERE age > 25;
```

## 完整选项

```sql
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE)
SELECT * FROM users WHERE age > 25;
```

## 执行计划关键操作


Seq Scan              顺序扫描
Index Scan            索引扫描
Index Only Scan       仅索引扫描
Bitmap Heap Scan      位图堆扫描
CStore Scan           列存储扫描（openGauss 特有）
Hash Join             哈希连接
Nested Loop           嵌套循环
Merge Join            合并连接
Streaming(type: GATHER)  汇集（分布式）
Streaming(type: REDISTRIBUTE)  重分布（分布式）
Streaming(type: BROADCAST)  广播（分布式）

## 查询性能视图


## 查看活跃语句

```sql
SELECT * FROM pg_stat_activity WHERE state = 'active';
```

## 查看 SQL 统计（openGauss 特有）

```sql
SELECT unique_sql_id, query, n_calls, total_elapse_time,
       avg_elapse_time, n_returned_rows
FROM dbe_perf.statement
ORDER BY total_elapse_time DESC
LIMIT 10;
```

## 查看等待事件

```sql
SELECT * FROM dbe_perf.wait_events;
```

## 统计信息


```sql
ANALYZE users;
```

## 查看统计信息

```sql
SELECT relname, reltuples, relpages
FROM pg_class WHERE relname = 'users';
```

## Workload 诊断报告（WDR）


## 创建快照

```sql
SELECT create_wdr_snapshot();
```

## 生成报告

```sql
SELECT generate_wdr_report(begin_snap_id, end_snap_id, 'all', 'node');
```

注意：openGauss 基于 PostgreSQL，EXPLAIN 语法兼容
注意：EXPLAIN PERFORMANCE 是 openGauss 特有的详细性能分析
注意：列存储（CStore）表有特有的扫描操作
注意：分布式部署时包含 Streaming 操作符
注意：dbe_perf schema 提供丰富的性能诊断视图
注意：WDR 报告类似 Oracle 的 AWR 报告
