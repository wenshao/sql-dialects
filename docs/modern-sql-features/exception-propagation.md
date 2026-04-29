# 异常传播 (Exception Propagation)

存储过程嵌套调用三层，最里层 `RAISE EXCEPTION` 抛出后会发生什么？UDF 在 `SELECT` 列表中除以零会让整个查询失败，还是只让那一行返回 NULL？`AFTER INSERT` 触发器里抛出的错误，会回滚刚刚的 INSERT 还是只回滚触发器自己的副作用？这三个问题的答案在 PostgreSQL、Oracle、SQL Server、MySQL、DB2 之间几乎完全不同——异常在控制流栈、事务边界、触发上下文之间的传播路径，是过程化 SQL 中最反直觉、最容易踩坑的语义边界。

## 没有 SQL 标准，但有 SQL/PSM HANDLER

ISO/IEC 9075 SQL 标准从未定义"异常传播"为独立概念。SQL/PSM (Persistent Stored Modules, ISO/IEC 9075-4) 在 SQL:1999 中引入了 `DECLARE HANDLER` 语句作为存储过程的异常处理机制，区分 `CONTINUE` 与 `EXIT` 两种处理动作；SIGNAL/RESIGNAL 语句在 SQL:2003 中正式纳入标准（MySQL 5.5 在 2010 年实现）。但标准对"异常如何在嵌套调用栈中向上传播"、"未捕获的异常是否回滚事务"、"触发器抛出异常对原 DML 的影响"这些核心问题留给了实现者自由发挥。

各引擎的设计哲学因此分裂为几个流派：**SQL Server TRY/CATCH 流派** (2005+) 借鉴 C#/.NET 的结构化异常处理，错误后事务进入"不可提交"状态需要显式回滚；**Oracle PL/SQL 流派** (v6+) 早在 1980 年代就实现了 `EXCEPTION` 块和 `PRAGMA EXCEPTION_INIT`，未捕获异常向上传播至最外层调用者；**PostgreSQL PL/pgSQL 流派** 模仿 Oracle 但将 EXCEPTION 块绑定为子事务（隐式 SAVEPOINT）；**MySQL/DB2 SQL/PSM 流派** 严格遵循标准的 `DECLARE HANDLER` 模型；**SQLite 等无过程化语言的引擎** 则通过特殊的 `RAISE()` 函数和 `ON CONFLICT` 子句简化异常控制。理解这些差异是为了避免一个最常见的 bug：**触发器中的错误是否会自动回滚那条触发它的 DML？** 答案在不同引擎中截然不同。

## 支持矩阵（综合）

### 异常抛出语法

| 引擎 | RAISE | RAISERROR/THROW | SIGNAL | 自定义异常 | 版本 |
|------|-------|----------------|--------|-----------|------|
| PostgreSQL | `RAISE EXCEPTION` | -- | -- | SQLSTATE 'P0001' | 8.0+ |
| Oracle | `RAISE` / `RAISE_APPLICATION_ERROR` | -- | -- | `EXCEPTION` 声明 + `PRAGMA EXCEPTION_INIT` | v6+ |
| SQL Server | -- | `RAISERROR` / `THROW` | -- | `sp_addmessage` | 2000+ / 2012+ |
| Azure SQL | -- | `RAISERROR` / `THROW` | -- | `sp_addmessage` | GA |
| MySQL | -- | -- | `SIGNAL SQLSTATE` | `DECLARE cond CONDITION` | 5.5+ |
| MariaDB | -- | -- | `SIGNAL SQLSTATE` | `DECLARE cond CONDITION` | 5.5+ |
| DB2 (LUW) | -- | -- | `SIGNAL SQLSTATE` / `RESIGNAL` | `DECLARE cond CONDITION` | V7+ |
| DB2 (z/OS) | -- | -- | `SIGNAL SQLSTATE` | `DECLARE cond CONDITION` | V7+ |
| SQLite | `RAISE(ABORT/FAIL/IGNORE/ROLLBACK)` | -- | -- | -- | 3.0+ |
| Snowflake | `RAISE` (Scripting) | -- | -- | `DECLARE cond EXCEPTION` | GA |
| BigQuery | `RAISE USING MESSAGE` | -- | -- | -- | 2023+ |
| Redshift | `RAISE EXCEPTION` (PL/pgSQL) | -- | -- | SQLSTATE | GA |
| CockroachDB | `RAISE EXCEPTION` | -- | -- | SQLSTATE | v20.1+ |
| YugabyteDB | `RAISE EXCEPTION` | -- | -- | SQLSTATE | 2.6+ |
| TiDB | -- | -- | `SIGNAL SQLSTATE` | `DECLARE cond CONDITION` | 6.1+ |
| OceanBase (MySQL) | -- | -- | `SIGNAL SQLSTATE` | -- | V3+ |
| OceanBase (Oracle) | `RAISE` / `RAISE_APPLICATION_ERROR` | -- | -- | `EXCEPTION` 声明 | V3+ |
| Teradata | -- | -- | `SIGNAL SQLSTATE` | -- | V14+ |
| SAP HANA | `SIGNAL` / `RESIGNAL` | -- | -- | `DECLARE cond CONDITION` | SPS09+ |
| Informix | `RAISE EXCEPTION` | -- | -- | `EXCEPTION` 块 | 11.50+ |
| Firebird | `EXCEPTION ex_name` | -- | -- | `CREATE EXCEPTION` | 1.0+ |
| Greenplum | `RAISE EXCEPTION` | -- | -- | SQLSTATE | 5.0+ |
| Vertica | -- | -- | -- | -- | 不支持 |
| SingleStore | -- | -- | `SIGNAL SQLSTATE` | -- | 7.0+ |
| Exasol | `RAISE` | -- | -- | SQLSTATE | 6.0+ |
| Databricks | `RAISE_ERROR()` 函数 | -- | `SIGNAL` (PL ext) | -- | Runtime 11+ |
| TimescaleDB | `RAISE EXCEPTION` | -- | -- | -- | 继承 PG |
| AlloyDB | `RAISE EXCEPTION` | -- | -- | -- | 继承 PG |
| Neon | `RAISE EXCEPTION` | -- | -- | -- | 继承 PG |
| EnterpriseDB | `RAISE` / `RAISE_APPLICATION_ERROR` | -- | -- | -- | 兼容 Oracle |
| 达梦 | `RAISE` / `RAISE_APPLICATION_ERROR` | -- | -- | -- | Oracle 兼容 |
| 金仓 | `RAISE` / `RAISE_APPLICATION_ERROR` | -- | -- | -- | Oracle 兼容 |
| openGauss | `RAISE EXCEPTION` | -- | -- | -- | 2.0+ |
| GaussDB | `RAISE` | -- | `SIGNAL` | -- | GA |
| PolarDB (PG) | `RAISE EXCEPTION` | -- | -- | -- | 继承 PG |
| PolarDB (Oracle) | `RAISE` / `RAISE_APPLICATION_ERROR` | -- | -- | -- | 兼容 Oracle |
| PolarDB (MySQL) | -- | -- | `SIGNAL` | -- | 继承 MySQL |
| Aurora (PG) | `RAISE EXCEPTION` | -- | -- | -- | 继承 PG |
| Aurora (MySQL) | -- | -- | `SIGNAL` | -- | 继承 MySQL |
| H2 | -- | -- | `SIGNAL` (有限) | -- | 1.4+ |
| HSQLDB | -- | -- | `SIGNAL` | -- | 2.0+ |
| Derby | -- | -- | `SIGNAL` (有限) | -- | 10.x+ |
| DuckDB | `error()` 函数 | -- | -- | -- | 0.x+ |
| ClickHouse | `throwIf()` 函数 | -- | -- | -- | 早期 |
| MonetDB | -- | -- | -- | -- | 不支持 |
| Trino | `fail()` 函数 | -- | -- | -- | 早期 |
| Presto | `fail()` 函数 | -- | -- | -- | 早期 |
| Spark SQL | `raise_error()` | -- | -- | -- | 3.0+ |
| Hive | -- | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | -- | 不支持 |
| Impala | -- | -- | -- | -- | 不支持 |
| StarRocks | -- | -- | -- | -- | 不支持 |
| Doris | -- | -- | -- | -- | 不支持 |
| Athena | `fail()` 函数 | -- | -- | -- | 继承 Trino |

