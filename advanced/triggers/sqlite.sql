-- SQLite: 触发器
--
-- 参考资料:
--   [1] SQLite Documentation - CREATE TRIGGER
--       https://www.sqlite.org/lang_createtrigger.html
--   [2] SQLite Documentation - DROP TRIGGER
--       https://www.sqlite.org/lang_droptrigger.html

-- BEFORE INSERT
CREATE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    -- 注意：不能用 SET NEW.col = ...，要用 SELECT RAISE 或单独的语句
    SELECT RAISE(ABORT, 'Username cannot be empty')
    WHERE NEW.username IS NULL OR NEW.username = '';
END;

-- AFTER INSERT
CREATE TRIGGER trg_users_after_insert
AFTER INSERT ON users
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'INSERT', NEW.id, datetime('now'));
END;

-- BEFORE UPDATE
CREATE TRIGGER trg_users_updated_at
AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    UPDATE users SET updated_at = datetime('now') WHERE id = NEW.id;
END;

-- AFTER DELETE
CREATE TRIGGER trg_users_after_delete
AFTER DELETE ON users
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'DELETE', OLD.id, datetime('now'));
END;

-- 指定列触发
CREATE TRIGGER trg_email_changed
AFTER UPDATE OF email ON users
FOR EACH ROW
WHEN OLD.email != NEW.email
BEGIN
    INSERT INTO email_change_log (user_id, old_email, new_email)
    VALUES (NEW.id, OLD.email, NEW.email);
END;

-- INSTEAD OF（仅用于视图）
CREATE TRIGGER trg_view_insert
INSTEAD OF INSERT ON user_view
FOR EACH ROW
BEGIN
    INSERT INTO users (username, email) VALUES (NEW.username, NEW.email);
END;

-- WHEN 条件
CREATE TRIGGER trg_check_balance
BEFORE UPDATE ON accounts
FOR EACH ROW
WHEN NEW.balance < 0
BEGIN
    SELECT RAISE(ABORT, 'Balance cannot be negative');
END;

-- RAISE 函数
-- RAISE(IGNORE)        -- 忽略这条操作
-- RAISE(ROLLBACK, msg) -- 回滚整个事务
-- RAISE(ABORT, msg)    -- 中止当前语句（默认）
-- RAISE(FAIL, msg)     -- 停止但保留已有更改

-- 删除触发器
DROP TRIGGER IF EXISTS trg_users_after_insert;

-- 查看触发器
SELECT * FROM sqlite_master WHERE type = 'trigger';

-- 注意：不支持 FOR EACH STATEMENT（只有行级触发器）
-- 注意：不能在触发器中修改 NEW 值（不像其他数据库的 BEFORE 触发器）
