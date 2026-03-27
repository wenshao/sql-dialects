-- MySQL: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] MySQL 8.0 Reference Manual - JSON Data Type
--       https://dev.mysql.com/doc/refman/8.0/en/json.html
--   [2] MySQL 8.0 Reference Manual - JSON Functions
--       https://dev.mysql.com/doc/refman/8.0/en/json-functions.html
--   [3] MySQL 8.0 Reference Manual - Multi-Valued Indexes
--       https://dev.mysql.com/doc/refman/8.0/en/create-index.html#create-index-multi-valued

-- ============================================================
-- MySQL 没有原生的 ARRAY / MAP / STRUCT 类型
-- 使用 JSON 类型作为替代（MySQL 5.7.8+）
-- ============================================================

CREATE TABLE users (
    id       BIGINT AUTO_INCREMENT PRIMARY KEY,
    name     VARCHAR(100) NOT NULL,
    tags     JSON,                           -- 用 JSON 数组代替 ARRAY
    metadata JSON,                           -- 用 JSON 对象代替 MAP/STRUCT
    scores   JSON                            -- 数值数组
) ENGINE=InnoDB;

-- ============================================================
-- JSON 数组（代替 ARRAY）
-- ============================================================

-- 插入 JSON 数组
INSERT INTO users (name, tags, scores) VALUES
    ('Alice', JSON_ARRAY('admin', 'dev'), JSON_ARRAY(90, 85, 95)),
    ('Bob',   '["user", "tester"]', '[70, 80, 75]'),
    ('Carol', '["dev"]', '[88]');

-- 数组索引（JSON 下标从 0 开始）
SELECT JSON_EXTRACT(tags, '$[0]') FROM users;        -- 第一个元素
SELECT tags->'$[0]' FROM users;                      -- 简写语法
SELECT tags->>'$[0]' FROM users;                     -- 去引号 (MySQL 8.0.21+)

-- 数组长度
SELECT JSON_LENGTH(tags) FROM users;

-- 数组包含检查
SELECT * FROM users
WHERE JSON_CONTAINS(tags, '"admin"');

-- 数组搜索
SELECT * FROM users
WHERE JSON_SEARCH(tags, 'one', 'admin') IS NOT NULL;

-- JSON_ARRAY_APPEND: 追加元素
SELECT JSON_ARRAY_APPEND(tags, '$', 'new_tag') FROM users;

-- JSON_ARRAY_INSERT: 指定位置插入
SELECT JSON_ARRAY_INSERT(tags, '$[1]', 'inserted') FROM users;

-- MEMBER OF（MySQL 8.0.17+）
SELECT * FROM users WHERE 'admin' MEMBER OF(tags);

-- ============================================================
-- JSON 对象（代替 MAP / STRUCT）
-- ============================================================

-- 插入 JSON 对象
UPDATE users SET metadata = JSON_OBJECT(
    'city', 'New York',
    'country', 'US',
    'settings', JSON_OBJECT('theme', 'dark', 'lang', 'en')
) WHERE id = 1;

-- 字面量语法
UPDATE users SET metadata = '{"city": "Boston", "country": "US"}'
WHERE id = 2;

-- 访问字段
SELECT JSON_EXTRACT(metadata, '$.city') FROM users;
SELECT metadata->'$.city' FROM users;
SELECT metadata->>'$.city' FROM users;               -- 去引号

-- 嵌套访问
SELECT metadata->'$.settings.theme' FROM users;

-- JSON_KEYS: 获取所有键（类似 MAP_KEYS）
SELECT JSON_KEYS(metadata) FROM users;

-- JSON_SET / JSON_INSERT / JSON_REPLACE / JSON_REMOVE
SELECT JSON_SET(metadata, '$.zip', '10001') FROM users;
SELECT JSON_REMOVE(metadata, '$.city') FROM users;

-- ============================================================
-- UNNEST 替代: JSON_TABLE（MySQL 8.0+）
-- ============================================================

-- 将 JSON 数组展开为行
SELECT u.name, jt.tag
FROM users u,
JSON_TABLE(u.tags, '$[*]' COLUMNS (
    tag VARCHAR(50) PATH '$'
)) AS jt;

-- 展开嵌套 JSON
SELECT *
FROM JSON_TABLE(
    '[{"name":"Alice","scores":[90,85]},{"name":"Bob","scores":[70,80]}]',
    '$[*]' COLUMNS (
        name VARCHAR(50) PATH '$.name',
        NESTED PATH '$.scores[*]' COLUMNS (
            score INT PATH '$'
        )
    )
) AS jt;

-- ============================================================
-- JSON_ARRAYAGG / JSON_OBJECTAGG（代替 ARRAY_AGG）
-- ============================================================

-- 聚合为 JSON 数组
SELECT department, JSON_ARRAYAGG(name) AS members
FROM employees
GROUP BY department;

-- 聚合为 JSON 对象
SELECT JSON_OBJECTAGG(name, salary) AS salary_map
FROM employees;

-- ============================================================
-- 嵌套 JSON 结构
-- ============================================================

INSERT INTO users (name, metadata) VALUES ('Dan', '{
    "addresses": [
        {"type": "home", "city": "NYC", "zip": "10001"},
        {"type": "work", "city": "Boston", "zip": "02101"}
    ],
    "preferences": {
        "notifications": {"email": true, "sms": false},
        "tags": ["vip", "premium"]
    }
}');

-- 深层嵌套访问
SELECT metadata->>'$.addresses[0].city' FROM users WHERE name = 'Dan';
SELECT metadata->'$.preferences.notifications.email' FROM users WHERE name = 'Dan';
SELECT metadata->'$.preferences.tags[0]' FROM users WHERE name = 'Dan';

-- ============================================================
-- 多值索引 (Multi-Valued Index, MySQL 8.0.17+)
-- ============================================================

-- 在 JSON 数组上创建索引
CREATE TABLE products (
    id    BIGINT AUTO_INCREMENT PRIMARY KEY,
    name  VARCHAR(100),
    tags  JSON
);

ALTER TABLE products ADD INDEX idx_tags ((CAST(tags AS CHAR(50) ARRAY)));

-- 使用多值索引的查询
SELECT * FROM products WHERE 'electronics' MEMBER OF(tags);
SELECT * FROM products WHERE JSON_CONTAINS(tags, '"electronics"');
SELECT * FROM products WHERE JSON_OVERLAPS(tags, '["electronics","books"]');

-- ============================================================
-- JSON Schema 验证（MySQL 8.0.17+）
-- ============================================================

ALTER TABLE users ADD CONSTRAINT chk_tags
CHECK (JSON_SCHEMA_VALID('{
    "type": "array",
    "items": {"type": "string"}
}', tags));

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. MySQL 没有原生 ARRAY / MAP / STRUCT 类型
-- 2. 使用 JSON 类型替代，功能完整
-- 3. JSON 列最大 1GB
-- 4. JSON 数组下标从 0 开始
-- 5. 多值索引 (8.0.17+) 支持高效的数组查询
-- 6. JSON_TABLE (8.0+) 提供 UNNEST 功能
-- 7. 存储为二进制格式，读取效率高