> 注：`fail()` / `error()` / `throwIf()` 等函数主要用于查询中触发错误（如断言失败），不属于完整的过程化异常处理体系。

### HANDLER 类型支持

| 引擎 | CONTINUE | EXIT | UNDO | SQLEXCEPTION | NOT FOUND | 命名条件 | 版本 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|------|
| MySQL | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | 5.0+ |
| MariaDB | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | 5.0+ |
| DB2 (LUW) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | V7+ |
| DB2 (z/OS) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | V7+ |
| TiDB | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | 6.1+ |
| OceanBase (MySQL) | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | V3+ |
| Teradata | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | V14+ |
| SAP HANA | ❌ | ✅ | ❌ | ✅ | ❌ | ✅ | SPS09+ |
| SingleStore | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ | 7.0+ |
| HSQLDB | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 2.0+ |
| Aurora (MySQL) | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | 继承 MySQL |
| PolarDB (MySQL) | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | 继承 MySQL |

> SQL/PSM 标准定义了 `CONTINUE`、`EXIT`、`UNDO` 三种 handler 动作。其中 `UNDO` 仅 DB2 和 HSQLDB 实现，要求复合语句以 `BEGIN ATOMIC` 形式声明。

### 触发器中未捕获异常 → 回滚触发 DML

| 引擎 | BEFORE 异常回滚 | AFTER 异常回滚 | INSTEAD OF 异常回滚 | 备注 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | ✅ 取消 DML | ✅ 取消 DML | ✅ 取消 DML | 整个语句原子失败 |
| MySQL | ✅ (InnoDB) | ✅ (InnoDB) | -- | 仅事务存储引擎；MyISAM 不回滚 |
| MariaDB | ✅ (InnoDB) | ✅ (InnoDB) | -- | 同 MySQL |
| Oracle | ✅ | ✅ | ✅ | 整个语句回滚（不是事务） |
| SQL Server | ❌ (无 BEFORE) | ✅ (2005+) | ✅ | 2005 前需要手动 ROLLBACK |
| DB2 | ✅ | ✅ | ✅ | BEGIN ATOMIC 提供原子性 |
| SQLite | ✅ (RAISE ABORT/ROLLBACK/FAIL) | ✅ | ✅ | ROLLBACK 撤销整个事务 |
| Firebird | ✅ | ✅ | -- | -- |
| Informix | ✅ | ✅ | -- | -- |
| H2 | ✅ | ✅ | ✅ | -- |
| HSQLDB | ✅ | ✅ | ✅ | -- |
| CockroachDB | ✅ | ✅ | -- | 22.2+ |
| YugabyteDB | ✅ | ✅ | ✅ | 继承 PG |
| OceanBase | ✅ | ✅ | ✅ | -- |
| Greenplum | ✅ | ✅ | ✅ | 继承 PG |
| TimescaleDB | ✅ | ✅ | ✅ | 继承 PG |
| Teradata | ✅ | ✅ | -- | -- |
| SAP HANA | ✅ | ✅ | ✅ | -- |

> 关键语义：在大多数引擎中，触发器中**未捕获**的异常会回滚**触发它的 DML 语句**（不是整个事务，除非外层无更多语句）。这是触发器作为约束机制的核心保障。

### UDF 错误对查询的影响

| 引擎 | UDF 错误中止整条语句 | UDF 错误隔离到一行 | TRY/SAFE 包装 | 版本 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | ✅ | ❌ | 自定义 try 函数 | 8.0+ |
| Oracle | ✅ | ❌ | `EXCEPTION` 内捕获 | 7.0+ |
| SQL Server | ✅ | ❌ | UDF 内不能 TRY/CATCH 部分错误 | 2005+ |
| MySQL | ✅ | ❌ | 函数内 HANDLER | 5.0+ |
| Snowflake | ✅ | ❌ | `TRY_*` 系列函数 | GA |
| BigQuery | ✅ | ❌ | `SAFE.func()` 前缀 | GA |
| ClickHouse | ✅ | ❌ | `OrNull` / `OrZero` 后缀 | 早期 |
| Trino | ✅ | ❌ | `TRY()` 包装器 | 早期 |
| Spark SQL | ✅ | ❌ | `try_*` 系列函数 | 3.0+ |
| DuckDB | ✅ | ❌ | `TRY_CAST` | 0.8+ |

> 标准语义：UDF 抛出未捕获异常会终止整个 SQL 语句的执行（即使只有一行触发错误）。要实现"一行错误其他继续"的容错行为，必须使用各引擎特定的 `TRY_*` / `SAFE_*` / `OrNull` 包装器，或在 UDF 内部捕获异常并返回 NULL。

### 嵌套过程调用异常传播

| 引擎 | 隐式向上传播 | 必须显式 RESIGNAL/RAISE | 调用栈信息 | 版本 |
|------|:---:|:---:|:---:|------|
| PostgreSQL | ✅ | ❌ | `PG_EXCEPTION_CONTEXT` | 8.0+ |
| Oracle | ✅ | ❌ | `DBMS_UTILITY.FORMAT_ERROR_BACKTRACE` | 7.0+ |
| SQL Server | ✅ | ❌ | `ERROR_PROCEDURE()` / `ERROR_LINE()` | 2005+ |
| MySQL | ✅ | ❌ (除非已捕获) | `RESIGNAL` 重抛 | 5.5+ |
| DB2 | ✅ | ❌ (除非已捕获) | `DIAGNOSTICS_AREA` | V7+ |
| Snowflake | ✅ | ❌ | `SQLERRM` | GA |
| BigQuery | ✅ | ❌ | `@@error.stack_trace` | 2023+ |
| Firebird | ✅ | ❌ | -- | 1.0+ |

## 核心概念：异常传播路径

### 三层调用栈中的异常流向

```
最外层 (主程序/应用)
    │
    └─> 中间层过程 P1 (调用 P2)
              │
              └─> 内层过程 P2 (调用 P3)
                        │
                        └─> 最内层过程 P3 (RAISE EXCEPTION)
                                  │
                                  ▼ 异常向上传播
                              P3 中无 EXCEPTION 块捕获
                                  │
                                  ▼
                              P2 是否有 EXCEPTION 块？
                                  │
                                  ├─是─> 捕获，P2 正常返回 (异常被吞噬)
                                  │
                                  └─否─> 继续向上
                                       │
                                       ▼
                                  P1 是否有 EXCEPTION 块？
                                       │
                                       ├─是─> 捕获
                                       │
                                       └─否─> 继续向上至最外层
                                             │
                                             ▼
                                       事务回滚 + 客户端报错
```

每层是否捕获异常、是否重抛、是否影响事务状态——这些行为在不同引擎中差异巨大。

### 关键问题：捕获后事务状态

```
SQL Server (TRY/CATCH):
  CATCH 内可调用 ROLLBACK，但事务可能已是 "uncommittable"
  XACT_STATE() = -1 表示事务被中毒，必须 ROLLBACK
  XACT_STATE() = 1 表示事务正常，可以 COMMIT

PostgreSQL (BEGIN..EXCEPTION):
  EXCEPTION 块隐式回滚到块开始处的 SAVEPOINT
  外层事务状态保留，可以继续工作
  函数内不能 COMMIT/ROLLBACK 整个事务

Oracle (BEGIN..EXCEPTION):
  EXCEPTION 块捕获异常后事务状态不变
  必须显式 ROLLBACK 或 ROLLBACK TO SAVEPOINT
  存储过程内可以 COMMIT/ROLLBACK

MySQL (DECLARE HANDLER):
  CONTINUE handler 后事务保留所有变更
  EXIT handler 默认不回滚，需显式 ROLLBACK
  事务不会因异常自动回滚（除连接断开）
```

## 各引擎详解

### PostgreSQL（最严格的子事务模型）

PostgreSQL 的 `BEGIN..EXCEPTION..END` 块通过隐式 SAVEPOINT 提供子事务语义，是各引擎中行为最容易理解的：

