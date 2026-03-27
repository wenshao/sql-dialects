-- 人大金仓 (KingbaseES): JSON 展平为关系行 (JSON Flatten)
--
-- 参考资料:
--   [1] KingbaseES SQL 语言参考手册
--       https://help.kingbase.com.cn/
--   [2] KingbaseES 兼容 PostgreSQL JSON/JSONB 类型
--       https://help.kingbase.com.cn/document/index.html
--   [3] KingbaseES JSON 函数参考
--       https://help.kingbase.com.cn/

-- ============================================================
-- 1. 示例数据
-- ============================================================

CREATE TABLE orders_json (
    id   SERIAL PRIMARY KEY,
    data JSONB NOT NULL
);

INSERT INTO orders_json (data) VALUES
    ('{"customer": "Alice", "total": 150.00, "items": [
        {"product": "Widget", "qty": 2, "price": 25.00},
        {"product": "Gadget", "qty": 1, "price": 100.00}
      ],
      "address": {"city": "Beijing", "zip": "100000"}
    }'),
    ('{"customer": "Bob", "total": 80.00, "items": [
        {"product": "Widget", "qty": 3, "price": 25.00},
        {"product": "Doohickey", "qty": 1, "price": 5.00}
      ],
      "address": {"city": "Shanghai", "zip": "200000"}
    }');

-- ============================================================
-- 2. 提取 JSON 字段为列
-- ============================================================

SELECT id,
       data->>'customer'                        AS customer,
       (data->>'total')::NUMERIC                 AS total,
       data->'address'->>'city'                  AS city,
       data->'address'->>'zip'                   AS zip
FROM   orders_json;

-- KingbaseES 完全兼容 PostgreSQL 的 JSONB 运算符
--   ->> : 提取 JSON 值为文本
--   ->  : 提取 JSON 值为 JSON 类型（用于链式访问嵌套对象）

-- ============================================================
-- 3. jsonb_array_elements 展开嵌套数组
-- ============================================================

SELECT o.id,
       o.data->>'customer'            AS customer,
       item->>'product'               AS product,
       (item->>'qty')::INT            AS qty,
       (item->>'price')::NUMERIC      AS price
FROM   orders_json o,
       LATERAL jsonb_array_elements(o.data->'items') AS item;

-- 设计分析: LATERAL + jsonb_array_elements
--   jsonb_array_elements 返回 JSONB 类型的集合（Set-Returning Function）
--   LATERAL 允许子查询引用外表的列
--   组合实现 JSON 数组 → 关系行的展开

-- ============================================================
-- 4. jsonb_to_recordset: 直接转为关系记录
-- ============================================================

SELECT o.id, o.data->>'customer' AS customer, r.*
FROM   orders_json o,
       LATERAL jsonb_to_recordset(o.data->'items')
              AS r(product TEXT, qty INT, price NUMERIC);

-- jsonb_to_recordset 比 jsonb_array_elements 更简洁:
--   一步定义列名和类型，无需逐字段 ->> 提取
--   适合 JSON 数组中对象结构一致的场景

-- ============================================================
-- 5. jsonb_each 展开对象键值对
-- ============================================================

SELECT o.id, kv.key, kv.value
FROM   orders_json o,
       LATERAL jsonb_each(o.data->'address') AS kv;

-- jsonb_each 将 JSON 对象展开为 (key, value) 行
-- jsonb_each_text 返回文本类型的 value（而非 JSONB）

-- ============================================================
-- 6. JSON Path 查询（KingbaseES V8R6+）
-- ============================================================

SELECT o.id,
       jsonb_path_query_first(o.data, '$.customer')  AS customer,
       item.*
FROM   orders_json o,
       LATERAL jsonb_path_query(o.data, '$.items[*]') AS raw_item,
       LATERAL jsonb_to_record(raw_item) AS item(product TEXT, qty INT, price NUMERIC);

-- JSON Path 是 SQL/JSON 标准的一部分
-- KingbaseES V8R6 起支持 jsonb_path_query 系列函数

-- ============================================================
-- 7. 过滤条件中使用 JSON 字段
-- ============================================================

SELECT id, data->>'customer' AS customer, (data->>'total')::NUMERIC AS total
FROM   orders_json
WHERE  (data->>'total')::NUMERIC > 100
  AND  data->'address'->>'city' = 'Beijing';

-- JSON 字段可以直接用于 WHERE 条件
-- 建议对高频查询字段创建 GIN 索引以提升性能:
-- CREATE INDEX idx_orders_data ON orders_json USING GIN (data);

-- ============================================================
-- 8. 横向对比与对引擎开发者的启示
-- ============================================================

-- 1. KingbaseES JSON 能力:
--   基于 PostgreSQL 内核，JSON/JSONB 功能完整
--   兼容 SQL/JSON 标准路径表达式
--   支持 GIN 索引加速 JSON 查询
--
-- 2. 与 PostgreSQL 的关系:
--   语法和函数 100% 兼容
--   性能特征相同（JSONB 二进制存储）
--   版本特性跟随 PostgreSQL 版本
--
-- 对引擎开发者:
--   兼容 PostgreSQL 的 JSON 生态意味着用户可以直接复用社区知识
--   国产数据库兼容 PostgreSQL 是降低迁移成本的常见策略
--   GIN 索引对 JSON 查询性能至关重要
