# Azure Synapse Analytics: 执行计划与查询分析

> 参考资料:
> - [Microsoft Docs - EXPLAIN (Synapse)](https://learn.microsoft.com/en-us/sql/t-sql/queries/explain-transact-sql)
> - [Microsoft Docs - Monitor workload](https://learn.microsoft.com/en-us/azure/synapse-analytics/sql-data-warehouse/sql-data-warehouse-manage-monitor)


## EXPLAIN（专用 SQL 池）


Synapse 专用 SQL 池使用 EXPLAIN
```sql
EXPLAIN SELECT * FROM users WHERE age > 25;
```


输出 XML 格式的分布式查询计划
包含数据移动（Data Movement）信息

WITH_RECOMMENDATIONS 选项
```sql
EXPLAIN WITH_RECOMMENDATIONS
SELECT * FROM users WHERE age > 25;
-- 输出包含优化建议（如建议创建统计信息）
```


## 数据移动操作


ShuffleMove        按哈希键重分布
BroadcastMove      广播（复制到所有分布）
TrimMove           只发送匹配行
PartitionMove      按分区键移动
RoundRobinMove     轮询分布
ReturnOperation    返回结果

目标：减少数据移动（选择合适的分布键）

## DMV（动态管理视图）


查看最消耗资源的查询
```sql
SELECT TOP 10
    request_id, command, submit_time, total_elapsed_time,
    resource_class, label
FROM sys.dm_pdw_exec_requests
WHERE status = 'Completed'
ORDER BY total_elapsed_time DESC;
```


查看查询步骤
```sql
SELECT request_id, step_index, operation_type,
       distribution_type, location_type,
       row_count, command
FROM sys.dm_pdw_request_steps
WHERE request_id = 'QID12345'
ORDER BY step_index;
```


查看数据移动
```sql
SELECT request_id, step_index, distribution_id,
       rows_processed, command
FROM sys.dm_pdw_sql_requests
WHERE request_id = 'QID12345'
ORDER BY step_index;
```


## 分布分析


检查数据倾斜
```sql
DBCC PDW_SHOWSPACEUSED('users');
```


查看分布类型
```sql
SELECT distribution_policy_desc, distribution_ordinal
FROM sys.pdw_table_distribution_properties
WHERE object_id = OBJECT_ID('users');
```


## 统计信息


创建统计信息
```sql
CREATE STATISTICS stats_users_age ON users(age);
```


更新统计信息
```sql
UPDATE STATISTICS users;
```


自动统计信息
默认启用 AUTO_CREATE_STATISTICS

## Serverless SQL 池


Serverless 池使用标准 SQL Server EXPLAIN 方式
```sql
SET SHOWPLAN_XML ON;
GO
SELECT * FROM OPENROWSET(...);
GO
SET SHOWPLAN_XML OFF;
GO
```


注意：EXPLAIN 返回 XML 格式的分布式计划
注意：数据移动（Data Movement）是分布式查询的主要开销
注意：WITH_RECOMMENDATIONS 提供优化建议
注意：选择正确的分布键可以避免不必要的数据移动
注意：sys.dm_pdw_* DMV 提供详细的查询诊断信息
注意：DBCC PDW_SHOWSPACEUSED 检查数据倾斜
