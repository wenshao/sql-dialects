# 存储过程与用户定义函数 (Stored Procedures & UDFs)

从 CREATE PROCEDURE 到 CREATE FUNCTION，从 PL/SQL 到 JavaScript UDF——各引擎在过程化编程支持上的语法差异与实现取舍。

## 支持矩阵

### 基本能力

| 引擎 | CREATE PROCEDURE | CREATE FUNCTION | 匿名块 | 函数重载 | 版本 |
|------|:---:|:---:|:---:|:---:|------|
| PostgreSQL | ✅ (11+) | ✅ | ✅ `DO` | ✅ | 7.0+ |
| MySQL | ✅ | ✅ | ❌ | ❌ | 5.0+ |
| MariaDB | ✅ | ✅ | ✅ `BEGIN NOT ATOMIC` (10.1.1+) | ❌ | 5.0+ |
| Oracle | ✅ | ✅ | ✅ `DECLARE/BEGIN` | ✅ | 6.0+ |
| SQL Server | ✅ | ✅ | ❌ | ❌ | 2000+ |
| DB2 | ✅ | ✅ | ✅ `BEGIN ATOMIC` | ✅ | 7.0+ |
| SQLite | ❌ | ❌(宿主语言注册) | ❌ | ❌ | — |
| Snowflake | ✅ | ✅ | ✅ (Snowpark) | ✅ | GA |
| BigQuery | ✅ | ✅ | ✅ `BEGIN/END` | ❌ | GA |
| Redshift | ✅ | ✅ | ❌ | ✅ | 2019+ |
| DuckDB | ❌ | ✅ (macro) | ❌ | ❌ | 0.3.0+ |
| ClickHouse | ❌ | ✅ (UDF) | ❌ | ❌ | 21.10+ |
| Trino | ❌ | ✅ (SQL routine 419+) | ❌ | ❌ | 419+ |
| Spark SQL | ❌ | ✅ (UDF via API) | ❌ | ❌ | 1.0+ |
| Databricks | ❌ | ✅ (SQL UDF + Python UDF) | ❌ | ❌ | DBR 9.1+ |
| Hive | ❌ | ✅ (UDF via Java) | ❌ | ❌ | 0.5+ |
| Flink SQL | ❌ | ✅ (UDF via Java/Scala) | ❌ | ❌ | 1.0+ |
| CockroachDB | ✅ (22.2+) | ✅ | ❌ | ✅ | 20.1+ |
| YugabyteDB | ✅ | ✅ | ✅ `DO` | ✅ | 2.0+ |
| TiDB | ❌ | ❌ | ❌ | ❌ | — |
| OceanBase | ✅ (Oracle 模式) | ✅ | ✅ (Oracle 模式) | ❌ | 3.0+ |
| Greenplum | ✅ | ✅ | ✅ `DO` | ✅ | 4.0+ |
| Teradata | ✅ | ✅ | ❌ | ✅ | V2R5+ |
| Vertica | ❌ | ✅ | ❌ | ✅ | 7.0+ |
| SAP HANA | ✅ | ✅ | ✅ `DO` | ✅ | 1.0+ |
| Firebird | ✅ | ✅ | ✅ `EXECUTE BLOCK` | ❌ | 1.5+ |
| Derby | ✅ | ✅ | ❌ | ❌ | 10.0+ |
| H2 | ✅ | ✅ | ❌ | ❌ | 1.0+ |
| Doris | ❌ | ✅ (UDF via Java) | ❌ | ❌ | 1.2+ |
| StarRocks | ❌ | ✅ (UDF via Java) | ❌ | ❌ | 2.2+ |
| PolarDB | ✅ | ✅ | ✅ `DO` | ✅ | 兼容源 |
| openGauss | ✅ | ✅ | ✅ `DO` | ✅ | 1.0+ |
| KingbaseES | ✅ | ✅ | ✅ `DO` | ✅ | V8+ |
| 达梦 (DM) | ✅ | ✅ | ✅ `DECLARE/BEGIN` | ✅ | V7+ |
| TDSQL | ✅ | ✅ | ❌ | ❌ | 兼容源 |
| TDengine | ❌ | ✅ (UDF via C/Python) | ❌ | ❌ | 3.0+ |
| MaxCompute | ❌ | ✅ (UDF via Java/Python) | ❌ | ❌ | GA |
| Hologres | ✅ | ✅ | ❌ | ✅ | 兼容 PG |
| Impala | ❌ | ✅ (UDF via C++/Java) | ❌ | ❌ | 2.0+ |
| Materialize | ❌ | ❌ | ❌ | ❌ | — |
| ksqlDB | ❌ | ✅ (UDF via Java) | ❌ | ❌ | 0.6+ |
| Spanner | ❌ | ❌ | ❌ | ❌ | — |
| Synapse | ✅ | ✅ (T-SQL) | ❌ | ❌ | GA |
| TimescaleDB | ✅ | ✅ | ✅ `DO` | ✅ | 兼容 PG |

### 语言支持

| 引擎 | SQL | PL/pgSQL | PL/SQL | T-SQL | JavaScript | Python | Java | Lua | 其他 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|------|
| PostgreSQL | ✅ | ✅ | ❌ | ❌ | ✅ (V8) | ✅ (PL/Python) | ✅ (PL/Java) | ✅ (PL/Lua) | Perl, Tcl, R |
| MySQL | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | — |
| MariaDB | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | — |
| Oracle | ✅ | ❌ | ✅ | ❌ | ✅ (21c+) | ❌ | ✅ | ❌ | — |
| SQL Server | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ (2017+) | ✅ (CLR) | ❌ | R, C# |
| DB2 | ✅ | ❌ | ✅ (兼容) | ❌ | ❌ | ❌ | ✅ | ❌ | C |
| Snowflake | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ | Scala |
| BigQuery | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | — |
| Redshift | ✅ | ✅ (兼容) | ❌ | ❌ | ❌ | ✅ (UDF) | ❌ | ❌ | — |
| ClickHouse | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 可执行 UDF |
| Trino | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | — |
| Spark SQL | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | Scala, R |
| Databricks | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | Scala |
| Hive | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | — |
| Flink SQL | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | Scala |
| SAP HANA | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | SQLScript, R |
| Firebird | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ (3.0+) | ❌ | PSQL |
| CockroachDB | ✅ | ✅ (兼容) | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | — |
| Vertica | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | C++, R |
| Teradata | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | C |
| TDengine | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | C |
| DuckDB | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ (扩展) | ❌ | ❌ | — |
| Greenplum | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ (PL/Python) | ✅ (PL/Java) | ❌ | Perl, R |
| 达梦 (DM) | ✅ | ❌ | ✅ (兼容) | ❌ | ❌ | ❌ | ✅ | ❌ | — |
| openGauss | ✅ | ✅ | ✅ (兼容) | ❌ | ❌ | ❌ | ✅ | ❌ | — |

## PROCEDURE 与 FUNCTION 的本质区别

大多数 SQL 引擎对过程（PROCEDURE）和函数（FUNCTION）做出了明确区分：

| 特性 | PROCEDURE | FUNCTION |
|------|-----------|----------|
| 返回值 | 通过 OUT 参数返回 | 通过 RETURN 返回 |
| 在 SELECT 中使用 | ❌（通常不允许） | ✅ |
| 在表达式中使用 | ❌ | ✅ |
| 调用方式 | `CALL proc(...)` | `SELECT func(...)` |
| 事务控制 | ✅（可 COMMIT/ROLLBACK） | ❌（大多数引擎禁止） |
| 副作用（DML） | ✅ | 引擎差异大 |

PostgreSQL 在 11 版本引入 `CREATE PROCEDURE` 前，只有 FUNCTION，且允许函数执行 DML 操作。这是 PostgreSQL 的历史特殊性。

## CREATE PROCEDURE 语法对比

### Oracle PL/SQL

