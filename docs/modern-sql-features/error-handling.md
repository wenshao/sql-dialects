# SQL 错误处理机制：各方言全对比

> 参考资料:
> - [SQL:2023 Standard - Diagnostics Management](https://www.iso.org/standard/76583.html)
> - [PostgreSQL - Error Handling in PL/pgSQL](https://www.postgresql.org/docs/current/plpgsql-control-structures.html#PLPGSQL-ERROR-TRAPPING)
> - [SQL Server - TRY...CATCH](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/try-catch-transact-sql)
> - [MySQL - DECLARE HANDLER](https://dev.mysql.com/doc/refman/8.0/en/declare-handler.html)
> - [Oracle PL/SQL - Exception Handling](https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/plsql-error-handling.html)

错误处理是存储过程和事务控制的核心基础设施。SQL 标准定义了 SQLSTATE、SQLCODE 和 GET DIAGNOSTICS，但各引擎在此基础上发展出了截然不同的错误捕获、抛出和传播机制。本文从引擎开发者视角，逐方言对比这些差异。

## 错误捕获机制支持矩阵

```
引擎               TRY/CATCH  BEGIN..EXCEPTION  DECLARE HANDLER  WHENEVER  条件表达式  版本
─────────────────  ─────────  ────────────────  ───────────────  ────────  ──────────  ────────
SQL Server         ✓          ✗                 ✗                ✗         ✓           2005+
Azure SQL          ✓          ✗                 ✗                ✗         ✓           GA
PostgreSQL         ✗          ✓                 ✗                ✗         ✓           8.0+
Oracle PL/SQL      ✗          ✓                 ✗                ✗         ✓           7.0+
MySQL              ✗          ✗                 ✓                ✗         ✗           5.0+ (SIGNAL/RESIGNAL 5.5+)
MariaDB            ✗          ✗                 ✓                ✗         ✗           5.0+ (SIGNAL/RESIGNAL 5.5+)
Db2 (LUW)         ✗          ✗                 ✓                ✓(嵌入)   ✓           V7+
Db2 (z/OS)        ✗          ✗                 ✓                ✓(嵌入)   ✓           V7+
Db2 (iSeries)     ✗          ✗                 ✓                ✓(嵌入)   ✓           V5+
Snowflake          ✗          ✓                 ✗                ✗         ✗           Scripting GA
BigQuery           ✗          ✓(1)              ✗                ✗         ✗           2023+
Databricks         ✗          ✗                 ✓(2)             ✗         ✓           Runtime 14+
Redshift           ✗          ✓                 ✗                ✗         ✗           GA
CockroachDB        ✗          ✓                 ✗                ✗         ✓           v20.1+
YugabyteDB         ✗          ✓                 ✗                ✗         ✓           2.6+
TiDB               ✗          ✗                 ✓(3)             ✗         ✗           6.1+
OceanBase (MySQL)  ✗          ✗                 ✓                ✗         ✗           V3.x+
OceanBase (Oracle) ✗          ✓                 ✗                ✗         ✓           V3.x+
Teradata           ✗          ✗                 ✓                ✓(嵌入)   ✗           V14+
SAP HANA           ✗          ✗                 ✓                ✗         ✓           SPS09+
Informix           ✗          ✓                 ✗                ✓(嵌入)   ✗           11.50+
Firebird           ✗          ✓                 ✗                ✗         ✓           2.0+
SQLite             ✗          ✗                 ✗                ✗         ✗(4)        -
DuckDB             ✗          ✗                 ✗                ✗         ✗(4)        -
ClickHouse         ✗          ✗                 ✗                ✗         ✗(4)        -
Trino              ✗          ✗                 ✗                ✗         ✗(4)        -
Presto             ✗          ✗                 ✗                ✗         ✗(4)        -
Spark SQL          ✗          ✗                 ✗                ✗         ✗(4)        -
Hive               ✗          ✗                 ✗                ✗         ✗(4)        -
StarRocks          ✗          ✗                 ✗                ✗         ✗(4)        -
Doris              ✗          ✗                 ✗                ✗         ✗(4)        -
Greenplum          ✗          ✓                 ✗                ✗         ✓           5.0+
Vertica            ✗          ✗                 ✗                ✗         ✗(5)        -
SingleStore        ✗          ✗                 ✓                ✗         ✗           7.0+
Couchbase (N1QL)   ✗          ✗                 ✗                ✗         ✗(4)        -
MongoDB (SQL)      ✗          ✗                 ✗                ✗         ✗(4)        -
Exasol             ✗          ✓                 ✗                ✗         ✓           6.0+
NuoDB              ✗          ✗                 ✓                ✗         ✗           2.0+
VoltDB             ✗          ✗                 ✗                ✗         ✗(6)        -
TimescaleDB        ✗          ✓                 ✗                ✗         ✓           继承PG
QuestDB            ✗          ✗                 ✗                ✗         ✗(4)        -
InfluxDB (SQL)     ✗          ✗                 ✗                ✗         ✗(4)        -
AlloyDB            ✗          ✓                 ✗                ✗         ✓           继承PG
Neon               ✗          ✓                 ✗                ✗         ✓           继承PG
PolarDB (MySQL)    ✗          ✗                 ✓                ✗         ✗           继承MySQL
PolarDB (PG)       ✗          ✓                 ✗                ✗         ✓           继承PG
Aurora (MySQL)     ✗          ✗                 ✓                ✗         ✗           继承MySQL
Aurora (PG)        ✗          ✓                 ✗                ✗         ✓           继承PG
MSSQL on Linux     ✓          ✗                 ✗                ✗         ✓           2017+

注:
(1) BigQuery 使用 BEGIN...EXCEPTION WHEN ERROR THEN...END，语法属于 BEGIN..EXCEPTION 模型（类似 PG），不是 TRY/CATCH。EXCEPTION WHEN ERROR THEN 实际上是 catch-all 模式
(2) Databricks SQL 通过 PL 扩展支持 DECLARE HANDLER 风格的异常处理
(3) TiDB 兼容 MySQL DECLARE HANDLER 语法，但存储过程功能仍在逐步完善中
(4) 分析型/嵌入式引擎，无存储过程，错误直接返回客户端
(5) Vertica 有存储过程但错误处理能力有限
(6) VoltDB 使用 Java 存储过程，错误处理在 Java 层面

关于 WHENEVER 列: 本矩阵的 WHENEVER 列仅反映存储过程/过程化 SQL 中的错误处理能力。Oracle (Pro*C) 和 PostgreSQL (ECPG) 均支持 WHENEVER SQLERROR，但这属于嵌入式 SQL (Embedded SQL) 预编译指令，不属于存储过程错误处理范畴，因此在本矩阵中标记为 ✗。详见下方"WHENEVER SQLERROR (嵌入式 SQL)"章节。
```

## 错误抛出机制对比

```
引擎               抛出语法                                   版本
─────────────────  ──────────────────────────────────────────  ────────
SQL Server         THROW / RAISERROR                          2012+ / 2000+
Azure SQL          THROW / RAISERROR                          GA
PostgreSQL         RAISE (EXCEPTION/WARNING/NOTICE/DEBUG)     8.0+
Oracle PL/SQL      RAISE / RAISE_APPLICATION_ERROR            7.0+
MySQL              SIGNAL SQLSTATE / RESIGNAL                 5.5+
MariaDB            SIGNAL SQLSTATE / RESIGNAL                 5.5+
Db2                SIGNAL SQLSTATE / RESIGNAL                 V7+
Snowflake          RAISE (Snowflake Scripting)                GA
BigQuery           RAISE USING MESSAGE                        2023+
Databricks         RAISE_ERROR() 函数 / SIGNAL                Runtime 11+
Redshift           RAISE (PL/pgSQL 兼容)                      GA
CockroachDB        RAISE (PL/pgSQL 兼容)                      v20.1+
YugabyteDB         RAISE (PL/pgSQL 兼容)                      2.6+
TiDB               SIGNAL SQLSTATE (MySQL 兼容)               6.1+
OceanBase (MySQL)  SIGNAL SQLSTATE                            V3.x+
OceanBase (Oracle) RAISE / RAISE_APPLICATION_ERROR            V3.x+
Teradata           SIGNAL SQLSTATE (ANSI 模式)                V14+
SAP HANA           SIGNAL / RESIGNAL / EXEC 'THROW'          SPS09+
Informix           RAISE EXCEPTION                            11.50+
Firebird           EXCEPTION (自定义异常名)                    2.0+
Greenplum          RAISE (继承 PG)                             5.0+
SingleStore        SIGNAL SQLSTATE (MySQL 兼容)               7.0+
Exasol             RAISE                                      6.0+
TimescaleDB        RAISE (继承 PG)                             继承PG
AlloyDB            RAISE (继承 PG)                             继承PG
```

## 三大捕获模型详解

### 模型一: TRY...CATCH (SQL Server 家族)

SQL Server 2005 引入的结构化错误处理，设计灵感来自 C#/Java 的 try-catch：

```sql
-- SQL Server / Azure SQL
BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO orders (customer_id, amount) VALUES (101, 500.00);
    UPDATE accounts SET balance = balance - 500.00 WHERE id = 101;

    -- 如果 balance 不足触发 CHECK 约束，跳到 CATCH
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    -- 获取错误信息
    DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrorState INT = ERROR_STATE();
    DECLARE @ErrorNumber INT = ERROR_NUMBER();
    DECLARE @ErrorLine INT = ERROR_LINE();
    DECLARE @ErrorProc NVARCHAR(200) = ERROR_PROCEDURE();

    -- 记录到日志表
    INSERT INTO error_log (error_number, error_message, error_severity,
                           error_state, error_procedure, error_line, created_at)
    VALUES (@ErrorNumber, @ErrorMessage, @ErrorSeverity,
            @ErrorState, @ErrorProc, @ErrorLine, GETDATE());

    -- 重新抛出（SQL Server 2012+）
    THROW;  -- 保留原始错误信息
END CATCH;
```

SQL Server TRY...CATCH 的关键行为：

```
行为                          说明
───────────────────────────  ──────────────────────────────────────────
捕获范围                      严重级别 11-19 的错误被捕获
不可捕获的错误                 严重级别 20+ (连接中断), 编译错误, 语法错误
事务状态                      错误后事务变为"不可提交" (XACT_STATE() = -1)
                              必须 ROLLBACK 才能继续
批处理终止错误                 某些错误 (如死锁 1205) 终止整个批处理
                              TRY 块中的死锁会被 CATCH 捕获
嵌套 TRY...CATCH             支持，内层未捕获的错误传播到外层
@@ERROR                       在 CATCH 块中被重置为 0
                              必须用 ERROR_NUMBER() 等函数获取错误信息
THROW vs RAISERROR            THROW 保留原始错误号; RAISERROR 必须使用 50000+
```

### 模型二: BEGIN...EXCEPTION...END (PostgreSQL / Oracle 家族)

```sql
-- PostgreSQL PL/pgSQL
DO $$
DECLARE
    v_customer_name TEXT;
    v_sqlstate TEXT;
    v_message TEXT;
    v_detail TEXT;
    v_hint TEXT;
    v_context TEXT;
BEGIN
    BEGIN  -- 内层 BEGIN 创建子事务 (savepoint)
        INSERT INTO orders (customer_id, amount) VALUES (101, 500.00);
        UPDATE accounts SET balance = balance - 500.00 WHERE id = 101;
    EXCEPTION
        WHEN check_violation THEN
            -- 获取完整诊断信息
            GET STACKED DIAGNOSTICS
                v_sqlstate = RETURNED_SQLSTATE,
                v_message  = MESSAGE_TEXT,
                v_detail   = PG_EXCEPTION_DETAIL,
                v_hint     = PG_EXCEPTION_HINT,
                v_context  = PG_EXCEPTION_CONTEXT;

            RAISE WARNING '余额不足: % (SQLSTATE: %)', v_message, v_sqlstate;

        WHEN unique_violation THEN
            RAISE NOTICE '订单已存在，跳过';

        WHEN OTHERS THEN
            -- 捕获所有其他错误
            GET STACKED DIAGNOSTICS
                v_sqlstate = RETURNED_SQLSTATE,
                v_message  = MESSAGE_TEXT;
            RAISE EXCEPTION '未预期的错误: % [%]', v_message, v_sqlstate;
    END;

    -- 即使内层 EXCEPTION 触发，外层继续执行
    RAISE NOTICE '处理完成';
END $$;
```

```sql
-- Oracle PL/SQL
DECLARE
    v_balance NUMBER;
    e_insufficient_funds EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_insufficient_funds, -20001);
BEGIN
    SELECT balance INTO v_balance FROM accounts WHERE id = 101;

    IF v_balance < 500 THEN
        RAISE_APPLICATION_ERROR(-20001, '余额不足: 当前余额 ' || v_balance);
    END IF;

    UPDATE accounts SET balance = balance - 500 WHERE id = 101;
    INSERT INTO orders (customer_id, amount) VALUES (101, 500);

    COMMIT;
EXCEPTION
    WHEN e_insufficient_funds THEN
        DBMS_OUTPUT.PUT_LINE('业务错误: ' || SQLERRM);
        ROLLBACK;
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('客户不存在');
        ROLLBACK;
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('重复订单');
        ROLLBACK;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('错误代码: ' || SQLCODE);
        DBMS_OUTPUT.PUT_LINE('错误信息: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('调用栈: ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
        ROLLBACK;
        RAISE;  -- 重新抛出
END;
/
```

PostgreSQL 与 Oracle EXCEPTION 块的关键差异：

```
行为                PostgreSQL                          Oracle PL/SQL
─────────────────  ──────────────────────────────────  ──────────────────────────────
子事务              EXCEPTION 块隐式创建 savepoint       不创建子事务
                    捕获错误后自动回滚到 savepoint        需手动 ROLLBACK
性能影响            每个 EXCEPTION 块有 savepoint 开销    无额外开销
错误码格式          SQLSTATE (5 字符, 如 '23505')        SQLCODE (负整数, 如 -1)
预定义异常名        条件名 (unique_violation 等)          命名异常 (DUP_VAL_ON_INDEX 等)
自定义异常          通过 RAISE EXCEPTION + SQLSTATE       PRAGMA EXCEPTION_INIT 绑定错误码
调用栈              PG_EXCEPTION_CONTEXT                 DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
OTHERS 内获取错误   GET STACKED DIAGNOSTICS               SQLCODE / SQLERRM
事务控制            不能在 EXCEPTION 块内 COMMIT/ROLLBACK 可以在 EXCEPTION 块内 COMMIT/ROLLBACK
                    (函数内不允许事务控制)                 (过程内允许自治事务)
```

### 模型三: DECLARE HANDLER (MySQL / MariaDB / Db2)

```sql
-- MySQL / MariaDB
DELIMITER //
CREATE PROCEDURE transfer_funds(
    IN p_from INT, IN p_to INT, IN p_amount DECIMAL(10,2),
    OUT p_status VARCHAR(50)
)
BEGIN
    -- 声明变量
    DECLARE v_error_occurred BOOLEAN DEFAULT FALSE;
    DECLARE v_error_code INT;
    DECLARE v_error_msg TEXT;
    DECLARE v_sqlstate CHAR(5);

    -- 声明 CONTINUE handler: 遇到错误后继续执行
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        SET v_error_occurred = TRUE;
        GET DIAGNOSTICS CONDITION 1
            v_error_code = MYSQL_ERRNO,
            v_error_msg = MESSAGE_TEXT,
            v_sqlstate = RETURNED_SQLSTATE;
    END;

    -- 声明特定 SQLSTATE 的 handler
    -- DECLARE CONTINUE HANDLER FOR SQLSTATE '23000'
    --     SET p_status = 'DUPLICATE_KEY';

    -- 声明 NOT FOUND handler (用于游标)
    -- DECLARE CONTINUE HANDLER FOR NOT FOUND
    --     SET v_done = TRUE;

    START TRANSACTION;

    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;

    IF v_error_occurred THEN
        ROLLBACK;
        SET p_status = CONCAT('ERROR: [', v_sqlstate, '] ', v_error_msg);
    ELSE
        COMMIT;
        SET p_status = 'SUCCESS';
    END IF;
END //
DELIMITER ;
```

```sql
-- Db2 LUW
CREATE PROCEDURE transfer_funds(
    IN p_from INT, IN p_to INT, IN p_amount DECIMAL(10,2))
LANGUAGE SQL
BEGIN
    -- Db2 支持更细粒度的 handler 类型
    DECLARE SQLSTATE CHAR(5);
    DECLARE SQLCODE INT DEFAULT 0;

    -- EXIT handler: 执行 handler 体后退出复合语句
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SIGNAL SQLSTATE '75001'
            SET MESSAGE_TEXT = '转账失败，已回滚';
    END;

    -- UNDO handler (Db2 独有): 自动回滚复合语句中的所有操作
    -- DECLARE UNDO HANDLER FOR SQLSTATE '23505'
    -- BEGIN
    --     -- 复合语句中已执行的操作自动回滚
    --     SIGNAL SQLSTATE '75002' SET MESSAGE_TEXT = '重复键冲突';
    -- END;

    UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;
    COMMIT;
END;
```

DECLARE HANDLER 的三种类型对比：

```
Handler 类型   行为                                        支持引擎
───────────  ──────────────────────────────────────────  ──────────────
CONTINUE     执行 handler 体，然后继续执行后续语句            MySQL, MariaDB, Db2, TiDB, SingleStore
EXIT         执行 handler 体，然后退出当前 BEGIN...END 块    MySQL, MariaDB, Db2, TiDB, SingleStore
UNDO         自动回滚当前复合语句，然后执行 handler 体        仅 Db2
```

Handler 条件类型：

```
条件                     含义                                  示例
──────────────────────  ────────────────────────────────────  ─────────────────────────
SQLEXCEPTION            所有 SQLSTATE 以 '02' 和 '01' 以外    运行时错误、约束违反等
SQLWARNING              SQLSTATE 以 '01' 开头                 截断警告、权限提示等
NOT FOUND               SQLSTATE '02000'                      SELECT INTO 或 FETCH 无数据
SQLSTATE 'xxxxx'        特定 SQLSTATE 值                       SQLSTATE '23000' (完整性约束)
MySQL 错误号            MySQL 特定的错误号                     1062 (重复键)
命名条件                DECLARE cond CONDITION FOR ...         自定义条件名
```

## SQLSTATE 与 SQLCODE 体系

### SQLSTATE 标准分类

SQL 标准定义了 5 字符的 SQLSTATE，前两位为类别码：

```
类别码  含义                    常见 SQLSTATE 值
──────  ─────────────────────  ──────────────────────────────────────
'00'    成功                    '00000' 操作成功
'01'    警告                    '01000' 通用警告
                                '01003' 聚合函数中忽略了 NULL
                                '01004' 字符串截断
'02'    无数据                  '02000' NOT FOUND
'08'    连接异常                '08001' 客户端无法建立连接
                                '08003' 连接不存在
                                '08004' 服务器拒绝连接
'21'    基数违反                '21000' 子查询返回多行
'22'    数据异常                '22001' 字符串截断
                                '22003' 数值超出范围
                                '22012' 除以零
                                '22023' 无效参数值
'23'    完整性约束违反          '23000' 通用约束违反
                                '23502' NOT NULL 违反 (PostgreSQL)
                                '23503' 外键违反 (PostgreSQL)
                                '23505' 唯一约束违反 (PostgreSQL)
                                '23514' CHECK 约束违反 (PostgreSQL)
'25'    无效事务状态            '25001' 活跃事务中不允许的操作
'28'    无效授权                '28000' 认证失败
'40'    事务回滚                '40001' 序列化失败 (可重试)
                                '40P01' 死锁检测 (PostgreSQL)
'42'    语法错误/访问规则违反   '42000' 语法错误
                                '42601' 语法错误 (PostgreSQL)
                                '42P01' 表不存在 (PostgreSQL)
                                '42703' 列不存在 (PostgreSQL)
'53'    资源不足                '53100' 磁盘满 (PostgreSQL)
                                '53200' 内存不足 (PostgreSQL)
'57'    操作干预                '57014' 查询取消 (PostgreSQL)
'P0'    PL/pgSQL 错误           'P0001' RAISE EXCEPTION (PostgreSQL)
```

### 各引擎 SQLSTATE 兼容性

```
引擎               SQLSTATE   SQLCODE    自有错误码体系          获取方式
─────────────────  ─────────  ─────────  ─────────────────────  ──────────────────────
PostgreSQL         完整支持    已弃用(1)  无                      GET DIAGNOSTICS / SQLSTATE 变量
Oracle             有限支持    主要使用   ORA-xxxxx 错误体系      SQLCODE / SQLERRM
SQL Server         有限支持    ✗          错误号 + 严重级别体系   ERROR_NUMBER() / ERROR_MESSAGE()
MySQL              完整支持    ✗          MySQL 错误号 (1xxx)     GET DIAGNOSTICS / MYSQL_ERRNO
MariaDB            完整支持    ✗          与 MySQL 兼容           GET DIAGNOSTICS / MYSQL_ERRNO
Db2                完整支持    完整支持   SQLCODE (正/负整数)     SQLCA 结构 / GET DIAGNOSTICS
Snowflake          有限支持    有限支持   SQLCODE + 自有错误码    SQLCODE / SQLERRM (Scripting)
BigQuery           ✗          ✗          google.rpc.Status       @@error.message / @@error.stack_trace
CockroachDB        完整支持    已弃用     CRDB 内部错误码         GET DIAGNOSTICS (PG 兼容)
TiDB               完整支持    ✗          MySQL 兼容错误号        GET DIAGNOSTICS (MySQL 兼容)
OceanBase          完整支持    视模式     双模式 (MySQL/Oracle)   视兼容模式而定
Teradata           完整支持    完整支持   Teradata 错误码体系     ACTIVITY_COUNT / SQLCA
SAP HANA           部分支持    ✗          HANA 错误号             ::SQL_ERROR_CODE / ::SQL_ERROR_MESSAGE

注:
(1) PostgreSQL 的 SQLCODE 在 PL/pgSQL 中仍可用但已弃用，推荐使用 SQLSTATE
```

## 错误抛出语法详解

### THROW vs RAISERROR (SQL Server)

```sql
-- RAISERROR (SQL Server 2000+, 较旧语法)
-- 格式: RAISERROR (message, severity, state [, argument...])
RAISERROR('客户 %d 的余额不足: 需要 %s', 16, 1, @customer_id, @amount);

-- 使用 sp_addmessage 注册自定义消息
EXEC sp_addmessage @msgnum = 60001, @severity = 16,
    @msgtext = N'转账失败: 从账户 %d 到账户 %d, 金额 %s';
RAISERROR(60001, 16, 1, @from_id, @to_id, @amount);

-- THROW (SQL Server 2012+, 推荐)
-- 格式: THROW [error_number, message, state]
THROW 60001, N'余额不足', 1;

-- 在 CATCH 块内无参数 THROW 重新抛出原始错误
BEGIN CATCH
    -- 记录日志...
    THROW;  -- 保留原始错误号和调用栈
END CATCH;
```

THROW 与 RAISERROR 的区别：

```
特性                  THROW                      RAISERROR
───────────────────  ─────────────────────────  ──────────────────────────
最低版本              SQL Server 2012            SQL Server 7.0
错误号范围            50000+                     50000+ (或已注册消息号)
严重级别              始终为 16                   可指定 0-25
SET XACT_ABORT 响应   始终响应（终止事务）        仅严重级别 >= 某阈值时响应
无参数重新抛出         支持 (CATCH 块内)           不支持
格式化参数            不支持                      支持 printf 风格 (%d, %s)
```

### RAISE (PostgreSQL 家族)

```sql
-- PostgreSQL RAISE 语法
-- 级别: DEBUG / LOG / INFO / NOTICE / WARNING / EXCEPTION

-- 信息级别的消息 (不中断执行)
RAISE NOTICE '正在处理客户 %', v_customer_id;
RAISE WARNING '余额接近下限: %', v_balance;

-- 抛出异常 (中断执行，触发 EXCEPTION 块)
RAISE EXCEPTION '余额不足'
    USING ERRCODE = '23514',           -- SQLSTATE
          DETAIL  = '当前余额: ' || v_balance,
          HINT    = '请先充值后再转账';

-- 重新抛出当前异常 (仅在 EXCEPTION 块内)
RAISE;  -- 无参数

-- 使用条件名而非 SQLSTATE
RAISE EXCEPTION '数据完整性错误'
    USING ERRCODE = 'integrity_constraint_violation';
```

### SIGNAL / RESIGNAL (MySQL / MariaDB / Db2)

```sql
-- MySQL / MariaDB
-- SIGNAL: 抛出新错误
SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = '余额不足',
        MYSQL_ERRNO  = 3100;

-- RESIGNAL: 在 handler 中修改并重新抛出
DECLARE EXIT HANDLER FOR SQLEXCEPTION
BEGIN
    GET DIAGNOSTICS CONDITION 1
        @err_msg = MESSAGE_TEXT;
    RESIGNAL SET MESSAGE_TEXT = CONCAT('转账失败: ', @err_msg);
    -- RESIGNAL 不带参数: 原样重新抛出
    -- RESIGNAL;
END;

-- Db2 SIGNAL
SIGNAL SQLSTATE '75000'
    SET MESSAGE_TEXT = '自定义业务错误';
```

### RAISE_APPLICATION_ERROR (Oracle)

```sql
-- Oracle 特有: RAISE_APPLICATION_ERROR
-- 错误号范围: -20000 到 -20999
RAISE_APPLICATION_ERROR(-20001, '余额不足: 当前 ' || v_balance);

-- 可选第三个参数: 是否保留错误栈
RAISE_APPLICATION_ERROR(-20001, '外层错误', TRUE);
-- TRUE: 将新错误添加到已有错误栈顶
-- FALSE (默认): 替换错误栈

-- 将 Oracle 错误码绑定到命名异常
DECLARE
    e_insufficient_funds EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_insufficient_funds, -20001);
BEGIN
    -- 可以在 EXCEPTION 块中用名字捕获
    NULL;
EXCEPTION
    WHEN e_insufficient_funds THEN
        -- 处理余额不足
        NULL;
END;
```

## 错误严重级别对比

```
引擎          级别体系                              说明
───────────  ────────────────────────────────────  ──────────────────────────────
SQL Server   0-10: 信息 (不被 TRY/CATCH 捕获)      0: 信息消息
             11-16: 用户可纠正的错误                 11: 对象不存在
             17-19: 资源/软件错误                    14: 权限不足
             20-25: 致命错误 (断开连接)              16: 通用用户错误
                                                    17: 资源不足
                                                    20: 当前语句致命错误
                                                    21+: 数据库级/服务器级致命

PostgreSQL   DEBUG5-DEBUG1: 调试信息                 日志级别递减
             LOG: 服务器日志                         不发送给客户端
             INFO: 信息                              发送给客户端
             NOTICE: 提示                            发送给客户端
             WARNING: 警告                           发送给客户端
             ERROR: 错误 (中止当前事务)               可被 EXCEPTION 捕获
             FATAL: 致命 (中止会话)                   不可被 EXCEPTION 捕获
             PANIC: 服务器崩溃                        所有会话中止

Oracle       ORA 错误                                ORA-00001 到 ORA-99999
             用户定义                                -20000 到 -20999
             内部错误 (ORA-00600)                     需联系 Oracle 支持

MySQL        Error (SQLEXCEPTION)                    阻止操作完成
             Warning (SQLWARNING)                    操作完成但有问题
             Note/Info                               仅供参考
```

## 事务在错误时的行为

这是各引擎差异最大的领域之一。错误发生后，事务是自动回滚、仅回滚当前语句、还是保持活跃等待用户决定？

### 事务错误行为矩阵

```
引擎               默认行为            SET 选项                   死锁时行为
─────────────────  ─────────────────  ─────────────────────────  ──────────────────────
PostgreSQL         回滚整个事务(1)     ✗ 不可改变                  回滚整个事务
Oracle             仅回滚当前语句      ✗ 不可改变                  回滚当前语句
SQL Server         仅回滚当前语句(2)   SET XACT_ABORT ON 全回滚   回滚整个事务
MySQL (InnoDB)     仅回滚当前语句(3)   ✗ 不可改变                  回滚整个事务
MariaDB            仅回滚当前语句      ✗ 不可改变                  回滚整个事务
Db2                仅回滚当前语句      ✗ 不可改变                  回滚整个事务
Snowflake          回滚整个事务        ✗ 不可改变                  无传统锁, 无死锁
BigQuery           回滚整个事务        ✗ 不可改变                  无传统锁, 无死锁
CockroachDB        回滚整个事务        ✗ 不可改变                  自动重试
TiDB               仅回滚当前语句(4)   SET tidb_retry_limit       乐观锁: 自动重试
OceanBase          视模式而定          ✗                          回滚整个事务
Redshift           回滚整个事务        ✗ 不可改变                  回滚整个事务
Firebird           仅回滚当前语句      ✗ 不可改变                  回滚整个事务
YugabyteDB         回滚整个事务        ✗ 不可改变                  回滚整个事务
SAP HANA           仅回滚当前语句      ✗ 不可改变                  回滚整个事务

注:
(1) PostgreSQL: 错误后事务进入 "aborted" 状态，只能 ROLLBACK
    但 PL/pgSQL 的 EXCEPTION 块隐式使用 savepoint 实现部分回滚
(2) SQL Server: 默认仅回滚当前语句，事务仍然活跃
    但 SET XACT_ABORT ON 使任何运行时错误都回滚整个事务
    建议: 始终使用 SET XACT_ABORT ON + TRY/CATCH
(3) MySQL: 大多数错误仅回滚当前语句
    但死锁 (错误 1213) 和锁等待超时 (错误 1205) 会回滚整个事务
    注意: innodb_rollback_on_timeout=OFF 时，锁超时仅回滚当前语句
(4) TiDB: 乐观事务模型下冲突在 COMMIT 时才检测
    悲观事务模型 (默认, v4.0+) 行为接近 MySQL
```

### PostgreSQL 的事务中止陷阱

```sql
-- PostgreSQL: 一个错误导致事务中所有后续语句都失败
BEGIN;
INSERT INTO t1 VALUES (1);  -- 成功
INSERT INTO t1 VALUES (1);  -- 失败: 唯一约束违反
-- 此时事务进入 "aborted" 状态
SELECT * FROM t1;           -- 错误: current transaction is aborted
                            -- commands ignored until end of transaction block
COMMIT;                     -- 实际执行的是 ROLLBACK
-- INSERT (1) 也被回滚了

-- 解决方案 1: 使用 savepoint
BEGIN;
INSERT INTO t1 VALUES (1);   -- 成功
SAVEPOINT sp1;
INSERT INTO t1 VALUES (1);   -- 失败
ROLLBACK TO SAVEPOINT sp1;   -- 回滚到 savepoint
INSERT INTO t1 VALUES (2);   -- 成功
COMMIT;                       -- (1) 和 (2) 都提交

-- 解决方案 2: 在 PL/pgSQL 中使用 EXCEPTION 块 (隐式 savepoint)
DO $$
BEGIN
    INSERT INTO t1 VALUES (1);
    BEGIN
        INSERT INTO t1 VALUES (1);  -- 失败，但被捕获
    EXCEPTION WHEN unique_violation THEN
        RAISE NOTICE '跳过重复值';
    END;
    INSERT INTO t1 VALUES (2);      -- 继续执行
END $$;

-- 解决方案 3: ON CONFLICT (PostgreSQL 9.5+)
INSERT INTO t1 VALUES (1) ON CONFLICT DO NOTHING;
```

### SQL Server 的 XACT_ABORT 最佳实践

```sql
-- 不使用 XACT_ABORT: 事务可能处于不一致状态
BEGIN TRANSACTION;
INSERT INTO orders VALUES (1, 100);  -- 成功
INSERT INTO orders VALUES (1, 200);  -- 失败 (主键冲突)
-- 事务仍然活跃! 第一条 INSERT 仍在事务中
-- 如果此时 COMMIT，第一条 INSERT 会被提交
COMMIT;  -- 只有第一条被提交 -> 可能不是期望的行为

-- 使用 XACT_ABORT ON: 错误时自动回滚整个事务
SET XACT_ABORT ON;
BEGIN TRANSACTION;
INSERT INTO orders VALUES (1, 100);  -- 成功
INSERT INTO orders VALUES (1, 200);  -- 失败 -> 自动回滚整个事务
-- 两条 INSERT 都被回滚

-- 推荐模式: XACT_ABORT + TRY/CATCH
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    -- ... 多条 DML ...
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
```

## GET DIAGNOSTICS / @@ERROR / SQLERRM 详解

### GET DIAGNOSTICS (SQL 标准)

```sql
-- PostgreSQL (GET STACKED DIAGNOSTICS, 仅在 EXCEPTION 块内)
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
        v_sqlstate  = RETURNED_SQLSTATE,
        v_message   = MESSAGE_TEXT,
        v_detail    = PG_EXCEPTION_DETAIL,
        v_hint      = PG_EXCEPTION_HINT,
        v_context   = PG_EXCEPTION_CONTEXT,
        v_column    = COLUMN_NAME,
        v_table     = TABLE_NAME,
        v_schema    = SCHEMA_NAME,
        v_constraint = CONSTRAINT_NAME,
        v_datatype  = PG_DATATYPE_NAME;

-- MySQL / MariaDB (GET DIAGNOSTICS, 可在 handler 内外使用)
GET DIAGNOSTICS @row_count = ROW_COUNT, @num_conditions = NUMBER;
GET DIAGNOSTICS CONDITION 1
    @sqlstate = RETURNED_SQLSTATE,
    @errno    = MYSQL_ERRNO,
    @message  = MESSAGE_TEXT,
    @table    = TABLE_NAME,
    @column   = COLUMN_NAME,
    @schema   = SCHEMA_NAME,
    @constraint = CONSTRAINT_NAME;

-- Db2 (GET DIAGNOSTICS, 最接近 SQL 标准)
GET DIAGNOSTICS
    v_row_count = ROW_COUNT,
    v_return_status = DB2_RETURN_STATUS;
GET DIAGNOSTICS CONDITION 1
    v_sqlstate = RETURNED_SQLSTATE,
    v_sqlcode  = DB2_SQLCODE,
    v_message  = MESSAGE_TEXT,
    v_token    = DB2_TOKEN_STRING;
```

### 各引擎的错误信息获取方式

```
引擎               获取错误号                获取错误消息                获取调用栈
─────────────────  ──────────────────────  ──────────────────────────  ──────────────────────────
SQL Server         ERROR_NUMBER()          ERROR_MESSAGE()             ERROR_PROCEDURE() + ERROR_LINE()
PostgreSQL         GET STACKED DIAGNOSTICS GET STACKED DIAGNOSTICS     PG_EXCEPTION_CONTEXT
                   RETURNED_SQLSTATE       MESSAGE_TEXT
Oracle PL/SQL      SQLCODE                 SQLERRM                     DBMS_UTILITY.FORMAT_ERROR_BACKTRACE
                                                                       DBMS_UTILITY.FORMAT_ERROR_STACK (12c+)
MySQL              GET DIAGNOSTICS         GET DIAGNOSTICS             SHOW WARNINGS (有限)
                   MYSQL_ERRNO             MESSAGE_TEXT
MariaDB            GET DIAGNOSTICS         GET DIAGNOSTICS             SHOW WARNINGS (有限)
                   MYSQL_ERRNO             MESSAGE_TEXT
Db2                SQLCA.SQLCODE           SQLCA.SQLERRMC              SQLCA.SQLERRP
                   GET DIAGNOSTICS         GET DIAGNOSTICS
Snowflake          SQLCODE (Scripting)     SQLERRM (Scripting)         无
BigQuery           @@error.message         @@error.message             @@error.stack_trace
                                           @@error.statement_text
Teradata           ACTIVITY_COUNT          SQLCA                       无
SAP HANA           ::SQL_ERROR_CODE        ::SQL_ERROR_MESSAGE         无
CockroachDB        GET STACKED DIAGNOSTICS GET STACKED DIAGNOSTICS     PG_EXCEPTION_CONTEXT (PG 兼容)
Firebird           SQLCODE / GDSCODE       通过 RDB$GET_CONTEXT 或     无
                                           WHEN GDSCODE ... 捕获
```

## Savepoint 与部分回滚

Savepoint 是实现细粒度错误恢复的关键机制，允许在事务内回滚到特定点而不影响之前的修改。

```sql
-- 标准语法 (大部分引擎支持)
SAVEPOINT sp1;
-- ... 操作 ...
ROLLBACK TO SAVEPOINT sp1;  -- 回滚到 sp1, 事务仍然活跃
RELEASE SAVEPOINT sp1;      -- 释放 savepoint (可选)
```

### Savepoint 支持矩阵

```
引擎               SAVEPOINT  ROLLBACK TO  RELEASE  嵌套 Savepoint  自动 Savepoint
─────────────────  ─────────  ───────────  ───────  ─────────────  ─────────────────
PostgreSQL         ✓          ✓            ✓        ✓              EXCEPTION 块隐式创建
Oracle             ✓          ✓            ✗(1)     ✓              ✗
SQL Server         ✓(2)       ✓            ✗        ✓              ✗
MySQL (InnoDB)     ✓          ✓            ✓        ✓              ✗
MariaDB            ✓          ✓            ✓        ✓              ✗
Db2                ✓          ✓            ✓        ✓              UNDO handler 隐式使用
Snowflake          ✗(3)       ✗            ✗        ✗              ✗
BigQuery           ✗          ✗            ✗        ✗              ✗
CockroachDB        ✓          ✓            ✓        ✓              ✓ (可配置)
TiDB               ✓          ✓            ✓        ✓              ✗
OceanBase          ✓          ✓            ✓        ✓              ✗
SQLite             ✓          ✓            ✓        ✓              ✗
DuckDB             ✓          ✓            ✓        ✓              ✗
Redshift           ✓          ✓            ✗        ✓              ✗
Firebird           ✓          ✓            ✓        ✓              WHEN 块隐式使用
YugabyteDB         ✓          ✓            ✓        ✓              ✗
SAP HANA           ✓          ✓            ✗        ✓              ✗

注:
(1) Oracle 不支持 RELEASE SAVEPOINT, savepoint 在事务结束时自动释放
(2) SQL Server 使用 SAVE TRANSACTION name 而非 SAVEPOINT name
(3) Snowflake 不支持 savepoint, 事务是全提交或全回滚
```

### 使用 Savepoint 实现批量操作的容错处理

```sql
-- PostgreSQL: 批量插入, 跳过失败行
DO $$
DECLARE
    v_ids INT[] := ARRAY[1, 2, 3, 4, 5];
    v_id INT;
    v_success_count INT := 0;
    v_fail_count INT := 0;
BEGIN
    FOREACH v_id IN ARRAY v_ids LOOP
        BEGIN
            INSERT INTO target_table (id, data)
            SELECT id, data FROM source_table WHERE id = v_id;
            v_success_count := v_success_count + 1;
        EXCEPTION WHEN OTHERS THEN
            v_fail_count := v_fail_count + 1;
            RAISE NOTICE '跳过 id=%: %', v_id, SQLERRM;
            -- 隐式 ROLLBACK TO SAVEPOINT, 继续下一条
        END;
    END LOOP;
    RAISE NOTICE '成功: %, 失败: %', v_success_count, v_fail_count;
END $$;

-- SQL Server: 等效实现
DECLARE @id INT, @success INT = 0, @fail INT = 0;
DECLARE cur CURSOR FOR SELECT id FROM source_ids;
OPEN cur;
FETCH NEXT FROM cur INTO @id;
WHILE @@FETCH_STATUS = 0
BEGIN
    SAVE TRANSACTION sp_row;
    BEGIN TRY
        INSERT INTO target_table (id, data)
        SELECT id, data FROM source_table WHERE id = @id;
        SET @success = @success + 1;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION sp_row;
        SET @fail = @fail + 1;
    END CATCH;
    FETCH NEXT FROM cur INTO @id;
END;
CLOSE cur;
DEALLOCATE cur;

-- MySQL: 等效实现
DELIMITER //
CREATE PROCEDURE batch_insert()
BEGIN
    DECLARE v_id INT;
    DECLARE v_done BOOLEAN DEFAULT FALSE;
    DECLARE v_success INT DEFAULT 0;
    DECLARE v_fail INT DEFAULT 0;
    DECLARE cur CURSOR FOR SELECT id FROM source_ids;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        SET v_fail = v_fail + 1;
        ROLLBACK TO SAVEPOINT sp_row;
    END;

    START TRANSACTION;
    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_id;
        IF v_done THEN LEAVE read_loop; END IF;
        SAVEPOINT sp_row;
        INSERT INTO target_table (id, data)
        SELECT id, data FROM source_table WHERE id = v_id;
        SET v_success = v_success + 1;
    END LOOP;
    CLOSE cur;
    COMMIT;
    SELECT v_success AS success_count, v_fail AS fail_count;
END //
DELIMITER ;
```

## 死锁处理与重试模式

### 死锁检测与自动重试

```
引擎               死锁检测机制              默认超时        重试建议
─────────────────  ──────────────────────  ──────────────  ──────────────────────────
MySQL (InnoDB)     等待图 (wait-for graph)  50 秒           应用层重试; 错误 1213
MariaDB            等待图                   50 秒           应用层重试; 错误 1213
PostgreSQL         等待图                   无超时(1)       应用层重试; SQLSTATE 40P01
Oracle             等待图                   即时检测        应用层重试; ORA-00060
SQL Server         等待图                   即时检测（lock_timeout 默认无限）  应用层重试; 错误 1205
Db2                等待图                   可配置          应用层重试; SQLSTATE 40001
CockroachDB        时间戳排序               自动重试(2)     引擎内自动重试
TiDB               等待图 (悲观锁)           50 秒           可配置自动重试
Snowflake          无传统锁                 可配置（默认无限制）  无死锁, 但有并发冲突
BigQuery           无传统锁                 无              无死锁, 但有并发 DML 冲突

注:
(1) PostgreSQL deadlock_timeout 默认 1 秒 (开始死锁检测的延迟, 不是超时)
    lock_timeout 默认为 0 (无限等待)
(2) CockroachDB 读写事务中的可重试错误 (SQLSTATE 40001) 会在引擎内自动重试
    如果事务使用了 AS OF SYSTEM TIME 则不会自动重试
```

### 应用层重试模式

```sql
-- PostgreSQL: 在 PL/pgSQL 中实现重试
CREATE OR REPLACE FUNCTION transfer_with_retry(
    p_from INT, p_to INT, p_amount NUMERIC, p_max_retries INT DEFAULT 3
) RETURNS VOID AS $$
DECLARE
    v_retry INT := 0;
    v_done BOOLEAN := FALSE;
BEGIN
    WHILE NOT v_done AND v_retry < p_max_retries LOOP
        BEGIN
            UPDATE accounts SET balance = balance - p_amount WHERE id = p_from;
            UPDATE accounts SET balance = balance + p_amount WHERE id = p_to;
            v_done := TRUE;
        EXCEPTION
            WHEN deadlock_detected THEN  -- SQLSTATE 40P01
                v_retry := v_retry + 1;
                IF v_retry >= p_max_retries THEN
                    RAISE EXCEPTION '重试 % 次后仍然死锁', p_max_retries;
                END IF;
                RAISE NOTICE '死锁检测, 第 % 次重试', v_retry;
                PERFORM pg_sleep(0.1 * v_retry);  -- 退避等待
            WHEN serialization_failure THEN  -- SQLSTATE 40001
                v_retry := v_retry + 1;
                IF v_retry >= p_max_retries THEN
                    RAISE EXCEPTION '重试 % 次后仍然序列化失败', p_max_retries;
                END IF;
                PERFORM pg_sleep(0.1 * v_retry);
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- SQL Server: 在 T-SQL 中实现重试
CREATE PROCEDURE dbo.transfer_with_retry
    @from_id INT, @to_id INT, @amount DECIMAL(10,2), @max_retries INT = 3
AS
BEGIN
    SET XACT_ABORT ON;
    DECLARE @retry INT = 0;

    WHILE @retry < @max_retries
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;
            UPDATE accounts SET balance = balance - @amount WHERE id = @from_id;
            UPDATE accounts SET balance = balance + @amount WHERE id = @to_id;
            COMMIT TRANSACTION;
            RETURN;  -- 成功退出
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0
                ROLLBACK TRANSACTION;

            IF ERROR_NUMBER() = 1205  -- 死锁
            BEGIN
                SET @retry = @retry + 1;
                IF @retry >= @max_retries
                    THROW;
                WAITFOR DELAY '00:00:00.100';  -- 100ms 退避
            END
            ELSE
                THROW;  -- 非死锁错误直接抛出
        END CATCH;
    END;
END;

-- CockroachDB: 使用 SAVEPOINT cockroach_restart 实现自动重试
-- 这是 CockroachDB 特有的重试协议
BEGIN;
SAVEPOINT cockroach_restart;

-- ... 事务操作 ...
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;

-- 如果遇到重试错误 (40001), 回滚到 savepoint 并重试
RELEASE SAVEPOINT cockroach_restart;
COMMIT;

-- 客户端伪代码:
-- LOOP:
--   BEGIN; SAVEPOINT cockroach_restart;
--   执行 SQL
--   RELEASE SAVEPOINT cockroach_restart; COMMIT;
--   IF 成功: BREAK
--   IF 40001: ROLLBACK TO SAVEPOINT cockroach_restart; CONTINUE
--   ELSE: ROLLBACK; RAISE
```

## 嵌套过程中的错误传播

### 错误传播规则

```
引擎               默认传播行为                          可否阻止传播
─────────────────  ──────────────────────────────────  ──────────────────
SQL Server         未捕获的错误向上传播到调用者          TRY/CATCH 捕获后不传播
PostgreSQL         异常自动传播到外层 EXCEPTION 块       EXCEPTION 块捕获后不传播
Oracle PL/SQL      异常自动传播到外层 EXCEPTION 块       EXCEPTION 块捕获后不传播
                   WHEN OTHERS 不含 RAISE 则不传播      需显式 RAISE 重新抛出
MySQL              handler 执行后按类型决定:             CONTINUE: 继续执行
                   CONTINUE handler -> 继续执行          EXIT: 退出当前块
                   EXIT handler -> 退出当前块            未处理: 向上传播
Db2                同 MySQL, 增加 UNDO handler           UNDO: 回滚后退出当前块
```

### 嵌套过程错误传播示例

```sql
-- SQL Server: 嵌套 TRY/CATCH
CREATE PROCEDURE dbo.inner_proc AS
BEGIN
    BEGIN TRY
        INSERT INTO t1 VALUES (1);  -- 假设主键冲突
    END TRY
    BEGIN CATCH
        -- 内层捕获: 记录日志但不重新抛出
        INSERT INTO error_log (msg) VALUES (ERROR_MESSAGE());
        -- 如果不 THROW, 错误不传播到外层
        -- THROW;  -- 取消注释以传播
    END CATCH;
END;

CREATE PROCEDURE dbo.outer_proc AS
BEGIN
    BEGIN TRY
        EXEC dbo.inner_proc;
        -- 如果 inner_proc 没有 THROW, 这里继续执行
        PRINT '继续执行';
    END TRY
    BEGIN CATCH
        PRINT '外层捕获: ' + ERROR_MESSAGE();
    END CATCH;
END;

-- PostgreSQL: 嵌套 EXCEPTION 块
CREATE OR REPLACE FUNCTION outer_func() RETURNS VOID AS $$
BEGIN
    BEGIN
        -- 调用内层函数
        PERFORM inner_func();
    EXCEPTION
        WHEN OTHERS THEN
            -- 捕获 inner_func 抛出的任何未处理异常
            RAISE NOTICE '外层捕获: %', SQLERRM;
    END;
    RAISE NOTICE '外层继续执行';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION inner_func() RETURNS VOID AS $$
BEGIN
    BEGIN
        INSERT INTO t1 VALUES (1);  -- 假设主键冲突
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE '内层处理: 重复键';
            -- 不再 RAISE, 异常被消化
        WHEN OTHERS THEN
            RAISE;  -- 其他异常重新抛出, 传播到外层
    END;
END;
$$ LANGUAGE plpgsql;

-- Oracle: WHEN OTHERS + RAISE 的传播陷阱
CREATE OR REPLACE PROCEDURE inner_proc IS
BEGIN
    INSERT INTO t1 VALUES (1);  -- 假设主键冲突
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('内层处理');
        -- 不 RAISE: 异常被消化, 外层不知道出了错
    WHEN OTHERS THEN
        -- 常见错误: 捕获 OTHERS 但不 RAISE
        -- 导致所有错误被静默吞掉
        DBMS_OUTPUT.PUT_LINE('错误: ' || SQLERRM);
        RAISE;  -- 最佳实践: 始终在 WHEN OTHERS 中 RAISE
END;
/
```

### Oracle WHEN OTHERS 的危险反模式

```sql
-- 反模式: 吞掉所有异常
-- 这是 Oracle PL/SQL 中最常见的错误之一
CREATE OR REPLACE PROCEDURE bad_practice IS
BEGIN
    -- ... 业务逻辑 ...
    NULL;
EXCEPTION
    WHEN OTHERS THEN
        NULL;  -- 静默吞掉所有错误!
        -- 调用者完全不知道发生了什么
        -- Oracle 编译器在 11g+ 会给出 PLW-06009 警告
END;
/

-- 正确做法: 记录 + 重新抛出
CREATE OR REPLACE PROCEDURE good_practice IS
    v_error_stack VARCHAR2(4000);
BEGIN
    -- ... 业务逻辑 ...
    NULL;
EXCEPTION
    WHEN OTHERS THEN
        v_error_stack := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
        INSERT INTO error_log (error_code, error_msg, error_stack, created_at)
        VALUES (SQLCODE, SQLERRM, v_error_stack, SYSTIMESTAMP);
        COMMIT;  -- 使用自治事务更好 (PRAGMA AUTONOMOUS_TRANSACTION)
        RAISE;   -- 重新抛出, 让调用者知道
END;
/
```

## WHENEVER SQLERROR (嵌入式 SQL)

嵌入式 SQL (Embedded SQL) 是一种将 SQL 语句直接嵌入宿主语言 (C, COBOL 等) 的编程方式。`WHENEVER` 指令用于声明式地指定错误处理行为。

```
引擎               WHENEVER 支持   嵌入式 SQL 预编译器
─────────────────  ─────────────  ──────────────────────
Db2                ✓              db2 precompile (sqc -> c)
Oracle             ✓              Pro*C / Pro*COBOL
Informix           ✓              ESQL/C
PostgreSQL         ✓              ECPG (ecpg -> c)
Teradata           ✓              Teradata Preprocessor
SQL Server         ✗(已弃用)       早期有 Embedded SQL for C
MySQL              ✗              无官方嵌入式 SQL
```

```c
/* Pro*C (Oracle 嵌入式 SQL) 示例 */
EXEC SQL WHENEVER SQLERROR GOTO error_handler;
EXEC SQL WHENEVER SQLWARNING CONTINUE;
EXEC SQL WHENEVER NOT FOUND GOTO not_found_handler;

EXEC SQL SELECT name INTO :v_name FROM customers WHERE id = :v_id;
/* 如果 NOT FOUND -> 跳转到 not_found_handler */
/* 如果出错 -> 跳转到 error_handler */

printf("客户名: %s\n", v_name);
EXEC SQL COMMIT;
goto done;

not_found_handler:
    printf("客户不存在\n");
    goto done;

error_handler:
    printf("SQL 错误: %d - %s\n", sqlca.sqlcode, sqlca.sqlerrmc);
    EXEC SQL ROLLBACK;

done:
    EXEC SQL DISCONNECT;
```

```c
/* ECPG (PostgreSQL 嵌入式 SQL) 示例 */
EXEC SQL WHENEVER SQLERROR SQLPRINT;    /* 打印错误并继续 */
EXEC SQL WHENEVER SQLERROR STOP;        /* 打印错误并终止程序 */
EXEC SQL WHENEVER SQLERROR DO handle_error(); /* 调用自定义函数 */
EXEC SQL WHENEVER SQLERROR GOTO label;  /* 跳转到标签 */
EXEC SQL WHENEVER SQLERROR CONTINUE;    /* 忽略错误继续 */

/* WHENEVER 是预编译指令, 作用范围是"从声明处到下一个同类 WHENEVER 指令" */
/* 不是运行时动态的, 是在预编译阶段替换为条件检查代码 */

EXEC SQL WHENEVER SQLERROR DO handle_error();
EXEC SQL INSERT INTO t1 VALUES (:val);
/* 预编译后等效于:
   ECPGdo(..., "INSERT INTO t1 VALUES ($1)", ...);
   if (sqlca.sqlcode < 0) handle_error();
*/
```

### SQLCA 结构 (SQL Communication Area)

```
字段             类型          说明
──────────────  ──────────  ──────────────────────────────────
sqlca.sqlcode   int         SQL 返回码: 0=成功, 100=NOT FOUND, <0=错误
sqlca.sqlerrml  short       错误消息长度
sqlca.sqlerrmc  char[70]    错误消息文本 (截断到 70 字符)
sqlca.sqlerrp   char[8]     诊断信息 (引擎特定)
sqlca.sqlerrd   int[6]      诊断计数器:
                             [2] = 影响的行数 (多数引擎)
                             [4] = 语句解析位置 (某些引擎)
sqlca.sqlwarn   char[8]     警告标志数组
sqlca.sqlstate  char[5]     SQLSTATE (5 字符)
```

## BigQuery 和 Snowflake 的现代错误处理

### BigQuery: 脚本中的 BEGIN...EXCEPTION

```sql
-- BigQuery Scripting (2023+)
BEGIN
    DECLARE x INT64 DEFAULT 0;

    BEGIN
        SET x = 1 / 0;  -- 除以零错误
    EXCEPTION WHEN ERROR THEN
        -- BigQuery 只支持 WHEN ERROR (catch-all)
        -- 不支持按 SQLSTATE 过滤
        SELECT
            @@error.message AS error_message,
            @@error.stack_trace AS stack_trace,
            @@error.statement_text AS failed_sql,
            @@error.formatted_stack_trace AS formatted_trace;

        SET x = -1;  -- 使用默认值
    END;

    SELECT x;  -- 输出 -1
END;

-- BigQuery: RAISE 抛出自定义错误
BEGIN
    IF (SELECT COUNT(*) FROM orders WHERE status = 'pending') > 1000 THEN
        RAISE USING MESSAGE = '待处理订单过多, 请稍后重试';
    END IF;
END;
```

### Snowflake: Snowflake Scripting 错误处理

```sql
-- Snowflake Scripting (2022+ GA)
DECLARE
    my_exception EXCEPTION (-20001, '自定义业务错误');
    v_sqlcode NUMBER;
    v_sqlerrm VARCHAR;
BEGIN
    BEGIN
        -- 可能失败的操作
        INSERT INTO target SELECT * FROM source WHERE id = :id;

        IF (SQLROWCOUNT = 0) THEN
            RAISE my_exception;
        END IF;
    EXCEPTION
        WHEN my_exception THEN
            v_sqlcode := SQLCODE;
            v_sqlerrm := SQLERRM;
            INSERT INTO error_log VALUES (:v_sqlcode, :v_sqlerrm, CURRENT_TIMESTAMP());

        WHEN statement_error THEN
            -- Snowflake 预定义异常: 语句执行错误
            RETURN 'SQL 语句执行失败: ' || SQLERRM;

        WHEN expression_error THEN
            -- Snowflake 预定义异常: 表达式求值错误
            RETURN '表达式错误: ' || SQLERRM;

        WHEN OTHER THEN
            -- 捕获所有其他异常
            RAISE;  -- 重新抛出
    END;

    RETURN 'SUCCESS';
END;
```

## Firebird 的命名异常机制

Firebird 使用 DDL 级别的命名异常，这在 SQL 引擎中比较独特：

```sql
-- Firebird: 在数据库级别创建命名异常
CREATE EXCEPTION e_insufficient_funds '余额不足';
CREATE EXCEPTION e_account_locked '账户已锁定';

-- 在存储过程中使用
CREATE PROCEDURE transfer_funds(
    p_from INTEGER, p_to INTEGER, p_amount DECIMAL(10,2))
AS
    DECLARE VARIABLE v_balance DECIMAL(10,2);
BEGIN
    SELECT balance FROM accounts WHERE id = :p_from INTO :v_balance;

    IF (v_balance < p_amount) THEN
        EXCEPTION e_insufficient_funds
            '账户 ' || :p_from || ' 余额不足, 当前: ' || :v_balance;
    END

    UPDATE accounts SET balance = balance - :p_amount WHERE id = :p_from;
    UPDATE accounts SET balance = balance + :p_amount WHERE id = :p_to;

    WHEN EXCEPTION e_insufficient_funds DO
    BEGIN
        -- 捕获特定命名异常
        -- 可通过 RDB$GET_CONTEXT('SYSTEM', 'GDSCODE') 获取错误码
        EXECUTE PROCEDURE log_error(SQLCODE, 'transfer_funds');
    END
    WHEN SQLCODE -803 DO  -- 唯一约束违反
    BEGIN
        EXECUTE PROCEDURE log_error(-803, 'transfer_funds');
    END
    WHEN ANY DO
    BEGIN
        -- 相当于 WHEN OTHERS
        EXECUTE PROCEDURE log_error(SQLCODE, 'transfer_funds');
        EXCEPTION;  -- 重新抛出
    END
END;
```

## SAP HANA 的错误处理 (DECLARE HANDLER 模型)

```sql
-- SAP HANA SQLScript: 使用 DECLARE EXIT/CONTINUE HANDLER 模型 (类似 MySQL/Db2)
-- 注意: SAP HANA 不使用 PostgreSQL/Oracle 风格的 BEGIN...EXCEPTION...END 块

-- 模式 1: DECLARE EXIT HANDLER (推荐)
CREATE PROCEDURE transfer_funds(
    IN p_from INT, IN p_to INT, IN p_amount DECIMAL(10,2))
LANGUAGE SQLSCRIPT
AS
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DECLARE v_code INT := ::SQL_ERROR_CODE;
        DECLARE v_msg NVARCHAR(5000) := ::SQL_ERROR_MESSAGE;
        INSERT INTO error_log VALUES (:v_code, :v_msg, CURRENT_TIMESTAMP);
        RESIGNAL;
    END;

    UPDATE accounts SET balance = balance - :p_amount WHERE id = :p_from;
    UPDATE accounts SET balance = balance + :p_amount WHERE id = :p_to;
END;

-- 模式 2: SIGNAL + 自定义条件
CREATE PROCEDURE validate_order(IN p_amount DECIMAL(10,2))
LANGUAGE SQLSCRIPT
AS
BEGIN
    DECLARE invalid_amount CONDITION FOR SQL_ERROR_CODE 10001;

    IF :p_amount <= 0 THEN
        SIGNAL invalid_amount SET MESSAGE_TEXT = '金额必须大于零';
    END IF;
END;
```

## 各引擎错误处理完整对比矩阵

```
特性                  SQL Server   PostgreSQL  Oracle    MySQL     Db2       Snowflake  BigQuery
───────────────────  ───────────  ──────────  ────────  ────────  ────────  ─────────  ────────
捕获机制              TRY/CATCH    EXCEPTION   EXCEPTION HANDLER   HANDLER   EXCEPTION  EXCEPTION
抛出机制              THROW        RAISE       RAISE     SIGNAL    SIGNAL    RAISE      RAISE
重新抛出              THROW (无参) RAISE (无参) RAISE     RESIGNAL  RESIGNAL  RAISE      RAISE
按SQLSTATE捕获        ✗            ✓           部分      ✓         ✓         ✗          ✗
按错误号捕获          ✗(ERROR_NUMBER) ✗        ✓(PRAGMA) ✓(ERRNO)  ✓         ✗          ✗
预定义异常名          ✗            ✓(40+个)    ✓(20+个)  ✗         ✗         ✓(3个)     ✓(1个)
用户自定义异常        ✗            ✓(SQLSTATE) ✓(PRAGMA) ✓(COND)   ✓(COND)   ✓(EXCPT)   ✗
获取错误号            ERROR_NUMBER() SQLSTATE  SQLCODE   GET DIAG  GET DIAG  SQLCODE    @@error
获取错误消息          ERROR_MESSAGE() SQLERRM  SQLERRM   GET DIAG  GET DIAG  SQLERRM    @@error
获取调用栈            ERROR_LINE() CONTEXT     BACKTRACE ✗         ✗         ✗          stack_trace
子事务/Savepoint      手动         隐式创建    ✗         手动      UNDO      ✗          ✗
嵌套捕获              ✓            ✓           ✓         ✓         ✓         ✓          ✓
事务感知              XACT_STATE() ✗(自动)     ✗(手动)   ✗(手动)   ✗(手动)   ✗(自动)    ✗(自动)
错误严重级别          0-25         7 级        ✗         3 级      ✗         ✗          ✗
```

## 对引擎开发者的实现建议

### 1. 错误码体系设计

```
建议: 同时支持 SQLSTATE 和引擎特定错误码

SQLSTATE 优点:
  - SQL 标准, 跨引擎可移植
  - 5 字符, 分类清晰 (类别 + 子类别)
  - 客户端库通常都支持

SQLSTATE 不足:
  - 粒度不够细: '23000' 同时表示唯一约束、外键约束、CHECK 约束违反
  - PostgreSQL 的做法最佳: 在 '23' 类别下细分
    '23502' = NOT NULL, '23503' = FOREIGN KEY, '23505' = UNIQUE, '23514' = CHECK
  - MySQL 也做了细分但通过 MYSQL_ERRNO 补充而非 SQLSTATE 子类别

实现建议:
  1. 核心使用 SQLSTATE 5 字符标准格式
  2. 扩展子类别以提供更细粒度 (参考 PostgreSQL 做法)
  3. 额外提供引擎特定的整数错误码 (便于编程判断)
  4. 为每个错误码提供: 错误消息模板、严重级别、是否可重试、建议动作
```

### 2. 错误捕获架构

```
三种模型各有取舍:

TRY/CATCH (SQL Server 风格):
  + 开发者最熟悉 (类似 Java/C#/Python)
  + 结构清晰, 易于阅读
  - 不支持按条件精细捕获 (只能在 CATCH 内用 ERROR_NUMBER() 判断)
  - 需要额外的 XACT_STATE() / @@TRANCOUNT 判断事务状态

BEGIN...EXCEPTION (PostgreSQL/Oracle 风格):
  + 支持按条件名/SQLSTATE 精细捕获
  + PostgreSQL 的隐式 savepoint 简化了事务管理
  - PostgreSQL 的隐式 savepoint 有性能开销
  - Oracle 不自动回滚, 需手动管理事务状态

DECLARE HANDLER (MySQL/Db2 风格):
  + 声明式, 将错误处理策略与业务逻辑分离
  + 支持 CONTINUE/EXIT/UNDO 三种行为
  - 控制流不直观 (handler 在何时何地执行不够显式)
  - 调试困难 (handler 执行后回到哪里不直观)

推荐: 新引擎优先实现 BEGIN...EXCEPTION 模式
  - 它平衡了表达力和直观性
  - PostgreSQL 的条件名系统是很好的参考
  - 考虑可选的隐式 savepoint (通过配置开关)
```

### 3. 事务错误行为设计

```
这是影响应用开发体验的最关键决策之一。

选项 A: 错误后回滚整个事务 (PostgreSQL 模式)
  + 安全: 不可能在错误状态下提交部分操作
  + 行为简单一致
  - 灵活性低: 无法在事务内"跳过错误继续"
  - 必须使用 savepoint/EXCEPTION 实现部分回滚 (有性能开销)

选项 B: 仅回滚当前语句 (Oracle/MySQL 模式)
  + 灵活: 应用可以决定是否继续或回滚
  + 批量操作中可以跳过个别失败
  - 危险: 应用忘记检查错误状态会导致不一致数据被提交
  - 需要更多应用层代码来确保一致性

选项 C: 可配置 (SQL Server 模式, XACT_ABORT)
  + 最大灵活性
  - 增加了认知复杂度
  - 不同配置下的行为差异是 bug 来源

推荐:
  - 默认行为选择 B (仅回滚当前语句), 因为这是大多数引擎的做法
  - 提供类似 XACT_ABORT 的选项让用户选择全回滚
  - 死锁和序列化失败强制回滚整个事务 (所有主流引擎都这样做)
  - 对于分布式引擎, 选项 A 更安全 (分布式 savepoint 代价很高)
```

### 4. 错误传播机制

```
关键设计点:

1. 未处理异常的默认传播:
   - 未被任何 handler/EXCEPTION 块捕获的错误应自动向上传播
   - 传播到最外层后返回给客户端
   - 保留完整的错误链 (inner exception / cause chain)

2. 错误信息的丰富程度:
   最小集合 (必须实现):
     - 错误码 (SQLSTATE + 引擎特定码)
     - 错误消息 (支持参数化模板)
     - 发生位置 (过程名 + 行号)

   推荐扩展:
     - 调用栈 (backtrace) -- PostgreSQL 和 Oracle 都支持
     - 相关对象信息 (表名、列名、约束名)
     - 建议动作 (hint)
     - 错误详情 (detail)

3. RESIGNAL / 重新抛出:
   - 必须支持无参数 RAISE/THROW 重新抛出原始异常
   - 保留原始错误码和调用栈
   - 可选支持 RESIGNAL 修改部分属性后重新抛出 (MySQL/Db2)

4. 错误信息的安全性:
   - 内部错误消息不应暴露实现细节 (表结构、文件路径等)
   - 考虑区分面向开发者和面向终端用户的错误消息
   - 敏感信息应仅记录到服务器日志, 不返回给客户端
```

### 5. 死锁与重试的引擎支持

```
对引擎开发者的建议:

1. 死锁检测:
   - 使用等待图 (wait-for graph) 检测死锁
   - 检测延迟应可配置 (参考 PostgreSQL 的 deadlock_timeout)
   - 选择"代价最小"的事务作为牺牲者 (victim)
   - 返回明确的 SQLSTATE '40001' 或 '40P01'

2. 可重试错误标记:
   - 在错误元数据中标记"是否可重试" (is_retryable)
   - 典型可重试错误: 死锁 (40001), 序列化失败 (40001), 临时连接错误
   - 这让客户端库能够实现自动重试
   - CockroachDB 的做法可参考: SQLSTATE 40001 表示可重试

3. 引擎内重试 vs 客户端重试:
   - 引擎内重试 (如 CockroachDB): 对应用透明, 但增加引擎复杂度
   - 客户端重试: 引擎简单, 但需要客户端库支持
   - 推荐: 提供两种模式
     a. 简单事务 (无副作用): 引擎内自动重试
     b. 复杂事务 (有副作用): 通知客户端重试

4. 退避策略:
   - 建议客户端使用指数退避 + 随机抖动
   - 引擎可在错误响应中建议等待时间 (retry-after)
```

### 6. 分析型引擎的简化方案

```
对于 OLAP / 分析型引擎 (如对标 ClickHouse, DuckDB, Trino):
  - 通常不需要存储过程级别的错误处理
  - 但仍应考虑:

1. 查询级错误恢复:
   - TRY_CAST / SAFE_CAST 等安全函数 (见 error-handling-safe.md)
   - 部分行失败时的策略: 跳过 vs 终止 vs 记录到错误表

2. ETL 场景的错误表:
   - COPY INTO 失败行写入错误表 (Snowflake ON_ERROR = CONTINUE)
   - 记录: 行号、原始数据、错误原因

3. 查询取消与超时:
   - 支持查询级别的超时设置
   - 支持异步取消 (CANCEL QUERY)
   - 超时应返回 SQLSTATE '57014' (query_canceled)
```

### 7. PostgreSQL EXCEPTION 块的性能陷阱

PostgreSQL 的 `BEGIN...EXCEPTION...END` 块在进入时隐式创建 savepoint，这在高频错误场景下会造成严重的性能问题:

```
-- 性能分析: EXCEPTION 块的隐式 savepoint 开销

无 EXCEPTION 块:
  BEGIN
    INSERT INTO t VALUES (...);  -- 直接执行, 无额外开销
  END;

有 EXCEPTION 块:
  BEGIN                          -- → 隐式 SAVEPOINT (写入 WAL)
    INSERT INTO t VALUES (...);  -- 执行
  EXCEPTION                      -- → 如果异常: ROLLBACK TO SAVEPOINT (写入 WAL)
    WHEN unique_violation THEN   --   如果无异常: RELEASE SAVEPOINT (写入 WAL)
      NULL;
  END;

每个 EXCEPTION 块至少产生 2 次额外 WAL 写入 (创建 + 释放/回滚)
```

**高频错误场景的灾难性影响**:
- "INSERT ... 遇到重复则忽略" 模式: 如果 90% 的插入触发 unique_violation，事务日志开销增加 3-5 倍
- 批量 UPSERT 操作: 每行一个 EXCEPTION 块 = 每行 2 次额外 WAL I/O
- 检测手段: `pg_stat_bgwriter` 中的 `buffers_checkpoint` 异常增长

**推荐替代方案**:
```sql
-- 反模式: 用 EXCEPTION 处理预期的重复
FOR rec IN SELECT * FROM staging LOOP
  BEGIN
    INSERT INTO target VALUES (rec.*);
  EXCEPTION WHEN unique_violation THEN
    NULL;  -- 忽略重复
  END;
END LOOP;

-- 正确做法: 用 INSERT ON CONFLICT 避免异常
INSERT INTO target SELECT * FROM staging
ON CONFLICT (id) DO NOTHING;  -- 零 savepoint 开销
```

### 8. 热路径中优先使用状态码检查

在高频执行的代码路径 (每秒数千次调用) 中，结构化异常处理的开销可能不可接受。应优先使用状态码检查模式:

```sql
-- 热路径反模式: 用异常控制流程
BEGIN
  SELECT balance INTO v_balance FROM accounts WHERE id = p_id;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    v_balance := 0;  -- 将"未找到"视为正常情况
END;

-- 热路径正确模式: 状态码检查
SELECT balance INTO v_balance FROM accounts WHERE id = p_id;
IF NOT FOUND THEN          -- 检查状态码, 零异常开销
  v_balance := 0;
END IF;
```

**引擎实现建议**:
- 在过程化语言中提供 `FOUND` / `ROW_COUNT` / `SQLSTATE` 等状态变量，让用户无需 EXCEPTION 块即可检查上一条语句的结果
- 对于预期会频繁发生的"非异常错误" (如 NOT FOUND、重复键)，提供非抛出的替代语法 (如 `INSERT ... ON CONFLICT`、`MERGE`、`GET DIAGNOSTICS`)
- 在性能文档中明确标注: EXCEPTION 块适用于真正的异常情况 (磁盘故障、约束违反等)，不应用于控制流

### 9. 深层嵌套异常处理器的 Savepoint 溢出

在递归调用或深层嵌套的过程中，每层 EXCEPTION 块都创建 savepoint，可能导致 savepoint 栈溢出:

```
-- 嵌套深度示例
PROCEDURE level_1()
  BEGIN                    -- savepoint 1
    CALL level_2();
  EXCEPTION ...
  END;

  PROCEDURE level_2()
    BEGIN                  -- savepoint 2
      CALL level_3();
    EXCEPTION ...
    END;

    PROCEDURE level_3()
      BEGIN                -- savepoint 3
        -- ... 以此类推
      EXCEPTION ...
      END;

-- 10 层嵌套 = 10 个并发活跃 savepoint
-- 每个 savepoint 占用: WAL 日志空间 + 内存中的事务快照
```

**实际风险**:
- PostgreSQL: 大量活跃 savepoint 增加 `PGPROC` 数组遍历开销，影响 MVCC 快照获取性能
- SQL Server: 嵌套 TRY/CATCH 本身不创建 savepoint，但手动 savepoint 过多会影响锁管理器
- 递归调用 + EXCEPTION 块: 递归深度 = savepoint 深度，可能耗尽事务日志空间

**引擎实现建议**:
- 设置 savepoint 嵌套深度上限 (如 64 层)，超过时报明确错误
- 优化 savepoint 实现: 对仅包含读操作的 EXCEPTION 块，可跳过 savepoint 创建 (因为读操作无需回滚)
- 提供 savepoint 使用统计 (如 `pg_stat_activity` 中的活跃 savepoint 计数)，帮助用户诊断性能问题
- 在递归过程中自动检测 EXCEPTION 块的存在，对超过阈值的嵌套深度发出警告

### 10. 测试错误处理的验证清单

```
引擎开发者在实现错误处理时应验证:

□ 基本功能
  □ 语法错误不被 TRY/CATCH / EXCEPTION 捕获 (编译时错误)
  □ 运行时错误被正确捕获
  □ 未处理的错误正确传播到客户端
  □ 错误码和错误消息正确设置
  □ GET DIAGNOSTICS 返回完整信息

□ 事务交互
  □ 错误后事务状态正确 (活跃/中止/可提交)
  □ ROLLBACK 后可以开始新事务
  □ Savepoint 在错误后正确工作
  □ 嵌套事务 + 错误的交互行为正确

□ 边界情况
  □ 错误处理代码本身出错的行为
  □ 堆栈溢出 (递归调用 + 错误处理)
  □ 内存不足时的错误处理
  □ 连接中断时的事务回滚
  □ 并发死锁检测的正确性

□ 性能
  □ EXCEPTION 块 / savepoint 的开销 (无错误时)
  □ 大量 handler 声明的编译性能
  □ 错误消息格式化的性能 (参数化 vs 字符串拼接)
```

## 总结: 迁移时的关键差异

```
从 → 到                       关键陷阱
──────────────────────────  ──────────────────────────────────────────────
Oracle → PostgreSQL          SQLCODE (负整数) → SQLSTATE (5 字符)
                              RAISE_APPLICATION_ERROR → RAISE EXCEPTION USING
                              PRAGMA EXCEPTION_INIT → 直接用条件名
                              WHEN OTHERS + SQLCODE → GET STACKED DIAGNOSTICS
                              异常块不回滚 → 隐式 savepoint 自动回滚

Oracle → MySQL               EXCEPTION 块 → DECLARE HANDLER
                              RAISE → SIGNAL SQLSTATE '45000'
                              SQLERRM → GET DIAGNOSTICS CONDITION 1

SQL Server → PostgreSQL       TRY/CATCH → BEGIN...EXCEPTION
                              ERROR_NUMBER() → SQLSTATE
                              ERROR_MESSAGE() → SQLERRM / MESSAGE_TEXT
                              XACT_ABORT → 默认就是全回滚
                              THROW → RAISE EXCEPTION
                              @@TRANCOUNT → 不需要 (自动管理)

SQL Server → MySQL            TRY/CATCH → DECLARE HANDLER
                              THROW → SIGNAL SQLSTATE
                              ERROR_NUMBER() → MYSQL_ERRNO
                              RAISERROR → SIGNAL

MySQL → PostgreSQL            DECLARE HANDLER → EXCEPTION 块
                              SIGNAL → RAISE EXCEPTION
                              GET DIAGNOSTICS → GET STACKED DIAGNOSTICS
                              CONTINUE handler → 在 EXCEPTION 中手动控制流

PostgreSQL → CockroachDB      大部分兼容, 但注意:
                              某些 PG 特定的 SQLSTATE 值可能不同
                              死锁处理需适配 CockroachDB 的重试协议

MySQL → TiDB                  DECLARE HANDLER 语法兼容
                              但存储过程功能可能不完整
                              错误码基本兼容 MySQL
```
