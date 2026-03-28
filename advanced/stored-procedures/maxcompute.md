# MaxCompute (ODPS): 存储过程与 UDF

> 参考资料:
> - [1] MaxCompute SQL - Script Mode
>   https://help.aliyun.com/zh/maxcompute/user-guide/script-mode
> - [2] MaxCompute UDF
>   https://help.aliyun.com/zh/maxcompute/user-guide/overview-of-udfs


## 1. MaxCompute 不支持传统存储过程 —— 设计决策


 为什么批处理引擎不需要传统存储过程?
   存储过程的核心价值: 服务端逻辑封装 + 减少网络往返
   MaxCompute 的场景: 提交 SQL 作业 → 分布式执行 → 返回结果
     没有"会话"概念（每个 SQL 是独立作业）
     没有"游标"概念（不逐行处理）
     没有"事务块"概念（不支持 BEGIN/COMMIT）
   因此传统 PL/SQL / PL/pgSQL 的模型不适用

   对比:
     PostgreSQL: PL/pgSQL（功能最完整的存储过程语言）
     Oracle:     PL/SQL（商业引擎中最成熟）
     MySQL:      存储过程（功能有限但够用）
     BigQuery:   Scripting（2020+，多语句脚本模式）
     Snowflake:  Stored Procedures（JavaScript/Python/SQL）
     Hive:       不支持存储过程（与 MaxCompute 相同）

 MaxCompute 的替代方案:
1. Script Mode（脚本模式）—— 多语句 SQL

2. UDF（用户定义函数）—— 行级逻辑扩展

3. DataWorks 调度 —— 工作流编排


## 2. Script Mode（脚本模式，2.0+）


变量声明和使用

```sql
SET @today = TO_CHAR(GETDATE(), 'yyyyMMdd');
SET @yesterday = TO_CHAR(DATEADD(GETDATE(), -1, 'dd'), 'yyyyMMdd');

```

多语句执行（在同一个 Script 中顺序执行）

```sql
INSERT OVERWRITE TABLE daily_orders PARTITION (dt = @yesterday)
SELECT user_id, SUM(amount) AS total
FROM orders WHERE dt = @yesterday
GROUP BY user_id;

INSERT OVERWRITE TABLE daily_summary PARTITION (dt = @yesterday)
SELECT COUNT(*) AS cnt, SUM(total) AS grand_total
FROM daily_orders WHERE dt = @yesterday;

```

 Script Mode 的限制:
   变量只支持常量赋值（不能 SET @x = SELECT COUNT(*) FROM t）
   不支持 IF/ELSE 条件分支
   不支持 LOOP/WHILE 循环
   不支持 EXCEPTION 异常处理
   变量不能用于表名替换（不是真正的动态 SQL）

   对比 BigQuery Scripting:
     SET var = (SELECT COUNT(*) FROM t);  -- BigQuery 支持查询赋值
     IF condition THEN ... END IF;        -- BigQuery 支持条件
     WHILE condition DO ... END WHILE;    -- BigQuery 支持循环

## 3. UDF（用户定义函数）—— 主要的逻辑扩展方式


### 3.1 SQL UDF（内联函数，最简单）

```sql
CREATE FUNCTION my_add(@a BIGINT, @b BIGINT) AS @a + @b;
SELECT my_add(1, 2);                       -- 3
DROP FUNCTION IF EXISTS my_add;

```

### 3.2 Java UDF（最常用的扩展方式）

步骤: 编写 Java 类 → 打包 JAR → 上传 → 注册

```sql
ADD JAR my_functions.jar;
CREATE FUNCTION my_lower AS 'com.example.udf.Lower' USING 'my_functions.jar';
SELECT my_lower(username) FROM users;

```

### 3.3 Python UDF（Python 3 推荐）

```sql
CREATE FUNCTION my_len AS 'my_udf.py.my_len' USING 'my_udf.py';

```

 UDF 的三种类型:
   UDF:  标量函数（一行输入 → 一个值输出）
   UDTF: 表生成函数（一行输入 → 多行输出）
   UDAF: 聚合函数（多行输入 → 一个值输出）

### 3.4 UDTF（表生成函数）

```sql
CREATE FUNCTION my_explode AS 'com.example.udtf.Explode' USING 'my_functions.jar';
SELECT u.id, t.tag
FROM users u
LATERAL VIEW my_explode(u.tags) t AS tag;

```

### 3.5 UDAF（聚合函数）

```sql
CREATE FUNCTION my_median AS 'com.example.udaf.Median' USING 'my_functions.jar';
SELECT my_median(age) FROM users;

```

## 4. TRANSFORM —— 调用外部脚本


```sql
SELECT TRANSFORM(id, username, email)
USING 'python my_script.py'
AS (new_id, new_username, processed_email)
FROM users;

```

 TRANSFORM 的工作原理:
1. 将输入行序列化为 TSV 格式

2. 通过 stdin 传递给外部脚本

3. 脚本处理后通过 stdout 输出

4. MaxCompute 读取输出并反序列化


   适用: 复杂的数据处理逻辑（NLP、ML 推理等）
   限制: 性能不如 UDF（进程间通信开销）

## 5. DataWorks 调度 —— 替代存储过程的工作流


 DataWorks 是 MaxCompute 的调度和编排平台
 实现存储过程的等价功能:

 工作流示例:
   节点 1 (SQL): INSERT OVERWRITE TABLE staging ... SELECT ...
   节点 2 (数据质量检查): 检查 staging 表行数波动
   节点 3 (SQL): INSERT OVERWRITE TABLE target ... SELECT ... FROM staging
   节点 4 (通知): 发送成功/失败通知

 DataWorks 优势:
   可视化 DAG 编排
   内置调度（cron 表达式）
   数据质量监控集成
   跨项目依赖管理
   失败重试和告警

## 6. 横向对比: 服务端逻辑能力


 存储过程:
MaxCompute: 不支持         | Oracle: PL/SQL（最强大）
Hive:       不支持         | PostgreSQL: PL/pgSQL
BigQuery:   Scripting      | Snowflake: JavaScript/Python/SQL 存储过程
MySQL:      支持           | SQL Server: T-SQL

 脚本模式:
MaxCompute: Script Mode（变量+多语句） | BigQuery: Scripting（完整控制流）
Snowflake:  Scripting（完整控制流）    | Hive: Beeline 脚本

 UDF 语言:
MaxCompute: Java/Python    | BigQuery: JavaScript/SQL
Snowflake:  Java/Python/JavaScript/Scala | Hive: Java
PostgreSQL: C/Python/Perl/TCL/PL/pgSQL   | ClickHouse: C++

## 7. 对引擎开发者的启示


1. Script Mode 是批处理引擎的务实折中 — 不需要完整存储过程

2. UDF（Java/Python）是最灵活的扩展方式 — 应优先投资

3. BigQuery Scripting 证明了批处理引擎可以支持控制流（IF/WHILE）

4. DataWorks 类调度平台替代了存储过程的编排功能

5. TRANSFORM 类外部脚本调用是重要的逃生通道（当 SQL 无法表达时）

6. UDF 的沙箱安全（内存限制、CPU 限制、网络隔离）是必须的

