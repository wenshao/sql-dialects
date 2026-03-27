-- StarRocks: ALTER TABLE
--
-- 参考资料:
--   [1] StarRocks - ALTER TABLE
--       https://docs.starrocks.io/docs/sql-reference/sql-statements/table_bucket_part_index/ALTER_TABLE/
--   [2] StarRocks - Data Types
--       https://docs.starrocks.io/docs/sql-reference/data-types/

-- 添加列
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;

-- 添加多列
ALTER TABLE users ADD COLUMN (
    city    VARCHAR(64),
    country VARCHAR(64)
);

-- 删除列
ALTER TABLE users DROP COLUMN phone;

-- 修改列类型（仅允许兼容变更）
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32);
-- INT -> BIGINT, VARCHAR(N) -> VARCHAR(M) 其中 M > N

-- 修改列顺序
ALTER TABLE users ORDER BY (id, username, email, age);

-- 修改列默认值
ALTER TABLE users MODIFY COLUMN status INT DEFAULT 0;

-- 重命名表
ALTER TABLE users RENAME members;

-- 添加/删除分区
ALTER TABLE orders ADD PARTITION p2024_04 VALUES LESS THAN ('2024-05-01');
ALTER TABLE orders ADD PARTITION p2024_04 VALUES [('2024-04-01'), ('2024-05-01'));
ALTER TABLE orders DROP PARTITION p2024_01;

-- 修改分区 TTL
ALTER TABLE orders MODIFY PARTITION (*) SET (
    "storage_medium" = "HDD",
    "storage_cooldown_time" = "2025-01-01 00:00:00"
);

-- 修改分桶数
ALTER TABLE users SET ("default_replication_num" = "1");

-- 修改表属性
ALTER TABLE users SET ("replication_num" = "1");
ALTER TABLE users SET ("in_memory" = "true");
ALTER TABLE users SET ("storage_medium" = "SSD");

-- Swap 表
ALTER TABLE users SWAP WITH users_new;

-- 修改 COMMENT
ALTER TABLE users MODIFY COMMENT 'User information table';

-- 创建 Rollup（聚合模型的物化视图）
ALTER TABLE daily_stats ADD ROLLUP rollup_by_date (date, SUM(clicks))
    PROPERTIES ("replication_num" = "1");
ALTER TABLE daily_stats DROP ROLLUP rollup_by_date;

-- 查看 ALTER 任务进度
SHOW ALTER TABLE COLUMN;
SHOW ALTER TABLE ROLLUP;

-- 注意：不支持重命名列（需要重建表）
-- 注意：不能删除 Key 列（排序键/分桶键/分区键）
-- 注意：添加列不能添加到 Key 列中
-- 注意：Aggregate Key 模型中 Value 列的聚合方式不能修改
