-- SQLite: ALTER TABLE（功能非常有限）
--
-- 参考资料:
--   [1] SQLite Documentation - ALTER TABLE
--       https://www.sqlite.org/lang_altertable.html
--   [2] SQLite Documentation - CREATE TABLE
--       https://www.sqlite.org/lang_createtable.html

-- 添加列（所有版本）
ALTER TABLE users ADD COLUMN phone TEXT;
-- 限制：不支持 AFTER / FIRST
-- 限制：新增列不能有 PRIMARY KEY 或 UNIQUE 约束
-- 限制：默认值不能是 CURRENT_TIMESTAMP 等表达式（3.37.0 之前）

-- 重命名表（所有版本）
ALTER TABLE users RENAME TO members;

-- 3.25.0+: 重命名列
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- 3.35.0+: 删除列
ALTER TABLE users DROP COLUMN phone;

-- 不支持的操作（需要重建表来实现）:
-- ✗ 修改列类型
-- ✗ 修改列约束
-- ✗ 修改列默认值
-- ✗ 添加/删除 PRIMARY KEY

-- 重建表的标准步骤：
-- 1. 创建新表
CREATE TABLE users_new (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    email    TEXT NOT NULL,
    age      INTEGER,
    phone    TEXT NOT NULL DEFAULT ''    -- 修改了约束
);
-- 2. 复制数据
INSERT INTO users_new (id, username, email, age)
SELECT id, username, email, age FROM users;
-- 3. 删除旧表
DROP TABLE users;
-- 4. 重命名
ALTER TABLE users_new RENAME TO users;
