-- Derby: 索引
--
-- 参考资料:
--   [1] Derby SQL Reference
--       https://db.apache.org/derby/docs/10.16/ref/
--   [2] Derby Developer Guide
--       https://db.apache.org/derby/docs/10.16/devguide/

-- B-tree 索引（唯一支持的类型）
CREATE INDEX idx_username ON users (username);

-- 唯一索引
CREATE UNIQUE INDEX idx_email ON users (email);

-- 复合索引
CREATE INDEX idx_city_age ON users (city, age);

-- 降序索引
CREATE INDEX idx_created_desc ON users (created_at DESC);

-- 混合排序索引
CREATE INDEX idx_mixed ON orders (user_id ASC, order_date DESC);

-- ============================================================
-- 主键和约束索引（自动创建）
-- ============================================================

-- PRIMARY KEY 自动创建唯一索引
CREATE TABLE users (
    id       INT NOT NULL GENERATED ALWAYS AS IDENTITY,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(128) NOT NULL,
    PRIMARY KEY (id),                  -- 自动创建唯一索引
    UNIQUE (email)                     -- 自动创建唯一索引
);

-- ============================================================
-- 索引管理
-- ============================================================

-- 删除索引
DROP INDEX idx_username;

-- 查看索引
SELECT * FROM SYS.SYSCONGLOMERATES
WHERE TABLEID = (SELECT TABLEID FROM SYS.SYSTABLES WHERE TABLENAME = 'USERS');

-- 通过系统表查看索引详情
SELECT
    c.CONGLOMERATENAME AS index_name,
    t.TABLENAME AS table_name,
    c.ISINDEX
FROM SYS.SYSCONGLOMERATES c
JOIN SYS.SYSTABLES t ON c.TABLEID = t.TABLEID
WHERE c.ISINDEX = TRUE;

-- ============================================================
-- 索引使用和优化
-- ============================================================

-- 查看查询计划（确认索引是否使用）
-- 在 ij 工具中
-- CALL SYSCS_UTIL.SYSCS_SET_RUNTIMESTATISTICS(1);
-- CALL SYSCS_UTIL.SYSCS_SET_STATISTICS_TIMING(1);
-- 执行查询后
-- VALUES SYSCS_UTIL.SYSCS_GET_RUNTIMESTATISTICS();

-- 更新统计信息（帮助优化器选择索引）
CALL SYSCS_UTIL.SYSCS_UPDATE_STATISTICS('APP', 'USERS', NULL);

-- 压缩表（重建索引）
CALL SYSCS_UTIL.SYSCS_COMPRESS_TABLE('APP', 'USERS', 0);

-- 注意：Derby 只支持 B-tree 索引
-- 注意：不支持 Hash 索引、全文索引、空间索引
-- 注意：不支持 IF NOT EXISTS / IF EXISTS
-- 注意：不支持函数索引/表达式索引
-- 注意：不支持部分索引（WHERE 子句）
-- 注意：索引名在 schema 内唯一
