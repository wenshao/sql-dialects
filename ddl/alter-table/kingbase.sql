-- KingbaseES (人大金仓): ALTER TABLE
-- PostgreSQL compatible syntax.
--
-- 参考资料:
--   [1] KingbaseES SQL Reference
--       https://help.kingbase.com.cn/v8/index.html
--   [2] KingbaseES Documentation
--       https://help.kingbase.com.cn/v8/index.html

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

-- 分区管理
-- 附加分区
ALTER TABLE logs ATTACH PARTITION logs_2026
    FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

-- 分离分区
ALTER TABLE logs DETACH PARTITION logs_2023;

-- 修改表存储参数
ALTER TABLE users SET (FILLFACTOR = 80);

-- 注意事项：
-- 添加带非 NULL 默认值的列是即时的（不重写表）
-- 分区语法与 PostgreSQL 10+ 声明式分区一致
-- 支持 Oracle 兼容模式的 MODIFY 语法
