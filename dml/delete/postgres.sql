-- PostgreSQL: DELETE
--
-- 参考资料:
--   [1] PostgreSQL Documentation - DELETE
--       https://www.postgresql.org/docs/current/sql-delete.html
--   [2] PostgreSQL Documentation - TRUNCATE
--       https://www.postgresql.org/docs/current/sql-truncate.html
--   [3] PostgreSQL Source - MVCC / Dead Tuple Cleanup
--       https://www.postgresql.org/docs/current/routine-vacuuming.html

-- ============================================================
-- 1. 基本 DELETE 语法
-- ============================================================

DELETE FROM users WHERE username = 'alice';

-- USING 子句（多表关联删除，PostgreSQL 特有语法）
DELETE FROM users USING blacklist
WHERE users.email = blacklist.email;

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- 删除所有行
DELETE FROM users;

-- ============================================================
-- 2. RETURNING 子句: PostgreSQL 最强大的 DML 特性之一
-- ============================================================

-- 返回被删除的行
DELETE FROM users WHERE status = 0 RETURNING id, username;
DELETE FROM users WHERE status = 0 RETURNING *;

-- CTE + DELETE + RETURNING（归档后删除，单语句原子操作）
WITH deleted AS (
    DELETE FROM users WHERE status = 0 RETURNING *
)
INSERT INTO users_archive SELECT * FROM deleted;

-- 设计分析: RETURNING 的内部实现
--   DELETE 在执行 heap_delete() 后，将被删除的 tuple 传给投影层（projection）。
--   RETURNING 表达式在已标记为死亡的 tuple 上求值。
--   这不需要额外的 I/O——数据已经在 buffer pool 中。
--
-- 对比:
--   MySQL:      不支持 RETURNING（需要先 SELECT 再 DELETE，两次 I/O）
--   Oracle:     DELETE ... RETURNING INTO（只能在 PL/SQL 中用变量接收）
--   SQL Server: OUTPUT deleted.* FROM ...（语法不同但功能等价）
--   SQLite:     3.35+ 支持 RETURNING
--
-- 对引擎开发者的启示:
--   RETURNING 将"读+写"合并为一次操作，减少 round-trip 和锁持有时间。
--   这对 OLTP 场景（如消息队列出队）性能提升显著。

-- ============================================================
-- 3. DELETE 的 MVCC 实现: 标记删除而非物理删除
-- ============================================================

-- PostgreSQL 的 DELETE 不会物理删除行。内部过程:
--   (1) 在 tuple header 中设置 xmax = 当前事务 ID
--   (2) tuple 变为"dead tuple"——对后续事务不可见
--   (3) VACUUM 进程稍后物理回收空间
--
-- 对比 MySQL InnoDB:
--   InnoDB 也是标记删除（delete mark），但通过 undo log 实现多版本。
--   PostgreSQL 的旧版本直接存在 heap 中（tuple versioning），
--   InnoDB 的旧版本存在 undo tablespace 中。
--
-- 影响:
--   大量 DELETE 后表不会立即缩小——需要 VACUUM (FULL) 回收空间。
--   Dead tuple 过多会导致 Index Scan 回表时大量无效读（table bloat）。
--   这是 PostgreSQL 的已知问题，autovacuum 是关键的调优目标。

-- ============================================================
-- 4. TRUNCATE: 快速清空表
-- ============================================================

TRUNCATE TABLE users;                  -- 快速清空
TRUNCATE TABLE users RESTART IDENTITY; -- 同时重置 IDENTITY/SERIAL 序列
TRUNCATE TABLE users CASCADE;          -- 级联清空引用表
TRUNCATE TABLE users, orders;          -- 多表一起清空

