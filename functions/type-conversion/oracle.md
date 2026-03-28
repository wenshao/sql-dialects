# Oracle: 类型转换

> 参考资料:
> - [Oracle SQL Language Reference - Conversion Functions](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Conversion-Functions.html)
> - [Oracle SQL Language Reference - Format Models](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Format-Models.html)

## CAST（SQL 标准）

```sql
SELECT CAST(42 AS VARCHAR2(10)) FROM DUAL;     -- '42'
SELECT CAST('42' AS NUMBER) FROM DUAL;          -- 42
SELECT CAST(3.14 AS NUMBER(10,0)) FROM DUAL;   -- 3
SELECT CAST(SYSDATE AS TIMESTAMP) FROM DUAL;
```

## TO_CHAR: 数值/日期 → 字符串（Oracle 最核心的转换函数）

数值格式化
```sql
SELECT TO_CHAR(123456.789, '999,999.99') FROM DUAL;    -- ' 123,456.79'
SELECT TO_CHAR(123456.789, 'FM999,999.99') FROM DUAL;  -- '123,456.79'
SELECT TO_CHAR(0.5, '990.00') FROM DUAL;                -- '  0.50'
SELECT TO_CHAR(42, '0000') FROM DUAL;                   -- '0042'
SELECT TO_CHAR(1234.5, '$9,999.99') FROM DUAL;         -- ' $1,234.50'
-- FM 修饰符去除前导空格（Oracle 独有的格式修饰符）

-- 日期格式化
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'Day, DD Month YYYY') FROM DUAL;
SELECT TO_CHAR(SYSDATE, 'YYYY"年"MM"月"DD"日"') FROM DUAL;
```

## TO_NUMBER / TO_DATE / TO_TIMESTAMP

```sql
SELECT TO_NUMBER('123,456.78', '999,999.99') FROM DUAL;
SELECT TO_NUMBER('$1,234.56', '$9,999.99') FROM DUAL;
SELECT TO_NUMBER('FF', 'XX') FROM DUAL;                 -- 255 (十六进制)

SELECT TO_DATE('2024-01-15', 'YYYY-MM-DD') FROM DUAL;
SELECT TO_DATE('15/01/2024', 'DD/MM/YYYY') FROM DUAL;

SELECT TO_TIMESTAMP('2024-01-15 10:30:00.123', 'YYYY-MM-DD HH24:MI:SS.FF3') FROM DUAL;

SELECT TO_TIMESTAMP_TZ('2024-01-15 10:30:00 +08:00',
    'YYYY-MM-DD HH24:MI:SS TZH:TZM') FROM DUAL;
```

## 设计分析: Oracle 的转换函数体系

Oracle 使用 TO_* 函数族进行显式转换:
  TO_CHAR:   任意类型 → VARCHAR2
  TO_NUMBER: VARCHAR2 → NUMBER
  TO_DATE:   VARCHAR2 → DATE
  TO_TIMESTAMP: VARCHAR2 → TIMESTAMP

横向对比:
  Oracle:     TO_CHAR / TO_NUMBER / TO_DATE + Format Model
  PostgreSQL: CAST + to_char() / to_number() / to_timestamp()
              :: 运算符（简洁: '42'::integer）
  MySQL:      CAST / CONVERT + DATE_FORMAT / STR_TO_DATE
  SQL Server: CAST / CONVERT(type, expr, style_code) + FORMAT

Oracle 的 Format Model 最丰富（'FM999,999.99' 等），
但也增加了学习成本。SQL Server 的 CONVERT style code 更简洁但不直观。

对引擎开发者的启示:
  类型转换函数是最常用的函数之一。至少需要:
  1. CAST（SQL 标准）
  2. 日期格式化/解析函数
  3. 数值格式化函数
  PostgreSQL 的 :: 运算符非常方便，值得考虑支持。

## 隐式转换（Oracle 较宽松，是 Bug 来源）

