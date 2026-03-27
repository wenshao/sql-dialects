-- Snowflake: ALTER TABLE
--
-- 参考资料:
--   [1] Snowflake SQL Reference - ALTER TABLE
--       https://docs.snowflake.com/en/sql-reference/sql/alter-table
--   [2] Snowflake SQL Reference - ALTER COLUMN
--       https://docs.snowflake.com/en/sql-reference/sql/alter-table-column

-- 添加列
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN status INTEGER NOT NULL DEFAULT 1;

-- 添加多列
ALTER TABLE users ADD COLUMN city VARCHAR(64), ADD COLUMN country VARCHAR(64);

-- 删除列
ALTER TABLE users DROP COLUMN phone;

-- 重命名列
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- 修改列类型（仅允许增大精度或兼容变更）
ALTER TABLE users ALTER COLUMN phone SET DATA TYPE VARCHAR(32);
-- 可以增大 VARCHAR 长度，不能缩小
-- NUMBER 精度可以增大

-- 修改 NOT NULL
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

-- 修改默认值
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 交换表内容（原子操作）
ALTER TABLE users SWAP WITH users_staging;

-- 聚集键
ALTER TABLE orders CLUSTER BY (order_date, user_id);
ALTER TABLE orders DROP CLUSTERING KEY;
-- 聚集键不是索引，Snowflake 通过微分区自动优化

-- 修改 Time Travel 保留时间
ALTER TABLE users SET DATA_RETENTION_TIME_IN_DAYS = 30;

-- 标签
ALTER TABLE users SET TAG cost_center = 'engineering';
ALTER TABLE users UNSET TAG cost_center;

-- 注释
ALTER TABLE users SET COMMENT = 'User information table';
ALTER TABLE users UNSET COMMENT;

-- 添加/删除信息性约束（不强制执行）
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE users DROP CONSTRAINT uk_email;

-- 注意：不能将永久表改为瞬态表或反之（需要重建表）
-- CREATE TRANSIENT TABLE staging_new AS SELECT * FROM staging_data;

-- 添加行访问策略
ALTER TABLE users ADD ROW ACCESS POLICY my_policy ON (department);
ALTER TABLE users DROP ROW ACCESS POLICY my_policy;

-- 添加列掩码策略
ALTER TABLE users ALTER COLUMN email SET MASKING POLICY email_mask;
ALTER TABLE users ALTER COLUMN email UNSET MASKING POLICY;

-- 注意：Snowflake 没有索引，数据按微分区自动组织
-- 注意：PRIMARY KEY / UNIQUE / FOREIGN KEY 是信息性的，不强制执行
-- 注意：聚集键影响微分区内的数据排列顺序
