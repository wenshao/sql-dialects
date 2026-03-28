# Snowflake: 错误处理

> 参考资料:
> - [1] Snowflake Documentation - Exception Handling
>   https://docs.snowflake.com/en/developer-guide/snowflake-scripting/exceptions
> - [2] Snowflake Documentation - RAISE
>   https://docs.snowflake.com/en/sql-reference/snowflake-scripting/raise


## 1. 基本语法: EXCEPTION WHEN


```sql
CREATE OR REPLACE PROCEDURE safe_divide(a FLOAT, b FLOAT)
RETURNS FLOAT
LANGUAGE SQL
AS
$$
DECLARE
    result FLOAT;
BEGIN
    result := a / b;
    RETURN result;
EXCEPTION
    WHEN EXPRESSION_ERROR THEN
        RETURN NULL;
    WHEN OTHER THEN
        RAISE;                   -- 重新抛出未处理的异常
END;
$$;

```

## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 异常处理模型: PL/SQL 风格

 Snowflake Scripting (2021+) 的异常处理借鉴了 Oracle PL/SQL 的设计:
   BEGIN ... EXCEPTION WHEN ... THEN ... END;

 但比 PL/SQL 大幅简化:
   PL/SQL: ~20+ 预定义异常 (NO_DATA_FOUND, TOO_MANY_ROWS, DUP_VAL_ON_INDEX...)
   Snowflake: 仅 3 种内置异常类型:
     EXPRESSION_ERROR  — 表达式求值错误（除零、类型转换失败等）
     STATEMENT_ERROR   — SQL 语句执行错误（表不存在、语法错误等）
     OTHER             — 所有其他错误（catch-all）

 设计 trade-off:
   简化: 3 种异常类型覆盖 99% 场景，学习成本极低
   不足: 无法精确区分错误类型（如区分"表不存在"和"列不存在"）
         需要通过 SQLCODE 判断具体错误

 对比:
   Oracle PL/SQL: 异常体系最完善，20+ 预定义异常 + PRAGMA EXCEPTION_INIT
   PostgreSQL:    EXCEPTION WHEN division_by_zero / unique_violation / ...
                  支持 SQLSTATE 条件（如 '23505' = unique_violation）
   SQL Server:    TRY...CATCH + ERROR_NUMBER() / ERROR_MESSAGE()
   MySQL:         DECLARE HANDLER FOR SQLSTATE / SQLEXCEPTION
   BigQuery:      脚本中 BEGIN...EXCEPTION WHEN ERROR THEN（也只有一种通用异常）

 对引擎开发者的启示:
   异常类型粒度是设计权衡: 太粗导致错误处理不精确，太细增加学习成本。
   Snowflake 的 3 种 + SQLCODE 组合是一个实用的折中。
   BigQuery 更激进: 只有一种 ERROR 异常类型。

## 3. RAISE: 抛出异常


```sql
CREATE OR REPLACE PROCEDURE validate_input(amount FLOAT)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    my_exception EXCEPTION (-20001, 'Amount must be positive');
BEGIN
    IF (amount <= 0) THEN
        RAISE my_exception;
    END IF;
    RETURN 'Valid';
EXCEPTION
    WHEN my_exception THEN
        RETURN 'Error: ' || SQLERRM;
END;
$$;

```

 自定义异常声明:
   DECLARE exc_name EXCEPTION (error_code, 'error_message');
 error_code: 用户自定义错误码（负数，通常 -20000 到 -20999）
 这与 Oracle 的 RAISE_APPLICATION_ERROR(-20001, 'msg') 类似

## 4. SQLCODE / SQLERRM / SQLSTATE


```sql
CREATE OR REPLACE PROCEDURE error_info_demo()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    SELECT * FROM nonexistent_table;
    RETURN 'OK';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'SQLCODE=' || SQLCODE ||
               ' SQLERRM=' || SQLERRM ||
               ' SQLSTATE=' || SQLSTATE;
END;
$$;

```

 SQLCODE:  数字错误码（Snowflake 内部定义）
 SQLERRM:  错误消息文本
 SQLSTATE: 5 字符 SQL 标准状态码（如 '42S02' = 表不存在）

 对比:
   Oracle:      SQLCODE + SQLERRM（与 Snowflake 最一致）
   PostgreSQL:  SQLSTATE + SQLERRM + GET DIAGNOSTICS
   SQL Server:  ERROR_NUMBER() + ERROR_MESSAGE() + ERROR_STATE()

## 5. 多重异常处理


