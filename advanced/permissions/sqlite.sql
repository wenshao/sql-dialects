-- SQLite: 权限管理
--
-- 参考资料:
--   [1] SQLite Documentation - Set Authorizer
--       https://www.sqlite.org/c3ref/set_authorizer.html
--   [2] SQLite Documentation - Compile-Time Authorization
--       https://www.sqlite.org/compile.html

-- SQLite 没有内置的用户和权限系统！

-- 安全机制依赖于:
-- 1. 文件系统权限（数据库就是一个文件）
-- 2. 应用层权限控制

-- 文件权限示例（操作系统层面）：
-- chmod 640 database.db      -- 所有者读写，组只读
-- chown app:app database.db  -- 设置所有者

-- SQLite 授权回调（C API，在应用层面控制）
-- sqlite3_set_authorizer() 可以拦截所有 SQL 操作
-- 回调返回:
--   SQLITE_OK     -- 允许
--   SQLITE_DENY   -- 拒绝（报错）
--   SQLITE_IGNORE -- 忽略（SELECT 返回 NULL，其他忽略）

-- Python 示例:
-- def authorizer(action, arg1, arg2, db_name, trigger_name):
--     if action == sqlite3.SQLITE_DELETE:
--         return sqlite3.SQLITE_DENY
--     return sqlite3.SQLITE_OK
-- conn.set_authorizer(authorizer)

-- 注意：没有 GRANT/REVOKE 语句
-- 注意：没有用户/角色概念
-- 注意：没有行级安全
-- 注意：加密需要第三方扩展（如 SQLCipher）
