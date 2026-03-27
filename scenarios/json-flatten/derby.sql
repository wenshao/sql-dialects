-- Derby: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Apache Derby 不原生支持 JSON
--       https://db.apache.org/derby/docs/10.16/ref/

-- ============================================================
-- 注意: Apache Derby 没有 JSON 数据类型和函数
-- ============================================================
-- 建议方案:
-- 1. 在应用层（Java）解析 JSON
-- 2. 使用 Derby 自定义函数（Java UDF）
-- 3. 将 JSON 数据预处理为关系表后存入 Derby

-- ============================================================
-- 方案 1: 创建 Java UDF 来解析 JSON
-- ============================================================
-- 提取单个值
-- CREATE FUNCTION json_value(json_str VARCHAR(10000), path VARCHAR(200))
--     RETURNS VARCHAR(1000)
--     LANGUAGE JAVA
--     EXTERNAL NAME 'com.example.JsonUDF.extractValue'
--     PARAMETER STYLE JAVA
--     NO SQL;

-- 提取数组长度
-- CREATE FUNCTION json_array_length(json_str VARCHAR(10000), path VARCHAR(200))
--     RETURNS INTEGER
--     LANGUAGE JAVA
--     EXTERNAL NAME 'com.example.JsonUDF.arrayLength'
--     PARAMETER STYLE JAVA
--     NO SQL;

-- 使用 UDF 查询 JSON:
-- SELECT json_value(data, '$.customer') AS customer,
--        json_value(data, '$.address.city') AS city
-- FROM orders_json;

-- ============================================================
-- 方案 2: 预处理为关系表
-- ============================================================
-- 将 JSON 数据拆分为规范化的关系表存储
CREATE TABLE orders (
    id          INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY,
    customer    VARCHAR(100),
    total       DECIMAL(10,2),
    city        VARCHAR(100),
    zip         VARCHAR(20),
    PRIMARY KEY (id)
);

CREATE TABLE order_items (
    id          INTEGER NOT NULL GENERATED ALWAYS AS IDENTITY,
    order_id    INTEGER NOT NULL,
    product     VARCHAR(200),
    qty         INTEGER,
    price       DECIMAL(10,2),
    PRIMARY KEY (id),
    FOREIGN KEY (order_id) REFERENCES orders(id)
);

-- 查询展平后的数据（标准关系查询）
SELECT o.id, o.customer, oi.product, oi.qty, oi.price, o.city
FROM   orders o
JOIN   order_items oi ON o.id = oi.order_id;

-- 注意：Derby 是纯 Java 嵌入式数据库，不支持 JSON
-- 注意：Java UDF 可使用 Jackson / Gson 库解析 JSON
-- 注意：预处理为关系表是最简单且性能最好的方案
-- 限制：无 JSON 数据类型
-- 限制：无 JSON 函数（JSON_VALUE, JSON_TABLE 等）
-- 限制：无 LATERAL / UNNEST