```sql
CREATE OR REPLACE PROCEDURE transfer_funds(
    p_from_acct  IN  NUMBER,
    p_to_acct    IN  NUMBER,
    p_amount     IN  NUMBER,
    p_status     OUT VARCHAR2
) AS
    v_balance NUMBER;
BEGIN
    SELECT balance INTO v_balance
    FROM accounts WHERE acct_id = p_from_acct
    FOR UPDATE;

    IF v_balance < p_amount THEN
        p_status := 'INSUFFICIENT_FUNDS';
        RETURN;
    END IF;

    UPDATE accounts SET balance = balance - p_amount
    WHERE acct_id = p_from_acct;

    UPDATE accounts SET balance = balance + p_amount
    WHERE acct_id = p_to_acct;

    p_status := 'SUCCESS';
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        p_status := 'ERROR: ' || SQLERRM;
        ROLLBACK;
END transfer_funds;
/
```

### PostgreSQL PL/pgSQL

```sql
CREATE OR REPLACE PROCEDURE transfer_funds(
    p_from_acct  INT,
    p_to_acct    INT,
    p_amount     NUMERIC,
    INOUT p_status TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_balance NUMERIC;
BEGIN
    SELECT balance INTO v_balance
    FROM accounts WHERE acct_id = p_from_acct
    FOR UPDATE;

    IF v_balance < p_amount THEN
        p_status := 'INSUFFICIENT_FUNDS';
        RETURN;
    END IF;

    UPDATE accounts SET balance = balance - p_amount
    WHERE acct_id = p_from_acct;

    UPDATE accounts SET balance = balance + p_amount
    WHERE acct_id = p_to_acct;

    p_status := 'SUCCESS';
    COMMIT;
END;
$$;

-- 调用
CALL transfer_funds(1001, 1002, 500.00);
```

关键差异：PostgreSQL 的过程没有 OUT 参数语义，用 `INOUT` 代替。

### SQL Server T-SQL

```sql
CREATE OR ALTER PROCEDURE dbo.transfer_funds
    @from_acct   INT,
    @to_acct     INT,
    @amount      DECIMAL(18,2),
    @status      VARCHAR(100) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @balance DECIMAL(18,2);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @balance = balance
        FROM accounts WITH (UPDLOCK)
        WHERE acct_id = @from_acct;

        IF @balance < @amount
        BEGIN
            SET @status = 'INSUFFICIENT_FUNDS';
            ROLLBACK;
            RETURN;
        END

        UPDATE accounts SET balance = balance - @amount
        WHERE acct_id = @from_acct;
        UPDATE accounts SET balance = balance + @amount
        WHERE acct_id = @to_acct;

        COMMIT;
        SET @status = 'SUCCESS';
    END TRY
    BEGIN CATCH
        ROLLBACK;
        SET @status = 'ERROR: ' + ERROR_MESSAGE();
    END CATCH
END;
GO

-- 调用
DECLARE @result VARCHAR(100);
EXEC dbo.transfer_funds 1001, 1002, 500.00, @result OUTPUT;
```

### MySQL

```sql
DELIMITER $$
CREATE PROCEDURE transfer_funds(
    IN  p_from_acct  INT,
    IN  p_to_acct    INT,
    IN  p_amount     DECIMAL(18,2),
    OUT p_status     VARCHAR(100)
)
BEGIN
    DECLARE v_balance DECIMAL(18,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET p_status = 'ERROR';
        ROLLBACK;
    END;

    START TRANSACTION;

    SELECT balance INTO v_balance
    FROM accounts WHERE acct_id = p_from_acct
    FOR UPDATE;

    IF v_balance < p_amount THEN
        SET p_status = 'INSUFFICIENT_FUNDS';
        ROLLBACK;
    ELSE
        UPDATE accounts SET balance = balance - p_amount
        WHERE acct_id = p_from_acct;
        UPDATE accounts SET balance = balance + p_amount
        WHERE acct_id = p_to_acct;
        COMMIT;
        SET p_status = 'SUCCESS';
    END IF;
END$$
DELIMITER ;

-- 调用
CALL transfer_funds(1001, 1002, 500.00, @status);
SELECT @status;
```

### Snowflake (JavaScript)

```sql
CREATE OR REPLACE PROCEDURE transfer_funds(
    FROM_ACCT FLOAT,
    TO_ACCT   FLOAT,
    AMOUNT    FLOAT
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var stmt = snowflake.createStatement({
        sqlText: "SELECT balance FROM accounts WHERE acct_id = ?",
        binds: [FROM_ACCT]
    });
    var result = stmt.execute();
    result.next();
    var balance = result.getColumnValue(1);

    if (balance < AMOUNT) {
        return 'INSUFFICIENT_FUNDS';
    }

    snowflake.execute({sqlText: "BEGIN"});
    try {
        snowflake.execute({
            sqlText: "UPDATE accounts SET balance = balance - ? WHERE acct_id = ?",
            binds: [AMOUNT, FROM_ACCT]
        });
        snowflake.execute({
            sqlText: "UPDATE accounts SET balance = balance + ? WHERE acct_id = ?",
            binds: [AMOUNT, TO_ACCT]
        });
        snowflake.execute({sqlText: "COMMIT"});
        return 'SUCCESS';
    } catch (err) {
        snowflake.execute({sqlText: "ROLLBACK"});
        return 'ERROR: ' + err.message;
    }
$$;
```

### BigQuery

```sql
CREATE OR REPLACE PROCEDURE myproject.mydataset.transfer_funds(
    p_from_acct INT64,
    p_to_acct   INT64,
    p_amount    NUMERIC,
    OUT p_status STRING
)
BEGIN
    DECLARE v_balance NUMERIC;

    SET v_balance = (
        SELECT balance FROM myproject.mydataset.accounts
        WHERE acct_id = p_from_acct
    );

    IF v_balance < p_amount THEN
        SET p_status = 'INSUFFICIENT_FUNDS';
        RETURN;
    END IF;

    -- BigQuery 不支持事务内多表更新; 使用 MERGE 或脚本方式
    UPDATE myproject.mydataset.accounts
    SET balance = balance - p_amount
    WHERE acct_id = p_from_acct;

    UPDATE myproject.mydataset.accounts
    SET balance = balance + p_amount
    WHERE acct_id = p_to_acct;

    SET p_status = 'SUCCESS';
END;
```

## CREATE FUNCTION 语法对比

### 标量函数 (Scalar Function)

**PostgreSQL:**

```sql
CREATE OR REPLACE FUNCTION calculate_tax(price NUMERIC, tax_rate NUMERIC DEFAULT 0.1)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT price * tax_rate;
$$;
```

**Oracle:**

```sql
CREATE OR REPLACE FUNCTION calculate_tax(
    p_price    NUMBER,
    p_tax_rate NUMBER DEFAULT 0.1
) RETURN NUMBER
DETERMINISTIC
PARALLEL_ENABLE
IS
BEGIN
    RETURN p_price * p_tax_rate;
END;
/
```

**SQL Server:**

```sql
CREATE OR ALTER FUNCTION dbo.calculate_tax(
    @price    DECIMAL(18,2),
    @tax_rate DECIMAL(5,4) = 0.1
)
RETURNS DECIMAL(18,2)
WITH SCHEMABINDING
AS
BEGIN
    RETURN @price * @tax_rate;
END;
GO
```

**MySQL:**

```sql
CREATE FUNCTION calculate_tax(p_price DECIMAL(18,2), p_tax_rate DECIMAL(5,4))
RETURNS DECIMAL(18,2)
DETERMINISTIC
NO SQL
BEGIN
    RETURN p_price * p_tax_rate;
END;
```

**Snowflake (SQL):**

```sql
CREATE OR REPLACE FUNCTION calculate_tax(price FLOAT, tax_rate FLOAT)
RETURNS FLOAT
AS
$$
    price * tax_rate
$$;
```

**BigQuery:**

```sql
CREATE FUNCTION myproject.mydataset.calculate_tax(price NUMERIC, tax_rate NUMERIC)
RETURNS NUMERIC
AS (
    price * tax_rate
);
```

**DuckDB (MACRO):**