```sql
-- 完整异常处理示例
CREATE OR REPLACE FUNCTION transfer_funds(
    p_from INT, p_to INT, p_amount DECIMAL
) RETURNS TEXT AS $$
DECLARE
    v_balance DECIMAL;
    v_sqlstate TEXT;
    v_message TEXT;
    v_context TEXT;
BEGIN
    -- 内层块创建子事务
    BEGIN
        SELECT balance INTO STRICT v_balance
        FROM accounts WHERE id = p_from FOR UPDATE;

        IF v_balance < p_amount THEN
            RAISE EXCEPTION '余额不足: 当前 %, 需要 %', v_balance, p_amount
                USING ERRCODE = 'P0001',
                      HINT = '请存入更多资金',
                      DETAIL = format('账户 %s', p_from);
        END IF;

        UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
        UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;

    EXCEPTION
        WHEN no_data_found THEN
            RETURN 'ACCOUNT_NOT_FOUND';
        WHEN insufficient_privilege THEN
            RETURN 'PERMISSION_DENIED';
        WHEN check_violation THEN
            RETURN 'CONSTRAINT_VIOLATED';
        WHEN OTHERS THEN
            -- 获取完整诊断信息
            GET STACKED DIAGNOSTICS
                v_sqlstate = RETURNED_SQLSTATE,
                v_message = MESSAGE_TEXT,
                v_context = PG_EXCEPTION_CONTEXT;
            -- 子事务回滚到 BEGIN 处，但函数继续
            INSERT INTO error_log(sqlstate, message, context, occurred_at)
            VALUES (v_sqlstate, v_message, v_context, NOW());
            RETURN 'ERROR: ' || v_sqlstate;
    END;

    -- 即使内层捕获了异常，外层依然继续执行
    RETURN 'SUCCESS';
END;
$$ LANGUAGE plpgsql;
```

PostgreSQL 异常传播的关键事实：

```
1. 每个 BEGIN..EXCEPTION 块隐式创建 SAVEPOINT
   - 进入块时: SAVEPOINT
   - 块成功结束: RELEASE SAVEPOINT
   - 异常被捕获: ROLLBACK TO SAVEPOINT
   - 性能开销: 每次 SAVEPOINT 约 5-10us，循环内大量使用需注意

2. 函数内不能直接 COMMIT/ROLLBACK 整个事务
   - PROCEDURE (11+) 可以
   - FUNCTION 不可以

3. 异常通过 SQLSTATE 标识，不是异常对象
   - 预定义条件名: unique_violation, foreign_key_violation 等
   - 自定义异常: USING ERRCODE = 'P0001' (P0xxx 是用户保留)
   - WHEN OTHERS 不捕获 'QUERY_CANCELED' 和 'ASSERT_FAILURE'

4. 异常向上传播规则:
   - 未被任何 EXCEPTION 块捕获 → 函数失败 → 调用方语句失败
   - 调用方有 EXCEPTION 块 → 子事务回滚，调用方继续
   - 整个事务回滚仅当最外层语句失败
```

PostgreSQL 嵌套调用异常传播示例：

```sql
-- 最内层
CREATE FUNCTION level3() RETURNS VOID AS $$
BEGIN
    RAISE EXCEPTION 'Level 3 error'
        USING ERRCODE = 'P0001',
              HINT = 'Innermost error';
END;
$$ LANGUAGE plpgsql;

-- 中间层 (不捕获)
CREATE FUNCTION level2() RETURNS VOID AS $$
BEGIN
    PERFORM level3();
    -- 此行永不执行
    RAISE NOTICE 'Level 2 success';
END;
$$ LANGUAGE plpgsql;

-- 最外层 (捕获)
CREATE FUNCTION level1() RETURNS TEXT AS $$
DECLARE
    v_message TEXT;
    v_context TEXT;
BEGIN
    PERFORM level2();
    RETURN 'Success';
EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_message = MESSAGE_TEXT,
            v_context = PG_EXCEPTION_CONTEXT;
        -- v_context 包含完整调用栈:
        --   PL/pgSQL function level3() line 3 at RAISE
        --   PL/pgSQL function level2() line 3 at PERFORM
        --   PL/pgSQL function level1() line 5 at PERFORM
        RETURN 'Caught: ' || v_message;
END;
$$ LANGUAGE plpgsql;

SELECT level1();
-- 返回: Caught: Level 3 error
```

### Oracle PL/SQL（业界最早的 EXCEPTION 块）

Oracle 在 PL/SQL 7.0 (1992) 引入完整的 `EXCEPTION` 块和命名异常机制，是后续所有"BEGIN..EXCEPTION..END"模型的鼻祖：

```sql
DECLARE
    -- 1. 命名异常: 绑定到 ORA 错误码
    e_balance_negative EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_balance_negative, -20001);

    e_account_locked EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_account_locked, -20002);

    -- 2. 用户定义异常 (无 ORA 错误码)
    e_business_rule EXCEPTION;

    v_balance NUMBER;
BEGIN
    -- 3. RAISE: 抛出命名/用户异常
    SELECT balance INTO v_balance FROM accounts WHERE id = 101;
    IF v_balance < 0 THEN
        RAISE e_balance_negative;
    END IF;

    -- 4. RAISE_APPLICATION_ERROR: 抛出带消息的应用错误
    --    错误号必须在 -20000 到 -20999 之间
    IF v_balance > 1000000 THEN
        RAISE_APPLICATION_ERROR(-20003, '余额异常高: ' || v_balance);
    END IF;

EXCEPTION
    WHEN e_balance_negative THEN
        DBMS_OUTPUT.PUT_LINE('余额为负');
        ROLLBACK;
    WHEN e_account_locked THEN
        DBMS_OUTPUT.PUT_LINE('账户已锁');
    WHEN NO_DATA_FOUND THEN  -- 预定义异常
        DBMS_OUTPUT.PUT_LINE('账户不存在');
    WHEN VALUE_ERROR THEN     -- 预定义异常 (ORA-06502)
        DBMS_OUTPUT.PUT_LINE('值类型错误');
    WHEN OTHERS THEN
        -- 5. SQLCODE / SQLERRM: 错误号和消息
        DBMS_OUTPUT.PUT_LINE('错误码: ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('错误消息: ' || SQLERRM);

        -- 6. 调用栈 (10g+)
        DBMS_OUTPUT.PUT_LINE('错误回溯:');
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_STACK);

        -- 7. RAISE; (无参数) 重新抛出当前异常
        RAISE;
END;
/
```

Oracle 异常传播的关键事实：

```
1. PRAGMA EXCEPTION_INIT 绑定 ORA 错误码到命名异常
   - 仅支持负的错误码 (Oracle 错误均为负)
   - -20000 ~ -20999 是用户保留范围
   - 用 RAISE_APPLICATION_ERROR 在此范围抛错

2. EXCEPTION 块不创建子事务 (与 PG 的关键差异)
   - 异常被捕获后，已经做的 DML 仍然在事务中
   - 必须显式 ROLLBACK 或 ROLLBACK TO SAVEPOINT 撤销
   - 这与 PG 的子事务自动回滚是反直觉的

3. 预定义异常 (PL/SQL 内置)
   预定义异常名             ORA 错误码
   ───────────────────  ──────────
   NO_DATA_FOUND        ORA-01403
   TOO_MANY_ROWS        ORA-01422
   INVALID_NUMBER       ORA-01722
   ZERO_DIVIDE          ORA-01476
   VALUE_ERROR          ORA-06502
   DUP_VAL_ON_INDEX     ORA-00001 (唯一约束)
   STORAGE_ERROR        ORA-06500 (PL/SQL 内存错误)
   PROGRAM_ERROR        ORA-06501 (PL/SQL 内部错误)
   TIMEOUT_ON_RESOURCE  ORA-00051

4. RAISE 语句的三种形式
   RAISE;                           -- 重抛当前异常 (仅 EXCEPTION 块内)
   RAISE e_my_exception;            -- 抛出命名异常
   RAISE_APPLICATION_ERROR(-20001, 'msg');  -- 抛出 ORA-20001
```

Oracle 嵌套调用异常传播示例：

