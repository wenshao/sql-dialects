-- SQL Server: 索引
--
-- 参考资料:
--   [1] SQL Server T-SQL - CREATE INDEX
--       https://learn.microsoft.com/en-us/sql/t-sql/statements/create-index-transact-sql
--   [2] SQL Server - Indexes
--       https://learn.microsoft.com/en-us/sql/relational-databases/indexes/indexes

-- 聚集索引（每表只能有一个，决定数据物理排序）
CREATE CLUSTERED INDEX idx_id ON users (id);

-- 非聚集索引
CREATE NONCLUSTERED INDEX idx_age ON users (age);

-- 唯一索引
CREATE UNIQUE INDEX uk_email ON users (email);

-- 复合索引
CREATE INDEX idx_city_age ON users (city, age);

-- 降序
CREATE INDEX idx_age_desc ON users (age DESC);

-- 2005+: 包含列（非键列，存在叶子节点，覆盖查询用）
CREATE INDEX idx_username ON users (username) INCLUDE (email, age);

-- 2008+: 过滤索引（类似 PG 的部分索引）
CREATE INDEX idx_active ON users (username) WHERE status = 1;

-- 2012+: 列存储索引（OLAP 场景，列式存储）
CREATE COLUMNSTORE INDEX idx_cs ON orders (order_date, amount, quantity);
-- 2014+: 聚集列存储（2016+ 可同时有非聚集行存储索引）
CREATE CLUSTERED COLUMNSTORE INDEX idx_cci ON orders;

-- 在线创建（Enterprise 版）
CREATE INDEX idx_age ON users (age) WITH (ONLINE = ON);

-- 填充因子（控制页面填充比例）
CREATE INDEX idx_age ON users (age) WITH (FILLFACTOR = 80);

-- 2019+: 可恢复索引创建（2017+ 仅支持可恢复索引重建）
CREATE INDEX idx_age ON users (age) WITH (ONLINE = ON, RESUMABLE = ON);

-- 删除索引
DROP INDEX idx_age ON users;
-- 2016+:
DROP INDEX IF EXISTS idx_age ON users;

-- 重建索引
ALTER INDEX idx_age ON users REBUILD;
ALTER INDEX idx_age ON users REBUILD WITH (ONLINE = ON);
ALTER INDEX ALL ON users REBUILD;  -- 重建表上所有索引

-- 禁用 / 启用
ALTER INDEX idx_age ON users DISABLE;
ALTER INDEX idx_age ON users REBUILD;  -- 重新启用需要 REBUILD

-- 查看索引
EXEC sp_helpindex 'users';
SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID('users');
