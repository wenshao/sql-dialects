-- DuckDB: 锁机制 (Locking)
--
-- 参考资料:
--   [1] DuckDB Documentation - Concurrency
--       https://duckdb.org/docs/connect/concurrency.html
--   [2] DuckDB Documentation - Transactions
--       https://duckdb.org/docs/sql/statements/transactions.html
--   [3] DuckDB Documentation - MVCC
--       https://duckdb.org/docs/internals/storage.html

-- ============================================================
-- DuckDB 并发模型概述
-- ============================================================
-- DuckDB 使用 MVCC (HyPer-style) 实现并发控制:
-- 1. 支持多个并发读取者
-- 2. 同一时间只能有一个写入者
-- 3. 读不阻塞写，写不阻塞读
-- 4. 不支持行级锁或 SELECT FOR UPDATE
-- 5. 适合嵌入式分析场景

-- ============================================================
-- 事务
-- ============================================================

-- 显式事务
BEGIN TRANSACTION;
    INSERT INTO orders VALUES (1, 'new');
    UPDATE orders SET status = 'confirmed' WHERE id = 1;
COMMIT;

-- 回滚
BEGIN TRANSACTION;
    DELETE FROM orders WHERE id = 1;
ROLLBACK;

-- 自动提交（默认）
INSERT INTO orders VALUES (2, 'new');

-- ============================================================
-- 写入串行化
-- ============================================================

-- DuckDB 使用单写入者模型：
-- 同一时间只能有一个活跃的写事务
-- 第二个写事务会等待第一个完成
-- 如果等待超时，第二个事务会失败

-- 读事务可以与写事务并发执行
-- 读事务看到的是事务开始时的快照

-- ============================================================
-- 乐观锁
-- ============================================================

-- 由于单写入者模型，写-写冲突通过串行化解决
-- 应用层仍然可以使用乐观锁模式

CREATE TABLE orders (
    id      INTEGER PRIMARY KEY,
    status  VARCHAR,
    version INTEGER NOT NULL DEFAULT 1
);

UPDATE orders
SET status = 'shipped', version = version + 1
WHERE id = 100 AND version = 5;

-- ============================================================
-- 并发访问模式
-- ============================================================

-- 单进程内多线程：DuckDB 内部管理并发
-- 多进程访问同一数据库文件：需要注意
-- 只有一个进程可以写入，多个进程可以读取

-- 只读模式打开（允许多进程并发读）
-- duckdb.connect('my.db', read_only=True)  # Python API

-- ============================================================
-- 监控
-- ============================================================

-- 查看运行中的查询
-- DuckDB 没有类似 pg_stat_activity 的系统视图
-- 可以使用 pragma 查看数据库信息
PRAGMA database_size;
PRAGMA version;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 不支持 SELECT FOR UPDATE / FOR SHARE
-- 2. 不支持 LOCK TABLE
-- 3. 不支持 advisory locks
-- 4. 单写入者模型：同一时间只能有一个写事务
-- 5. MVCC 提供快照隔离
-- 6. 适合分析型工作负载，不适合高并发 OLTP
-- 7. 内存数据库模式下没有文件级别的锁问题
