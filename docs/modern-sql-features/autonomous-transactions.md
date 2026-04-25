# 自治事务 (Autonomous Transactions)

外层事务回滚后，审计日志依然存在——这是自治事务最经典的应用场景。一个**自治事务 (Autonomous Transaction)** 是嵌套在外层（"主事务"）调用栈中、却拥有完全独立提交/回滚生命周期的子事务：它的提交不会影响主事务，主事务的回滚也不会撤销它已经提交的变更。这种"事务内部的独立事务"能力，让审计、错误日志、资源计费、配额扣减等"必须落盘"的副作用可以与主业务逻辑解耦，是 Oracle PL/SQL `PRAGMA AUTONOMOUS_TRANSACTION` 二十多年来在企业系统中无可替代的根本原因。

## 没有 SQL 标准

ISO/IEC 9075 SQL 标准从未定义"自治事务"概念。SQL:1999 引入的 SAVEPOINT 只能在同一事务上下文内部分回滚，无法绕过外层事务的回滚边界；SQL:2003 / 2011 增加的事务管理语句也只覆盖单事务模型。"自治事务"作为一个供应商扩展，最早出现在 **Oracle 8i (1999)** 引入的 `PRAGMA AUTONOMOUS_TRANSACTION`，此后被部分商业数据库以不同方式仿照（DB2 9.7、Firebird 2.5、HSQLDB 等），但绝大多数引擎（PostgreSQL、SQL Server、MySQL、SQLite、几乎所有 OLAP/MPP 引擎）都没有原生支持，需要通过远程连接回环 (loopback)、调度器、后台作业等方式模拟。

跨引擎的根本分歧在于**事务隔离哲学**：Oracle/DB2 阵营认为"日志、计费、配额"这类副作用应当**写穿事务边界**；PostgreSQL/SQL Server 阵营则坚持"一个连接、一个事务"的纯粹模型，要求开发者通过外部组件（队列、独立连接）实现等价语义。这种分歧直接影响应用架构选型。

## 支持矩阵（综合）

### 自治事务原生支持

| 引擎 | 原生自治事务 | 语法 | 关键字 | 版本 |
|------|------------|------|-------|------|
| Oracle | 是 | `PRAGMA AUTONOMOUS_TRANSACTION` | PRAGMA | 8i (1999) |
| Oracle (Pro*C) | 是 | `EXEC SQL SET TRANSACTION` (autonomous) | -- | 8i+ |
| OceanBase (Oracle 模式) | 是 | `PRAGMA AUTONOMOUS_TRANSACTION` | PRAGMA | 2.x+ |
| openGauss | 是 | `AUTONOMOUS TRANSACTION` 关键字 | DECLARE 块 | 2.0+ |
| GaussDB (华为) | 是 | `AUTONOMOUS TRANSACTION` | 类 PG/Oracle | GA |
| DB2 (LUW) | 是 | `AUTONOMOUS` 子句 | CREATE PROCEDURE | 9.7 (2009) |
| DB2 (z/OS) | 是 | `AUTONOMOUS` 子句 | 存储过程 | V10+ |
| DB2 (iSeries) | 是 | `AUTONOMOUS` 子句 | 存储过程 | 7.1+ |
| Firebird | 是 | `IN AUTONOMOUS TRANSACTION DO` | PSQL 块 | 2.5 (2010) |
| HSQLDB | 是 | `@AUTONOMOUS` 注解 | 存储过程 | 2.5+ |
| Informix | 部分 | 子事务 (subtransaction) | -- | 12.10+ |
| EnterpriseDB (EDB) | 是 | `PRAGMA AUTONOMOUS_TRANSACTION` | Oracle 兼容层 | 8.0+ |
| Dameng (达梦) | 是 | `PRAGMA AUTONOMOUS_TRANSACTION` | Oracle 兼容 | 7.x+ |
| Kingbase (人大金仓) | 是 | `PRAGMA AUTONOMOUS_TRANSACTION` | Oracle 兼容 | V8+ |
| ShenTong (神通) | 是 | `PRAGMA AUTONOMOUS_TRANSACTION` | Oracle 兼容 | V7+ |
| H2 | -- | -- | -- | 不支持 |
| Derby | -- | -- | -- | 不支持 |
| PostgreSQL | -- | -- | -- | 不支持原生 |
| SQL Server | -- | -- | -- | 不支持原生 |
| MySQL | -- | -- | -- | 不支持 |
| MariaDB | -- | -- | -- | 不支持 |
| SQLite | -- | -- | -- | 不支持 |
| TiDB | -- | -- | -- | 不支持 |
| CockroachDB | -- | -- | -- | 不支持 |
| YugabyteDB | -- | -- | -- | 不支持（继承 PG） |
| Greenplum | -- | -- | -- | 不支持（继承 PG） |
| Snowflake | -- | -- | -- | 不支持 |
| BigQuery | -- | -- | -- | 不支持 |
| Redshift | -- | -- | -- | 不支持 |
| ClickHouse | -- | -- | -- | 不支持（无事务） |
| DuckDB | -- | -- | -- | 不支持 |
| Trino | -- | -- | -- | 不支持 |
| Presto | -- | -- | -- | 不支持 |
| Spark SQL | -- | -- | -- | 不支持 |
| Hive | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | 不支持 |
| Databricks | -- | -- | -- | 不支持 |
| Teradata | -- | -- | -- | 不支持 |
| SingleStore | -- | -- | -- | 不支持 |
| Vertica | -- | -- | -- | 不支持 |
| Impala | -- | -- | -- | 不支持 |
| StarRocks | -- | -- | -- | 不支持 |
| Doris | -- | -- | -- | 不支持 |
| MonetDB | -- | -- | -- | 不支持 |
| CrateDB | -- | -- | -- | 不支持 |
| TimescaleDB | -- | -- | -- | 不支持（继承 PG） |
| QuestDB | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | 不支持 |
| SAP HANA | -- | -- | -- | 不支持原生 |
| Amazon Athena | -- | -- | -- | 不支持 |
| Azure Synapse | -- | -- | -- | 不支持 |
| Google Spanner | -- | -- | -- | 不支持 |
| Materialize | -- | -- | -- | 不支持 |
| RisingWave | -- | -- | -- | 不支持 |
| InfluxDB (SQL) | -- | -- | -- | 不支持 |
| DatabendDB | -- | -- | -- | 不支持 |
| Yellowbrick | -- | -- | -- | 不支持 |
| Firebolt | -- | -- | -- | 不支持 |
| AlloyDB | -- | -- | -- | 不支持（继承 PG） |
| Neon | -- | -- | -- | 不支持（继承 PG） |
| PolarDB (PG) | -- | -- | -- | 不支持（继承 PG） |
| PolarDB (Oracle 兼容) | 是 | `PRAGMA AUTONOMOUS_TRANSACTION` | Oracle 兼容 | GA |
| Aurora (PG) | -- | -- | -- | 不支持（继承 PG） |
| Aurora (MySQL) | -- | -- | -- | 不支持 |

> 统计：约 14 个引擎提供原生自治事务支持（绝大多数集中在 Oracle 兼容生态：Oracle 自身 + DB2 + Oracle 兼容产品如 EDB/达梦/金仓/OceanBase/openGauss/PolarDB Oracle 模式），约 40+ 个引擎完全不支持，需要通过仿真方案实现。
>
> Oracle 8i 在 1999 年引入 `PRAGMA AUTONOMOUS_TRANSACTION` 时，是首个将"自治事务"作为一等公民语言特性的工业数据库。此后 25 年间，没有任何 SQL 标准化组织接受这个概念，但商业 PL/SQL 生态（DB2 PL/SQL、openGauss PL/pgSQL 扩展、Oracle 兼容层产品）普遍跟进。

