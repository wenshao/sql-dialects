# ClickHouse: 锁机制（Locking）

> 参考资料:
> - [1] ClickHouse - MergeTree Consistency
>   https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/mergetree
> - [2] ClickHouse - system.mutations / system.processes
>   https://clickhouse.com/docs/en/operations/system-tables/mutations


## 1. 为什么 ClickHouse 几乎没有锁


 ClickHouse 的核心设计使其几乎不需要传统意义上的锁:

 (a) 不可变 data part:
     INSERT 创建新的 data part → 不修改已有 part → 读写不冲突
     → 没有脏读、不可重复读、幻读问题（因为数据不会被修改）

 (b) 无 UPDATE/DELETE 的即时修改:
     UPDATE/DELETE 通过 mutation 异步处理 → 创建新 part 替换旧 part
     → 查询看到的是某个时间点的 part 集合快照

 (c) 列式存储:
     不同列存储在不同文件中，不同查询可以并行读取不同列
     → 列级并行而非行级竞争

 对比:
   MySQL InnoDB: 行级锁 + 间隙锁 + 意向锁 → 复杂的锁管理器
   PostgreSQL:   行级锁 + MVCC → 每行有 xmin/xmax 版本号
   SQLite:       文件级锁（5 级状态）
   ClickHouse:   几乎无锁（不可变 part + 快照读）

## 2. ClickHouse 中存在的"锁"


### 2.1 表级元数据锁

DDL 操作（ALTER TABLE, DROP TABLE）会获取表级元数据锁。
这不影响查询（查询使用 part 快照），但会阻塞其他 DDL:

```sql
ALTER TABLE users ADD COLUMN phone String;
```

 → 获取元数据锁 → 修改 schema → 释放锁
 → 在此期间其他 ALTER TABLE 等待

### 2.2 Part 级锁（merge 操作）

 后台 merge 时，参与 merge 的 part 被标记为"正在 merge"。
 新 INSERT 不受影响（创建新 part），但 merge 的 part 不会被再次 merge。
 这不是锁，更像是"互斥标记"。

### 2.3 Mutation 锁

mutation（ALTER TABLE UPDATE/DELETE）按顺序执行:
后提交的 mutation 等待前一个完成后才开始。

```sql
SELECT mutation_id, command, is_done, parts_to_do
FROM system.mutations WHERE table = 'users';

```

## 3. 并发控制机制


### 3.1 Part 快照隔离

 每个 SELECT 在执行时获取当前 part 列表的快照。
 查询期间即使有新 INSERT（创建新 part）或 merge（替换 part），
 当前查询仍然读旧的 part 集合。
 → 这是天然的快照隔离，不需要 MVCC。

### 3.2 INSERT 并发

 多个连接可以同时 INSERT（各自创建独立的 data part）。
 没有写写冲突，因为每个 INSERT 创建的 part 完全独立。
 唯一的约束: max_parts_in_total 限制 part 总数

### 3.3 查看当前运行的查询

```sql
SELECT query_id, user, elapsed, read_rows, memory_usage, query
FROM system.processes
WHERE is_cancelled = 0;

```

终止查询

```sql
KILL QUERY WHERE query_id = 'xxx';

```

## 4. 分布式环境的一致性


ZooKeeper 用于分布式协调:
(a) 副本间数据同步（ReplicatedMergeTree）
(b) 分布式 DDL（ON CLUSTER 语句）
(c) Leader 选举（哪个副本执行 merge）

insert_quorum: 写入确认机制

```sql
SET insert_quorum = 2;
INSERT INTO orders VALUES (...);
```

→ 等待 2 个副本确认才返回成功

select_sequential_consistency: 读取一致性

```sql
SET select_sequential_consistency = 1;
SELECT * FROM orders;
```

 → 确保读取到最新确认的数据（有延迟开销）

## 5. 对比与引擎开发者启示

ClickHouse 的"无锁"设计:
(1) 不可变 part → 读写不冲突
(2) 快照隔离天然实现 → 不需要 MVCC
(3) INSERT 完全并发 → 无写写冲突
(4) mutation 串行执行 → 简化实现
(5) ZooKeeper 协调 → 分布式一致性

对引擎开发者的启示:
不可变数据结构（immutable data parts）是消除锁的最佳方案。
LSM-Tree（RocksDB）、列式存储（ClickHouse）、时序数据库（InfluxDB）
都采用类似的"追加写入 + 后台合并"模式来避免锁竞争。
如果引擎设计为 INSERT-heavy，应该优先考虑不可变存储模型。