```sql
CREATE OR REPLACE PROCEDURE level3 IS
BEGIN
    RAISE_APPLICATION_ERROR(-20003, 'Level 3 error');
END;
/

CREATE OR REPLACE PROCEDURE level2 IS
BEGIN
    level3;  -- 异常向上传播
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Level 2 caught: ' || SQLERRM);
        -- 不重抛: 异常在此被吞噬
        -- RAISE;  -- 如果重抛, 继续向上传播
END;
/

CREATE OR REPLACE PROCEDURE level1 IS
BEGIN
    level2;
    DBMS_OUTPUT.PUT_LINE('Level 1 success');  -- 此行执行
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Level 1 caught: ' || SQLERRM);
END;
/

EXEC level1;
-- 输出:
-- Level 2 caught: ORA-20003: Level 3 error
-- Level 1 success
```

### SQL Server（TRY/CATCH 结构化异常处理）

SQL Server 2005 引入 `BEGIN TRY..BEGIN CATCH..END CATCH`，借鉴 .NET 异常处理：

```sql
-- 完整 TRY/CATCH 示例
CREATE PROCEDURE transfer_funds
    @from_id INT, @to_id INT, @amount DECIMAL(10,2),
    @status NVARCHAR(50) OUTPUT
AS
BEGIN
    SET XACT_ABORT ON;  -- 关键：错误时自动回滚事务
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE accounts SET balance = balance - @amount
        WHERE id = @from_id;

        IF @@ROWCOUNT = 0
            THROW 60001, '转出账户不存在', 1;

        IF EXISTS (SELECT 1 FROM accounts WHERE id = @from_id AND balance < 0)
            THROW 60002, '转出后余额为负', 1;

        UPDATE accounts SET balance = balance + @amount
        WHERE id = @to_id;

        IF @@ROWCOUNT = 0
            THROW 60003, '转入账户不存在', 1;

        COMMIT TRANSACTION;
        SET @status = 'SUCCESS';
    END TRY
    BEGIN CATCH
        -- 检查事务状态
        DECLARE @xact_state INT = XACT_STATE();

        IF @xact_state = -1
        BEGIN
            -- 事务被中毒 (uncommittable)
            -- 必须 ROLLBACK，COMMIT 会失败
            ROLLBACK TRANSACTION;
        END
        ELSE IF @xact_state = 1
        BEGIN
            -- 事务仍可提交，但通常我们要回滚
            ROLLBACK TRANSACTION;
        END
        -- @xact_state = 0 表示无活动事务

        -- 收集错误信息
        DECLARE
            @err_num INT = ERROR_NUMBER(),
            @err_msg NVARCHAR(4000) = ERROR_MESSAGE(),
            @err_severity INT = ERROR_SEVERITY(),
            @err_state INT = ERROR_STATE(),
            @err_proc NVARCHAR(200) = ERROR_PROCEDURE(),
            @err_line INT = ERROR_LINE();

        INSERT INTO error_log(num, message, severity, state, proc, line, occurred_at)
        VALUES (@err_num, @err_msg, @err_severity, @err_state, @err_proc, @err_line, GETDATE());

        SET @status = 'FAILED: ' + @err_msg;

        -- 重抛 (SQL Server 2012+)
        ;THROW;
        -- 较旧的 RAISERROR 方式:
        -- RAISERROR(@err_msg, @err_severity, @err_state);
    END CATCH;
END;
GO
```

SQL Server 异常传播的关键事实：

```
1. XACT_STATE() 三种状态
   状态  含义                    可执行操作
   ────  ────────────────────   ────────────────
    1    活跃且可提交            COMMIT 或 ROLLBACK
    0    无活动事务              开始新事务
   -1    被中毒 (uncommittable)  仅 ROLLBACK

2. SET XACT_ABORT ON 的作用
   - 任何运行时错误都会自动 ROLLBACK
   - 不依赖 CATCH 块捕获
   - 强烈推荐在所有过程中开启

3. 不可捕获的错误
   - 严重级别 20+ (连接错误)
   - 编译错误 (语法、对象不存在等)
   - 客户端中断、超时
   - 攻击型错误 (CHECKDB 严重错误)

4. THROW vs RAISERROR
   特性             THROW (2012+)         RAISERROR
   ─────────────  ──────────────────  ─────────────────
   错误号范围        允许 50000+         必须 50000+
   保留原错误号      ✅ (无参数 THROW)   ❌
   消息中嵌入参数    ❌ 用 FORMATMESSAGE  ✅ printf 风格
   SET XACT_ABORT   按设置生效          按设置生效
   严重级别          固定为 16           可指定 0-25
   推荐程度          ✅ 现代             遗留兼容

5. CATCH 块中嵌套调用
   - CATCH 内的过程调用异常会冒泡到上层 CATCH
   - 如果上层无 CATCH，整个连接错误
   - SQL Server 不像 C# 有完整的异常对象，需用 ERROR_*() 函数提取
```

SQL Server 嵌套过程调用异常传播：

```sql
CREATE PROCEDURE level3
AS
BEGIN
    THROW 60001, 'Level 3 error', 1;
END;
GO

CREATE PROCEDURE level2
AS
BEGIN
    BEGIN TRY
        EXEC level3;
    END TRY
    BEGIN CATCH
        PRINT 'Level 2 caught: ' + ERROR_MESSAGE();
        ;THROW;  -- 重抛保留原始错误
    END CATCH;
END;
GO

CREATE PROCEDURE level1
AS
BEGIN
    BEGIN TRY
        EXEC level2;
    END TRY
    BEGIN CATCH
        PRINT 'Level 1 caught: ' + ERROR_MESSAGE();
        PRINT 'Original procedure: ' + ERROR_PROCEDURE();
        PRINT 'Line: ' + CAST(ERROR_LINE() AS VARCHAR(10));
        -- ERROR_PROCEDURE() 返回最初抛出错误的过程
        -- 即 'level3'，而非 'level2'
    END CATCH;
END;
GO
```

### MySQL / MariaDB（DECLARE HANDLER 模型）

MySQL 5.5 引入完整的 SIGNAL/RESIGNAL，DECLARE HANDLER 自 5.0 起：

```sql
DELIMITER $$

CREATE PROCEDURE transfer_funds(
    IN p_from INT, IN p_to INT, IN p_amount DECIMAL(10,2),
    OUT p_status VARCHAR(50)
)
BEGIN
    DECLARE v_balance DECIMAL(10,2);
    DECLARE v_error_occurred BOOLEAN DEFAULT FALSE;
    DECLARE v_sqlstate CHAR(5);
    DECLARE v_msg TEXT;
    DECLARE v_errno INT;

    -- 1. 命名条件
    DECLARE insufficient_funds CONDITION FOR SQLSTATE '45001';
    DECLARE account_not_found CONDITION FOR SQLSTATE '45002';

    -- 2. EXIT handler: 处理后退出当前 BEGIN..END
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_errno = MYSQL_ERRNO,
            v_msg = MESSAGE_TEXT;
        ROLLBACK;
        SET p_status = CONCAT('ERROR [', v_sqlstate, '/', v_errno, ']: ', v_msg);
        -- EXIT handler 在此处之后退出整个 BEGIN..END
    END;

    -- 3. CONTINUE handler: 处理后继续执行下一语句
    DECLARE CONTINUE HANDLER FOR SQLWARNING
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_msg = MESSAGE_TEXT;
        -- 警告记录，不影响主流程
    END;

    START TRANSACTION;

    SELECT balance INTO v_balance FROM accounts WHERE id = p_from FOR UPDATE;

    IF v_balance IS NULL THEN
        SIGNAL account_not_found SET MESSAGE_TEXT = '转出账户不存在';
    END IF;

    IF v_balance < p_amount THEN
        SIGNAL insufficient_funds
            SET MESSAGE_TEXT = '余额不足',
                MYSQL_ERRNO = 1644;  -- 自定义错误号 >= 1644
    END IF;

    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;

    COMMIT;
    SET p_status = 'SUCCESS';
END$$

DELIMITER ;
```

MySQL 异常处理的关键事实：

