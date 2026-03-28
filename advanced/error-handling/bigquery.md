# BigQuery: Error Handling

> 参考资料:
> - [1] BigQuery - Scripting Exception Handling
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/scripting#exception
> - [2] BigQuery - RAISE Statement
>   https://cloud.google.com/bigquery/docs/reference/standard-sql/scripting#raise


## BEGIN...EXCEPTION (BigQuery Scripting)

```sql
BEGIN
    SELECT 1/0;
EXCEPTION WHEN ERROR THEN
    SELECT @@error.message AS error_message,
           @@error.statement_text AS failed_statement;
END;

```

## 错误系统变量

```sql
BEGIN
    INSERT INTO mydataset.users(id, username) VALUES(1, 'test');
EXCEPTION WHEN ERROR THEN
    SELECT
        @@error.message AS message,
        @@error.statement_text AS statement,
        @@error.formatted_stack_trace AS stack_trace;
END;

```

## RAISE (主动抛出错误)

```sql
BEGIN
    DECLARE amount INT64 DEFAULT -1;
    IF amount < 0 THEN
        RAISE USING MESSAGE = 'Amount cannot be negative';
    END IF;
END;

```

## RAISE 重抛异常

```sql
BEGIN
    SELECT * FROM nonexistent_table;
EXCEPTION WHEN ERROR THEN
    -- 记录错误后重抛
    INSERT INTO mydataset.error_log(message, ts)
    VALUES(@@error.message, CURRENT_TIMESTAMP());
    RAISE;
END;

```

## 存储过程中的错误处理

```sql
CREATE OR REPLACE PROCEDURE mydataset.safe_transfer(
    from_id INT64, to_id INT64, amount NUMERIC
)
BEGIN
    IF amount <= 0 THEN
        RAISE USING MESSAGE = FORMAT('Invalid amount: %t', amount);
    END IF;

    BEGIN
        BEGIN TRANSACTION;
        UPDATE mydataset.accounts SET balance = balance - amount WHERE id = from_id;
        UPDATE mydataset.accounts SET balance = balance + amount WHERE id = to_id;
        COMMIT TRANSACTION;
    EXCEPTION WHEN ERROR THEN
        ROLLBACK TRANSACTION;
        RAISE;
    END;
END;

```

版本说明：
BigQuery Scripting (2020+) : BEGIN...EXCEPTION WHEN ERROR
BigQuery Scripting (2020+) : RAISE
注意：BigQuery 只有一种异常条件: WHEN ERROR
注意：@@error 系统变量在 EXCEPTION 块中可用
限制：不能按错误类型分别捕获
限制：不支持 TRY/CATCH, DECLARE HANDLER, SIGNAL

