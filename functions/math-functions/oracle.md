# Oracle: 数学函数

> 参考资料:
> - [Oracle SQL Language Reference - Number Functions](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Number-Functions.html)

## 基本数学函数（所有 SELECT 需要 FROM DUAL）

```sql
SELECT ABS(-42) FROM DUAL;                     -- 42
SELECT CEIL(4.3) FROM DUAL;                    -- 5
SELECT FLOOR(4.7) FROM DUAL;                   -- 4
SELECT ROUND(3.14159, 2) FROM DUAL;            -- 3.14
SELECT TRUNC(3.14159, 2) FROM DUAL;            -- 3.14 (截断，不四舍五入)
SELECT MOD(17, 5) FROM DUAL;                   -- 2
SELECT REMAINDER(17, 5) FROM DUAL;             -- 2 (IEEE 余数)

-- MOD vs REMAINDER:
--   MOD 使用 FLOOR 除法: MOD(a,b) = a - b * FLOOR(a/b)
--   REMAINDER 使用 ROUND 除法: REMAINDER(a,b) = a - b * ROUND(a/b)
--   大多数场景相同，但负数时行为不同:
--   MOD(-7, 3) = -1,  REMAINDER(-7, 3) = 2
```

## 幂、根、指数、对数

```sql
SELECT POWER(2, 10) FROM DUAL;                 -- 1024
SELECT SQRT(144) FROM DUAL;                    -- 12
SELECT EXP(1) FROM DUAL;                       -- e ≈ 2.718
SELECT LN(2.718281828) FROM DUAL;              -- ≈ 1.0 (自然对数)
SELECT LOG(10, 1000) FROM DUAL;                -- 3 (LOG(base, x))

-- Oracle LOG(base, x) 底数在前! 这与数学记法一致但与某些数据库不同
-- PostgreSQL: LOG(base, x) — 相同
-- MySQL:      LOG(x) = LN(x), LOG(base, x) 也支持但意义相反!
-- SQL Server: LOG(x, base) — 底数在后
```

## Oracle 没有 PI() 函数!

```sql
SELECT ACOS(-1) FROM DUAL;                     -- π ≈ 3.14159...
-- 这是 Oracle 的一个遗漏，其他数据库都有 PI() 函数
```

## 随机数（DBMS_RANDOM 包，Oracle 独有方式）

```sql
SELECT DBMS_RANDOM.VALUE FROM DUAL;            -- 0.0 到 1.0
SELECT DBMS_RANDOM.VALUE(1, 100) FROM DUAL;    -- 1 到 100
SELECT TRUNC(DBMS_RANDOM.VALUE(1, 101)) FROM DUAL;  -- 1 到 100 整数
SELECT DBMS_RANDOM.NORMAL FROM DUAL;           -- 正态分布随机数

-- 横向对比:
--   Oracle:     DBMS_RANDOM.VALUE（包函数，不是 SQL 函数!）
--   PostgreSQL: random()（SQL 函数）
--   MySQL:      RAND()（SQL 函数）
--   SQL Server: RAND()（SQL 函数）
--
-- 对引擎开发者的启示:
--   随机数应作为 SQL 内置函数（如 RANDOM()）而非包函数提供。
--   Oracle 用包函数是因为早期 SQL 函数不支持有状态操作。
```

## 三角函数（弧度制）

```sql
SELECT SIN(0) FROM DUAL;                       -- 0
SELECT COS(0) FROM DUAL;                       -- 1
SELECT TAN(ACOS(-1)/4) FROM DUAL;              -- ≈ 1.0 (tan(π/4))
SELECT ASIN(1), ACOS(1), ATAN(1) FROM DUAL;
SELECT ATAN2(1, 1) FROM DUAL;                  -- π/4
```

双曲函数
```sql
SELECT SINH(1), COSH(1), TANH(1) FROM DUAL;
```

## GREATEST / LEAST

```sql
SELECT GREATEST(1, 5, 3, 9, 2) FROM DUAL;     -- 9
SELECT LEAST(1, 5, 3, 9, 2) FROM DUAL;         -- 1

-- NULL 参数使结果为 NULL（Oracle 特有行为）
SELECT GREATEST(1, NULL, 3) FROM DUAL;         -- NULL
-- MySQL: GREATEST(1, NULL, 3) → 3（忽略 NULL）
```

## 位运算（Oracle 最弱的领域）

```sql
SELECT BITAND(5, 3) FROM DUAL;                 -- 1 (AND)
-- Oracle 只有 BITAND!
-- OR, XOR, NOT 需要手动模拟:
--   OR:  a + b - BITAND(a, b)
--   XOR: a + b - 2 * BITAND(a, b)
--   NOT: (power(2, n) - 1) - a  (n 位反转)

-- 横向对比:
--   Oracle:     只有 BITAND（最弱）
--   PostgreSQL: &, |, #, ~, <<, >>（运算符，最完整）
--   MySQL:      &, |, ^, ~, <<, >>（运算符）
--   SQL Server: &, |, ^, ~（运算符）
--
-- 对引擎开发者的启示:
--   位运算对低级数据处理（权限位图、特征标记）很重要。
--   推荐作为运算符而非函数实现（语法更自然）。
```

## 其他数学函数

```sql
SELECT SIGN(-42) FROM DUAL;                    -- -1
SELECT SIGN(0) FROM DUAL;                      -- 0
SELECT SIGN(42) FROM DUAL;                     -- 1

SELECT WIDTH_BUCKET(42, 0, 100, 10) FROM DUAL; -- 5 (直方图桶号)
SELECT NANVL(0/0, 0) FROM DUAL;               -- 0 (NaN 替换，BINARY_DOUBLE)
```

## 对引擎开发者的总结

1. Oracle 没有 PI() 函数，这是一个明显的遗漏，新引擎应提供。
2. DBMS_RANDOM 是包函数而非 SQL 函数，使用不够方便。
3. Oracle 位运算只有 BITAND，这是最大的短板，需要模拟其他操作。
4. LOG(base, x) 的参数顺序各数据库不一致，这是迁移的常见错误来源。
5. MOD vs REMAINDER 在负数时行为不同，文档中应明确说明。
6. FROM DUAL 在数学计算中尤为烦人，新引擎应允许无 FROM 的 SELECT。
