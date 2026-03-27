-- Oracle: 触发器 (Triggers)
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - CREATE TRIGGER
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-TRIGGER.html
--   [2] Oracle PL/SQL Language Reference - Triggers
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/plsql-triggers.html

-- ============================================================
-- 1. DML 触发器（行级）
-- ============================================================

-- BEFORE INSERT
CREATE OR REPLACE TRIGGER trg_users_before_insert
BEFORE INSERT ON users FOR EACH ROW
BEGIN
    :NEW.created_at := SYSTIMESTAMP;
    :NEW.updated_at := SYSTIMESTAMP;
    :NEW.username := LOWER(:NEW.username);
END;
/

-- AFTER INSERT（审计）
CREATE OR REPLACE TRIGGER trg_users_after_insert
AFTER INSERT ON users FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, action, record_id, created_at)
    VALUES ('users', 'INSERT', :NEW.id, SYSTIMESTAMP);
END;
/

-- BEFORE UPDATE（自动更新时间戳）
CREATE OR REPLACE TRIGGER trg_users_before_update
BEFORE UPDATE ON users FOR EACH ROW
BEGIN
    :NEW.updated_at := SYSTIMESTAMP;
END;
/
-- 注: MySQL 有 ON UPDATE CURRENT_TIMESTAMP 内置语法，Oracle 需要触发器实现

-- ============================================================
-- 2. 复合触发器（11g+，Oracle 独有的杀手级特性）
-- ============================================================

CREATE OR REPLACE TRIGGER trg_users_compound
FOR INSERT OR UPDATE ON users
COMPOUND TRIGGER
    -- 声明区（在所有时间点之间共享）
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
        FORALL i IN 1..v_ids.COUNT
            INSERT INTO audit_log (record_id) VALUES (v_ids(i));
    END AFTER STATEMENT;
END trg_users_compound;
/

-- 设计分析: 复合触发器的价值
--   传统触发器: 每个时间点（BEFORE/AFTER x STATEMENT/ROW）需要独立的触发器
--   复合触发器: 一个触发器处理所有 4 个时间点，共享变量
--   核心价值: 解决"mutating table"问题（行级触发器不能查询触发表）
--
-- 横向对比:
--   Oracle:     COMPOUND TRIGGER（11g+，最优雅的解决方案）
--   PostgreSQL: 分别创建行级和语句级触发器，用临时表传递数据
--   MySQL:      无复合触发器，需要创建多个独立触发器
--   SQL Server: 无复合触发器

-- ============================================================
-- 3. 条件触发与列级触发
-- ============================================================

-- WHEN 子句（条件触发，注意: WHEN 中不用冒号前缀）
CREATE OR REPLACE TRIGGER trg_salary_alert
AFTER UPDATE OF salary ON employees FOR EACH ROW
WHEN (NEW.salary > OLD.salary * 1.5)
BEGIN
    INSERT INTO salary_alerts (emp_id, old_salary, new_salary)
    VALUES (:NEW.id, :OLD.salary, :NEW.salary);
END;
/

-- OF column_name: 只在特定列更新时触发

-- ============================================================
-- 4. INSTEAD OF 触发器（视图更新）
-- ============================================================

CREATE OR REPLACE TRIGGER trg_view_insert
INSTEAD OF INSERT ON user_detail_view FOR EACH ROW
BEGIN
    INSERT INTO users (username, email) VALUES (:NEW.username, :NEW.email);
    INSERT INTO user_profiles (user_id) VALUES (users_seq.CURRVAL);
END;
/

-- INSTEAD OF 触发器使复杂视图（JOIN、GROUP BY 等）可以进行 DML

-- ============================================================
-- 5. DDL 触发器（Oracle 独有，审计 DDL 操作）
-- ============================================================

CREATE OR REPLACE TRIGGER trg_ddl_audit
AFTER DDL ON SCHEMA
BEGIN
    INSERT INTO ddl_log (event, object_name, event_date)
    VALUES (ora_sysevent, ora_dict_obj_name, SYSTIMESTAMP);
END;
/

-- 可用的 DDL 事件属性函数:
-- ora_sysevent:         事件类型（CREATE, ALTER, DROP 等）
-- ora_dict_obj_name:    对象名称
-- ora_dict_obj_type:    对象类型
-- ora_dict_obj_owner:   对象所有者

-- 横向对比:
--   Oracle:     DDL 触发器 + 事件属性函数（最完善）
--   PostgreSQL: EVENT TRIGGER (9.3+)
--   MySQL:      不支持 DDL 触发器
--   SQL Server: DDL 触发器（类似 Oracle）

-- ============================================================
-- 6. '' = NULL 对触发器的影响
-- ============================================================

-- 在触发器中检查字段是否为空:
-- IF :NEW.bio = '' THEN ...  -- 永远为 FALSE（因为 '' = NULL）
-- 正确写法: IF :NEW.bio IS NULL THEN ...

-- ============================================================
-- 7. 触发器管理
-- ============================================================

ALTER TRIGGER trg_users_before_insert DISABLE;
ALTER TRIGGER trg_users_before_insert ENABLE;
ALTER TABLE users DISABLE ALL TRIGGERS;
ALTER TABLE users ENABLE ALL TRIGGERS;
DROP TRIGGER trg_users_before_insert;

-- ============================================================
-- 8. 对引擎开发者的总结
-- ============================================================
-- 1. 复合触发器是 Oracle 独有的优秀设计，解决了 mutating table 和代码组织问题。
-- 2. DDL 触发器是审计系统的重要基础，但需要提供事件属性函数。
-- 3. INSTEAD OF 触发器使视图可更新，是视图层 DML 的关键基础设施。
-- 4. WHEN 子句在行级触发器中提供条件过滤，减少不必要的触发器执行。
-- 5. 触发器执行顺序: BEFORE STATEMENT → BEFORE EACH ROW → AFTER EACH ROW → AFTER STATEMENT
