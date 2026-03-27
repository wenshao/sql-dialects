-- Trino (formerly PrestoSQL): ALTER TABLE
--
-- 参考资料:
--   [1] Trino - ALTER TABLE
--       https://trino.io/docs/current/sql/alter-table.html
--   [2] Trino - Data Types
--       https://trino.io/docs/current/language/types.html

-- 添加列
ALTER TABLE users ADD COLUMN phone VARCHAR;
-- 使用完整限定名
ALTER TABLE hive.mydb.users ADD COLUMN phone VARCHAR;

-- 删除列（取决于 Connector）
ALTER TABLE users DROP COLUMN phone;

-- 重命名列
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- 修改列类型（Iceberg Connector 支持）
ALTER TABLE users ALTER COLUMN age SET DATA TYPE BIGINT;

-- 设置/去除 NOT NULL（Iceberg Connector）
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 设置表注释
COMMENT ON TABLE users IS 'User information table';
COMMENT ON COLUMN users.email IS 'User email address';

-- 设置表属性（取决于 Connector）
ALTER TABLE users SET PROPERTIES format = 'ORC';

-- Hive Connector 属性
ALTER TABLE users SET PROPERTIES format = 'PARQUET';
-- 注意：partitioned_by 不能通过 ALTER TABLE 修改，必须在建表时指定

-- Iceberg Connector 属性
ALTER TABLE users SET PROPERTIES format = 'PARQUET';
ALTER TABLE users SET PROPERTIES partitioning = ARRAY['month(order_date)'];

-- 添加/删除分区（Hive Connector）
-- 使用 INSERT 自动创建分区，或通过 Hive 管理

-- Iceberg 分区演进（无需重写数据）
ALTER TABLE orders SET PROPERTIES partitioning = ARRAY['year(order_date)'];

-- 物化视图（Trino 不支持 ALTER MATERIALIZED VIEW SET PROPERTIES）
-- 物化视图的刷新需要通过外部调度工具管理
-- Trino 支持 REFRESH MATERIALIZED VIEW 手动刷新（部分 Connector）

-- 注意：DDL 能力完全取决于底层 Connector
-- Hive Connector: 支持 ADD/DROP COLUMN、RENAME TABLE
-- Iceberg Connector: 支持最多操作（类型变更、NOT NULL、分区演进）
-- Memory Connector: 基本不支持 ALTER
-- Delta Lake Connector: 支持 ADD COLUMN、RENAME COLUMN
-- 注意：不支持修改列默认值（大多数 Connector）
-- 注意：不支持多列同时操作
