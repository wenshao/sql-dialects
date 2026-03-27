-- BigQuery: ALTER TABLE
--
-- 参考资料:
--   [1] BigQuery SQL Reference - ALTER TABLE
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-definition-language#alter_table_set_options
--   [2] BigQuery SQL Reference - Data Types
--       https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types

-- 添加列
ALTER TABLE myproject.mydataset.users ADD COLUMN phone STRING;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone STRING;

-- 添加列（带约束）
ALTER TABLE users ADD COLUMN status INT64 NOT NULL DEFAULT 1;

-- 删除列
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN IF EXISTS phone;

-- 重命名列
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- 修改列类型（仅允许兼容的类型变更）
-- INT64 -> NUMERIC, FLOAT64 -> NUMERIC 等
ALTER TABLE users ALTER COLUMN age SET DATA TYPE NUMERIC;

-- 修改默认值
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- 修改 NOT NULL（放宽为可空）
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;
-- 注意：不能从可空改为 NOT NULL

-- 修改列选项
ALTER TABLE users ALTER COLUMN email SET OPTIONS (description = 'User email');

-- 设置表选项
ALTER TABLE users SET OPTIONS (
    description = 'User information table',
    expiration_timestamp = TIMESTAMP '2026-12-31 00:00:00 UTC',
    labels = [('env', 'prod'), ('team', 'backend')]
);

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 添加/删除分区过期
ALTER TABLE orders SET OPTIONS (
    partition_expiration_days = 90
);

-- 修改聚集列（需要重建表）
-- BigQuery 不支持直接修改聚集列，需要 CREATE TABLE AS SELECT

-- 添加信息性主键（不强制执行）
ALTER TABLE users ADD PRIMARY KEY (id) NOT ENFORCED;

-- 添加信息性外键（不强制执行）
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id) NOT ENFORCED;

-- 删除信息性约束
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;

-- 注意：不支持同时多个 ADD/DROP COLUMN 操作
-- 注意：DDL 操作是元数据操作，通常很快
-- 注意：表名格式为 project.dataset.table