```sql
CREATE OR REPLACE PROCEDURE order_processing(amount FLOAT)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    e_too_small EXCEPTION (-20001, 'Order amount too small');
    e_too_large EXCEPTION (-20002, 'Order amount too large');
BEGIN
    IF (amount < 1.0) THEN
        RAISE e_too_small;
    ELSIF (amount > 999999.0) THEN
        RAISE e_too_large;
    END IF;
    -- 正常处理
    INSERT INTO orders (amount, status) VALUES (:amount, 'pending');
    RETURN 'Order accepted';
EXCEPTION
    WHEN e_too_small THEN
        RETURN 'Rejected: ' || SQLERRM;
    WHEN e_too_large THEN
        RETURN 'Rejected: ' || SQLERRM;
    WHEN OTHER THEN
        RAISE;                   -- 未预期的错误重新抛出
END;
$$;

```

## 6. 嵌套异常处理


```sql
CREATE OR REPLACE PROCEDURE nested_error_handling()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    BEGIN
        -- 内层 BEGIN...END 块
        INSERT INTO users (id, username) VALUES (1, 'alice');
    EXCEPTION
        WHEN OTHER THEN
            -- 内层异常处理（如记录日志）
            INSERT INTO error_log (msg) VALUES (SQLERRM);
    END;
    -- 即使内层出错，外层继续执行
    RETURN 'Completed';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'Outer error: ' || SQLERRM;
END;
$$;

```

 对比嵌套异常处理:
   Oracle PL/SQL:  支持任意深度嵌套，异常可以向上传播
   PostgreSQL:     同样支持嵌套 BEGIN...EXCEPTION...END
   SQL Server:     TRY...CATCH 支持嵌套
   Snowflake:      支持嵌套，行为与 Oracle 类似

## 7. JavaScript 中的错误处理


```sql
CREATE OR REPLACE PROCEDURE js_error_handling()
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
AS
$$
    try {
        var stmt = snowflake.createStatement({sqlText: "SELECT * FROM bad_table"});
        stmt.execute();
        return 'OK';
    } catch (err) {
        return 'Error: ' + err.message + ' (Code: ' + err.code + ')';
    }
$$;

```

 JavaScript 使用原生 try/catch，错误对象包含 code 和 message 属性

## 8. TRY_* 安全函数: 表达式级别的错误处理


Snowflake 提供 TRY_* 系列函数，避免类型转换错误:

```sql
SELECT TRY_CAST('abc' AS INTEGER);          -- 返回 NULL（不报错）
SELECT TRY_TO_NUMBER('abc');                -- 返回 NULL
SELECT TRY_TO_DATE('not-a-date');           -- 返回 NULL
SELECT TRY_TO_BOOLEAN('maybe');             -- 返回 NULL
SELECT TRY_TO_TIMESTAMP('bad-ts');          -- 返回 NULL

```

 对比:
   PostgreSQL:  无 TRY_* 函数（需要 EXCEPTION 块或正则验证）
   SQL Server:  TRY_CAST / TRY_CONVERT（与 Snowflake 最接近）
   BigQuery:    SAFE_CAST（名称不同但功能相同）
   Oracle:      无 TRY_*（需要 EXCEPTION 块）

 对引擎开发者的启示:
   TRY_* 函数极大减少了错误处理的样板代码。
   在 ETL/数据清洗场景中，脏数据的类型转换失败非常常见。
   TRY_* 模式（返回 NULL 而非报错）是比 EXCEPTION 块更高效的处理方式。
   现代引擎应该为所有类型转换函数提供 TRY/SAFE 变体。

## 横向对比: 错误处理能力矩阵

| 能力             | Snowflake       | Oracle PL/SQL  | PostgreSQL    | SQL Server |
|------|------|------|------|------|
| 异常块           | EXCEPTION WHEN  | EXCEPTION WHEN | EXCEPTION WHEN| TRY...CATCH |
| 内置异常类型     | 3 种            | 20+ 种         | 丰富(SQLSTATE)| ERROR_NUMBER |
| 自定义异常       | DECLARE EXCEPTION| PRAGMA INIT   | RAISE EXCEPTION| RAISERROR |
| 嵌套异常         | 支持            | 支持           | 支持          | 支持 |
| TRY_* 安全函数   | TRY_CAST/TO_*   | 无             | 无            | TRY_CAST |
| 错误上下文       | SQLCODE/SQLERRM | SQLCODE/SQLERRM| GET DIAGNOSTICS| ERROR_*() |
| 异常重新抛出     | RAISE (无参数)  | RAISE          | RAISE         | THROW |

