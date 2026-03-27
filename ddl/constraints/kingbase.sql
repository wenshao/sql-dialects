-- KingbaseES (人大金仓): 约束
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

-- PRIMARY KEY
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY
);
-- 复合主键
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);

-- UNIQUE
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

-- FOREIGN KEY
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;
-- 动作: CASCADE / SET NULL / SET DEFAULT / RESTRICT / NO ACTION

-- NOT NULL
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- DEFAULT
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- CHECK
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE events ADD CONSTRAINT chk_dates CHECK (end_date > start_date);

-- EXCLUDE（排除约束）
CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE reservations ADD CONSTRAINT no_overlap
    EXCLUDE USING gist (room_id WITH =, period WITH &&);

-- 可延迟约束
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    DEFERRABLE INITIALLY DEFERRED;

-- 删除约束
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE users DROP CONSTRAINT IF EXISTS uk_email;

-- NOT VALID（添加约束时不校验已有数据）
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0) NOT VALID;
ALTER TABLE users VALIDATE CONSTRAINT chk_age;

-- 查看约束
SELECT * FROM information_schema.table_constraints
WHERE table_name = 'users';
SELECT conname, contype, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'users'::regclass;

-- 注意事项：
-- 约束语法与 PostgreSQL 完全兼容
-- 支持排除约束（EXCLUDE）
-- 支持可延迟约束
-- 支持 NOT VALID 延迟验证
