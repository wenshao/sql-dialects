-- TDSQL: INSERT
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

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

-- SET 语法
INSERT INTO users SET username = 'alice', email = 'alice@example.com', age = 25;

-- 注意事项：
-- 插入时必须指定 shardkey 列的值（否则无法路由到正确分片）
-- 批量插入中不同 shardkey 值的行会路由到不同分片
-- AUTO_INCREMENT 全局唯一但不连续
-- 广播表的插入会同步写入所有节点
-- INSERT ... SELECT 跨分片时会使用分布式执行计划
