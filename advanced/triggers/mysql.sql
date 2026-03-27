-- MySQL: 触发器
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - CREATE TRIGGER
--       https://dev.mysql.com/doc/refman/8.0/en/create-trigger.html
--   [2] MySQL 8.0 Reference Manual - Trigger Syntax
--       https://dev.mysql.com/doc/refman/8.0/en/trigger-syntax.html

-- BEFORE INSERT
DELIMITER //
CREATE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    SET NEW.created_at = NOW();
    SET NEW.updated_at = NOW();
    SET NEW.username = LOWER(NEW.username);
END //
DELIMITER ;

-- AFTER INSERT
DELIMITER //
CREATE TRIGGER trg_users_after_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'INSERT', NEW.id, NOW());
END //
DELIMITER ;

-- BEFORE UPDATE
DELIMITER //
CREATE TRIGGER trg_users_before_update
BEFORE UPDATE ON users
FOR EACH ROW
BEGIN
    SET NEW.updated_at = NOW();
END //
DELIMITER ;

-- AFTER DELETE
DELIMITER //
CREATE TRIGGER trg_users_after_delete
AFTER DELETE ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, old_data, created_at)
    VALUES ('users', 'DELETE', OLD.id, JSON_OBJECT('username', OLD.username), NOW());
END //
DELIMITER ;

-- 5.7.2+: 同一表同一事件可以有多个触发器
-- 控制执行顺序
DELIMITER //
CREATE TRIGGER trg2 AFTER INSERT ON users
FOR EACH ROW FOLLOWS trg_users_after_insert  -- 在指定触发器之后
BEGIN
    -- 触发器逻辑
END //
DELIMITER ;

DELIMITER //
CREATE TRIGGER trg3 AFTER INSERT ON users
FOR EACH ROW PRECEDES trg_users_after_insert  -- 在指定触发器之前
BEGIN
    -- 触发器逻辑
END //
DELIMITER ;

-- 删除触发器
DROP TRIGGER IF EXISTS trg_users_before_insert;

-- 查看触发器
SHOW TRIGGERS;
SELECT * FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = DATABASE();

-- 注意：不支持 INSTEAD OF 触发器
-- 注意：不支持语句级触发器（只有行级 FOR EACH ROW）
-- 注意：触发器内不能调用存储过程使用事务语句（COMMIT/ROLLBACK）
