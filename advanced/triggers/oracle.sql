-- Oracle: 触发器
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - CREATE TRIGGER
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-TRIGGER.html
--   [2] Oracle PL/SQL Language Reference - Triggers
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/plsql-triggers.html

-- BEFORE INSERT（行级）
CREATE OR REPLACE TRIGGER trg_users_before_insert
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    :NEW.created_at := SYSTIMESTAMP;
    :NEW.updated_at := SYSTIMESTAMP;
    :NEW.username := LOWER(:NEW.username);
END;
/

-- AFTER INSERT
CREATE OR REPLACE TRIGGER trg_users_after_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'INSERT', :NEW.id, SYSTIMESTAMP);
END;
/

-- BEFORE UPDATE
CREATE OR REPLACE TRIGGER trg_users_before_update
BEFORE UPDATE ON users
FOR EACH ROW
BEGIN
    :NEW.updated_at := SYSTIMESTAMP;
END;
/

-- 复合触发器（11g+，一个触发器处理多个时间点）
CREATE OR REPLACE TRIGGER trg_users_compound
FOR INSERT OR UPDATE ON users
COMPOUND TRIGGER
    -- 声明区
    TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    v_ids t_ids;
    v_idx PLS_INTEGER := 0;

    BEFORE EACH ROW IS
    BEGIN
        :NEW.updated_at := SYSTIMESTAMP;
    END BEFORE EACH ROW;

    AFTER EACH ROW IS
    BEGIN
        v_idx := v_idx + 1;
        v_ids(v_idx) := :NEW.id;
    END AFTER EACH ROW;

    AFTER STATEMENT IS
    BEGIN
        -- 批量处理
        FORALL i IN 1..v_ids.COUNT
            INSERT INTO audit_log (record_id) VALUES (v_ids(i));
    END AFTER STATEMENT;
END trg_users_compound;
/

-- INSTEAD OF（用于视图）
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

-- 条件触发（WHEN 子句）
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
    INSERT INTO ddl_log (event, object_name, sql_text, event_date)
    VALUES (ora_sysevent, ora_dict_obj_name, NULL, SYSTIMESTAMP);
END;
/

-- 启用/禁用
ALTER TRIGGER trg_users_before_insert DISABLE;
ALTER TRIGGER trg_users_before_insert ENABLE;
ALTER TABLE users DISABLE ALL TRIGGERS;
ALTER TABLE users ENABLE ALL TRIGGERS;

-- 删除
DROP TRIGGER trg_users_before_insert;
