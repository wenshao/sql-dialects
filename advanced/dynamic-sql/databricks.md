# Databricks: Dynamic SQL

> 参考资料:
> - [Databricks SQL Reference - EXECUTE IMMEDIATE](https://docs.databricks.com/en/sql/language-manual/sql-ref-syntax-aux-execute-immediate.html)


## EXECUTE IMMEDIATE (Databricks SQL)

```sql
EXECUTE IMMEDIATE 'SELECT * FROM users WHERE id = 1';
```


使用变量
```sql
DECLARE sql_text STRING;
SET VAR sql_text = 'SELECT COUNT(*) FROM users';
EXECUTE IMMEDIATE sql_text;
```


## EXECUTE IMMEDIATE ... USING (参数化)

```sql
EXECUTE IMMEDIATE 'SELECT * FROM users WHERE age > ? AND status = ?'
    USING 18, 'active';
```


命名参数
```sql
EXECUTE IMMEDIATE 'SELECT * FROM users WHERE age > :min_age'
    USING 18 AS min_age;
```


## EXECUTE IMMEDIATE ... INTO

```sql
DECLARE cnt INT;
EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users WHERE age > ?' INTO cnt USING 18;
SELECT cnt;
```


## Python/PySpark 替代方案

# 在 Databricks Notebooks 中
table_name = "users"
result = spark.sql(f"SELECT COUNT(*) FROM {table_name}")

# 参数化查询
spark.sql("SELECT * FROM users WHERE age > {min_age}", min_age=18)

版本说明：
Databricks SQL  : EXECUTE IMMEDIATE 支持
Databricks Runtime 14.0+ : SQL 变量 DECLARE/SET VAR
注意：也可在 Python/Scala notebooks 中使用 spark.sql() 实现动态 SQL
限制：不支持传统的 PREPARE / DEALLOCATE
