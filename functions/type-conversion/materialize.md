# Materialize: Type Conversion

> 参考资料:
> - [Materialize Documentation - CAST](https://materialize.com/docs/sql/functions/#casts)

```sql
SELECT CAST(42 AS TEXT); SELECT CAST('42' AS INT); SELECT CAST('2024-01-15' AS DATE);
SELECT 42::TEXT; SELECT '42'::INT; SELECT '2024-01-15'::DATE;
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_timestamp(1705276800);
```

## 数值转换

```sql
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT CAST('100' AS BIGINT);                        -- 100
SELECT '3.14'::NUMERIC(10,2);                        -- 3.14
SELECT 42::FLOAT8;                                   -- 42.0
SELECT CAST(3.14 AS NUMERIC(10,1));                  -- 3.1
```

## 布尔转换

```sql
SELECT CAST(1 AS BOOLEAN);                           -- true
SELECT 'true'::BOOLEAN;                              -- true
SELECT 'false'::BOOLEAN;                             -- false
SELECT TRUE::INT;                                    -- 1
```

## 日期/时间格式化

```sql
SELECT to_char(now(), 'YYYY-MM-DD HH24:MI:SS');
SELECT to_char(now(), 'Day, DD Month YYYY');
SELECT to_timestamp(1705276800);                     -- Unix 时间戳 → TIMESTAMP
SELECT EXTRACT(EPOCH FROM now());                    -- TIMESTAMP → Unix
SELECT '2024-01-15'::DATE;
SELECT '10:30:00'::TIME;
SELECT '2024-01-15 10:30:00+00'::TIMESTAMPTZ;
```

## 数值格式化

```sql
SELECT to_char(1234567.89, 'FM9,999,999.00');        -- '1,234,567.89'
```

## JSON 转换

```sql
SELECT '{"name":"test"}'::JSONB;
SELECT CAST('["a","b","c"]' AS JSONB);
SELECT '42'::JSONB;
```

## 隐式转换规则

```sql
SELECT 1 + 1.5;                                     -- NUMERIC
SELECT 'hello' || 42::TEXT;                          -- 需要显式转 TEXT
SELECT 1 + '2'::INT;                                -- 需显式 CAST
```

## 区间转换

```sql
SELECT INTERVAL '1 day';
SELECT INTERVAL '2 hours 30 minutes';
SELECT '1 day'::INTERVAL;
```

流处理中的类型转换
CREATE MATERIALIZED VIEW typed_view AS
SELECT
CAST(raw_field AS INTEGER) AS int_field,
CAST(ts_field AS TIMESTAMPTZ) AS event_time,
raw_field::NUMERIC(10,2) AS decimal_field
FROM source_stream;
错误处理（无 TRY_CAST，转换失败中止查询）
建议在 CREATE SOURCE 阶段确保数据类型正确
注意：Materialize 兼容 PostgreSQL 类型转换
注意：支持 CAST, ::, to_char, to_timestamp
注意：流处理中转换失败可能导致管道停滞
限制：无 TRY_CAST, TO_NUMBER, TO_DATE
