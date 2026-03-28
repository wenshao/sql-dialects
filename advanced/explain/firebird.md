# Firebird: 执行计划与查询分析

> 参考资料:
> - [Firebird Documentation - Query Plan](https://firebirdsql.org/file/documentation/chunk/en/refdocs/fblangref40/fblangref40-commons.html#fblangref40-commons-plan)
> - [Firebird Documentation - SET PLANONLY](https://firebirdsql.org/file/documentation/chunk/en/refdocs/fblangref40/fblangref40-management.html)
> - ============================================================
> - 自动执行计划输出（isql）
> - ============================================================
> - 在 isql 中启用执行计划显示
> - SET PLAN ON;
> - SET PLANONLY ON;  -- 只显示计划，不执行
> - ============================================================
> - PLAN 子句（手动指定执行计划）
> - ============================================================
> - Firebird 允许在查询中显式指定执行计划

```sql
SELECT * FROM users
PLAN (users NATURAL);   -- 全表扫描

SELECT * FROM users
PLAN (users INDEX (idx_users_age))
WHERE age > 25;

SELECT * FROM users
PLAN (users ORDER idx_users_age)
WHERE age > 25
ORDER BY age;
```

## 连接查询的 PLAN


```sql
SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id
PLAN JOIN (u NATURAL, o INDEX (idx_orders_user_id));

SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id
PLAN HASH (u NATURAL, o NATURAL);  -- 3.0+: 哈希连接

SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id
PLAN MERGE (SORT (u NATURAL), SORT (o NATURAL));  -- 合并连接
```

## 3.0+: 详细执行计划


在 isql 中：
SET EXPLAIN ON;  -- 显示详细执行计划
详细计划包含：
访问方式（Natural, Index, Order）
索引名称
连接方式（Join, Hash, Merge）
记录源描述

## MON$ 监控表


## 查看当前活跃语句

```sql
SELECT m.MON$STATEMENT_ID, m.MON$SQL_TEXT, m.MON$TIMESTAMP,
       s.MON$RECORD_SEQ_READS, s.MON$RECORD_IDX_READS
FROM MON$STATEMENTS m
LEFT JOIN MON$RECORD_STATS s ON m.MON$STAT_ID = s.MON$STAT_ID
WHERE m.MON$STATE = 1;
```

## 查看 I/O 统计

```sql
SELECT MON$PAGE_READS, MON$PAGE_WRITES, MON$PAGE_FETCHES, MON$PAGE_MARKS
FROM MON$IO_STATS
WHERE MON$STAT_GROUP = 0;  -- 数据库级别
```

## 查看记录级统计

```sql
SELECT MON$RECORD_SEQ_READS AS seq_reads,
       MON$RECORD_IDX_READS AS idx_reads,
       MON$RECORD_INSERTS AS inserts,
       MON$RECORD_UPDATES AS updates,
       MON$RECORD_DELETES AS deletes
FROM MON$RECORD_STATS
WHERE MON$STAT_GROUP = 0;
```

## 执行计划操作


NATURAL         全表扫描（自然读取）
INDEX           通过索引访问
ORDER           通过索引排序
JOIN            嵌套循环连接
HASH            哈希连接（3.0+）
MERGE           合并连接
SORT            排序

## 统计信息


## Firebird 自动维护索引统计

手动重新计算：

```sql
SET STATISTICS INDEX idx_users_age;
```

## 查看索引选择性

```sql
SELECT RDB$INDEX_NAME, RDB$STATISTICS
FROM RDB$INDICES WHERE RDB$RELATION_NAME = 'USERS';
```

注意：Firebird 使用 PLAN 子句手动指定执行计划（非常独特）
注意：isql 中用 SET PLAN ON 显示自动选择的计划
注意：3.0+ 版本 SET EXPLAIN ON 提供详细计划信息
注意：3.0+ 支持 HASH JOIN
注意：MON$ 表提供运行时监控信息
注意：SET STATISTICS 更新索引统计信息
