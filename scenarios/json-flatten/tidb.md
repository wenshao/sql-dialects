# TiDB: JSON 展开

> 参考资料:
> - [TiDB Documentation - JSON Functions](https://docs.pingcap.com/tidb/stable/json-functions)
> - [TiDB Documentation - JSON_TABLE (TiDB 6.5+)](https://docs.pingcap.com/tidb/stable/json-functions#json_table)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

## 示例数据

```sql
CREATE TABLE orders_json (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    data JSON NOT NULL
);

INSERT INTO orders_json (data) VALUES
('{"customer":"Alice","total":150.0,"items":[{"product":"Widget","qty":2,"price":25.0},{"product":"Gadget","qty":1,"price":100.0}],"address":{"city":"Beijing","zip":"100000"}}'),
('{"customer":"Bob","total":80.0,"items":[{"product":"Widget","qty":3,"price":25.0},{"product":"Doohickey","qty":1,"price":5.0}],"address":{"city":"Shanghai","zip":"200000"}}');

```

## 提取 JSON 字段（兼容 MySQL 语法）

```sql
SELECT id,
       JSON_UNQUOTE(JSON_EXTRACT(data, '$.customer'))  AS customer,
       JSON_EXTRACT(data, '$.total')                    AS total,
       data->>'$.address.city'                          AS city
FROM   orders_json;

```

## JSON_TABLE（TiDB 6.5+）

```sql
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(
           o.data, '$.items[*]'
           COLUMNS (
               product VARCHAR(100) PATH '$.product',
               qty     INT          PATH '$.qty',
               price   DECIMAL(10,2) PATH '$.price'
           )
       ) AS j;

```

## 嵌套 JSON_TABLE

```sql
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(
           o.data, '$'
           COLUMNS (
               customer VARCHAR(100) PATH '$.customer',
               city     VARCHAR(100) PATH '$.address.city',
               NESTED PATH '$.items[*]' COLUMNS (
                   product VARCHAR(100) PATH '$.product',
                   qty     INT          PATH '$.qty'
               )
           )
       ) AS j;

```