```sql
CREATE MACRO calculate_tax(price, tax_rate := 0.1) AS price * tax_rate;
-- MACRO 在 DuckDB 中是 inline 展开的，不是真正的函数调用
```

**ClickHouse:**

```sql
CREATE FUNCTION calculate_tax AS (price, tax_rate) -> price * tax_rate;
-- Lambda 语法定义，参数无类型声明
```

**Trino (SQL routine):**

```sql
CREATE FUNCTION calculate_tax(price DOUBLE, tax_rate DOUBLE)
RETURNS DOUBLE
DETERMINISTIC
RETURN price * tax_rate;
```

### 表值函数 (Table-Valued Function)

**PostgreSQL:**

```sql
CREATE OR REPLACE FUNCTION get_employees_by_dept(dept_id INT)
RETURNS TABLE (
    emp_id    INT,
    emp_name  TEXT,
    salary    NUMERIC
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT e.emp_id, e.emp_name, e.salary
    FROM employees e
    WHERE e.department_id = dept_id;
END;
$$;

-- 调用
SELECT * FROM get_employees_by_dept(10);
```

**SQL Server (Inline TVF):**

```sql
CREATE FUNCTION dbo.get_employees_by_dept(@dept_id INT)
RETURNS TABLE
AS
RETURN (
    SELECT emp_id, emp_name, salary
    FROM employees
    WHERE department_id = @dept_id
);
GO

-- Multi-statement TVF
CREATE FUNCTION dbo.get_employee_summary(@dept_id INT)
RETURNS @result TABLE (
    emp_count   INT,
    avg_salary  DECIMAL(18,2),
    max_salary  DECIMAL(18,2)
)
AS
BEGIN
    INSERT INTO @result
    SELECT COUNT(*), AVG(salary), MAX(salary)
    FROM employees WHERE department_id = @dept_id;
    RETURN;
END;
GO
```

**Oracle (Pipelined Table Function):**

```sql
CREATE TYPE emp_row AS OBJECT (
    emp_id   NUMBER,
    emp_name VARCHAR2(100),
    salary   NUMBER
);
/
CREATE TYPE emp_table AS TABLE OF emp_row;
/
CREATE FUNCTION get_employees_by_dept(p_dept_id NUMBER)
RETURN emp_table PIPELINED
IS
BEGIN
    FOR rec IN (
        SELECT emp_id, emp_name, salary
        FROM employees WHERE department_id = p_dept_id
    ) LOOP
        PIPE ROW(emp_row(rec.emp_id, rec.emp_name, rec.salary));
    END LOOP;
    RETURN;
END;
/

-- 调用
SELECT * FROM TABLE(get_employees_by_dept(10));
```

**SAP HANA:**

```sql
CREATE FUNCTION get_employees_by_dept(IN dept_id INT)
RETURNS TABLE (
    emp_id    INT,
    emp_name  NVARCHAR(100),
    salary    DECIMAL(18,2)
)
LANGUAGE SQLSCRIPT
READS SQL DATA
AS
BEGIN
    RETURN SELECT emp_id, emp_name, salary
           FROM employees
           WHERE department_id = :dept_id;
END;
```

## IN / OUT / INOUT 参数

### 参数方向支持矩阵

| 引擎 | IN | OUT | INOUT | 默认方向 | DEFAULT 值 |
|------|:---:|:---:|:---:|---------|:---:|
| Oracle | ✅ | ✅ | ✅ | IN | ✅ |
| PostgreSQL | ✅ | ✅ (FUNCTION) / INOUT (PROCEDURE) | ✅ | IN | ✅ |
| MySQL | ✅ | ✅ | ✅ | IN (显式标注) | ❌ (5.x), ✅ (8.0+) |
| SQL Server | ✅ (隐式) | ✅ `OUTPUT` | ✅ `OUTPUT` | IN | ✅ |
| DB2 | ✅ | ✅ | ✅ | IN | ✅ |
| Snowflake | ✅ | ❌ (用 RETURNS) | ❌ | IN | ✅ |
| BigQuery | ✅ | ✅ | ✅ | IN | ❌ |
| Firebird | ✅ | ✅ | ❌ | IN | ✅ |
| SAP HANA | ✅ | ✅ | ✅ | IN | ✅ |
| Teradata | ✅ | ✅ | ✅ | IN | ✅ |
| 达梦 (DM) | ✅ | ✅ | ✅ | IN | ✅ |

SQL Server 语法要点：没有 IN 关键字，参数默认为输入；`OUTPUT` 同时表示 OUT 和 INOUT。

```sql
-- SQL Server: 调用者必须同时标注 OUTPUT
EXEC my_proc @x = 10, @result = @r OUTPUT;

-- Oracle: 调用者无需标注方向
EXECUTE my_proc(10, v_result);
```

PostgreSQL 的特殊处理——PROCEDURE 不支持 OUT 参数，需用 INOUT 模拟：

```sql
-- PostgreSQL 11+
CREATE PROCEDURE calc(IN x INT, INOUT result INT DEFAULT 0)
LANGUAGE plpgsql AS $$
BEGIN
    result := x * 2;
END;
$$;

CALL calc(5, NULL);  -- 返回 result = 10
```

## 确定性注解 (Determinism Annotations)

确定性注解告知优化器函数的行为特征，直接影响查询优化策略。

### 语义定义

| 注解 | 含义 | 副作用 | 同参数同结果 | 使用引擎 |
|------|------|:---:|:---:|------|
| `DETERMINISTIC` | 同输入总返回同结果 | ❌ | ✅ | Oracle, MySQL, DB2, Teradata |
| `IMMUTABLE` | 同 DETERMINISTIC，最严格 | ❌ | ✅ | PostgreSQL, CockroachDB |
| `STABLE` | 单语句内一致 | ❌ | ✅ (单语句内) | PostgreSQL |
| `VOLATILE` | 每次调用可能不同（默认） | ✅ | ❌ | PostgreSQL |
| `NOT DETERMINISTIC` | 明确标记不确定 | ✅ | ❌ | MySQL, DB2 |
| `PARALLEL_ENABLE` | 可在并行执行中安全使用 | ❌ | — | Oracle |
| `PARALLEL SAFE` | 同上 | ❌ | — | PostgreSQL |
| `PARALLEL UNSAFE` | 不可并行 | — | — | PostgreSQL |

### 各引擎语法

```sql
-- PostgreSQL
CREATE FUNCTION f(x INT) RETURNS INT
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$ SELECT x * 2; $$;

CREATE FUNCTION now_wrapper() RETURNS TIMESTAMP
LANGUAGE sql STABLE
AS $$ SELECT now(); $$;

-- Oracle
CREATE FUNCTION f(x NUMBER) RETURN NUMBER
DETERMINISTIC PARALLEL_ENABLE
IS BEGIN RETURN x * 2; END;
/

-- MySQL（必须声明，否则默认 NOT DETERMINISTIC）
CREATE FUNCTION f(x INT) RETURNS INT
DETERMINISTIC NO SQL
BEGIN RETURN x * 2; END;

-- DB2
CREATE FUNCTION f(x INTEGER) RETURNS INTEGER
DETERMINISTIC NO EXTERNAL ACTION CONTAINS SQL
RETURN x * 2;

-- Snowflake（隐式推断，无显式注解）
-- 函数是否确定性由引擎自动推断

-- BigQuery（无显式注解，自动推断）
CREATE FUNCTION f(x INT64) RETURNS INT64 AS (x * 2);

-- Trino
CREATE FUNCTION f(x DOUBLE) RETURNS DOUBLE
DETERMINISTIC RETURN x * 2;

-- ClickHouse（无显式注解，表达式 UDF 自动确定）
```

PostgreSQL 的三级分类（IMMUTABLE / STABLE / VOLATILE）是最精细的。对引擎开发者而言，这直接影响：
- IMMUTABLE：可在计划阶段常量折叠
- STABLE：可在单次扫描中缓存结果
- VOLATILE：每行必须重新计算

## SECURITY DEFINER vs SECURITY INVOKER

控制函数/过程执行时使用的权限上下文。