-- TRUNCATE vs DELETE 的内部差异:
--   TRUNCATE: 直接删除表的数据文件页面（O(1)），获取 ACCESS EXCLUSIVE 锁
--   DELETE:   逐行标记 xmax（O(n)），获取 ROW EXCLUSIVE 锁
--
-- TRUNCATE 的独特性质:
--   (a) 不触发行级触发器（但触发语句级 TRUNCATE 触发器）
--   (b) 在 PostgreSQL 中是事务性的！可以 BEGIN; TRUNCATE; ROLLBACK;
--       MySQL InnoDB 的 TRUNCATE 是隐式 DDL，不可回滚
--   (c) 不产生大量 WAL 日志（DELETE 每行都写 WAL）
--   (d) 不增加 dead tuple（无需 VACUUM）

-- ============================================================
-- 5. 大表删除策略
-- ============================================================

-- 问题: 一次 DELETE 百万行会导致长事务、大量 WAL、VACUUM 压力

-- 策略 1: 分批删除
DO $$
DECLARE batch_size INT := 10000;
BEGIN
    LOOP
        DELETE FROM logs WHERE id IN (
            SELECT id FROM logs WHERE created_at < '2023-01-01'
            LIMIT batch_size FOR UPDATE SKIP LOCKED
        );
        EXIT WHEN NOT FOUND;
        COMMIT;  -- 在 PROCEDURE 中可以中间 COMMIT
    END LOOP;
END $$;

-- 策略 2: 分区表 + DROP PARTITION（最快，O(1)）
ALTER TABLE logs DETACH PARTITION logs_2022;
DROP TABLE logs_2022;

-- 策略 3: CTAS 替换（保留有效数据，删除旧表）
CREATE TABLE users_new AS SELECT * FROM users WHERE status <> 0;
-- 然后重建索引、约束，最后 RENAME

-- ============================================================
-- 6. 横向对比: DELETE 行为差异
-- ============================================================

-- 1. 多表删除语法:
--   PostgreSQL: DELETE FROM t1 USING t2 WHERE ...
--   MySQL:      DELETE t1 FROM t1 JOIN t2 ON ... 或 DELETE t1, t2 FROM t1 JOIN t2
--   Oracle:     DELETE FROM t1 WHERE EXISTS (SELECT ... FROM t2)
--   SQL Server: DELETE t1 FROM t1 JOIN t2 ON ...（类似 MySQL）
--
-- 2. RETURNING:
--   PostgreSQL: DELETE ... RETURNING *（直接返回被删除的行）
--   SQL Server: DELETE ... OUTPUT deleted.*（功能等价，语法不同）
--   MySQL/Oracle: 不支持
--
-- 3. TRUNCATE 事务性:
--   PostgreSQL: TRUNCATE 是事务性的（可回滚）
--   MySQL:      TRUNCATE 隐式提交（不可回滚）
--   Oracle:     TRUNCATE 隐式提交（不可回滚）
--   SQL Server: TRUNCATE 是事务性的（同 PostgreSQL）

-- ============================================================
-- 7. 对引擎开发者的启示
-- ============================================================

-- (1) RETURNING 是 OLTP 场景的关键优化:
--     消息队列出队（DELETE + RETURNING）、令牌消费等场景
--     比"SELECT + DELETE"减少一次 round-trip 和锁竞争。
--
-- (2) MVCC DELETE 的空间回收是所有 heap 存储引擎的痛点:
--     PostgreSQL 的 autovacuum 是必须的后台进程。
--     MySQL InnoDB 通过 undo purge 线程回收 undo log。
--     设计新引擎时，必须规划"dead tuple 回收"策略。
--
-- (3) 分区表 DROP 是大数据删除的最佳方案:
--     O(1) 操作，无 VACUUM 压力，无长事务。
--     时序数据应该默认按时间分区。

-- ============================================================
-- 8. 版本演进
-- ============================================================
-- PostgreSQL 8.1:  DELETE ... USING 语法
-- PostgreSQL 8.4:  CTE (WITH ... DELETE ... RETURNING)
-- PostgreSQL 9.1:  可写 CTE（WITH deleted AS (DELETE ... RETURNING *) INSERT ...)
-- PostgreSQL 14:   DETACH PARTITION CONCURRENTLY
