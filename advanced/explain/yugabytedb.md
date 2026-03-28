# YugabyteDB: 执行计划

> 参考资料:
> - [YugabyteDB Documentation - EXPLAIN](https://docs.yugabyte.com/preview/api/ysql/the-sql-language/statements/perf_explain/)
> - [YugabyteDB Documentation - Query Tuning](https://docs.yugabyte.com/preview/explore/query-1-performance/)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

## EXPLAIN 基本用法（YSQL，兼容 PostgreSQL）


```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';

```

## EXPLAIN ANALYZE


```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

```

YugabyteDB 特有输出：
包含分布式相关信息（RPC 调用、远程过滤等）

## 完整选项


```sql
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE, DIST)
SELECT u.*, COUNT(o.id)
FROM users u LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id;

```

DIST 选项（YugabyteDB 特有）：显示分布式执行信息

## YugabyteDB 特有的执行计划信息


Storage Table Read Requests:  存储层读取请求数
Storage Table Rows Scanned:   存储层扫描行数
Storage Index Read Requests:  索引读取请求数
Storage Index Rows Scanned:   索引扫描行数
Remote Filter:                远程过滤条件（下推到 Tablet）

输出示例：
Seq Scan on users (...)
  Storage Table Read Requests: 1
  Storage Table Rows Scanned: 1000

## 执行计划关键操作


Seq Scan              顺序扫描
Index Scan            索引扫描（YB 索引）
Index Only Scan       仅索引扫描
YB Batched Nested Loop Join  YugabyteDB 批量嵌套循环
Hash Join             哈希连接
Merge Join            合并连接
Sort                  排序
HashAggregate         哈希聚合
GroupAggregate         分组聚合

## 分布式查询优化


查看 Tablet 分布
yugabyte-admin list_tablets ysql.mydb users

查看表的分片信息
```sql
SELECT * FROM yb_table_properties('users'::regclass);

```

## YCQL EXPLAIN（Cassandra 兼容接口）


YCQL 不支持 EXPLAIN
使用跟踪（Tracing）替代：
TRACING ON;
SELECT * FROM users WHERE id = 1;
TRACING OFF;

## 性能诊断视图


查看活跃查询
```sql
SELECT * FROM pg_stat_activity WHERE state = 'active';

```

pg_stat_statements（需要启用扩展）
```sql
SELECT query, calls, total_time, mean_time, rows
FROM pg_stat_statements
ORDER BY total_time DESC LIMIT 10;

```

## 统计信息


```sql
ANALYZE users;

```

**注意:** YugabyteDB YSQL 基于 PostgreSQL，EXPLAIN 语法相同
**注意:** DIST 选项显示分布式执行的额外信息
**注意:** Storage Read Requests 反映了 RPC 调用次数
**注意:** Remote Filter 表示过滤条件下推到存储层
**注意:** YB Batched Nested Loop 是 YugabyteDB 优化的分布式连接方式
**注意:** YCQL（Cassandra 兼容）不支持 EXPLAIN，使用 TRACING
