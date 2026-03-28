# TiDB: 执行计划

> 参考资料:
> - [TiDB Documentation - EXPLAIN](https://docs.pingcap.com/tidb/stable/sql-statement-explain)
> - [TiDB Documentation - EXPLAIN ANALYZE](https://docs.pingcap.com/tidb/stable/sql-statement-explain-analyze)
> - [TiDB Documentation - Understanding the Query Execution Plan](https://docs.pingcap.com/tidb/stable/query-execution-plan)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## EXPLAIN 基本用法


```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';

```

输出列：
id:        操作符名称
estRows:   估算行数
task:      任务类型（root/cop[tikv]/cop[tiflash]）
access object: 访问对象
operator info: 操作信息

## EXPLAIN 输出格式


默认格式
```sql
EXPLAIN SELECT * FROM users WHERE age > 25;

```

简要格式
```sql
EXPLAIN FORMAT='brief' SELECT * FROM users WHERE age > 25;

```

详细格式（含成本信息）
```sql
EXPLAIN FORMAT='verbose' SELECT * FROM users WHERE age > 25;

```

DOT 格式（可用 graphviz 渲染）
```sql
EXPLAIN FORMAT='dot' SELECT * FROM users WHERE age > 25;

```

## EXPLAIN ANALYZE（实际执行）


```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

```

额外输出列：
actRows:    实际行数
execution info: 执行信息（时间、循环次数、RPC 调用）
memory:     内存使用
disk:       磁盘使用（溢出时）

```sql
EXPLAIN ANALYZE
SELECT u.username, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.username
ORDER BY order_count DESC
LIMIT 10;

```

## 关键操作符说明


task 类型：
root:          TiDB 层执行
cop[tikv]:     下推到 TiKV 层执行
cop[tiflash]:  下推到 TiFlash 层执行（HTAP）

扫描操作：
TableFullScan     全表扫描
TableRangeScan    表范围扫描
TableRowIDScan    通过 RowID 回表
IndexFullScan     索引全扫描
IndexRangeScan    索引范围扫描
IndexLookUp       索引查找 + 回表

连接操作：
HashJoin           哈希连接
IndexJoin           索引连接（类似 Nested Loop + Index）
MergeJoin           合并连接

聚合操作：
HashAgg            哈希聚合
StreamAgg          流式聚合

## TiFlash 查询（HTAP）


使用 TiFlash 副本分析（列式存储）
```sql
EXPLAIN SELECT /*+ READ_FROM_STORAGE(TIFLASH[users]) */
    age, COUNT(*) FROM users GROUP BY age;

```

task = cop[tiflash] 表示在 TiFlash 执行

## 慢查询日志


查看慢查询日志
```sql
SELECT * FROM information_schema.slow_query
WHERE query_time > 1
ORDER BY query_time DESC
LIMIT 10;

```

查看集群慢查询
```sql
SELECT * FROM information_schema.cluster_slow_query
WHERE query_time > 1
ORDER BY query_time DESC
LIMIT 10;

```

## STATEMENTS_SUMMARY（语句统计）


```sql
SELECT digest_text, exec_count, avg_latency, avg_mem,
       avg_processed_keys, plan
FROM information_schema.statements_summary
ORDER BY avg_latency DESC
LIMIT 10;

```

## 统计信息管理


收集统计信息
```sql
ANALYZE TABLE users;

```

查看统计信息
```sql
SHOW STATS_META WHERE table_name = 'users';
SHOW STATS_HISTOGRAMS WHERE table_name = 'users';

```

查看统计信息健康度
```sql
SHOW STATS_HEALTHY WHERE table_name = 'users';

```

## TiDB Dashboard


TiDB Dashboard 提供：
- 慢查询分析
- SQL 语句分析（执行次数、平均延迟）
- 执行计划图形化查看
- 集群诊断
- 关键可视化（Key Visualizer）

## Hint 控制执行计划


强制索引
```sql
EXPLAIN SELECT /*+ USE_INDEX(users, idx_users_age) */ * FROM users WHERE age > 25;

```

强制连接方式
```sql
EXPLAIN SELECT /*+ HASH_JOIN(u, o) */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

EXPLAIN SELECT /*+ INL_JOIN(o) */ u.*, o.amount
FROM users u JOIN orders o ON u.id = o.user_id;

```

强制使用 TiFlash
```sql
EXPLAIN SELECT /*+ READ_FROM_STORAGE(TIFLASH[users]) */ * FROM users;

```

**注意:** EXPLAIN 不执行查询，EXPLAIN ANALYZE 会实际执行
**注意:** task 列区分 TiDB / TiKV / TiFlash 的执行位置
**注意:** cop 任务表示计算下推到存储层，减少数据传输
**注意:** TiFlash 副本提供列式存储的分析能力（HTAP）
**注意:** STATEMENTS_SUMMARY 提供语句级的性能统计
**注意:** 统计信息健康度影响优化器的决策质量
