-- SQLite: CREATE TABLE
--
-- 参考资料:
--   [1] SQLite Documentation - CREATE TABLE
--       https://www.sqlite.org/lang_createtable.html
--   [2] SQLite Documentation - Datatypes
--       https://www.sqlite.org/datatype3.html

CREATE TABLE users (
    id         INTEGER      PRIMARY KEY AUTOINCREMENT,  -- 必须是 INTEGER 才能自增
    username   TEXT         NOT NULL UNIQUE,
    email      TEXT         NOT NULL UNIQUE,
    age        INTEGER,
    balance    REAL         DEFAULT 0.00,               -- SQLite 没有 DECIMAL 类型
    bio        TEXT,
    created_at TEXT         NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT         NOT NULL DEFAULT (datetime('now'))
);

-- SQLite 没有 ON UPDATE，需要用触发器
CREATE TRIGGER trg_users_updated_at
    AFTER UPDATE ON users
    FOR EACH ROW
BEGIN
    UPDATE users SET updated_at = datetime('now') WHERE id = NEW.id;
END;