```
1. HANDLER 三种动作 (UNDO 不支持)
   - CONTINUE: 处理后从下一语句继续
   - EXIT:     处理后退出当前 BEGIN..END
   - UNDO:     未实现 (DB2 独有)

2. HANDLER 条件
   条件               含义
   ───────────────   ────────────────────────────
   SQLEXCEPTION      所有非警告非 NOT FOUND 错误
   SQLWARNING        SQLSTATE '01' 警告
   NOT FOUND         SQLSTATE '02' 无数据 (光标用)
   SQLSTATE 'xxxxx'  特定 SQLSTATE
   命名条件          DECLARE cond CONDITION FOR ...
   MySQL 错误号      1062, 1452 等

3. SIGNAL 抛出异常
   SIGNAL SQLSTATE 'xxxxx'
       SET MESSAGE_TEXT = '...',
           MYSQL_ERRNO = 1644,
           CLASS_ORIGIN = '...',
           SUBCLASS_ORIGIN = '...';
   - 自定义 SQLSTATE 必须以 '45' 开头 (用户保留)

4. RESIGNAL: 重抛/修改当前异常
   RESIGNAL;                     -- 原样重抛
   RESIGNAL SET MESSAGE_TEXT = ... ;  -- 修改后重抛
   RESIGNAL SQLSTATE '23000';    -- 改 SQLSTATE 重抛

5. HANDLER 作用域
   - HANDLER 仅在声明它的 BEGIN..END 内生效
   - 嵌套块: 内层 HANDLER 优先于外层
   - 多个匹配的 HANDLER: 选择最具体的
     SQLSTATE > 命名条件 > SQLEXCEPTION/SQLWARNING/NOT FOUND
```

MySQL HANDLER 作用域示例（重要）：

```sql
DELIMITER $$

CREATE PROCEDURE handler_scope_demo()
BEGIN
    -- 外层 handler
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        SELECT 'Outer handler caught' AS msg;

    BEGIN  -- 内层块
        -- 内层 handler (覆盖外层)
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            SELECT 'Inner handler caught' AS msg;

        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Test';
        -- 被内层 CONTINUE handler 捕获
        -- 输出: 'Inner handler caught'

        SELECT 'Continued after inner' AS msg;
        -- 此行执行: CONTINUE 模式后继续
    END;

    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Test 2';
    -- 内层块已结束，内层 handler 失效
    -- 被外层 EXIT handler 捕获
    -- 输出: 'Outer handler caught'

    SELECT 'Never reached' AS msg;
    -- 此行不执行 (EXIT handler 退出整个 BEGIN..END)
END$$

DELIMITER ;
```

### DB2（最完整的 SQL/PSM 实现）

DB2 是 SQL/PSM 标准的主导推动者，支持 `UNDO HANDLER` 和 `BEGIN ATOMIC`：

```sql
CREATE PROCEDURE transfer_funds(
    IN p_from INT, IN p_to INT, IN p_amount DECIMAL(10,2)
)
LANGUAGE SQL
BEGIN
    DECLARE SQLSTATE CHAR(5);
    DECLARE SQLCODE INT DEFAULT 0;
    DECLARE v_balance DECIMAL(10,2);

    -- 命名条件
    DECLARE insufficient_funds CONDITION FOR SQLSTATE '75001';

    -- UNDO handler (DB2 独有): 自动回滚 BEGIN ATOMIC 中的所有操作
    DECLARE UNDO HANDLER FOR insufficient_funds
    BEGIN
        -- 复合语句中的所有操作已自动回滚
        SIGNAL SQLSTATE '75002' SET MESSAGE_TEXT = '转账失败已回滚';
    END;

    -- EXIT handler
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            SQLSTATE = RETURNED_SQLSTATE,
            SQLCODE = DB2_RETURNED_SQLCODE;
        SIGNAL SQLSTATE '75003'
            SET MESSAGE_TEXT = 'Unknown error';
    END;

    BEGIN ATOMIC  -- 原子复合语句
        SELECT balance INTO v_balance FROM accounts WHERE id = p_from;

        IF v_balance < p_amount THEN
            SIGNAL insufficient_funds;
        END IF;

        UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
        UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;
    END;
END;
```

DB2 的 UNDO HANDLER 是 SQL/PSM 标准中最强大的特性：在 `BEGIN ATOMIC` 中，UNDO handler 触发时自动撤销所有已执行的语句，无需显式 ROLLBACK。这与子事务语义类似但更细粒度。

### SQLite（无过程化语言但支持 RAISE）

SQLite 没有完整的存储过程，但 `CREATE TRIGGER` 中可以使用特殊的 `RAISE()` 函数：

```sql
-- BEFORE INSERT 触发器使用 RAISE 控制错误
CREATE TRIGGER trg_validate_amount
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    SELECT CASE
        WHEN NEW.amount <= 0
            THEN RAISE(ABORT, '金额必须大于零')
        WHEN NEW.amount > 1000000
            THEN RAISE(ROLLBACK, '金额超出上限')
        WHEN NEW.customer_id IS NULL
            THEN RAISE(FAIL, '客户ID不能为空')
        WHEN NEW.status IS NULL
            THEN RAISE(IGNORE)  -- 静默放弃这一行
    END;
END;
```

SQLite RAISE 的四种动作：

```
动作       行为
────────  ───────────────────────────────────────────────────
ABORT     回滚当前语句的变更，但不影响事务中之前的语句
          后续语句（如同一事务的其他 INSERT）继续

ROLLBACK  回滚整个事务
          所有未提交的变更都丢失

FAIL      不回滚已发生的变更，但中止当前语句
          少用，行为反直觉

IGNORE    跳过当前行，但不报错
          适合行级容错（INSERT OR IGNORE 类似）
```

`RAISE(ABORT)` 是触发器中最常用的，行为类似其他引擎的"未捕获异常 → 取消触发 DML"。

### Snowflake Scripting（PL/pgSQL 风格）

```sql
EXECUTE IMMEDIATE $$
DECLARE
    insufficient_funds EXCEPTION (-20001, 'Insufficient funds');
    account_not_found  EXCEPTION (-20002, 'Account not found');
    v_balance DECIMAL;
BEGIN
    SELECT balance INTO :v_balance FROM accounts WHERE id = 101;

    IF (v_balance IS NULL) THEN
        RAISE account_not_found;
    END IF;

    IF (v_balance < 500) THEN
        RAISE insufficient_funds;
    END IF;

    UPDATE accounts SET balance = balance - 500 WHERE id = 101;

    RETURN 'success';

EXCEPTION
    WHEN insufficient_funds THEN
        RETURN 'Insufficient: ' || SQLERRM;
    WHEN account_not_found THEN
        RETURN 'Not found: ' || SQLERRM;
    WHEN OTHER THEN
        -- WHEN OTHER 是 Snowflake 特有，标准为 WHEN OTHERS
        RETURN 'Generic error: ' || SQLERRM || ' [' || SQLCODE || ']';
END;
$$;
```

### BigQuery 脚本（2023+ EXCEPTION 块）

```sql
BEGIN
    INSERT INTO orders VALUES (1, 100.00);
    RAISE USING MESSAGE = '业务错误';
EXCEPTION WHEN ERROR THEN
    SELECT @@error.message AS msg,
           @@error.stack_trace AS stack,
           @@error.statement_text AS stmt;
    -- BigQuery 仅支持 catch-all 异常处理
    -- 没有按异常类型分支的能力
END;
```

### CockroachDB / YugabyteDB（继承 PostgreSQL）

```sql
-- CockroachDB v20.1+ 完整支持 PL/pgSQL 异常处理
CREATE FUNCTION transfer_funds(...) RETURNS TEXT AS $$
BEGIN
    -- 与 PostgreSQL 完全相同
    -- 注意: CockroachDB 是分布式事务，子事务的回滚开销更高
    RAISE EXCEPTION 'distributed error' USING ERRCODE = 'P0001';
EXCEPTION
    WHEN OTHERS THEN
        RETURN 'caught';
END;
$$ LANGUAGE plpgsql;
```

CockroachDB 异常处理的特殊考虑：分布式事务中的子事务（PostgreSQL 风格的 EXCEPTION 块）有较高的网络往返开销，循环内频繁使用 EXCEPTION 块可能成为性能瓶颈。

