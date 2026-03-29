# EXPLAIN 与执行计划：各 SQL 方言全对比

> 参考资料:
> - [MySQL 8.0 - EXPLAIN](https://dev.mysql.com/doc/refman/8.0/en/explain.html)
> - [PostgreSQL - EXPLAIN](https://www.postgresql.org/docs/current/sql-explain.html)
> - [SQL Server - Execution Plans](https://learn.microsoft.com/en-us/sql/relational-databases/performance/execution-plans)
> - [Oracle - EXPLAIN PLAN](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/generating-and-displaying-execution-plans.html)

执行计划是 SQL 引擎将声明式查询转化为物理操作序列的蓝图。理解不同引擎的 EXPLAIN 语法、输出格式、Cost 模型和 Hint 机制，是引擎开发者和 DBA 的核心技能。本文覆盖 17+ 种 SQL 方言，从传统 RDBMS 到分布式分析引擎逐一对比。

## EXPLAIN 语法矩阵

### 传统 RDBMS

| 能力 | MySQL | PostgreSQL | Oracle | SQL Server | SQLite | MariaDB | Db2 |
|------|-------|-----------|--------|-----------|--------|---------|-----|
| EXPLAIN | `EXPLAIN SELECT ...` | `EXPLAIN SELECT ...` | `EXPLAIN PLAN FOR SELECT ...` | 不支持 EXPLAIN | `EXPLAIN QUERY PLAN SELECT ...` | `EXPLAIN SELECT ...` | `EXPLAIN SELECT ...` |
| 实际执行统计 | `EXPLAIN ANALYZE` (8.0.18+) | `EXPLAIN ANALYZE` | `DBMS_XPLAN.DISPLAY_CURSOR` | `SET STATISTICS TIME/IO ON` | 不支持 | `ANALYZE` 关键字 | `db2exfmt` |
| FORMAT JSON | 5.6+ | 支持 | 不支持 | 不支持 | 不支持 | 10.1+ | 不支持 |
| FORMAT TREE | 8.0.16+ | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| FORMAT XML | 不支持 | 支持 | 不支持 | `SET SHOWPLAN_XML ON` | 不支持 | 不支持 | 不支持 |
| FORMAT YAML | 不支持 | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| BUFFERS 选项 | 不支持 | `EXPLAIN (BUFFERS)` | 不支持 | `SET STATISTICS IO ON` | 不支持 | 不支持 | 不支持 |
| EXPLAIN DML | 5.6.3+ | 支持 | 支持 | 支持 | 不支持 | 支持 | 支持 |
| 优化器追踪 | `OPTIMIZER_TRACE` | 不支持 | `10046 Trace / SQL Monitor` | 不支持 | 不支持 | `OPTIMIZER_TRACE` | 不支持 |

### 分布式 / NewSQL

| 能力 | TiDB | OceanBase | CockroachDB | YugabyteDB | PolarDB | openGauss | Spanner |
|------|------|-----------|-------------|-----------|---------|-----------|---------|
| EXPLAIN | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 | API/Console |
| EXPLAIN ANALYZE | 支持 | 不支持 | 支持 | 支持 | 支持 | 支持 | 不支持 |
| FORMAT JSON | 支持 | 不支持 | 支持 | 支持 | 支持 | 支持 | 不支持 |
| EXPLAIN (DISTSQL) | 不支持 | 不支持 | 支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| EXPLAIN PERFORMANCE | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 支持 | 不支持 |

### 大数据 / 分析引擎

| 能力 | StarRocks | Doris | Trino | Spark | ClickHouse | Hive | Flink | DuckDB |
|------|----------|-------|-------|-------|-----------|------|-------|--------|
| EXPLAIN | 支持 | 支持 | 支持 | 支持 | 20.6+ | 支持 | 支持 | 支持 |
| EXPLAIN ANALYZE | 支持 | 2.0+ | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 支持 |
| EXPLAIN VERBOSE | 支持 | 支持 | 支持 | 支持 | 不支持 | 不支持 | 不支持 | 支持 |
| EXPLAIN COSTS | 支持 | 不支持 | 不支持 | 支持 | 不支持 | 不支持 | 支持 | 不支持 |
| EXPLAIN PIPELINE | 不支持 | 不支持 | 不支持 | 不支持 | 支持 | 不支持 | 不支持 | 不支持 |
| EXPLAIN CODEGEN | 不支持 | 不支持 | 不支持 | 支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| EXPLAIN GRAPH | 不支持 | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| FORMAT GRAPHVIZ | 不支持 | 不支持 | 支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| Query Profile (UI) | FE UI | FE UI | Web UI | Web UI | 不支持 | Tez UI | Web UI | 不支持 |

### 云数据仓库

| 能力 | BigQuery | Snowflake | Redshift | Synapse | Databricks | Vertica | Teradata |
|------|---------|-----------|----------|---------|-----------|---------|---------|
| EXPLAIN | SQL 不支持（Dry Run 估算字节 + 控制台 Query Plan 可视化） | `EXPLAIN USING TEXT` | 支持 | 支持 | 支持 | 支持 | `EXPLAIN SELECT ...` |
| EXPLAIN ANALYZE | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 | 不支持 |
| EXPLAIN VERBOSE | 不支持 | 不支持 | 支持 | 不支持 | 支持 | 支持 | 不支持 |
| Dry Run / 预估 | 支持 (`--dry_run`) | 不支持 | 不支持 | 支持 (估算) | 不支持 | 不支持 | 不支持 |
| Query Profile (UI) | 支持 | 支持 | STL 系统表 | DMV | Spark UI | MC 系统表 | DBQL |

## 各引擎 EXPLAIN 语法详解

### MySQL

```sql
-- 传统表格格式 (默认)
EXPLAIN SELECT * FROM orders WHERE customer_id = 100;
-- 输出列: id | select_type | table | type | possible_keys | key | rows | Extra

-- JSON 格式 (5.6+): 包含 cost 信息
EXPLAIN FORMAT=JSON SELECT * FROM orders o
  JOIN customers c ON o.customer_id = c.id
  WHERE c.country = 'CN';

-- TREE 格式 (8.0.16+): 迭代器模型, 最直观
EXPLAIN FORMAT=TREE SELECT * FROM orders o
  JOIN customers c ON o.customer_id = c.id
  WHERE c.country = 'CN';
-- 输出示例:
-- -> Nested loop inner join  (cost=2.40 rows=1)
--     -> Filter: (c.country = 'CN')  (cost=1.10 rows=1)
--         -> Table scan on c  (cost=1.10 rows=5)
--     -> Index lookup on o using idx_customer (customer_id=c.id)  (cost=1.30 rows=1)

-- EXPLAIN ANALYZE (8.0.18+): 实际执行, 输出真实时间和行数
EXPLAIN ANALYZE SELECT * FROM orders
  WHERE order_date BETWEEN '2024-01-01' AND '2024-12-31';
-- 输出示例:
-- -> Filter: (orders.order_date between '2024-01-01' and '2024-12-31')
--     (cost=1.10 rows=1) (actual time=0.023..0.045 rows=280 loops=1)
--     -> Table scan on orders  (cost=1.10 rows=1000)
--         (actual time=0.015..0.032 rows=1000 loops=1)

-- 优化器追踪: 查看优化器为什么做出某个选择
SET optimizer_trace = 'enabled=on';
SELECT * FROM orders WHERE customer_id = 100;
SELECT * FROM information_schema.OPTIMIZER_TRACE\G
SET optimizer_trace = 'enabled=off';
```

### PostgreSQL

```sql
-- 基本 EXPLAIN: 只做计划, 不执行
EXPLAIN SELECT * FROM orders WHERE customer_id = 100;
-- 输出: Index Scan using idx_customer on orders  (cost=0.29..8.31 rows=1 width=64)

-- EXPLAIN ANALYZE: 实际执行
EXPLAIN ANALYZE SELECT * FROM orders o
  JOIN customers c ON o.customer_id = c.id
  WHERE c.country = 'CN';
-- 输出:
-- Hash Join  (cost=1.09..23.50 rows=10 width=128) (actual time=0.035..0.120 rows=8 loops=1)
--   Hash Cond: (o.customer_id = c.id)
--   -> Seq Scan on orders o  (cost=0.00..17.50 rows=750 width=64) (actual time=...)
--   -> Hash  (cost=1.06..1.06 rows=2 width=64) (actual time=0.010..0.011 rows=2 loops=1)
--        -> Seq Scan on customers c  (cost=0.00..1.06 rows=2 width=64) (actual time=...)
--            Filter: (country = 'CN')
-- Planning Time: 0.150 ms
-- Execution Time: 0.180 ms

-- 全选项组合: 生产环境排查利器
EXPLAIN (ANALYZE, BUFFERS, COSTS, TIMING, VERBOSE, SETTINGS, WAL, FORMAT JSON)
SELECT u.*, COUNT(o.id) AS order_count
FROM users u LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id;

-- BUFFERS 示例输出:
-- Buffers: shared hit=12 read=3    -- 12 个页面在缓冲池命中, 3 个从磁盘读取
-- Buffers: shared dirtied=2        -- 2 个页面被标记为脏页 (DML 时)

-- DML 使用事务保护
BEGIN;
EXPLAIN ANALYZE DELETE FROM orders WHERE status = 'cancelled';
ROLLBACK;  -- 回滚, 避免真正删除数据

-- auto_explain: 自动记录慢查询执行计划
-- postgresql.conf:
-- shared_preload_libraries = 'auto_explain'
-- auto_explain.log_min_duration = '1s'
-- auto_explain.log_analyze = true
-- auto_explain.log_buffers = true
```

### Oracle

```sql
-- EXPLAIN PLAN FOR: 将计划存入 PLAN_TABLE
EXPLAIN PLAN FOR
SELECT o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id
WHERE o.order_date > DATE '2024-01-01';

-- 查看计划: DBMS_XPLAN.DISPLAY
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
-- 输出:
-- --------------------------------------------------------------------------------------------------
-- | Id  | Operation                    | Name          | Rows  | Bytes | Cost (%CPU) | Time     |
-- --------------------------------------------------------------------------------------------------
-- |   0 | SELECT STATEMENT             |               |   100 |  9800 |    25   (4) | 00:00:01 |
-- |   1 |  HASH JOIN                   |               |   100 |  9800 |    25   (4) | 00:00:01 |
-- |   2 |   TABLE ACCESS FULL          | CUSTOMERS     |    50 |  2450 |    12   (0) | 00:00:01 |
-- |*  3 |   TABLE ACCESS BY INDEX ROWID| ORDERS        |   100 |  4900 |    12   (0) | 00:00:01 |
-- |*  4 |    INDEX RANGE SCAN          | IDX_ORD_DATE  |   100 |       |     2   (0) | 00:00:01 |
-- --------------------------------------------------------------------------------------------------

-- 查看实际运行后的执行计划 (含真实统计)
SELECT /*+ GATHER_PLAN_STATISTICS */ o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id
WHERE o.order_date > DATE '2024-01-01';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));
-- 增加列: Starts | E-Rows | A-Rows | A-Time | Buffers | Reads

-- SQL Monitor (企业版): 实时监控长时间运行的 SQL
SELECT DBMS_SQLTUNE.REPORT_SQL_MONITOR(
  sql_id => '7h5qx1234abcd',
  type => 'HTML'
) FROM dual;
```

### SQL Server

```sql
-- SQL Server 不使用 EXPLAIN, 而是 SET 语句

-- 预估执行计划 (不执行)
SET SHOWPLAN_TEXT ON;
GO
SELECT * FROM orders WHERE customer_id = 100;
GO
SET SHOWPLAN_TEXT OFF;
GO

-- XML 格式预估计划 (SSMS 可视化)
SET SHOWPLAN_XML ON;
GO
SELECT o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id;
GO
SET SHOWPLAN_XML OFF;
GO

-- 实际执行计划 + IO 统计 + 时间统计
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SET STATISTICS XML ON;

SELECT o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id
WHERE o.order_date > '2024-01-01';

-- 输出:
-- Table 'orders'. Scan count 1, logical reads 150, physical reads 3
-- SQL Server Execution Times: CPU time = 16 ms, elapsed time = 22 ms

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
SET STATISTICS XML OFF;

-- SSMS: Ctrl+L 查看预估计划, Ctrl+M 包含实际计划后执行
```

### SQLite

```sql
-- EXPLAIN QUERY PLAN: 高层操作概览
EXPLAIN QUERY PLAN
SELECT o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id
WHERE o.order_date > '2024-01-01';
-- 输出:
-- QUERY PLAN
-- |--SCAN o USING INDEX idx_ord_date (order_date>?)
-- `--SEARCH c USING INTEGER PRIMARY KEY (rowid=?)

-- EXPLAIN: 底层字节码 (Virtual Machine 操作码)
EXPLAIN SELECT * FROM orders WHERE customer_id = 100;
-- 输出: addr | opcode | p1 | p2 | p3 | p4 | p5 | comment
-- 0    | Init   | 0  | 12 | 0  |    | 0  |
-- 1    | OpenRead | 0 | 2  | 0  | 5  | 0  |
-- ...
-- SQLite 执行计划非常简洁, 没有 cost 估算
```

### TiDB

```sql
-- 基本 EXPLAIN
EXPLAIN SELECT * FROM orders WHERE customer_id = 100;
-- 输出: id | estRows | task | access object | operator info

-- EXPLAIN ANALYZE: 实际执行
EXPLAIN ANALYZE SELECT o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id
WHERE c.country = 'CN';
-- 输出增加: actRows | execution info | memory | disk

-- EXPLAIN FORMAT='dot': 生成 Graphviz 图
EXPLAIN FORMAT='dot' SELECT * FROM orders o
  JOIN customers c ON o.customer_id = c.id;

-- EXPLAIN FORMAT='brief': 简洁输出
EXPLAIN FORMAT='brief' SELECT * FROM orders WHERE status = 1;

-- 查看 TiKV Coprocessor 下推情况
EXPLAIN SELECT COUNT(*) FROM orders WHERE amount > 1000;
-- 注意 task 列: cop[tikv] 表示下推到 TiKV 执行
-- root 表示在 TiDB Server 执行
```

### CockroachDB

```sql
-- 基本 EXPLAIN
EXPLAIN SELECT * FROM orders WHERE customer_id = 100;

-- EXPLAIN ANALYZE: 实际执行
EXPLAIN ANALYZE SELECT o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id;

-- EXPLAIN (DISTSQL): 查看分布式执行计划
EXPLAIN (DISTSQL) SELECT customer_id, SUM(amount)
FROM orders GROUP BY customer_id;
-- 输出包含各节点的数据流图, 可以看到哪些节点参与执行

-- EXPLAIN (OPT): 查看优化器选择过程
EXPLAIN (OPT, VERBOSE) SELECT * FROM orders WHERE customer_id = 100;

-- EXPLAIN (VEC): 向量化执行引擎的计划
EXPLAIN (VEC) SELECT customer_id, SUM(amount)
FROM orders GROUP BY customer_id;
```

## 输出格式对比

各引擎执行计划的输出格式差异显著，影响可读性和工具集成。

### 格式类型

```
┌─────────────┬─────────────────────────────────────────────────────────┐
│ 格式        │ 支持引擎                                               │
├─────────────┼─────────────────────────────────────────────────────────┤
│ 表格 (行列) │ MySQL (TRADITIONAL), Oracle (DBMS_XPLAN), SQL Server   │
│ 树状 (缩进) │ MySQL (TREE), PostgreSQL (TEXT), TiDB, CockroachDB     │
│ JSON        │ MySQL, PostgreSQL, TiDB, CockroachDB, Trino            │
│ XML         │ PostgreSQL, SQL Server (SHOWPLAN_XML)                   │
│ YAML        │ PostgreSQL                                              │
│ Graphviz    │ Trino (FORMAT GRAPHVIZ), TiDB (FORMAT='dot')            │
│ 图形化 (UI) │ SQL Server (SSMS), Oracle (Enterprise Manager),        │
│             │ BigQuery (Query Plan), Snowflake (Query Profile),       │
│             │ StarRocks/Doris (FE UI), Spark (Web UI)                │
└─────────────┴─────────────────────────────────────────────────────────┘
```

### 表格 vs 树状 vs JSON 对比

同一查询在不同格式下的表现:

```sql
-- 查询
SELECT c.name, COUNT(o.id) AS cnt
FROM customers c JOIN orders o ON c.id = o.customer_id
WHERE c.country = 'CN'
GROUP BY c.name;
```

MySQL 传统表格:
```
+----+-------------+-------+------+---------------+---------+---------+-----------+------+----------+--------------------------+
| id | select_type | table | type | possible_keys | key     | key_len | ref       | rows | filtered | Extra                    |
+----+-------------+-------+------+---------------+---------+---------+-----------+------+----------+--------------------------+
|  1 | SIMPLE      | c     | ref  | PRIMARY,idx   | idx_cty | 30      | const     |    5 |   100.00 | Using index condition    |
|  1 | SIMPLE      | o     | ref  | idx_cust      | idx_cust| 4       | db.c.id   |   10 |   100.00 | NULL                     |
+----+-------------+-------+------+---------------+---------+---------+-----------+------+----------+--------------------------+
```

MySQL TREE 格式 (8.0.16+):
```
-> Group aggregate: count(o.id)  (cost=6.50 rows=5)
    -> Nested loop inner join  (cost=5.50 rows=50)
        -> Index lookup on c using idx_cty (country='CN')  (cost=1.50 rows=5)
        -> Index lookup on o using idx_cust (customer_id=c.id)  (cost=0.80 rows=10)
```

PostgreSQL TEXT 格式 (默认):
```
HashAggregate  (cost=35.50..36.00 rows=5 width=72)
  Group Key: c.name
  -> Hash Join  (cost=1.09..35.00 rows=50 width=68)
        Hash Cond: (o.customer_id = c.id)
        -> Seq Scan on orders o  (cost=0.00..20.00 rows=1000 width=8)
        -> Hash  (cost=1.06..1.06 rows=5 width=64)
              -> Seq Scan on customers c  (cost=0.00..1.06 rows=5 width=64)
                    Filter: (country = 'CN')
```

PostgreSQL JSON 格式:
```json
[
  {
    "Plan": {
      "Node Type": "Aggregate",
      "Strategy": "Hashed",
      "Group Key": ["c.name"],
      "Startup Cost": 35.50,
      "Total Cost": 36.00,
      "Plan Rows": 5,
      "Plans": [
        {
          "Node Type": "Hash Join",
          "Join Type": "Inner",
          "Hash Cond": "(o.customer_id = c.id)",
          "Plans": [...]
        }
      ]
    }
  }
]
```

## Cost 模型对比

各引擎对 Cost 的定义和单位完全不同，不能跨引擎比较。

### Cost 单位与含义

```
┌────────────┬──────────────────────────────────────────────────────────────────┐
│ 引擎       │ Cost 含义                                                       │
├────────────┼──────────────────────────────────────────────────────────────────┤
│ PostgreSQL │ 以顺序页面读取为基准单位 1.0 (seq_page_cost=1.0)                  │
│            │ 随机页面读取 = 4.0 (random_page_cost=4.0)                        │
│            │ CPU 处理一行 = 0.01 (cpu_tuple_cost=0.01)                        │
│            │ CPU 处理一个索引条目 = 0.005 (cpu_index_tuple_cost=0.005)         │
│            │ Cost = startup_cost..total_cost                                  │
├────────────┼──────────────────────────────────────────────────────────────────┤
│ MySQL      │ Cost 代表估算行数 * 访问代价 (内部单位)                            │
│            │ TREE 格式输出的 cost 值与 JSON 格式中 query_cost 相同              │
│            │ 引擎可通过 mysql.engine_cost / mysql.server_cost 表调整            │
├────────────┼──────────────────────────────────────────────────────────────────┤
│ Oracle     │ Cost = 估算的 I/O 次数 + CPU 时间折算                             │
│            │ 单位: 约等于单块 I/O 操作次数                                     │
│            │ %CPU 列显示 CPU 占总 Cost 的比例                                  │
│            │ Time 列显示预估执行时间 (格式 HH:MI:SS)                           │
├────────────┼──────────────────────────────────────────────────────────────────┤
│ SQL Server │ 不直接暴露数字 Cost, 使用 Subtree Cost (相对单位)                  │
│            │ Estimated Number of Rows, Estimated I/O Cost, Estimated CPU Cost │
│            │ 以 SSMS 图形计划的百分比展示最直观                                 │
├────────────┼──────────────────────────────────────────────────────────────────┤
│ TiDB       │ estRows: 估算行数 (基于统计信息)                                  │
│            │ task: root (TiDB) / cop[tikv] (TiKV) / cop[tiflash] (TiFlash)    │
│            │ EXPLAIN ANALYZE 增加 actRows / execution info / memory / disk     │
├────────────┼──────────────────────────────────────────────────────────────────┤
│ StarRocks  │ cardinality: 估算行数                                            │
│            │ avgRowSize: 平均行宽                                             │
│            │ cost: CBO 内部代价 (不同版本含义可能变化)                          │
├────────────┼──────────────────────────────────────────────────────────────────┤
│ Trino      │ rows: 估算行数                                                  │
│            │ cpu / memory / network: 预估资源消耗 (字节为单位)                  │
└────────────┴──────────────────────────────────────────────────────────────────┘
```

### PostgreSQL Cost 计算示例

```sql
-- 参数查看
SHOW seq_page_cost;       -- 默认 1.0
SHOW random_page_cost;    -- 默认 4.0 (SSD 可改为 1.1)
SHOW cpu_tuple_cost;      -- 默认 0.01
SHOW cpu_operator_cost;   -- 默认 0.0025

-- 全表扫描 Cost 估算:
-- 假设 orders 表: 100 个数据页, 10000 行
-- cost = seq_page_cost * 页数 + cpu_tuple_cost * 行数
--      = 1.0 * 100 + 0.01 * 10000 = 200.0

-- 索引扫描 Cost 估算:
-- 假设索引 3 层, 命中 50 行, 需要 50 次回表随机读
-- cost = random_page_cost * (索引页 + 回表页) + cpu_index_tuple_cost * 索引行 + cpu_tuple_cost * 结果行
--      = 4.0 * (3 + 50) + 0.005 * 50 + 0.01 * 50 = 212.75
-- 当选择性低时, 索引扫描 cost > 全表扫描 cost, 优化器会选择全表扫描

-- SSD 优化: 缩小随机 I/O 与顺序 I/O 的差距
ALTER SYSTEM SET random_page_cost = 1.1;  -- SSD 上随机读与顺序读差距小
SELECT pg_reload_conf();
```

### MySQL Cost 配置

```sql
-- 查看服务器层代价参数
SELECT * FROM mysql.server_cost;
-- cost_name                    | cost_value
-- disk_temptable_create_cost   | 20.0
-- disk_temptable_row_cost      | 0.5
-- key_compare_cost             | 0.05
-- memory_temptable_create_cost | 1.0
-- memory_temptable_row_cost    | 0.1
-- row_evaluate_cost            | 0.1

-- 查看存储引擎层代价参数
SELECT * FROM mysql.engine_cost;
-- cost_name              | engine_name | cost_value
-- io_block_read_cost     | default     | 1.0
-- memory_block_read_cost | default     | 0.25

-- 针对 SSD 调优: 降低 I/O 代价
UPDATE mysql.engine_cost
SET cost_value = 0.5
WHERE cost_name = 'io_block_read_cost';
FLUSH OPTIMIZER_COSTS;
```

## Hint 语法对比

Hint 是开发者手动干预优化器决策的手段，各引擎的 Hint 机制差异巨大。

### Hint 语法概览

```sql
-- Oracle: /*+ hint */ 注释式 (最完善的 Hint 系统)
SELECT /*+ FULL(o) USE_HASH(o c) PARALLEL(o 4) */
  o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id;

-- Oracle 常用 Hint:
-- 访问路径: FULL, INDEX, INDEX_FFS, NO_INDEX
-- JOIN 方式: USE_HASH, USE_NL, USE_MERGE
-- JOIN 顺序: LEADING, ORDERED
-- 并行:     PARALLEL(table degree)
-- 其他:     PUSH_PRED, NO_MERGE, MATERIALIZE, RESULT_CACHE

-- MySQL 8.0+: /*+ hint */ 注释式 (受 Oracle 启发)
SELECT /*+ JOIN_ORDER(c, o) HASH_JOIN(o) NO_INDEX(o idx_status) */
  o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id;

-- MySQL 旧式索引 Hint (仍然有效):
SELECT * FROM orders USE INDEX (idx_customer) WHERE customer_id = 100;
SELECT * FROM orders FORCE INDEX (idx_date) WHERE order_date > '2024-01-01';
SELECT * FROM orders IGNORE INDEX (idx_status) WHERE status = 1;

-- MySQL 8.0 新 Hint 分类:
-- JOIN 顺序:  JOIN_ORDER, JOIN_PREFIX, JOIN_SUFFIX, JOIN_FIXED_ORDER
-- JOIN 类型:  HASH_JOIN, NO_HASH_JOIN, BNL, NO_BNL (8.0.18 前)
-- 索引:       INDEX, NO_INDEX, INDEX_MERGE, NO_INDEX_MERGE
--             GROUP_INDEX, ORDER_INDEX, JOIN_INDEX, NO_JOIN_INDEX
-- 子查询:     SEMIJOIN, NO_SEMIJOIN
-- 优化器开关: SET_VAR(optimizer_switch='...')
-- 资源组:     RESOURCE_GROUP(group_name)

-- PostgreSQL: 无原生 Hint, 通过 pg_hint_plan 扩展实现
-- 安装: CREATE EXTENSION pg_hint_plan;
SELECT /*+ HashJoin(o c) SeqScan(c) IndexScan(o idx_customer) */
  o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id;

-- pg_hint_plan 支持的 Hint:
-- 扫描方式: SeqScan, IndexScan, IndexOnlyScan, BitmapScan, TidScan, NoSeqScan, ...
-- JOIN 方式: NestLoop, HashJoin, MergeJoin, NoNestLoop, ...
-- JOIN 顺序: Leading((c o))   -- 嵌套括号表示 join 树结构
-- 并行:     Parallel(t 4 hard)
-- 其他:     Set(random_page_cost 1.1)  -- 在 Hint 里设置 GUC 参数

-- SQL Server: 查询 Hint 和表 Hint
SELECT o.*, c.name
FROM orders o WITH (INDEX(idx_date))       -- 表 Hint
  JOIN customers c WITH (NOLOCK) ON o.customer_id = c.id
OPTION (HASH JOIN, MAXDOP 4);             -- 查询 Hint

-- SQL Server 常用 Hint:
-- 表 Hint:   INDEX, NOLOCK, ROWLOCK, TABLOCK, FORCESEEK, FORCESCAN
-- 查询 Hint: HASH JOIN, LOOP JOIN, MERGE JOIN, FORCE ORDER
--            MAXDOP, OPTIMIZE FOR, RECOMPILE, USE PLAN

-- TiDB: /*+ hint */ 注释式 (兼容 MySQL 8.0 风格)
SELECT /*+ HASH_JOIN(o, c) USE_INDEX(o, idx_customer) READ_FROM_STORAGE(tikv[o], tiflash[c]) */
  o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id;

-- TiDB 特有 Hint:
-- READ_FROM_STORAGE(tikv[t1], tiflash[t2])  -- 指定从 TiKV 或 TiFlash 读取
-- MPP_1PHASE_AGG, MPP_2PHASE_AGG           -- TiFlash MPP 聚合策略
-- SHUFFLE_JOIN, BROADCAST_JOIN              -- TiFlash MPP JOIN 策略

-- StarRocks / Doris: 通过 session 变量控制, 无 SQL-level Hint
-- StarRocks:
SET enable_hash_join = true;
SET new_planner_optimize_timeout = 3000;
-- Doris:
SET enable_nereids_planner = true;
SET exec_mem_limit = 8589934592;

-- Spark SQL: /*+ hint */
SELECT /*+ BROADCAST(c) */ o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id;
-- BROADCAST, SHUFFLE_HASH, SHUFFLE_REPLICATE_NL, MERGE
-- COALESCE(n), REPARTITION(n), REPARTITION_BY_RANGE(n, col)

-- Trino: 不支持 SQL Hint, 通过 session property 控制
SET SESSION join_distribution_type = 'BROADCAST';
SET SESSION join_reordering_strategy = 'AUTOMATIC';
```

## 执行算子对比

不同引擎对同一种物理算子的命名和展示方式不同。

### JOIN 算子

```
┌──────────────────┬──────────────────────────────────────────────────────┐
│ JOIN 算法        │ 各引擎中的名称                                       │
├──────────────────┼──────────────────────────────────────────────────────┤
│ Nested Loop Join │ MySQL: Nested loop inner join                       │
│                  │ PostgreSQL: Nested Loop                              │
│                  │ Oracle: NESTED LOOPS                                 │
│                  │ SQL Server: Nested Loops                             │
│                  │ TiDB: IndexJoin / IndexHashJoin / IndexMergeJoin     │
│                  │ StarRocks: NESTLOOP JOIN (较少使用)                   │
│                  │ CockroachDB: lookup join                             │
├──────────────────┼──────────────────────────────────────────────────────┤
│ Hash Join        │ MySQL: Hash (8.0.18+, 仅等值 JOIN)                   │
│                  │ PostgreSQL: Hash Join                                │
│                  │ Oracle: HASH JOIN                                    │
│                  │ SQL Server: Hash Match                               │
│                  │ TiDB: HashJoin                                       │
│                  │ StarRocks: HASH JOIN                                 │
│                  │ Trino: InnerJoin (Hash)                              │
│                  │ CockroachDB: hash join                               │
│                  │ DuckDB: HASH_JOIN                                    │
├──────────────────┼──────────────────────────────────────────────────────┤
│ Sort Merge Join  │ MySQL: 不支持                                        │
│                  │ PostgreSQL: Merge Join                               │
│                  │ Oracle: SORT MERGE JOIN                              │
│                  │ SQL Server: Merge Join                               │
│                  │ TiDB: MergeJoin                                      │
│                  │ StarRocks: 不支持                                     │
│                  │ Trino: 不支持                                         │
│                  │ CockroachDB: merge join                              │
└──────────────────┴──────────────────────────────────────────────────────┘
```

### 扫描算子

```
┌─────────────────┬──────────────────────────────────────────────────────┐
│ 扫描方式        │ 各引擎中的名称                                       │
├─────────────────┼──────────────────────────────────────────────────────┤
│ 全表扫描        │ MySQL: Table scan on t / ALL                        │
│                 │ PostgreSQL: Seq Scan on t                            │
│                 │ Oracle: TABLE ACCESS FULL                            │
│                 │ SQL Server: Table Scan / Clustered Index Scan        │
│                 │ TiDB: TableFullScan                                  │
│                 │ StarRocks: OlapScanNode                              │
│                 │ CockroachDB: full scan                               │
│                 │ DuckDB: SEQ_SCAN                                     │
├─────────────────┼──────────────────────────────────────────────────────┤
│ 索引扫描        │ MySQL: Index lookup on t using idx                   │
│                 │ PostgreSQL: Index Scan using idx on t                 │
│                 │ Oracle: INDEX RANGE SCAN + TABLE ACCESS BY INDEX ROWID│
│                 │ SQL Server: Index Seek                                │
│                 │ TiDB: IndexRangeScan + TableRowIDScan                │
│                 │ CockroachDB: scan (with constraint)                  │
│                 │ DuckDB: INDEX_SCAN                                   │
├─────────────────┼──────────────────────────────────────────────────────┤
│ 仅索引扫描      │ MySQL: Index scan (covering index)                   │
│ (覆盖索引)      │ PostgreSQL: Index Only Scan                          │
│                 │ Oracle: INDEX FAST FULL SCAN                         │
│                 │ SQL Server: Index Scan (非聚簇, covering)             │
│                 │ TiDB: IndexFullScan (covering)                       │
├─────────────────┼──────────────────────────────────────────────────────┤
│ 位图索引扫描    │ MySQL: 不支持 (使用 Index Merge)                      │
│                 │ PostgreSQL: Bitmap Heap Scan + Bitmap Index Scan      │
│                 │ Oracle: BITMAP INDEX SINGLE VALUE                    │
│                 │ SQL Server: 不支持 (使用 Index Intersection)          │
│                 │ Greenplum: Bitmap Heap Scan                          │
└─────────────────┴──────────────────────────────────────────────────────┘
```

### 聚合算子

```
┌────────────────┬──────────────────────────────────────────────────────┐
│ 聚合方式       │ 各引擎中的名称                                       │
├────────────────┼──────────────────────────────────────────────────────┤
│ Hash 聚合      │ PostgreSQL: HashAggregate                            │
│                │ Oracle: HASH GROUP BY                                │
│                │ MySQL: <tmp table> + Group aggregate (8.0.16+)       │
│                │ SQL Server: Hash Match (Aggregate)                   │
│                │ TiDB: HashAgg                                        │
│                │ StarRocks: AGGREGATE (hash)                          │
│                │ Trino: Aggregate (HASH)                              │
│                │ DuckDB: HASH_GROUP_BY                                │
├────────────────┼──────────────────────────────────────────────────────┤
│ 排序聚合       │ PostgreSQL: GroupAggregate (需要预排序)                │
│                │ Oracle: SORT GROUP BY                                │
│                │ SQL Server: Stream Aggregate                         │
│                │ TiDB: StreamAgg                                      │
│                │ StarRocks: AGGREGATE (sort)                          │
├────────────────┼──────────────────────────────────────────────────────┤
│ 流式/增量聚合  │ Flink: GroupAggregate (增量更新状态)                   │
│                │ Materialize: Reduce (差分计算)                        │
│                │ ksqlDB: AGGREGATE (Kafka Streams)                    │
└────────────────┴──────────────────────────────────────────────────────┘
```

## 分布式执行计划

分布式引擎的执行计划中包含数据交换 (Exchange / Shuffle) 算子，这是与单机引擎最大的区别。

### 数据交换策略

```
三种基本策略:

1. Broadcast (广播): 将小表复制到所有节点
   适用场景: 一侧表很小 (< 几十 MB)
   网络开销: |小表| * N (N = 节点数)

2. Shuffle (重分布/Hash Partition): 按 JOIN key 重新分区
   适用场景: 两侧都是大表
   网络开销: |左表| + |右表| (全量数据移动)

3. Colocate (本地/共置): 数据已按 JOIN key 分区在同一节点
   适用场景: 建表时指定了 Colocate Group / Distribution Key
   网络开销: 0 (无数据移动)
```

### StarRocks

```sql
EXPLAIN SELECT c.city, SUM(o.amount) AS total
FROM orders o JOIN customers c ON o.customer_id = c.id
GROUP BY c.city;

-- 输出示例:
-- PLAN FRAGMENT 0  -- 结果聚合 Fragment
--   OUTPUT EXPRS: c.city | sum(o.amount)
--   PARTITION: UNPARTITIONED
--   RESULT SINK
--   6: AGGREGATE (merge finalize)     -- 最终聚合
--     5: EXCHANGE                      -- 从 Fragment 1 收集
--        PARTITION: HASH_PARTITIONED(c.city)  -- 按 city Hash 分布
--
-- PLAN FRAGMENT 1  -- 分布式执行 Fragment
--   4: AGGREGATE (update serialize)   -- 局部聚合
--     3: HASH JOIN
--        join op: INNER JOIN
--        hash predicates: o.customer_id = c.id
--        2: EXCHANGE                   -- 接收 orders 数据
--           PARTITION: HASH_PARTITIONED(o.customer_id)  -- Shuffle
--        1: OlapScanNode              -- 扫描 customers (本地)
--   0: OlapScanNode                   -- 扫描 orders (本地)

-- Colocate JOIN: 如果 orders 和 customers 属于同一 Colocate Group
-- 输出: join op: INNER JOIN (COLOCATE)
-- 没有 EXCHANGE 节点, 数据无需网络传输

-- 查看是否使用了 Colocate
EXPLAIN SELECT o.*, c.name
FROM orders o JOIN customers c ON o.customer_id = c.id;
-- 关注: COLOCATE 标记和是否有 EXCHANGE 节点
```

### Apache Doris

```sql
EXPLAIN SELECT c.city, SUM(o.amount) AS total
FROM orders o JOIN customers c ON o.customer_id = c.id
GROUP BY c.city;

-- 输出类似 StarRocks (同源):
-- PLAN FRAGMENT 0
--   PARTITION: UNPARTITIONED
--   6:VAGGREGATE (merge finalize)
--     5:VEXCHANGE
--       PARTITION: HASH_PARTITIONED: c.city
-- PLAN FRAGMENT 1
--   PARTITION: HASH_PARTITIONED: o.customer_id
--   4:VAGGREGATE (update serialize)
--     3:VHASH JOIN
--       |  join op: INNER JOIN(BROADCAST)   -- 或 SHUFFLE / COLOCATE
--       2:VEXCHANGE                          -- Broadcast 或 Shuffle 交换
-- PLAN FRAGMENT 2
--   1:VOlapScanNode  TABLE: customers
-- PLAN FRAGMENT 3
--   0:VOlapScanNode  TABLE: orders

-- Doris 特有: EXPLAIN GRAPH (DOT 格式输出)
EXPLAIN GRAPH SELECT c.city, SUM(o.amount)
FROM orders o JOIN customers c ON o.customer_id = c.id
GROUP BY c.city;

-- Doris 强制使用特定 JOIN 策略
SELECT o.*, c.name
FROM orders o JOIN [broadcast] customers c ON o.customer_id = c.id;

SELECT o.*, c.name
FROM orders o JOIN [shuffle] customers c ON o.customer_id = c.id;

SELECT o.*, c.name
FROM orders o JOIN [bucket] customers c ON o.customer_id = c.id;  -- Colocate
```

### Trino

```sql
EXPLAIN SELECT c.city, SUM(o.amount) AS total
FROM orders o JOIN customers c ON o.customer_id = c.id
GROUP BY c.city;

-- 输出示例:
-- Fragment 0 [SINGLE]
--   Output[city, total]
--     Aggregate(FINAL)[city]
--       total := sum(sum_partial)
--       RemoteExchange[GATHER]
--         Fragment 1 [HASH]
--           Aggregate(PARTIAL)[city]
--             sum_partial := sum(amount)
--             InnerJoin[customer_id = id]
--               Distribution: PARTITIONED     -- Shuffle JOIN
--               RemoteExchange[REPARTITION] by (customer_id)
--                 Fragment 2 [SOURCE]
--                   TableScan[orders]
--               LocalExchange[HASH] by (id)
--                 RemoteExchange[REPARTITION] by (id)
--                   Fragment 3 [SOURCE]
--                     TableScan[customers]

-- 分布类型:
-- [SINGLE]:    单节点执行
-- [HASH]:      按哈希键分布
-- [SOURCE]:    数据源节点
-- [BROADCAST]: 广播分布

-- EXPLAIN ANALYZE: 包含实际行数和时间
EXPLAIN ANALYZE SELECT c.city, SUM(o.amount)
FROM orders o JOIN customers c ON o.customer_id = c.id
GROUP BY c.city;

-- Graphviz 输出: 可用于可视化工具
EXPLAIN (FORMAT GRAPHVIZ) SELECT c.city, SUM(o.amount)
FROM orders o JOIN customers c ON o.customer_id = c.id
GROUP BY c.city;
```

### Spark SQL

```sql
-- 基本 EXPLAIN
EXPLAIN SELECT c.city, SUM(o.amount) AS total
FROM orders o JOIN customers c ON o.customer_id = c.id
GROUP BY c.city;

-- 输出示例:
-- == Physical Plan ==
-- AdaptiveSparkPlan isFinalPlan=false
-- +- HashAggregate(keys=[city], functions=[sum(amount)])
--    +- Exchange hashpartitioning(city, 200)            -- Shuffle
--       +- HashAggregate(keys=[city], functions=[partial_sum(amount)])
--          +- BroadcastHashJoin [customer_id], [id], Inner, BuildRight
--             :- FileScan parquet orders [customer_id, amount]
--             +- BroadcastExchange HashedRelationBroadcastMode
--                +- FileScan parquet customers [id, city]

-- EXPLAIN EXTENDED: 包含逻辑计划和优化后计划
EXPLAIN EXTENDED SELECT c.city, SUM(o.amount)
FROM orders o JOIN customers c ON o.customer_id = c.id
GROUP BY c.city;
-- 输出:
-- == Parsed Logical Plan ==
-- == Analyzed Logical Plan ==
-- == Optimized Logical Plan ==
-- == Physical Plan ==

-- EXPLAIN CODEGEN: 查看 Tungsten 代码生成
EXPLAIN CODEGEN SELECT SUM(amount) FROM orders WHERE status = 'completed';
-- 输出生成的 Java 代码 (WholeStageCodegen)

-- EXPLAIN FORMATTED: 结构化输出
EXPLAIN FORMATTED SELECT c.city, SUM(o.amount)
FROM orders o JOIN customers c ON o.customer_id = c.id
GROUP BY c.city;

-- Spark 分布式算子关键词:
-- Exchange hashpartitioning:      Shuffle (按 hash key 重分布)
-- BroadcastExchange:              Broadcast (广播小表)
-- Exchange SinglePartition:       汇聚到单分区
-- Exchange RoundRobinPartitioning: 轮询分布
-- Exchange rangepartitioning:      范围分区 (用于排序)

-- AQE (Adaptive Query Execution): 运行时自动调整
-- isFinalPlan=false 表示计划可能在运行时被 AQE 修改
-- AQE 能力:
--   自动切换 Shuffle JOIN -> Broadcast JOIN (当运行时发现一侧数据量小)
--   自动合并小分区 (Coalesce Shuffle Partitions)
--   自动处理数据倾斜 (Skew Join Optimization)
```

### Flink SQL

```sql
-- Flink: 流处理引擎, 执行计划与批处理有本质区别
EXPLAIN SELECT c.city, SUM(o.amount) AS total
FROM orders o JOIN customers c ON o.customer_id = c.id
GROUP BY c.city;

-- 流模式输出示例:
-- == Physical Plan ==
-- GroupAggregate(groupBy=[city], select=[city, SUM(amount) AS total])
-- +- Exchange(distribution=[hash[city]])
--    +- Calc(select=[city, amount])
--       +- Join(joinType=[InnerJoin], where=[customer_id = id], select=[customer_id, amount, id, city])
--          :- Exchange(distribution=[hash[customer_id]])
--          :  +- TableSourceScan(table=[[orders]], fields=[customer_id, amount])
--          +- Exchange(distribution=[hash[id]])
--             +- TableSourceScan(table=[[customers]], fields=[id, city])

-- Flink 特有概念:
-- Exchange(distribution=[hash[key]]):  按 key Hash 分布到下游算子
-- Exchange(distribution=[broadcast]):  广播到所有下游并行度
-- Exchange(distribution=[forward]):    相同并行度直接转发
-- Exchange(distribution=[global]):     汇聚到单并行度

-- EXPLAIN ESTIMATED_COST: 显示行数和数据量估算
EXPLAIN ESTIMATED_COST SELECT c.city, SUM(o.amount)
FROM orders o JOIN customers c ON o.customer_id = c.id
GROUP BY c.city;

-- EXPLAIN CHANGELOG_MODE: 显示变更日志模式 (流特有)
EXPLAIN CHANGELOG_MODE SELECT c.city, SUM(o.amount)
FROM orders o JOIN customers c ON o.customer_id = c.id
GROUP BY c.city;
-- 输出: [I, UB, UA]  (Insert, Update Before, Update After)
```

### ClickHouse

```sql
-- 基本 EXPLAIN
EXPLAIN SELECT customer_id, SUM(amount) AS total
FROM orders
WHERE order_date >= '2024-01-01'
GROUP BY customer_id;

-- EXPLAIN PIPELINE: 查看执行管道 (ClickHouse 独有)
EXPLAIN PIPELINE SELECT customer_id, SUM(amount) AS total
FROM orders
WHERE order_date >= '2024-01-01'
GROUP BY customer_id;
-- 输出:
-- (Expression)
-- ExpressionTransform x 8         -- 8 个线程并行
--   (Aggregating)
--   AggregatingTransform x 8
--     (Expression)
--     ExpressionTransform x 8
--       (ReadFromMergeTree)
--       MergeTreeThread x 8

-- EXPLAIN SYNTAX: 查看优化后的等价 SQL (ClickHouse 独有)
EXPLAIN SYNTAX SELECT *
FROM orders
WHERE toYear(order_date) = 2024
  AND customer_id IN (SELECT id FROM customers WHERE country = 'CN');
-- 输出优化后的 SQL, 可能包含谓词下推、分区裁剪等变换

-- EXPLAIN PLAN: 带更多细节
EXPLAIN PLAN header=1, actions=1, indexes=1
SELECT customer_id, SUM(amount) AS total
FROM orders
WHERE order_date >= '2024-01-01'
GROUP BY customer_id;
-- indexes=1: 显示使用了哪些索引 (主键/跳数索引)
-- actions=1: 显示每一步的表达式
-- header=1: 显示列头
```

## 对引擎开发者的建议

### 设计 EXPLAIN 输出时的核心原则

```
1. 分层展示
   - 第一层: 简要概览 (EXPLAIN) -- 算子树 + 估算行数
   - 第二层: 详细统计 (EXPLAIN ANALYZE) -- 实际行数、时间、内存
   - 第三层: 诊断信息 (EXPLAIN VERBOSE / BUFFERS) -- I/O、缓冲区、网络

2. 估算 vs 实际 的对比
   - 始终同时展示 estRows 和 actRows (或 estimated 和 actual)
   - 差异过大时给出警告 (如 PostgreSQL: "Rows Removed by Filter: 99000")
   - 帮助用户快速定位统计信息不准的表

3. 输出格式
   - 必须支持: 人类可读的文本格式 (树状缩进)
   - 强烈建议: JSON 格式 (便于工具解析和 UI 渲染)
   - 可选: XML, YAML, Graphviz (满足不同生态集成需求)

4. 分布式计划的额外要素
   - 标注数据交换类型: Shuffle / Broadcast / Colocate / Gather
   - 显示 Fragment (执行片段) 的分布: 在哪些节点上执行
   - 展示网络传输量估算: 帮助判断数据移动是否合理
   - 标注分区裁剪结果: 扫描了多少分区 / 桶
```

### EXPLAIN ANALYZE 的实现要点

```
EXPLAIN ANALYZE 需要在执行引擎中插入计时器和计数器:

1. 每个算子记录:
   - rows_produced: 实际产出行数
   - time_open:     算子初始化时间
   - time_next:     算子迭代时间 (包含等待下游的时间)
   - time_close:    算子关闭时间
   - memory_peak:   峰值内存使用

2. 注意事项:
   - 计时开销: 高频率调用 clock_gettime() 有性能损耗
     PostgreSQL 提供 TIMING OFF 选项关闭精确计时
   - 并行执行: 并行度 > 1 时, 需要 per-worker 统计
     PostgreSQL: "Workers Planned: 4, Workers Launched: 4"
   - 流式执行: Flink/Materialize 等流引擎无法用 ANALYZE
     因为查询永不结束, 需要通过 metrics 系统持续暴露

3. DML 安全:
   - EXPLAIN ANALYZE INSERT/UPDATE/DELETE 会真正执行并修改数据
   - PostgreSQL 方案: 文档建议 BEGIN + EXPLAIN ANALYZE + ROLLBACK
   - CockroachDB 方案: EXPLAIN ANALYZE 在事务中执行但自动回滚
   - 建议引擎开发者: 提供 dry-run 模式或自动事务包装
```

### Cost 模型设计建议

```
1. 可配置性:
   - 暴露关键代价参数 (如 PostgreSQL 的 random_page_cost)
   - 允许用户根据硬件调整 (SSD vs HDD, 本地 vs 网络存储)
   - MySQL 的 mysql.engine_cost / server_cost 表是很好的参考

2. 可观测性:
   - Cost 值应有明确的物理含义或文档化的计算公式
   - 避免内部 Cost 值无法解读的情况
   - 提供"为什么选了这个计划"的解释 (如 MySQL 的 OPTIMIZER_TRACE)

3. 统计信息:
   - 自动收集 + 手动刷新双通道
   - 直方图 (Histogram) 对非均匀分布至关重要
   - 多列相关性统计 (如 PostgreSQL 的 CREATE STATISTICS)
   - 统计信息过期检测和警告

4. 自适应机制:
   - 运行时反馈: Oracle ABO, Spark AQE
   - Plan Cache 失效策略: 统计信息变化时重新编译
   - 学习型优化器: 根据历史执行结果修正 Cost 模型
```

## 常见陷阱与最佳实践

### 跨引擎注意事项

```
1. Cost 不可跨引擎比较
   - PostgreSQL Cost=100 与 MySQL Cost=100 含义完全不同
   - 只在同一引擎内比较不同计划的 Cost

2. EXPLAIN ANALYZE 的副作用
   - 会真正执行查询 (包括 DML)
   - 慢查询的 EXPLAIN ANALYZE 会等待执行完成
   - 对于超慢查询, 先用 EXPLAIN (不执行) 初步判断

3. 估算行数不准的常见原因
   - 统计信息过期 (解决: ANALYZE TABLE)
   - 多列联合条件的选择性估算偏差 (独立性假设)
   - 函数调用导致优化器无法使用统计信息
   - 参数化查询的 plan cache 使用了不具代表性的参数

4. 分布式引擎额外关注点
   - 是否发生了不必要的 Shuffle (数据已 Colocate 但优化器未识别)
   - Broadcast 的表是否真的够小 (避免 OOM)
   - 分区裁剪是否生效 (是否扫描了过多分区)
```
