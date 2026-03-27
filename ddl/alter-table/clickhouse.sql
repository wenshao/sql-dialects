-- ClickHouse: ALTER TABLE
--
-- 参考资料:
--   [1] ClickHouse SQL Reference - ALTER TABLE
--       https://clickhouse.com/docs/en/sql-reference/statements/alter
--   [2] ClickHouse SQL Reference - ALTER COLUMN
--       https://clickhouse.com/docs/en/sql-reference/statements/alter/column

-- 添加列
ALTER TABLE users ADD COLUMN phone String;
ALTER TABLE users ADD COLUMN phone String AFTER email;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone String;

-- 添加列（带默认值）
ALTER TABLE users ADD COLUMN status UInt8 DEFAULT 1;

-- 删除列
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN IF EXISTS phone;

-- 修改列类型
ALTER TABLE users MODIFY COLUMN phone String;
ALTER TABLE users MODIFY COLUMN age Nullable(UInt16);
-- 类型变更在后台异步执行（mutation）

-- 重命名列
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- 修改默认值
ALTER TABLE users MODIFY COLUMN status UInt8 DEFAULT 0;

-- 清除列数据（用默认值填充，MergeTree 引擎）
ALTER TABLE users CLEAR COLUMN phone;
ALTER TABLE users CLEAR COLUMN phone IN PARTITION '202401';

-- 修改列注释
ALTER TABLE users COMMENT COLUMN phone 'User phone number';

-- 修改列编码
ALTER TABLE users MODIFY COLUMN username String CODEC(ZSTD(3));

-- 修改列 TTL
ALTER TABLE users MODIFY COLUMN phone String TTL created_at + INTERVAL 90 DAY;

-- 修改表 TTL
ALTER TABLE logs MODIFY TTL timestamp + INTERVAL 30 DAY;

-- 分区操作
ALTER TABLE orders DETACH PARTITION '202401';
ALTER TABLE orders ATTACH PARTITION '202401';
ALTER TABLE orders DROP PARTITION '202401';
ALTER TABLE orders FREEZE PARTITION '202401';  -- 备份
ALTER TABLE orders REPLACE PARTITION '202401' FROM orders_staging;
ALTER TABLE orders MOVE PARTITION '202401' TO TABLE orders_archive;

-- 轻量级 DELETE 和 UPDATE（mutations，异步执行）
ALTER TABLE users DELETE WHERE status = 0;
ALTER TABLE users UPDATE status = 1 WHERE id = 100;

-- 添加/删除数据跳过索引
ALTER TABLE users ADD INDEX idx_email email TYPE bloom_filter GRANULARITY 4;
ALTER TABLE users DROP INDEX idx_email;

-- ORDER BY 修改
ALTER TABLE users MODIFY ORDER BY (id, username);

-- 查看 mutations 进度
SELECT * FROM system.mutations WHERE table = 'users' AND is_done = 0;

-- 注意：列操作是即时的（元数据变更）
-- 注意：MODIFY COLUMN 类型变更是异步 mutation
-- 注意：DELETE/UPDATE 是异步 mutation，不是立即执行
-- 注意：不支持重命名表（需要用 RENAME TABLE）
RENAME TABLE users TO members;
