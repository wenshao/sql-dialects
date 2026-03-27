-- Hologres: ALTER TABLE
--
-- 参考资料:
--   [1] Hologres SQL - ALTER TABLE
--       https://help.aliyun.com/zh/hologres/user-guide/alter-table
--   [2] Hologres SQL Reference
--       https://help.aliyun.com/zh/hologres/user-guide/overview-27

-- 添加列（兼容 PostgreSQL 语法）
ALTER TABLE users ADD COLUMN phone TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;

-- 添加列（带约束）
ALTER TABLE users ADD COLUMN status INTEGER NOT NULL DEFAULT 1;

-- 删除列
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN IF EXISTS phone;

-- 重命名列
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- 修改列类型
ALTER TABLE users ALTER COLUMN phone TYPE VARCHAR(32);

-- 设置/去除 NOT NULL
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

-- 修改默认值
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 修改表属性（Hologres 特色，通过 CALL 设置）
CALL set_table_property('users', 'orientation', 'column');
CALL set_table_property('users', 'clustering_key', 'id');
CALL set_table_property('users', 'segment_key', 'created_at');
CALL set_table_property('users', 'bitmap_columns', 'username,email');
CALL set_table_property('users', 'dictionary_encoding_columns', 'status');
CALL set_table_property('users', 'distribution_key', 'id');

-- 修改 TTL
CALL set_table_property('users', 'time_to_live_in_seconds', '7776000'); -- 90 天

-- 修改 Binlog 设置
CALL set_table_property('users', 'binlog.level', 'replica');
CALL set_table_property('users', 'binlog.ttl', '86400');

-- 分区操作（LIST 分区）
-- 子分区通过 CREATE TABLE ... PARTITION OF 创建
-- 删除子分区通过 DROP TABLE 删除

-- 修改表 OWNER
ALTER TABLE users OWNER TO new_owner;

-- 注意：Hologres 兼容 PostgreSQL 语法
-- 注意：核心属性通过 CALL set_table_property 设置
-- 注意：不支持修改主键（需要重建表）
-- 注意：不支持修改分区键（需要重建表）
-- 注意：某些属性在表创建后不可修改（如 orientation）