| 引擎 | DEFINER | INVOKER | 默认 | 注意事项 |
|------|:---:|:---:|---------|------|
| PostgreSQL | ✅ `SECURITY DEFINER` | ✅ `SECURITY INVOKER` | INVOKER | 推荐设置 `search_path` |
| Oracle | ✅ `AUTHID DEFINER` | ✅ `AUTHID CURRENT_USER` | DEFINER | 默认以拥有者权限运行 |
| MySQL | ✅ `SQL SECURITY DEFINER` | ✅ `SQL SECURITY INVOKER` | DEFINER | — |
| SQL Server | ✅ `EXECUTE AS OWNER` | ✅ `EXECUTE AS CALLER` | CALLER | 也支持 `EXECUTE AS 'user'` |
| Snowflake | ✅ `EXECUTE AS OWNER` | ✅ `EXECUTE AS CALLER` | OWNER | 重要安全考量 |
| DB2 | ✅ (默认) | ❌ | DEFINER | — |
| MariaDB | ✅ `SQL SECURITY DEFINER` | ✅ `SQL SECURITY INVOKER` | DEFINER | — |
| Firebird | ❌ | ✅ (默认) | INVOKER | — |
| SAP HANA | ✅ `SECURITY DEFINER` | ✅ `SECURITY INVOKER` | INVOKER | — |
| BigQuery | ❌ | ✅ (默认) | INVOKER | 所有权限基于调用者 |
| CockroachDB | ✅ `SECURITY DEFINER` | ✅ `SECURITY INVOKER` | INVOKER | 兼容 PostgreSQL |

### 安全陷阱：search_path 注入

PostgreSQL 中 `SECURITY DEFINER` 函数必须固定 `search_path`，否则攻击者可以通过修改 `search_path` 注入恶意对象：

```sql
-- 安全写法
CREATE FUNCTION admin_lookup(uid INT) RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT username FROM users WHERE id = uid;
$$;
```

Oracle 中等价的安全建议是使用 schema 限定对象名：

```sql
CREATE FUNCTION admin_lookup(p_uid NUMBER) RETURN VARCHAR2
AUTHID DEFINER
IS
    v_name VARCHAR2(100);
BEGIN
    SELECT username INTO v_name FROM myschema.users WHERE id = p_uid;
    RETURN v_name;
END;
/
```

## 异常处理 (Exception Handling)

### 语法对比矩阵

| 引擎 | 语法 | 命名异常 | 自定义异常 | 异常代码 |
|------|------|:---:|:---:|:---:|
| Oracle | `EXCEPTION WHEN ... THEN` | ✅ | ✅ `RAISE_APPLICATION_ERROR` | ✅ SQLCODE |
| PostgreSQL | `EXCEPTION WHEN ... THEN` | ✅ | ✅ `RAISE EXCEPTION` | ✅ SQLSTATE |
| SQL Server | `BEGIN TRY/CATCH` | ❌ | ✅ `THROW` / `RAISERROR` | ✅ ERROR_NUMBER() |
| MySQL | `DECLARE HANDLER` | ❌ | ✅ `SIGNAL` | ✅ SQLSTATE |
| DB2 | `DECLARE HANDLER` / `SIGNAL` | ❌ | ✅ `SIGNAL` | ✅ SQLSTATE |
| BigQuery | `BEGIN/EXCEPTION/END` | ❌ | ✅ `RAISE` | ❌ |
| Snowflake | `TRY/CATCH` (JS) | ❌ | ✅ | ❌ |
| Firebird | `WHEN ... DO` | ✅ | ✅ `EXCEPTION` | ✅ SQLCODE |
| SAP HANA | `DECLARE EXIT HANDLER` | ❌ | ✅ `SIGNAL` | ✅ |
| 达梦 (DM) | `EXCEPTION WHEN ... THEN` | ✅ | ✅ | ✅ |

### Oracle

```sql
CREATE PROCEDURE safe_divide(a NUMBER, b NUMBER, OUT result NUMBER) AS
BEGIN
    result := a / b;
EXCEPTION
    WHEN ZERO_DIVIDE THEN
        result := NULL;
        DBMS_OUTPUT.PUT_LINE('除零错误');
    WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(-20001, '未知错误: ' || SQLERRM);
END;
/
```

### PostgreSQL

```sql
CREATE FUNCTION safe_divide(a NUMERIC, b NUMERIC) RETURNS NUMERIC
LANGUAGE plpgsql AS $$
BEGIN
    RETURN a / b;
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE '除零错误，返回 NULL';
        RETURN NULL;
    WHEN OTHERS THEN
        RAISE EXCEPTION '未知错误: % (SQLSTATE=%)', SQLERRM, SQLSTATE;
END;
$$;
```

### SQL Server

```sql
CREATE PROCEDURE safe_divide @a DECIMAL(18,2), @b DECIMAL(18,2), @result DECIMAL(18,2) OUTPUT
AS
BEGIN
    BEGIN TRY
        SET @result = @a / @b;
    END TRY
    BEGIN CATCH
        SET @result = NULL;
        -- ERROR_NUMBER(), ERROR_MESSAGE(), ERROR_SEVERITY(), ERROR_STATE()
        THROW 50001, N'除零或其他计算错误', 1;
    END CATCH
END;
```

### MySQL

```sql
CREATE PROCEDURE safe_divide(IN a DECIMAL(18,2), IN b DECIMAL(18,2), OUT result DECIMAL(18,2))
BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        SET result = NULL;
        -- GET DIAGNOSTICS 获取详细错误信息 (MySQL 5.6+)
    END;

    DECLARE CONTINUE HANDLER FOR SQLSTATE '22012'  -- 除零
    BEGIN
        SET result = NULL;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '除零错误';
    END;

    SET result = a / b;
END;
```

注意 MySQL 的 HANDLER 模型与 Oracle/PostgreSQL 的 EXCEPTION 块模型截然不同。MySQL 使用**声明式处理器**，在异常发生时自动触发，且有 CONTINUE / EXIT / UNDO 三种处理器类型。

## 游标 (Cursor) 支持

### 游标支持矩阵

| 引擎 | 显式游标 | 隐式游标 | REF CURSOR | 可滚动 | WITH HOLD |
|------|:---:|:---:|:---:|:---:|:---:|
| Oracle | ✅ | ✅ | ✅ `SYS_REFCURSOR` | ❌ | ❌ |
| PostgreSQL | ✅ | ✅ | ✅ `REFCURSOR` | ✅ | ✅ |
| SQL Server | ✅ | ❌ | ❌ | ✅ | ❌ |
| MySQL | ✅ | ❌ | ❌ | ❌ | ❌ |
| DB2 | ✅ | ❌ | ✅ | ✅ | ✅ |
| Firebird | ✅ | ✅ | ❌ | ✅ | ❌ |
| SAP HANA | ✅ | ❌ | ✅ | ❌ | ❌ |
| 达梦 (DM) | ✅ | ✅ | ✅ | ✅ | ❌ |

### Oracle 游标

```sql
CREATE PROCEDURE process_orders AS
    CURSOR c_orders IS
        SELECT order_id, amount FROM orders WHERE status = 'PENDING';
    v_order c_orders%ROWTYPE;
BEGIN
    OPEN c_orders;
    LOOP
        FETCH c_orders INTO v_order;
        EXIT WHEN c_orders%NOTFOUND;
        -- 处理每一行
        UPDATE orders SET status = 'PROCESSED' WHERE order_id = v_order.order_id;
    END LOOP;
    CLOSE c_orders;
END;
/

-- 隐式游标 (FOR 循环自动管理)
CREATE PROCEDURE process_orders_v2 AS
BEGIN
    FOR rec IN (SELECT order_id, amount FROM orders WHERE status = 'PENDING')
    LOOP
        UPDATE orders SET status = 'PROCESSED' WHERE order_id = rec.order_id;
    END LOOP;
END;
/
```

### PostgreSQL 游标

