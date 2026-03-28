# Spark SQL: Dynamic SQL (动态 SQL)

> 参考资料:
> - [1] Spark SQL Reference
>   https://spark.apache.org/docs/latest/sql-ref.html
> - [2] Spark SQL - Parameterized Queries
>   https://spark.apache.org/docs/latest/sql-ref-syntax-qry-select-hints.html


## 1. 核心设计: Spark SQL 不支持服务端动态 SQL


 Spark SQL 没有 EXECUTE IMMEDIATE、PREPARE/EXECUTE、动态游标等机制。
 根本原因: Spark SQL 是声明式查询引擎，不是过程式编程环境。
 所有"动态"逻辑都在应用层（PySpark/Scala/Java）完成。

 这是 Spark SQL 最大的设计差异之一——SQL 只负责查询，程序逻辑在宿主语言中。

 对比:
   MySQL:      PREPARE stmt FROM '...'; EXECUTE stmt USING @var;
   PostgreSQL: EXECUTE format('SELECT * FROM %I', table_name);（PL/pgSQL）
   Oracle:     EXECUTE IMMEDIATE 'SELECT ...' INTO var;（PL/SQL）
   SQL Server: sp_executesql N'SELECT ...', N'@id INT', @id = 1;
   Hive:       无动态 SQL（与 Spark 同理）
   Flink SQL:  无动态 SQL（计算引擎，非过程式环境）
   Trino:      无动态 SQL（纯查询引擎）
   MaxCompute: 通过 SCRIPT 模式或 PyODPS 实现动态 SQL

 对引擎开发者的启示:
   动态 SQL 本质上需要过程式编程能力（变量、控制流、字符串拼接）。
   Spark 选择不在 SQL 层提供这些能力，而是让用户通过 DataFrame API 实现。
   这降低了 SQL 引擎的复杂度，但增加了用户的编程门槛。
   如果你的引擎面向数据工程师（会写代码），Spark 的做法是合理的。
   如果面向业务分析师（纯 SQL），需要考虑提供过程式扩展（如 BigQuery 的 Scripting）。

## 2. 应用层替代: PySpark / Scala


 PySpark 动态 SQL 示例:
 table_name = "users"
 filter_col = "age"
 min_val = 18
 df = spark.sql(f"SELECT * FROM {table_name} WHERE {filter_col} > {min_val}")

 DataFrame API 替代动态 SQL（推荐，类型安全）:
 from pyspark.sql.functions import col
 df = spark.table("users").filter(col("age") > 18)

 动态表名/列名选择:
 tables = ["users", "orders", "products"]
 for t in tables:
     count = spark.sql(f"SELECT COUNT(*) FROM {t}").collect()[0][0]
     print(f"{t}: {count} rows")

 动态构建复杂查询:
 conditions = ["age > 18", "status = 1", "city = 'Beijing'"]
 where_clause = " AND ".join(conditions)
 df = spark.sql(f"SELECT * FROM users WHERE {where_clause}")

## 3. 参数化查询（Spark 3.4+）


 Spark 3.4+ 引入了参数化查询，部分解决了 SQL 注入风险:
 spark.sql("SELECT * FROM users WHERE age > :min_age AND city = :city",
           args={"min_age": 18, "city": "Beijing"})

 设计分析:
   参数化查询的引入标志着 Spark SQL 开始关注"安全的动态查询"。
   但参数只能替换值（不能替换表名、列名、关键字），因此不等于完整的动态 SQL。
   这与 JDBC PreparedStatement 的限制完全相同——参数只能在值位置使用。

 对比:
   MySQL:      ? 占位符 + PreparedStatement
   PostgreSQL: $1, $2 占位符 + PREPARE
   BigQuery:   @param 命名参数
   Spark:      :param 命名参数（3.4+），仅在 spark.sql() API 中可用

## 4. Hive 变量替换（兼容模式）


```sql
SET spark.sql.variable.substitute=true;
SET hivevar:table_name=users;
SELECT * FROM ${hivevar:table_name} LIMIT 10;

```

 这是 Hive 遗留语法，Spark 为兼容性保留。
 变量在 SQL 解析前做文本替换（类似 shell 的 $VAR），有 SQL 注入风险。
 不推荐在生产环境使用——优先使用参数化查询或 DataFrame API。

## 5. IDENTIFIER 子句（Spark 4.0+）


 Spark 4.0 引入 IDENTIFIER() 子句，允许动态指定表名和列名:
 SELECT * FROM IDENTIFIER(:table_name) WHERE IDENTIFIER(:col_name) > :min_val;

 这是 Spark SQL 向"安全动态 SQL"迈出的重要一步:
   解决了参数化查询不能替换标识符（表名/列名）的限制
   同时保持了 SQL 注入安全性（IDENTIFIER 只接受合法标识符）

## 6. 实战模式: DataFrame API 构建动态查询


 模式 1: 动态过滤条件
 from pyspark.sql import functions as F
 filters = {"age": (">=", 18), "status": ("=", 1)}
 df = spark.table("users")
 for col_name, (op, val) in filters.items():
     df = df.filter(F.expr(f"{col_name} {op} {val}"))

 模式 2: 动态聚合
 agg_cols = ["amount", "quantity"]
 agg_exprs = [F.sum(c).alias(f"total_{c}") for c in agg_cols]
 df = spark.table("orders").groupBy("category").agg(*agg_exprs)

 模式 3: 动态 PIVOT
 pivot_values = spark.sql("SELECT DISTINCT quarter FROM sales").collect()
 quarters = [row.quarter for row in pivot_values]
 df = spark.table("sales").groupBy("product").pivot("quarter", quarters).sum("amount")

## 7. 版本演进

Spark 2.0: Hive 变量替换（兼容模式）
Spark 3.4: 参数化查询（:param 语法）
Spark 4.0: IDENTIFIER 子句（动态标识符）

限制:
无 PREPARE / EXECUTE / EXECUTE IMMEDIATE
无存储过程中的动态 SQL
参数化查询仅在 spark.sql() API 中可用（不能在 Spark Thrift Server SQL 中直接用）
Hive 变量替换是文本替换，有安全风险
IDENTIFIER 子句仅 Spark 4.0+

