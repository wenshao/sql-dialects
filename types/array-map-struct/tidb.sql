-- TiDB: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] TiDB Documentation - JSON Type
--       https://docs.pingcap.com/tidb/stable/data-type-json
--   [2] TiDB Documentation - JSON Functions
--       https://docs.pingcap.com/tidb/stable/json-functions

-- ============================================================
-- TiDB 没有原生 ARRAY / MAP / STRUCT 类型
-- 使用 JSON 类型替代（兼容 MySQL JSON）
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
SELECT tags->>'$[0]' FROM users;
SELECT JSON_LENGTH(tags) FROM users;
SELECT * FROM users WHERE JSON_CONTAINS(tags, '"admin"');
SELECT * FROM users WHERE 'admin' MEMBER OF(tags);           -- TiDB 6.5+

-- JSON 对象
UPDATE users SET metadata = JSON_OBJECT('city', 'NYC', 'settings', JSON_OBJECT('theme', 'dark'))
WHERE id = 1;
SELECT JSON_VALUE(metadata, '$.city') FROM users;            -- TiDB 6.1+
SELECT JSON_KEYS(metadata) FROM users;

-- JSON_TABLE（TiDB 7.1+）
SELECT u.name, jt.tag
FROM users u,
JSON_TABLE(u.tags, '$[*]' COLUMNS (tag VARCHAR(50) PATH '$')) AS jt;

-- 聚合
SELECT department, JSON_ARRAYAGG(name) FROM employees GROUP BY department;
SELECT JSON_OBJECTAGG(name, salary) FROM employees;

-- 多值索引（TiDB 6.6+）
CREATE TABLE products (id BIGINT PRIMARY KEY, tags JSON);
CREATE INDEX idx_tags ON products ((CAST(tags AS CHAR(50) ARRAY)));
SELECT * FROM products WHERE 'electronics' MEMBER OF(tags);

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. 兼容 MySQL JSON 功能
-- 2. 没有原生 ARRAY / MAP / STRUCT 类型
-- 3. JSON_TABLE 从 TiDB 7.1 开始支持
-- 4. 多值索引从 TiDB 6.6 开始支持
-- 5. MEMBER OF 从 TiDB 6.5 开始支持
