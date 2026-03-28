# ksqlDB: Type Conversion

> 参考资料:
> - [ksqlDB Function Reference](https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-reference/scalar-functions/)

```sql
SELECT CAST(42 AS VARCHAR); SELECT CAST('42' AS INTEGER);
SELECT CAST('3.14' AS DOUBLE); SELECT CAST('42' AS BIGINT);
```

## 格式化

```sql
SELECT FORMAT_DATE(ROWTIME, 'yyyy-MM-dd');
SELECT FORMAT_TIMESTAMP(ROWTIME, 'yyyy-MM-dd HH:mm:ss');
SELECT PARSE_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT PARSE_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
```

## 更多数值转换

```sql
SELECT CAST(3.14 AS INTEGER);                        -- 3 (截断)
SELECT CAST(42 AS DOUBLE);                           -- 42.0
SELECT CAST(42 AS BIGINT);                           -- 42
SELECT CAST(42 AS VARCHAR);                          -- '42'
SELECT CAST('3.14' AS DOUBLE);                       -- 3.14
```

## 布尔转换

```sql
SELECT CAST(TRUE AS VARCHAR);                        -- 'true'
SELECT CAST('true' AS BOOLEAN);                      -- true
SELECT CAST('false' AS BOOLEAN);                     -- false
```

## 日期/时间格式化

```sql
SELECT FORMAT_DATE(ROWTIME, 'yyyy-MM-dd');
SELECT FORMAT_DATE(ROWTIME, 'dd/MM/yyyy');
SELECT FORMAT_TIMESTAMP(ROWTIME, 'yyyy-MM-dd HH:mm:ss');
SELECT FORMAT_TIMESTAMP(ROWTIME, 'yyyy-MM-dd''T''HH:mm:ss.SSSXXX');
SELECT PARSE_DATE('2024-01-15', 'yyyy-MM-dd');
SELECT PARSE_DATE('15/01/2024', 'dd/MM/yyyy');
SELECT PARSE_TIMESTAMP('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss');
```

## Unix 时间戳转换

```sql
SELECT UNIX_TIMESTAMP();                             -- 当前 Unix 毫秒
SELECT TIMESTAMPTOSTRING(ROWTIME, 'yyyy-MM-dd HH:mm:ss');
SELECT STRINGTOTIMESTAMP('2024-01-15', 'yyyy-MM-dd');
```

复合类型转换
SELECT CAST(MAP('key1', 'val1') AS MAP<STRING, STRING>);
SELECT CAST(ARRAY['a', 'b'] AS ARRAY<STRING>);
SELECT STRUCT(field1 := 'val1', field2 := 42);
流式处理中的类型转换
CREATE STREAM typed_stream AS
SELECT
CAST(raw_id AS BIGINT) AS id,
CAST(raw_amount AS DECIMAL(10,2)) AS amount,
PARSE_TIMESTAMP(event_time, 'yyyy-MM-dd HH:mm:ss') AS ts
FROM raw_stream
EMIT CHANGES;
隐式转换
ksqlDB 隐式转换非常有限
数值类型可自动提升 (INT → BIGINT → DOUBLE)
字符串和数值之间必须显式 CAST
错误处理（无 TRY_CAST）
CAST 转换失败会导致记录被丢弃或查询失败
建议在上游 Kafka 生产者端确保数据质量
注意：ksqlDB CAST 类型有限
注意：日期使用 Java DateTimeFormatter 模式
注意：流处理中转换失败可能导致消息丢失
限制：无 TRY_CAST, ::, CONVERT, TO_NUMBER, TO_CHAR
