# DB2: JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [IBM DB2 Documentation - JSON Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-json-value)
> - [IBM DB2 Documentation - JSON_TABLE](https://www.ibm.com/docs/en/db2/11.5?topic=functions-json-table)


## 示例数据

```sql
CREATE TABLE orders_json (
    id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    data CLOB NOT NULL
);

INSERT INTO orders_json (data) VALUES
('{"customer": "Alice", "total": 150.00, "items": [{"product": "Widget", "qty": 2, "price": 25.00}, {"product": "Gadget", "qty": 1, "price": 100.00}], "address": {"city": "Beijing", "zip": "100000"}}');
INSERT INTO orders_json (data) VALUES
('{"customer": "Bob", "total": 80.00, "items": [{"product": "Widget", "qty": 3, "price": 25.00}, {"product": "Doohickey", "qty": 1, "price": 5.00}], "address": {"city": "Shanghai", "zip": "200000"}}');
```

## JSON_VALUE 提取字段（DB2 11.1+）

```sql
SELECT id,
       JSON_VALUE(data, '$.customer')          AS customer,
       JSON_VALUE(data, '$.total' RETURNING DECIMAL(10,2)) AS total,
       JSON_VALUE(data, '$.address.city')      AS city
FROM   orders_json;
```

## JSON_TABLE 展开数组（DB2 11.1+）

```sql
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(o.data, '$.items[*]'
           COLUMNS (
               product VARCHAR(100) PATH '$.product',
               qty     INTEGER      PATH '$.qty',
               price   DECIMAL(10,2) PATH '$.price'
           )
       ) AS j;
```

## 嵌套 JSON_TABLE

```sql
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(o.data, '$'
           COLUMNS (
               customer VARCHAR(100) PATH '$.customer',
               NESTED PATH '$.items[*]' COLUMNS (
                   product VARCHAR(100) PATH '$.product',
                   qty     INTEGER      PATH '$.qty',
                   price   DECIMAL(10,2) PATH '$.price'
               )
           )
       ) AS j;
```

## SYSTOOLS.BSON2JSON / JSON2BSON（旧版 DB2 的 NoSQL 兼容层）

## 早期版本使用 SYSTOOLS schema 下的 JSON 函数
