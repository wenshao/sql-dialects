-- MySQL: 索引
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - CREATE INDEX
--       https://dev.mysql.com/doc/refman/8.0/en/create-index.html
--   [2] MySQL 8.0 Reference Manual - Optimization and Indexes
--       https://dev.mysql.com/doc/refman/8.0/en/optimization-indexes.html
--   [3] MySQL 8.0 Reference Manual - FULLTEXT Indexes
--       https://dev.mysql.com/doc/refman/8.0/en/fulltext-search.html

-- 普通索引
CREATE INDEX idx_age ON users (age);

-- 唯一索引
CREATE UNIQUE INDEX uk_email ON users (email);

-- 复合索引
CREATE INDEX idx_city_age ON users (city, age);

-- 前缀索引（对长字符串列只索引前 N 个字符）
CREATE INDEX idx_email_prefix ON users (email(20));

-- 全文索引（5.6+ InnoDB，之前只有 MyISAM）
CREATE FULLTEXT INDEX idx_ft_bio ON users (bio);

-- 空间索引
CREATE SPATIAL INDEX idx_location ON places (geo_point);

-- 降序索引语法在 8.0 之前被解析但实际忽略（均按 ASC 存储）
-- 8.0+: 真正的降序索引
CREATE INDEX idx_age_desc ON users (age DESC);

-- 8.0+: 函数索引（表达式索引）
CREATE INDEX idx_upper_name ON users ((UPPER(username)));
CREATE INDEX idx_json_name ON users ((CAST(data->>'$.name' AS CHAR(64))));

-- 8.0+: 不可见索引（优化器不使用，但仍维护）
CREATE INDEX idx_age ON users (age) INVISIBLE;
ALTER TABLE users ALTER INDEX idx_age VISIBLE;

-- 删除索引
DROP INDEX idx_age ON users;
-- 注意：MySQL 不支持 DROP INDEX IF EXISTS（MariaDB 扩展语法）
-- 可用 ALTER TABLE 方式删除索引：
ALTER TABLE users DROP INDEX idx_age;

-- 查看索引
SHOW INDEX FROM users;

-- USING 指定索引类型
CREATE INDEX idx_age ON users (age) USING BTREE;    -- 默认
CREATE INDEX idx_hash ON users (username) USING HASH; -- 仅 MEMORY 引擎
