-- TDSQL: 约束
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

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
ALTER TABLE users ADD CONSTRAINT uk_name_email UNIQUE (username, email);

-- NOT NULL
ALTER TABLE users MODIFY COLUMN email VARCHAR(255) NOT NULL;

-- DEFAULT
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;

-- CHECK（MySQL 8.0 兼容）
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);

-- 删除约束
ALTER TABLE users DROP INDEX uk_email;
ALTER TABLE users DROP CHECK chk_age;

-- 查看约束
SELECT * FROM information_schema.TABLE_CONSTRAINTS
WHERE TABLE_NAME = 'users';
SELECT * FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_NAME = 'users';

-- 注意事项：
-- 唯一索引必须包含 shardkey 列
-- 主键必须包含 shardkey 列
-- 不支持外键约束（分布式环境限制）
-- CHECK 约束在 MySQL 8.0 兼容模式下支持
-- 唯一性只能在分片内保证（除非包含 shardkey）
-- 广播表的约束在所有节点上都会执行
