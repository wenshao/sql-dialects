# Firebird: Math Functions

> 参考资料:
> - [Firebird Language Reference - Built-in Scalar Functions](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref40/)

```sql
SELECT ABS(-42); SELECT CEIL(4.3); SELECT CEILING(4.3); SELECT FLOOR(4.7);
SELECT ROUND(3.14159, 2); SELECT TRUNC(3.14159, 2);
SELECT MOD(17, 5);
SELECT POWER(2, 10); SELECT SQRT(144);
SELECT EXP(1); SELECT LN(EXP(1)); SELECT LOG(10, 1000); SELECT LOG10(1000);
SELECT SIGN(-42); SELECT PI();
SELECT RAND();
```

## 三角函数

```sql
SELECT SIN(0); SELECT COS(0); SELECT TAN(0);
SELECT ASIN(1); SELECT ACOS(1); SELECT ATAN(1); SELECT ATAN2(1, 1);
SELECT SINH(1); SELECT COSH(1); SELECT TANH(1);
```

## GREATEST / LEAST                                    -- 3.0+

```sql
SELECT MAXVALUE(1, 5, 3);                -- 5 (Firebird 用 MAXVALUE)
SELECT MINVALUE(1, 5, 3);                -- 1 (Firebird 用 MINVALUE)
```

## 位运算

```sql
SELECT BIN_AND(5, 3); SELECT BIN_OR(5, 3); SELECT BIN_XOR(5, 3);
SELECT BIN_NOT(5);
SELECT BIN_SHL(1, 4); SELECT BIN_SHR(16, 2);
```

注意：Firebird 使用 MAXVALUE/MINVALUE 而非 GREATEST/LEAST
注意：LOG(base, x) 底数在前
注意：位运算使用 BIN_* 前缀函数
