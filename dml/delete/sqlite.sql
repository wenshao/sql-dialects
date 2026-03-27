-- SQLite: DELETE
--
-- 参考资料:
--   [1] SQLite Documentation - DELETE
--       https://www.sqlite.org/lang_delete.html
--   [2] SQLite Documentation - VACUUM
--       https://www.sqlite.org/lang_vacuum.html

-- ============================================================
-- 1. 基本语法
-- ============================================================

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- 删除所有行（SQLite 没有 TRUNCATE）
DELETE FROM users;
-- 注意: DELETE 不会缩小数据库文件! 已删除的页被标记为空闲（free page）。
-- 后续 INSERT 会复用空闲页，但文件大小不会减小。

-- 3.35.0+: RETURNING
DELETE FROM users WHERE status = 0 RETURNING id, username;

-- LIMIT / ORDER BY（需要编译选项 SQLITE_ENABLE_UPDATE_DELETE_LIMIT）
DELETE FROM users WHERE status = 0 ORDER BY created_at LIMIT 100;

-- ============================================================
-- 2. DELETE 与磁盘空间（对引擎开发者）
-- ============================================================

-- SQLite 的 DELETE 不释放磁盘空间。原因:
--   B-Tree 页被标记为 free page，但文件不会缩小。
--   这是所有基于页的存储引擎的通用行为:
--     MySQL InnoDB: DELETE 后空间不释放（需要 OPTIMIZE TABLE）
--     PostgreSQL:   DELETE 后 dead tuples 需要 VACUUM 回收
--     SQL Server:   DELETE 后空间标记为可用但不归还 OS
--
-- SQLite 的 VACUUM 命令回收空间:
VACUUM;
-- VACUUM 的工作原理:
--   (1) 创建新的临时数据库文件
--   (2) 将所有活跃数据从旧文件复制到新文件
--   (3) 删除旧文件，重命名新文件
--   → 需要 2x 的磁盘空间（旧文件 + 新文件同时存在）
--   → 需要独占锁（阻塞所有读写）

-- 增量 VACUUM（auto_vacuum = INCREMENTAL）:
-- PRAGMA auto_vacuum = INCREMENTAL;
-- PRAGMA incremental_vacuum(100);  -- 回收最多 100 页
-- 优点: 不需要 2x 磁盘空间，可以在线执行
-- 缺点: 可能导致碎片化（页不连续）

-- ============================================================
-- 3. DELETE 触发器
-- ============================================================

-- BEFORE DELETE 和 AFTER DELETE 触发器正常工作
-- CREATE TRIGGER trg_before_delete BEFORE DELETE ON users
-- BEGIN
--     INSERT INTO audit_log (action, user_id) VALUES ('DELETE', OLD.id);
-- END;

-- DELETE 与外键级联:
-- PRAGMA foreign_keys = ON;
-- 如果子表有 ON DELETE CASCADE，DELETE 父表行会自动删除子表行
-- 级联删除也会触发子表的 DELETE 触发器

-- ============================================================
-- 4. 对比与引擎开发者启示
-- ============================================================
-- SQLite DELETE 的特征:
--   (1) 无 TRUNCATE → DELETE 全表是唯一清空方式
--   (2) 空间不释放 → 需要 VACUUM 回收
--   (3) RETURNING → 3.35.0 才添加
--   (4) LIMIT → 需要编译选项
--
-- 对引擎开发者的启示:
--   DELETE 后的空间回收是所有存储引擎的共同挑战。
--   SQLite 的 VACUUM 是最简单粗暴的方案（全量重建），
--   PostgreSQL 的 VACUUM 是更精细的方案（逐页回收），
--   但都有性能开销。
--   嵌入式引擎应优先考虑 incremental vacuum（不需要 2x 空间）。
