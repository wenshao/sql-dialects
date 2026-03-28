# Spark SQL: 存储过程与函数 (Stored Procedures & Functions)

> 参考资料:
> - [1] Spark SQL - UDF
>   https://spark.apache.org/docs/latest/sql-ref-functions-udf-scalar.html
> - [2] Spark SQL - SQL Functions
>   https://spark.apache.org/docs/latest/sql-ref-syntax-ddl-create-function.html
> - [3] Pandas UDF
>   https://spark.apache.org/docs/latest/api/python/user_guide/sql/arrow_pandas.html


## 1. 核心设计: Spark SQL 不支持存储过程


 Spark SQL 没有 CREATE PROCEDURE、CALL、DECLARE、BEGIN...END 等过程式语法。
 根本原因: Spark SQL 是声明式查询引擎，过程式逻辑在宿主语言（Python/Scala/Java）中实现。

 这是一个重大的设计取舍:
   优势: SQL 引擎简单、可预测；业务逻辑在通用编程语言中更灵活
   劣势: 纯 SQL 用户无法编写复杂逻辑；迁移传统数据库的存储过程困难

 对比:
   MySQL:      完整存储过程（CREATE PROCEDURE + IF/WHILE/CURSOR + SIGNAL）
   PostgreSQL: PL/pgSQL（功能最强大的过程式扩展）
   Oracle:     PL/SQL（最成熟的过程式语言，包含包、类型、异常处理）
   SQL Server: T-SQL（IF/WHILE/TRY-CATCH + 丰富的系统过程）
   BigQuery:   BigQuery Scripting（DECLARE/SET/IF/WHILE/FOR + BEGIN/END）
   Hive:       无存储过程
   Flink SQL:  无存储过程
   Trino:      无存储过程
   MaxCompute: 通过 Script Mode 提供有限的过程式能力

## 2. SQL UDF: 纯 SQL 函数（Spark 3.4+）


标量函数

```sql
CREATE TEMPORARY FUNCTION add_numbers(a INT, b INT)
    RETURNS INT
    RETURN a + b;

SELECT add_numbers(3, 5);                              -- 8

```

CASE 表达式函数

```sql
CREATE TEMPORARY FUNCTION classify_age(age INT)
    RETURNS STRING
    RETURN CASE
        WHEN age < 18 THEN 'minor'
        WHEN age < 65 THEN 'adult'
        ELSE 'senior'
    END;

SELECT classify_age(25);                               -- 'adult'

```

表值函数（Table-Valued Function, Spark 3.4+）

```sql
CREATE TEMPORARY FUNCTION active_users(min_age INT)
    RETURNS TABLE (id BIGINT, username STRING, age INT)
    RETURN SELECT id, username, age FROM users WHERE status = 1 AND age >= min_age;

SELECT * FROM active_users(25);

```

 设计分析:
   SQL UDF 是 Spark SQL 向过程式编程迈出的一步，但能力有限:
   - 只支持单表达式 RETURN（不能有多条语句）
   - 不能声明变量、不能有控制流（IF/WHILE）
   - 不能做 DML（INSERT/UPDATE/DELETE）
   这与 BigQuery 的 UDF 限制类似，本质上是"命名的查询片段"而非"存储过程"。

## 3. Java/Scala UDF（通过 JAR 注册）


注册 JAR 中的 UDF

```sql
CREATE TEMPORARY FUNCTION classify_age AS
    'com.example.ClassifyAge'
    USING JAR '/path/to/udf.jar';

```

持久化函数（存储在 Hive Metastore 中）

```sql
CREATE FUNCTION mydb.classify_age AS
    'com.example.ClassifyAge'
    USING JAR '/path/to/udf.jar';

```

## 4. Python UDF（通过 PySpark 注册）


 注册 Python UDF（性能较差: 行逐行序列化到 Python 进程）:
 from pyspark.sql.functions import udf
 from pyspark.sql.types import StringType
 @udf(returnType=StringType())
 def classify(age):
     if age < 18: return 'minor'
     elif age < 65: return 'adult'
     else: return 'senior'
 spark.udf.register('classify_age', classify)
 之后在 SQL 中: SELECT classify_age(age) FROM users;

## 5. Pandas UDF: 向量化 Python UDF（推荐）


 Pandas UDF 通过 Apache Arrow 实现向量化，性能比普通 Python UDF 快 10-100 倍
 from pyspark.sql.functions import pandas_udf
 import pandas as pd
 @pandas_udf(DoubleType())
 def multiply(a: pd.Series, b: pd.Series) -> pd.Series:
     return a * b
 spark.udf.register('multiply', multiply)

 Pandas UDF 的性能优势来自:
1. Apache Arrow 列式内存格式: 零拷贝数据共享（JVM -> Python）

2. 向量化操作: Pandas/NumPy 在批量数据上比逐行 Python 快几个数量级

3. 减少序列化开销: Arrow 的列式布局天然适合批量传输


 对引擎开发者的启示:
   Python UDF 的性能瓶颈是 JVM<->Python 进程间的数据序列化。
   Apache Arrow 是解决这一问题的事实标准——DuckDB、Polars、DataFusion 都采用了 Arrow。
   如果你的引擎需要支持 Python UDF，Arrow 集成是必要的。

## 6. TRANSFORM（运行外部脚本）


Hive 兼容语法: 将数据通过 stdin/stdout 传递给外部脚本处理

```sql
SELECT TRANSFORM(username, age)
    USING 'python3 /path/to/script.py'
    AS (processed_name STRING, processed_age INT)
FROM users;

```

 TRANSFORM 的设计继承自 Hive，类似 Unix 管道的理念:
 将表数据序列化为文本 -> 通过 stdin 传给脚本 -> 脚本结果通过 stdout 返回
 灵活但性能差（文本序列化 + 进程间通信），不推荐用于大数据量

## 7. 视图作为"存储查询"（存储过程的部分替代）


```sql
CREATE OR REPLACE VIEW vip_users AS
SELECT u.*, SUM(o.amount) AS total_spent
FROM users u
JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.username, u.email, u.age
HAVING SUM(o.amount) > 10000;

```

## 8. 函数管理


```sql
DROP TEMPORARY FUNCTION IF EXISTS classify_age;
DROP FUNCTION IF EXISTS mydb.classify_age;

SHOW FUNCTIONS;
SHOW USER FUNCTIONS;
SHOW SYSTEM FUNCTIONS;
DESCRIBE FUNCTION classify_age;
DESCRIBE FUNCTION EXTENDED classify_age;

```

## 9. 版本演进

Spark 2.0: Java/Scala UDF, TRANSFORM
Spark 2.3: Pandas UDF（向量化）
Spark 3.0: 持久化函数改进
Spark 3.4: SQL UDF（RETURN 语法）, 表值函数
Spark 4.0: SQL UDF 增强

限制:
不支持 CREATE PROCEDURE / CALL（无过程式编程）
SQL UDF 仅支持单表达式 RETURN（无多语句、无控制流）
Python UDF 性能差（推荐 Pandas UDF）
TRANSFORM 使用文本序列化（性能瓶颈）
复杂多步逻辑必须在 PySpark/Scala 应用代码中实现

