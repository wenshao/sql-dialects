# Spark SQL: 错误处理 (Error Handling)

> 参考资料:
> - [1] Spark SQL - Error Conditions
>   https://spark.apache.org/docs/latest/sql-error-conditions.html
> - [2] Spark SQL - try_* Functions
>   https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html


## 1. 核心设计: Spark SQL 无过程式错误处理


 Spark SQL 不支持 TRY/CATCH、EXCEPTION WHEN、DECLARE HANDLER、SIGNAL 等语法。
 错误处理通过两条路径实现:
   (a) 应用层 API: PySpark/Scala 的 try-catch 捕获异常
   (b) SQL 层 try_* 函数: 将可能失败的操作转换为 NULL 返回

 设计理由:
   Spark SQL 是声明式查询引擎，不是过程式编程环境。
   错误处理需要控制流（if-then-else, loop, goto），这在纯 SQL 中不存在。
   Spark 的做法是: SQL 负责"避免错误"（try_* 函数），应用层负责"处理错误"。

 对比:
   MySQL:      存储过程中 DECLARE HANDLER FOR SQLEXCEPTION
   PostgreSQL: PL/pgSQL 中 EXCEPTION WHEN ... THEN ...
   Oracle:     PL/SQL 中 EXCEPTION WHEN ... THEN ...（最成熟的异常处理）
   SQL Server: TRY ... CATCH（最接近通用编程语言的语法）
   Hive:       无错误处理（与 Spark 同理）
   Flink SQL:  无错误处理（计算引擎）
   Trino:      无错误处理（查询引擎）
   BigQuery:   BigQuery Scripting 支持 BEGIN ... EXCEPTION ... END;

## 2. ANSI 模式: 错误行为的总开关


ANSI 模式决定了 Spark SQL 遇到问题时的行为:
ANSI=false (Spark 3.x 默认): 宽容模式，错误转为 NULL 或默认值
ANSI=true  (Spark 4.0 默认): 严格模式，错误抛出异常

示例对比:
1/0:              ANSI=false -> NULL,   ANSI=true -> ARITHMETIC_OVERFLOW 异常
CAST('abc' AS INT): ANSI=false -> NULL,  ANSI=true -> INVALID_FORMAT 异常
INT 溢出:          ANSI=false -> wrap,   ANSI=true -> ARITHMETIC_OVERFLOW 异常


```sql
SET spark.sql.ansi.enabled = true;              -- 启用严格模式
SET spark.sql.ansi.enabled = false;             -- 宽容模式

```

 对引擎开发者的启示:
   Spark 的 ANSI 模式演进（默认关闭 -> 4.0 默认开启）是一个教训:
   过于宽容的默认行为导致大量"隐式 bug"——用户以为计算成功，实际结果是错的。
   PostgreSQL 从一开始就严格执行类型检查，这是更好的设计选择。
   但 Spark 面临向后兼容性问题——大量存量代码依赖 ANSI=false 的行为。

## 3. try_* 安全函数: SQL 层错误避免


TRY_CAST: 类型转换失败返回 NULL 而非报错（Spark 3.0+）

```sql
SELECT TRY_CAST('abc' AS INT);                  -- NULL
SELECT TRY_CAST('2024-01-01' AS DATE);          -- 2024-01-01
SELECT TRY_CAST('2024-13-45' AS DATE);          -- NULL

```

try_divide: 除零返回 NULL（Spark 3.2+）

```sql
SELECT try_divide(10, 0);                        -- NULL
SELECT try_divide(10, 3);                        -- 3.333...

```

try_add / try_subtract / try_multiply: 溢出返回 NULL（Spark 3.2+）

```sql
SELECT try_add(2147483647, 1);                   -- NULL (INT 溢出)
SELECT try_subtract(-2147483648, 1);             -- NULL (INT 下溢)
SELECT try_multiply(2147483647, 2);              -- NULL (INT 溢出)

```

try_to_timestamp: 安全时间戳解析（Spark 3.4+）

```sql
SELECT try_to_timestamp('2024-13-01', 'yyyy-MM-dd');  -- NULL (月份无效)
SELECT try_to_timestamp('2024-01-15 10:30:00', 'yyyy-MM-dd HH:mm:ss'); -- OK

```