### 仿真方案（无原生支持的引擎）

| 引擎 | 仿真方案 | 复杂度 | 性能开销 | 备注 |
|------|---------|-------|---------|------|
| PostgreSQL | dblink 回环连接 | 中 | 高（每次新建连接） | 最常见方案 |
| PostgreSQL | pg_background 扩展 | 中 | 中 | 需安装第三方扩展 |
| PostgreSQL | dblink_connect 持久连接 | 中 | 中 | 减少连接开销 |
| PostgreSQL | LISTEN/NOTIFY + 后台 worker | 高 | 低 | 异步，不能立即查询结果 |
| PostgreSQL | 外部消息队列 + 消费者 | 高 | 低 | 完全异步 |
| SQL Server | sp_OACreate + ADO 回环 | 高 | 高 | 已不推荐 |
| SQL Server | Loopback Linked Server | 中 | 高 | 需 MSDTC |
| SQL Server | Service Broker 队列 | 高 | 低 | 异步消息驱动 |
| SQL Server | SQLCLR (Context Connection=false) | 高 | 中 | 需 CLR 程序集 |
| SQL Server | SQL Agent Job + sp_start_job | 中 | 高 | 异步，不能立即返回结果 |
| MySQL | 独立连接 + 应用层协调 | 高 | 中 | 数据库内部无解 |
| MySQL | Event Scheduler + 标记表 | 中 | 中 | 异步轮询 |
| SQLite | 独立连接 (ATTACH) | 中 | 低 | 需注意锁竞争 |
| Snowflake | 独立 Session 调用 | 高 | 高 | 通过外部协调 |
| BigQuery | 独立查询作业 | 高 | 高 | 异步 |
| Trino/Presto | 不支持事务嵌套 | -- | -- | 单语句即事务 |
| ClickHouse | INSERT 自带原子性 | -- | -- | 无事务概念 |
| TiDB | 独立 Session（应用层） | 高 | 中 | 跨 PD 协调 |
| CockroachDB | 独立 Session | 中 | 中 | -- |

### 与相关特性的关系

| 特性 | 与自治事务的差异 |
|------|---------------|
| SAVEPOINT (SQL:1999) | 仅在同一事务内部回滚，回滚整个外层事务时仍会被撤销 |
| 嵌套事务 (Nested Transaction) | 子事务提交需依赖父事务最终提交（多数实现） |
| BEGIN ATOMIC (SQL/PSM) | 块级原子性，但不独立于外层 |
| 后台作业 (DBMS_SCHEDULER, SQL Agent) | 异步，无法在主事务中等待结果 |
| 外部消息队列 | 真正的异步解耦，但增加架构复杂度 |
| 远程过程调用 (DBLINK) | 跨连接，自然独立事务，是仿真自治事务的常用手段 |

## 经典应用场景

自治事务的核心价值在于**让某些副作用绕过外层事务的回滚**。最典型的四类场景：

### 1. 审计日志（最常见）

```sql
-- Oracle 经典模式：即使主业务回滚，审计记录依然保留
CREATE OR REPLACE PROCEDURE log_audit(
    p_user VARCHAR2,
    p_action VARCHAR2,
    p_detail VARCHAR2
) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO audit_log(ts, username, action, detail)
    VALUES (SYSTIMESTAMP, p_user, p_action, p_detail);
    COMMIT;  -- 必须 COMMIT/ROLLBACK 才能退出自治事务
END;
/

-- 调用方：业务回滚不会撤销审计
BEGIN
    log_audit('alice', 'TRANSFER', 'amount=1000');
    UPDATE accounts SET balance = balance - 1000 WHERE id = 1;
    UPDATE accounts SET balance = balance + 1000 WHERE id = 2;
    -- 检测到异常
    RAISE_APPLICATION_ERROR(-20001, 'Fraud detected');
EXCEPTION
    WHEN OTHERS THEN
        log_audit('alice', 'TRANSFER_FAILED', SQLERRM);
        ROLLBACK;  -- 主业务回滚
        -- 但两条 audit_log 都保留下来（自治事务已提交）
        RAISE;
END;
/
```

### 2. 错误日志

```sql
-- 异常处理中记录错误，确保错误信息不丢失
CREATE OR REPLACE PROCEDURE log_error(
    p_module VARCHAR2,
    p_errcode NUMBER,
    p_errmsg VARCHAR2
) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO error_log(ts, module, errcode, errmsg, stack)
    VALUES (SYSTIMESTAMP, p_module, p_errcode, p_errmsg,
            DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    COMMIT;
END;
/

CREATE OR REPLACE PROCEDURE process_order(p_order_id NUMBER) IS
BEGIN
    -- 业务逻辑
    UPDATE orders SET status = 'PROCESSING' WHERE id = p_order_id;
    -- ...
EXCEPTION
    WHEN OTHERS THEN
        log_error('process_order', SQLCODE, SQLERRM);
        ROLLBACK;
        RAISE;
END;
/
```

### 3. 计数器/序列号管理（不依赖序列对象）

```sql
-- 在没有原生 SEQUENCE 的场景，用自治事务保证 ID 单调递增
CREATE OR REPLACE FUNCTION next_invoice_no
RETURN NUMBER IS
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_next NUMBER;
BEGIN
    UPDATE counter SET val = val + 1 WHERE name = 'INVOICE_NO'
    RETURNING val INTO v_next;
    COMMIT;
    RETURN v_next;
END;
/

-- 即使调用方回滚，发出的 invoice_no 不会被回收（避免重复使用）
```

### 4. 资源计费 / 配额扣减

```sql
-- 计费记录必须落盘：即使业务因后续步骤失败回滚，已消耗的资源仍要计费
CREATE OR REPLACE PROCEDURE charge_quota(
    p_user_id NUMBER,
    p_amount NUMBER
) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    UPDATE user_quota SET used = used + p_amount WHERE user_id = p_user_id;
    INSERT INTO quota_history(user_id, amount, ts)
    VALUES (p_user_id, p_amount, SYSTIMESTAMP);
    COMMIT;
END;
/
```

## 各引擎语法详解

### Oracle (PRAGMA AUTONOMOUS_TRANSACTION 鼻祖)

Oracle 8i (1999) 引入 `PRAGMA AUTONOMOUS_TRANSACTION` 至今 25 年未变，是其他引擎仿照的"标准实现"。

