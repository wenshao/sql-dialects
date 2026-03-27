-- MySQL: ALTER TABLE
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - ALTER TABLE
--       https://dev.mysql.com/doc/refman/8.0/en/alter-table.html
--   [2] MySQL 8.0 Reference Manual - Data Types
--       https://dev.mysql.com/doc/refman/8.0/en/data-types.html

-- 添加列
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;
ALTER TABLE users ADD COLUMN status TINYINT NOT NULL DEFAULT 1 FIRST;

-- 支持一次添加多列（所有版本均支持）
ALTER TABLE users
    ADD COLUMN city VARCHAR(64),
    ADD COLUMN country VARCHAR(64);

-- 修改列类型
ALTER TABLE users MODIFY COLUMN phone VARCHAR(32) NOT NULL;

-- 重命名列
-- 5.7: 必须用 CHANGE，需要重新声明类型
ALTER TABLE users CHANGE COLUMN phone mobile VARCHAR(32);
-- 8.0+: RENAME COLUMN（不需要重新声明类型）
ALTER TABLE users RENAME COLUMN mobile TO phone;

-- 删除列
ALTER TABLE users DROP COLUMN phone;

-- 注意：MySQL 不支持 ALTER TABLE ADD/DROP COLUMN IF [NOT] EXISTS
-- 这是 MariaDB 的扩展语法；MySQL 中需要用其他方式处理（如查询 information_schema）

-- 修改默认值
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- 重命名表
ALTER TABLE users RENAME TO members;
-- 或
RENAME TABLE users TO members;

-- 修改表引擎 / 字符集
ALTER TABLE users ENGINE = InnoDB;
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 8.0.12+: 即时列添加（INSTANT，不锁表不重建）
ALTER TABLE users ADD COLUMN tag VARCHAR(32), ALGORITHM=INSTANT;