VARCHAR2 → NUMBER: 在算术运算中自动转换
```sql
SELECT '42' + 0 FROM DUAL;                     -- 42

-- VARCHAR2 → DATE: 使用 NLS_DATE_FORMAT 自动转换
-- 这是 Oracle 中 Bug 的主要来源之一!
-- 不同会话的 NLS_DATE_FORMAT 可能不同，导致相同 SQL 在不同环境下行为不一致

-- NUMBER → VARCHAR2: 在字符串拼接中自动转换
SELECT 'Value: ' || 42 FROM DUAL;              -- 'Value: 42'

-- 对引擎开发者的启示:
--   隐式转换方便但危险。推荐:
--   - 算术运算中的字符串→数值: 可以支持（MySQL/Oracle 做法）
--   - 日期隐式转换: 强烈不推荐（Oracle 的 NLS_DATE_FORMAT 是反面教材）
--   - 字符串拼接中的数值: 可以支持（用户体验好）
```

## 安全转换（12c R2+）

VALIDATE_CONVERSION: 检查是否可转换（返回 0/1）
```sql
SELECT VALIDATE_CONVERSION('42' AS NUMBER) FROM DUAL;      -- 1
SELECT VALIDATE_CONVERSION('abc' AS NUMBER) FROM DUAL;     -- 0
SELECT VALIDATE_CONVERSION('2024-13-01' AS DATE, 'YYYY-MM-DD') FROM DUAL; -- 0

-- DEFAULT ON CONVERSION ERROR: 转换失败时使用默认值
SELECT CAST('abc' AS NUMBER DEFAULT 0 ON CONVERSION ERROR) FROM DUAL; -- 0
SELECT CAST('bad-date' AS DATE DEFAULT DATE '2000-01-01'
    ON CONVERSION ERROR) FROM DUAL;
```

横向对比:
  Oracle 12c R2+: VALIDATE_CONVERSION + DEFAULT ON CONVERSION ERROR
  PostgreSQL:     无原生安全转换（需要自定义函数或 PL/pgSQL）
  MySQL:          隐式转换失败时返回 0 或 NULL（不报错，但不安全）
  SQL Server:     TRY_CAST / TRY_CONVERT（SQL Server 2012+）

对引擎开发者的启示:
  安全转换（TRY_CAST 或 DEFAULT ON CONVERSION ERROR）是必备功能。
  用户经常需要处理脏数据，转换失败不应该终止整个查询。

## '' = NULL 对类型转换的影响

TO_NUMBER('') 报错! 因为 '' = NULL:
```sql
SELECT TO_NUMBER('') FROM DUAL;  -- ORA-01722: invalid number
```

实际上 TO_NUMBER(NULL) 返回 NULL，但 Oracle 的行为不一致

LENGTH('') 返回 NULL:
```sql
SELECT LENGTH('') FROM DUAL;                    -- NULL（不是 0）

-- TO_CHAR(NULL) 返回 NULL:
SELECT TO_CHAR(NULL) FROM DUAL;                 -- NULL
-- 由于 '' = NULL，TO_CHAR 结果可能需要 NVL 包装
```

## Unix 时间戳转换

日期 → Unix 时间戳
```sql
SELECT (CAST(SYSDATE AS DATE) - TO_DATE('1970-01-01','YYYY-MM-DD')) * 86400
FROM DUAL;
```

Unix 时间戳 → 日期
```sql
SELECT TO_DATE('1970-01-01','YYYY-MM-DD') + 1700000000/86400 FROM DUAL;
```

RAW / 十六进制转换
```sql
SELECT RAWTOHEX('hello') FROM DUAL;            -- '68656C6C6F'
SELECT UTL_RAW.CAST_TO_VARCHAR2(HEXTORAW('68656C6C6F')) FROM DUAL; -- 'hello'
```

## 对引擎开发者的总结

1. Oracle 的 TO_* 函数族 + Format Model 是最成熟的转换体系，但学习曲线陡峭。
2. 隐式日期转换依赖 NLS_DATE_FORMAT 是 Oracle 最大的设计缺陷之一。
3. VALIDATE_CONVERSION 和 DEFAULT ON CONVERSION ERROR 是 12c R2 的优秀创新。
4. FM 修饰符（去前导空格）是 TO_CHAR 中最常忘记的细节。
5. 安全转换（TRY_CAST 模式）是现代引擎的必备功能。
