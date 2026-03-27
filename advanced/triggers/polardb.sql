-- PolarDB: 触发器
-- PolarDB-X (distributed, MySQL compatible).
--
-- 参考资料:
--   [1] PolarDB-X SQL Reference
--       https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/
--   [2] PolarDB MySQL Documentation
--       https://help.aliyun.com/zh/polardb/polardb-for-mysql/

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

-- 多触发器执行顺序
CREATE TRIGGER trg2 AFTER INSERT ON users
FOR EACH ROW FOLLOWS trg_users_after_insert
BEGIN ... END;

-- 删除触发器
DROP TRIGGER IF EXISTS trg_users_before_insert;

-- 查看触发器
SHOW TRIGGERS;

-- 注意事项：
-- 触发器在各分片上独立执行
-- 触发器中的 DML 也遵循分片路由规则
-- 不支持 INSTEAD OF 触发器
-- 不支持语句级触发器（只有行级 FOR EACH ROW）
-- 触发器在分布式事务中作为一部分执行
