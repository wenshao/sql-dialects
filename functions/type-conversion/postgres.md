# PostgreSQL: 类型转换

> 参考资料:
> - [PostgreSQL Documentation - Type Conversion](https://www.postgresql.org/docs/current/typeconv.html)
> - [PostgreSQL Documentation - CREATE CAST](https://www.postgresql.org/docs/current/sql-createcast.html)
> - [PostgreSQL Source - parse_coerce.c](https://github.com/postgres/postgres/blob/master/src/backend/parser/parse_coerce.c)

## 三种类型转换语法

SQL 标准 CAST
```sql
SELECT CAST(42 AS TEXT);                   -- '42'
SELECT CAST('2024-01-15' AS DATE);         -- 2024-01-15
SELECT CAST('{1,2,3}' AS INTEGER[]);       -- ARRAY[1,2,3]

-- :: 运算符 (PostgreSQL 特有)
SELECT 42::TEXT;                           -- '42'
SELECT '42'::INTEGER;                      -- 42
SELECT '2024-01-15'::DATE;
SELECT '192.168.1.1'::INET;               -- PostgreSQL 专有类型
SELECT '{"a":1}'::JSONB;
SELECT 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::UUID;
```

函数式语法（仅限部分类型）
```sql
SELECT integer '42';                       -- 42 (类型名 字面量)
SELECT text '42';                          -- '42'
```

## :: 运算符的解析器实现

:: 在 PostgreSQL 解析器（gram.y）中是一个中缀运算符:
  expression :: typename
在语法分析阶段展开为 TypeCast 节点（与 CAST 完全等价）。

优先级: :: 的优先级很高，仅低于 . (成员访问) 和 [] (下标)。
  SELECT data->>'age'::INT  -- 错误！:: 先绑定 'age'
  SELECT (data->>'age')::INT -- 正确

链式转换:
  SELECT '2024-01-15'::TIMESTAMP::DATE;  -- 先转 TIMESTAMP 再转 DATE
  等价于 CAST(CAST('2024-01-15' AS TIMESTAMP) AS DATE)

对比:
  MySQL:      无 :: 运算符（只有 CAST 和 CONVERT）
  Oracle:     无 :: 运算符（TO_NUMBER/TO_CHAR/TO_DATE）
  SQL Server: 无 :: 运算符（CAST + CONVERT + TRY_CAST）
  CockroachDB/YugabyteDB: 支持 ::（PostgreSQL 兼容）

## 格式化函数: TO_CHAR / TO_NUMBER / TO_DATE / TO_TIMESTAMP

TO_CHAR: 数值/日期 → 格式化字符串
```sql
SELECT TO_CHAR(123456.789, '999,999.99');  -- ' 123,456.79'
SELECT TO_CHAR(NOW(), 'YYYY-MM-DD HH24:MI:SS');
SELECT TO_CHAR(1234, 'FM0000');            -- '1234' (FM 去除前导空格)
```

TO_NUMBER: 字符串 → 数值
```sql
SELECT TO_NUMBER('123,456.78', '999,999.99'); -- 123456.78

-- TO_DATE / TO_TIMESTAMP
SELECT TO_DATE('15/01/2024', 'DD/MM/YYYY');
SELECT TO_TIMESTAMP(1705312200);            -- Unix 时间戳 → TIMESTAMPTZ
```

FM 修饰符: 去除前导空格和尾部零
TH 修饰符: 序数后缀 (1st, 2nd, 3rd)
```sql
SELECT TO_CHAR(NOW(), 'FMMonth DDth, YYYY'); -- 'January 15th, 2024'
```

## 隐式转换规则: PostgreSQL 的类型严格性

PostgreSQL 的隐式转换分三类:
  (a) Assignment cast（赋值转换）: INSERT/UPDATE 时自动发生
      INSERT INTO t(int_col) VALUES('42');  -- 字符串→整数，赋值时允许
  (b) Implicit cast（隐式转换）: 表达式中自动发生
      SELECT 1 + 1.5;  -- INT → NUMERIC 自动提升
  (c) Explicit cast（显式转换）: 必须写 CAST 或 ::

规则:
  数值间: INT → BIGINT → NUMERIC → FLOAT（自动提升）
  TEXT 家族: CHAR → VARCHAR → TEXT（自动转换）
  字符串→数值: 不隐式转换！
  字符串→日期: 不隐式转换！

```sql
SELECT 1 + 1.5;                            -- 2.5 (INT → NUMERIC 隐式)
-- SELECT 'hello' || 42;                   -- 错误！不隐式转换
SELECT 'hello' || 42::TEXT;                -- 正确: 'hello42'

-- 对比 MySQL 的宽松转换:
--   MySQL: '123abc' + 0 = 123（静默截断字符串）
--   MySQL: 'abc' + 0 = 0（完全丢失信息）
--   MySQL: WHERE int_col = '123abc'（静默转换，可能全表扫描）
--   这些"便利"行为是大量 bug 的根源。
```

## pg_cast 系统表: 类型转换注册中心

所有可用的转换都注册在 pg_cast 系统表中:
```sql
SELECT castsource::regtype, casttarget::regtype, castcontext
FROM pg_cast WHERE castsource = 'text'::regtype LIMIT 10;
```

castcontext: 'e'=explicit only, 'a'=assignment, 'i'=implicit

## 自定义类型转换 (CREATE CAST)

创建从 TEXT 到自定义类型的转换
```sql
CREATE TYPE email_type AS (address TEXT);

CREATE FUNCTION text_to_email(TEXT) RETURNS email_type AS $$
    SELECT ROW($1)::email_type;
$$ LANGUAGE sql IMMUTABLE;

CREATE CAST (TEXT AS email_type)
    WITH FUNCTION text_to_email(TEXT)
    AS ASSIGNMENT;  -- 赋值时自动转换
```

设计意义:
  可扩展类型系统 + 可扩展 CAST = PostgreSQL 的核心架构优势。
  PostGIS 的 GEOMETRY 类型、pgvector 的 VECTOR 类型
  都通过 CREATE CAST 注册了与 TEXT 等类型的转换规则。

## 数值→布尔 / JSON 转换

数值↔布尔
```sql
SELECT 0::BOOLEAN;                         -- FALSE
SELECT 1::BOOLEAN;                         -- TRUE
SELECT TRUE::INTEGER;                      -- 1

-- JSON 转换
SELECT '{"name":"test"}'::JSONB;
SELECT '{"name":"test"}'::JSONB->>'name';  -- 'test' (TEXT)
SELECT ROW_TO_JSON(ROW(1, 'test'));        -- {"f1":1,"f2":"test"}
SELECT TO_JSONB(ROW(1, 'test'));           -- {"f1": 1, "f2": "test"}
```

## 横向对比: 类型转换体系

### 安全转换

  PostgreSQL: 无内置 TRY_CAST（需自定义函数）
  SQL Server: TRY_CAST, TRY_CONVERT（失败返回 NULL）
  BigQuery:   SAFE_CAST（失败返回 NULL）
  MySQL:      无（错误时截断或返回 0/NULL，取决于 sql_mode）

### 类型转换严格度 (从严到松)

  PostgreSQL > Oracle > SQL Server > MySQL > SQLite

### 转换函数命名

  PostgreSQL: CAST + :: + TO_CHAR/TO_NUMBER/TO_DATE
  MySQL:      CAST + CONVERT + 隐式
  Oracle:     CAST + TO_NUMBER/TO_CHAR/TO_DATE（Oracle风格）
  SQL Server: CAST + CONVERT + TRY_CAST + TRY_CONVERT + FORMAT

## 对引擎开发者的启示

(1) 类型转换注册表（pg_cast）是可扩展类型系统的关键:
    每个类型转换都有明确的来源类型、目标类型、转换函数、转换级别。
    新的数据类型（如向量、几何）只需注册转换规则，就能与现有类型互操作。

(2) 隐式转换的严格性是正确的设计:
    MySQL 的宽松转换导致了 WHERE int_col = 'abc' 全表扫描等经典问题。
    严格类型检查在编译期发现错误，比运行时隐式转换安全得多。

(3) :: 运算符的实现成本很低（解析器中增加一个产生式），
    但用户体验提升很大（特别是链式转换场景）。
    所有 PostgreSQL 兼容引擎都必须支持 ::。

(4) TRY_CAST 缺失是一个已知的待改进点:
    社区讨论多年但因为不同类型错误语义不同而未纳入核心。
    新引擎建议从第一天就提供安全转换函数。

## 版本演进

PostgreSQL 全版本: CAST, :: 运算符, TO_CHAR/TO_NUMBER/TO_DATE
PostgreSQL 9.4:   to_regclass() 等安全解析函数
PostgreSQL 14:    IS JSON 谓词（验证字符串是否为合法 JSON）
PostgreSQL 16:    改进 NUMERIC → FLOAT 转换精度
