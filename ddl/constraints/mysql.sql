-- MySQL: 约束
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - Constraints
--       https://dev.mysql.com/doc/refman/8.0/en/constraints.html
--   [2] MySQL 8.0 Reference Manual - CREATE TABLE
--       https://dev.mysql.com/doc/refman/8.0/en/create-table.html
--   [3] MySQL 8.0 Reference Manual - FOREIGN KEY
--       https://dev.mysql.com/doc/refman/8.0/en/create-table-foreign-keys.html

-- PRIMARY KEY
CREATE TABLE users (
    id BIGINT NOT NULL AUTO_INCREMENT,
    PRIMARY KEY (id)
);
-- 复合主键
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);

-- UNIQUE
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
-- 复合唯一
ALTER TABLE users ADD CONSTRAINT uk_name_email UNIQUE (username, email);

-- FOREIGN KEY
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;
-- 动作: CASCADE / SET NULL / RESTRICT / NO ACTION / SET DEFAULT(InnoDB 不支持)

-- NOT NULL
ALTER TABLE users MODIFY COLUMN email VARCHAR(255) NOT NULL;

-- DEFAULT
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;

-- CHECK（8.0.16+ 才真正执行，之前只解析不校验）
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);

-- 删除约束
ALTER TABLE users DROP INDEX uk_email;                 -- 删除唯一约束
ALTER TABLE orders DROP FOREIGN KEY fk_orders_user;    -- 删除外键
ALTER TABLE users DROP CHECK chk_age;                  -- 8.0.16+

-- 查看约束
SELECT * FROM information_schema.TABLE_CONSTRAINTS
WHERE TABLE_NAME = 'users';
SELECT * FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_NAME = 'users';