```sql
-- 自治事务的核心结构
CREATE OR REPLACE PROCEDURE proc_name IS
    PRAGMA AUTONOMOUS_TRANSACTION;  -- 必须在 DECLARE 段
BEGIN
    -- 执行 DML
    INSERT INTO log VALUES (...);
    -- 必须显式 COMMIT 或 ROLLBACK，否则报错 ORA-06519
    COMMIT;
END;
/

-- 适用对象：
-- 1. 顶层匿名 PL/SQL 块
-- 2. 存储过程 / 函数 (Stand-alone)
-- 3. 包 (Package) 中的过程/函数
-- 4. 数据库触发器 (Trigger)
-- 5. 对象类型 (Object Type) 的方法
-- 不适用：嵌入到 PL/SQL 块内部声明（必须在最外层 DECLARE）

-- 触发器示例：审计 DML 操作
CREATE OR REPLACE TRIGGER audit_emp_changes
AFTER INSERT OR UPDATE OR DELETE ON employees
FOR EACH ROW
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_action VARCHAR2(10);
BEGIN
    IF INSERTING THEN v_action := 'INSERT';
    ELSIF UPDATING THEN v_action := 'UPDATE';
    ELSE v_action := 'DELETE';
    END IF;

    INSERT INTO emp_audit(ts, action, emp_id, who)
    VALUES (SYSTIMESTAMP, v_action,
            COALESCE(:NEW.emp_id, :OLD.emp_id),
            USER);
    COMMIT;
END;
/

-- 包内自治事务
CREATE OR REPLACE PACKAGE BODY logger IS
    PROCEDURE info(p_msg VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO log(level, msg, ts) VALUES ('INFO', p_msg, SYSTIMESTAMP);
        COMMIT;
    END;

    PROCEDURE error(p_msg VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO log(level, msg, ts) VALUES ('ERROR', p_msg, SYSTIMESTAMP);
        COMMIT;
    END;
END;
/

-- 关键限制和规则：
-- 1. 必须在最外层 DECLARE 段声明 PRAGMA
-- 2. 进入自治事务后，主事务被"挂起"
-- 3. 退出前必须 COMMIT 或 ROLLBACK，否则 ORA-06519: active autonomous transaction detected and rolled back
-- 4. 自治事务可以再嵌套自治事务（最大深度受 INIT.ORA 参数 TRANSACTIONS 限制）
-- 5. 自治事务无法看到主事务未提交的修改（独立 MVCC 视图）
-- 6. 主事务也看不到自治事务未提交的修改（直到自治事务 COMMIT）
-- 7. 自治事务和主事务之间可能死锁（互相等待对方持有的行锁）
```

#### Oracle 自治事务的可见性

```sql
-- 主事务的修改对自治事务不可见（独立 SCN 起点）
DECLARE
    v_count NUMBER;
    PROCEDURE check_count IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM t;
        DBMS_OUTPUT.PUT_LINE('Autonomous sees: ' || v_count);
        COMMIT;
    END;
BEGIN
    SELECT COUNT(*) INTO v_count FROM t;
    DBMS_OUTPUT.PUT_LINE('Main before insert: ' || v_count);  -- 假设输出 5

    INSERT INTO t VALUES (...);  -- 主事务插入但未提交
    SELECT COUNT(*) INTO v_count FROM t;
    DBMS_OUTPUT.PUT_LINE('Main after insert: ' || v_count);   -- 输出 6

    check_count();  -- 自治事务看不到未提交的插入，输出 5

    COMMIT;
    check_count();  -- 现在主事务已提交，输出 6
END;
/
```

#### Oracle 自治事务死锁

```sql
-- 经典死锁场景：自治事务尝试更新主事务已锁定的行
DECLARE
    PROCEDURE update_in_autonomous IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        UPDATE accounts SET balance = balance + 10 WHERE id = 1;  -- 等待
        COMMIT;
    END;
BEGIN
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;  -- 主事务持有行锁
    update_in_autonomous();  -- 死锁：自治事务等待主事务，主事务等待自治事务返回
END;
/
-- 报错：ORA-00060: deadlock detected while waiting for resource
```

### DB2 (PL/SQL AUTONOMOUS 子句)

DB2 9.7 (2009 年发布) 引入 Oracle 兼容性时加入了自治事务支持。语法上更接近 SQL/PSM，使用过程级别的 `AUTONOMOUS` 子句。

```sql
-- DB2 SQL PL 自治事务语法
CREATE PROCEDURE log_audit(
    IN p_user VARCHAR(64),
    IN p_action VARCHAR(64),
    IN p_detail VARCHAR(1024)
)
LANGUAGE SQL
AUTONOMOUS  -- 关键字置于过程定义级别
BEGIN
    INSERT INTO audit_log(ts, username, action, detail)
    VALUES (CURRENT TIMESTAMP, p_user, p_action, p_detail);
    -- DB2 不要求显式 COMMIT，过程退出时自动提交自治事务
END;

-- 调用方
BEGIN ATOMIC
    CALL log_audit('alice', 'TRANSFER', 'amount=1000');
    UPDATE accounts SET balance = balance - 1000 WHERE id = 1;
    -- 异常发生
    SIGNAL SQLSTATE '70001' SET MESSAGE_TEXT = 'Fraud detected';
END;
-- audit_log 保留，accounts 回滚

-- DB2 PL/SQL 兼容模式（启用 DB2_COMPATIBILITY_VECTOR=ORA 后）
CREATE OR REPLACE PROCEDURE log_audit(
    p_user VARCHAR2,
    p_action VARCHAR2
) IS
    PRAGMA AUTONOMOUS_TRANSACTION;  -- DB2 也接受 Oracle 风格的 PRAGMA
BEGIN
    INSERT INTO audit_log VALUES (...);
    COMMIT;
END;
/

-- 关键限制：
-- 1. AUTONOMOUS 子句仅适用于 SQL PL 过程，不适用于函数
-- 2. 过程必须独立模块，不能嵌入到表达式
-- 3. 与触发器配合使用时需谨慎（嵌套深度限制）
```

### OceanBase (Oracle 模式 PRAGMA 完全兼容)

OceanBase 在 Oracle 模式下完整支持 `PRAGMA AUTONOMOUS_TRANSACTION`，是从 2.x 版本开始作为 Oracle 兼容性的核心特性提供。

```sql
-- 使用方式与 Oracle 完全一致
CREATE OR REPLACE PROCEDURE ob_log_event(
    p_event VARCHAR2,
    p_payload VARCHAR2
) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO event_log(ts, event, payload, server_id)
    VALUES (SYSTIMESTAMP, p_event, p_payload, OB_SERVER_ID());
    COMMIT;
END;
/

-- OceanBase 特有：分布式自治事务
-- 自治事务可能涉及多个 OBServer，内部使用 2PC 协调
-- 跨 zone/region 的自治事务延迟显著高于 Oracle 单机

-- MySQL 模式下不支持 PRAGMA 语法
-- 需要通过应用层独立连接实现
```

### openGauss / GaussDB (华为)

openGauss 继承了 PostgreSQL 的 PL/pgSQL，并在此基础上扩展了 Oracle 风格的自治事务关键字。

```sql
-- openGauss 自治事务语法（PL/pgSQL 扩展）
CREATE OR REPLACE PROCEDURE log_action(
    p_action TEXT,
    p_user TEXT
) AS
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO audit_log(ts, action, "user")
    VALUES (NOW(), p_action, p_user);
    COMMIT;
END;
/

-- 或使用 AUTONOMOUS_TRANSACTION 块语法（不同版本可能略有差异）
CREATE OR REPLACE FUNCTION fn_count_and_log()
RETURNS INTEGER
AS $$
DECLARE
    v_count INTEGER;
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    SELECT COUNT(*) INTO v_count FROM users;
    INSERT INTO stats_log(metric, val, ts)
    VALUES ('user_count', v_count, NOW());
    COMMIT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- openGauss 实现细节：
-- 1. 通过派生独立 backend 进程执行自治事务
-- 2. 与主事务进程通过共享内存通信
-- 3. 性能开销略高于 Oracle (Oracle 是同进程切换上下文)
-- 4. 不支持自治事务读取主事务未提交的修改（与 Oracle 一致）
```

### Firebird (IN AUTONOMOUS TRANSACTION DO)

Firebird 2.5 (2010 年发布) 引入自治事务，语法是块级 `IN AUTONOMOUS TRANSACTION DO ... END` 结构，而非过程级别的 PRAGMA。