```sql
CREATE FUNCTION process_large_table() RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    cur CURSOR FOR SELECT id, data FROM large_table;
    rec RECORD;
BEGIN
    OPEN cur;
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        PERFORM process_row(rec.id, rec.data);
    END LOOP;
    CLOSE cur;
END;
$$;

-- REF CURSOR 传递
CREATE FUNCTION get_cursor(dept INT) RETURNS REFCURSOR
LANGUAGE plpgsql AS $$
DECLARE
    ref REFCURSOR;
BEGIN
    OPEN ref FOR SELECT * FROM employees WHERE department_id = dept;
    RETURN ref;
END;
$$;
```

### SQL Server 游标

```sql
CREATE PROCEDURE process_orders
AS
BEGIN
    DECLARE @order_id INT, @amount DECIMAL(18,2);
    DECLARE order_cursor CURSOR
        LOCAL FAST_FORWARD  -- 最高效模式
        FOR SELECT order_id, amount FROM orders WHERE status = 'PENDING';

    OPEN order_cursor;
    FETCH NEXT FROM order_cursor INTO @order_id, @amount;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        UPDATE orders SET status = 'PROCESSED' WHERE order_id = @order_id;
        FETCH NEXT FROM order_cursor INTO @order_id, @amount;
    END;
    CLOSE order_cursor;
    DEALLOCATE order_cursor;
END;
```

SQL Server 游标类型影响性能：`FAST_FORWARD`（只前进、只读）最快，`SCROLL`（可滚动）最慢。引擎开发者需权衡内存占用与访问灵活性。

## 动态 SQL

### 动态 SQL 支持矩阵

| 引擎 | 语法 | 绑定变量 | USING 子句 | 动态游标 |
|------|------|:---:|:---:|:---:|
| Oracle | `EXECUTE IMMEDIATE` | ✅ | ✅ | ✅ `OPEN FOR` |
| PostgreSQL | `EXECUTE` (plpgsql) | ✅ `$1, $2` | ✅ | ✅ |
| SQL Server | `sp_executesql` / `EXEC()` | ✅ | ✅ | ❌ |
| MySQL | `PREPARE/EXECUTE/DEALLOCATE` | ✅ `?` | ❌ | ❌ |
| DB2 | `EXECUTE IMMEDIATE` / `PREPARE` | ✅ | ✅ | ✅ |
| Firebird | `EXECUTE STATEMENT` | ✅ | ❌ | ✅ |
| SAP HANA | `EXECUTE IMMEDIATE` / `EXEC` | ✅ | ✅ | ❌ |
| BigQuery | `EXECUTE IMMEDIATE` | ✅ | ✅ `USING` | ❌ |
| Snowflake | `EXECUTE IMMEDIATE` | ✅ `?` | ✅ `USING` | ❌ |

### Oracle

```sql
CREATE PROCEDURE dynamic_query(p_table VARCHAR2, p_col VARCHAR2, p_val VARCHAR2) AS
    v_sql   VARCHAR2(4000);
    v_count NUMBER;
BEGIN
    v_sql := 'SELECT COUNT(*) FROM ' || DBMS_ASSERT.SQL_OBJECT_NAME(p_table)
          || ' WHERE ' || DBMS_ASSERT.SIMPLE_SQL_NAME(p_col) || ' = :1';
    EXECUTE IMMEDIATE v_sql INTO v_count USING p_val;
    DBMS_OUTPUT.PUT_LINE('Count: ' || v_count);
END;
/
```

### PostgreSQL

```sql
CREATE FUNCTION dynamic_count(tbl TEXT, col TEXT, val TEXT) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    result BIGINT;
BEGIN
    EXECUTE format('SELECT COUNT(*) FROM %I WHERE %I = $1', tbl, col)
    INTO result
    USING val;
    RETURN result;
END;
$$;
```

`format()` 的 `%I` 自动处理标识符转义，`%L` 处理字面量转义，是防 SQL 注入的最佳实践。

### SQL Server

```sql
CREATE PROCEDURE dynamic_count
    @tbl NVARCHAR(128), @col NVARCHAR(128), @val NVARCHAR(MAX)
AS
BEGIN
    DECLARE @sql NVARCHAR(MAX);
    -- QUOTENAME 防注入
    SET @sql = N'SELECT COUNT(*) FROM ' + QUOTENAME(@tbl)
             + N' WHERE ' + QUOTENAME(@col) + N' = @p_val';
    EXEC sp_executesql @sql, N'@p_val NVARCHAR(MAX)', @p_val = @val;
END;
```

### BigQuery

```sql
DECLARE table_name STRING DEFAULT 'my_table';
DECLARE result INT64;
EXECUTE IMMEDIATE
    CONCAT('SELECT COUNT(*) FROM `', table_name, '`')
INTO result;
```

## UDF vs UDTF vs UDAF

三种用户定义函数类型覆盖了不同的数据处理模式：

| 类型 | 全称 | 输入/输出 | 类比 |
|------|------|----------|------|
| UDF | User-Defined Function | 一行 → 一值 | `UPPER()`, `ABS()` |
| UDTF | User-Defined Table Function | 一行 → 多行 | `UNNEST()`, `EXPLODE()` |
| UDAF | User-Defined Aggregate Function | 多行 → 一值 | `SUM()`, `COUNT()` |

### 各引擎支持矩阵

| 引擎 | UDF | UDTF | UDAF | 注册方式 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | ✅ | ✅ (RETURNS TABLE/SETOF) | ✅ (CREATE AGGREGATE) | SQL |
| Oracle | ✅ | ✅ (PIPELINED) | ✅ (ODCIAggregate) | SQL/Java |
| SQL Server | ✅ | ✅ (TVF) | ✅ (CLR) | T-SQL/C# |
| MySQL | ✅ | ❌ | ❌ (仅 C 插件) | SQL |
| Snowflake | ✅ | ✅ | ✅ (Java/Python UDAF) | SQL/JS/Python/Java |
| BigQuery | ✅ | ❌ | ✅ (JS UDAF) | SQL/JS |
| Hive | ✅ | ✅ | ✅ | Java |
| Spark SQL | ✅ | ✅ | ✅ | Scala/Java/Python |
| Flink SQL | ✅ | ✅ | ✅ | Java/Scala/Python |
| ClickHouse | ✅ | ❌ | ✅ (-State/-Merge 组合器) | SQL/可执行 |
| Trino | ✅ | ✅ (SQL 419+) | ✅ (Plugin) | SQL/Java |
| DuckDB | ✅ (MACRO) | ✅ (TABLE MACRO) | ❌ | SQL |
| Databricks | ✅ | ✅ | ✅ | SQL/Python/Scala |
| Doris | ✅ | ✅ | ✅ | Java |
| StarRocks | ✅ | ✅ | ✅ | Java |
| Vertica | ✅ | ✅ | ✅ | C++/Python/Java/R |
| Impala | ✅ | ❌ | ✅ | C++/Java |
| MaxCompute | ✅ | ✅ | ✅ | Java/Python |
| ksqlDB | ✅ | ✅ | ✅ | Java |
| TDengine | ✅ | ❌ | ✅ | C/Python |

### PostgreSQL 自定义聚合

```sql
-- 创建状态转移函数
CREATE FUNCTION text_concat_sfunc(state TEXT, value TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN state = '' THEN value
                ELSE state || ', ' || value END;
$$;

-- 创建聚合
CREATE AGGREGATE text_concat(TEXT) (
    SFUNC = text_concat_sfunc,
    STYPE = TEXT,
    INITCOND = ''
);

-- 使用
SELECT department, text_concat(name ORDER BY name) FROM employees GROUP BY department;
```

### Hive/Spark UDAF (Java 接口)

```java
// Hive GenericUDAFEvaluator 接口
public class MedianUDAF extends AbstractGenericUDAFResolver {
    @Override
    public GenericUDAFEvaluator getEvaluator(TypeInfo[] parameters) {
        return new MedianEvaluator();
    }

    public static class MedianEvaluator extends GenericUDAFEvaluator {
        // init() -> iterate() -> terminatePartial()
        //        -> merge() -> terminate()
    }
}
```

