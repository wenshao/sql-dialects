-- PolarDB: UPSERT
-- PolarDB-X (distributed, MySQL compatible).
--
-- 参考资料:
--   [1] PolarDB-X SQL Reference
--       https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/
--   [2] PolarDB MySQL Documentation
--       https://help.aliyun.com/zh/polardb/polardb-for-mysql/

-- 方式一: ON DUPLICATE KEY UPDATE
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
ON DUPLICATE KEY UPDATE
    email = VALUES(email),
    age = VALUES(age);

-- VALUES() 已废弃，推荐用别名
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25) AS new
ON DUPLICATE KEY UPDATE
    email = new.email,
    age = new.age;

-- 方式二: REPLACE INTO
REPLACE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

-- 方式三: INSERT IGNORE
INSERT IGNORE INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25);

-- 注意事项：
-- ON DUPLICATE KEY UPDATE 在分布式环境下需要有唯一索引
-- REPLACE INTO 会先 DELETE 再 INSERT，注意自增值变化
-- 全局唯一索引（GSI）可以跨分片检测冲突
-- 跨分片的 UPSERT 使用分布式事务