```sql
-- Firebird PSQL 自治事务
SET TERM ^ ;

CREATE OR ALTER PROCEDURE log_audit(
    p_user VARCHAR(64),
    p_action VARCHAR(64)
)
AS
BEGIN
    -- 块级自治事务，更接近 PostgreSQL pg_background 模型
    IN AUTONOMOUS TRANSACTION DO
    BEGIN
        INSERT INTO audit_log(ts, username, action)
        VALUES (CURRENT_TIMESTAMP, :p_user, :p_action);
    END
    -- 块结束自动提交，无需显式 COMMIT
END^

SET TERM ; ^

-- 异常处理示例
SET TERM ^ ;
CREATE OR ALTER PROCEDURE safe_transfer(
    from_id INTEGER,
    to_id INTEGER,
    amount NUMERIC(10,2)
)
AS
BEGIN
    UPDATE accounts SET balance = balance - :amount WHERE id = :from_id;
    UPDATE accounts SET balance = balance + :amount WHERE id = :to_id;

    WHEN ANY DO
    BEGIN
        IN AUTONOMOUS TRANSACTION DO
        BEGIN
            INSERT INTO error_log(ts, src, dst, amt, errmsg)
            VALUES (CURRENT_TIMESTAMP, :from_id, :to_id, :amount,
                    'Transfer failed');
        END
        EXCEPTION;  -- 重新抛出
    END
END^
SET TERM ; ^

-- Firebird 自治事务特点：
-- 1. 块级而非过程级，可在过程内部多次使用
-- 2. 自动提交（无需显式 COMMIT）
-- 3. 自治事务内部可以再嵌套自治事务
-- 4. 异常处理 (WHEN ANY DO) 中常见
```

### HSQLDB (@AUTONOMOUS 注解)

HSQLDB 2.5+ 通过过程注解 `@AUTONOMOUS` 提供自治事务能力，语法借鉴了 Java EJB 注解风格。

```sql
-- HSQLDB 自治事务示例
CREATE PROCEDURE log_audit(
    IN p_user VARCHAR(64),
    IN p_action VARCHAR(64)
)
MODIFIES SQL DATA
AUTONOMOUS  -- HSQLDB 关键字置于 SQL 安全级别之后
BEGIN ATOMIC
    INSERT INTO audit_log(ts, username, action)
    VALUES (CURRENT_TIMESTAMP, p_user, p_action);
END;

-- 调用方
START TRANSACTION;
CALL log_audit('alice', 'LOGIN');
INSERT INTO orders VALUES (...);
ROLLBACK;
-- audit_log 中的记录保留，orders 中的插入回滚
```

### EnterpriseDB (EDB) / Dameng / Kingbase

国产数据库与 EnterpriseDB 都通过 Oracle 兼容层提供 `PRAGMA AUTONOMOUS_TRANSACTION` 支持，语法与 Oracle 完全一致。

```sql
-- 达梦 DM8 自治事务
CREATE OR REPLACE PROCEDURE dm_log_event(
    p_event VARCHAR2,
    p_user VARCHAR2
) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO event_log(ts, event, "user")
    VALUES (SYSDATE, p_event, p_user);
    COMMIT;
END;
/

-- 人大金仓 KingbaseES 自治事务
CREATE OR REPLACE PROCEDURE ks_log_audit(
    p_action VARCHAR2,
    p_user VARCHAR2
) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO audit_log(ts, action, "user")
    VALUES (CURRENT_TIMESTAMP, p_action, p_user);
    COMMIT;
END;
/
```

## PostgreSQL 仿真方案深度解析

PostgreSQL 至今没有原生自治事务支持。社区从 9.x 版本就在讨论 `PRAGMA AUTONOMOUS_TRANSACTION`，但因事务模型设计理念不同，PG 核心团队倾向于"应用层独立连接"或"扩展实现"。截至 PG 17 仍未合并到主线。

### 方案 1: dblink 回环连接（最常见）

通过 `dblink` 扩展建立到本机自身数据库的 TCP 连接，每个 dblink 调用是一个完全独立的会话和事务。

```sql
-- 安装 dblink 扩展
CREATE EXTENSION IF NOT EXISTS dblink;

-- 仿真自治事务：审计日志
CREATE OR REPLACE FUNCTION log_audit_via_dblink(
    p_user TEXT,
    p_action TEXT,
    p_detail TEXT
) RETURNS VOID AS $$
DECLARE
    v_conn_str TEXT := 'host=localhost port=5432 dbname=mydb user=audit_user password=xxx';
BEGIN
    PERFORM dblink_exec(v_conn_str,
        format('INSERT INTO audit_log(ts, username, action, detail)
                VALUES (NOW(), %L, %L, %L)',
                p_user, p_action, p_detail));
END;
$$ LANGUAGE plpgsql;

-- 使用示例
BEGIN;
SELECT log_audit_via_dblink('alice', 'TRANSFER', 'amount=1000');
UPDATE accounts SET balance = balance - 1000 WHERE id = 1;
-- 业务异常
ROLLBACK;
-- audit_log 中记录保留（因为是另一个连接的独立事务）

-- 性能优化：使用持久连接
SELECT dblink_connect('audit_conn',
    'host=localhost port=5432 dbname=mydb user=audit_user');

CREATE OR REPLACE FUNCTION log_audit_persistent(
    p_action TEXT
) RETURNS VOID AS $$
BEGIN
    PERFORM dblink_exec('audit_conn',
        format('INSERT INTO audit_log(ts, action) VALUES (NOW(), %L)',
                p_action));
END;
$$ LANGUAGE plpgsql;

-- 使用完后断开
SELECT dblink_disconnect('audit_conn');
```

### 方案 2: pg_background 扩展

`pg_background` 是社区维护的 PostgreSQL 扩展（最初由 EnterpriseDB 开发），通过派生后台 worker 进程执行 SQL，自然形成独立事务上下文。

```sql
CREATE EXTENSION IF NOT EXISTS pg_background;

-- 异步执行（返回作业 ID，供后续查询结果）
SELECT pg_background_launch(
    'INSERT INTO audit_log(ts, username, action)
     VALUES (NOW(), ''alice'', ''TRANSFER'')'
) AS job_pid;

-- 同步等待（需要时获取结果）
SELECT * FROM pg_background_result(<job_pid>) AS r(result TEXT);

-- 一步完成（封装常用模式）
CREATE OR REPLACE FUNCTION log_audit_bg(
    p_action TEXT,
    p_user TEXT
) RETURNS VOID AS $$
DECLARE
    v_pid INTEGER;
BEGIN
    SELECT pg_background_launch(
        format('INSERT INTO audit_log(ts, action, "user")
                VALUES (NOW(), %L, %L)', p_action, p_user)
    ) INTO v_pid;
    -- 不等待结果，让它异步完成
END;
$$ LANGUAGE plpgsql;

-- pg_background 限制：
-- 1. 无法访问主会话的临时表
-- 2. 无法继承当前的 search_path / role
-- 3. 后台 worker 数量受 max_worker_processes 限制
-- 4. 不在 PostgreSQL 主线，需要单独安装
```

### 方案 3: LISTEN/NOTIFY + 后台 worker

异步消息机制，主事务发出通知，后台 worker 监听并执行。完全解耦，但无法在主事务中等待结果。

