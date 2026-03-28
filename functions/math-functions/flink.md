# Flink SQL: 数学函数

> 参考资料:
> - [Flink Documentation - Math Functions](https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/functions/systemfunctions/#math-functions)

**引擎定位**: 流批一体计算引擎。表是外部系统的映射，支持 Changelog 语义和 Watermark 机制。

```sql
SELECT ABS(-42); SELECT CEIL(4.3); SELECT CEILING(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT TRUNCATE(3.14159, 2);
SELECT MOD(17, 5); SELECT 17 % 5;
SELECT POWER(2, 10); SELECT SQRT(144);
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG(EXP(1));
SELECT LOG2(1024); SELECT LOG10(1000);
SELECT SIGN(-42); SELECT PI();
SELECT RAND(); SELECT RAND(42);           -- 可设种子
SELECT RAND_INTEGER(100);                 -- 0 到 99 的随机整数

```

三角函数
```sql
SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);
SELECT DEGREES(PI()); SELECT RADIANS(180);
SELECT COT(1);
SELECT SINH(1); SELECT COSH(1); SELECT TANH(1);

```

GREATEST / LEAST
```sql
SELECT GREATEST(1, 5, 3); SELECT LEAST(1, 5, 3);

```

位运算
```sql
SELECT 5 & 3; SELECT 5 | 3;

```

**注意:** Flink SQL 支持丰富的数学函数
**注意:** RAND_INTEGER 生成整数随机数
**注意:** LOG(x) 以 e 为底