## Oracle 嵌套 PL/SQL 异常传播深入

Oracle 是异常传播规则最复杂的引擎之一，因为它支持多种触发上下文（过程、函数、触发器、PRAGMA AUTONOMOUS_TRANSACTION）：

```sql
-- 包定义
CREATE OR REPLACE PACKAGE order_pkg AS
    -- 包级异常 (整个包共享)
    e_inventory_short EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_inventory_short, -20100);

    e_credit_check_failed EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_credit_check_failed, -20101);

    PROCEDURE create_order(p_customer_id INT, p_amount NUMBER);
END order_pkg;
/

CREATE OR REPLACE PACKAGE BODY order_pkg AS
    -- 私有过程
    PROCEDURE check_credit(p_customer_id INT, p_amount NUMBER) IS
        v_credit_limit NUMBER;
    BEGIN
        SELECT credit_limit INTO v_credit_limit
        FROM customers WHERE id = p_customer_id;

        IF v_credit_limit < p_amount THEN
            RAISE e_credit_check_failed;
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20102, '客户不存在: ' || p_customer_id);
    END check_credit;

    PROCEDURE check_inventory(p_amount NUMBER) IS
    BEGIN
        IF NOT inventory_available(p_amount) THEN
            RAISE e_inventory_short;
        END IF;
    END check_inventory;

    PROCEDURE create_order(p_customer_id INT, p_amount NUMBER) IS
    BEGIN
        check_credit(p_customer_id, p_amount);
        check_inventory(p_amount);

        INSERT INTO orders(customer_id, amount, status)
        VALUES (p_customer_id, p_amount, 'CREATED');
        COMMIT;

    EXCEPTION
        WHEN e_credit_check_failed THEN
            INSERT INTO order_failures(customer_id, reason, occurred_at)
            VALUES (p_customer_id, 'CREDIT_CHECK_FAILED', SYSDATE);
            COMMIT;
            RAISE;  -- 重抛给调用者
        WHEN e_inventory_short THEN
            INSERT INTO order_failures(customer_id, reason, occurred_at)
            VALUES (p_customer_id, 'INVENTORY_SHORT', SYSDATE);
            COMMIT;
            RAISE;
        WHEN OTHERS THEN
            ROLLBACK;
            DBMS_OUTPUT.PUT_LINE('未预期错误: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('回溯: ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
            RAISE;
    END create_order;
END order_pkg;
/
```

Oracle 异常传播的特殊行为：

```
1. EXCEPTION 块结束后的状态
   - 已执行的 DML 仍然在事务中（与 PG 不同）
   - 必须手动 ROLLBACK 才能撤销
   - 这意味着 EXCEPTION 块可以记录错误（INSERT INTO log）然后 RAISE

2. 自治事务中的异常
   PROCEDURE log_audit(p_msg VARCHAR2) IS
       PRAGMA AUTONOMOUS_TRANSACTION;
   BEGIN
       INSERT INTO audit_log VALUES (p_msg, SYSDATE);
       COMMIT;  -- 自治事务的提交
   EXCEPTION
       WHEN OTHERS THEN
           ROLLBACK;  -- 仅回滚自治事务
           RAISE;     -- 异常向上传播到主事务
   END;
   - 自治事务的 COMMIT 不影响主事务
   - 自治事务中的异常向主事务传播时，主事务状态不变

3. 触发器中的异常
   - BEFORE 触发器异常: 取消触发 DML，行不被插入/更新/删除
   - AFTER 触发器异常: 已经发生的 DML 被回滚 (语句级)
   - 行级触发器: 仅当前行的 DML 被影响（部分语句完成）
   - 注意: "mutating table" 错误 ORA-04091

4. 调用栈追踪 (10g+)
   DBMS_UTILITY.FORMAT_ERROR_STACK     - 错误消息栈
   DBMS_UTILITY.FORMAT_ERROR_BACKTRACE - 调用位置栈
   DBMS_UTILITY.FORMAT_CALL_STACK      - PL/SQL 调用栈
```

## 触发器异常 → DML 回滚

这是异常传播中最反直觉的行为：触发器中**未捕获**的异常会回滚**触发它的 DML 语句**。

### PostgreSQL 行为

```sql
-- 触发器拒绝特定行
CREATE FUNCTION validate_order() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.amount <= 0 THEN
        RAISE EXCEPTION '金额必须大于零'
            USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;  -- BEFORE: 必须返回 NEW 才会真正插入
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_order
BEFORE INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION validate_order();

-- 测试
BEGIN;
INSERT INTO orders(amount) VALUES (100);   -- 成功
INSERT INTO orders(amount) VALUES (-50);   -- 触发器抛异常
-- 整个事务进入失败状态，需要 ROLLBACK
-- 此时不能继续 INSERT，必须 ROLLBACK 后重新 BEGIN
ROLLBACK;
SELECT count(*) FROM orders WHERE amount = 100;  -- 0 行 (上面的 INSERT 也回滚)
```

PostgreSQL 在事务中遇到错误后进入 "in failed transaction" 状态，所有后续语句都会失败直到 ROLLBACK。要避免，可以使用 SAVEPOINT：

```sql
BEGIN;
INSERT INTO orders(amount) VALUES (100);  -- 成功
SAVEPOINT sp1;
INSERT INTO orders(amount) VALUES (-50);  -- 失败
ROLLBACK TO SAVEPOINT sp1;
INSERT INTO orders(amount) VALUES (200);  -- 成功
COMMIT;
SELECT count(*) FROM orders;  -- 2 行
```

### MySQL InnoDB 行为

```sql
DELIMITER $$
CREATE TRIGGER trg_validate_order
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF NEW.amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = '金额必须大于零';
    END IF;
END$$
DELIMITER ;

START TRANSACTION;
INSERT INTO orders(amount) VALUES (100);   -- 成功
INSERT INTO orders(amount) VALUES (-50);   -- 失败 (触发器异常)
-- 关键差异: MySQL 不进入 "failed transaction" 状态
-- 后续语句可以继续执行
INSERT INTO orders(amount) VALUES (200);   -- 成功
COMMIT;
SELECT count(*) FROM orders;  -- 2 行 (-50 那行被回滚，但其他 INSERT 都成功)
```

### Oracle 行为

```sql
CREATE OR REPLACE TRIGGER trg_validate_order
BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
    IF :NEW.amount <= 0 THEN
        RAISE_APPLICATION_ERROR(-20001, '金额必须大于零');
    END IF;
END;
/

-- 多行 INSERT: 整个语句要么全成功要么全失败
INSERT INTO orders(amount)
SELECT amount FROM staging_orders;
-- 如果任何一行触发异常，整个 INSERT 回滚
-- 但事务中之前的语句不受影响

-- 单条触发: 仅这条 INSERT 失败
INSERT INTO orders VALUES (100);
INSERT INTO orders VALUES (-50);  -- 失败
INSERT INTO orders VALUES (200);  -- 仍可执行
```

### SQL Server 行为

```sql
CREATE TRIGGER trg_validate_order
ON orders AFTER INSERT
AS
BEGIN
    IF EXISTS (SELECT 1 FROM inserted WHERE amount <= 0)
    BEGIN
        ;THROW 60001, '金额必须大于零', 1;
    END
END;
GO

-- 默认行为
INSERT INTO orders VALUES (100);    -- 成功
INSERT INTO orders VALUES (-50);    -- 失败
INSERT INTO orders VALUES (200);    -- 取决于是否在事务中

-- 在事务中: SQL Server 2005+ 自动回滚整个事务
BEGIN TRANSACTION;
INSERT INTO orders VALUES (100);    -- 成功
INSERT INTO orders VALUES (-50);    -- 失败 → 事务进入 uncommittable 状态
SELECT XACT_STATE();                -- -1
INSERT INTO orders VALUES (200);    -- 此语句失败 (事务被中毒)
ROLLBACK;
```

## MySQL HANDLER 作用域规则

MySQL HANDLER 的作用域规则非常细致，理解它对避免 bug 至关重要：

