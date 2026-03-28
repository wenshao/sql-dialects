# CockroachDB: 执行计划

> 参考资料:
> - [CockroachDB Documentation - EXPLAIN](https://www.cockroachlabs.com/docs/stable/explain.html)
> - [CockroachDB Documentation - EXPLAIN ANALYZE](https://www.cockroachlabs.com/docs/stable/explain-analyze.html)
> - [CockroachDB Documentation - Statement Statistics](https://www.cockroachlabs.com/docs/stable/ui-statements-page.html)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 Pebble (RocksDB) 存储，Raft 共识，支持 Geo-Partitioning。

## EXPLAIN 基本用法


```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';

```

输出示例：
distribution: local
vectorized: true

scan
  table: users@users_pkey
  spans: FULL SCAN
  filter: username = 'alice'

## EXPLAIN 选项


显示详细信息（含列信息和排序）
```sql
EXPLAIN (VERBOSE) SELECT * FROM users WHERE age > 25 ORDER BY age;

```

显示类型信息
```sql
EXPLAIN (TYPES) SELECT * FROM users WHERE age > 25;

```

## EXPLAIN ANALYZE（实际执行）


实际执行并收集统计信息
```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;

```

输出包含：
actual row count: 实际行数
KV rows read: 读取的 KV 行数
KV bytes read: 读取的字节数
estimated row count: 估算行数

## EXPLAIN ANALYZE (DEBUG)


生成可下载的调试包（包含执行计划、跟踪、统计信息）
```sql
EXPLAIN ANALYZE (DEBUG) SELECT * FROM users WHERE age > 25;

```

返回一个 URL，可以在 DB Console 中查看详细信息

## EXPLAIN (DISTSQL)


显示分布式执行计划
```sql
EXPLAIN (DISTSQL) SELECT u.username, COUNT(o.id) AS cnt
FROM users u
JOIN orders o ON u.id = o.user_id
GROUP BY u.username;

```

返回图形化 URL，显示处理器和数据流

## EXPLAIN ANALYZE (DISTSQL)


带实际统计的分布式执行计划
```sql
EXPLAIN ANALYZE (DISTSQL)
SELECT user_id, SUM(amount) FROM orders GROUP BY user_id;

```

## 执行计划关键操作


scan           表扫描（含索引扫描）
filter         过滤
render         投影/表达式计算
lookup join    索引查找连接
hash join      哈希连接
merge join     合并连接
sort           排序
group          分组聚合
distinct       去重
limit          限制行数
union all      联合

## 统计信息管理


创建统计信息
```sql
CREATE STATISTICS stats_users ON username FROM users;
CREATE STATISTICS stats_users_age ON age FROM users;

```

自动统计信息（默认启用）
```sql
SHOW CLUSTER SETTING sql.stats.automatic_collection.enabled;

```

查看表的统计信息
```sql
SHOW STATISTICS FOR TABLE users;

```

## 语句诊断


请求下一次执行时收集诊断包
```sql
SELECT crdb_internal.request_statement_bundle(
    'SELECT * FROM users WHERE age > 25', -- 语句指纹
    0.0,                                   -- 采样率
    '10m'::INTERVAL,                       -- 过期时间
    '0s'::INTERVAL                         -- 最小执行时间
);

```

查看已收集的诊断
```sql
SELECT * FROM system.statement_diagnostics;

```

## DB Console 性能页面


CockroachDB DB Console 提供：
- Statements 页面：语句级性能统计
- Transactions 页面：事务级性能统计
- 执行计划图形化查看
- 热点范围（Hot Ranges）
- 网络延迟

## 查询性能视图


活跃查询
```sql
SELECT query, phase, start AS started_at
FROM [SHOW QUERIES]
WHERE application_name != 'cockroach';

```

会话信息
```sql
SELECT * FROM [SHOW SESSIONS];

```

## 索引建议


22.2+: 执行计划中的索引建议
```sql
EXPLAIN SELECT * FROM users WHERE age > 25 AND status = 1;
```

如果缺少索引，输出会包含：
index recommendations: CREATE INDEX ON users (age) STORING (status, ...)

**注意:** EXPLAIN 显示分布式执行计划和向量化信息
**注意:** EXPLAIN ANALYZE 实际执行并收集 KV 层统计
**注意:** EXPLAIN (DISTSQL) 显示多节点的处理器拓扑
**注意:** EXPLAIN ANALYZE (DEBUG) 生成完整的诊断包
**注意:** CockroachDB 自动收集统计信息（可手动触发）
**注意:** 22.2+ 版本在执行计划中提供索引建议
