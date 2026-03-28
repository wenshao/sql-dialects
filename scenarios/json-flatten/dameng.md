# 达梦 (Dameng): JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [达梦数据库 SQL 参考手册 - JSON 函数](https://eco.dameng.com/document/dm/zh-cn/sql-dev/)
> - 达梦兼容 Oracle JSON 语法


## 示例数据

```sql
CREATE TABLE orders_json (
    id   INT IDENTITY(1,1) PRIMARY KEY,
    data CLOB
);
```

## JSON_VALUE 提取字段（兼容 Oracle）

```sql
SELECT id,
       JSON_VALUE(data, '$.customer')      AS customer,
       JSON_VALUE(data, '$.total')         AS total,
       JSON_VALUE(data, '$.address.city')  AS city
FROM   orders_json;
```

## JSON_TABLE 展开数组

```sql
SELECT o.id, j.*
FROM   orders_json o,
       JSON_TABLE(o.data, '$.items[*]'
           COLUMNS (
               product VARCHAR(100) PATH '$.product',
               qty     INT          PATH '$.qty',
               price   DECIMAL(10,2) PATH '$.price'
           )
       ) j;
```
