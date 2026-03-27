-- TDSQL: ALTER TABLE
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

-- 添加列
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;
ALTER TABLE users ADD COLUMN status TINYINT NOT NULL DEFAULT 1 FIRST;

-- 一次添加多列
ALTER TABLE users
    ADD COLUMN city VARCHAR(64),
    ADD COLUMN country VARCHAR(64);

-- 修改列类型
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32) NOT NULL;

-- 重命名列
ALTER TABLE users CHANGE COLUMN phone mobile VARCHAR(32);
ALTER TABLE users RENAME COLUMN mobile TO phone;

-- 删除列
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);
ALTER TABLE users DROP COLUMN IF EXISTS phone;

-- 修改默认值
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- 重命名表
ALTER TABLE users RENAME TO members;
RENAME TABLE users TO members;

-- 修改表引擎 / 字符集
ALTER TABLE users ENGINE = InnoDB;
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 即时列添加
ALTER TABLE users ADD COLUMN tag VARCHAR(32), ALGORITHM=INSTANT;

-- 分区管理
-- 添加分区（节点内分区）
ALTER TABLE logs ADD PARTITION (
    PARTITION p2026 VALUES LESS THAN (2027)
);

-- 删除分区
ALTER TABLE logs DROP PARTITION p2023;

-- 注意事项：
-- 分布式 DDL 操作会在所有分片上执行
-- 不能修改 shardkey 列
-- ALTER TABLE 操作会在所有分片上同步执行
-- 修改列类型时所有分片必须都能成功
-- 广播表的 ALTER TABLE 会同步到所有节点
