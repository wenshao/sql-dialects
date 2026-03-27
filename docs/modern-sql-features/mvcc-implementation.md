# MVCC 实现对比

多版本并发控制 (MVCC) 让读操作不阻塞写操作、写操作不阻塞读操作。不同引擎选择了截然不同的实现方式，各有深刻的 trade-off。

## MVCC 的核心思想

```
传统锁并发控制:
  读加共享锁, 写加排他锁
  读写互相阻塞 -> 并发度低

MVCC:
  每行数据可以有多个版本
  读操作看到的是某个时间点的"快照"
  写操作创建新版本, 不影响读操作
  读写不互相阻塞 -> 并发度高

核心问题:
  1. 旧版本存在哪里? (undo log / 独立元组 / 版本链)
  2. 读操作如何确定看哪个版本? (Read View / Snapshot)
  3. 旧版本何时清理? (GC / Vacuum / Purge)
```

## Undo-based MVCC: MySQL InnoDB

### 实现原理

```
InnoDB 的 MVCC 基于 Undo Log:

数据页存储:
  每行只保存最新版本
  旧版本通过 undo log 回溯

行的隐藏列:
  DB_TRX_ID: 最后修改该行的事务 ID
  DB_ROLL_PTR: 指向 undo log 中上一个版本的指针

版本链:
  当前行 -> undo log v3 -> undo log v2 -> undo log v1
  (从新到旧, 通过 ROLL_PTR 链接)

UPDATE 操作:
  1. 将当前行复制到 undo log (作为旧版本)
  2. 在数据页上原地修改行
  3. 设置 DB_TRX_ID = 当前事务 ID
  4. 设置 DB_ROLL_PTR 指向 undo log 中的旧版本

DELETE 操作:
  1. 不立即删除, 只是标记 (delete mark)
  2. 后台 purge 线程真正删除
```

### Read View (一致性视图)

```
InnoDB 的 Read View 决定一个事务能看到哪些行版本:

Read View 包含:
  m_low_limit_id: 创建 Read View 时系统中最大的事务 ID + 1
  m_up_limit_id: 创建 Read View 时最小的活跃事务 ID
  m_ids: 创建 Read View 时所有活跃事务的 ID 列表
  m_creator_trx_id: 创建该 Read View 的事务 ID

可见性判断规则:
  对于行的 DB_TRX_ID:
  1. 如果 trx_id < m_up_limit_id:
     该版本在 Read View 创建前已提交 -> 可见
  2. 如果 trx_id >= m_low_limit_id:
     该版本在 Read View 创建后才开始 -> 不可见
  3. 如果 m_up_limit_id <= trx_id < m_low_limit_id:
     检查 trx_id 是否在 m_ids 中:
     - 在 m_ids 中: 该事务在创建 Read View 时还未提交 -> 不可见
     - 不在 m_ids 中: 该事务已提交 -> 可见
  4. 如果 trx_id == m_creator_trx_id:
     自己的修改 -> 可见

如果当前版本不可见, 沿 ROLL_PTR 找到上一个版本, 重复判断。
直到找到可见版本或版本链耗尽 (该行对当前事务"不存在")。
```

### 创建 Read View 的时机

```sql
-- READ COMMITTED: 每条 SELECT 创建新的 Read View
-- 每次读取都能看到最新已提交的数据
START TRANSACTION;
SELECT * FROM t;  -- 创建 Read View 1, 看到此刻已提交的数据
-- 其他事务提交了新数据...
SELECT * FROM t;  -- 创建 Read View 2, 能看到新提交的数据

-- REPEATABLE READ (InnoDB 默认): 第一条 SELECT 创建 Read View
-- 整个事务中的所有读取都看到相同的快照
START TRANSACTION;
SELECT * FROM t;  -- 创建 Read View, 记录此刻的快照
-- 其他事务提交了新数据...
SELECT * FROM t;  -- 复用同一个 Read View, 看不到新提交的数据
```

### InnoDB 的 Purge

```
Purge 线程的工作:
  1. 找到系统中最老的活跃 Read View
  2. 比该 Read View 更老的 undo log 可以安全删除
  3. 清理 delete-marked 的行

问题: 长事务!
  如果有一个事务运行了 24 小时不提交:
  - 所有 24 小时内的 undo log 都不能清理
  - undo tablespace 持续膨胀
  - 查询变慢 (版本链越来越长, 回溯代价越来越大)

  解决:
  - 监控长事务: SELECT * FROM information_schema.innodb_trx ORDER BY trx_started;
  - 设置超时: innodb_rollback_on_timeout, wait_timeout
  - 运维报警: 超过 N 分钟的事务自动告警
```

