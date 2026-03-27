-- DamengDB (达梦): 触发器
-- Oracle compatible PL/SQL trigger syntax.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

-- BEFORE INSERT
CREATE OR REPLACE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    :NEW.created_at := CURRENT_TIMESTAMP;
    :NEW.updated_at := CURRENT_TIMESTAMP;
    :NEW.username := LOWER(:NEW.username);
END;
/

-- AFTER INSERT
CREATE OR REPLACE TRIGGER trg_users_after_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'INSERT', :NEW.id, CURRENT_TIMESTAMP);
END;
/

-- BEFORE UPDATE
CREATE OR REPLACE TRIGGER trg_users_before_update
BEFORE UPDATE ON users
FOR EACH ROW
BEGIN
    :NEW.updated_at := CURRENT_TIMESTAMP;
END;
/

-- AFTER DELETE
CREATE OR REPLACE TRIGGER trg_users_after_delete
AFTER DELETE ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'DELETE', :OLD.id, CURRENT_TIMESTAMP);
END;
/

-- 复合触发器（多个事件）
CREATE OR REPLACE TRIGGER trg_users_dml
AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        INSERT INTO audit_log (action) VALUES ('INSERT');
    ELSIF UPDATING THEN
        INSERT INTO audit_log (action) VALUES ('UPDATE');
    ELSIF DELETING THEN
        INSERT INTO audit_log (action) VALUES ('DELETE');
    END IF;
END;
/

-- INSTEAD OF（视图触发器）
CREATE OR REPLACE TRIGGER trg_view_insert
INSTEAD OF INSERT ON user_view
FOR EACH ROW
BEGIN
    INSERT INTO users (username, email) VALUES (:NEW.username, :NEW.email);
END;
/

-- 语句级触发器（不加 FOR EACH ROW）
CREATE OR REPLACE TRIGGER trg_users_after_stmt
AFTER INSERT ON users
BEGIN
    DBMS_OUTPUT.PUT_LINE('Insert completed');
END;
/

-- 条件触发
CREATE OR REPLACE TRIGGER trg_log_salary_change
AFTER UPDATE OF salary ON employees
FOR EACH ROW
WHEN (NEW.salary > OLD.salary * 1.5)
BEGIN
    INSERT INTO salary_alerts (emp_id, old_salary, new_salary)
    VALUES (:NEW.id, :OLD.salary, :NEW.salary);
END;
/

-- DDL 触发器
CREATE OR REPLACE TRIGGER trg_ddl_audit
AFTER DDL ON SCHEMA
BEGIN
    INSERT INTO ddl_log (event, event_date)
    VALUES (SYSEVENT, CURRENT_TIMESTAMP);
END;
/

-- 启用/禁用
ALTER TRIGGER trg_users_before_insert DISABLE;
ALTER TRIGGER trg_users_before_insert ENABLE;
ALTER TABLE users DISABLE ALL TRIGGERS;
ALTER TABLE users ENABLE ALL TRIGGERS;

-- 删除
DROP TRIGGER trg_users_before_insert;

-- 注意事项：
-- 触发器语法与 Oracle 兼容
-- 支持 INSTEAD OF 触发器
-- 支持语句级和行级触发器
-- 支持复合触发器（INSERTING/UPDATING/DELETING 条件）
-- 支持 DDL 触发器
-- 支持条件触发（WHEN 子句）
