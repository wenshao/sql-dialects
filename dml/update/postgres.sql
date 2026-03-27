-- PostgreSQL: UPDATE
--
-- 参考资料:
--   [1] PostgreSQL Documentation - UPDATE
--       https://www.postgresql.org/docs/current/sql-update.html
--   [2] PostgreSQL Source - ExecUpdate / heapam.c
--       https://github.com/postgres/postgres/blob/master/src/backend/access/heap/heapam.c

-- ============================================================
-- 1. 基本 UPDATE 语法
-- ============================================================

UPDATE users SET age = 26 WHERE username = 'alice';
UPDATE users SET email = 'new@example.com', age = 26 WHERE username = 'alice';

-- 元组赋值（PostgreSQL 特有）
UPDATE users SET (email, age) = ('new@example.com', 26) WHERE username = 'alice';

-- RETURNING（返回更新后的行）
UPDATE users SET age = 26 WHERE username = 'alice' RETURNING id, username, age;

-- ============================================================
-- 2. FROM 子句: PostgreSQL 特有的多表 UPDATE 语法
-- ============================================================

UPDATE users SET status = 1
FROM orders
WHERE users.id = orders.user_id AND orders.amount > 1000;

-- CTE + UPDATE
WITH vip AS (
    SELECT user_id FROM orders GROUP BY user_id HAVING SUM(amount) > 10000
)
UPDATE users SET status = 2 FROM vip WHERE users.id = vip.user_id;

-- 从 VALUES 列表批量更新（极其实用）
UPDATE users u SET email = t.new_email
FROM (VALUES ('alice', 'alice_new@example.com'),
             ('bob', 'bob_new@example.com'))
    AS t(username, new_email)
WHERE u.username = t.username;

-- 设计对比:
--   PostgreSQL: UPDATE t1 SET ... FROM t2 WHERE t1.id = t2.id
--   MySQL:      UPDATE t1 JOIN t2 ON t1.id = t2.id SET t1.col = t2.col
--   Oracle:     UPDATE t1 SET col = (SELECT col FROM t2 WHERE t2.id = t1.id)
--               或 MERGE INTO（更常用）
--   SQL Server: UPDATE t1 SET ... FROM t1 JOIN t2 ON ...（类似 MySQL）
--   SQL 标准:   不包含 FROM 子句，UPDATE 只能更新单表

-- ============================================================
-- 3. UPDATE 的 MVCC 实现: 每次 UPDATE 都是 DELETE + INSERT
-- ============================================================

-- PostgreSQL 的 UPDATE 内部过程:
--   (1) 找到目标 tuple，在旧 tuple 的 header 中设置 xmax = 当前事务 ID
--   (2) 在 heap 中插入一条新 tuple（包含更新后的值），设置 xmin = 当前事务 ID
--   (3) 旧 tuple 的 t_ctid 指向新 tuple（形成版本链）
--   (4) 更新所有索引（每个索引删除旧条目，插入新条目）
--
-- 关键影响: HOT Update (Heap-Only Tuple)
--   如果更新没有修改任何索引列，且新 tuple 在同一个 page 中，
--   PostgreSQL 执行 HOT update:
--     - 不更新任何索引（省去索引维护开销）
--     - 旧 tuple 通过 t_ctid 链指向新 tuple
--     - 索引仍指向旧 tuple，heap scan 时沿链找到新 tuple
--   HOT 对高频 UPDATE 场景性能提升巨大（减少 50%+ 的 I/O）
--
-- 设计对比 (MVCC 实现方式):
--   PostgreSQL: Tuple Versioning（旧版本在 heap 中，DELETE+INSERT）
--   MySQL InnoDB: Undo Log（旧版本在 undo tablespace 中，原地修改）
--   Oracle:     Undo Segment（同 MySQL InnoDB 原理）
--
-- PostgreSQL 方式的 trade-off:
--   优点: 实现简单，不需要 undo tablespace 管理，ROLLBACK 瞬间完成
--   缺点: 表膨胀（dead tuples），UPDATE 密集的表需要频繁 VACUUM
--         每次 UPDATE 都要重写完整行（即使只改一个字段）

