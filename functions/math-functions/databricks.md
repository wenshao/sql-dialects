# Databricks: Math Functions

> 参考资料:
> - [Databricks SQL Reference - Math Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)


```sql
SELECT ABS(-42); SELECT CEIL(4.3); SELECT CEILING(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT BROUND(2.5);           -- 银行家舍入
SELECT MOD(17, 5); SELECT 17 % 5;
SELECT POWER(2, 10); SELECT POW(2, 10); SELECT SQRT(144);
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG(10, 1000); SELECT LOG2(1024); SELECT LOG10(1000);
SELECT SIGN(-42); SELECT PI();
SELECT RAND(); SELECT RAND(42);                          -- 可设种子
```


三角函数
```sql
SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);
SELECT DEGREES(PI()); SELECT RADIANS(180);
SELECT SINH(1); SELECT COSH(1); SELECT TANH(1);
```


GREATEST / LEAST
```sql
SELECT GREATEST(1, 5, 3); SELECT LEAST(1, 5, 3);
```


位运算
```sql
SELECT 5 & 3; SELECT 5 | 3; SELECT 5 ^ 3; SELECT ~5;
SELECT SHIFTLEFT(1, 4); SELECT SHIFTRIGHT(16, 2);
SELECT BIT_COUNT(7);
```


其他
```sql
SELECT CBRT(27); SELECT FACTORIAL(5);
SELECT CONV(255, 10, 16);                -- 'FF'
SELECT WIDTH_BUCKET(42, 0, 100, 10);     -- 5
```


注意：Databricks SQL 兼容 Spark SQL 数学函数
注意：BROUND 银行家舍入（四舍六入五成双）
注意：位移用 SHIFTLEFT/SHIFTRIGHT 函数
