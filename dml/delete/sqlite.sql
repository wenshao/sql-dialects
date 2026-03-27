-- SQLite: DELETE
--
-- 参考资料:
--   [1] SQLite Documentation - DELETE
--       https://www.sqlite.org/lang_delete.html

-- 基本删除
DELETE FROM users WHERE username = 'alice';

-- 带 LIMIT / ORDER BY（需要 SQLITE_ENABLE_UPDATE_DELETE_LIMIT 编译选项）
DELETE FROM users WHERE status = 0 ORDER BY created_at LIMIT 100;

-- 子查询删除
DELETE FROM users WHERE id IN (SELECT user_id FROM blacklist);

-- 3.35.0+: RETURNING
DELETE FROM users WHERE status = 0 RETURNING id, username;

-- 删除所有行
DELETE FROM users;
-- 注意：SQLite 没有 TRUNCATE，DELETE FROM 无 WHERE 就相当于清空
-- 可以用 DROP + CREATE 来重建表

-- 回收空间（DELETE 后文件大小不变）
VACUUM;