```sql
DELIMITER $$

CREATE PROCEDURE handler_specificity_demo()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        SELECT 'Generic SQLEXCEPTION' AS caught;

    DECLARE EXIT HANDLER FOR SQLSTATE '23000'
        SELECT 'Specific SQLSTATE 23000' AS caught;

    DECLARE EXIT HANDLER FOR 1062
        SELECT 'MySQL error 1062' AS caught;

    -- 触发重复键错误
    INSERT INTO users (id, name) VALUES (1, 'Alice');
    INSERT INTO users (id, name) VALUES (1, 'Bob');  -- 错误 1062 / SQLSTATE 23000

    -- 优先级 (从高到低):
    -- 1. MySQL 错误号 1062 → 这个被选中
    -- 2. SQLSTATE '23000'
    -- 3. SQLEXCEPTION
    --
    -- 输出: 'MySQL error 1062'
END$$

DELIMITER ;
```

HANDLER 选择规则的完整优先级：

```
最高优先级
    ↓
1. MySQL 特定错误号 (DECLARE HANDLER FOR 1062)
2. SQLSTATE 完整匹配 (DECLARE HANDLER FOR SQLSTATE '23000')
3. SQLSTATE 类别匹配 (DECLARE HANDLER FOR SQLSTATE '23xxx' - 不支持)
4. 命名条件 (DECLARE HANDLER FOR my_condition)
5. 通用条件 (SQLEXCEPTION / SQLWARNING / NOT FOUND)
    ↓
最低优先级

注意: HANDLER 只在声明它的 BEGIN..END 块内生效
内层 HANDLER 优先于外层 HANDLER
```

HANDLER 作用域的常见陷阱：

```sql
DELIMITER $$

CREATE PROCEDURE scope_pitfall()
BEGIN
    -- 陷阱 1: 在 IF 块内声明 HANDLER 不行
    -- 标准: HANDLER 必须紧接在 DECLARE 变量后

    -- 陷阱 2: HANDLER 不捕获 HANDLER 自身的错误
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- 此处的错误不会被自身捕获
        SELECT 1/0;  -- 错误! 但不会再触发 HANDLER
        -- 异常向上传播到调用者
    END;

    -- 陷阱 3: CONTINUE handler 后变量状态
    DECLARE v_count INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        SET v_count = v_count + 1;

    -- 即使 INSERT 失败，v_count 加 1
    -- 但 INSERT 的"行号"等局部状态不可恢复
END$$
```

## 触发器中的异常深入

### BEFORE vs AFTER 触发器异常的语义差别

```
BEFORE 触发器异常:
  - DML 还没执行
  - 异常 → 取消整个 DML
  - 适合验证、规范化

AFTER 触发器异常:
  - DML 已经执行 (但未提交)
  - 异常 → 回滚 DML
  - 适合审计、级联

行级触发器异常:
  - 仅取消当前行的 DML
  - 但语句级原子性: 整条 INSERT/UPDATE 失败

语句级触发器异常:
  - 取消整条语句
  - 已修改的行回滚
```

### Oracle 触发器中的 RAISE_APPLICATION_ERROR

```sql
-- 业务时间限制
CREATE OR REPLACE TRIGGER trg_business_hours
BEFORE INSERT OR UPDATE ON orders
FOR EACH ROW
DECLARE
    v_hour NUMBER;
BEGIN
    v_hour := EXTRACT(HOUR FROM SYSTIMESTAMP);
    IF v_hour < 9 OR v_hour >= 18 THEN
        RAISE_APPLICATION_ERROR(
            -20001,
            '订单仅在工作时间(9-18)处理: 当前 ' || v_hour
        );
    END IF;

    IF :NEW.amount > 1000000 THEN
        RAISE_APPLICATION_ERROR(
            -20002,
            '大额订单需主管审批: ' || :NEW.amount
        );
    END IF;
END;
/

-- 审计触发器中的异常处理
CREATE OR REPLACE TRIGGER trg_audit_orders
AFTER INSERT OR UPDATE OR DELETE ON orders
FOR EACH ROW
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    BEGIN
        INSERT INTO audit_log(table_name, action, old_id, new_id, ts)
        VALUES (
            'orders',
            CASE WHEN INSERTING THEN 'INSERT'
                 WHEN UPDATING THEN 'UPDATE'
                 WHEN DELETING THEN 'DELETE'
            END,
            CASE WHEN UPDATING OR DELETING THEN :OLD.id END,
            CASE WHEN INSERTING OR UPDATING THEN :NEW.id END,
            SYSTIMESTAMP
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            -- 审计失败不应阻止主操作
            -- 但 PRAGMA AUTONOMOUS_TRANSACTION 必须 COMMIT 或 ROLLBACK
            ROLLBACK;
            -- 不重抛 → 主 DML 继续
    END;
END;
/
```

## 关键发现

1. **完全没有 SQL 标准定义"异常传播"** —— SQL/PSM 仅规范了 `DECLARE HANDLER` 语句和 `SIGNAL` / `RESIGNAL`，未规定异常如何在嵌套调用栈中传播。每个引擎自行设计。

2. **三大异常处理流派分裂主流引擎** —— SQL Server 的 `TRY/CATCH` (.NET 风格) vs PostgreSQL/Oracle 的 `BEGIN..EXCEPTION..END` (Ada/PL/SQL 风格) vs MySQL/DB2 的 `DECLARE HANDLER` (SQL/PSM 标准)。三种语法表达力相近但风格迥异。

3. **PostgreSQL 子事务 vs Oracle 非子事务的本质差异** —— PG 的 `BEGIN..EXCEPTION` 块隐式创建 SAVEPOINT，捕获异常后已执行的 DML 自动回滚；Oracle 的 EXCEPTION 块**不创建子事务**，捕获异常后必须手动 ROLLBACK。这在迁移时是常见 bug 源。

4. **触发器异常默认回滚触发它的 DML** —— 几乎所有支持触发器的引擎都遵循这一语义：未捕获的异常会取消整条触发它的 INSERT/UPDATE/DELETE。这是触发器作为"约束机制"的核心保障。

5. **MySQL 与 PostgreSQL 在事务中错误后的行为截然不同** —— PG 进入 "in failed transaction" 状态，所有后续语句失败直到 ROLLBACK；MySQL/InnoDB 仅回滚失败的语句，事务可继续。这导致同样的应用代码在两个引擎中表现不同。

6. **SQL Server 的 XACT_STATE() = -1 是独特的"中毒事务"概念** —— 某些错误（特别是触发器中的 `THROW`）会让事务进入"不可提交"状态，必须显式 ROLLBACK。这是其他引擎没有的概念。

7. **Oracle 的 PRAGMA EXCEPTION_INIT 是绑定错误码到命名异常的强大机制** —— 允许将系统错误（如 ORA-01403 NO_DATA_FOUND）和应用自定义错误（-20000 ~ -20999）以可读名称使用。其他引擎的等价物（PG 的 SQLSTATE 'P0001'、MySQL 的 DECLARE CONDITION）都不如此优雅。

8. **DB2 的 UNDO HANDLER + BEGIN ATOMIC 是 SQL/PSM 标准最完整的实现** —— UNDO handler 在异常时自动回滚 BEGIN ATOMIC 中的所有操作，无需显式 ROLLBACK。MySQL 和大多数 SQL/PSM 实现都不支持这一特性。

9. **MySQL HANDLER 作用域比想象中复杂** —— HANDLER 仅在声明它的 BEGIN..END 内生效，内层覆盖外层；选择优先级为 MySQL 错误号 > 完整 SQLSTATE > 命名条件 > 通用条件。这些规则在嵌套循环和复合语句中容易踩坑。

10. **UDF 错误总是中止整个语句** —— 即使一行数据导致 UDF 抛错，整个查询都会失败。要实现"行级容错"必须在 UDF 内部 catch 异常返回 NULL，或使用引擎特定的 `TRY_*` / `SAFE_*` / `OrNull` 包装器。

11. **SQLite 的 RAISE() 函数提供了独特的细粒度控制** —— `ABORT`（取消语句）、`ROLLBACK`（回滚事务）、`FAIL`（中止语句但保留已发生变更）、`IGNORE`（静默放弃）四种模式覆盖了不同的容错需求，比其他引擎更灵活。

