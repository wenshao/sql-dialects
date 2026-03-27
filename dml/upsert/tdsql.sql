-- TDSQL: UPSERT
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

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
-- 唯一索引必须包含 shardkey 列才能正确检测冲突
-- 不包含 shardkey 的唯一索引无法保证全局唯一性
-- REPLACE INTO 会先 DELETE 再 INSERT
-- 跨分片的 UPSERT 使用分布式事务
-- 广播表的 UPSERT 会同步到所有节点
