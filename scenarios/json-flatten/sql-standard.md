# SQL 标准: JSON 展平为关系行

> 参考资料:
> - ISO/IEC 9075-2:2016 (SQL/JSON)
> - SQL:2016 引入了 JSON_VALUE, JSON_QUERY, JSON_TABLE
> - SQL:2023 进一步扩展了 JSON 支持

## SQL:2016 标准 JSON 函数

JSON_VALUE: 提取标量值
SELECT JSON_VALUE(data, '$.customer') FROM orders_json;

JSON_QUERY: 提取 JSON 子文档
SELECT JSON_QUERY(data, '$.items') FROM orders_json;

JSON_TABLE: 将 JSON 转为关系行（最核心的功能）
SELECT j.*
FROM orders_json o,
     JSON_TABLE(o.data, '$.items[*]'
         COLUMNS (
             product VARCHAR(100) PATH '$.product',
             qty     INT          PATH '$.qty',
             price   DECIMAL(10,2) PATH '$.price'
         )
     ) AS j;

JSON_EXISTS: 检查路径是否存在
SELECT * FROM orders_json WHERE JSON_EXISTS(data, '$.items[*]?(@.price > 50)');

## 各数据库的 JSON 支持对照

PostgreSQL:   jsonb_array_elements / jsonb_each / jsonb_to_recordset (9.4+)
MySQL:        JSON_TABLE (8.0.4+)
SQL Server:   OPENJSON (2016+)
Oracle:       JSON_TABLE (12c+)
BigQuery:     JSON_QUERY_ARRAY + UNNEST
Snowflake:    FLATTEN + VARIANT
ClickHouse:   JSONExtract + arrayJoin
Hive:         get_json_object + LATERAL VIEW
Spark:        from_json + explode
SQLite:       json_each / json_tree (3.9.0+)
DuckDB:       json_extract + UNNEST
DB2:          JSON_TABLE (11.1+)
Trino:        json_extract + CAST + UNNEST