```sql
-- 主事务：发出审计通知
CREATE OR REPLACE FUNCTION log_audit_async(
    p_action TEXT,
    p_user TEXT
) RETURNS VOID AS $$
BEGIN
    PERFORM pg_notify('audit_channel',
        format('{"ts": "%s", "action": "%s", "user": "%s"}',
                NOW()::TEXT, p_action, p_user));
END;
$$ LANGUAGE plpgsql;

-- 后台 worker（独立 Python/Node.js 进程，或 PG background worker）
-- 伪代码：
-- conn = psycopg2.connect(...)
-- conn.execute("LISTEN audit_channel")
-- while True:
--     conn.poll()
--     while conn.notifies:
--         notify = conn.notifies.pop()
--         data = json.loads(notify.payload)
--         conn2 = psycopg2.connect(...)  # 独立连接
--         conn2.execute("INSERT INTO audit_log ...", data)
--         conn2.commit()

-- 注意：pg_notify 的负载有 8KB 限制
-- 大数据量需配合表 + 触发器
```

### 方案 4: 独立连接（应用层）

最干净的方案：应用层维护两个独立的 DB 连接，一个用于主业务，一个专门用于审计/日志。

```python
# Python 示例
import psycopg2

main_conn = psycopg2.connect("dbname=mydb user=app")
audit_conn = psycopg2.connect("dbname=mydb user=audit")

try:
    # 审计立即提交（独立事务）
    with audit_conn.cursor() as cur:
        cur.execute("INSERT INTO audit_log VALUES (NOW(), %s, %s)",
                    ('alice', 'TRANSFER'))
    audit_conn.commit()  # 立即提交

    # 主事务可能失败
    with main_conn.cursor() as cur:
        cur.execute("UPDATE accounts SET balance = balance - 1000 WHERE id = 1")
        cur.execute("UPDATE accounts SET balance = balance + 1000 WHERE id = 2")
        if some_business_rule_failed:
            raise Exception("Validation failed")
    main_conn.commit()
except Exception:
    main_conn.rollback()
    # audit_log 已经在独立连接里提交，不会回滚
```

### SAVEPOINT 不等于自治事务

PostgreSQL 用户常误以为 SAVEPOINT + ROLLBACK 可以模拟自治事务，但语义完全不同：

```sql
-- 错误理解：以为 SAVEPOINT 能让审计独立
BEGIN;
INSERT INTO audit_log VALUES (NOW(), 'alice', 'TRANSFER');
SAVEPOINT after_audit;
UPDATE accounts SET balance = balance - 1000 WHERE id = 1;
ROLLBACK;  -- 整个事务回滚，audit_log 也被撤销！
-- SAVEPOINT 只能 ROLLBACK TO，不能让某个 INSERT "提前提交"

-- 正确语义：SAVEPOINT 仅用于"部分回滚"
BEGIN;
SAVEPOINT before_step1;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
SAVEPOINT before_step2;
UPDATE accounts SET balance = balance - 200 WHERE id = 1;
ROLLBACK TO SAVEPOINT before_step2;  -- 只撤销 step2，step1 仍在
COMMIT;  -- 最终保留 step1 的修改

-- SAVEPOINT 与 AUTONOMOUS 的本质区别：
-- - SAVEPOINT 是同一事务内的部分回滚点（取决于外层 COMMIT）
-- - AUTONOMOUS 是独立事务（提交不依赖外层）
```

## SQL Server 仿真方案

SQL Server 同样没有原生自治事务，仿真方案有四类。

### 方案 1: Loopback Linked Server

```sql
-- 创建到自身的 Linked Server
EXEC sp_addlinkedserver
    @server = 'LOOPBACK',
    @srvproduct = '',
    @provider = 'SQLNCLI',
    @datasrc = 'localhost\SQLEXPRESS';

EXEC sp_serveroption @server = 'LOOPBACK',
    @optname = 'remote proc transaction promotion', @optvalue = 'false';
-- 关键：禁用事务提升，否则 Linked Server 调用会被合并到当前事务

-- 使用 Linked Server 实现自治事务
CREATE OR ALTER PROCEDURE dbo.log_audit
    @action NVARCHAR(100),
    @user NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    -- 通过 Loopback Linked Server 的远程调用，自动是独立事务
    EXEC LOOPBACK.MyDB.dbo.do_log_audit @action, @user;
END;

-- 实际写入日志的过程
CREATE OR ALTER PROCEDURE dbo.do_log_audit
    @action NVARCHAR(100),
    @user NVARCHAR(100)
AS
BEGIN
    INSERT INTO audit_log(ts, action, [user])
    VALUES (SYSDATETIME(), @action, @user);
END;

-- 使用示例
BEGIN TRANSACTION;
EXEC dbo.log_audit @action = 'TRANSFER', @user = 'alice';
UPDATE accounts SET balance = balance - 1000 WHERE id = 1;
ROLLBACK;
-- audit_log 中的记录保留

-- 限制：
-- 1. Linked Server 的远程调用开销显著（建立独立会话）
-- 2. 需要禁用事务提升才能避免合并到 MSDTC
-- 3. 高并发下连接数膨胀
```

### 方案 2: SQLCLR (Context Connection=false)

```csharp
// SQLCLR 程序集
[Microsoft.SqlServer.Server.SqlProcedure]
public static void LogAudit(string action, string user)
{
    // 使用 Context Connection=false 强制独立连接
    using (var conn = new SqlConnection(
        "Server=localhost;Database=MyDB;Integrated Security=true;Context Connection=false"))
    {
        conn.Open();
        using (var cmd = new SqlCommand(
            "INSERT INTO audit_log(ts, action, [user]) VALUES (SYSDATETIME(), @action, @user)",
            conn))
        {
            cmd.Parameters.AddWithValue("@action", action);
            cmd.Parameters.AddWithValue("@user", user);
            cmd.ExecuteNonQuery();
        }
    }
}
```

```sql
-- 注册到 SQL Server
CREATE PROCEDURE dbo.log_audit_clr
    @action NVARCHAR(100),
    @user NVARCHAR(100)
AS EXTERNAL NAME MyAssembly.[Namespace.Class].LogAudit;
GO

-- 使用
BEGIN TRANSACTION;
EXEC dbo.log_audit_clr @action = 'TRANSFER', @user = 'alice';
ROLLBACK;
-- audit_log 保留
```

### 方案 3: Service Broker 队列

异步消息驱动，最复杂但最可扩展。

```sql
-- 创建消息类型、契约、队列、服务
CREATE MESSAGE TYPE AuditMessage VALIDATION = WELL_FORMED_XML;
CREATE CONTRACT AuditContract (AuditMessage SENT BY ANY);

CREATE QUEUE AuditQueue;
CREATE SERVICE AuditService ON QUEUE AuditQueue (AuditContract);

-- 主事务发送消息
BEGIN TRANSACTION;
DECLARE @msg XML = '<audit><action>TRANSFER</action><user>alice</user></audit>';
DECLARE @handle UNIQUEIDENTIFIER;
BEGIN DIALOG @handle FROM SERVICE AuditService TO SERVICE 'AuditService';
SEND ON CONVERSATION @handle MESSAGE TYPE AuditMessage (@msg);
ROLLBACK;
-- 消息发送会被回滚！Service Broker 默认在事务内

-- 修复：使用 SAVE TRANSACTION 或独立提交
-- 真正的自治效果需要队列 activator 在另一个事务中处理
```

### 方案 4: SQL Agent Job (异步)

```sql
-- 创建只执行一次的 Job
EXEC msdb.dbo.sp_add_job @job_name = N'log_audit_temp_job';
EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'log_audit_temp_job',
    @step_name = N'insert audit',
    @command = N'INSERT INTO MyDB.dbo.audit_log VALUES (SYSDATETIME(), ''alice'', ''TRANSFER'')';
EXEC msdb.dbo.sp_add_jobserver @job_name = N'log_audit_temp_job';

-- 异步启动
EXEC msdb.dbo.sp_start_job @job_name = N'log_audit_temp_job';

-- 限制：完全异步，无法在主事务中等待结果
-- 不适合需要立即返回值的场景
```