## Tuple-versioning MVCC: PostgreSQL

### 实现原理

```
PostgreSQL 的 MVCC 基于元组版本化 (Heap Tuple):

核心区别: 每个版本是独立的物理元组, 存储在同一个 table 中!
(不像 InnoDB 只保留最新版本, 旧版本在 undo log 中)

每个元组的系统列:
  xmin: 插入该元组的事务 ID
  xmax: 删除/更新该元组的事务 ID (0 = 未删除)
  ctid: 元组的物理位置 (page, offset)

INSERT: 创建新元组, xmin = 当前事务, xmax = 0
UPDATE: 标记旧元组 (xmax = 当前事务) + 创建新元组 (xmin = 当前事务)
DELETE: 标记元组 (xmax = 当前事务)

示例:
  原始行: (xmin=100, xmax=0, data='v1')

  事务 200 执行 UPDATE:
  旧元组: (xmin=100, xmax=200, data='v1')  <- 标记为被200删除
  新元组: (xmin=200, xmax=0, data='v2')    <- 新版本

  事务 300 执行 DELETE:
  元组: (xmin=200, xmax=300, data='v2')    <- 标记为被300删除
```

### Snapshot 可见性

```
PostgreSQL 的 Snapshot:
  xmin: 快照创建时最小的活跃事务 ID
  xmax: 快照创建时最大的事务 ID + 1
  xip_list: 快照创建时所有活跃事务的列表

可见性判断 (HeapTupleSatisfiesMVCC):
  对于元组 (t_xmin, t_xmax):

  1. t_xmin 是否可见?
     - t_xmin 已提交且 < 快照 xmin -> 可见
     - t_xmin 在 xip_list 中 -> 不可见 (未提交)
     - t_xmin >= 快照 xmax -> 不可见 (快照之后的事务)

  2. t_xmax 是否可见? (如果 t_xmax != 0)
     - t_xmax 已提交且 < 快照 xmin -> 元组已被删除, 不可见
     - t_xmax 在 xip_list 中 -> 删除未提交, 元组可见
     - t_xmax >= 快照 xmax -> 删除在快照之后, 元组可见

  总结: 元组可见 iff (t_xmin 可见 AND t_xmax 不可见)
```

### VACUUM: PostgreSQL 的 GC

```sql
-- PostgreSQL 的核心维护操作: VACUUM

-- 普通 VACUUM: 回收死元组的空间 (标记为可复用)
VACUUM employees;

-- VACUUM FULL: 重写整个表, 回收所有空间 (排他锁!)
VACUUM FULL employees;

-- VACUUM ANALYZE: 回收空间 + 更新统计信息
VACUUM ANALYZE employees;

-- autovacuum: 后台自动运行
-- 当死元组数量超过阈值时触发:
-- threshold = autovacuum_vacuum_threshold + autovacuum_vacuum_scale_factor * row_count
-- 默认: 50 + 0.2 * row_count

-- VACUUM 的工作:
-- 1. 扫描表, 找到所有死元组 (xmax 已提交且对所有活跃事务不可见)
-- 2. 将死元组的空间标记为可复用 (Free Space Map)
-- 3. 更新 Visibility Map (标记全可见的页面, 优化 Index-Only Scan)
-- 4. 冻结旧事务 ID (防止事务 ID 回卷)

-- 事务 ID 回卷问题 (Transaction ID Wraparound):
-- PostgreSQL 的事务 ID 是 32 位整数 (约 42 亿)
-- 超过 20 亿个事务后, 旧事务 ID 会"看起来"比新事务 ID 更大
-- 必须定期 VACUUM FREEZE 将旧事务 ID 标记为"冻结" (frozen)
-- 如果不及时冻结: 数据库拒绝新事务! (安全措施)
```

### PostgreSQL vs InnoDB MVCC 对比

