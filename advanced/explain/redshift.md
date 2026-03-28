# Amazon Redshift: 执行计划与查询分析

> 参考资料:
> - [AWS Documentation - EXPLAIN](https://docs.aws.amazon.com/redshift/latest/dg/r_EXPLAIN.html)
> - [AWS Documentation - Query Performance Tuning](https://docs.aws.amazon.com/redshift/latest/dg/c-optimizing-query-performance.html)
> - [AWS Documentation - System Tables for Query Monitoring](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_system.html)


## EXPLAIN 基本用法


```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';
```


输出示例：
XN Seq Scan on users  (cost=0.00..12.50 rows=1 width=100)
Filter: (username = 'alice'::character varying)

XN 前缀表示 Redshift 操作符（Xen Network）

## EXPLAIN 详细选项


显示详细信息
```sql
EXPLAIN VERBOSE SELECT * FROM users WHERE age > 25;
```


## 执行计划关键操作符


XN Seq Scan           顺序扫描
XN Index Scan         通过排序键扫描
XN Merge Join         合并连接
XN Hash Join          哈希连接
XN Nested Loop        嵌套循环连接
XN Aggregate          聚合
XN Sort               排序
XN HashAggregate      哈希聚合
XN Subquery Scan      子查询扫描
XN Network            网络传输（节点间数据移动）
XN Broadcast          广播（小表分发到所有节点）
XN Distribute         重分布（按连接键重新分布数据）

DS_DIST_NONE          无需重分布（共置连接）
DS_DIST_ALL_NONE      一个表使用 ALL 分布
DS_BCAST_INNER        广播内表
DS_DIST_BOTH          两个表都需要重分布（最差）

## 系统表查询性能分析


查询执行详情
```sql
SELECT query, elapsed, substring(querytxt, 1, 100) AS query_text
FROM stl_query
WHERE userid > 1
ORDER BY starttime DESC
LIMIT 10;
```


查询执行步骤
```sql
SELECT query, segment, step, label, rows, bytes,
       elapsed_time / 1000000.0 AS elapsed_sec
FROM svl_query_report
WHERE query = 12345
ORDER BY segment, step;
```


## STL 系统表（详细诊断）


扫描统计
```sql
SELECT query, tbl, perm_table_name, rows, bytes,
       elapsed / 1000000.0 AS elapsed_sec
FROM stl_scan
WHERE query = 12345;
```


连接统计
```sql
SELECT query, tbl, num_hs_probes, num_hs_rows
FROM stl_hashjoin
WHERE query = 12345;
```


排序统计
```sql
SELECT query, tbl, rows, elapsed / 1000000.0 AS elapsed_sec,
       is_diskbased
FROM stl_sort
WHERE query = 12345;
```


磁盘溢出
```sql
SELECT query, segment, step, rows, workmem, is_diskbased
FROM svl_query_summary
WHERE query = 12345 AND is_diskbased = 't';
```


## SVL 视图（汇总信息）


查询执行汇总
```sql
SELECT query, elapsed, rows_out,
       bytes, label
FROM svl_query_summary
WHERE query = 12345
ORDER BY segment, step;
```


查询排队等待
```sql
SELECT query, total_queue_time / 1000000.0 AS queue_sec,
       total_exec_time / 1000000.0 AS exec_sec
FROM svl_query_queue_info
WHERE query = 12345;
```


## 分布键和排序键分析


检查分布倾斜
```sql
SELECT "table", size, pct_used, skew_rows, skew_sortkey1
FROM svv_table_info
ORDER BY skew_rows DESC NULLS LAST
LIMIT 10;
```


检查排序键效果
```sql
SELECT "table", unsorted, vacuum_sort_benefit
FROM svv_table_info
WHERE unsorted > 10
ORDER BY unsorted DESC;
```


## 编译时间分析


查看编译时间（首次执行可能较慢）
```sql
SELECT query, segment, compile_duration / 1000000.0 AS compile_sec
FROM svl_compile
WHERE query = 12345;
```


## 查询告警


查看查询告警（如嵌套循环、广播大表等）
```sql
SELECT query, trim(event) AS event, trim(solution) AS solution
FROM stl_alert_event_log
WHERE userid > 1
ORDER BY event_time DESC
LIMIT 10;
```


注意：Redshift 基于 PostgreSQL 但执行引擎完全不同
注意：DS_DIST 标记说明数据是否需要在节点间重分布
注意：DS_DIST_BOTH 表示两表都需要重分布，通常需要优化分布键
注意：stl_alert_event_log 提供自动化的性能告警
注意：磁盘溢出（is_diskbased = true）表示需要更多内存或更大节点
注意：编译时间可能使首次执行较慢，后续执行会使用缓存
