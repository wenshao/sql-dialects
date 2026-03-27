-- Oracle: 约束
--
-- 参考资料:
--   [1] Oracle SQL Language Reference - Constraints
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/constraint.html
--   [2] Oracle SQL Language Reference - CREATE TABLE
--       https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-TABLE.html

-- PRIMARY KEY
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);

-- UNIQUE
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

-- FOREIGN KEY
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE;
-- 注意：Oracle 不支持 ON UPDATE CASCADE/SET NULL（只有隐式的 NO ACTION 行为）
-- ON DELETE 支持: CASCADE / SET NULL / NO ACTION

-- NOT NULL
ALTER TABLE users MODIFY (email NOT NULL);
ALTER TABLE users MODIFY (email NULL);  -- 去除 NOT NULL

-- DEFAULT
ALTER TABLE users MODIFY (status DEFAULT 1);

-- CHECK
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
-- 可以引用多列
ALTER TABLE events ADD CONSTRAINT chk_dates CHECK (end_date > start_date);

-- 可延迟约束
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    DEFERRABLE INITIALLY DEFERRED;

-- 启用 / 禁用约束（不删除）
ALTER TABLE users DISABLE CONSTRAINT chk_age;
ALTER TABLE users ENABLE CONSTRAINT chk_age;
ALTER TABLE users ENABLE NOVALIDATE CONSTRAINT chk_age;  -- 启用但不校验已有数据

-- 删除约束
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE users DROP CONSTRAINT uk_email CASCADE;  -- 级联删除依赖的约束

-- 查看约束
SELECT constraint_name, constraint_type, search_condition
FROM user_constraints
WHERE table_name = 'USERS';

SELECT * FROM user_cons_columns WHERE table_name = 'USERS';
