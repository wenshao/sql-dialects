# MariaDB: 数学函数

与 MySQL 完全一致

参考资料:
[1] MariaDB Knowledge Base - Numeric Functions
https://mariadb.com/kb/en/numeric-functions/

## 1. 基本数学函数

```sql
SELECT ABS(-10), CEIL(3.2), FLOOR(3.8), ROUND(3.567, 2), TRUNCATE(3.567, 1);
SELECT MOD(10, 3), POWER(2, 10), SQRT(16), SIGN(-5);
```


## 2. 对数和指数

```sql
SELECT LOG(100), LOG2(1024), LOG10(1000), LN(2.718281828), EXP(1);
```


## 3. 三角函数

```sql
SELECT SIN(PI()/2), COS(0), TAN(PI()/4);
SELECT ASIN(1), ACOS(0), ATAN(1), ATAN2(1, 1);
SELECT DEGREES(PI()), RADIANS(180);
```


## 4. 随机数

```sql
SELECT RAND(), RAND(42);     -- 可选种子
SELECT FLOOR(RAND() * 100);  -- 0-99 随机整数
```


## 5. 对引擎开发者的启示

数学函数是 SQL 引擎中最标准化的部分
MariaDB/MySQL 的数学函数与 SQL 标准和其他引擎高度一致
实现通常直接映射到 C 标准库 (libm) 的对应函数
精度注意: DOUBLE 类型的浮点精度问题在所有引擎中都存在
DECIMAL 精确运算: 需要实现任意精度算术库 (MariaDB 内部使用 decimal 类型)
