-- SQLite: Error Handling
--
-- 参考资料:
--   [1] SQLite Documentation - Result Codes
--       https://www.sqlite.org/rescode.html
--   [2] SQLite Documentation - C API Error Handling
--       https://www.sqlite.org/c3ref/errcode.html

-- ============================================================
-- SQLite 没有内置的服务端错误处理
-- ============================================================
-- SQLite 是嵌入式数据库，没有存储过程或 PL/SQL
-- 错误处理必须在应用层实现

-- ============================================================
-- 应用层替代方案: Python
-- ============================================================
-- import sqlite3
--
-- conn = sqlite3.connect('mydb.db')
-- try:
--     conn.execute('INSERT INTO users(id, username) VALUES(1, "test")')
--     conn.commit()
-- except sqlite3.IntegrityError as e:
--     print(f'Constraint violation: {e}')
--     conn.rollback()
-- except sqlite3.OperationalError as e:
--     print(f'Operational error: {e}')
--     conn.rollback()
-- except sqlite3.Error as e:
--     print(f'SQLite error: {e}')
--     conn.rollback()

-- ============================================================
-- SQLite 错误码 (通过 C API 返回)
-- ============================================================
-- SQLITE_OK         (0)   成功
-- SQLITE_ERROR      (1)   通用错误
-- SQLITE_BUSY       (5)   数据库被锁定
-- SQLITE_LOCKED     (6)   表被锁定
-- SQLITE_CONSTRAINT (19)  约束违反
-- SQLITE_MISMATCH   (20)  数据类型不匹配
-- SQLITE_READONLY   (8)   只读数据库

-- ============================================================
-- SQL 层面的错误避免策略
-- ============================================================
-- 使用 INSERT OR IGNORE 忽略约束错误
INSERT OR IGNORE INTO users(id, username) VALUES(1, 'test');

-- 使用 INSERT OR REPLACE 替换已有记录
INSERT OR REPLACE INTO users(id, username) VALUES(1, 'updated');

-- 使用 ON CONFLICT 子句
INSERT INTO users(id, username) VALUES(1, 'test')
    ON CONFLICT(id) DO UPDATE SET username = excluded.username;

-- 使用 IF EXISTS / IF NOT EXISTS 避免 DDL 错误
CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, username TEXT);
DROP TABLE IF EXISTS temp_table;

-- 注意：SQLite 不支持服务端错误处理
-- 注意：错误处理完全在应用层实现
-- 注意：使用 OR IGNORE / OR REPLACE / ON CONFLICT 避免约束错误
-- 注意：SQLite 扩展错误码提供更详细的错误信息
-- 限制：无 TRY/CATCH, EXCEPTION WHEN, DECLARE HANDLER
-- 限制：无 SIGNAL / RAISE / RAISERROR
-- 限制：无存储过程
