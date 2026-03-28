# PostgreSQL: 错误处理

> 参考资料:
> - [PostgreSQL Documentation - PL/pgSQL Error Trapping](https://www.postgresql.org/docs/current/plpgsql-control-structures.html#PLPGSQL-ERROR-TRAPPING)
> - [PostgreSQL Documentation - Error Codes](https://www.postgresql.org/docs/current/errcodes-appendix.html)

## EXCEPTION WHEN: PL/pgSQL 异常捕获

```sql
CREATE OR REPLACE FUNCTION safe_divide(a NUMERIC, b NUMERIC)
RETURNS NUMERIC AS $$
BEGIN
    RETURN a / b;
EXCEPTION
    WHEN division_by_zero THEN RETURN NULL;
    WHEN numeric_value_out_of_range THEN RETURN NULL;
END; $$ LANGUAGE plpgsql;
```

多个异常条件
```sql
CREATE OR REPLACE FUNCTION safe_insert(p_name VARCHAR, p_email VARCHAR)
RETURNS VOID AS $$
BEGIN
    INSERT INTO users(username, email) VALUES(p_name, p_email);
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'Duplicate: % or %', p_name, p_email;
    WHEN not_null_violation THEN
        RAISE NOTICE 'NULL not allowed';
    WHEN OTHERS THEN
        RAISE NOTICE 'Error: %, %', SQLSTATE, SQLERRM;
END; $$ LANGUAGE plpgsql;
```

## EXCEPTION 块的内部实现: 隐式 SAVEPOINT

关键设计: 每个 BEGIN...EXCEPTION 块创建一个隐式 SAVEPOINT（子事务）。
如果异常发生，回滚到该 SAVEPOINT（只撤销块内的操作，不影响外部事务）。
如果没有异常，释放 SAVEPOINT。

性能影响:
  (a) 每个 EXCEPTION 块都有 SAVEPOINT 开销（WAL 记录 + 资源跟踪）
  (b) 在高频循环中使用 EXCEPTION 块会严重影响性能
  (c) 对比: 没有 EXCEPTION 的 BEGIN...END 块没有 SAVEPOINT 开销

这也是 PostgreSQL 事务模型的特点:
  PostgreSQL 的事务是"一旦出错就中止"——EXCEPTION 块通过子事务来局部恢复。
  对比 MySQL: 单语句失败不会中止整个事务（除非显式 ROLLBACK）。
  对比 Oracle: 自动在语句级回滚（statement-level rollback）。

## RAISE: 抛出消息和异常

消息级别: DEBUG / LOG / INFO / NOTICE / WARNING / EXCEPTION
```sql
CREATE OR REPLACE FUNCTION validate_age(p_age INT)
RETURNS VOID AS $$
BEGIN
    IF p_age < 0 THEN
        RAISE EXCEPTION 'Age cannot be negative: %', p_age
            USING ERRCODE = 'check_violation';
    ELSIF p_age > 200 THEN
        RAISE WARNING 'Suspicious age: %', p_age;
    ELSE
        RAISE NOTICE 'Age valid: %', p_age;
    END IF;
END; $$ LANGUAGE plpgsql;
```

RAISE EXCEPTION 带丰富的上下文信息
```sql
RAISE EXCEPTION 'Custom error'
    USING ERRCODE = '45000',
          DETAIL = 'Additional details',
          HINT = 'Try a different approach',
          COLUMN = 'username',
          TABLE = 'users';
```

设计分析: RAISE 的消息级别
  只有 EXCEPTION 级别会中止当前事务/子事务。
  NOTICE/WARNING 只是发送消息给客户端（不影响执行流）。
  客户端可通过 client_min_messages 控制接收哪些级别的消息。

## GET STACKED DIAGNOSTICS: 获取异常详情 (9.2+)

```sql
CREATE OR REPLACE FUNCTION log_error()
RETURNS VOID AS $$
DECLARE
    v_state TEXT; v_msg TEXT; v_detail TEXT; v_hint TEXT; v_context TEXT;
BEGIN
    PERFORM 1/0;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_state   = RETURNED_SQLSTATE,
        v_msg     = MESSAGE_TEXT,
        v_detail  = PG_EXCEPTION_DETAIL,
        v_hint    = PG_EXCEPTION_HINT,
        v_context = PG_EXCEPTION_CONTEXT;
    INSERT INTO error_log(sqlstate, message, detail, created_at)
    VALUES(v_state, v_msg, v_detail, NOW());
END; $$ LANGUAGE plpgsql;
```

## SQLSTATE 条件匹配

可以用条件名或 SQLSTATE 编码匹配
```sql
BEGIN
    INSERT INTO users(id, username) VALUES(1, 'test');
EXCEPTION
    WHEN SQLSTATE '23505' THEN NULL;  -- unique_violation
    WHEN SQLSTATE '23503' THEN NULL;  -- foreign_key_violation
END;
```

SQLSTATE 编码遵循 SQL 标准:
  23xxx = 完整性约束违反
  42xxx = 语法或访问规则违反
  22xxx = 数据异常
  40xxx = 事务回滚

## ASSERT: 调试断言 (9.5+)

```sql
CREATE OR REPLACE FUNCTION process_order(p_amount NUMERIC)
RETURNS VOID AS $$
BEGIN
    ASSERT p_amount > 0, 'Amount must be positive';
    ASSERT p_amount <= 999999, 'Amount exceeds maximum';
END; $$ LANGUAGE plpgsql;
```

ASSERT 可通过 plpgsql.check_asserts = off 全局关闭（生产环境建议关闭）
ASSERT 失败抛出 ASSERT_FAILURE 异常（SQLSTATE P0004）
WHEN OTHERS 不会捕获 ASSERT_FAILURE（需要显式匹配）

## 嵌套异常处理: 子事务的独立性

```sql
CREATE OR REPLACE FUNCTION nested_exception()
RETURNS TEXT AS $$
DECLARE result TEXT := '';
BEGIN
    BEGIN  -- 子事务 1
        INSERT INTO users(id, username) VALUES(1, 'alice');
        result := result || 'Insert 1 OK. ';
    EXCEPTION WHEN unique_violation THEN
        result := result || 'Insert 1 skipped. ';
    END;

    BEGIN  -- 子事务 2（独立于子事务 1）
        INSERT INTO users(id, username) VALUES(2, 'bob');
        result := result || 'Insert 2 OK. ';
    EXCEPTION WHEN unique_violation THEN
        result := result || 'Insert 2 skipped. ';
    END;

    RETURN result;  -- 两个子事务独立，不互相影响
END; $$ LANGUAGE plpgsql;
```

## 横向对比: 错误处理模型

### 语法

  PostgreSQL: BEGIN...EXCEPTION WHEN...END（PL/pgSQL）
  MySQL:      DECLARE HANDLER FOR ... BEGIN...END（SQL/PSM 风格）
  Oracle:     EXCEPTION WHEN...THEN（PL/SQL，语法类似但无隐式SAVEPOINT）
  SQL Server: TRY...CATCH + THROW/RAISERROR

### 事务中止行为

  PostgreSQL: 语句失败 → 整个事务中止（除非有 EXCEPTION 块捕获）
  MySQL:      语句失败 → 该语句回滚，事务可继续
  Oracle:     语句失败 → 语句级回滚，事务可继续
  SQL Server: 取决于错误严重度（severity）

### 子事务

  PostgreSQL: EXCEPTION 块隐式创建子事务
  Oracle:     SAVEPOINT 需要显式声明
  SQL Server: TRY...CATCH 不创建子事务

## 对引擎开发者的启示

(1) "语句失败 → 事务中止" 的设计更安全但更严格:
    用户必须用 EXCEPTION 块处理预期的错误。
    MySQL 的"语句失败但事务继续"虽然方便，但可能导致部分数据写入的不一致状态。

(2) EXCEPTION 块的隐式 SAVEPOINT 是精妙的设计:
    用户不需要手动管理 SAVEPOINT，异常处理自动获得子事务语义。
    但代价是性能开销——每个 EXCEPTION 块 ≈ 一个子事务。

(3) SQLSTATE 标准化让跨数据库错误处理成为可能:
    23505 = unique_violation 在所有数据库中含义一致。

## 版本演进

PostgreSQL 8.0:  EXCEPTION WHEN, RAISE
PostgreSQL 9.2:  GET STACKED DIAGNOSTICS
PostgreSQL 9.5:  ASSERT
> **注意**: WHEN OTHERS 不捕获 QUERY_CANCELED 和 ASSERT_FAILURE
