# TDSQL: 复合/复杂类型 (Array, Map, Struct)

TDSQL uses MySQL-compatible JSON type as the primary complex data structure.

> 参考资料:
> - [TDSQL 文档 - JSON 类型](https://cloud.tencent.com/document/product/557)
> - [MySQL 8.0 Reference Manual - JSON Functions](https://dev.mysql.com/doc/refman/8.0/en/json-functions.html)
> - ============================================================
> - 1. 概述: TDSQL 没有原生 ARRAY / MAP / STRUCT 类型
> - ============================================================
> - TDSQL 兼容 MySQL，使用 JSON 类型替代原生的复合类型:
> - 数组需求 → JSON 数组: ["a", "b", "c"]
> - 映射需求 → JSON 对象: {"key1": "val1", "key2": "val2"}
> - 结构体需求 → JSON 对象: {"name": "alice", "age": 25}
> - 与 PostgreSQL / KingbaseES / openGauss 的对比:
> - PostgreSQL: 原生 ARRAY、COMPOSITE、hstore、JSONB
> - TDSQL:      仅 JSON（MySQL 兼容）
> - ClickHouse: 原生 Array、Map、Tuple、Nested
> - BigQuery:   原生 ARRAY、STRUCT
> - ============================================================
> - 2. JSON 数组（替代 ARRAY）
> - ============================================================

```sql
CREATE TABLE users (
    id       BIGINT AUTO_INCREMENT PRIMARY KEY,
    name     VARCHAR(100) NOT NULL,
    tags     JSON,                              -- 替代 ARRAY<VARCHAR>
    scores   JSON                               -- 替代 ARRAY<INT>
);
```

## 插入数组

```sql
INSERT INTO users (name, tags) VALUES
    ('Alice', JSON_ARRAY('admin', 'dev')),
    ('Bob',   '["user", "tester"]'),
    ('Charlie', CAST('["vip", "premium"]' AS JSON));
```

## 数组读取

```sql
SELECT JSON_EXTRACT(tags, '$[0]') FROM users;         -- 第一个元素
SELECT tags->'$[0]' FROM users;                       -- 简写
SELECT tags->'$[1]' FROM users;                       -- 第二个元素
SELECT tags->'$[*]' FROM users;                       -- 所有元素
```

## 数组长度

```sql
SELECT JSON_LENGTH(tags) FROM users;                   -- 元素个数
```

## 数组包含检查

```sql
SELECT * FROM users WHERE JSON_CONTAINS(tags, '"admin"');
SELECT * FROM users WHERE JSON_CONTAINS(tags, '"admin"', '$');
```

## 数组追加元素

```sql
UPDATE users SET tags = JSON_ARRAY_APPEND(tags, '$', 'new_tag') WHERE id = 1;
```

## 数组插入元素

```sql
UPDATE users SET tags = JSON_ARRAY_INSERT(tags, '$[0]', 'first_tag') WHERE id = 1;
```

## JSON 对象（替代 MAP / STRUCT）


```sql
CREATE TABLE products (
    id       BIGINT AUTO_INCREMENT PRIMARY KEY,
    name     VARCHAR(100) NOT NULL,
    metadata JSON,                              -- 替代 MAP<VARCHAR, VARCHAR>
    spec     JSON                               -- 替代 STRUCT
);
```

## 插入对象

```sql
UPDATE products SET metadata = JSON_OBJECT('color', 'red', 'size', 'L') WHERE id = 1;
```

## 对象读取

```sql
SELECT JSON_VALUE(metadata, '$.color') FROM products;
SELECT metadata->>'$.color' FROM products;             -- TEXT 值
SELECT JSON_EXTRACT(metadata, '$.color') FROM products; -- JSON 值
```

## 获取所有键

```sql
SELECT JSON_KEYS(metadata) FROM products;               -- ['color', 'size']
```

## 检查键是否存在

```sql
SELECT * FROM products WHERE JSON_CONTAINS_PATH(metadata, 'one', '$.color');
```

## 添加/更新键

```sql
UPDATE products SET metadata = JSON_SET(metadata, '$.weight', '500g') WHERE id = 1;
UPDATE products SET metadata = JSON_SET(metadata, '$.material', 'cotton') WHERE id = 1;
```

## 删除键

```sql
UPDATE products SET metadata = JSON_REMOVE(metadata, '$.size') WHERE id = 1;
```

## JSON 嵌套结构（替代复杂 STRUCT）


## 嵌套对象和数组组合

```sql
CREATE TABLE orders (
    id         BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id    BIGINT NOT NULL,
    items      JSON,                             -- 数组，每个元素是对象
    shipping   JSON,                             -- 嵌套对象
    PRIMARY KEY (id),
    SHARDKEY (user_id)
);
```

## 插入嵌套 JSON

```sql
INSERT INTO orders (user_id, items, shipping) VALUES (
    1001,
    '[{"product": "iPhone", "qty": 1, "price": 999.99}, {"product": "AirPods", "qty": 2, "price": 199.99}]',
    '{"address": {"city": "Beijing", "zip": "100000"}, "method": "express"}'
);
```

## 读取嵌套数据

```sql
SELECT items->'$[0].product' FROM orders;               -- "iPhone"
SELECT items->>'$[0].product' FROM orders;              -- iPhone
SELECT shipping->>'$.address.city' FROM orders;          -- Beijing
```

## JSON_TABLE: 将 JSON 展开为关系表


## 将 JSON 数组展开为行（最常用的"数组→表"转换）

```sql
SELECT jt.*
FROM orders o,
JSON_TABLE(o.items, '$[*]' COLUMNS (
    product VARCHAR(64) PATH '$.product',
    qty     INT         PATH '$.qty',
    price   DECIMAL(10,2) PATH '$.price'
)) jt;
```

## 带嵌套列的 JSON_TABLE

```sql
SELECT jt.*
FROM orders o,
JSON_TABLE(o.shipping, '$' COLUMNS (
    method  VARCHAR(32) PATH '$.method',
    NESTED PATH '$.address' COLUMNS (
        city VARCHAR(64) PATH '$.city',
        zip  VARCHAR(10) PATH '$.zip'
    )
)) jt;
```

## JSON 聚合（行→数组/对象）


## 将多行聚合成 JSON 数组

```sql
SELECT JSON_ARRAYAGG(name) FROM users;                   -- ["Alice", "Bob", "Charlie"]
```

## 将多行聚合成 JSON 对象

```sql
SELECT JSON_OBJECTAGG(name, id) FROM users;              -- {"Alice": 1, "Bob": 2}
```

## 分组聚合

```sql
SELECT department, JSON_ARRAYAGG(name) AS members
FROM employees
GROUP BY department;
```

## 分布式环境下的注意事项


7.1 JSON 列与 shardkey
JSON 列不能作为 shardkey（数据大小不确定）
如果需要按 JSON 内字段分片，提取为独立列

```sql
CREATE TABLE orders_v2 (
    id        BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id   BIGINT NOT NULL,               -- 作为 shardkey
    items     JSON,
    metadata  JSON,
    SHARDKEY (user_id)
);
```

7.2 跨分片 JSON 操作
JSON 函数在各分片独立执行，结果由代理层合并
JSON_ARRAYAGG / JSON_OBJECTAGG 跨分片聚合由代理层合并
JSON_TABLE 展开在各分片独立完成
7.3 性能建议
JSON 文档控制在合理大小（建议 < 10KB）
高频查询的 JSON 字段提取为虚拟列并建索引
大 JSON 文档的跨分片传输开销显著

## 与其他数据库的复合类型对比


TDSQL (JSON):             无原生类型，JSON 替代，功能完整但性能一般
PostgreSQL (ARRAY):       原生数组，支持 @> / ANY / UNNEST / GIN 索引
PostgreSQL (COMPOSITE):   原生复合类型，CREATE TYPE ... AS (...)
PostgreSQL (hstore):      键值对扩展，比 JSON 更轻量
ClickHouse (Array):       原生数组，高效向量化操作
ClickHouse (Map/Tuple):   原生映射和元组
BigQuery (ARRAY/STRUCT):  原生数组+结构体，嵌套查询支持好

## 注意事项与最佳实践


## TDSQL 没有原生 ARRAY/MAP/STRUCT，使用 JSON 类型替代

## JSON 数组替代 ARRAY: 使用 JSON_ARRAY / JSON_ARRAY_APPEND

## JSON 对象替代 MAP/STRUCT: 使用 JSON_OBJECT / JSON_SET

## JSON_TABLE 是最强大的工具: JSON 数组→关系表的桥梁

## JSON 聚合函数 (JSON_ARRAYAGG/JSON_OBJECTAGG) 实现行→JSON 转换

## JSON 列不能作为 shardkey

## 高频 JSON 字段建议提取为虚拟列并建索引

## 参见 mysql.sql 获取完整的 MySQL JSON 函数列表
