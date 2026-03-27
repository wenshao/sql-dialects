-- DamengDB (达梦): 约束
-- Oracle compatible syntax.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

-- PRIMARY KEY
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);

-- UNIQUE
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

-- FOREIGN KEY
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE;
-- ON DELETE 支持: CASCADE / SET NULL / NO ACTION
-- ON UPDATE 仅支持 NO ACTION

-- NOT NULL
ALTER TABLE users MODIFY (email NOT NULL);
ALTER TABLE users MODIFY (email NULL);

-- DEFAULT
ALTER TABLE users MODIFY (status DEFAULT 1);

-- CHECK
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE events ADD CONSTRAINT chk_dates CHECK (end_date > start_date);

-- 可延迟约束
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    DEFERRABLE INITIALLY DEFERRED;

-- 启用 / 禁用约束（不删除）
ALTER TABLE users DISABLE CONSTRAINT chk_age;
ALTER TABLE users ENABLE CONSTRAINT chk_age;
ALTER TABLE users ENABLE NOVALIDATE CONSTRAINT chk_age;

-- 删除约束
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE users DROP CONSTRAINT uk_email CASCADE;

-- 查看约束
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE, SEARCH_CONDITION
FROM USER_CONSTRAINTS
WHERE TABLE_NAME = 'USERS';
SELECT * FROM USER_CONS_COLUMNS WHERE TABLE_NAME = 'USERS';

-- 注意事项：
-- 语法与 Oracle 高度兼容
-- 支持约束的启用/禁用而不删除
-- 支持可延迟约束
-- 支持 NOVALIDATE 模式启用约束