```
                  PostgreSQL              InnoDB
旧版本存储位置    同一个表 (heap)          undo tablespace
UPDATE 操作       新旧元组都在 heap        旧版本在 undo log
空间回收          VACUUM (必须主动运行)    Purge 线程 (自动)
写放大            高 (每次 UPDATE 写全行)  中 (只写变更到 undo)
读性能            直接读 heap              可能需要回溯 undo chain
索引更新          每次 UPDATE 更新所有索引  只在索引列变更时更新
HOT 优化          同页内更新不需更新索引   -
Visibility Map    是 (优化 Index-Only Scan) -
事务 ID 回卷      是 (需要 VACUUM FREEZE)   否 (64位内部, 不回卷)
```

## Timestamp-based MVCC: Google Spanner

### TrueTime 全局时间戳

```
Spanner 的 MVCC 不使用递增的事务 ID, 而是使用真实时间戳。

TrueTime API:
  TT.now() -> [earliest, latest]
  返回一个时间区间, 保证真实时间在这个区间内

  依赖: 每个数据中心的原子钟 + GPS 接收器
  精度: 通常在 ±1-7 毫秒

Commit Wait 协议:
  事务提交时:
  1. 获取 commit timestamp = TT.now().latest
  2. 等待直到 TT.now().earliest > commit timestamp
  3. 确保所有后续事务看到这个提交

效果:
  全球任何节点的读取都能获得一致的快照
  无需中心化的事务管理器
  实现了"外部一致性" (Linearizability)
```

### 读写操作

```sql
-- Spanner 的强一致读 (默认):
SELECT * FROM employees WHERE id = 1;
-- 读取最新已提交的版本
-- 可能需要等待正在提交的事务

-- Stale Read (过期读, 更低延迟):
-- 读取指定时间戳之前的快照
-- 如果时间戳足够旧, 可以在任何副本上读取 (无需协调)
SELECT * FROM employees WHERE id = 1
-- 应用层指定: exactStaleness=15s 或 maxStaleness=15s

-- 多版本保留:
-- Spanner 默认保留 1 小时的历史版本
-- 可配置 version_retention_period
ALTER DATABASE mydb SET OPTIONS (version_retention_period = '7d');
```

## Delta-based MVCC: SQL Server

### 行版本存储

```
SQL Server 的 MVCC (Read Committed Snapshot Isolation):

存储结构:
  数据页: 只存储最新版本 (类似 InnoDB)
  Version Store: tempdb 中的版本存储区域

UPDATE 操作:
  1. 将旧版本复制到 tempdb 的 version store
  2. 在数据页上原地修改
  3. 添加 14 字节的版本指针

与 InnoDB 的区别:
  InnoDB: undo log 在专用的 undo tablespace
  SQL Server: version store 在 tempdb (共享的临时数据库)

后果:
  tempdb 是 SQL Server 的性能瓶颈之一
  高并发更新时 tempdb 可能成为热点
  需要确保 tempdb 有足够的磁盘空间和 I/O 性能
```

### 两种隔离级别

```sql
-- Read Committed Snapshot Isolation (RCSI):
-- 数据库级别开启
ALTER DATABASE mydb SET READ_COMMITTED_SNAPSHOT ON;
-- 效果: READ COMMITTED 隔离级别使用 MVCC (不加锁)
-- 每条 SELECT 看到语句开始时已提交的数据

-- Snapshot Isolation (SI):
ALTER DATABASE mydb SET ALLOW_SNAPSHOT_ISOLATION ON;
-- 事务级别使用:
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
-- 效果: 整个事务看到事务开始时的快照
-- 类似 PostgreSQL 的 REPEATABLE READ

-- RCSI vs SI:
-- RCSI: 语句级别快照, 自动生效 (推荐大多数场景)
-- SI: 事务级别快照, 需要显式指定
-- 两者都使用 version store, 但粒度不同
```

## Append-only MVCC: ClickHouse MergeTree

### 不可变数据模型

```
ClickHouse MergeTree 不修改已有数据:

INSERT:
  写入新的 data part (不可变文件)

UPDATE/DELETE:
  创建 mutation (异步任务)
  后台重写包含受影响行的 data part
  旧 part 在新 part 就绪后标记为非活跃

Merge (后台合并):
  多个小 part 合并为大 part
  合并时应用 mutations、去重等

可以说 ClickHouse 没有传统意义上的 MVCC,
因为它面向的是分析场景 (append-mostly, 很少更新)。
```

### ReplacingMergeTree

