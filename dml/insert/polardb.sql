-- PolarDB: INSERT
-- PolarDB-X (distributed, MySQL compatible).
--
-- 参考资料:
--   [1] PolarDB-X SQL Reference
--       https://help.aliyun.com/zh/polardb/polardb-for-xscale/sql-reference/
--   [2] PolarDB MySQL Documentation
--       https://help.aliyun.com/zh/polardb/polardb-for-mysql/

-- 单行插入
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 多行插入
INSERT INTO users (username, email, age) VALUES
    ('alice', 'alice@example.com', 25),
    ('bob', 'bob@example.com', 30),
    ('charlie', 'charlie@example.com', 35);

-- 插入并忽略重复
INSERT IGNORE INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);

-- 从查询结果插入
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;

-- VALUES 行别名
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25) AS new
ON DUPLICATE KEY UPDATE email = new.email;

-- 获取自增 ID
INSERT INTO users (username, email) VALUES ('alice', 'alice@example.com');
SELECT LAST_INSERT_ID();

-- 指定列默认值
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', DEFAULT);

-- SET 语法（MySQL 特有）
INSERT INTO users SET username = 'alice', email = 'alice@example.com', age = 25;

-- 注意事项：
-- 分布式环境下批量插入会按分区键路由到不同分片
-- AUTO_INCREMENT 在分布式环境下全局唯一但不保证连续
-- LAST_INSERT_ID() 返回当前会话最后插入的自增值
-- 广播表的插入会同步到所有节点
-- 大批量插入建议按分片键排序以减少跨分片操作
