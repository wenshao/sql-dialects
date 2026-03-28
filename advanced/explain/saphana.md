# SAP HANA: 执行计划与查询分析

> 参考资料:
> - [SAP HANA Documentation - EXPLAIN PLAN](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20d9fda075191014b12fcc10cdf42570.html)
> - [SAP HANA Documentation - SQL Plan Cache](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/20c57b8375191014b536e2f0b40c47f7.html)
> - ============================================================
> - EXPLAIN PLAN 基本用法
> - ============================================================
> - 将执行计划存入 EXPLAIN_PLAN_TABLE

```sql
EXPLAIN PLAN FOR
SELECT * FROM users WHERE username = 'alice';
```

## 查看执行计划

```sql
SELECT OPERATOR_NAME, OPERATOR_DETAILS, TABLE_NAME,
       OUTPUT_SIZE, SUBTREE_COST
FROM EXPLAIN_PLAN_TABLE
ORDER BY OPERATOR_ID;
```

## 带语句标识符

```sql
EXPLAIN PLAN SET STATEMENT_NAME = 'query1' FOR
SELECT * FROM users WHERE age > 25;

SELECT * FROM EXPLAIN_PLAN_TABLE
WHERE STATEMENT_NAME = 'query1'
ORDER BY OPERATOR_ID;
```

## Plan Visualizer（SAP HANA Studio / Web IDE）


在 SAP HANA Studio 中：
1. 右键点击 SQL 编辑器中的查询
2. 选择 "Visualize Plan"
3. 查看图形化执行计划
支持两种模式：
Estimated Plan（估算计划，不执行）
Executed Plan（实际计划，执行后）

## 执行计划关键操作符


COLUMN SEARCH       列存储搜索
ROW SEARCH          行存储搜索
COLUMN TABLE SCAN   列存储全表扫描
CPBTREE INDEX SEARCH  B-Tree 索引搜索
JOIN                连接
HASH JOIN           哈希连接
NESTED LOOP JOIN    嵌套循环连接
AGGREGATION         聚合
ORDER BY            排序
LIMIT               限制
UNION ALL           联合
GROUP BY            分组

## SQL Plan Cache


## 查看 SQL 计划缓存

```sql
SELECT STATEMENT_STRING, EXECUTION_COUNT, TOTAL_EXECUTION_TIME,
       AVG_EXECUTION_TIME, TOTAL_LOCK_WAIT_DURATION
FROM M_SQL_PLAN_CACHE
ORDER BY TOTAL_EXECUTION_TIME DESC
LIMIT 10;
```

## 查看特定查询的计划

```sql
SELECT PLAN_ID, STATEMENT_STRING, EXECUTION_COUNT,
       TOTAL_EXECUTION_TIME / 1000 AS total_ms,
       AVG_EXECUTION_TIME / 1000 AS avg_ms
FROM M_SQL_PLAN_CACHE
WHERE STATEMENT_STRING LIKE '%users%'
ORDER BY AVG_EXECUTION_TIME DESC;
```

## 清除计划缓存

```sql
ALTER SYSTEM CLEAR SQL PLAN CACHE;
```

## 系统视图（性能分析）


## 当前执行的语句

```sql
SELECT CONNECTION_ID, STATEMENT_STRING, DURATION_MICROSEC,
       LOCK_WAIT_DURATION
FROM M_ACTIVE_STATEMENTS;
```

## 服务线程

```sql
SELECT CONNECTION_ID, THREAD_ID, THREAD_TYPE, THREAD_STATE,
       DURATION / 1000000 AS duration_sec
FROM M_SERVICE_THREADS
WHERE IS_ACTIVE = 'TRUE';
```

## 列存储与行存储分析


## 查看表的存储类型

```sql
SELECT TABLE_NAME, TABLE_TYPE, IS_COLUMN_TABLE, RECORD_COUNT
FROM M_TABLES
WHERE SCHEMA_NAME = CURRENT_SCHEMA;
```

## 列存储表的列信息

```sql
SELECT TABLE_NAME, COLUMN_NAME, COMPRESSION_TYPE,
       MEMORY_SIZE_IN_TOTAL, COUNT
FROM M_CS_ALL_COLUMNS
WHERE TABLE_NAME = 'USERS';
```

## Hint 控制执行计划


## 使用 Hint

```sql
SELECT /*+ USE_OLAP_PLAN */ * FROM users WHERE age > 25;
SELECT /*+ NO_USE_OLAP_PLAN */ * FROM users WHERE age > 25;
SELECT /*+ INDEX_SEARCH */ * FROM users WHERE age > 25;
```

注意：EXPLAIN PLAN 将计划存入 EXPLAIN_PLAN_TABLE
注意：SAP HANA Studio 的 Plan Visualizer 提供最佳的可视化体验
注意：M_SQL_PLAN_CACHE 是分析历史查询性能的主要工具
注意：HANA 同时支持列存储和行存储，计划因存储类型不同而不同
注意：列存储（COLUMN TABLE）是 HANA 的默认和推荐存储方式
