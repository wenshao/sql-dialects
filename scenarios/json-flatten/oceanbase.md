# OceanBase: JSON 展开

> 参考资料:
> - [OceanBase Documentation - JSON 函数（MySQL 模式）](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - OceanBase 兼容 MySQL / Oracle 语法

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## 示例数据（MySQL 模式）

```sql
CREATE TABLE orders_json (
    id   INT AUTO_INCREMENT PRIMARY KEY,
    data JSON NOT NULL
);

```

## JSON_EXTRACT 提取字段

```sql
SELECT id,
       JSON_UNQUOTE(JSON_EXTRACT(data, '$.customer')) AS customer,
       JSON_EXTRACT(data, '$.total')                   AS total,
       data->>'$.address.city'                         AS city
FROM   orders_json;

```

## JSON_TABLE 展开数组（OceanBase 4.x+）

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