## MySQL 仿真方案

MySQL 完全没有自治事务，且没有官方扩展。常见做法：

### 方案 1: 应用层独立连接

```python
# Python 应用层实现
import mysql.connector

main_conn = mysql.connector.connect(host='localhost', database='mydb')
audit_conn = mysql.connector.connect(host='localhost', database='mydb',
                                      autocommit=True)

main_cur = main_conn.cursor()
audit_cur = audit_conn.cursor()

try:
    # 审计立即提交（autocommit=True）
    audit_cur.execute("INSERT INTO audit_log VALUES (NOW(), %s)", ('alice',))

    # 主事务
    main_conn.start_transaction()
    main_cur.execute("UPDATE accounts SET balance = balance - 1000 WHERE id = 1")
    if validation_failed:
        raise Exception("Validation failed")
    main_conn.commit()
except Exception:
    main_conn.rollback()
    # audit_log 不受影响
```

### 方案 2: Event Scheduler + 标记表

```sql
-- 创建标记表，主事务向标记表插入"待处理"记录
CREATE TABLE audit_pending (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    ts DATETIME DEFAULT CURRENT_TIMESTAMP,
    user_id VARCHAR(64),
    action VARCHAR(64),
    payload TEXT,
    processed TINYINT DEFAULT 0
);

-- Event 定时处理
DELIMITER $$
CREATE EVENT process_audit_pending
ON SCHEDULE EVERY 1 SECOND
DO BEGIN
    -- Event 在独立事务中执行
    INSERT INTO audit_log
    SELECT id, ts, user_id, action, payload FROM audit_pending
    WHERE processed = 0;

    UPDATE audit_pending SET processed = 1 WHERE processed = 0;
END$$
DELIMITER ;

-- 主事务向 pending 表插入
BEGIN;
INSERT INTO audit_pending(user_id, action) VALUES ('alice', 'TRANSFER');
UPDATE accounts SET balance = balance - 1000 WHERE id = 1;
ROLLBACK;
-- 注意：pending 表的插入也被回滚！
-- 这种方案仅适用于"主事务成功后异步处理"，无法实现"主事务回滚但日志保留"
```

### 方案 3: 跨连接 Stored Procedure（不可行）

MySQL 的存储过程总是在调用者的事务上下文中执行，无法在过程内部建立独立事务。即使过程内部 `COMMIT`/`ROLLBACK`，也是对外层事务的操作，而非建立子事务。

```sql
DELIMITER $$
CREATE PROCEDURE log_audit(p_action VARCHAR(64))
BEGIN
    INSERT INTO audit_log(ts, action) VALUES (NOW(), p_action);
    COMMIT;  -- 这会提交外层事务！不是独立事务
END$$
DELIMITER ;

BEGIN;
INSERT INTO orders VALUES (...);
CALL log_audit('TRANSFER');  -- COMMIT 会把 orders 也提交
-- 后续 ROLLBACK 无效，orders 已经被 procedure 内部 COMMIT
ROLLBACK;
```

## SQLite 仿真方案

SQLite 是文件级数据库，单连接单事务，但可以通过多个连接（同一进程或不同进程）实现自治事务效果。

```python
import sqlite3

# 主连接
main_conn = sqlite3.connect('mydb.sqlite')
# 独立连接用于审计
audit_conn = sqlite3.connect('mydb.sqlite', isolation_level=None)  # autocommit

main_cur = main_conn.cursor()
audit_cur = audit_conn.cursor()

try:
    # 审计立即提交
    audit_cur.execute("INSERT INTO audit_log VALUES (datetime('now'), 'alice', 'TRANSFER')")
    # autocommit 模式自动提交

    # 主事务
    main_cur.execute("BEGIN")
    main_cur.execute("UPDATE accounts SET balance = balance - 1000 WHERE id = 1")
    if validation_failed:
        raise Exception("validation failed")
    main_conn.commit()
except Exception:
    main_conn.rollback()

# 注意：SQLite 的 WAL 模式下，多连接并发更友好
# 默认 rollback journal 模式可能因写锁导致竞争
```

## TiDB / OceanBase MySQL 模式 / CockroachDB

兼容 MySQL/PostgreSQL 协议的分布式数据库继承了原生不支持自治事务的限制：

```sql
-- TiDB: 与 MySQL 一致，无原生支持
-- 推荐：应用层独立连接，每个连接是独立 SQL session

-- OceanBase MySQL 模式: 仅 Oracle 模式支持 PRAGMA
-- MySQL 模式下需通过应用层独立连接

-- CockroachDB: 完全不支持嵌套事务概念
-- 应用层连接池中维护单独连接专门用于"自治"操作
```

## 自治事务的实现原理

### Oracle: 独立 transaction context (TX 槽)

Oracle 在共享池中维护 transaction context 数组，每个事务占用一个 TX 槽。进入自治事务时：

```
1. 当前会话的活跃 TX 槽 (主事务) 被标记为 "suspended"
2. 分配一个新的 TX 槽给自治事务
3. 自治事务的 SCN 起点为当前系统 SCN（独立可见性视图）
4. 自治事务持有的行锁与主事务持有的行锁互相独立（可能死锁）
5. 自治事务 COMMIT/ROLLBACK 后，TX 槽释放，主事务恢复 active
6. 主事务的 undo 与自治事务的 undo 在不同的 undo segment
```

性能开销：
- 上下文切换 ~5-10 微秒（同进程内切换）
- 自治事务 COMMIT 触发独立的 redo log 同步（影响 commit latency）
- 自治事务的 undo 单独写入，可能放大 undo I/O

### DB2: 独立连接（连接池复用）

DB2 9.7 的 AUTONOMOUS 实现是在内部连接池中获取一个新连接执行过程：

```
1. 主事务保持当前连接的事务上下文
2. 从内部连接池获取新连接（或新建）
3. 自治过程在新连接的独立事务中执行
4. 过程返回时，新连接归还到池中（事务自动 COMMIT）
5. 主事务的连接继续使用
```

性能开销：
- 比 Oracle 略高（连接获取开销）
- 高并发下可能因连接池竞争产生延迟

### openGauss: 独立 backend 进程

openGauss 通过派生独立的 backend 进程实现自治事务：

```
1. 主进程通过 fork() 派生子进程（或从池中获取空闲 backend）
2. 子进程执行自治过程的 PL/pgSQL 代码
3. 通过共享内存传递参数和返回值
4. 子进程独立 COMMIT 后退出（或归还到池）
5. 主进程继续主事务
```

性能开销：
- 派生进程开销显著（如果不池化）
- 共享内存通信比同进程内调用慢
- 故障隔离更好（自治事务进程崩溃不影响主事务）

### Firebird: 块级事务句柄切换

Firebird 通过引擎内部的事务句柄切换实现：

```
1. IN AUTONOMOUS TRANSACTION DO 块入口：保存当前事务句柄到栈
2. 创建新事务句柄（独立的 TIP - Transaction Inventory Page）
3. 执行块内 SQL
4. 块出口：自动 COMMIT 新事务，从栈恢复原事务句柄
5. 异常情况下自动 ROLLBACK 自治事务
```

性能开销：
- 同进程内事务句柄切换，开销最小
- 但每次自治事务需要写 TIP，I/O 开销不可忽略

## 自治事务的陷阱与最佳实践

### 1. 死锁风险

自治事务和主事务可能因争用同一行锁而死锁。Oracle 会检测到这种死锁并抛出 ORA-00060。

