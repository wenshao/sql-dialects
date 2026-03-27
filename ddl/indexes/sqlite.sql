-- SQLite: 索引
--
-- 参考资料:
--   [1] SQLite Documentation - CREATE INDEX
--       https://www.sqlite.org/lang_createindex.html
--   [2] SQLite Documentation - Query Planner
--       https://www.sqlite.org/queryplanner.html

-- 普通索引
CREATE INDEX idx_age ON users (age);

-- 唯一索引
CREATE UNIQUE INDEX uk_email ON users (email);

-- 复合索引
CREATE INDEX idx_city_age ON users (city, age);

-- IF NOT EXISTS
CREATE INDEX IF NOT EXISTS idx_age ON users (age);

-- 部分索引（3.8.0+）
CREATE INDEX idx_active_users ON users (username) WHERE status = 1;

-- 表达式索引（3.9.0+）
CREATE INDEX idx_lower_email ON users (LOWER(email));

-- 降序
CREATE INDEX idx_age_desc ON users (age DESC);

-- 删除索引
DROP INDEX idx_age;
DROP INDEX IF EXISTS idx_age;

-- 查看索引
SELECT * FROM sqlite_master WHERE type = 'index';
-- 或
PRAGMA index_list('users');
PRAGMA index_info('idx_age');

-- 注意：SQLite 只支持 B-tree 索引，不支持 HASH、GIN、GiST 等
-- 注意：没有 ALTER INDEX，要修改索引必须 DROP + CREATE
-- 注意：没有 CONCURRENTLY 选项
