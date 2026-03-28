# 达梦 (DM): 执行计划与查询分析

> 参考资料:
> - [达梦数据库 SQL 语言使用手册](https://eco.dameng.com/document/dm/zh-cn/sql-dev/)
> - [达梦数据库性能优化](https://eco.dameng.com/document/dm/zh-cn/pm/)
> - ============================================================
> - EXPLAIN 基本用法
> - ============================================================
> - 达梦使用 EXPLAIN 语句

```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';
```

## ET（执行跟踪）


## 启用执行跟踪（类似 EXPLAIN ANALYZE）

```sql
ALTER SESSION SET EVENTS 'IMMEDIATE TRACE NAME CONTEXT FOREVER, LEVEL 1';

SELECT * FROM users WHERE age > 25;
```

## 查看跟踪结果

```sql
SELECT * FROM V$SQL_STAT ORDER BY EXEC_TIME DESC;
```

## 执行计划关键操作


CSCN    聚集索引全扫描（全表扫描）
SSEK    二级索引扫描
SSCN    二级索引全扫描
BLKUP   回表（通过 ROWID）
NEST LOOP JOIN  嵌套循环连接
HASH JOIN       哈希连接
MERGE JOIN      合并连接
HAGR            哈希聚合
SAGR            流聚合
SORT            排序
PRJT            投影
SLCT            选择/过滤
NSET            结果集
HASH RIGHT SEMI JOIN  哈希右半连接

## Hint 控制执行计划


```sql
EXPLAIN SELECT /*+ INDEX(users, idx_users_age) */
* FROM users WHERE age > 25;

EXPLAIN SELECT /*+ FULL(users) */
* FROM users WHERE age > 25;

EXPLAIN SELECT /*+ USE_HASH(u, o) */
u.*, o.amount FROM users u JOIN orders o ON u.id = o.user_id;
```

## V$ 性能视图


## 查看 SQL 执行统计

```sql
SELECT SQL_TEXT, EXEC_COUNT, TOTAL_TIME, AVG_TIME,
       LOGICAL_READS, PHYSICAL_READS
FROM V$SQL_STAT
ORDER BY TOTAL_TIME DESC;
```

## 查看活跃会话

```sql
SELECT * FROM V$SESSIONS WHERE STATE = 'ACTIVE';
```

## 查看等待事件

```sql
SELECT * FROM V$WAIT_STAT;
```

## 统计信息


## 收集统计信息

```sql
CALL SP_TAB_STAT_INIT('SYSDBA', 'USERS');
```

## 或使用 DBMS_STATS

```sql
CALL DBMS_STATS.GATHER_TABLE_STATS('SYSDBA', 'USERS');
```

注意：达梦 EXPLAIN 语法简洁
注意：CSCN 表示全表扫描，SSEK 表示索引查找
注意：达梦支持 Oracle 风格的 Hint
注意：V$SQL_STAT 提供 SQL 执行统计信息
注意：DBMS_STATS 包用于管理统计信息
