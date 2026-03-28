# Hive: 数值类型

> 参考资料:
> - [1] Apache Hive - Data Types
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+Types
> - [2] Apache Hive - Mathematical Functions
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+UDF#LanguageManualUDF-MathematicalFunctions


## 1. 整数类型

TINYINT:   1 字节, -128 ~ 127
SMALLINT:  2 字节, -32768 ~ 32767
INT:       4 字节, -2^31 ~ 2^31-1
BIGINT:    8 字节, -2^63 ~ 2^63-1


```sql
CREATE TABLE examples (
    tiny_val  TINYINT,
    small_val SMALLINT,
    int_val   INT,
    big_val   BIGINT
) STORED AS ORC;

```

整数字面量后缀（Hive 特有）

```sql
SELECT 100Y;     -- TINYINT
SELECT 100S;     -- SMALLINT
SELECT 100;      -- INT
SELECT 100L;     -- BIGINT

```

 对比: MySQL 不支持字面量后缀; PostgreSQL 也不支持
 这是 Java 风格的字面量语法（Hive 底层是 Java）

## 2. 浮点类型

FLOAT:  4 字节, 单精度 IEEE 754
DOUBLE: 8 字节, 双精度 IEEE 754 (DOUBLE PRECISION 是别名)

浮点精度问题（所有引擎共同问题）

```sql
SELECT CAST(0.1 + 0.2 AS DOUBLE);    -- ≈ 0.30000000000000004
```

 金融计算必须使用 DECIMAL

## 3. 定点数: DECIMAL (0.11+)

DECIMAL(p, s): p = 总位数(最大38), s = 小数位数(最大38)
DECIMAL: 默认 DECIMAL(10, 0)


```sql
CREATE TABLE prices (
    price DECIMAL(10, 2),            -- 精确到分: -99999999.99 ~ 99999999.99
    rate  DECIMAL(5, 4)              -- 精确到万分: -9.9999 ~ 9.9999
) STORED AS ORC;

```

 DECIMAL 的演进:
 0.11: 首次引入 DECIMAL（内部使用 Java BigDecimal）
 0.13: 重大改进，性能提升，支持更多操作
 推荐: 金融/精确计算使用 DECIMAL，科学计算使用 DOUBLE

 DECIMAL 运算规则:
 DECIMAL(p1,s1) + DECIMAL(p2,s2) → DECIMAL(max(s1,s2)+max(p1-s1,p2-s2)+1, max(s1,s2))
 DECIMAL(10,2) * DECIMAL(10,2)   → DECIMAL(21,4)

## 4. BOOLEAN

```sql
CREATE TABLE flags (active BOOLEAN DEFAULT TRUE) STORED AS ORC;

SELECT CAST(1 AS BOOLEAN);      -- true
SELECT CAST(0 AS BOOLEAN);      -- false
SELECT CAST('true' AS BOOLEAN); -- true

```

BOOLEAN 在 WHERE 中直接使用

```sql
SELECT * FROM flags WHERE active;
SELECT * FROM flags WHERE NOT active;

```

## 5. 类型转换与隐式提升

```sql
SELECT CAST('123' AS INT);
SELECT CAST(3.14 AS INT);       -- 3 (截断，非四舍五入)
SELECT CAST(TRUE AS INT);       -- 1

```

隐式提升方向:
TINYINT → SMALLINT → INT → BIGINT → FLOAT → DOUBLE → DECIMAL → STRING

```sql
SELECT 1 + 1.5;                 -- DOUBLE (INT → DOUBLE)
SELECT '42' + 0;                -- 42 (STRING → DOUBLE → 加法)

```

## 6. 跨引擎对比: 数值类型

 引擎          整数类型             浮点         定点           特殊
 MySQL         TINYINT~BIGINT       FLOAT/DOUBLE DECIMAL(65,30) UNSIGNED
 PostgreSQL    SMALLINT/INT/BIGINT  REAL/DOUBLE  NUMERIC        SERIAL
 Oracle        NUMBER(统一)         BINARY_FLOAT NUMBER(p,s)    无
 Hive          TINYINT~BIGINT       FLOAT/DOUBLE DECIMAL(38,38) 字面量后缀
 Spark SQL     同 Hive              同 Hive      同 Hive        同 Hive
 BigQuery      INT64                FLOAT64      NUMERIC/BIGNUMERIC 无小类型
 ClickHouse    Int8~Int256          Float32/64   Decimal(P,S)   UInt系列

 Oracle 的 NUMBER 是唯一的数值类型（NUMBER(10,0) = 整数，NUMBER(10,2) = 定点数）
 Hive 区分了整数/浮点/定点，提供了更精确的类型选择

## 7. 已知限制

### 1. 无 UNSIGNED 类型: 所有整数都是有符号的

### 2. DECIMAL 最大精度 38 位: 对于超高精度计算可能不够

### 3. FLOAT/DOUBLE 的 NaN 和 Infinity 处理: 与 IEEE 754 标准一致

### 4. 整数溢出: 溢出时返回 NULL（不报错）

### 5. 隐式转换宽松: '42' + 0 = 42（可能导致意外行为）


## 8. 对引擎开发者的启示

### 1. DECIMAL 是金融计算的必备: FLOAT/DOUBLE 的精度问题是所有引擎的共同挑战

### 2. 字面量后缀（100Y/100S/100L）降低了类型歧义: 用户可以精确控制字面量类型

### 3. 隐式转换的宽松程度是 trade-off: 宽松降低用户门槛但增加 Bug 风险

### 4. BOOLEAN 应该是一等公民: Hive 的 BOOLEAN 支持完整，可以直接在 WHERE 中使用

