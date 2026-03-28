# Spanner: 数学函数

> 参考资料:
> - [Cloud Spanner SQL Reference - Math Functions](https://cloud.google.com/spanner/docs/reference/standard-sql/mathematical_functions)

**引擎定位**: Google 全球分布式数据库，TrueTime 外部一致性。基于 Colossus 存储，支持跨洲强一致事务。

```sql
SELECT ABS(-42); SELECT CEIL(4.3); SELECT CEILING(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT TRUNC(3.14159, 2);
SELECT MOD(17, 5);
SELECT POWER(2, 10); SELECT POW(2, 10); SELECT SQRT(144);
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG(100); SELECT LOG10(1000);
SELECT SIGN(-42);

SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);
SELECT SINH(1); SELECT COSH(1); SELECT TANH(1);

SELECT GREATEST(1, 5, 3); SELECT LEAST(1, 5, 3);

SELECT 5 & 3; SELECT 5 | 3; SELECT 5 ^ 3; SELECT ~5;
SELECT 1 << 4; SELECT 16 >> 2;
SELECT BIT_COUNT(7);

```

其他
```sql
SELECT IEEE_DIVIDE(10, 3);               -- IEEE 754 除法
SELECT SAFE_DIVIDE(10, 0);               -- NULL
SELECT SAFE_NEGATE(-42);                  -- 42
SELECT RANGE_BUCKET(35, ARRAY[0, 10, 20, 30, 40]);
SELECT IS_NAN(CAST('NaN' AS FLOAT64));
SELECT IS_INF(CAST('Inf' AS FLOAT64));

```

**注意:** Spanner 使用 GoogleSQL（标准 SQL 兼容）
**注意:** SAFE_* 函数不抛错，返回 NULL
**注意:** IEEE_DIVIDE 遵循 IEEE 754
