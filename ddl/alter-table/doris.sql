-- Apache Doris: ALTER TABLE
--
-- 参考资料:
--   [1] Doris SQL Manual
--       https://doris.apache.org/docs/sql-manual/sql-statements/
--   [2] Doris Data Types
--       https://doris.apache.org/docs/sql-manual/data-types/
--   [3] Doris Functions
--       https://doris.apache.org/docs/sql-manual/sql-functions/

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

-- Light Schema Change（1.2+，秒级生效）
-- VARCHAR 扩容、添加/删除 Value 列等不需要数据重写
-- 自动识别，无需额外语法

-- 修改列默认值
ALTER TABLE users MODIFY COLUMN status INT DEFAULT 0;

-- 修改列顺序
ALTER TABLE users ORDER BY (id, username, email, age);

-- 重命名表
ALTER TABLE users RENAME members;

-- 添加/删除分区
ALTER TABLE orders ADD PARTITION p2024_04 VALUES LESS THAN ('2024-05-01');
ALTER TABLE orders ADD PARTITION p2024_04 VALUES [('2024-04-01'), ('2024-05-01'));
ALTER TABLE orders DROP PARTITION p2024_01;

-- 批量添加分区（2.1+）
ALTER TABLE orders ADD PARTITIONS FROM ('2024-01-01') TO ('2024-12-01') INTERVAL 1 MONTH;

-- 修改分区属性
ALTER TABLE orders MODIFY PARTITION p2024_01 SET (
    "storage_medium" = "HDD",
    "storage_cooldown_time" = "2025-01-01 00:00:00"
);

-- 修改表属性
ALTER TABLE users SET ("replication_num" = "1");
ALTER TABLE users SET ("in_memory" = "true");
ALTER TABLE users SET ("storage_medium" = "SSD");

-- 创建/删除 Rollup
ALTER TABLE daily_stats ADD ROLLUP rollup_by_date (date, clicks)
    PROPERTIES ("replication_num" = "1");
ALTER TABLE daily_stats DROP ROLLUP rollup_by_date;

-- 修改 COMMENT
ALTER TABLE users MODIFY COMMENT 'User information table';
ALTER TABLE users MODIFY COLUMN username COMMENT 'Login name';

-- Replace Table（原子替换）
ALTER TABLE users REPLACE WITH TABLE users_new;

-- 修改分桶数（2.0+）
ALTER TABLE users MODIFY DISTRIBUTION DISTRIBUTED BY HASH(id) BUCKETS 32;

-- 查看 ALTER 任务进度
SHOW ALTER TABLE COLUMN;
SHOW ALTER TABLE ROLLUP;

-- 注意：2.0+ 支持 RENAME COLUMN（ALTER TABLE t RENAME COLUMN old TO new）
-- 注意：不能删除 Key 列（排序键/分桶键/分区键）
-- 注意：添加列不能添加到 Key 列中
-- 注意：Aggregate Key 模型中 Value 列的聚合方式不能修改
