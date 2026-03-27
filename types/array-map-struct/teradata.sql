-- Teradata: 复合/复杂类型 (Array, Map, Struct)
--
-- 参考资料:
--   [1] Teradata Documentation - ARRAY/VARRAY Data Type
--       https://docs.teradata.com/r/Teradata-Database-SQL-Data-Types-and-Literals/ARRAY-VARRAY-Data-Types
--   [2] Teradata Documentation - DATASET Data Type
--       https://docs.teradata.com/r/Teradata-Database-SQL-Data-Types-and-Literals/DATASET-Data-Type
--   [3] Teradata Documentation - JSON Data Type
--       https://docs.teradata.com/r/Teradata-Database-JSON-User-Guide

-- ============================================================
-- ARRAY / VARRAY 类型
-- ============================================================

-- 创建 ARRAY 类型
CREATE TYPE tag_array AS VARCHAR(50) ARRAY[20];

CREATE TABLE users (
    id     INTEGER NOT NULL PRIMARY KEY,
    name   VARCHAR(100) NOT NULL,
    tags   VARCHAR(50) ARRAY[20],
    scores INTEGER ARRAY[50]
);

-- 插入（使用 NEW 构造器）
INSERT INTO users VALUES (1, 'Alice',
    NEW tag_array('admin', 'dev'),
    NEW INTEGER ARRAY[50](90, 85, 95));

-- 数组索引（从 1 开始）
SELECT tags[1] FROM users;

-- CARDINALITY: 长度
SELECT CARDINALITY(tags) FROM users;

-- ============================================================
-- DATASET 类型（Teradata 特有的半结构化类型）
-- ============================================================

-- AVRO 或 CSV 格式的内嵌数据
CREATE TABLE events (
    id   INTEGER,
    data DATASET STORAGE FORMAT AVRO
);

-- ============================================================
-- JSON 类型（Teradata 15.10+）
-- ============================================================

CREATE TABLE products (
    id         INTEGER PRIMARY KEY,
    name       VARCHAR(100),
    attributes JSON(1000)
);

INSERT INTO products VALUES (1, 'Laptop',
    '{"brand": "Dell", "specs": {"ram": "16GB"}}');

-- JSON 方法语法（Teradata 特有的点方法）
SELECT attributes.JSONExtractValue('$.brand') FROM products;

-- JSON 函数
SELECT JSONExtract(attributes, '$.brand') FROM products;
SELECT JSONExtractLargeValue(attributes, '$.brand') FROM products;

-- JSON_KEYS / JSON_COMPOSE
-- 使用 Teradata JSON 函数库

-- ============================================================
-- 结构化类型 (Structured UDT)
-- ============================================================

CREATE TYPE address_type AS (
    street VARCHAR(200),
    city   VARCHAR(100),
    state  VARCHAR(50),
    zip    VARCHAR(10)
) NOT FINAL;

-- ============================================================
-- 注意事项
-- ============================================================

-- 1. Teradata 支持 ARRAY/VARRAY 类型
-- 2. 没有原生 MAP 类型
-- 3. DATASET 类型用于半结构化数据
-- 4. JSON 类型从 15.10 版本开始支持
-- 5. 结构化 UDT 提供 STRUCT 功能
-- 6. 数组下标从 1 开始
