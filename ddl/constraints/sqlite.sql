-- SQLite: 约束
--
-- 参考资料:
--   [1] SQLite Documentation - CREATE TABLE (Constraints)
--       https://www.sqlite.org/lang_createtable.html
--   [2] SQLite Documentation - Foreign Key Support
--       https://www.sqlite.org/foreignkeys.html

-- PRIMARY KEY（建表时定义）
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT
);
-- 复合主键
CREATE TABLE order_items (
    order_id INTEGER NOT NULL,
    item_id  INTEGER NOT NULL,
    PRIMARY KEY (order_id, item_id)
);

-- UNIQUE（建表时定义）
CREATE TABLE users (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    email    TEXT NOT NULL,
    UNIQUE (email)
);

-- FOREIGN KEY
-- 注意：必须先开启外键支持（默认关闭！）
PRAGMA foreign_keys = ON;

CREATE TABLE orders (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users (id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
-- 动作: CASCADE / SET NULL / SET DEFAULT / RESTRICT / NO ACTION

-- NOT NULL / DEFAULT（只能在建表时定义）
CREATE TABLE users (
    id     INTEGER PRIMARY KEY AUTOINCREMENT,
    status INTEGER NOT NULL DEFAULT 1
);

-- CHECK（3.0+，但一直支持）
CREATE TABLE users (
    id  INTEGER PRIMARY KEY AUTOINCREMENT,
    age INTEGER CHECK (age >= 0 AND age <= 200)
);

-- 注意：SQLite 不支持 ALTER TABLE 添加/删除约束！
-- 修改约束必须重建表（见 alter-table/sqlite.sql）

-- 查看约束
PRAGMA table_info('users');
PRAGMA foreign_key_list('orders');
