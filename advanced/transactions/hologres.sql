-- Hologres: 事务
--
-- 参考资料:
--   [1] Hologres SQL Reference
--       https://help.aliyun.com/zh/hologres/user-guide/overview-27
--   [2] Hologres Documentation
--       https://help.aliyun.com/zh/hologres/

-- Hologres 兼容 PostgreSQL 事务语法

-- ============================================================
-- 基本事务
-- ============================================================

BEGIN;  -- 或 START TRANSACTION
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
COMMIT;  -- 或 END

-- 回滚
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
ROLLBACK;

-- ============================================================
-- 自动提交
-- ============================================================

-- 默认每条语句自动提交
-- 使用 BEGIN 开启显式事务

-- ============================================================
-- 隔离级别
-- ============================================================

-- Hologres 使用 READ COMMITTED 隔离级别
-- 这是唯一支持的隔离级别

BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- 其他隔离级别不支持

-- ============================================================
-- 保存点（不支持）
-- ============================================================

-- Hologres 不支持 SAVEPOINT
-- 事务只能整体 COMMIT 或 ROLLBACK

-- ============================================================
-- INSERT ON CONFLICT（原子 UPSERT）
-- ============================================================

-- 主键冲突时更新
INSERT INTO users (id, username, email, updated_at)
VALUES (1, 'alice', 'alice@example.com', now())
ON CONFLICT (id) DO UPDATE SET
    username = EXCLUDED.username,
    email = EXCLUDED.email,
    updated_at = now();

-- 主键冲突时忽略
INSERT INTO users (id, username, email)
VALUES (1, 'alice', 'alice@example.com')
ON CONFLICT (id) DO NOTHING;

-- 批量 UPSERT
INSERT INTO users (id, username, email)
VALUES (1, 'alice', 'alice@example.com'),
       (2, 'bob', 'bob@example.com'),
       (3, 'charlie', 'charlie@example.com')
ON CONFLICT (id) DO UPDATE SET
    username = EXCLUDED.username,
    email = EXCLUDED.email;

-- ============================================================
-- 批量写入
-- ============================================================

-- Hologres 优化了高吞吐量写入
-- 推荐批量写入而不是逐条写入

-- COPY 批量导入
COPY users (id, username, email) FROM STDIN WITH (FORMAT csv);

-- INSERT INTO ... SELECT
INSERT INTO users_backup SELECT * FROM users WHERE status = 1;

-- ============================================================
-- 表级别的写入策略
-- ============================================================

-- 配置主键冲突处理策略
CALL set_table_property('users', 'mutate_type', 'insertorignore');
-- insertorignore: 忽略冲突行
-- insertorreplace: 替换冲突行

-- ============================================================
-- DDL 和事务
-- ============================================================

-- DDL 操作不支持事务回滚
-- CREATE TABLE, ALTER TABLE 等操作立即生效

-- ============================================================
-- 并发控制
-- ============================================================

-- 行级别的并发控制
-- 多个写入操作可以并行（不同行）
-- 同一行的并发写入使用最后写入胜出（Last Write Wins）

-- 高并发写入建议：
-- 1. 使用批量写入而不是逐条写入
-- 2. 使用 Fixed Plan 加速写入
-- 3. 合理设置 distribution_key 分散写入负载

-- ============================================================
-- 查看事务信息
-- ============================================================

-- 兼容 PostgreSQL 系统视图
SELECT * FROM pg_stat_activity WHERE state = 'active';

-- 注意：Hologres 支持基本的事务（BEGIN/COMMIT/ROLLBACK）
-- 注意：唯一支持的隔离级别是 READ COMMITTED
-- 注意：不支持 SAVEPOINT
-- 注意：ON CONFLICT 提供原子的 UPSERT 操作
-- 注意：DDL 不支持事务回滚
-- 注意：高吞吐量写入是 Hologres 的核心能力
