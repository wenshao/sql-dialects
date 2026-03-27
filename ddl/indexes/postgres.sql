-- PostgreSQL: 索引
--
-- 参考资料:
--   [1] PostgreSQL Documentation - CREATE INDEX
--       https://www.postgresql.org/docs/current/sql-createindex.html
--   [2] PostgreSQL Documentation - Indexes
--       https://www.postgresql.org/docs/current/indexes.html
--   [3] PostgreSQL Documentation - Index Types
--       https://www.postgresql.org/docs/current/indexes-types.html

-- 普通索引（B-tree，默认）
CREATE INDEX idx_age ON users (age);

-- 唯一索引
CREATE UNIQUE INDEX uk_email ON users (email);

-- 复合索引
CREATE INDEX idx_city_age ON users (city, age);

-- 降序索引
CREATE INDEX idx_age_desc ON users (age DESC);

-- 表达式索引（所有版本）
CREATE INDEX idx_lower_email ON users (LOWER(email));
CREATE INDEX idx_year ON events (EXTRACT(YEAR FROM created_at));

-- 部分索引（只索引满足条件的行）
CREATE INDEX idx_active_users ON users (username) WHERE status = 1;

-- 并发创建（不锁表，但速度更慢）
CREATE INDEX CONCURRENTLY idx_age ON users (age);

-- 包含列索引（11+，Index-Only Scan 友好）
CREATE INDEX idx_username_incl ON users (username) INCLUDE (email, age);

-- 不同索引类型
CREATE INDEX idx_btree ON users USING btree (age);      -- 默认
CREATE INDEX idx_hash ON users USING hash (username);    -- 等值查询
CREATE INDEX idx_gin ON documents USING gin (tags);      -- 数组、JSONB、全文
CREATE INDEX idx_gist ON places USING gist (location);   -- 几何、范围、全文
CREATE INDEX idx_brin ON logs USING brin (created_at);   -- 大表顺序数据（9.5+）

-- GIN 索引用于 JSONB
CREATE INDEX idx_data ON users USING gin (data jsonb_path_ops);

-- 全文搜索索引
CREATE INDEX idx_ft ON articles USING gin (to_tsvector('english', content));

-- 删除索引
DROP INDEX idx_age;
DROP INDEX IF EXISTS idx_age;
DROP INDEX CONCURRENTLY idx_age;

-- 重建索引
REINDEX INDEX idx_age;
-- 12+: 并发重建
REINDEX INDEX CONCURRENTLY idx_age;

-- 查看索引
SELECT * FROM pg_indexes WHERE tablename = 'users';
