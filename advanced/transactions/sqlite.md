# SQLite: 事务

> 参考资料:
> - [SQLite Documentation - BEGIN TRANSACTION](https://www.sqlite.org/lang_transaction.html)
> - [SQLite Documentation - SAVEPOINT](https://www.sqlite.org/lang_savepoint.html)
> - [SQLite Documentation - WAL Mode](https://www.sqlite.org/wal.html)
> - [SQLite Documentation - File Locking](https://www.sqlite.org/lockingv3.html)
> - [SQLite Documentation - Write-Ahead Logging](https://www.sqlite.org/wal.html)

## 基本事务

```sql
BEGIN TRANSACTION;  -- 或简写 BEGIN
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;  -- 或 END TRANSACTION
```

回滚
```sql
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
-- 发现余额不足
ROLLBACK;
```

自动提交: 不写 BEGIN/COMMIT 的话，每条语句自动在独立事务中执行
这意味着 10 次 INSERT 如果不包在 BEGIN/COMMIT 里，就有 10 次 fsync
这是 SQLite "写入慢" 的头号原因
解决: 永远把批量操作包在事务里
不包: 10000 条 INSERT 可能要 30+ 秒
包了: 10000 条 INSERT 通常 < 0.5 秒

## 保存点 (SAVEPOINT)

嵌套事务的替代方案（SQLite 不支持嵌套 BEGIN/COMMIT）
```sql
SAVEPOINT sp1;
INSERT INTO orders (user_id, amount) VALUES (1, 500.00);

SAVEPOINT sp2;
INSERT INTO order_items (order_id, product_id) VALUES (last_insert_rowid(), 42);
-- 某个商品不存在？回滚 sp2，但保留 sp1
ROLLBACK TO SAVEPOINT sp2;
```

sp1 的操作还在，可以继续
```sql
INSERT INTO order_items (order_id, product_id) VALUES (last_insert_rowid(), 43);
RELEASE SAVEPOINT sp1;  -- 相当于 COMMIT（但不会真的 commit 到磁盘，除非是最外层）
```

SAVEPOINT 的特殊行为:
RELEASE 不是 COMMIT: 如果 SAVEPOINT 在 BEGIN/COMMIT 块内，RELEASE 只是合并到外层事务
ROLLBACK TO 不会删除 SAVEPOINT: 回滚后可以继续在同一个 SAVEPOINT 中操作
嵌套 SAVEPOINT: 可以无限嵌套，每层独立回滚

## 事务类型: 为什么 BEGIN IMMEDIATE 很重要

SQLite 有三种事务类型，选错会导致死锁

DEFERRED（默认）— 通常是错误的选择
```sql
BEGIN DEFERRED;
```

不获取任何锁
第一次 SELECT → 获取 SHARED 锁
第一次 INSERT/UPDATE/DELETE → 尝试升级到 RESERVED → EXCLUSIVE 锁
> **问题**: 两个 DEFERRED 事务如果都先读后写，会互相死锁:
  连接 A: BEGIN → SELECT (获取 SHARED) → UPDATE (需要 EXCLUSIVE，但 B 持有 SHARED → 等待)
  连接 B: BEGIN → SELECT (获取 SHARED) → UPDATE (需要 EXCLUSIVE，但 A 持有 SHARED → 等待)
  结果: 死锁! 其中一个收到 SQLITE_BUSY
```sql
COMMIT;
```

IMMEDIATE（推荐用于写事务）
```sql
BEGIN IMMEDIATE;
```

立即获取 RESERVED 锁（阻止其他写入，但允许读取）
如果获取失败，立即返回 SQLITE_BUSY（而不是在事务中途失败）
这是关键优势: 在 BEGIN 时就知道能不能写，而不是操作到一半才发现
```sql
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;
```

EXCLUSIVE（很少需要）
```sql
BEGIN EXCLUSIVE;
```

立即获取 EXCLUSIVE 锁（阻止所有其他连接的读和写）
只在极少数需要保证完全独占的场景使用
WAL 模式下几乎不需要，因为 WAL 允许读写并发
```sql
COMMIT;
```

最佳实践:
  只读事务: BEGIN DEFERRED (或直接 BEGIN)
  读写事务: 始终用 BEGIN IMMEDIATE
  这样做消除了死锁的可能性

## WAL 模式 vs DELETE (Journal) 模式

这是影响 SQLite 性能最大的单一设置

DELETE 模式（默认）:
  写入流程: 1) 复制原始页到 .journal 文件
            2) 修改数据库文件
            3) 删除 .journal 文件 (= commit)
  并发: 写入时整个数据库不可读（EXCLUSIVE 锁）
  优点: 单文件（.journal 在 commit 后删除）
  性能: 每次 commit 需要至少 2 次 fsync

WAL 模式:
```sql
PRAGMA journal_mode = WAL;  -- 设置后永久生效，存储在数据库头部
--   写入流程: 1) 新数据追加到 .wal 文件
--             2) checkpoint 时将 .wal 合并回数据库
--   并发: 读和写可以同时进行! 这是最大优势
--   读取一致性: 每个读连接看到事务开始时的快照（snapshot isolation）
--   性能对比 (典型 benchmark):
--     随机写入:   WAL 模式 ≈ DELETE 模式的 2-5x 快
--     顺序写入:   WAL 模式 ≈ DELETE 模式的 3-10x 快
--     并发读+写:  WAL 模式大幅领先（DELETE 模式下读会被写阻塞）
--     纯读:       两者差不多

-- WAL 模式的限制 — 这些必须知道:
--   1. 不支持网络文件系统: NFS/CIFS/SSHFS 上的文件锁不可靠
--      在 NFS 上用 WAL 模式 = 数据损坏的定时炸弹
--   2. 产生额外文件: database.db-wal 和 database.db-shm 必须和主文件在一起
--      复制/备份时必须复制这三个文件
--   3. WAL 文件会持续增长直到 checkpoint:
PRAGMA wal_autocheckpoint = 1000;  -- 默认: 每 1000 页自动 checkpoint
--      如果写入量很大，WAL 文件可能达到 GB 级别
--   4. 长时间运行的读事务会阻止 WAL checkpoint:
--      如果一个 SELECT 持续 10 分钟，WAL 文件在这 10 分钟内不能被回收
--      解决: 避免长事务，读完尽快 COMMIT

-- WAL2 模式（实验性）: 使用两个 WAL 文件交替写入，
-- 消除 checkpoint 期间的写入停顿。截至 2025 年仍未合入主线
```

## busy_timeout 和重试策略

当另一个连接持有锁时，默认行为是立即返回 SQLITE_BUSY 错误
这在多线程/多进程场景下几乎一定会出问题

```sql
PRAGMA busy_timeout = 5000;  -- 等待最多 5 秒

-- busy_timeout 的工作方式:
--   不是简单的 sleep 5 秒然后重试
--   而是多次重试，每次间隔递增: 1ms, 2ms, 5ms, 10ms, 15ms, 20ms, 25ms, ...
--   总时间不超过指定毫秒数
--   注意: 即使设置了 busy_timeout，仍然可能返回 SQLITE_BUSY（超时后）

-- 自定义重试策略（应用层，伪代码）:
-- 对于需要更精细控制的场景，在应用层实现:
--   max_retries = 5
--   for attempt in range(max_retries):
--       try:
--           conn.execute("BEGIN IMMEDIATE")
--           conn.execute("INSERT ...")
--           conn.execute("COMMIT")
--           break
--       except SQLITE_BUSY:
--           sleep(random(0.01, 0.05) * (2 ** attempt))  # 指数退避 + 抖动
--
-- 为什么指数退避比 busy_timeout 更好:
--   busy_timeout 是全局设置，所有操作相同的等待时间
--   指数退避可以根据操作重要性和场景灵活调整
--   加随机抖动避免惊群效应（多个连接同时重试）
```

## 单写者限制和应对策略

SQLite 的核心限制: 整个数据库同一时刻只有一个写者
这不是 bug，是设计: 单文件 → 文件级锁 → 单写者

写入吞吐量实测参考:
  SSD 上 WAL 模式: 约 50,000-100,000 次简单 INSERT/秒（批量事务）
  SSD 上 WAL 模式: 约 500-2,000 次独立事务/秒（每次 INSERT 独立 commit）
  机械硬盘: 约 50-100 次独立事务/秒（受 fsync 限制）

应对策略:
  1. 批量写入: 把多个写操作合并到一个事务里（最有效的优化）
  2. 写入队列: 应用层用单线程/单协程处理所有写入
     多个线程/协程读，一个线程/协程写，通过队列传递写请求
  3. 读写分离: 用独立的连接读和写
     写连接: 一个，设置 busy_timeout，用 BEGIN IMMEDIATE
     读连接: 可以多个，WAL 模式下和写互不干扰
  4. 分库: 如果不同类型的数据没有 JOIN 关系，放不同的 .db 文件
     每个文件有独立的写锁，等于并行写入

## 文件锁行为: 跨平台差异

SQLite 的锁通过操作系统的文件锁实现

Unix/macOS (fcntl 锁):
  同一进程内: 锁是进程级别的! 同一进程内的多个连接共享锁
    这意味着: 同一进程内开两个连接，它们不会互相 BUSY
    但也意味着: 一个连接 COMMIT 了，另一个连接的事务可能不知道
  不同进程: 正常的进程间文件锁
> **注意**: POSIX advisory locks 有一个 gotcha:
    close() 任何指向同一文件的 fd 会释放该进程所有的锁
    SQLite 内部已经处理了这个问题，但自己混用 fcntl 会踩坑

Windows (LockFileEx):
  锁是基于文件句柄的，不是进程级别
  同一进程内的多个连接有独立的锁
  通常行为更符合预期

Android/iOS:
  和 Unix 相同 (fcntl 锁)
  但移动端更容易遇到文件系统问题:
  iOS: 后台任务随时可能被 kill，确保事务短小
  Android: 某些设备的文件系统实现有 bug，WAL 模式可能有问题

## 隔离级别和一致性保证

SQLite 只有一种隔离级别: SERIALIZABLE
通过锁来实现，不是 MVCC (但 WAL 模式提供了类似快照读的效果)

WAL 模式下的读一致性:
  每个读事务看到的是事务开始时的数据库快照
  即使其他连接在此期间写入了新数据，读事务看到的仍然是旧数据
  这类似于 PostgreSQL 的 REPEATABLE READ

DDL 也是事务性的:
```sql
BEGIN;
CREATE TABLE test1 (id INTEGER PRIMARY KEY, name TEXT);
CREATE TABLE test2 (id INTEGER PRIMARY KEY, value REAL);
INSERT INTO test1 VALUES (1, 'hello');
ROLLBACK;
```

test1 和 test2 都不存在了! 这比 MySQL 强（MySQL 的 DDL 隐式 commit）

## 实用 PRAGMA 配置（事务相关）

```sql
PRAGMA journal_mode = WAL;       -- 启用 WAL 模式（最重要的单一优化）
PRAGMA busy_timeout = 5000;      -- 等待锁释放最多 5 秒
PRAGMA synchronous = NORMAL;     -- WAL 模式下安全且快速（默认 FULL 过于保守）
                                 -- NORMAL: 可能丢失最后一次 checkpoint 后的数据
                                 -- 但不会损坏数据库（trade-off 合理）
PRAGMA foreign_keys = ON;        -- 外键约束默认关闭! 必须每个连接都设置

-- synchronous 选项详解:
--   OFF:    不做 fsync，崩溃可能损坏数据库（只用于开发/测试）
--   NORMAL: WAL 模式下安全，DELETE 模式下崩溃可能丢数据
--   FULL:   每次事务 commit 都 fsync（默认，最安全但最慢）
--   EXTRA:  比 FULL 更多的 fsync（几乎不需要）
```

## 并发实战: Web 应用中使用 SQLite

SQLite 完全可以用于中小型 Web 应用（Litestream, Turso, LiteFS 等生态证明了这点）
关键配置:

连接池配置 (以 Python 为例):
  写连接: 1 个，设置 busy_timeout=5000
  读连接池: 根据 CPU 核数，通常 4-8 个

每个连接的初始化 PRAGMA:
```sql
  PRAGMA journal_mode = WAL;
  PRAGMA busy_timeout = 5000;
  PRAGMA synchronous = NORMAL;
```

  PRAGMA cache_size = -64000;      -- 64MB 页缓存
```sql
  PRAGMA foreign_keys = ON;
```

写操作模板:
  conn.execute("BEGIN IMMEDIATE")
  try:
      conn.execute("INSERT/UPDATE/DELETE ...")
      conn.execute("COMMIT")
  except:
      conn.execute("ROLLBACK")

BEGIN CONCURRENT（实验性分支，截至 2025 年未合入主线）
允许真正的并发写入: 多个写事务同时执行，commit 时检测冲突
如果修改的是不同的页，两个写事务可以同时成功
如果修改了同一页，后提交的事务失败（需要重试）
关注: https://www.sqlite.org/cgi/src/doc/begin-concurrent/doc/begin_concurrent.md
