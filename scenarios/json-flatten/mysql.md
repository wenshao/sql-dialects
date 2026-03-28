# MySQL: JSON 展平

> 参考资料:
> - [MySQL 8.0 Reference Manual - JSON Functions](https://dev.mysql.com/doc/refman/8.0/en/json-functions.html)
> - [MySQL 8.0 Reference Manual - JSON_TABLE](https://dev.mysql.com/doc/refman/8.0/en/json-table-functions.html)
> - [MySQL 8.0 Reference Manual - JSON Path Syntax](https://dev.mysql.com/doc/refman/8.0/en/json-path-syntax.html)

## 示例数据

```sql
CREATE TABLE orders_json (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    data JSON NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
```

## 提取 JSON 字段为列

```sql
SELECT id,
       JSON_UNQUOTE(JSON_EXTRACT(data, '$.customer'))  AS customer,
       JSON_EXTRACT(data, '$.total')                    AS total,
       data->>'$.address.city'                          AS city,    -- MySQL 5.7.13+
       data->>'$.address.zip'                           AS zip
FROM   orders_json;
```

## JSON_TABLE 展开数组为多行（推荐, MySQL 8.0.4+）

```sql
SELECT o.id,
       o.data->>'$.customer' AS customer,
       j.*
FROM   orders_json o,
       JSON_TABLE(
           o.data, '$.items[*]'
           COLUMNS (
               rownum  FOR ORDINALITY,
               product VARCHAR(100) PATH '$.product',
               qty     INT          PATH '$.qty',
               price   DECIMAL(10,2) PATH '$.price'
           )
       ) AS j;
```

## 嵌套 JSON_TABLE（嵌套展平）

```sql
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(
           o.data, '$'
           COLUMNS (
               customer VARCHAR(100) PATH '$.customer',
               city     VARCHAR(100) PATH '$.address.city',
               zip      VARCHAR(20)  PATH '$.address.zip',
               NESTED PATH '$.items[*]' COLUMNS (
                   product VARCHAR(100) PATH '$.product',
                   qty     INT          PATH '$.qty',
                   price   DECIMAL(10,2) PATH '$.price'
               )
           )
       ) AS j;
```

## JSON_KEYS + 递归遍历键

```sql
SELECT o.id, jk.key_name
FROM   orders_json o,
       JSON_TABLE(
           JSON_KEYS(o.data), '$[*]'
           COLUMNS (key_name VARCHAR(100) PATH '$')
       ) AS jk;
```

## JSON_ARRAYAGG / JSON_OBJECTAGG（反向：行转 JSON）

```sql
SELECT JSON_ARRAYAGG(JSON_OBJECT('id', id, 'customer', data->>'$.customer'))
```

FROM orders_json;
