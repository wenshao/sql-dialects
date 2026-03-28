# Amazon Redshift: Math Functions

> 参考资料:
> - [Redshift Documentation - Mathematical Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_Mathematical_functions.html)


```sql
SELECT ABS(-42); SELECT CEIL(4.3); SELECT CEILING(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT TRUNC(3.14159, 2);
SELECT MOD(17, 5); SELECT 17 % 5;
SELECT POWER(2, 10); SELECT SQRT(144); SELECT CBRT(27);
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG(100);
SELECT SIGN(-42); SELECT PI();
SELECT RANDOM();

SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);
SELECT DEGREES(PI()); SELECT RADIANS(180);

SELECT GREATEST(1, 5, 3); SELECT LEAST(1, 5, 3);
```


位运算
```sql
SELECT 5 & 3; SELECT 5 | 3; SELECT 5 # 3;              -- # = XOR
SELECT ~5; SELECT 1 << 4; SELECT 16 >> 2;
```


注意：Redshift 基于 PostgreSQL 8.0.2，数学函数与 PostgreSQL 兼容
注意：LOG(x) 以 10 为底
限制：可能不支持 PostgreSQL 新版本的函数
