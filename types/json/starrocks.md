# StarRocks: JSON 类型

> 参考资料:
> - [1] StarRocks Documentation - JSON Type
>   https://docs.starrocks.io/docs/sql-reference/data-types/


## 1. JSON 类型 (2.2+)

```sql
CREATE TABLE events (
    id BIGINT NOT NULL, data JSON
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 16;

INSERT INTO events VALUES (1, PARSE_JSON('{"name":"alice","age":25}'));

```

## 2. 路径访问

```sql
SELECT json_query(data, '$.name') FROM events;
SELECT data->'name', data->>'name' FROM events;

```

## 3. Flat JSON (StarRocks 独有优化)

 StarRocks 自动将 JSON 的常用字段"列化"存储(Flat JSON)。
 查询高频字段时性能接近原生列。
 对比 Doris 的 Variant 类型: 概念类似(自动列化)，但实现不同。

## 4. JSON 函数

```sql
SELECT json_length(data), json_keys(data) FROM events;
SELECT PARSE_JSON('{"a":1}');  -- StarRocks 特有

```

## 5. StarRocks vs Doris JSON 差异

构造函数:
- **StarRocks**: PARSE_JSON (更语义化)
- **Doris**: CAST('...' AS JSON)

查询函数:
- **StarRocks**: json_query / json_value
- **Doris**: json_extract / json_extract_string

优化:
- **StarRocks**: Flat JSON(自动列化)
- **Doris**: Variant 类型(2.1+，更激进的列化)

JSONB:
- **Doris 2.1+**: 支持 JSONB(二进制存储)
- **StarRocks**: JSON 内部已是二进制(无需单独类型)

对引擎开发者的启示:
JSON 列化(Flat JSON / Variant)是分析引擎的趋势:
- 存储时自动推断字段类型 → 按列存储
- 查询时按列读取 → 性能接近原生列
ClickHouse 的 JSON Object 类型也采用了类似设计。
