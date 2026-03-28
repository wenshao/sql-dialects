# Apache Doris: 存储过程

 Apache Doris: 存储过程

 参考资料:
   [1] Doris Documentation
       https://doris.apache.org/docs/sql-manual/sql-statements/

## 1. 不支持存储过程: OLAP 引擎的架构选择

 Doris 不支持存储过程、用户自定义函数(SQL 定义)、触发器、游标。

 设计理由:
   存储过程的核心价值: 减少网络往返(逻辑在服务端执行)。
   OLAP 引擎的查询模式: 少量复杂 SQL(每条扫描大量数据)。
   存储过程在 OLAP 场景的价值极低——网络往返不是瓶颈，数据扫描才是。

 对比:
   StarRocks:  同样不支持(同源)
   ClickHouse: 不支持存储过程。支持 UDF(C++/SQL/Executable)
   BigQuery:   不支持传统存储过程。有 Scripting(DECLARE/SET/IF/LOOP)
   MySQL:      完整支持(CREATE PROCEDURE / FUNCTION)
   PostgreSQL: 最强的过程化支持(PL/pgSQL, PL/Python, PL/V8)

 对引擎开发者的启示:
   存储过程需要服务端维护执行状态(游标、变量、控制流)。
   这与 MPP 引擎的无状态计算节点设计冲突。
   替代方案: 外部调度(Airflow) + 多条 SQL 任务编排。

## 2. 替代方案: INSERT INTO ... SELECT (ETL)

```sql
INSERT INTO users_clean
SELECT id, TRIM(username), LOWER(email), COALESCE(age, 0)
FROM users_raw;

INSERT INTO users (id, username, email, age)
SELECT id, username, email, age FROM staging_users
WHERE updated_at > '2024-01-01';

```

## 3. 替代方案: CTAS (数据转换)

```sql
CREATE TABLE users_enriched AS
SELECT u.*, COUNT(o.id) AS order_count, SUM(o.amount) AS total_spend
FROM users u LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id, u.username, u.email, u.age;

```

## 4. 替代方案: 外部调度工具

 Apache Airflow / DolphinScheduler / Azkaban
 编排多个 SQL 任务，实现复杂 ETL 流程

## 5. Java UDF (2.0+)

 Doris 2.0+ 支持 Java UDF(用户自定义函数):
 CREATE FUNCTION my_add(INT, INT) RETURNS INT
 PROPERTIES ("file"="hdfs:///udf/my_udf.jar", "symbol"="com.example.MyAdd");
 不是存储过程，但可以扩展内置函数。

## 6. 会话变量 (替代过程变量)

```sql
SET exec_mem_limit = 8589934592;
SET query_timeout = 3600;
SET parallel_fragment_exec_instance_num = 8;

```
