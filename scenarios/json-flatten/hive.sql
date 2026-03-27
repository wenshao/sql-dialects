-- Hive: JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] Hive Language Manual - LATERAL VIEW + json_tuple
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-json_tuple
--   [2] Hive Language Manual - get_json_object
--       https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF

-- ============================================================
-- 示例数据
-- ============================================================
CREATE TABLE orders_json (
    id   INT,
    data STRING
) STORED AS TEXTFILE;

-- ============================================================
-- 1. get_json_object 提取字段
-- ============================================================
SELECT id,
       get_json_object(data, '$.customer')      AS customer,
       get_json_object(data, '$.total')         AS total,
       get_json_object(data, '$.address.city')  AS city
FROM   orders_json;

-- ============================================================
-- 2. LATERAL VIEW json_tuple（推荐，一次提取多个字段）
-- ============================================================
SELECT o.id, j.customer, j.total
FROM   orders_json o
LATERAL VIEW json_tuple(o.data, 'customer', 'total') j
         AS customer, total;

-- ============================================================
-- 3. explode + get_json_object 展开数组
-- ============================================================
-- 先把 JSON 数组字符串转为 Hive Array
SELECT o.id,
       get_json_object(o.data, '$.customer')      AS customer,
       get_json_object(item, '$.product')          AS product,
       get_json_object(item, '$.qty')              AS qty,
       get_json_object(item, '$.price')            AS price
FROM   orders_json o
LATERAL VIEW explode(
    split(
        regexp_replace(
            regexp_replace(
                get_json_object(o.data, '$.items'),
                '^\\[|\\]$', ''
            ),
            '\\},\\s*\\{', '},,{'
        ),
        ',,'
    )
) exploded AS item;

-- ============================================================
-- 4. JsonSerDe 建表（推荐用于 JSON 格式数据）
-- ============================================================
CREATE TABLE orders_serde (
    customer STRING,
    total    DOUBLE,
    items    ARRAY<STRUCT<product:STRING, qty:INT, price:DOUBLE>>,
    address  STRUCT<city:STRING, zip:STRING>
) ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
STORED AS TEXTFILE;

-- 直接用 LATERAL VIEW explode 展开
SELECT o.customer, o.address.city, item.product, item.qty, item.price
FROM   orders_serde o
LATERAL VIEW explode(o.items) exploded AS item;
