# Greenplum: JSON 展平为关系行 (JSON Flatten)

> 参考资料:
> - [Greenplum 兼容 PostgreSQL JSON 函数](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-function-summary.html)
> - [PostgreSQL JSON Functions](https://www.postgresql.org/docs/current/functions-json.html)


## 示例数据

```sql
CREATE TABLE orders_json (
    id   SERIAL PRIMARY KEY,
    data JSONB NOT NULL
);

INSERT INTO orders_json (data) VALUES
('{"customer":"Alice","total":150.0,"items":[{"product":"Widget","qty":2,"price":25.0},{"product":"Gadget","qty":1,"price":100.0}],"address":{"city":"Beijing","zip":"100000"}}');
```


## 1. 提取 JSON 字段（兼容 PostgreSQL）

```sql
SELECT id,
       data->>'customer'          AS customer,
       (data->>'total')::NUMERIC  AS total,
       data->'address'->>'city'   AS city
FROM   orders_json;
```


## 2. jsonb_array_elements 展开数组

```sql
SELECT o.id,
       o.data->>'customer'        AS customer,
       item->>'product'           AS product,
       (item->>'qty')::INT        AS qty
FROM   orders_json o,
       LATERAL jsonb_array_elements(o.data->'items') AS item;
```


## 3. jsonb_each 展开对象

```sql
SELECT o.id, kv.key, kv.value
FROM   orders_json o,
       LATERAL jsonb_each(o.data->'address') AS kv;
```