### Flink SQL UDF (Java)

```java
// 标量 UDF
public class HashFunction extends ScalarFunction {
    public int eval(String s) {
        return s.hashCode();
    }
}

// 表 UDF (UDTF)
public class SplitFunction extends TableFunction<Row> {
    public void eval(String str) {
        for (String s : str.split(",")) {
            collect(Row.of(s, s.length()));
        }
    }
}

// 聚合 UDF (UDAF)
public class WeightedAvg extends AggregateFunction<Long, WeightedAvgAccum> {
    public void accumulate(WeightedAvgAccum acc, long value, int weight) {
        acc.sum += value * weight;
        acc.count += weight;
    }
    public Long getValue(WeightedAvgAccum acc) {
        return acc.count == 0 ? null : acc.sum / acc.count;
    }
}
```

## Lambda 与匿名函数

部分引擎支持内联的 Lambda 表达式，无需预先 CREATE FUNCTION。

| 引擎 | Lambda 语法 | 使用场景 | 示例 |
|------|------------|---------|------|
| ClickHouse | `(x) -> expr` | 高阶函数参数 | `arrayMap(x -> x * 2, arr)` |
| DuckDB | `(x) -> expr` | `list_transform` 等 | `list_transform(l, x -> x + 1)` |
| Trino | `x -> expr` | `transform`, `filter` 等 | `transform(arr, x -> x * 2)` |
| Spark SQL | `x -> expr` | `transform`, `filter`, `aggregate` | `transform(arr, x -> x + 1)` |
| Databricks | `x -> expr` | 同 Spark | `filter(arr, x -> x > 0)` |
| BigQuery | ❌ | — | — |
| PostgreSQL | ❌ (需 CREATE FUNCTION) | — | — |
| Oracle | ❌ | — | — |
| SQL Server | ❌ | — | — |
| MySQL | ❌ | — | — |
| Flink SQL | ❌ | — | — |
| Snowflake | ❌ | — | — |

### Lambda 示例

```sql
-- ClickHouse
SELECT arrayMap(x -> x * x, [1, 2, 3, 4, 5]);       -- [1, 4, 9, 16, 25]
SELECT arrayFilter(x -> x > 3, [1, 2, 3, 4, 5]);     -- [4, 5]
SELECT arrayReduce('sum', arrayMap(x -> x * 2, [1, 2, 3]));  -- 12

-- DuckDB
SELECT list_transform([1, 2, 3], x -> x * x);         -- [1, 4, 9]
SELECT list_filter([1, 2, 3, 4, 5], x -> x % 2 = 0);  -- [2, 4]

-- Trino / Spark SQL
SELECT transform(ARRAY[1, 2, 3], x -> x * 2);          -- [2, 4, 6]
SELECT filter(ARRAY[1, 2, 3, 4, 5], x -> x > 3);       -- [4, 5]
SELECT aggregate(ARRAY[1, 2, 3], 0, (acc, x) -> acc + x); -- 6

-- Databricks 高级用法
SELECT transform(arr, (element, index) -> element + index)
FROM VALUES (ARRAY(10, 20, 30)) AS t(arr);  -- [10, 21, 32]
```

## 函数/过程重载 (Overloading)

函数重载指同名函数可以拥有不同的参数签名。

| 引擎 | 支持重载 | 解析策略 | 备注 |
|------|:---:|---------|------|
| PostgreSQL | ✅ | 参数类型匹配 + 隐式转换 | 函数标识 = 名称 + 参数类型列表 |
| Oracle | ✅ (包内) | 包内同名不同签名 | 顶层 schema 对象不允许同名 |
| DB2 | ✅ | 特定路径解析 | 同 schema 下可重载 |
| SQL Server | ❌ | — | CLR 函数可重载 |
| MySQL | ❌ | — | — |
| Snowflake | ✅ | 参数数量+类型 | 同名不同签名 |
| CockroachDB | ✅ | 兼容 PostgreSQL | — |
| SAP HANA | ✅ | 参数类型匹配 | — |
| Teradata | ✅ | 特定函数解析 | — |
| Vertica | ✅ | 参数类型匹配 | — |
| 达梦 (DM) | ✅ | 兼容 Oracle 包内重载 | — |
| openGauss | ✅ | 兼容 PostgreSQL | — |

### PostgreSQL 重载

```sql
-- 同名不同参数类型
CREATE FUNCTION format_value(val INT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$ SELECT val::text; $$;

CREATE FUNCTION format_value(val NUMERIC) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$ SELECT to_char(val, 'FM999,999.00'); $$;

CREATE FUNCTION format_value(val TIMESTAMP) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$ SELECT to_char(val, 'YYYY-MM-DD HH24:MI:SS'); $$;

-- 调用时根据参数类型自动选择
SELECT format_value(42);                          -- '42'
SELECT format_value(1234.56);                     -- '1,234.56'
SELECT format_value(NOW()::timestamp);            -- '2026-03-30 14:30:00'
```

### Oracle 包内重载

```sql
CREATE OR REPLACE PACKAGE format_pkg AS
    FUNCTION format_value(val NUMBER) RETURN VARCHAR2;
    FUNCTION format_value(val DATE) RETURN VARCHAR2;
    FUNCTION format_value(val VARCHAR2) RETURN VARCHAR2;
END format_pkg;
/

CREATE OR REPLACE PACKAGE BODY format_pkg AS
    FUNCTION format_value(val NUMBER) RETURN VARCHAR2 IS
    BEGIN RETURN TO_CHAR(val, 'FM999,999.00'); END;

    FUNCTION format_value(val DATE) RETURN VARCHAR2 IS
    BEGIN RETURN TO_CHAR(val, 'YYYY-MM-DD'); END;

    FUNCTION format_value(val VARCHAR2) RETURN VARCHAR2 IS
    BEGIN RETURN val; END;
END format_pkg;
/
```

重载引入了**歧义解析**问题。PostgreSQL 通过类型优先级和隐式转换链来解决，但可能产生令人困惑的结果：

```sql
-- 歧义示例
CREATE FUNCTION f(x INT) RETURNS TEXT LANGUAGE sql AS $$ SELECT 'int'; $$;
CREATE FUNCTION f(x BIGINT) RETURNS TEXT LANGUAGE sql AS $$ SELECT 'bigint'; $$;

SELECT f(42);     -- 调用 INT 版本（精确匹配）
SELECT f(42::INT8); -- 调用 BIGINT 版本
```

## 匿名块 (Anonymous Blocks)

无需创建持久化对象即可运行过程化代码。

| 引擎 | 语法 | 示例 |
|------|------|------|
| PostgreSQL | `DO $$ ... $$` | `DO $$ BEGIN RAISE NOTICE 'hello'; END; $$;` |
| Oracle | `DECLARE/BEGIN ... END` | `BEGIN DBMS_OUTPUT.PUT_LINE('hello'); END; /` |
| MariaDB | `BEGIN NOT ATOMIC ... END` | `BEGIN NOT ATOMIC SELECT 1; END;` |
| BigQuery | `BEGIN ... END` | `BEGIN DECLARE x INT64; SET x = 1; END;` |
| SAP HANA | `DO BEGIN ... END` | `DO BEGIN DECLARE x INT; x = 1; END;` |
| Firebird | `EXECUTE BLOCK` | `EXECUTE BLOCK AS BEGIN ... END` |
| DB2 | `BEGIN ATOMIC ... END` | `BEGIN ATOMIC DECLARE x INT; SET x = 1; END` |
| Snowflake | 脚本模式 | `BEGIN LET x := 1; RETURN x; END;` |

