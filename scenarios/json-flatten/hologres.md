# Hologres: JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [Hologres 兼容 PostgreSQL JSON 函数](https://help.aliyun.com/document_detail/416498.html)


## 与 PostgreSQL 语法相同


## 示例数据

```sql
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
}');
```

## 提取 JSON 字段为列

```sql
SELECT id,
       data->>'customer'          AS customer,
       (data->>'total')::NUMERIC  AS total,
       data->'address'->>'city'   AS city,
       data->'address'->>'zip'    AS zip
FROM   orders_json;
```

## 展开 JSON 数组为多行 (jsonb_array_elements)

```sql
SELECT o.id,
       o.data->>'customer'              AS customer,
       item->>'product'                  AS product,
       (item->>'qty')::INT               AS qty,
       (item->>'price')::NUMERIC         AS price
FROM   orders_json o,
       LATERAL jsonb_array_elements(o.data->'items') AS item;
```

## 展开 JSON 对象键值对 (jsonb_each)

```sql
SELECT o.id, kv.key, kv.value
FROM   orders_json o,
       LATERAL jsonb_each(o.data->'address') AS kv;
```

## jsonb_to_recordset（转为关系记录）

```sql
SELECT o.id, o.data->>'customer' AS customer, r.*
FROM   orders_json o,
       LATERAL jsonb_to_recordset(o.data->'items')
              AS r(product TEXT, qty INT, price NUMERIC);
```

注意：Hologres 兼容 PostgreSQL JSON/JSONB 函数
注意：LATERAL 关键字用于关联子查询中引用外部表
注意：Hologres 面向实时分析，适合 JSON 展平后的聚合查询
限制：某些高级 JSON 路径查询（jsonb_path_query）可能不支持
