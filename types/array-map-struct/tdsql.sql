-- TDSQL: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] TDSQL 文档 - JSON 类型
--       https://cloud.tencent.com/document/product/557

-- ============================================================
-- TDSQL 兼容 MySQL，使用 JSON 类型作为复杂类型替代
-- ============================================================

CREATE TABLE users (
    id       BIGINT AUTO_INCREMENT PRIMARY KEY,
    name     VARCHAR(100) NOT NULL,
    tags     JSON,
    metadata JSON
);

-- JSON 数组
INSERT INTO users (name, tags) VALUES
    ('Alice', JSON_ARRAY('admin', 'dev')),
    ('Bob',   '["user", "tester"]');

SELECT JSON_EXTRACT(tags, '$[0]') FROM users;
SELECT tags->'$[0]' FROM users;
SELECT JSON_LENGTH(tags) FROM users;
SELECT * FROM users WHERE JSON_CONTAINS(tags, '"admin"');

-- JSON 对象
UPDATE users SET metadata = JSON_OBJECT('city', 'NYC') WHERE id = 1;
SELECT JSON_VALUE(metadata, '$.city') FROM users;
SELECT JSON_KEYS(metadata) FROM users;

-- 聚合
SELECT JSON_ARRAYAGG(name) FROM users;
SELECT JSON_OBJECTAGG(name, 'value') FROM users;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 兼容 MySQL JSON 功能
-- 2. 没有原生 ARRAY / MAP / STRUCT 类型
-- 3. 分布式环境下 JSON 列正常工作
-- 4. 参见 mysql.sql 获取完整的 JSON 函数列表
