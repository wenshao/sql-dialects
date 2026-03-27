-- TDSQL: 触发器
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

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

-- 删除触发器
DROP TRIGGER IF EXISTS trg_users_before_insert;

-- 查看触发器
SHOW TRIGGERS;

-- 注意事项：
-- 触发器在各分片上独立执行
-- 触发器中的 INSERT/UPDATE 也遵循分片路由
-- 不支持 INSTEAD OF 触发器
-- 不支持语句级触发器
-- 触发器内不能使用事务控制语句（COMMIT/ROLLBACK）
-- 广播表的触发器在所有节点上执行