```sql
-- 错误模式：自治事务尝试更新主事务持有的行
DECLARE
    PROCEDURE try_update IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        UPDATE accounts SET balance = balance + 1 WHERE id = 1;  -- 死锁！
        COMMIT;
    END;
BEGIN
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    try_update();  -- 主事务持有 id=1 的行锁
END;
/
```

最佳实践：自治事务**只读不同的表**（典型如 audit_log、error_log），或使用乐观锁机制。

### 2. 必须显式 COMMIT/ROLLBACK (Oracle)

Oracle 自治事务退出前必须明确提交或回滚，否则报错：

```
ORA-06519: active autonomous transaction detected and rolled back
```

### 3. 不能与触发器循环

如果自治事务在触发器中调用，且操作的表又有自治事务触发器，可能形成无限递归。

```sql
-- 危险：表 audit_log 自身有触发器，可能死循环
CREATE OR REPLACE TRIGGER audit_log_trigger
AFTER INSERT ON audit_log
FOR EACH ROW
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO audit_log VALUES (...);  -- 触发自身，无限循环！
    COMMIT;
END;
/
```

最佳实践：审计/日志表通常不应有触发器，或显式排除自身递归。

### 4. 性能开销不可忽视

每次自治事务调用都涉及上下文切换、独立 redo log、独立 commit。在高并发审计场景下：

- Oracle: 每次 ~10-50 微秒
- DB2: 每次 ~50-200 微秒（连接池）
- openGauss: 每次 ~100-500 微秒（进程切换）
- PostgreSQL dblink: 每次 ~1-10 毫秒（建立连接）
- pg_background: 每次 ~500 微秒-2 毫秒

最佳实践：批量审计 + 自治事务（一次提交多条记录），而非每条记录都开自治事务。

### 5. 隔离级别独立

自治事务的隔离级别独立于主事务设置，需要在自治事务内部显式设置。

```sql
-- Oracle 自治事务内部独立设置
DECLARE
    PROCEDURE log_with_isolation IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;  -- 独立设置
        INSERT INTO audit_log VALUES (...);
        COMMIT;
    END;
BEGIN
    -- 主事务用 READ COMMITTED
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    log_with_isolation();
END;
/
```

### 6. 主事务回滚后审计如何关联

自治事务提交了审计记录，但主事务回滚了——审计记录中如何标识"这次操作最终失败了"？

最佳实践：分两步审计

```sql
-- 步骤 1: 进入操作前记录"开始"
log_audit('TRANSFER_START', 'alice', '...');

-- 主事务执行...

-- 步骤 2: 操作成功/失败后记录结果
EXCEPTION
    WHEN OTHERS THEN
        log_audit('TRANSFER_FAILED', 'alice', SQLERRM);
        ROLLBACK;
        RAISE;
END;
log_audit('TRANSFER_SUCCESS', 'alice', '...');
COMMIT;
```

## 自治事务 vs 替代方案对比

| 方案 | 独立提交 | 同步等待 | 性能 | 复杂度 | 跨引擎 |
|------|---------|---------|------|-------|-------|
| 原生自治事务 (Oracle/DB2) | 是 | 是 | 高 | 低 | 否（仅商业 DB） |
| dblink 回环 | 是 | 是 | 中 | 中 | 是（任何支持 dblink） |
| pg_background | 是 | 可选 | 中高 | 中 | 否（仅 PG 扩展） |
| 应用层独立连接 | 是 | 是 | 中 | 高 | 是 |
| 后台作业 (Job/Scheduler) | 是 | 否 | 低 | 中 | 是 |
| 消息队列 (LISTEN/NOTIFY/Service Broker) | 是 | 否 | 中 | 高 | 部分 |
| SQLCLR / UDF | 是 | 是 | 中 | 高 | 否（SQL Server only） |
| SAVEPOINT | 否 | -- | -- | -- | 多数引擎 |

## 为什么大多数引擎不支持原生自治事务？

PostgreSQL 核心团队 / SQL Server 团队 / 现代分布式数据库的共识是：**自治事务违反"一个连接一个事务"的纯粹模型**，会带来如下问题：

### 1. MVCC 设计冲突

PostgreSQL 的 MVCC 基于事务 ID (xid) 的可见性规则。自治事务需要在一个会话中维护多个 xid 上下文，需要在 MVCC 引擎中支持"挂起的 xid 栈"，对快照管理造成显著复杂度。

```
PostgreSQL MVCC 假设：
  - 一个 backend = 一个事务 = 一个 xid
  - 快照基于当前 xid 和活跃事务列表

自治事务破坏假设：
  - 一个 backend 内部需要管理多个 xid
  - 需要嵌套快照栈
  - 锁管理器需要区分"主事务锁"和"自治事务锁"
  - WAL 写入需要交错记录两个事务的变更
```

### 2. 锁管理复杂度

自治事务和主事务在同一连接中，但持有独立的锁。锁管理器需要区分：

- 主事务持有的行锁
- 自治事务持有的行锁
- 自治事务和主事务之间的死锁检测

### 3. 死锁风险天然存在

任何自治事务方案都面临"自治事务等待主事务持有的资源"问题。Oracle 通过死锁检测自动识别，但用户体验不佳。PG 团队认为这是一种"反模式"。

### 4. 应用架构应当推动副作用解耦

PostgreSQL 社区主张：审计、错误日志、计费这类副作用应当通过**独立的服务**（独立连接、消息队列、后台 worker）实现，而不是在数据库内部"绕开"事务边界。这种观点强调架构纯粹性。

### 5. 性能开销显著

即使实现了，自治事务每次调用都需要独立的 commit（独立的 fsync），在高 TPS 场景下成为性能瓶颈。批量审计（应用层缓冲后一次写入）通常更高效。

### 6. 分布式数据库尤其困难

CockroachDB / Spanner / TiDB 等分布式数据库的事务跨多个节点协调（2PC / Percolator），自治事务需要在分布式上下文中嵌套独立的 2PC 协调，复杂度爆炸。这些引擎选择不实现。

## 各引擎社区讨论与未来展望

### PostgreSQL

- Hackers 邮件列表多次讨论 `PRAGMA AUTONOMOUS_TRANSACTION`
- 2016 年 EDB 提出过 patch，但未被合并（认为破坏架构）
- pg_background 扩展提供了部分能力，但不在主线
- 长期方向：通过逻辑解码、外部消息队列等"应用层"方式解决

### SQL Server

- 微软曾在 SQL Server 2014 路线图讨论过，最终未实现
- 推荐 SQLCLR 或 Service Broker 作为替代
- 2016 年后基本不再讨论原生支持

### MySQL

- 多次社区请求，Oracle 收购后路线图未明确
- 8.0 版本仍未支持
- MySQL 开发团队倾向于"应用层独立连接"

### 分布式数据库

- TiDB: 明确不实现，推荐应用层
- CockroachDB: 不在路线图
- YugabyteDB: 不支持，继承 PG 的设计哲学

### 国产数据库

- OceanBase: Oracle 模式完整支持，长期维护
- openGauss: 持续完善 Oracle 兼容性
- 达梦/金仓: Oracle 兼容是核心卖点，全面支持
- 总体趋势：以 Oracle 兼容为目标的国产数据库都会实现

## 引擎实现建议（对开发者）

如果你正在为某个数据库引擎设计自治事务支持，关键设计点：

### 1. 选择实现层级

