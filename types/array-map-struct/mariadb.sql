-- MariaDB: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] MariaDB Knowledge Base - JSON Data Type
--       https://mariadb.com/kb/en/json-data-type/
--   [2] MariaDB Knowledge Base - JSON Functions
--       https://mariadb.com/kb/en/json-functions/
--   [3] MariaDB Knowledge Base - Dynamic Columns
--       https://mariadb.com/kb/en/dynamic-columns/

-- ============================================================
-- MariaDB 没有原生 ARRAY / MAP / STRUCT 类型
-- 使用 JSON 或 Dynamic Columns 作为替代
-- ============================================================

-- ============================================================
-- JSON 类型（MariaDB 10.2+）
-- ============================================================
-- 注意: MariaDB 的 JSON 是 LONGTEXT 的别名，与 MySQL 不同

CREATE TABLE users (
    id       BIGINT AUTO_INCREMENT PRIMARY KEY,
    name     VARCHAR(100) NOT NULL,
    tags     JSON,                             -- LONGTEXT 别名
    metadata JSON
    -- 注意: MariaDB 不支持 JSON CHECK 约束 (10.4.3 之前)
);

-- ============================================================
-- JSON 数组（代替 ARRAY）
-- ============================================================

INSERT INTO users (name, tags) VALUES
    ('Alice', JSON_ARRAY('admin', 'dev')),
    ('Bob',   '["user", "tester"]');

-- 访问元素
SELECT JSON_EXTRACT(tags, '$[0]') FROM users;
SELECT JSON_VALUE(tags, '$[0]') FROM users;    -- 返回标量（MariaDB 10.2.3+）
SELECT JSON_UNQUOTE(JSON_EXTRACT(tags, '$[0]')) FROM users;

-- 数组长度
SELECT JSON_LENGTH(tags) FROM users;

-- 数组包含
SELECT * FROM users WHERE JSON_CONTAINS(tags, '"admin"');
SELECT * FROM users WHERE JSON_SEARCH(tags, 'one', 'admin') IS NOT NULL;

-- JSON_ARRAY_APPEND / JSON_ARRAY_INSERT
SELECT JSON_ARRAY_APPEND(tags, '$', 'new_tag') FROM users;
SELECT JSON_ARRAY_INSERT(tags, '$[1]', 'inserted') FROM users;

-- ============================================================
-- JSON 对象（代替 MAP / STRUCT）
-- ============================================================

UPDATE users SET metadata = JSON_OBJECT(
    'city', 'New York',
    'settings', JSON_OBJECT('theme', 'dark')
) WHERE id = 1;

SELECT JSON_VALUE(metadata, '$.city') FROM users;
SELECT JSON_VALUE(metadata, '$.settings.theme') FROM users;

SELECT JSON_KEYS(metadata) FROM users;
SELECT JSON_SET(metadata, '$.zip', '10001') FROM users;
SELECT JSON_REMOVE(metadata, '$.city') FROM users;

-- ============================================================
-- UNNEST 替代: JSON_TABLE（MariaDB 10.6+）
-- ============================================================

SELECT u.name, jt.tag
FROM users u,
JSON_TABLE(u.tags, '$[*]' COLUMNS (
    tag VARCHAR(50) PATH '$'
)) AS jt;

-- ============================================================
-- 聚合
-- ============================================================

SELECT department, JSON_ARRAYAGG(name) AS members
FROM employees
GROUP BY department;

SELECT JSON_OBJECTAGG(name, salary) FROM employees;

-- ============================================================
-- Dynamic Columns（MariaDB 特有，5.3+）
-- ============================================================

-- Dynamic Columns 使用 BLOB 存储键值对
CREATE TABLE products (
    id    BIGINT PRIMARY KEY,
    name  VARCHAR(100),
    attrs BLOB                                -- Dynamic Columns
);

-- 创建 Dynamic Column
INSERT INTO products VALUES
    (1, 'Laptop', COLUMN_CREATE('brand', 'Dell', 'ram', '16GB'));

-- 访问值
SELECT COLUMN_GET(attrs, 'brand' AS CHAR) FROM products;

-- 检查键存在
SELECT COLUMN_EXISTS(attrs, 'ram') FROM products;

-- 列出所有键
SELECT COLUMN_LIST(attrs) FROM products;

-- 添加/修改
UPDATE products SET attrs = COLUMN_ADD(attrs, 'cpu', 'i7') WHERE id = 1;

-- 删除
UPDATE products SET attrs = COLUMN_DELETE(attrs, 'ram') WHERE id = 1;

-- 转为 JSON
SELECT COLUMN_JSON(attrs) FROM products;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. MariaDB 没有原生 ARRAY / MAP / STRUCT 类型
-- 2. JSON 类型是 LONGTEXT 的别名（非二进制存储，与 MySQL 不同）
-- 3. JSON_TABLE 从 MariaDB 10.6 开始支持
-- 4. Dynamic Columns 是 MariaDB 特有功能（早于 JSON 支持）
-- 5. 不支持 MySQL 的多值索引（Multi-Valued Index）
