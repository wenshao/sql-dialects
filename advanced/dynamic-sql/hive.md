# Hive: 动态 SQL (无原生支持)

> 参考资料:
> - [1] Apache Hive Language Manual
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual
> - [2] Apache Hive - Variable Substitution
>   https://cwiki.apache.org/confluence/display/Hive/LanguageManual+VariableSubstitution


## 1. Hive 不支持服务端动态 SQL

 Hive 没有 PREPARE/EXECUTE、EXECUTE IMMEDIATE 或存储过程。
 这是有意的架构决策:

 为什么 Hive 不需要动态 SQL?
### 1. 编译模型: HiveQL 编译为 MapReduce/Tez/Spark DAG，不是解释执行

    动态生成并编译 MR/Tez 作业的代价远高于 RDBMS 的 PREPARE/EXECUTE
### 2. 批处理定位: Hive 作业是预定义的 ETL 流水线，不是交互式即席查询

    SQL 在提交前已经确定（调度工具中配置好的 SQL 模板）
### 3. 安全性: 动态 SQL 是 SQL 注入的主要入口，批处理引擎没有这个风险面


## 2. 变量替换: hivevar / hiveconf

Hive 提供客户端级别的变量替换（不是服务端动态 SQL）

设置变量

```sql
SET hivevar:target_date=2024-01-15;
SET hivevar:min_age=18;
SET hivevar:table_name=users;

```

使用变量

```sql
SELECT * FROM ${hivevar:table_name}
WHERE age > ${hivevar:min_age} LIMIT 10;

```

hiveconf 系统变量

```sql
SET hiveconf:mapreduce.job.reduces=10;

```

 命令行传入变量:
 hive --hivevar target_date=2024-01-15 -f daily_report.sql
 beeline --hivevar target_date=2024-01-15 -f daily_report.sql

 设计分析: 变量替换 vs 动态 SQL
 变量替换是文本级别的替换（类似 C 的 #define），发生在 SQL 解析之前。
 这意味着:
### 1. 不能动态生成表名/列名然后执行（虽然变量可以替换文本）

### 2. 不能根据查询结果决定下一步 SQL（无控制流）

### 3. 安全性好: 变量值在解析前替换，无 SQL 注入风险

### 4. 足够应对大多数参数化场景（日期参数、表名参数等）


## 3. 应用层动态 SQL: Python (PyHive)

 from pyhive import hive
 conn = hive.connect('localhost')
 cursor = conn.cursor()

 # 参数化查询
 table = 'users'
 min_age = 18
 cursor.execute(f'SELECT * FROM {table} WHERE age > %s', (min_age,))

 # 动态建表
 for date in date_list:
     cursor.execute(f"""
         INSERT OVERWRITE TABLE results PARTITION (dt='{date}')
         SELECT * FROM source WHERE dt = '{date}'
     """)

## 4. 应用层动态 SQL: Java (JDBC)

 Connection conn = DriverManager.getConnection("jdbc:hive2://host:10000/default");
 Statement stmt = conn.createStatement();

 // 动态生成并执行 SQL
 String table = "users";
 String sql = "SELECT COUNT(*) FROM " + table + " WHERE age > ?";
 PreparedStatement pstmt = conn.prepareStatement(sql);
 pstmt.setInt(1, 18);
 ResultSet rs = pstmt.executeQuery();

## 5. 应用层动态 SQL: Spark SQL

 // Spark 中使用 Hive 表
 val tables = spark.sql("SHOW TABLES").collect()
 tables.foreach { row =>
   val tableName = row.getString(1)
   spark.sql(s"ANALYZE TABLE $tableName COMPUTE STATISTICS")
 }

## 6. HPL/SQL: 过程式扩展 (Hive 2.0+)

 HPL/SQL 是 Hive 的过程式语言扩展，提供类似 PL/SQL 的动态 SQL 能力。
 但使用不广泛，大多数团队选择外部编排。

 hplsql -f dynamic_etl.sql
 示例 HPL/SQL:
 DECLARE v_table STRING;
 SET v_table = 'users';
EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || v_table;

## 7. 跨引擎对比: 动态 SQL 能力

 引擎          动态 SQL 能力                设计理由
 MySQL         PREPARE/EXECUTE              OLTP 需要动态查询
 PostgreSQL    EXECUTE (PL/pgSQL)           存储过程中的动态 SQL
 Oracle        EXECUTE IMMEDIATE (PL/SQL)   企业应用的核心需求
 Hive          无（变量替换 + 外部编排）    批处理不需要服务端动态 SQL
 Spark SQL     DataFrame API / sql()        编程语言级别的动态性
 BigQuery      Scripting (2019+)            EXECUTE IMMEDIATE
 Trino         无                           查询引擎，不支持过程式
 Flink SQL     无                           流处理由框架编排
 MaxCompute    无（类似 Hive）              批处理外部编排

## 8. 对引擎开发者的启示

### 1. 批处理引擎不需要服务端动态 SQL: Hive 证明了变量替换 + 外部编排

    可以满足所有批处理 ETL 需求
### 2. 变量替换应该是基本能力: 即使不支持动态 SQL，参数化查询是必须的

### 3. 大数据引擎的"动态 SQL"在 API 层: Spark DataFrame API / Flink Table API

    提供了比 SQL 字符串拼接更安全、更强大的动态查询构建能力
### 4. BigQuery 的 Scripting 是一个有趣的折中: 在分析引擎中加入过程式能力

但保持简单（变量、IF/ELSE、LOOP），不尝试复制 PL/SQL 的完整功能

