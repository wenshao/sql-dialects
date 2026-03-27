-- MySQL: UPSERT
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - INSERT ... ON DUPLICATE KEY UPDATE
--       https://dev.mysql.com/doc/refman/8.0/en/insert-on-duplicate.html
--   [2] MySQL 8.0 Reference Manual - REPLACE
--       https://dev.mysql.com/doc/refman/8.0/en/replace.html

-- 方式一: ON DUPLICATE KEY UPDATE (4.1+)
-- 需要有唯一索引或主键冲突才会触发 UPDATE
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON DUPLICATE KEY UPDATE
    email = VALUES(email),
    age = VALUES(age);

-- VALUES() 在 UPDATE 子句中引用待插入的值（4.1+ 即可用）
-- 8.0.20+: VALUES() 在此场景中已废弃，推荐用行/列别名
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25) AS new
ON DUPLICATE KEY UPDATE
    email = new.email,
    age = new.age;

-- 方式二: REPLACE INTO
-- 冲突时先 DELETE 再 INSERT，会改变主键自增值，触发 DELETE 触发器
REPLACE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

-- 方式三: INSERT IGNORE
-- 冲突时静默跳过，不报错也不更新
INSERT IGNORE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);