-- ============================================================
-- 4. CASE 表达式 + UPDATE: 条件更新
-- ============================================================

UPDATE users SET status = CASE
    WHEN age < 18 THEN 0
    WHEN age >= 65 THEN 2
    ELSE 1
END;

-- 条件更新（只更新有变化的行，减少无效 UPDATE）
UPDATE users SET status = 1
WHERE status <> 1 AND last_login > NOW() - INTERVAL '30 days';
-- 加 WHERE status <> 1 避免"更新到相同值"——
-- PostgreSQL 即使值不变也会产生新 tuple（浪费空间+WAL）

-- ============================================================
-- 5. UPDATE 性能优化策略
-- ============================================================

-- (1) 避免更新索引列（触发 HOT 优化）
-- fillfactor 设置: 预留空间给 HOT update
ALTER TABLE users SET (fillfactor = 80);
-- 每页保留 20% 空间，提高 HOT update 命中率

-- (2) 批量 UPDATE 分段执行
-- 一次更新百万行会持有长锁、生成大量 WAL
UPDATE users SET status = 0 WHERE id BETWEEN 1 AND 10000;
UPDATE users SET status = 0 WHERE id BETWEEN 10001 AND 20000;

-- (3) CONCURRENTLY 替代方案: 使用 CTE 分批
WITH batch AS (
    SELECT id FROM users
    WHERE status = 1 AND needs_update = true
    LIMIT 1000
    FOR UPDATE SKIP LOCKED
)
UPDATE users SET processed = true
FROM batch WHERE users.id = batch.id;

-- ============================================================
-- 6. 横向对比: UPDATE 行为差异
-- ============================================================

-- 1. 多表 UPDATE 语法:
--   PostgreSQL: UPDATE ... FROM ...（独特语法）
--   MySQL:      UPDATE t1 JOIN t2 SET ...（JOIN 语法）
--   SQL Server: UPDATE t1 SET ... FROM t1 JOIN t2（同 MySQL 思路）
--   Oracle:     UPDATE (SELECT ...) SET ...  或 MERGE
--
-- 2. RETURNING:
--   PostgreSQL: UPDATE ... RETURNING *
--   SQL Server: UPDATE ... OUTPUT inserted.*
--   MySQL/Oracle: 不支持
--
-- 3. UPDATE 对 MVCC 的影响:
--   PostgreSQL: 每次 UPDATE = DELETE + INSERT（完整行复制）
--   MySQL InnoDB: 原地修改 + undo log（只记录变化的列）
--   Oracle:     原地修改 + undo segment

-- ============================================================
-- 7. 对引擎开发者的启示
-- ============================================================

-- (1) HOT (Heap-Only Tuple) 是 PostgreSQL UPDATE 性能的关键:
--     如果没有 HOT，每次 UPDATE 都要维护所有索引。
--     HOT 的条件: 不修改索引列 + 新 tuple 在同一 page。
--     fillfactor 是调优 HOT 命中率的关键参数。
--
-- (2) "UPDATE = DELETE + INSERT" 的代价:
--     PostgreSQL 的 MVCC 实现简单优雅，但 UPDATE 密集场景的
--     表膨胀问题是最大痛点。这也是为什么 VACUUM 如此重要。
--     设计新引擎时需要权衡: undo log 复杂但空间效率高，
--     tuple versioning 简单但需要后台清理。
--
-- (3) FROM 子句的便利性:
--     多表 UPDATE 是极常见的需求，PostgreSQL 的 FROM 语法简洁直观。
--     对比 Oracle 需要子查询或 MERGE，明显不够直观。

-- ============================================================
-- 8. 版本演进
-- ============================================================
-- PostgreSQL 8.2:  UPDATE ... RETURNING
-- PostgreSQL 8.3:  HOT Update（Heap-Only Tuple 优化）
-- PostgreSQL 9.0:  UPDATE ... FROM ... RETURNING
-- PostgreSQL 9.1:  可写 CTE（WITH ... UPDATE ... RETURNING）
-- PostgreSQL 12:   改进 HOT 链跟踪算法
-- PostgreSQL 16:   MERGE 支持（SQL:2003 标准，作为 UPDATE/INSERT 的替代）
