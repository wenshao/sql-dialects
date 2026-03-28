# PostgreSQL: 执行计划

> 参考资料:
> - [PostgreSQL Documentation - EXPLAIN](https://www.postgresql.org/docs/current/sql-explain.html)
> - [PostgreSQL Documentation - Using EXPLAIN](https://www.postgresql.org/docs/current/using-explain.html)

## EXPLAIN 基本用法

```sql
EXPLAIN SELECT * FROM users WHERE username = 'alice';
```

输出: Seq Scan on users (cost=0.00..12.50 rows=1 width=100)

cost 的含义:
  cost=启动成本..总成本（任意单位，基于 seq_page_cost=1.0）
  rows: 估算返回行数（基于 pg_statistic 统计信息）
  width: 估算行宽度（字节）

## EXPLAIN ANALYZE: 实际执行

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE age > 25;
```

输出增加: (actual time=0.015..0.120 rows=280 loops=1)
          Planning Time: 0.080 ms
          Execution Time: 0.150 ms

DML 使用事务保护:
```sql
BEGIN;
EXPLAIN ANALYZE DELETE FROM users WHERE status = 0;
ROLLBACK;
```

## EXPLAIN 选项组合

```sql
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE, SETTINGS)
SELECT u.*, COUNT(o.id) AS order_count
FROM users u LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id;
```

ANALYZE:   实际执行，收集运行时统计
BUFFERS:   共享缓冲区命中/读取/脏页统计
COSTS:     显示成本估算（默认开启）
TIMING:    显示实际时间（需要 ANALYZE）
VERBOSE:   显示输出列列表等额外信息
SETTINGS:  显示影响计划的非默认参数 (12+)
WAL:       显示 WAL 记录生成信息 (13+, 需 ANALYZE)

TIMING OFF: 减少 gettimeofday() 系统调用开销 (13+)
```sql
EXPLAIN (ANALYZE, TIMING OFF) SELECT * FROM users;
```

输出格式
```sql
EXPLAIN (FORMAT JSON) SELECT * FROM users;     -- 程序解析友好
EXPLAIN (FORMAT YAML) SELECT * FROM users;
EXPLAIN (FORMAT XML) SELECT * FROM users;
```

## 常见执行计划节点解读

扫描节点:
  Seq Scan:         顺序扫描全表
  Index Scan:       索引扫描 + 回表
  Index Only Scan:  只读索引（需要 Visibility Map 标记页面全可见）
  Bitmap Heap Scan: 先构建位图再批量回表（减少随机 I/O）
  TID Scan:         按 ctid 直接定位行

连接节点:
  Nested Loop:  外表每行查内表（小表驱动大表+索引）
  Hash Join:    小表建哈希表，大表探测（等值 JOIN）
  Merge Join:   两个有序流合并（等值 JOIN，已排序）

聚合节点:
  HashAggregate:  哈希分桶聚合
  GroupAggregate: 排序后分组聚合
  MixedAggregate: GROUPING SETS 的混合策略

其他:
  Sort:     排序（in-memory 或 external sort）
  Limit:    LIMIT 截断
  Append:   UNION ALL 拼接
  Memoize:  缓存嵌套循环内表结果 (14+)

## BUFFERS 信息: I/O 性能分析的关键

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM users WHERE age > 25;
```

Buffers: shared hit=10 read=5 dirtied=2 written=1

shared hit:     缓冲区命中（数据在内存中）
shared read:    从磁盘读取（cache miss）
shared dirtied: 弄脏的页面
shared written: 写回磁盘的页面（eviction 触发）

hit/(hit+read) = 缓存命中率，低于 99% 需要关注

## 统计信息管理

```sql
ANALYZE users;                             -- 更新全表统计
ANALYZE users (username, age);             -- 更新特定列统计

-- 查看统计信息
SELECT relname, reltuples, relpages FROM pg_class WHERE relname = 'users';
SELECT attname, n_distinct, most_common_vals, histogram_bounds
FROM pg_stats WHERE tablename = 'users';
```

调整采样精度
```sql
ALTER TABLE users ALTER COLUMN username SET STATISTICS 1000; -- 默认 100
ANALYZE users;
```

多列统计 (10+): 解决列间相关性导致的基数估算偏差
```sql
CREATE STATISTICS stats_city_age ON city, age FROM users;
ANALYZE users;
```

## 查询计划控制参数

```sql
SET enable_seqscan = off;              -- 禁用顺序扫描（调试用）
SET enable_hashjoin = off;
SET random_page_cost = 1.1;            -- SSD 建议降低（默认 4.0）
SET effective_cache_size = '4GB';      -- 告诉优化器可用内存
SET work_mem = '256MB';                -- 排序/哈希操作的内存
```

## auto_explain + pg_stat_statements

auto_explain: 自动记录慢查询的执行计划
```sql
LOAD 'auto_explain';
SET auto_explain.log_min_duration = '500ms';
SET auto_explain.log_analyze = true;
SET auto_explain.log_buffers = true;
```

pg_stat_statements: 查询性能 Top-N
```sql
SELECT query, calls, total_exec_time, mean_exec_time, rows
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;
```

## 横向对比: 执行计划分析

### EXPLAIN 语法

  PostgreSQL: EXPLAIN (ANALYZE, BUFFERS, ...)
  MySQL:      EXPLAIN [ANALYZE] SELECT ...（8.0.18+ 支持 ANALYZE）
  Oracle:     EXPLAIN PLAN FOR ... + DBMS_XPLAN.DISPLAY
  SQL Server: SET STATISTICS PROFILE ON / SET SHOWPLAN_XML ON

### 独特信息

  PostgreSQL: BUFFERS（缓冲区命中率），WAL（WAL 生成量）
  MySQL:      无 BUFFERS 等价信息
  Oracle:     V$SQL_PLAN + V$SESSION_LONGOPS（最丰富）

## 对引擎开发者的启示

(1) cost 模型的设计:
    PostgreSQL 的成本基于"单位是一次顺序页面读取"。
    seq_page_cost=1.0，random_page_cost=4.0（HDD），SSD 建议 1.1。
    成本模型需要与硬件特性匹配。

(2) BUFFERS 信息对性能调优不可或缺:
    光看执行时间不够——需要知道是 CPU bound 还是 I/O bound。
    hit vs read 的比例直接反映缓存效果。

(3) 多列统计 (10+) 解决了一个经典问题:
    优化器默认假设列间独立，但 city 和 zipcode 高度相关。
    CREATE STATISTICS 让优化器了解列间相关性，改善基数估算。

## 版本演进

PostgreSQL 9.0:  EXPLAIN (FORMAT JSON/YAML/XML)
PostgreSQL 10:   CREATE STATISTICS（多列统计）
PostgreSQL 12:   EXPLAIN (SETTINGS)，JIT 编译信息
PostgreSQL 13:   EXPLAIN (WAL)，TIMING OFF 选项
PostgreSQL 14:   Memoize 节点
PostgreSQL 17:   EXPLAIN (MEMORY)（显示内存使用）
