# ClickHouse: 类型转换

> 参考资料:
> - [1] ClickHouse - Type Conversion Functions
>   https://clickhouse.com/docs/en/sql-reference/functions/type-conversion-functions


## 1. 显式转换函数族


ClickHouse 使用 to* 函数族进行类型转换（不是 CAST）:

```sql
SELECT toUInt32(42);
SELECT toFloat64('3.14');
SELECT toString(42);
SELECT toDate('2024-01-15');
SELECT toDateTime('2024-01-15 10:30:00');
SELECT toDecimal64(3.14, 2);      -- 3.14（精度 2 位小数）
SELECT toUUID('7f1b7e42-3a1c-4b5d-8f2e-9c0d1e2f3a4b');

```

CAST 也支持（SQL 标准语法）:

```sql
SELECT CAST(42 AS String);
SELECT CAST('3.14' AS Float64);
SELECT CAST('2024-01-15' AS Date);

```

## 2. 安全转换: *OrZero / *OrNull（ClickHouse 独有设计）


每个 to* 函数都有安全变体，失败不报错:

```sql
SELECT toUInt64OrZero('not_a_number');   -- 0
SELECT toUInt64OrNull('not_a_number');   -- NULL
SELECT toFloat64OrZero('invalid');       -- 0.0
SELECT toFloat64OrNull('invalid');       -- NULL
SELECT toDateOrZero('invalid');          -- '1970-01-01'
SELECT toDateOrNull('invalid');          -- NULL
SELECT toDecimal64OrNull('abc', 2);     -- NULL

```

 设计分析:
   这是 ClickHouse 最有价值的类型转换设计。
   OLAP 场景中数据质量不保证，一行脏数据不应终止整个查询。
   OrZero: 返回类型的零值（0, 0.0, 空字符串, 1970-01-01）
   OrNull: 返回 NULL（更适合需要区分"真正的 0"和"转换失败"的场景）

 对比:
   MySQL:      CAST 失败返回 0 或 NULL（取决于 sql_mode）
   PostgreSQL: 需要 EXCEPTION WHEN 或 PL/pgSQL
   BigQuery:   SAFE_CAST（返回 NULL）
   SQL Server: TRY_CAST / TRY_CONVERT（返回 NULL）
   SQLite:     动态类型，不需要转换（但也不验证）

## 3. 特殊转换函数


数值精度控制

```sql
SELECT toDecimal64(3.14159, 2);        -- 3.14
SELECT round(3.14159, 2);              -- 3.14
SELECT floor(3.7);                     -- 3
SELECT ceil(3.2);                      -- 4

```

日期时间转换

```sql
SELECT toDate(toDateTime('2024-01-15 10:30:00'));      -- 2024-01-15
SELECT toStartOfMonth(toDate('2024-01-15'));           -- 2024-01-01
SELECT toStartOfHour(toDateTime('2024-01-15 10:30:00')); -- 2024-01-15 10:00:00

```

字符串格式化

```sql
SELECT formatDateTime(now(), '%Y-%m-%d %H:%i:%S');
SELECT toTypeName(42);                 -- 'UInt8'（查询值的类型名）

```

位操作类型转换

```sql
SELECT reinterpretAsFloat64(reinterpretAsUInt64(1.0));
SELECT reinterpretAsString(toUInt64(42));

```

## 4. 隐式转换规则


 ClickHouse 的隐式转换比 MySQL 严格，比 PostgreSQL 宽松:
 UInt8 + UInt16 → UInt16（自动拓宽到更大类型）
 Int32 + Float64 → Float64（整数 + 浮点 → 浮点）
 String + UInt64 → 报错!（不自动转换字符串到数字）

 特殊: Nullable 传播
 Nullable(UInt64) + UInt64 → Nullable(UInt64)

## 5. 对比与引擎开发者启示

ClickHouse 类型转换的设计:
(1) to* 函数族 → 每种类型一个函数（比 CAST 更可发现）
(2) *OrZero/*OrNull → 安全转换（不终止查询）
(3) toTypeName → 运行时类型检查（调试利器）
(4) 严格隐式转换 → 字符串不自动转数字

对引擎开发者的启示:
为每个可能失败的转换提供安全变体（OrZero/OrNull）
是 OLAP 引擎的必备设计。
toTypeName 对用户调试查询很有用，实现成本低但价值高。