```sql
-- ReplacingMergeTree: 通过合并实现"最终一致"的更新
CREATE TABLE events (
    event_id UInt64,
    event_time DateTime,
    event_type String,
    version UInt64
)
ENGINE = ReplacingMergeTree(version)
ORDER BY event_id;

-- 插入 (包括"更新" = 插入新版本):
INSERT INTO events VALUES (1, now(), 'click', 1);
INSERT INTO events VALUES (1, now(), 'view', 2);   -- 更新: version 更大

-- 查询可能看到两个版本 (未合并前):
SELECT * FROM events WHERE event_id = 1;
-- 结果可能是 2 行!

-- 确保只看到最新版本:
SELECT * FROM events FINAL WHERE event_id = 1;
-- FINAL 关键字: 在查询时合并, 只返回最新版本
-- 代价: 查询变慢 (需要做合并)

-- 后台 OPTIMIZE 强制合并:
OPTIMIZE TABLE events FINAL;
-- 合并后旧版本被物理删除
```

## 各方案 Trade-off 总结

| 维度 | Undo-based (InnoDB) | Tuple-versioning (PG) | Timestamp (Spanner) | Delta-based (SQL Server) | Append-only (ClickHouse) |
|------|--------------------|-----------------------|--------------------|-----------------------|--------------------------|
| 写入性能 | 好 | 中等 (写放大) | 中等 (Commit Wait) | 好 | 极好 |
| 点读性能 | 好 | 好 | 好 | 好 | 不适用 |
| 范围读性能 | 好 | 中等 (死元组) | 好 | 好 | 极好 |
| 空间开销 | 中等 (undo) | 高 (多版本在 heap) | 中等 | 中等 (tempdb) | 低 (合并后) |
| GC 压力 | 低 (purge) | 高 (VACUUM!) | 低 | 中等 | 中等 (merge) |
| 全局一致性 | 单机 | 单机 | 全球 | 单机 | 最终一致 |
| 实现复杂度 | 高 | 中等 | 极高 | 高 | 低 |

## 对引擎开发者: MVCC 是 ACID 事务的基础

### 选择建议

```
1. OLTP 引擎: Undo-based (InnoDB 模式)
   优点: 写入性能好, 空间效率高
   缺点: 实现复杂, 长事务导致 undo 膨胀
   适合: 高并发读写的 OLTP 场景

2. 分析型引擎: Append-only
   优点: 实现简单, 写入性能极好
   缺点: 更新和删除不友好
   适合: 以 INSERT 为主的分析场景

3. HTAP 引擎: 混合方案
   行存 (OLTP) 用 Undo-based
   列存 (OLAP) 用 Append-only
   通过 redo log 同步两个存储

4. 分布式引擎: 需要全局事务管理
   方案 A: 中心化的事务管理器 (TiDB 的 PD)
   方案 B: 全局时间戳 (Spanner 的 TrueTime)
   方案 C: HLC (Hybrid Logical Clock, CockroachDB)
```

### 最小 MVCC 实现

```
核心组件:

1. 事务 ID 分配器:
   - 单调递增的 64 位整数
   - 单机: 原子变量 (atomic_increment)
   - 分布式: 中心化 ID 生成器或时间戳

2. 版本存储:
   - 方案 A: Undo Log (内存/磁盘)
   - 方案 B: 多版本元组 (内联在数据中)
   - 方案 C: 追加写入 (Append-only)

3. 快照管理器 (Snapshot Manager):
   - 维护当前活跃事务列表
   - 提供 Snapshot (Read View) 创建接口
   - 决定事务的可见性

4. 垃圾回收器 (GC):
   - 定期扫描, 找到不再被任何活跃快照需要的旧版本
   - 回收旧版本的空间
   - 关键: 不能删除任何活跃事务可能需要的版本!

5. 冲突检测 (写-写冲突):
   - 方案 A: 行级锁 (First Writer Wins)
   - 方案 B: 乐观并发控制 (Commit 时检查冲突)
```

## 参考资料

- Berenson et al.: "A Critique of ANSI SQL Isolation Levels" (1995)
- MySQL: [InnoDB Multi-Versioning](https://dev.mysql.com/doc/refman/8.0/en/innodb-multi-versioning.html)
- PostgreSQL: [Concurrency Control](https://www.postgresql.org/docs/current/mvcc.html)
- Google: [Spanner: Google's Globally-Distributed Database](https://research.google/pubs/pub39966/)
- SQL Server: [Row Versioning-based Isolation](https://learn.microsoft.com/en-us/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide)
- CMU 15-445: [Multi-Version Concurrency Control](https://15445.courses.cs.cmu.edu/)