12. **CockroachDB / YugabyteDB 等分布式 PG 兼容引擎在子事务上有性能成本** —— 每个 EXCEPTION 块的 SAVEPOINT 在分布式事务中需要额外的网络往返，循环内频繁使用可能成为性能瓶颈。建议改写为基于条件检查的非异常控制流。

13. **触发器中的异常通常不会回滚整个事务，只回滚触发的语句** —— 这与许多开发者的直觉相反。在 Oracle/PG/MySQL InnoDB 中，触发器异常默认只取消那条 DML，需要显式 `RAISE`/`SIGNAL` 在外层捕获并 ROLLBACK 才能回滚整个事务。SQL Server 因 `XACT_STATE = -1` 行为表现为整个事务回滚，是少数派。

14. **几乎所有 OLAP / 分析型引擎都不支持完整的异常处理** —— ClickHouse、Trino、Spark SQL、StarRocks、Doris、Impala 等无存储过程或仅有简化的脚本能力。它们使用 `fail()` / `throwIf()` / `raise_error()` 等函数仅做查询级断言，不支持嵌套异常块。

15. **BigQuery 的 EXCEPTION WHEN ERROR 是简化的 catch-all 模型** —— 不支持按异常类型分支，所有错误都进同一个 `WHEN ERROR THEN` 块。与传统 OLTP 数据库的精细异常类型形成对比，反映了 OLAP 引擎对过程化能力的简化倾向。

16. **AUTONOMOUS_TRANSACTION 中的异常传播规则独特** —— Oracle 的 `PRAGMA AUTONOMOUS_TRANSACTION` 让子事务的 COMMIT/ROLLBACK 与主事务隔离，但**异常仍然向上传播**。这意味着自治事务可以做"日志即使主事务失败也保留"，同时让主事务感知错误。

17. **嵌套调用中"重抛"是核心模式** —— Oracle/PG 的 `RAISE` (无参)、SQL Server 的 `;THROW`、MySQL 的 `RESIGNAL`、DB2 的 `RESIGNAL` 都用于在中间层记录错误后继续向上传播。不重抛会导致异常被吞噬，调用者看不到失败，是常见 bug。

18. **未捕获异常的最终行为：客户端报错 + 事务回滚** —— 在所有引擎中，最外层调用者未捕获的异常会导致客户端连接收到错误，并触发事务回滚。但事务回滚的范围在不同引擎中差异巨大（仅当前语句 vs 整个事务），需结合上下文判断。

## 对引擎开发者的实现建议

### 1. 异常表示：SQLSTATE vs 错误对象

```
设计选择 1: 5 字符 SQLSTATE (PG, MySQL, DB2, SQL/PSM)
  优点: 标准化、语言无关、便于跨引擎兼容
  缺点: 信息密度低，难以区分类似错误

设计选择 2: 错误号 (SQL Server, Oracle ORA-xxx)
  优点: 易于记忆、错误码体系完整
  缺点: 不跨引擎，需要错误码到 SQLSTATE 的映射

设计选择 3: 异常对象 (Snowflake EXCEPTION 声明)
  优点: 类型安全，便于按类型分支
  缺点: 复杂度高，序列化难

推荐: 同时支持 SQLSTATE 和应用错误码（如 PG 的 RAISE EXCEPTION USING ERRCODE = 'P0001'）
```

### 2. 子事务 vs 非子事务模型

```
PG 风格 (子事务):
  优点: 异常后自动回滚到块开始
  缺点: 每个 EXCEPTION 块有 SAVEPOINT 开销 (5-10us)
  适用: OLTP 场景，异常路径不频繁

Oracle 风格 (非子事务):
  优点: 无额外开销，性能高
  缺点: 必须手动 ROLLBACK，容易忘记
  适用: 大量 DML 的过程，性能敏感

折中方案: 显式 SAVEPOINT
  允许用户控制是否使用子事务
  RAISE 时不强制回滚，由用户决定
```

### 3. 调用栈追踪

```
最小: 错误位置 + 错误消息 (大多数引擎)
中等: 错误位置 + 调用过程名 (SQL Server ERROR_PROCEDURE)
完整: 完整调用栈 (Oracle FORMAT_ERROR_BACKTRACE, PG PG_EXCEPTION_CONTEXT)

实现: 在每次过程调用进入/退出时维护调用栈，异常时序列化为字符串
```

### 4. HANDLER 优先级匹配

```
当多个 HANDLER 都能捕获某异常时，按以下优先级选择:

1. 最具体的引擎特定错误号 (1062 vs 23000)
2. 完整 SQLSTATE 匹配 ('23000')
3. SQLSTATE 类别 ('23xxx' - 仅部分引擎)
4. 命名条件 (DECLARE cond CONDITION FOR ...)
5. 通用条件 (SQLEXCEPTION / SQLWARNING / NOT FOUND)

实现: HANDLER 链按特异性排序，遍历找到第一个匹配
```

### 5. 触发器异常的事务影响

```
推荐设计:
  - 行级触发器异常: 取消当前行的 DML
  - 语句级触发器异常: 取消整条 DML
  - 事务范围: 默认仅当前语句回滚 (Oracle/PG/MySQL 风格)
  - 提供选项: SET XACT_ABORT ON 让任何错误都回滚事务 (SQL Server 风格)

实现要点:
  - 触发器执行前创建隐式 SAVEPOINT
  - 触发器异常后自动回滚到该 SAVEPOINT
  - 异常向上传播到调用者，由其决定是否捕获
```

### 6. UDF 异常的语句级传播

```
默认: UDF 异常终止整条 SQL 语句
  优点: 简单，错误明确
  缺点: 一行错误废掉整个查询

可选: 提供 TRY_* / SAFE_* 包装器
  - TRY_CAST: 类型转换失败返回 NULL
  - TRY(expr): 通用包装，捕获 expr 中的任何错误返回 NULL
  - 实现: 在执行框架引入"安全模式"标志，UDF 检查后选择路径

更高级: SAFE. 前缀 (BigQuery)
  - 在函数名前加 SAFE.，自动包装
  - 减少冗余的 TRY_ 函数定义
```

### 7. SIGNAL/RESIGNAL 实现

```
SIGNAL: 抛出异常
  - 验证 SQLSTATE 格式 (5 字符)
  - 用户保留前缀: '45' (MySQL/DB2), 'P0' (PG)
  - 设置 MESSAGE_TEXT, MYSQL_ERRNO 等条件信息项

RESIGNAL: 重抛当前异常
  - 仅在 HANDLER 内有效
  - 可修改 SQLSTATE 或保留原值
  - 修改时验证用户保留前缀

实现要点:
  - 维护当前异常上下文 (SQLSTATE, message, 错误号等)
  - HANDLER 进入时保存，退出时恢复
  - RESIGNAL 时使用保存的上下文
```

## 参考资料

- ISO/IEC 9075-4 SQL/PSM (Persistent Stored Modules) 标准
- PostgreSQL: [Error Handling in PL/pgSQL](https://www.postgresql.org/docs/current/plpgsql-control-structures.html#PLPGSQL-ERROR-TRAPPING)
- Oracle: [PL/SQL Error Handling](https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/plsql-error-handling.html)
- SQL Server: [TRY...CATCH](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/try-catch-transact-sql)
- MySQL: [DECLARE HANDLER](https://dev.mysql.com/doc/refman/8.0/en/declare-handler.html)
- DB2: [Condition Handlers](https://www.ibm.com/docs/en/db2/11.5?topic=procedures-condition-handlers)
- SQLite: [RAISE function in CREATE TRIGGER](https://www.sqlite.org/lang_createtrigger.html)
- Snowflake: [Snowflake Scripting - Exception Handling](https://docs.snowflake.com/en/developer-guide/snowflake-scripting/exceptions)
- BigQuery: [BEGIN...EXCEPTION...END](https://cloud.google.com/bigquery/docs/reference/standard-sql/procedural-language)
- Firebird: [PSQL Statements - EXCEPTION](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref50/firebird-50-language-reference.html)
- 相关文章: [error-handling.md](./error-handling.md), [error-handling-safe.md](./error-handling-safe.md), [triggers.md](./triggers.md), [autonomous-transactions.md](./autonomous-transactions.md)
