-- Derby: ALTER TABLE
--
-- 参考资料:
--   [1] Derby SQL Reference
--       https://db.apache.org/derby/docs/10.16/ref/
--   [2] Derby Developer Guide
--       https://db.apache.org/derby/docs/10.16/devguide/

-- 添加列
ALTER TABLE users ADD COLUMN phone VARCHAR(20);

-- 添加列带约束
ALTER TABLE users ADD COLUMN status INT NOT NULL DEFAULT 1;

-- 删除列
ALTER TABLE users DROP COLUMN phone;

-- 修改列类型（有限制，需兼容类型）
-- 增大 VARCHAR 长度
ALTER TABLE users ALTER COLUMN username SET DATA TYPE VARCHAR(128);

-- 修改默认值
ALTER TABLE users ALTER COLUMN status DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- 添加 NOT NULL
ALTER TABLE users ALTER COLUMN email NOT NULL;

-- 添加约束
ALTER TABLE users ADD CONSTRAINT uq_email UNIQUE (email);
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age > 0);
ALTER TABLE orders ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES users(id);

-- 添加主键
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);

-- 删除约束
ALTER TABLE users DROP CONSTRAINT uq_email;
ALTER TABLE orders DROP CONSTRAINT fk_user;

-- 外键约束操作
ALTER TABLE orders ADD CONSTRAINT fk_user
    FOREIGN KEY (user_id) REFERENCES users(id)
    ON DELETE CASCADE
    ON UPDATE RESTRICT;

-- 修改 IDENTITY 列
ALTER TABLE users ALTER COLUMN id RESTART WITH 1000;
ALTER TABLE users ALTER COLUMN id SET INCREMENT BY 2;

-- 锁定表的超时
ALTER TABLE users LOCKSIZE TABLE;    -- 表级锁
ALTER TABLE users LOCKSIZE ROW;      -- 行级锁

-- 注意：不支持 RENAME TABLE（需要用 RENAME TABLE 语句）
RENAME TABLE users TO members;

-- 注意：不支持 RENAME COLUMN
-- 注意：不支持 DROP NOT NULL
-- 注意：不支持修改列类型（除增大 VARCHAR 长度外）
-- 注意：不支持 IF NOT EXISTS / IF EXISTS 子句
-- 注意：每条 ALTER TABLE 只能执行一个操作