- **进程内事务句柄切换**（Oracle / Firebird 模式）：性能最优，但 MVCC 复杂度高
- **独立 backend 进程**（openGauss 模式）：故障隔离好，但通信开销大
- **连接池复用**（DB2 模式）：实现简单，但连接占用增加

### 2. 处理 MVCC 可见性

```
关键决策：自治事务能否看到主事务未提交的修改？

Oracle 选择: 不能看到（独立 SCN 视图）
原因: 与主事务完全独立，避免破坏 ACID 隔离
影响: 用户需要理解"自治事务是另一个事务"
```

### 3. 死锁检测必须支持

```
死锁场景: 自治事务等待主事务的锁
检测算法: 在锁等待图中将"同一会话的两个事务"视为不同节点
处理: 自动回滚自治事务，主事务继续
```

### 4. 显式 COMMIT/ROLLBACK 的强制规则

```
退出自治事务时：
  - 已 COMMIT/ROLLBACK：正常返回
  - 未 COMMIT/ROLLBACK：抛出错误（Oracle ORA-06519）
                       或自动 ROLLBACK（部分实现）

推荐: 强制要求显式提交/回滚（与 Oracle 一致），避免静默数据丢失
```

### 5. WAL/Redo 写入的协调

```
主事务和自治事务的 WAL 记录可能交错：
  T1: BEGIN main
  T2: BEGIN autonomous (suspend T1)
  T3: INSERT in autonomous
  T4: COMMIT autonomous (write WAL)
  T5: resume T1
  T6: UPDATE in main
  T7: ROLLBACK main

WAL 中的顺序：T1_BEGIN, T2_BEGIN, T2_INSERT, T2_COMMIT, T1_UPDATE, T1_ROLLBACK
回放时：必须按 WAL 顺序回放，自治事务的 COMMIT 在主事务 ROLLBACK 之前生效
```

### 6. 性能优化

```
1. 自治事务上下文池化（避免每次新建）
2. 自治事务的 commit 可批量化（如果应用允许延迟）
3. 自治事务的 redo 与主事务的 redo 共享 WAL writer
4. 自治事务的 undo 段复用（减少 segment 切换开销）
```

### 7. 监控与可观测性

```
EXPLAIN 应当标记自治事务调用：
  -> Procedure call (autonomous)
       overhead: ~50us (context switch + commit)

SQL trace 应当区分主事务和自治事务的执行：
  trace.txn_id = 100 (main)
  trace.txn_id = 101 (autonomous, parent=100)

死锁报告应当明确标识自治事务参与方：
  Deadlock between session 5 (main txn 100) and session 5 (autonomous txn 101)
```

## 关键发现

1. **Oracle PRAGMA AUTONOMOUS_TRANSACTION 是事实标准**：1999 年 Oracle 8i 引入后，DB2、OceanBase Oracle 模式、openGauss、EDB、达梦、金仓等所有 Oracle 兼容数据库都跟进实现。但 ANSI/ISO SQL 标准从未承认这个特性。

2. **"独立事务"是 Oracle/DB2 阵营独有**：约 14 个引擎提供原生支持，且大多数集中在 Oracle 兼容生态。PostgreSQL、SQL Server、MySQL、SQLite、所有 OLAP/MPP/分布式 SQL 引擎都不支持。

3. **PostgreSQL 的明确反对**：PG 核心团队多次明确表示不会实现，理由是破坏 MVCC 模型、违反"一个连接一个事务"哲学。pg_background、dblink 等扩展或仿真方案虽然能实现等价功能，但都不在主线。

4. **Firebird 是开源数据库中的特例**：2010 年 Firebird 2.5 引入 `IN AUTONOMOUS TRANSACTION DO` 块语法，是少数原生支持自治事务的开源数据库（除了 Oracle 兼容产品）。

5. **DB2 的两种语法风格**：DB2 同时支持 SQL/PSM 风格的过程级 `AUTONOMOUS` 子句，以及 Oracle 兼容模式的 `PRAGMA AUTONOMOUS_TRANSACTION`，体现了两种事务模型哲学的融合。

6. **审计日志是首要应用场景**：所有引擎的官方文档都把"审计日志"作为自治事务的第一个示例。其他常见场景包括错误日志、计费、配额、序列号生成等"必须落盘"的副作用。

7. **SAVEPOINT 不是自治事务的替代**：SAVEPOINT 是同一事务内部的部分回滚机制，外层事务回滚时所有 SAVEPOINT 状态都会撤销。两者解决的问题完全不同。

8. **dblink 回环是 PostgreSQL 最常见的仿真方案**：通过 `dblink_exec('host=localhost', 'INSERT...')` 建立到自身的独立连接，但每次调用开销高（建立 TCP 连接 + 鉴权）。持久化连接 (dblink_connect) 可降低开销。

9. **死锁是自治事务的固有风险**：自治事务和主事务可能因争用同一资源而死锁，Oracle 通过 ORA-00060 检测。最佳实践是自治事务只操作不同的表（如审计日志专用表）。

10. **分布式数据库基本拒绝实现**：CockroachDB、TiDB、YugabyteDB、Spanner 等分布式 SQL 引擎都明确不支持自治事务，原因是分布式 2PC 嵌套独立 2PC 复杂度爆炸，且 OLAP/HTAP 场景下需求较少。

11. **国产数据库全面跟进**：达梦、金仓、神通、OceanBase Oracle 模式、openGauss、PolarDB Oracle 兼容版等国产数据库以"Oracle 兼容"为核心卖点，全部支持 PRAGMA AUTONOMOUS_TRANSACTION，是国产数据库迁移老 Oracle 系统的关键能力。

12. **性能开销不可忽视**：原生自治事务每次调用约 10-50 微秒（Oracle/Firebird），仿真方案则可能高达毫秒级（dblink）。高频审计场景应当批量化处理。

## 参考资料

- Oracle: [PL/SQL PRAGMA AUTONOMOUS_TRANSACTION](https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/AUTONOMOUS_TRANSACTION-pragma.html)
- Oracle: [Autonomous Transactions in PL/SQL](https://docs.oracle.com/en/database/oracle/oracle-database/19/adfns/transactions-and-concurrency.html)
- DB2: [CREATE PROCEDURE AUTONOMOUS clause](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-procedure-sql)
- Firebird: [PSQL Autonomous Transactions](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref30/firebird-30-language-reference.html)
- openGauss: [Autonomous Transactions](https://docs.opengauss.org/en/docs/latest/docs/DatabaseReference/transaction.html)
- HSQLDB: [User Guide - SQL-Invoked Routines](http://hsqldb.org/doc/2.0/guide/sqlroutines-chapt.html)
- PostgreSQL: [dblink](https://www.postgresql.org/docs/current/dblink.html)
- PostgreSQL: [pg_background extension](https://github.com/vibhorkum/pg_background)
- PostgreSQL: [Hackers thread - PRAGMA AUTONOMOUS_TRANSACTION (2016)](https://www.postgresql.org/message-id/flat/56AAD1F2.7000001%40postgrespro.ru)
- SQL Server: [Loopback Linked Server for Autonomous Transactions](https://learn.microsoft.com/en-us/sql/relational-databases/linked-servers/linked-servers-database-engine)
- OceanBase: [PL/SQL Reference - PRAGMA AUTONOMOUS_TRANSACTION](https://en.oceanbase.com/docs/)
- 达梦: [DM8 PL/SQL 程序设计指南 - 自治事务](https://eco.dameng.com/document/dm/zh-cn/pm/plsql-program.html)
- "Oracle Database 11g PL/SQL Programming" by Michael McLaughlin (2008), Oracle Press
- "DB2 9.7 Application Development Guide", IBM Documentation
