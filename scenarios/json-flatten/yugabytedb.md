# YugabyteDB: JSON 展开

> 参考资料:
> - [YugabyteDB Documentation - JSON Data Type (YSQL)](https://docs.yugabyte.com/preview/api/ysql/datatypes/type_json/)
> - [YugabyteDB Documentation - JSON Functions](https://docs.yugabyte.com/preview/api/ysql/functions-operators/jsonb/)
> - [PostgreSQL Documentation - JSON Functions（YugabyteDB 兼容）](https://www.postgresql.org/docs/current/functions-json.html)

**引擎定位**: 分布式 SQL 数据库，兼容 PostgreSQL 协议。基于 DocDB (RocksDB) 存储，Raft 共识。

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
       data->>'customer'                        AS customer,
       (data->>'total')::NUMERIC                 AS total,
       data->'address'->>'city'                  AS city,
       data->'address'->>'zip'                   AS zip
FROM   orders_json;

```

YugabyteDB YSQL API 完全兼容 PostgreSQL 的 JSONB 运算符
  ->> : 提取值为文本    -> : 提取值为 JSONB
  JSONB 存储格式与 PostgreSQL 相同（二进制，查询无需重新解析）

## jsonb_array_elements 展开嵌套数组


```sql
SELECT o.id,
       o.data->>'customer'            AS customer,
       item->>'product'               AS product,
       (item->>'qty')::INT            AS qty,
       (item->>'price')::NUMERIC      AS price
FROM   orders_json o,
       LATERAL jsonb_array_elements(o.data->'items') AS item;

```

**设计分析:** 分布式环境下的 JSON 展开
  LATERAL + jsonb_array_elements 语法与 PostgreSQL 完全一致
  YugabyteDB 会将 LATERAL 下推到数据所在节点执行
  对于分布式表，JSON 展开在本地节点完成后再合并结果

## jsonb_to_recordset: 直接转为关系记录


```sql
SELECT o.id, o.data->>'customer' AS customer, r.*
FROM   orders_json o,
       LATERAL jsonb_to_recordset(o.data->'items')
              AS r(product TEXT, qty INT, price NUMERIC);

```

jsonb_to_recordset 一步完成列映射，比逐字段提取更简洁

## jsonb_each 展开对象键值对


```sql
SELECT o.id, kv.key, kv.value
FROM   orders_json o,
       LATERAL jsonb_each(o.data->'address') AS kv;

```

## 分布式 JSON 查询优化


在分布式场景中，JSON 列上的查询可能涉及跨节点通信
推荐策略:
  (a) 将 JSON 中高频查询的字段提取为独立列（包括主键）
  (b) 使用 hash 分片将相关数据放在同一节点
  (c) 对 JSON 列创建 GIN 索引（YugabyteDB 支持）

CREATE INDEX idx_orders_json_gin ON orders_json USING GIN (data);

分布式索引示例:
CREATE INDEX idx_orders_customer
    ON orders_json ((data->>'customer'));

```sql
SELECT id, data->>'customer' AS customer
FROM   orders_json
WHERE  data->>'customer' = 'Alice';

```

## JSON 聚合（反向操作: 行转 JSON）


将展开的数据重新聚合为 JSON
```sql
SELECT o.data->>'customer' AS customer,
       jsonb_agg(
           jsonb_build_object('product', item->>'product',
                              'qty', (item->>'qty')::INT)
       ) AS items_summary
FROM   orders_json o,
       LATERAL jsonb_array_elements(o.data->'items') AS item
GROUP  BY o.id, o.data->>'customer';

```

## 横向对比与对引擎开发者的启示


## YugabyteDB JSON 能力:

  基于 PostgreSQL YSQL API，JSON 功能完整
  支持 JSONB 类型、所有 JSON 函数、GIN 索引
  分布式架构下 JSON 操作可下推到节点本地执行

## 与 PostgreSQL 的差异:

  单节点语法完全相同
  分布式场景需要考虑数据分片和查询下推
  索引策略需要考虑分区键选择

**对引擎开发者:**
  分布式数据库兼容 PostgreSQL JSON 生态是巨大优势
  JSON 展开操作（LATERAL + SRF）应尽量下推到存储节点
  考虑 JSON 列的分布式索引策略（全局 vs 本地）
