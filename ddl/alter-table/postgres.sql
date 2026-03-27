-- PostgreSQL: ALTER TABLE
--
-- 参考资料:
--   [1] PostgreSQL Documentation - ALTER TABLE
--       https://www.postgresql.org/docs/current/sql-altertable.html
--   [2] PostgreSQL Documentation - Data Types
--       https://www.postgresql.org/docs/current/datatype.html

-- 添加列
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
-- 注意：不支持 AFTER / FIRST，列总是添加到末尾

-- 添加列（带约束）
ALTER TABLE users ADD COLUMN status INTEGER NOT NULL DEFAULT 1;

-- 修改列类型
ALTER TABLE users ALTER COLUMN phone TYPE VARCHAR(32);
-- 类型不兼容时需要 USING
ALTER TABLE users ALTER COLUMN age TYPE TEXT USING age::TEXT;

-- 重命名列
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- 删除列
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN IF EXISTS phone;

-- 一次多个操作
ALTER TABLE users
    ADD COLUMN city VARCHAR(64),
    ADD COLUMN country VARCHAR(64),
    DROP COLUMN IF EXISTS phone;

-- 修改默认值
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- 设置 / 去除 NOT NULL
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

-- 重命名表
ALTER TABLE users RENAME TO members;

-- 修改 schema
ALTER TABLE users SET SCHEMA archive;

-- 11+: 添加带非 NULL 默认值的列是即时的（不重写表）
