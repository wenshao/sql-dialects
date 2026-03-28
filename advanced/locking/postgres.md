# PostgreSQL: 锁机制

> 参考资料:
> - [PostgreSQL Documentation - Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html)
> - [PostgreSQL Documentation - Advisory Locks](https://www.postgresql.org/docs/current/functions-admin.html#FUNCTIONS-ADVISORY-LOCKS)

## 行级锁: 四种强度（PostgreSQL 独有的细粒度设计）

```sql
SELECT * FROM orders WHERE id = 100 FOR UPDATE;            -- 排他锁
SELECT * FROM orders WHERE id = 100 FOR NO KEY UPDATE;     -- 弱排他锁 (9.3+)
SELECT * FROM orders WHERE id = 100 FOR SHARE;             -- 共享锁
SELECT * FROM orders WHERE id = 100 FOR KEY SHARE;         -- 弱共享锁 (9.3+)

-- 锁兼容矩阵:
--                  FOR KEY SHARE  FOR SHARE  FOR NO KEY UPDATE  FOR UPDATE
-- FOR KEY SHARE        OK           OK            OK              X
-- FOR SHARE            OK           OK            X               X
-- FOR NO KEY UPDATE    OK           X             X               X
-- FOR UPDATE           X            X             X               X
--
-- 设计分析: 为什么有四种行锁
--   FOR UPDATE:         阻塞所有其他锁（DELETE/UPDATE 使用）
--   FOR NO KEY UPDATE:  不阻塞 FOR KEY SHARE（UPDATE 非主键列时使用）
--   FOR SHARE:          允许其他 SHARE 但阻塞写（外键检查使用）
--   FOR KEY SHARE:      最弱锁（外键子表 INSERT 时自动获取，锁父表行）
--
--   9.3 之前只有 FOR UPDATE 和 FOR SHARE，外键操作经常导致不必要的锁冲突。
--   FOR NO KEY UPDATE 和 FOR KEY SHARE 解决了"更新非外键列时阻塞子表 INSERT"的问题。
```

## NOWAIT / SKIP LOCKED

NOWAIT: 无法获取锁时立即报错（不等待）
```sql
SELECT * FROM orders WHERE status = 'pending' FOR UPDATE NOWAIT;
```

SKIP LOCKED (9.5+): 跳过已被锁定的行
这是实现数据库级工作队列的关键特性
```sql
SELECT * FROM tasks WHERE status = 'pending'
ORDER BY created_at LIMIT 5
FOR UPDATE SKIP LOCKED;
```

工作队列模式:
Worker 1: SELECT ... LIMIT 1 FOR UPDATE SKIP LOCKED → 获取 task A
Worker 2: SELECT ... LIMIT 1 FOR UPDATE SKIP LOCKED → 跳过 A，获取 task B
Worker 3: SELECT ... LIMIT 1 FOR UPDATE SKIP LOCKED → 跳过 A,B，获取 task C

对比:
  PostgreSQL: SKIP LOCKED (9.5+)
  Oracle:     SKIP LOCKED (也支持)
  MySQL:      SKIP LOCKED (8.0+)
  SQL Server: READPAST hint (类似语义)

## 表级锁: 八种级别

```sql
LOCK TABLE orders IN ACCESS SHARE MODE;           -- SELECT 自动获取
LOCK TABLE orders IN ROW SHARE MODE;              -- FOR UPDATE/SHARE 自动获取
LOCK TABLE orders IN ROW EXCLUSIVE MODE;          -- DML 自动获取
LOCK TABLE orders IN SHARE UPDATE EXCLUSIVE MODE; -- VACUUM/CREATE INDEX CONCURRENTLY
LOCK TABLE orders IN SHARE MODE;                  -- CREATE INDEX (非 CONCURRENTLY)
LOCK TABLE orders IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE orders IN EXCLUSIVE MODE;
LOCK TABLE orders IN ACCESS EXCLUSIVE MODE;       -- ALTER TABLE/DROP TABLE
LOCK TABLE orders IN EXCLUSIVE MODE NOWAIT;
```

PostgreSQL 的 8 级表锁设计是最精细的（其他数据库通常只有 3-4 级）。
这使得不同操作之间的并发性最大化:
  读操作 (ACCESS SHARE) 只与 ACCESS EXCLUSIVE (DROP TABLE) 冲突
  DML (ROW EXCLUSIVE) 不与其他 DML 冲突（行锁在行级处理）

## 咨询锁 (Advisory Locks): PostgreSQL 独有

会话级咨询锁（手动释放或会话结束释放）
```sql
SELECT pg_advisory_lock(12345);
-- ... 执行需要互斥的操作 ...
SELECT pg_advisory_unlock(12345);
```

事务级咨询锁（事务结束自动释放）
```sql
SELECT pg_advisory_xact_lock(12345);
```

非阻塞版本
```sql
SELECT pg_try_advisory_lock(12345);       -- 获取失败返回 false

-- 共享咨询锁
SELECT pg_advisory_lock_shared(12345);
```

双参数形式（二维锁标识）
```sql
SELECT pg_advisory_lock(100, 200);        -- (class_id, lock_id)

-- 设计分析: 咨询锁的应用场景
--   (a) 分布式互斥: 确保只有一个进程执行特定任务（如定时任务去重）
--   (b) 应用层锁: 锁定业务对象而非数据库行（如"锁定用户的编辑操作"）
--   (c) 批处理协调: 多个 worker 抢占任务
--
-- 内部实现:
--   咨询锁使用 PostgreSQL 的 lock manager（与表锁/行锁共享基础设施）。
--   锁信息存在共享内存中，不涉及 I/O。
--   会话级锁的数量受 max_locks_per_transaction 限制。
--
-- 对比:
--   MySQL:      GET_LOCK('name', timeout) — 也有咨询锁但功能较弱
--   Oracle:     DBMS_LOCK 包
--   SQL Server: sp_getapplock / sp_releaseapplock
```

## 乐观锁 vs 悲观锁

乐观锁: 使用版本号（应用层实现）
```sql
UPDATE orders SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;
```

受影响行数 = 0 → 并发冲突

使用 xmin 系统列（PostgreSQL 特有）
```sql
SELECT id, xmin FROM orders WHERE id = 100;
UPDATE orders SET status = 'shipped' WHERE id = 100 AND xmin = '12345';
```

xmin 是行的创建事务 ID，行被修改后 xmin 改变

悲观锁: SELECT FOR UPDATE
```sql
BEGIN;
    SELECT * FROM accounts WHERE id = 1 FOR UPDATE;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;
```

## 死锁检测

```sql
SHOW deadlock_timeout;                 -- 默认 1s（检测间隔）
SET deadlock_timeout = '2s';
SET lock_timeout = '5s';               -- 单个锁等待超时
SET statement_timeout = '30s';         -- 语句执行超时
```

死锁预防: 按固定顺序获取锁（如按 id 升序）
```sql
BEGIN;
    SELECT * FROM accounts WHERE id IN (1, 2) ORDER BY id FOR UPDATE;
COMMIT;
```

锁监控
```sql
SELECT * FROM pg_locks;
-- 9.6+: pg_blocking_pids 函数
SELECT pid, pg_blocking_pids(pid), query
FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0;
```

终止阻塞进程
```sql
SELECT pg_terminate_backend(12345);
```

## 横向对比: 锁机制

### 行锁粒度

  PostgreSQL: 4 级行锁（最精细）
  MySQL:      2 级（FOR UPDATE / FOR SHARE）
  Oracle:     1 级（FOR UPDATE 只有排他锁）
  SQL Server: 多级（S/U/X/IS/IX/SIX + key-range locks）

### 咨询锁

  PostgreSQL: pg_advisory_lock（功能最完整，会话级+事务级+共享+排他）
  MySQL:      GET_LOCK（只支持会话级排他锁）
  Oracle:     DBMS_LOCK

### SKIP LOCKED

  PostgreSQL: 9.5+（工作队列模式的基础）
  MySQL:      8.0+
  Oracle:     全版本支持

## 对引擎开发者的启示

(1) 四级行锁是外键性能的关键:
    9.3 之前，外键操作频繁导致锁冲突。
    FOR KEY SHARE / FOR NO KEY UPDATE 解决了这个问题。
    教训: 行锁粒度影响实际工作负载的并发度。

(2) SKIP LOCKED 让数据库成为轻量级消息队列:
    不需要 Redis/RabbitMQ，PostgreSQL 本身就能实现任务队列。
    SELECT FOR UPDATE SKIP LOCKED + DELETE RETURNING = 出队操作。

(3) 咨询锁是"数据库作为协调服务"的体现:
    替代 ZooKeeper/etcd 的轻量级分布式锁（限单集群内）。
    实现简单（复用 lock manager），成本低。

## 版本演进

PostgreSQL 8.2:  咨询锁 (Advisory Locks)
PostgreSQL 9.3:  FOR NO KEY UPDATE, FOR KEY SHARE
PostgreSQL 9.5:  SKIP LOCKED
PostgreSQL 9.6:  pg_blocking_pids() 函数
