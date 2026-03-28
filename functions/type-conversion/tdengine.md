# TDengine: Type Conversion

> 参考资料:
> - [TDengine Documentation](https://docs.tdengine.com/reference/sql/function/)

```sql
SELECT CAST(42 AS VARCHAR(10)); SELECT CAST('42' AS INT);
SELECT CAST('42' AS BIGINT); SELECT CAST(42 AS FLOAT);
```

时间戳转换
SELECT CAST(ts AS BIGINT) FROM meters;        -- 时间戳 → 毫秒数
SELECT CAST(1705276800000 AS TIMESTAMP);       -- 毫秒数 → 时间戳
更多数值转换

```sql
SELECT CAST(42 AS DOUBLE);                           -- 42.0
SELECT CAST(42 AS SMALLINT);                         -- 42
SELECT CAST(42 AS TINYINT);                          -- 42
SELECT CAST('3.14' AS FLOAT);                        -- 3.14
SELECT CAST('3.14' AS DOUBLE);                       -- 3.14
```

## 字符串 ↔ 数值

```sql
SELECT CAST(12345 AS VARCHAR(10));                   -- '12345'
SELECT CAST('67890' AS BIGINT);                      -- 67890
SELECT CAST('42' AS INT);                            -- 42
```

时间戳转换 (TDengine 核心)
SELECT CAST(ts AS BIGINT) FROM meters;             -- 时间戳 → 毫秒数
SELECT CAST(1705276800000 AS TIMESTAMP);           -- 毫秒数 → 时间戳
SELECT NOW() AS current_ts;                        -- 当前时间戳
SELECT NOW() + 1h;                                 -- 时间算术
SELECT NOW() - 1d;
时间格式化 (有限支持)
SELECT TO_ISO8601(ts) FROM meters;                 -- 时间戳 → ISO 8601 字符串
SELECT TO_UNIXTIMESTAMP('2024-01-15 00:00:00');    -- 字符串 → Unix 毫秒
SELECT TIMETRUNCATE(ts, 1h) FROM meters;           -- 时间截断到小时
SELECT TIMEDIFF(ts1, ts2) FROM t;                  -- 时间差（毫秒）
布尔转换

```sql
SELECT CAST(1 AS BOOL);                              -- true
SELECT CAST(0 AS BOOL);                              -- false
SELECT CAST('true' AS BOOL);                         -- true
```

## NCHAR 和 BINARY 转换

```sql
SELECT CAST('hello' AS NCHAR(10));                   -- Unicode 字符串
SELECT CAST('hello' AS BINARY(10));                  -- 二进制字符串
SELECT CAST(42 AS NCHAR(10));                        -- 数值→NCHAR
```

隐式转换
TDengine 隐式转换非常有限
数值类型之间可以隐式转换 (INT → BIGINT, FLOAT → DOUBLE)
字符串和数值之间必须显式 CAST
错误处理（无安全转换函数）
CAST 转换失败直接报错，无 TRY_CAST 替代
注意：TDengine CAST 类型有限
注意：时间戳以毫秒为单位（可配置为微秒/纳秒）
注意：第一列必须是 TIMESTAMP 类型
注意：支持的类型: BOOL, TINYINT, SMALLINT, INT, BIGINT, FLOAT, DOUBLE, BINARY, NCHAR, VARCHAR, TIMESTAMP
限制：无 TRY_CAST, ::, CONVERT, TO_NUMBER, TO_CHAR, TO_DATE
限制：无日期格式化函数（除 TO_ISO8601）