```sql
-- PostgreSQL 匿名块
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE format('ANALYZE %I', r.tablename);
        RAISE NOTICE 'Analyzed: %', r.tablename;
    END LOOP;
END;
$$;

-- Oracle 匿名块
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM user_tables;
    DBMS_OUTPUT.PUT_LINE('Table count: ' || v_count);
    FOR r IN (SELECT table_name FROM user_tables) LOOP
        EXECUTE IMMEDIATE 'ANALYZE TABLE ' || r.table_name || ' COMPUTE STATISTICS';
    END LOOP;
END;
/

-- Firebird EXECUTE BLOCK（可带参数）
EXECUTE BLOCK (dept_id INT = ?)
RETURNS (emp_name VARCHAR(100), salary DECIMAL(18,2))
AS
BEGIN
    FOR SELECT emp_name, salary FROM employees WHERE department_id = :dept_id
        INTO :emp_name, :salary
    DO
        SUSPEND;  -- 返回当前行
END
```

## 返回类型：标量、表、集合

### 返回类型支持矩阵

| 引擎 | 标量 | SETOF/TABLE | 游标 | 复合类型 | VOID |
|------|:---:|:---:|:---:|:---:|:---:|
| PostgreSQL | ✅ | ✅ `RETURNS TABLE` / `SETOF` | ✅ `REFCURSOR` | ✅ | ✅ |
| Oracle | ✅ | ✅ `PIPELINED` | ✅ `SYS_REFCURSOR` | ✅ `%ROWTYPE` | ❌ |
| SQL Server | ✅ | ✅ `RETURNS TABLE` | ✅ (CURSOR OUTPUT) | ❌ | ❌ |
| MySQL | ✅ | ❌ (过程可返回结果集) | ✅ (过程内) | ❌ | ❌ |
| DB2 | ✅ | ✅ `RETURNS TABLE` | ✅ | ✅ `ROW` | ❌ |
| Snowflake | ✅ | ✅ `RETURNS TABLE` | ❌ | ✅ `OBJECT` | ❌ |
| BigQuery | ✅ | ❌ (过程可返回结果集) | ❌ | ✅ `STRUCT` | ❌ |
| SAP HANA | ✅ | ✅ `RETURNS TABLE` | ✅ | ❌ | ❌ |
| Firebird | ✅ | ✅ `SUSPEND` | ❌ | ❌ | ❌ |

### PostgreSQL 多种返回方式

```sql
-- 返回 SETOF（集合返回函数）
CREATE FUNCTION active_users() RETURNS SETOF users
LANGUAGE sql STABLE AS $$
    SELECT * FROM users WHERE active = true;
$$;

-- 返回 TABLE（命名列）
CREATE FUNCTION user_stats()
RETURNS TABLE(dept TEXT, cnt BIGINT, avg_salary NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT department, COUNT(*), AVG(salary)
    FROM users GROUP BY department;
$$;

-- 返回复合类型
CREATE TYPE point3d AS (x FLOAT, y FLOAT, z FLOAT);
CREATE FUNCTION make_point(x FLOAT, y FLOAT, z FLOAT) RETURNS point3d
LANGUAGE sql IMMUTABLE AS $$
    SELECT ROW(x, y, z)::point3d;
$$;

-- OUT 参数（等效于复合返回）
CREATE FUNCTION get_bounds(arr INT[], OUT min_val INT, OUT max_val INT)
LANGUAGE sql IMMUTABLE AS $$
    SELECT MIN(v), MAX(v) FROM unnest(arr) AS v;
$$;
```

## 特殊引擎的独有设计

### ClickHouse: 可执行 UDF

ClickHouse 除 Lambda UDF 外，支持通过外部程序定义 UDF：

```xml
<!-- /etc/clickhouse-server/config.d/executable_udf.xml -->
<function>
    <name>my_sentiment</name>
    <type>executable</type>
    <command>sentiment.py</command>
    <format>TabSeparated</format>
    <argument><type>String</type></argument>
    <return_type>Float32</return_type>
</function>
```

```sql
SELECT my_sentiment('This product is great!');  -- 0.95
```

这是一种进程间 UDF 模型，通过 stdin/stdout 通信。性能低于内嵌 UDF 但安全性更高。

### DuckDB: MACRO 系统

DuckDB 的 MACRO 不是传统函数，而是**语法宏**，在计划阶段内联展开：

```sql
-- 标量 MACRO
CREATE MACRO add_tax(price, rate := 0.1) AS price * (1 + rate);

-- 表 MACRO
CREATE MACRO filtered_orders(min_amount) AS TABLE
    SELECT * FROM orders WHERE amount >= min_amount;

-- 使用
SELECT add_tax(100);              -- 110
SELECT * FROM filtered_orders(1000);
```

MACRO 没有运行时调用开销，但也意味着没有独立的执行上下文、无法使用过程化逻辑。

### SQLite: 宿主语言注册

SQLite 不支持 SQL 层面的 CREATE FUNCTION，所有 UDF 通过宿主语言的 C API 注册：

```c
// C API 注册标量函数
sqlite3_create_function(db, "my_upper", 1, SQLITE_UTF8, NULL,
    my_upper_func, NULL, NULL);

// C API 注册聚合函数
sqlite3_create_function(db, "my_median", 1, SQLITE_UTF8, NULL,
    NULL, my_median_step, my_median_final);
```

Python 等语言提供了更友好的封装：

```python
import sqlite3
conn = sqlite3.connect(':memory:')
conn.create_function("my_upper", 1, lambda s: s.upper() if s else None)
conn.create_aggregate("my_sum", 1, MySumAgg)
```

### Snowflake: 多语言 UDF

Snowflake 允许在同一数据库中混用多种语言的 UDF：

```sql
-- SQL UDF
CREATE FUNCTION area_sql(r FLOAT) RETURNS FLOAT AS $$ 3.14159 * r * r $$;

-- JavaScript UDF
CREATE FUNCTION area_js(r FLOAT) RETURNS FLOAT
LANGUAGE JAVASCRIPT AS $$ return 3.14159 * R * R; $$;

-- Python UDF
CREATE FUNCTION area_py(r FLOAT) RETURNS FLOAT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
HANDLER = 'compute_area'
AS $$
def compute_area(r):
    import math
    return math.pi * r * r
$$;

-- Java UDF
CREATE FUNCTION area_java(r DOUBLE) RETURNS DOUBLE
LANGUAGE JAVA
HANDLER = 'MyMath.area'
AS $$
class MyMath {
    public static double area(double r) {
        return Math.PI * r * r;
    }
}
$$;
```

### Teradata: 事务语义

Teradata 的过程在事务控制上有独特约束：

```sql
CREATE PROCEDURE td_proc(IN p_id INTEGER, OUT p_result VARCHAR(100))
BEGIN
    DECLARE v_cnt INTEGER;
    SELECT COUNT(*) INTO v_cnt FROM my_table WHERE id = p_id;
    IF v_cnt > 0 THEN
        SET p_result = 'FOUND';
    ELSE
        SET p_result = 'NOT FOUND';
    END IF;
END;
```

Teradata 区分 ANSI 模式（自动提交）和 BTET 模式（显式事务），过程行为因会话模式而异。

## 跨引擎语法快速参考

### 创建过程

| 引擎 | 语法骨架 |
|------|---------|
| Oracle | `CREATE [OR REPLACE] PROCEDURE name (params) AS BEGIN ... END;` |
| PostgreSQL | `CREATE [OR REPLACE] PROCEDURE name (params) LANGUAGE plpgsql AS $$ BEGIN ... END; $$;` |
| SQL Server | `CREATE [OR ALTER] PROCEDURE name @params AS BEGIN ... END;` |
| MySQL | `CREATE PROCEDURE name (params) BEGIN ... END;` |
| DB2 | `CREATE [OR REPLACE] PROCEDURE name (params) BEGIN ... END;` |
| Snowflake | `CREATE [OR REPLACE] PROCEDURE name (params) RETURNS ... LANGUAGE ... AS $$ ... $$;` |
| BigQuery | `CREATE [OR REPLACE] PROCEDURE name (params) BEGIN ... END;` |
| SAP HANA | `CREATE [OR REPLACE] PROCEDURE name (params) LANGUAGE SQLSCRIPT AS BEGIN ... END;` |
| Firebird | `CREATE [OR ALTER] PROCEDURE name (params) [RETURNS (...)] AS BEGIN ... END` |

### 创建函数

