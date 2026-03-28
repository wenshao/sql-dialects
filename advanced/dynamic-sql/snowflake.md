# Snowflake: 动态 SQL

> 参考资料:
> - [1] Snowflake Documentation - EXECUTE IMMEDIATE
>   https://docs.snowflake.com/en/sql-reference/sql/execute-immediate
> - [2] Snowflake Documentation - Snowflake Scripting
>   https://docs.snowflake.com/en/developer-guide/snowflake-scripting/


## 1. 基本语法: EXECUTE IMMEDIATE


直接执行 SQL 字符串

```sql
EXECUTE IMMEDIATE 'SELECT * FROM users WHERE id = 1';
EXECUTE IMMEDIATE 'CREATE TABLE test_tbl (id INT, name VARCHAR(100))';

```

参数化执行（使用 ? 占位符 + USING）

```sql
EXECUTE IMMEDIATE 'SELECT * FROM users WHERE age > ? AND status = ?'
    USING (18, 'active');

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 EXECUTE IMMEDIATE vs PREPARE/EXECUTE

 Snowflake 不支持 PREPARE / DEALLOCATE 模式:
   传统数据库: PREPARE stmt FROM '...'; EXECUTE stmt USING @var;
   Snowflake:  EXECUTE IMMEDIATE '...' USING (...);

 设计理由:
   PREPARE/EXECUTE 是为了重复执行相同查询时复用解析结果。
   在 Snowflake 的云原生架构中，Services 层有全局查询缓存:
   相同 SQL 文本自动命中缓存的执行计划，无需显式 PREPARE。

 对比:
   MySQL:      PREPARE / EXECUTE / DEALLOCATE
   PostgreSQL: PREPARE / EXECUTE / DEALLOCATE
   Oracle:     EXECUTE IMMEDIATE（动态 PL/SQL，语法最接近 Snowflake）
   SQL Server: sp_executesql @sql, @params（参数化最优雅）
   BigQuery:   EXECUTE IMMEDIATE（与 Snowflake 一致）
   Redshift:   EXECUTE（在 PL/pgSQL 中）

 对引擎开发者的启示:
   如果引擎有全局执行计划缓存，PREPARE/EXECUTE 的价值降低。
   Oracle 和 Snowflake 选择 EXECUTE IMMEDIATE 作为唯一接口是合理的。

### 2.2 USING 子句的 SQL 注入防护

 EXECUTE IMMEDIATE '...' USING (...) 使用参数化绑定，防止 SQL 注入
 但表名/列名无法参数化（只能拼接字符串），需要额外验证:
sql_text := 'SELECT * FROM ' || p_table;  -- 存在注入风险!
 建议: 使用 IDENTIFIER() 函数或白名单验证表名

## 3. Snowflake Scripting 中的动态 SQL


### 3.1 EXECUTE IMMEDIATE ... INTO（将结果绑定到变量）

```sql
CREATE OR REPLACE PROCEDURE count_table(p_table VARCHAR)
RETURNS INTEGER
LANGUAGE SQL
AS
$$
DECLARE
    row_count INTEGER;
    sql_text VARCHAR;
BEGIN
    sql_text := 'SELECT COUNT(*) FROM ' || p_table;
    EXECUTE IMMEDIATE sql_text INTO :row_count;
    RETURN row_count;
END;
$$;

CALL count_table('users');

```

### 3.2 参数化动态 SQL

```sql
CREATE OR REPLACE PROCEDURE get_user_count(p_status VARCHAR)
RETURNS INTEGER
LANGUAGE SQL
AS
$$
DECLARE
    cnt INTEGER;
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM users WHERE status = ?'
        INTO :cnt
        USING (p_status);
    RETURN cnt;
END;
$$;

```

### 3.3 返回结果集的动态 SQL (RESULTSET)

```sql
CREATE OR REPLACE PROCEDURE dynamic_query(p_table VARCHAR, p_limit INTEGER)
RETURNS TABLE()
LANGUAGE SQL
AS
$$
DECLARE
    res RESULTSET;
    sql_text VARCHAR;
BEGIN
    sql_text := 'SELECT * FROM ' || p_table || ' LIMIT ' || p_limit::VARCHAR;
    res := (EXECUTE IMMEDIATE :sql_text);
    RETURN TABLE(res);
END;
$$;

```

 对比 RESULTSET 设计:
   Oracle:     SYS_REFCURSOR + OPEN ... FOR dynamic_sql
   PostgreSQL: RETURN QUERY EXECUTE dynamic_sql
   SQL Server: sp_executesql + OUTPUT 参数
   Snowflake RESULTSET 语法更简洁，但不支持游标遍历

## 4. JavaScript 存储过程中的动态 SQL


```sql
CREATE OR REPLACE PROCEDURE dynamic_js(table_name VARCHAR)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
AS
$$
    var sql = "SELECT COUNT(*) AS CNT FROM " + TABLE_NAME;
    var stmt = snowflake.createStatement({sqlText: sql});
    var rs = stmt.execute();
    rs.next();
    return 'Row count: ' + rs.getColumnValue(1);
$$;

```

 JavaScript API: snowflake.createStatement() + stmt.execute()
 这是 Snowflake 最早支持的存储过程语言（2018）
 优点: JavaScript 擅长字符串处理和 JSON 操作
 缺点: 与 SQL Scripting 相比，语法更繁琐

## 5. Python 存储过程中的动态 SQL


 CREATE OR REPLACE PROCEDURE dynamic_py(table_name VARCHAR)
 RETURNS VARCHAR
 LANGUAGE PYTHON
 RUNTIME_VERSION = '3.8'
 PACKAGES = ('snowflake-snowpark-python')
 HANDLER = 'run'
 AS $$
 def run(session, table_name):
     df = session.sql(f"SELECT COUNT(*) AS cnt FROM {table_name}")
     return str(df.collect()[0][0])
 $$;
 session.sql() 是 Snowpark 的动态 SQL 接口

## 6. 多语言动态 SQL 对比

语言       | 动态 SQL 接口                    | 参数化  | 返回结果集
SQL Script | EXECUTE IMMEDIATE ... USING      | ? 占位  | RESULTSET
JavaScript | snowflake.createStatement()       | binds[] | ResultSet
Python     | session.sql()                     | f-string| DataFrame
Java       | session.sql()                     | 同上    | DataFrame

 对引擎开发者的启示:
   多语言存储过程是现代云数仓的趋势（Snowflake/BigQuery/Databricks 均支持）。
   每种语言需要独立的 SQL 执行 API，这增加了引擎的接口复杂度。
   SQL Script 的 EXECUTE IMMEDIATE 最轻量（引擎内部直接调用解析器）；
   JavaScript/Python 需要嵌入语言运行时 + SQL 网关。

## 横向对比: 动态 SQL 能力矩阵

| 能力             | Snowflake          | BigQuery    | Oracle        | PostgreSQL |
|------|------|------|------|------|
| 基本执行         | EXECUTE IMMEDIATE  | EXECUTE IMM | EXECUTE IMM   | EXECUTE |
| 参数化           | USING (?)          | USING       | USING         | $1, $2 |
| 返回结果集       | RESULTSET          | 不支持      | SYS_REFCURSOR | RETURN QUERY |
| PREPARE/EXECUTE  | 不支持             | 不支持      | 不支持(PL/SQL)| 支持 |
| 多语言支持       | SQL/JS/Python/Java | SQL/JS/Py   | PL/SQL/Java   | PL/pgSQL |
| 防注入           | USING 参数化       | USING       | USING         | USING/format |

