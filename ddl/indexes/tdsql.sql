-- TDSQL: 索引
-- TDSQL distributed MySQL-compatible syntax.
--
-- 参考资料:
--   [1] TDSQL-C MySQL Documentation
--       https://cloud.tencent.com/document/product/1003
--   [2] TDSQL MySQL Documentation
--       https://cloud.tencent.com/document/product/557

-- 普通索引
CREATE INDEX idx_age ON users (age);

-- 唯一索引
CREATE UNIQUE INDEX uk_email ON users (email);

-- 复合索引
CREATE INDEX idx_city_age ON users (city, age);

-- 前缀索引
CREATE INDEX idx_email_prefix ON users (email(20));

-- 降序索引
CREATE INDEX idx_age_desc ON users (age DESC);

-- 函数索引（表达式索引）
CREATE INDEX idx_upper_name ON users ((UPPER(username)));

-- 不可见索引
CREATE INDEX idx_age ON users (age) INVISIBLE;
ALTER TABLE users ALTER INDEX idx_age VISIBLE;

-- 删除索引
DROP INDEX idx_age ON users;
DROP INDEX IF EXISTS idx_age ON users;

-- 查看索引
SHOW INDEX FROM users;

-- USING 指定索引类型
CREATE INDEX idx_age ON users (age) USING BTREE;

-- 注意事项：
-- 索引在每个分片上独立创建和维护
-- 唯一索引必须包含 shardkey 列（否则无法保证全局唯一性）
-- 不支持 FULLTEXT 索引
-- 不支持 SPATIAL 索引
-- CREATE INDEX 会在所有分片上同步执行
-- 索引只能保证分片内的数据有序
-- 非 shardkey 上的索引查询可能需要扫描所有分片
