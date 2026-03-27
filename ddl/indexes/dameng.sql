-- DamengDB (达梦): 索引
-- Oracle compatible syntax.
--
-- 参考资料:
--   [1] DamengDB SQL Reference
--       https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html
--   [2] DamengDB System Admin Manual
--       https://eco.dameng.com/document/dm/zh-cn/pm/index.html

-- 普通索引（B-tree）
CREATE INDEX idx_age ON users (age);

-- 唯一索引
CREATE UNIQUE INDEX uk_email ON users (email);

-- 复合索引
CREATE INDEX idx_city_age ON users (city, age);

-- 降序索引
CREATE INDEX idx_age_desc ON users (age DESC);

-- 函数索引
CREATE INDEX idx_upper_name ON users (UPPER(username));

-- 位图索引（低基数列，适合 OLAP）
CREATE BITMAP INDEX idx_status ON users (status);

-- 反向键索引（避免插入热点）
CREATE INDEX idx_id_rev ON users (id) REVERSE;

-- 不可见索引
CREATE INDEX idx_age ON users (age) INVISIBLE;
ALTER INDEX idx_age VISIBLE;

-- 在线创建（不阻塞 DML）
CREATE INDEX idx_age ON users (age) ONLINE;

-- 分区索引
-- 本地分区索引（与表分区对齐）
CREATE INDEX idx_date ON logs (log_date) LOCAL;
-- 全局分区索引
CREATE INDEX idx_id ON logs (id) GLOBAL
    PARTITION BY RANGE (id) (
        PARTITION p1 VALUES LESS THAN (10000),
        PARTITION p2 VALUES LESS THAN (MAXVALUE)
    );

-- 全文索引
CREATE CONTEXT INDEX idx_ft_bio ON users (bio) LEXER DEFAULT_LEXER;

-- 删除索引
DROP INDEX idx_age;
DROP INDEX IF EXISTS idx_age;

-- 重建索引
ALTER INDEX idx_age REBUILD;
ALTER INDEX idx_age REBUILD ONLINE;

-- 查看索引
SELECT INDEX_NAME, INDEX_TYPE, UNIQUENESS
FROM USER_INDEXES WHERE TABLE_NAME = 'USERS';
SELECT * FROM USER_IND_COLUMNS WHERE TABLE_NAME = 'USERS';

-- 注意事项：
-- 语法与 Oracle 高度兼容
-- 支持位图索引（用于数据仓库场景）
-- 支持在线索引操作
-- 支持本地和全局分区索引
-- 全文索引使用 CONTEXT INDEX 语法