| 引擎 | 语法骨架 |
|------|---------|
| Oracle | `CREATE [OR REPLACE] FUNCTION name (params) RETURN type AS BEGIN ... RETURN ...; END;` |
| PostgreSQL | `CREATE [OR REPLACE] FUNCTION name (params) RETURNS type LANGUAGE ... AS $$ ... $$;` |
| SQL Server | `CREATE [OR ALTER] FUNCTION name (@params) RETURNS type AS BEGIN RETURN ...; END;` |
| MySQL | `CREATE FUNCTION name (params) RETURNS type BEGIN RETURN ...; END;` |
| DB2 | `CREATE [OR REPLACE] FUNCTION name (params) RETURNS type RETURN ...;` |
| Snowflake | `CREATE [OR REPLACE] FUNCTION name (params) RETURNS type AS $$ ... $$;` |
| BigQuery | `CREATE [OR REPLACE] FUNCTION name (params) RETURNS type AS (expr);` |
| ClickHouse | `CREATE FUNCTION name AS (params) -> expr;` |
| DuckDB | `CREATE MACRO name (params) AS expr;` |
| Trino | `CREATE FUNCTION name (params) RETURNS type [DETERMINISTIC] RETURN expr;` |

## 对引擎开发者的实现建议

### 1. 函数调用框架设计

函数执行的核心数据流：

```
调用者 → 参数求值 → 参数绑定 → 函数体执行 → 返回值 → 调用者
```

关键设计决策：
- **栈帧管理**：每次函数调用需要独立的变量作用域。递归函数要求栈帧可嵌套。PostgreSQL 使用 PLpgSQL_execstate 结构体管理执行状态，Oracle 的 PGA 内存区为每个会话分配独立调用栈。
- **参数传递模式**：IN 参数可以传值或传引用（对大对象如 LOB 传引用更高效）；OUT 参数通常需要在调用者栈帧中预分配空间。
- **返回值传递**：标量返回简单直接；集合返回需要 iterator/pipeline 模式避免一次性物化全部结果。

### 2. 确定性标记的优化利用

```
IMMUTABLE/DETERMINISTIC:
  ├─ 计划阶段: 常量折叠 (constant folding)
  ├─ 索引: 可用于函数索引 / 表达式索引
  ├─ 物化视图: 可用于增量刷新判断
  └─ 并行: 默认安全

STABLE:
  ├─ 单语句内: 可缓存调用结果 (memoization)
  ├─ 索引: 不可用于函数索引
  └─ WHERE 子句: 可提前求值一次

VOLATILE:
  ├─ 每次调用必须重新求值
  ├─ 不可出现在索引定义中
  └─ 可能阻止某些优化（如谓词下推）
```

实现建议：在函数元数据中存储确定性标记，在优化器的 constant folding pass 和 predicate pushdown pass 中检查此标记。即使引擎不暴露这些关键字给用户，内部也应维护等价的元信息。

### 3. 安全上下文切换

SECURITY DEFINER 的实现要点：
- 在函数入口处保存当前用户上下文，切换到定义者身份
- 在函数退出（包括异常退出）时恢复调用者身份
- 必须使用 RAII 或 finally 模式保证上下文恢复
- `search_path` / 当前 schema 也需要同步切换

```
进入函数 → 保存 {user_id, search_path, role_list}
         → 切换到 definer 的身份
         → 执行函数体
         → [异常?] → 恢复上下文 → 重新抛出异常
         → 恢复上下文 → 返回结果
```

### 4. 过程化语言的嵌入架构

支持多语言 UDF 的引擎需要一个语言运行时抽象层：

```
SQL 引擎层
   │
   ├── 内置 SQL 函数执行器
   ├── PL 语言处理器接口 (Language Handler)
   │    ├── PL/pgSQL 解释器
   │    ├── PL/Python 桥接 (CPython 嵌入)
   │    ├── PL/Java 桥接 (JNI)
   │    └── PL/v8 桥接 (V8 引擎)
   └── 外部 UDF 接口
        └── stdin/stdout 进程通信 (ClickHouse 模式)
```

PostgreSQL 的 Language Handler 接口设计值得参考：每种语言注册一个 handler 函数和一个 validator 函数。handler 接收函数 OID 和参数，负责调用目标语言运行时。

外部语言的安全隔离策略：
- **进程内沙箱**：限制系统调用（seccomp）、限制内存（cgroup）
- **进程隔离**：独立进程运行 UDF，通过 IPC 通信（如 Snowflake 的 Python UDF）
- **容器隔离**：最强隔离，但延迟最高

### 5. 异常处理的实现

过程化语言的异常处理比标准 try-catch 更复杂，因为涉及事务状态：

```
PostgreSQL 模型:
  BEGIN (隐式 savepoint)
    → 语句执行
    → [异常] → 回滚到 savepoint
             → 进入 EXCEPTION 块
             → EXCEPTION 块可以:
                 a) 处理异常并继续
                 b) 重新抛出 (RAISE)
```

实现注意：
- PL/pgSQL 的每个 `BEGIN...EXCEPTION...END` 块在进入时创建一个 savepoint。这有性能开销，因此无 EXCEPTION 子句的 BEGIN 块不创建 savepoint。
- MySQL 的 HANDLER 模型不同：HANDLER 在声明时注册，异常发生时自动调用，不需要 savepoint。
- 引擎应记录异常链（cause chain），方便调试嵌套调用。

### 6. 集合返回函数 (SRF) 的执行模型

SRF 的核心挑战是避免将全部结果物化到内存：

- **Iterator 模型**（PostgreSQL）：SRF 实现为协程，每次 `RETURN NEXT` 或 `RETURN QUERY` 产出一行，执行器拉取下一行时恢复执行。
- **Pipeline 模型**（Oracle PIPELINED）：`PIPE ROW` 语义与 PostgreSQL 类似，但通过 ODCITable 接口实现。
- **物化模型**（SQL Server Multi-statement TVF）：先执行完整函数体填充表变量，再返回。性能较差但实现简单。

建议优先实现 iterator 模型，因为它与 Volcano 执行器天然契合。

### 7. 函数重载的解析算法

实现重载解析的推荐步骤：

1. 收集所有同名候选函数
2. 排除参数个数不匹配的候选（考虑 DEFAULT 参数）
3. 对每个参数位置计算类型匹配度：精确匹配 > 隐式转换 > 无法匹配
4. 选择总体匹配度最高的候选
5. 如存在歧义（多个候选得分相同），报错

PostgreSQL 的类型优先级链定义在 `pg_type.typpreferred` 中，可参考其 `func_select_candidate()` 实现。

### 8. 性能考量

| 方面 | 建议 |
|------|------|
| 调用开销 | SQL UDF 可内联到调用查询中（PostgreSQL 对简单 SQL 函数做 inlining）；PL 函数无法内联 |
| 计划缓存 | 为 PL 函数中的 SQL 语句缓存执行计划（PostgreSQL 的 SPI plan cache） |
| JIT | 对高频调用的标量函数考虑 JIT 编译（DuckDB 方向） |
| 批处理 | 外部语言 UDF 应支持向量化/批量调用以减少跨语言调用开销 |
| 内存管理 | 每次函数调用应在独立内存上下文中分配，调用结束后统一释放 |

### 9. 元数据存储

函数/过程的元数据至少需要存储：

| 字段 | 说明 |
|------|------|
| 名称 | 标识符 |
| 参数列表 | 名称、类型、方向（IN/OUT/INOUT）、默认值 |
| 返回类型 | 标量类型 / TABLE 定义 / VOID |
| 语言 | SQL / plpgsql / javascript / python / ... |
| 函数体 | 源代码文本 |
| 确定性 | IMMUTABLE / STABLE / VOLATILE |
| 安全模式 | DEFINER / INVOKER |
| 并行安全 | SAFE / RESTRICTED / UNSAFE |
| 所有者 | 创建者用户 ID |
| ACL | 执行权限列表 |

PostgreSQL 的 `pg_proc` 系统表是一个成熟的参考实现。
