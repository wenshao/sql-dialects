-- PolarDB: 约束
-- PolarDB-X (distributed, MySQL compatible).
--
-- 参考资料:
--   [1] PolarDB-X SQL Reference
--       https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/
--   [2] PolarDB MySQL Documentation
--       https://help.aliyun.com/zh/polardb/polardb-for-mysql/

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

-- FOREIGN KEY（分布式环境下有限制）
-- 仅在同一分片键的表之间支持
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;

-- NOT NULL
ALTER TABLE users MODIFY COLUMN email VARCHAR(255) NOT NULL;

-- DEFAULT
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;

-- CHECK
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);

-- 删除约束
ALTER TABLE users DROP INDEX uk_email;
ALTER TABLE orders DROP FOREIGN KEY fk_orders_user;
ALTER TABLE users DROP CHECK chk_age;

-- 查看约束
SELECT * FROM information_schema.TABLE_CONSTRAINTS
WHERE TABLE_NAME = 'users';

-- 注意事项：
-- 分布式环境下唯一约束必须包含分区键列
-- 全局唯一索引（GSI）可以在非分区键上保证唯一性
-- 外键在跨分片场景下不支持
-- CHECK 约束在 MySQL 8.0 兼容模式下支持