try_avg / try_sum: 聚合时忽略异常值（Spark 3.4+）

```sql
SELECT try_avg(CAST('NaN' AS DOUBLE));           -- NULL

```

 设计分析:
   try_* 函数族是 Spark SQL 错误避免的核心手段。设计灵感来自:
   - C# 的 Int32.TryParse()（返回 bool + out 参数）
   - PostgreSQL 社区长期讨论的 safe_cast 提案
   - BigQuery 的 SAFE_CAST / SAFE_DIVIDE 系列函数

   Spark 的 try_* 命名比 BigQuery 的 SAFE_ 前缀更一致，更容易发现。

## 4. Spark 错误分类体系（Spark 3.4+）


 Spark 3.4+ 引入了统一的错误分类（Error Classes），每个错误包含:
   errorClass:         错误类别（如 ARITHMETIC_OVERFLOW）
   messageParameters:  错误上下文参数
   queryContext:       出错的 SQL 片段
   sqlState:           SQL 标准状态码（如 22003）

 常见错误类:
   ARITHMETIC_OVERFLOW:       算术溢出
   DIVIDE_BY_ZERO:            除零错误
   INVALID_FORMAT:            格式错误（日期/数字解析）
   UNRESOLVED_COLUMN:         列名无法解析
   TABLE_OR_VIEW_NOT_FOUND:   表或视图不存在
   SCHEMA_NOT_COMPATIBLE:     Schema 不兼容
   PARTITION_NOT_FOUND:       分区不存在
   MALFORMED_RECORD:          数据格式损坏

## 5. 防御性 SQL 写法


IF NOT EXISTS 避免建表冲突

```sql
CREATE TABLE IF NOT EXISTS users (id INT, name STRING) USING DELTA;

```

COALESCE + TRY_CAST 处理脏数据

```sql
SELECT
    id,
    COALESCE(TRY_CAST(age_str AS INT), -1) AS age,
    COALESCE(TRY_CAST(price_str AS DOUBLE), 0.0) AS price
FROM raw_data;

```

CASE WHEN 替代可能失败的除法

```sql
SELECT
    id,
    CASE WHEN denom = 0 THEN NULL ELSE numer / denom END AS ratio
FROM measurements;

```

MERGE INTO 避免 INSERT/UPDATE 冲突

```sql
MERGE INTO users AS target
USING (SELECT 1 AS id, 'alice' AS name) AS source
ON target.id = source.id
WHEN MATCHED THEN UPDATE SET target.name = source.name
WHEN NOT MATCHED THEN INSERT (id, name) VALUES(source.id, source.name);

```

## 6. 应用层错误处理


 PySpark 异常分类:
 from pyspark.errors import (
     AnalysisException,           -- 编译/分析阶段（表不存在、列名错误）
     ParseException,              -- SQL 语法解析错误
     ArithmeticException,         -- 算术异常（ANSI 模式下除零等）
     SparkRuntimeException,       -- 运行时异常
 )
 try:
     spark.sql("SELECT * FROM nonexistent_table")
 except AnalysisException as e:
     print(f"Analysis error: {e.getErrorClass()}")

 Spark UI 诊断（http://driver-host:4040）:
   SQL 页面:       查看 SQL 执行计划和错误
   Jobs 页面:      查看作业失败原因和重试次数
   Executors 页面: 查看 OOM、任务失败等

## 7. 版本演进

Spark 3.0: TRY_CAST 引入
Spark 3.2: try_divide, try_add, try_subtract, try_multiply
Spark 3.3: 改进错误消息，新增 SQLSTATE 编码
Spark 3.4: 统一错误分类体系（Error Classes），try_to_timestamp
Spark 3.5: 增强错误诊断信息
Spark 4.0: ANSI 模式默认开启（最重大的行为变更）

限制:
无 TRY/CATCH、EXCEPTION WHEN、DECLARE HANDLER、SIGNAL 语法
try_* 函数只能避免特定类型的错误（类型转换、算术溢出）
通用错误处理完全依赖应用层 API（PySpark/Scala）
ANSI 模式切换可能导致存量查询行为变化

