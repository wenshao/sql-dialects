# 保存点 (SAVEPOINT / Nested Transactions)

一个包含 100 次插入的批处理，其中第 37 条触发唯一键冲突——你希望回滚这 1 条却保留前 36 条、继续后 63 条。保存点 (SAVEPOINT) 是关系数据库提供的**部分回滚**机制：在外层事务不中断的前提下，撤销事务内部一段子操作。它让长事务具备错误恢复的局部粒度，让 Spring `@Transactional(propagation=NESTED)`、Django `transaction.savepoint`、Python DB-API 嵌套事务、存储过程异常处理等上层抽象得以实现。

## SQL:1999 标准定义

SQL:1999 标准 (ISO/IEC 9075-2, Section 17.9–17.11) 正式引入了 SAVEPOINT 语句族，包含三条核心语句：

```sql
-- 创建保存点
<savepoint statement> ::= SAVEPOINT <savepoint specifier>

-- 回滚到保存点（保存点仍然存在，其后创建的保存点被销毁）
<rollback statement> ::=
    ROLLBACK [ WORK ] TO SAVEPOINT <savepoint specifier>

-- 释放保存点（保存点不再可用，但其所做的变更仍保留）
<release savepoint statement> ::=
    RELEASE SAVEPOINT <savepoint specifier>
```

标准的关键语义：

1. **必须在活跃事务中**：SAVEPOINT 不能独立于事务存在；隐式事务模式下发出 SAVEPOINT 会自动开启事务。
2. **同名覆盖**：重复使用同一名字创建 SAVEPOINT，旧的保存点在标准中被"覆盖"（部分引擎是销毁而非覆盖）。
3. **ROLLBACK TO 不结束事务**：与 ROLLBACK 不同，ROLLBACK TO SAVEPOINT 之后事务仍活跃。
4. **销毁链**：ROLLBACK TO sp_A 会销毁 sp_A 之后创建的所有保存点（级联销毁）。
5. **嵌套**：保存点之间可以嵌套，形成栈结构。
6. **COMMIT 释放所有**：事务提交时，所有保存点自动释放。
7. **完整 ROLLBACK 销毁所有**：事务完整回滚时，所有保存点被销毁。

SQL:1999 同时定义了 **CHAINED TRANSACTION**：`COMMIT AND CHAIN` / `ROLLBACK AND CHAIN` 在提交/回滚当前事务后立即启动一个新事务，常与保存点搭配使用。

## 支持矩阵（综合）

### SAVEPOINT 基础三语句

| 引擎 | SAVEPOINT | ROLLBACK TO | RELEASE | 嵌套深度 | 同名语义 | 版本 |
|------|-----------|-------------|---------|---------|---------|------|
| PostgreSQL | 是 | 是 | 是 | 无硬限制 | 覆盖（旧的被遮蔽） | 8.0+ |
| MySQL (InnoDB) | 是 | 是 | 是 | 无硬限制 | 替换（销毁旧的） | 5.0+ |
| MariaDB (InnoDB) | 是 | 是 | 是 | 无硬限制 | 替换 | 5.0+ |
| SQLite | 是 | 是 | 是 | 无硬限制 | 新建（同名并存） | 3.6.8+ |
| Oracle | 是 | 是 | -- | 受 UGA 内存限 | 替换 | v7+ |
| SQL Server | `SAVE TRANSACTION` | 是 | -- | 无硬限制 | 替换 | 全版本 |
| DB2 | 是 | 是 | 是 | 无硬限制 | 可配置 | 8+ |
| Snowflake | -- | -- | -- | -- | -- | 不支持 |
| BigQuery | -- | -- | -- | -- | -- | 不支持 |
| Redshift | -- | -- | -- | -- | -- | 不支持 |
| DuckDB | 是 | 是 | 是 | 无硬限制 | 替换 | 0.7+ |
| ClickHouse | -- | -- | -- | -- | -- | 不支持 |
| Trino | -- | -- | -- | -- | -- | 不支持 |
| Presto | -- | -- | -- | -- | -- | 不支持 |
| Spark SQL | -- | -- | -- | -- | -- | 不支持 |
| Hive | -- | -- | -- | -- | -- | 不支持 |
| Flink SQL | -- | -- | -- | -- | -- | 不支持 |
| Databricks | -- | -- | -- | -- | -- | 不支持 |
| Teradata | -- | -- | -- | -- | -- | 不支持 (ANSI mode 限制) |
| Greenplum | 是 | 是 | 是 | 无硬限制 | 覆盖 | 继承 PG |
| CockroachDB | 是 | 是 | 是 | 无硬限制 | 替换 | 20.1+ (GA) |
| TiDB | 是 | 是 | 是 | 无硬限制 | 替换 | 6.2+ |
| OceanBase | 是 | 是 | 是 | 无硬限制 | 替换 | 4.0+ |
| YugabyteDB | 是 | 是 | 是 | 无硬限制 | 覆盖 | 2.14+ |
| SingleStore | -- | -- | -- | -- | -- | 不支持 |
| Vertica | 是 | 是 | 是 | 无硬限制 | 替换 | 全版本 |
| Impala | -- | -- | -- | -- | -- | 不支持 |
| StarRocks | -- | -- | -- | -- | -- | 不支持 |
| Doris | -- | -- | -- | -- | -- | 不支持 |
| MonetDB | 是 | 是 | 是 | 无硬限制 | 替换 | Jun2020+ |
| CrateDB | -- | -- | -- | -- | -- | 不支持 |
| TimescaleDB | 是 | 是 | 是 | 无硬限制 | 覆盖 | 继承 PG |
| QuestDB | -- | -- | -- | -- | -- | 不支持 |
| Exasol | -- | -- | -- | -- | -- | 不支持 |
| SAP HANA | 是 | 是 | 是 | 无硬限制 | 替换 | 1.0+ |
| Informix | 是 | 是 | 是 | 无硬限制 | 替换 | 全版本 |
| Firebird | `SAVEPOINT` | 是 | 是 | 无硬限制 | 替换 | 1.5+ |
| H2 | 是 | 是 | 是 | 无硬限制 | 替换 | 全版本 |
| HSQLDB | 是 | 是 | 是 | 无硬限制 | 替换 | 1.8+ |
| Derby | 是 | 是 | 是 | 无硬限制 | 替换 | 10.0+ |
| Amazon Athena | -- | -- | -- | -- | -- | 不支持 |
| Azure Synapse | `SAVE TRANSACTION` | 是 | -- | -- | 替换 | 继承 MSSQL |
| Google Spanner | -- | -- | -- | -- | -- | 不支持 |
| Materialize | -- | -- | -- | -- | -- | 不支持（只读视图） |
| RisingWave | -- | -- | -- | -- | -- | 不支持 |
| InfluxDB (SQL) | -- | -- | -- | -- | -- | 不支持（无事务） |
| DatabendDB | -- | -- | -- | -- | -- | 不支持 |
| Yellowbrick | 是 | 是 | 是 | 无硬限制 | 覆盖 | 继承 PG |
| Firebolt | -- | -- | -- | -- | -- | 不支持 |

> 统计：约 22 个引擎支持完整的 SAVEPOINT/ROLLBACK TO/RELEASE 三元组；约 2 个引擎（SQL Server/Azure Synapse）仅支持 SAVE TRANSACTION + ROLLBACK TO，不提供 RELEASE；约 24 个引擎完全不支持保存点。
>
> 不支持保存点的引擎多为：(1) OLAP/MPP 引擎（Snowflake/BigQuery/Redshift/ClickHouse/Trino/Spark SQL/Databricks/Impala/StarRocks/Doris 等），事务模型以单语句或批量提交为主；(2) 流处理引擎（Flink/Materialize/RisingWave/KsqlDB）；(3) 存储/查询分离的查询服务（Athena/Firebolt/Databend）。

### 隐式保存点 & 异常处理

| 引擎 | 隐式保存点 | 触发场景 | 备注 |
|------|----------|---------|------|
| Oracle (PL/SQL) | 是 | 语句执行前 | 语句失败自动回滚到语句前状态 |
| Oracle (PL/SQL EXCEPTION) | 是 | BEGIN/EXCEPTION 块入口 | 命名异常处理块内部隐式保存点 |
| PostgreSQL (PL/pgSQL BEGIN/EXCEPTION) | 是 | EXCEPTION 块 | 每个带 EXCEPTION 的 BEGIN 创建子事务 |
| SQL Server | 否 | -- | XACT_ABORT + TRY/CATCH + SAVE TRANSACTION 手动模拟 |
| MySQL (InnoDB) | 是（语句级） | 单语句失败 | 语句失败只回滚该语句，不影响事务 |
| DB2 (SQL PL) | 是 | BEGIN ATOMIC 块 | ATOMIC 块内部隐式保存点 |
| SQLite | 否 | -- | 需要显式 SAVEPOINT |
| Firebird (PSQL) | 是 | WHEN 块入口 | 存储过程异常处理隐式保存点 |
| CockroachDB | 是（语句级） | 单语句失败 | 通过隐式事务重试 |

### 与自动提交 (autocommit) 的交互

| 引擎 | autocommit=ON 时 SAVEPOINT | 行为 |
|------|--------------------------|------|
| PostgreSQL | 报错 | "SAVEPOINT can only be used in transaction blocks" |
| MySQL | 静默接受并立即释放 | SAVEPOINT 在语句级事务内部有效，语句结束后失效 |
| Oracle | 报错 ORA-01086 | "SAVEPOINT '...' never established" |
| SQL Server | `@@TRANCOUNT=0` 时报错 | 需要显式 BEGIN TRAN |
| SQLite | 开启隐式事务 | SAVEPOINT 会启动一个新事务（autocommit 关闭） |
| DB2 | 报错 | SQLSTATE 3B002 |
| CockroachDB | 开启隐式事务 | 第一个 SAVEPOINT 启动显式事务 |
| TiDB | 报错 | "SAVEPOINT on autocommit session" |

### COMMIT/ROLLBACK AND CHAIN（SQL:1999 链式事务）

| 引擎 | COMMIT AND CHAIN | ROLLBACK AND CHAIN | 版本 |
|------|-----------------|-------------------|------|
| PostgreSQL | 是 | 是 | 12+ |
| MySQL | 是 | 是 | 5.0+ |
| MariaDB | 是 | 是 | 全版本 |
| SQL Server | -- | -- | 不支持 |
| Oracle | -- | -- | 不支持（SET TRANSACTION 手动）|
| DB2 | -- | -- | 不支持 |
| SQLite | -- | -- | 不支持 |
| CockroachDB | -- | -- | 不支持 |

## 核心语义：三元组详解

### 基本用法

```sql
BEGIN;                                    -- 开启事务
INSERT INTO orders VALUES (1, 'A');

SAVEPOINT sp1;                            -- 创建保存点 sp1
INSERT INTO orders VALUES (2, 'B');

SAVEPOINT sp2;                            -- 创建保存点 sp2
INSERT INTO orders VALUES (3, 'C');

ROLLBACK TO SAVEPOINT sp2;                -- 撤销 (3, 'C')，sp2 仍然存在
                                          -- 此时已写入：(1,'A'), (2,'B')
INSERT INTO orders VALUES (4, 'D');

RELEASE SAVEPOINT sp1;                    -- 释放 sp1（连带 sp2），变更保留
                                          -- 当前状态：(1,'A'), (2,'B'), (4,'D')
COMMIT;                                   -- 永久保存
```

### ROLLBACK TO 的关键语义

ROLLBACK TO 只回滚该保存点之后的数据修改，**保存点本身仍然存在**，可以再次 ROLLBACK TO 或 RELEASE。同时所有**在该保存点之后创建的保存点被级联销毁**：

```sql
BEGIN;
SAVEPOINT sp1;
  INSERT INTO t VALUES (1);
  SAVEPOINT sp2;
    INSERT INTO t VALUES (2);
    SAVEPOINT sp3;
      INSERT INTO t VALUES (3);
ROLLBACK TO SAVEPOINT sp1;
  -- 结果：t 为空；sp1 仍然存在；sp2, sp3 被销毁
  -- RELEASE SAVEPOINT sp2;  -- 会报错：sp2 不存在
SAVEPOINT sp2;                -- 可以重新创建同名保存点
COMMIT;
```

### RELEASE SAVEPOINT 的语义

RELEASE 销毁保存点但**保留其后所有变更**。相当于"确认这段子操作成功，合并到外层"。RELEASE 同样级联销毁其后创建的保存点：

```sql
BEGIN;
INSERT INTO t VALUES (1);
SAVEPOINT sp1;
  INSERT INTO t VALUES (2);
  SAVEPOINT sp2;
    INSERT INTO t VALUES (3);
  RELEASE SAVEPOINT sp1;
  -- 结果：t = {1, 2, 3}；sp1 和 sp2 都被销毁
COMMIT;
```

## 各引擎语法详解

### PostgreSQL（最标准的实现）

```sql
-- 基础用法
BEGIN;
INSERT INTO accounts VALUES (1, 'Alice', 100);

SAVEPOINT before_update;
UPDATE accounts SET balance = balance - 50 WHERE id = 1;
-- 检测到业务错误
ROLLBACK TO SAVEPOINT before_update;

COMMIT;

-- PL/pgSQL 的 BEGIN...EXCEPTION 自动使用保存点
CREATE OR REPLACE FUNCTION safe_transfer(from_id INT, to_id INT, amount NUMERIC)
RETURNS TEXT AS $$
DECLARE
    err_msg TEXT;
BEGIN
    UPDATE accounts SET balance = balance - amount WHERE id = from_id;
    UPDATE accounts SET balance = balance + amount WHERE id = to_id;
    RETURN 'success';
EXCEPTION
    WHEN check_violation THEN
        -- 自动回滚到 BEGIN 处的隐式保存点
        GET STACKED DIAGNOSTICS err_msg = MESSAGE_TEXT;
        RETURN 'failed: ' || err_msg;
    WHEN OTHERS THEN
        RETURN 'unknown error';
END;
$$ LANGUAGE plpgsql;

-- 匿名 DO 块同样支持 EXCEPTION 隐式保存点
DO $$
BEGIN
    INSERT INTO log VALUES ('start');
    PERFORM 1/0;  -- division_by_zero
EXCEPTION
    WHEN division_by_zero THEN
        INSERT INTO log VALUES ('recovered');
END; $$;
-- 结果：log = {'start', 'recovered'}；'start' 因子事务回滚被撤销
-- 注意：PostgreSQL BEGIN/EXCEPTION 会回滚整个块内的变更，
-- 因此 'start' 会被撤销，最终只剩 'recovered'

-- 同名 SAVEPOINT：旧的被遮蔽但仍存在
BEGIN;
SAVEPOINT x;
INSERT INTO t VALUES (1);
SAVEPOINT x;             -- 创建新的 x，旧 x 被遮蔽（但未销毁）
INSERT INTO t VALUES (2);
RELEASE SAVEPOINT x;     -- 释放新 x，旧 x 恢复可见
ROLLBACK TO SAVEPOINT x; -- 回滚到旧 x（即 t = {1}）
COMMIT;
```

PostgreSQL 的保存点实现基于 **子事务 (subtransaction)**：每个 SAVEPOINT 分配一个独立的 virtual XID，MVCC 可见性通过 pg_subtrans 文件跟踪父子关系。这是保存点性能问题的根源（下文深入分析）。

### Oracle（SAVEPOINT 诞生地）

Oracle v7 (1992) 引入 SAVEPOINT 语句，是工业数据库中最早实现者之一：

```sql
-- 基础用法
BEGIN
  INSERT INTO emp VALUES (1001, 'Alice', 50000);
  SAVEPOINT before_promotion;
  UPDATE emp SET salary = salary * 1.5 WHERE id = 1001;
  -- 审批未通过
  ROLLBACK TO SAVEPOINT before_promotion;
  COMMIT;
END;
/

-- Oracle 不支持 RELEASE SAVEPOINT（SQL:1999 标准之后仍未实现）
-- 保存点只能通过 COMMIT 或 ROLLBACK 释放
-- ROLLBACK TO SAVEPOINT 是唯一显式操作

-- PL/SQL EXCEPTION 块的隐式保存点
DECLARE
    v_count NUMBER;
BEGIN
    INSERT INTO audit_log VALUES ('step1', SYSDATE);
    UPDATE balance SET amount = amount - 100 WHERE acct = 'A';
    UPDATE balance SET amount = amount + 100 WHERE acct = 'B';
EXCEPTION
    WHEN OTHERS THEN
        -- Oracle 为每个语句创建隐式保存点（"statement-level atomicity"）
        -- 但 BEGIN/END 块本身没有隐式保存点
        -- 如需块级回滚，需手动 SAVEPOINT
        ROLLBACK;  -- 完全回滚；如需部分回滚需手动 SAVEPOINT
END;
/

-- Oracle 的 statement-level 原子性（隐式保存点）
BEGIN
    INSERT INTO t VALUES (1);  -- 成功
    INSERT INTO t VALUES (2, 'too many columns');  -- 失败
    -- Oracle 自动回滚第二条 INSERT（隐式保存点）
    -- 但第一条仍保留
    COMMIT;
END;
/

-- PL/SQL 过程推荐模式：在过程入口创建保存点
CREATE PROCEDURE transfer_funds(p_from INT, p_to INT, p_amt NUMBER) IS
BEGIN
    SAVEPOINT sp_begin;
    UPDATE accounts SET balance = balance - p_amt WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amt WHERE id = p_to;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO SAVEPOINT sp_begin;
        RAISE;  -- 重新抛出
END;
/
```

Oracle 的保存点基于 UGA (User Global Area) 和 undo 段管理：ROLLBACK TO 实际上是 undo 链的回放。Oracle 不支持 RELEASE SAVEPOINT，这是其与 SQL 标准的主要差异。

### PostgreSQL 子事务（Subtransactions）深入解析

PostgreSQL 是唯一将保存点实现为**完整的子事务**的主流引擎。每个 SAVEPOINT 创建一个独立的 virtual transaction ID（vXID），子事务可以独立提交（RELEASE）或回滚（ROLLBACK TO）。

#### 实现机制

```
主事务 XID = 1000
├─ SAVEPOINT sp1 → 子事务 XID = 1001
│  ├─ SAVEPOINT sp2 → 子事务 XID = 1002
│  └─ SAVEPOINT sp3 → 子事务 XID = 1003
└─ ...

每个元组的 xmin/xmax 记录写入时的 XID（可以是子事务）
pg_subtrans 文件跟踪父子关系：1001→1000, 1002→1001, 1003→1001
MVCC 可见性判断时：先查元组 XID，若是子事务则递归查找根事务
```

#### 性能成本

PostgreSQL 子事务有若干性能陷阱：

1. **pg_subtrans SLRU 缓冲区**：子事务多时 SLRU 缓冲命中率下降，可能触发磁盘 I/O。默认 SLRU 缓冲仅 32 个页。
2. **快照大小膨胀**：每个事务的快照需要记录所有活跃事务和子事务的 XID。大量子事务导致快照尺寸增大，占用内存和 CPU。
3. **超过 64 个子事务触发 "subxid overflow"**：每个后端进程 PGPROC 最多缓存 64 个子事务 XID；超过后快照计算需扫描 pg_subtrans。
4. **可见性检查下沉**：嵌套深度大时，MVCC 可见性需递归遍历父链。

```sql
-- 性能问题示例：大循环中的异常处理
DO $$
BEGIN
    FOR i IN 1..100000 LOOP
        BEGIN
            INSERT INTO t VALUES (i);
        EXCEPTION
            WHEN unique_violation THEN NULL;
        END;
    END LOOP;
END; $$;
-- 每次 BEGIN/EXCEPTION 创建子事务
-- 100000 个子事务 → pg_subtrans 严重抖动 → 慢数十倍
-- 推荐改为 INSERT ... ON CONFLICT DO NOTHING（单语句）
```

社区的 Subtransaction 性能问题已知多年。部分分支（如 GitLab 的自定义 PG）禁用子事务以避免 overflow。PG 16 引入优化减少 SLRU 抖动，但根本问题仍在。

### SQL Server（SAVE TRANSACTION，无 RELEASE）

```sql
-- SQL Server 使用 SAVE TRANSACTION（SAVE TRAN）
BEGIN TRANSACTION;
    INSERT INTO orders VALUES (1, 'A');
    
    SAVE TRANSACTION sp1;
    INSERT INTO orders VALUES (2, 'B');
    
    -- 业务校验失败
    ROLLBACK TRANSACTION sp1;
    -- 仅回滚 (2, 'B')；(1, 'A') 保留
    
    INSERT INTO orders VALUES (3, 'C');
COMMIT TRANSACTION;

-- 注意：SQL Server 不提供 RELEASE SAVEPOINT
-- 保存点由 COMMIT / ROLLBACK（完整）自动释放
-- 同名保存点：新的覆盖旧的，不能回到旧的

-- 同名陷阱
BEGIN TRAN;
    SAVE TRAN x;
    INSERT INTO t VALUES (1);
    SAVE TRAN x;          -- 覆盖，旧 x 丢失
    INSERT INTO t VALUES (2);
ROLLBACK TRAN x;          -- 只回滚 (2)
                          -- 无法回到 (1) 之前
COMMIT;

-- 与 TRY/CATCH 结合（推荐模式）
BEGIN TRY
    BEGIN TRANSACTION;
    SAVE TRANSACTION sp_outer;

    INSERT INTO orders VALUES (1, 'A');

    -- 嵌套的子操作
    BEGIN TRY
        SAVE TRANSACTION sp_inner;
        INSERT INTO orders VALUES (2, 'DUPLICATE_KEY');
    END TRY
    BEGIN CATCH
        IF XACT_STATE() = 1  -- 事务仍可提交
            ROLLBACK TRANSACTION sp_inner;
        ELSE
            THROW;
    END CATCH;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- SQL Server 的 XACT_ABORT 陷阱
SET XACT_ABORT ON;
-- 在 XACT_ABORT=ON 模式下，任何运行时错误导致整个事务立即回滚
-- SAVE TRANSACTION 在这种模式下几乎无效
-- 大多数错误无法通过 ROLLBACK TO SAVEPOINT 恢复

-- @@TRANCOUNT 与保存点的关系
BEGIN TRAN;        -- @@TRANCOUNT = 1
    SAVE TRAN sp;  -- @@TRANCOUNT 仍 = 1（SAVE TRAN 不增加计数）
    BEGIN TRAN;    -- @@TRANCOUNT = 2（嵌套事务，非真实嵌套）
    COMMIT TRAN;   -- @@TRANCOUNT = 1
    ROLLBACK TRAN sp;  -- 成功
COMMIT TRAN;
```

SQL Server 的保存点有几个与标准不同的特性：

1. **没有 RELEASE SAVEPOINT**：只能通过 COMMIT / 完全 ROLLBACK / 覆盖释放。
2. **BEGIN TRAN 的嵌套只是计数器**：`BEGIN TRAN` + `COMMIT TRAN` 不真正嵌套，只有最外层 COMMIT 才真正提交；任何 ROLLBACK 都回滚所有层。
3. **XACT_ABORT 场景下保存点几乎失效**：许多错误（如死锁）会强制整个事务回滚。
4. **触发器内的 ROLLBACK**：在触发器内 ROLLBACK 会回滚整个事务及所有保存点。

### MySQL / InnoDB（完整 SQL:1999 实现）

MySQL 从 5.0 (2005) 开始在 InnoDB 存储引擎支持完整的 SAVEPOINT 三元组：

```sql
START TRANSACTION;
INSERT INTO orders VALUES (1, 'A');

SAVEPOINT sp1;
INSERT INTO orders VALUES (2, 'B');

SAVEPOINT sp2;
INSERT INTO orders VALUES (3, 'C');

ROLLBACK TO SAVEPOINT sp2;  -- 回滚 (3, 'C')，sp2 销毁
                            -- 注：MySQL 的 ROLLBACK TO 会销毁目标 savepoint
RELEASE SAVEPOINT sp1;       -- 释放 sp1

COMMIT;

-- MySQL 特性：ROLLBACK TO SAVEPOINT 会销毁目标保存点？
-- 官方文档：ROLLBACK TO 不销毁目标（与 PostgreSQL 一致）
-- 但 ROLLBACK TO 之后在该名字上的 RELEASE 会报错（因为其后创建的被销毁了）

-- 存储引擎限制：只有 InnoDB 支持 SAVEPOINT
-- MyISAM / MEMORY 引擎表：SAVEPOINT 无效果（MyISAM 无事务）

-- autocommit 交互
SET autocommit = 1;
SAVEPOINT sp1;  -- 在隐式事务内；下一个语句提交后 sp1 失效
INSERT INTO t VALUES (1);  -- 立即提交
ROLLBACK TO SAVEPOINT sp1; -- 报错：sp1 不存在

-- 推荐模式：显式 START TRANSACTION
START TRANSACTION;
SAVEPOINT sp1;
...
COMMIT;

-- MySQL 同名 SAVEPOINT：新的销毁旧的
START TRANSACTION;
SAVEPOINT sp;
INSERT INTO t VALUES (1);
SAVEPOINT sp;           -- 旧 sp 被销毁
INSERT INTO t VALUES (2);
ROLLBACK TO SAVEPOINT sp;  -- 回滚到新 sp，仅撤销 (2)
COMMIT;

-- MySQL 的语句级隐式回滚
START TRANSACTION;
INSERT INTO t VALUES (1);      -- 成功
INSERT INTO t VALUES (NULL);   -- 失败（假设 NOT NULL）
-- InnoDB 自动回滚失败的语句，事务仍然活跃
-- (1) 仍在事务中
COMMIT;
-- 最终：t = {1}
```

MySQL 的实现基于 InnoDB undo log：SAVEPOINT 记录当前 undo log 位置，ROLLBACK TO 根据 undo 链回退。由于 InnoDB 不创建独立子事务，性能开销远小于 PostgreSQL。

### MariaDB

MariaDB 在 5.0 fork 时继承了 MySQL 的 SAVEPOINT 实现，基本语义与 MySQL 一致。MariaDB 额外在 Aria / XtraDB 引擎上保留支持。

### DB2（完整支持 + UOW 细节）

```sql
-- 基础用法
BEGIN ATOMIC
    INSERT INTO orders VALUES (1, 'A');
    SAVEPOINT sp1 ON ROLLBACK RETAIN CURSORS;
    INSERT INTO orders VALUES (2, 'B');
    ROLLBACK TO SAVEPOINT sp1;
    -- (2, 'B') 回滚；(1, 'A') 保留
    RELEASE SAVEPOINT sp1;
END;

-- DB2 特有子句
SAVEPOINT sp1 UNIQUE;                 -- 强制唯一名字，重复报错
SAVEPOINT sp1 ON ROLLBACK RETAIN CURSORS;   -- 回滚时保留游标（默认）
SAVEPOINT sp1 ON ROLLBACK RETAIN LOCKS;     -- 回滚时保留锁（默认）

-- BEGIN ATOMIC 的隐式保存点
CREATE PROCEDURE safe_insert(IN p_val INT)
BEGIN ATOMIC
    -- 整个 ATOMIC 块是一个隐式保存点
    INSERT INTO t VALUES (p_val);
    -- 如果块内任何语句失败，整个块原子回滚
    -- 但外层事务仍可继续
END;

-- DB2 的 XA 限制
-- 在 XA 分布式事务中，SAVEPOINT 行为受限：
-- 1. 不能跨 XA 分支使用保存点
-- 2. XA 事务提交前，保存点不能跨越 xa_prepare 边界
-- 3. 部分 DB2 for z/OS 版本在 XA 模式下完全禁用 SAVEPOINT
```

### SQLite（轻量但完整）

SQLite 从 3.6.8 (2008) 开始支持完整的 SAVEPOINT 三元组：

```sql
BEGIN TRANSACTION;
INSERT INTO t VALUES (1);

SAVEPOINT sp1;
INSERT INTO t VALUES (2);

SAVEPOINT sp2;
INSERT INTO t VALUES (3);

ROLLBACK TRANSACTION TO SAVEPOINT sp2;
-- (3) 回滚；sp2 仍存在

RELEASE SAVEPOINT sp1;

COMMIT;

-- SQLite 独特语义：SAVEPOINT 可以在无事务时使用
-- 第一个 SAVEPOINT 会隐式开启事务
SAVEPOINT my_outer;  -- 自动开启事务
INSERT INTO t VALUES (1);
SAVEPOINT my_inner;
INSERT INTO t VALUES (2);
RELEASE my_outer;     -- 释放最外层 SAVEPOINT 等同于 COMMIT
                      -- my_inner 被级联释放

-- 同名 SAVEPOINT：新建（栈式，同名并存）
SAVEPOINT x;
INSERT INTO t VALUES (1);
SAVEPOINT x;            -- 推入新的 x 到栈
INSERT INTO t VALUES (2);
ROLLBACK TO x;          -- 弹到栈顶的 x，回滚 (2)
RELEASE x;              -- 释放栈顶 x
ROLLBACK TO x;          -- 找到下一个 x，回滚 (1)
RELEASE x;              -- 释放最后的 x
```

SQLite 的 SAVEPOINT 实现通过 journal 文件：每个保存点记录当前 journal 位置。ROLLBACK TO 根据 journal 回放。

### CockroachDB（经过漫长演进）

CockroachDB 的保存点支持经历了漫长演进：

- **19.2 之前**：仅支持特殊的 `cockroach_restart` 内置保存点（用于序列化重试）
- **20.1 (2020)**：全面支持 SQL:1999 标准 SAVEPOINT / ROLLBACK TO / RELEASE（GA）
- **20.2+**：支持嵌套保存点

```sql
-- 早期的 cockroach_restart 模式（仍兼容）
BEGIN;
SAVEPOINT cockroach_restart;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
-- 如果遇到 40001 serialization_failure 错误：
ROLLBACK TO SAVEPOINT cockroach_restart;
-- 重试事务
COMMIT;

-- 现代通用保存点（20.1+）
BEGIN;
INSERT INTO orders VALUES (1);
SAVEPOINT sp1;
INSERT INTO orders VALUES (2);
ROLLBACK TO SAVEPOINT sp1;
COMMIT;
```

CockroachDB 的分布式特性使得保存点实现更复杂：
- ROLLBACK TO 需要撤销分布式写入的时间戳
- RELEASE 需要与分布式事务协调器同步
- 序列化失败时的保存点处理需要特殊考虑

### TiDB（2022 年才支持）

TiDB 从 6.2.0 (2022 年 8 月) 开始支持 SAVEPOINT。此前任何版本都不支持：

```sql
-- TiDB 6.2+
BEGIN;
INSERT INTO orders VALUES (1);
SAVEPOINT sp1;
INSERT INTO orders VALUES (2);
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
COMMIT;

-- TiDB 的已知限制：
-- 1. 悲观事务模式下支持
-- 2. 乐观事务模式下也支持（但回滚成本较高，因为需要撤销内存事务缓冲区）
-- 3. 与 TiFlash 副本交互：ROLLBACK TO 不影响 TiFlash 的读
-- 4. 不支持跨 SQL 语句（autocommit 模式下）

-- TiDB 的 SAVEPOINT 实现细节：
-- - 基于内存事务缓冲区的状态快照
-- - ROLLBACK TO 撤销缓冲区中的写入
-- - 不涉及 TiKV 层的额外 RPC
```

TiDB 长期不支持 SAVEPOINT 的原因与其两阶段提交架构有关：悲观事务的实现较复杂。6.2 版本的支持填补了 MySQL 兼容性的重要一环。

### Snowflake（不支持，用存储过程替代）

Snowflake 不支持 SAVEPOINT。官方推荐使用存储过程 + 异常处理：

```sql
CREATE OR REPLACE PROCEDURE transfer_with_retry(
    from_id INT, to_id INT, amt NUMBER
)
RETURNS STRING
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
var conn = snowflake.createStatement({sqlText: 'BEGIN'}); conn.execute();
try {
    var stmt1 = snowflake.createStatement({
        sqlText: 'UPDATE accounts SET balance = balance - ? WHERE id = ?',
        binds: [AMT, FROM_ID]
    });
    stmt1.execute();
    var stmt2 = snowflake.createStatement({
        sqlText: 'UPDATE accounts SET balance = balance + ? WHERE id = ?',
        binds: [AMT, TO_ID]
    });
    stmt2.execute();
    snowflake.createStatement({sqlText: 'COMMIT'}).execute();
    return 'success';
} catch(err) {
    snowflake.createStatement({sqlText: 'ROLLBACK'}).execute();
    return 'failed: ' + err.message;
}
$$;

-- Snowpark Scripting 的 TRY ... CATCH 块
EXECUTE IMMEDIATE $$
BEGIN
    BEGIN TRANSACTION;
    UPDATE t1 SET x = 1;
    -- 无 SAVEPOINT；只能选择全部回滚或全部提交
    COMMIT;
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RAISE;
END;
$$;
```

Snowflake 的无保存点设计与其架构相关：
- 存储计算分离，每个微分区独立写入
- 事务语义偏向批量操作
- 没有传统 undo log 可以回放到中间状态

### BigQuery / ClickHouse / Trino（OLAP 引擎普遍不支持）

这些引擎的事务模型限制：

**BigQuery**：DML 以单语句事务为主。多语句事务 (2022 年推出) 不支持 SAVEPOINT。
```sql
BEGIN TRANSACTION;
  INSERT INTO orders VALUES (1);
  INSERT INTO orders VALUES (2);
  -- 无法 SAVEPOINT
COMMIT TRANSACTION;
```

**ClickHouse**：实验性 Transactions (v22.3+) 仅支持 BEGIN/COMMIT/ROLLBACK，无 SAVEPOINT。
```sql
-- 实验性事务（需开启 allow_experimental_transactions）
BEGIN TRANSACTION;
  INSERT INTO t VALUES (1), (2);
COMMIT;
```

**Trino / Presto**：连接器相关。多数连接器（Hive/Iceberg/Kafka）只支持写入级别事务，无 SAVEPOINT。

**Spark SQL / Databricks**：Delta Lake 支持 ACID 事务，但以文件级别而非行级别。不支持 SAVEPOINT。

**Flink SQL**：流式 SQL 引擎，exactly-once 语义通过 checkpoint 实现，概念上与 SAVEPOINT 不同。

### DuckDB（0.7+ 完整支持）

```sql
BEGIN TRANSACTION;
INSERT INTO t VALUES (1);
SAVEPOINT sp1;
INSERT INTO t VALUES (2);
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
COMMIT;

-- DuckDB 的实现基于行级 undo log
-- 单机嵌入式场景下，保存点开销极小
-- 嵌套深度无硬限制
```

### OceanBase（4.0+ 完整支持）

```sql
-- MySQL 兼容模式
BEGIN;
INSERT INTO t VALUES (1);
SAVEPOINT sp1;
INSERT INTO t VALUES (2);
ROLLBACK TO SAVEPOINT sp1;
RELEASE SAVEPOINT sp1;
COMMIT;

-- Oracle 兼容模式（OceanBase 独有）
-- 支持 Oracle 语法 SAVEPOINT（无 RELEASE）
-- 支持 PL/SQL 异常处理中的保存点
```

### YugabyteDB（继承 PostgreSQL）

YugabyteDB 基于 PostgreSQL 10.4 fork，保存点语法完全继承 PG。内部实现为分布式子事务：每个 SAVEPOINT 分配独立的 TxnStatusTablet 条目。

### Firebird / Interbase

Firebird 从 1.5 开始支持 SAVEPOINT，语法标准：

```sql
SET TRANSACTION;
INSERT INTO t VALUES (1);
SAVEPOINT sp1;
INSERT INTO t VALUES (2);
ROLLBACK TO sp1;
RELEASE SAVEPOINT sp1;
COMMIT;

-- PSQL 异常处理中的隐式保存点
CREATE PROCEDURE safe_insert(p_val INT)
AS
BEGIN
    INSERT INTO t VALUES (:p_val);
    WHEN ANY DO
    BEGIN
        -- 异常处理；原子回滚进入块前的状态
        INSERT INTO error_log VALUES (:p_val, 'failed');
    END
END;
```

### Vertica / SAP HANA / Informix / H2 / HSQLDB / Derby

这些引擎都提供符合 SQL:1999 的 SAVEPOINT/ROLLBACK TO/RELEASE 三元组，语义基本一致，差异主要在：

- 嵌套深度限制（多数为内存限制）
- 同名语义（多数为替换）
- 与分布式事务的交互

## 嵌套事务：误解与真相

SAVEPOINT 常被称为 "nested transactions"，但这是**误称**。真正的嵌套事务应该支持：
- 子事务独立提交与回滚
- 子事务的隔离级别独立设置
- 子事务失败不影响父事务

PostgreSQL 的子事务**最接近**真正的嵌套事务（但仍非完整嵌套）；其他引擎的 SAVEPOINT 只是"部分回滚点"。

### SQL Server 的伪嵌套事务

```sql
BEGIN TRAN;    -- 外层事务
    -- 操作
    BEGIN TRAN;  -- "嵌套"事务（@@TRANCOUNT++）
        -- 操作
        ROLLBACK TRAN;  -- 回滚所有嵌套层！@@TRANCOUNT = 0
    -- 此时再 COMMIT 会报错
COMMIT TRAN;  -- 错误：没有活跃事务
```

SQL Server 的 BEGIN TRAN / COMMIT TRAN 嵌套**只是计数器**：只有最外层 COMMIT 真正提交；任何 ROLLBACK 都回滚所有层。这是常见的误用陷阱。

### 真正的嵌套事务：DB2 BEGIN ATOMIC

DB2 的 `BEGIN ATOMIC` 块提供最接近真正嵌套事务的语义：

```sql
CREATE PROCEDURE outer_proc()
BEGIN
    INSERT INTO t VALUES (1);
    
    BEGIN ATOMIC    -- 嵌套原子块
        INSERT INTO t VALUES (2);
        INSERT INTO t VALUES (3);
        -- 内部块原子执行，失败整体回滚
    END;
    
    INSERT INTO t VALUES (4);
END;
```

## 实际应用场景

### 场景 1：批量插入的局部错误恢复

```sql
-- PostgreSQL 示例：批量加载，单行失败不影响其他
BEGIN;
FOR each row IN batch LOOP
    SAVEPOINT sp_row;
    BEGIN
        INSERT INTO target_table VALUES (row.*);
    EXCEPTION
        WHEN unique_violation THEN
            ROLLBACK TO SAVEPOINT sp_row;
            INSERT INTO error_log VALUES (row.id, 'duplicate');
        WHEN OTHERS THEN
            ROLLBACK TO SAVEPOINT sp_row;
            INSERT INTO error_log VALUES (row.id, SQLERRM);
    END;
    RELEASE SAVEPOINT sp_row;
END LOOP;
COMMIT;

-- 性能提示：PostgreSQL 中应优先用 INSERT ... ON CONFLICT
-- 每行一个 SAVEPOINT 在大批量时会严重影响性能（subxid overflow）
INSERT INTO target_table SELECT * FROM source
ON CONFLICT (id) DO NOTHING;
```

### 场景 2：ORM 与 Spring @Transactional(NESTED)

```java
// Spring 的嵌套事务传播
@Transactional(propagation = Propagation.REQUIRED)
public void outerMethod() {
    // 外层事务
    doWork1();
    try {
        innerMethod();  // 失败时只回滚内层
    } catch (Exception e) {
        log.error("inner failed", e);
    }
    doWork2();
}

@Transactional(propagation = Propagation.NESTED)
public void innerMethod() {
    // Spring 在 JDBC 层调用 connection.setSavepoint()
    // 抛异常时调用 connection.rollback(savepoint)
    // 正常返回时调用 connection.releaseSavepoint(savepoint)
    doRiskyWork();
}
```

Spring 的 `NESTED` 传播模式底层就是 JDBC 的 `Connection.setSavepoint()` + `rollback(Savepoint)` + `releaseSavepoint(Savepoint)`。

### 场景 3：JDBC API 的保存点

```java
// JDBC 3.0 (2002) 引入 Savepoint 接口
Connection conn = dataSource.getConnection();
conn.setAutoCommit(false);
try {
    stmt.executeUpdate("INSERT INTO t VALUES (1)");
    
    Savepoint sp = conn.setSavepoint("before_risky");
    try {
        stmt.executeUpdate("INSERT INTO t VALUES (2)");
    } catch (SQLException e) {
        conn.rollback(sp);  // 只回滚 (2)
    }
    
    conn.releaseSavepoint(sp);
    conn.commit();
} catch (SQLException e) {
    conn.rollback();
}
```

### 场景 4：PL/pgSQL 循环中的容错

```sql
CREATE FUNCTION import_data() RETURNS INTEGER AS $$
DECLARE
    rec RECORD;
    success_count INTEGER := 0;
BEGIN
    FOR rec IN SELECT * FROM staging LOOP
        BEGIN  -- 每次循环开启隐式子事务（隐式 SAVEPOINT）
            INSERT INTO target VALUES (rec.id, rec.data);
            success_count := success_count + 1;
        EXCEPTION
            WHEN OTHERS THEN
                -- 子事务自动回滚，外层事务继续
                CONTINUE;
        END;
    END LOOP;
    RETURN success_count;
END;
$$ LANGUAGE plpgsql;
```

**⚠️ 性能警告**：如果 staging 有 100 万行，上述模式会创建 100 万个子事务，导致 pg_subtrans 严重瓶颈。对于大批量，应改用：
```sql
INSERT INTO target (id, data)
SELECT id, data FROM staging
ON CONFLICT (id) DO NOTHING;
```

## Oracle PL/SQL EXCEPTION 的隐式保存点

Oracle 的 PL/SQL 异常处理机制有两个层次的隐式保存点：

### 语句级原子性（statement-level rollback）

```sql
-- Oracle 每个 DML 语句执行前创建隐式保存点
-- 语句失败时自动回滚该语句
BEGIN
    INSERT INTO t VALUES (1);         -- 成功
    UPDATE t SET x = 'invalid';       -- 失败
    -- 自动回滚 UPDATE，但 INSERT (1) 仍保留
    INSERT INTO t VALUES (2);         -- 继续执行
END;
/
-- 最终：t = {1, 2}（如果后续 COMMIT）
```

### PL/SQL 块级异常处理

```sql
-- PL/SQL BEGIN/EXCEPTION 本身不创建隐式保存点
-- 需要手动 SAVEPOINT 实现块级原子性
CREATE PROCEDURE transfer_with_retry(
    p_from INT, p_to INT, p_amt NUMBER
) AS
BEGIN
    SAVEPOINT sp_before;  -- 手动保存点
    UPDATE accounts SET balance = balance - p_amt WHERE id = p_from;
    UPDATE accounts SET balance = balance + p_amt WHERE id = p_to;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO SAVEPOINT sp_before;  -- 只回滚本过程内的修改
        INSERT INTO error_log VALUES (p_from, p_to, p_amt, SQLERRM);
        COMMIT;  -- 提交错误日志
END;
/
```

### PostgreSQL vs Oracle：PL/SQL 异常块的关键区别

```sql
-- PostgreSQL：BEGIN/EXCEPTION 自动创建隐式子事务
CREATE FUNCTION pg_example() RETURNS VOID AS $$
BEGIN
    INSERT INTO t VALUES (1);  -- 在隐式子事务中
    RAISE EXCEPTION 'test';
EXCEPTION
    WHEN OTHERS THEN
        INSERT INTO log VALUES ('caught');
        -- 此时 (1) 已被自动回滚
END;
$$ LANGUAGE plpgsql;
-- 最终：t = {}，log = {'caught'}

-- Oracle：BEGIN/EXCEPTION 不自动创建隐式保存点
CREATE PROCEDURE orcl_example AS
BEGIN
    INSERT INTO t VALUES (1);  -- 在外层事务中
    RAISE_APPLICATION_ERROR(-20001, 'test');
EXCEPTION
    WHEN OTHERS THEN
        INSERT INTO log VALUES ('caught');
        -- 此时 (1) 仍然保留（EXCEPTION 不自动回滚）
END;
/
-- 最终：t = {1}，log = {'caught'}
-- 除非在 EXCEPTION 块中显式 ROLLBACK 或 ROLLBACK TO SAVEPOINT
```

这是 PostgreSQL 和 Oracle 的关键行为差异。PostgreSQL 的自动子事务更符合"异常安全"直觉，但也是子事务性能问题的根源。

## PostgreSQL 子事务性能深入分析

### 子事务 overflow 问题

PostgreSQL 每个后端进程的 PGPROC 结构有 `subxid cache`，默认大小 64：

```c
// src/include/storage/proc.h (简化)
typedef struct PGPROC {
    TransactionId xid;
    int nxids;                    // 当前活跃子事务数
    TransactionId subxids[64];    // 子事务 XID 缓存
    bool overflowed;              // 是否溢出（超过 64 个）
    ...
} PGPROC;
```

当子事务数超过 64：
1. `overflowed` 标志设为 true
2. 快照构建时，需要扫描 pg_subtrans SLRU 判断可见性
3. 性能大幅下降（可能 10-100 倍）

### pg_subtrans SLRU 瓶颈

```
pg_subtrans 是一个 SLRU（Simple LRU）结构：
- 每条记录 4 字节（父事务 XID）
- 缓冲区默认 32 个页（约 256KB）
- 命中率低时触发磁盘 I/O

高频子事务场景（如大循环中的 EXCEPTION 块）：
- 每秒数千次子事务创建
- SLRU 缓冲频繁换出
- 磁盘 I/O 成为瓶颈
```

### 实际案例：GitLab 的子事务性能问题

GitLab 2021 年曾公开报告 PostgreSQL 子事务性能问题：高并发下 CPU 100% 但吞吐下降。根因是 Rails ActiveRecord 的 `transaction { ... }` 嵌套调用使用 SAVEPOINT，并发量大时触发 subxid overflow。GitLab 的缓解方案包括：
1. 将嵌套事务展平（避免 SAVEPOINT）
2. 调大 pg_subtrans SLRU 缓冲
3. 使用 `PROPAGATION_REQUIRED` 而非 `PROPAGATION_NESTED`

### 何时避免 PostgreSQL 子事务

**避免使用子事务的场景**：
- 大循环中每次迭代都 BEGIN/EXCEPTION（改用批量操作）
- 高并发 OLTP 场景
- 嵌套深度超过 10 层

**仍可安全使用的场景**：
- 低频调用的业务逻辑
- 单次事务内 < 64 个保存点
- 错误恢复是核心需求（如批量导入）

## 与分布式事务的交互

### XA 事务中的保存点

```sql
-- DB2 / MySQL XA 事务中的限制
XA START 'xid_123';
    INSERT INTO t1 VALUES (1);
    SAVEPOINT sp1;        -- XA 分支内的保存点
    INSERT INTO t1 VALUES (2);
    ROLLBACK TO sp1;      -- 可以
XA END 'xid_123';
XA PREPARE 'xid_123';
-- PREPARE 后：保存点不能跨 PREPARE 边界使用
XA COMMIT 'xid_123';

-- MySQL 在 XA 分支的 PREPARE 阶段之前允许 SAVEPOINT
-- PREPARE 之后：XA 分支必须整体提交或整体回滚
```

### 两阶段提交（2PC）与 SAVEPOINT

Java EE / JTA 的 XAResource 接口不提供 SAVEPOINT API。保存点只能在 XA 分支的**本地**事务阶段使用：分支内部可以有 SAVEPOINT，但跨分支协调仅限于 prepare/commit。

### CockroachDB / TiDB 分布式 SAVEPOINT

CockroachDB 的 SAVEPOINT 实现需要与分布式事务协调器（Txn Coordinator）同步：
- ROLLBACK TO 需要撤销已广播到 Range 的意向写入（intent）
- 嵌套保存点增加 coordinator 状态机复杂度
- 高冲突场景下，保存点回滚可能引发额外的冲突检测

## 错误处理模式

### 模式 1：单保存点重试

```sql
-- PostgreSQL / MySQL 通用模式
BEGIN;
SAVEPOINT attempt;
DO operation;
IF error THEN
    ROLLBACK TO SAVEPOINT attempt;
    -- 尝试其他方案
END IF;
COMMIT;
```

### 模式 2：嵌套保存点 + try/catch

```sql
-- SQL Server 模式
BEGIN TRY
    BEGIN TRAN;
    SAVE TRAN sp_outer;
    
    BEGIN TRY
        SAVE TRAN sp_inner;
        -- 高风险操作
    END TRY
    BEGIN CATCH
        IF XACT_STATE() = 1  -- 事务仍可恢复
            ROLLBACK TRAN sp_inner;
    END CATCH;
    
    COMMIT;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK;
END CATCH;
```

### 模式 3：Oracle autonomous transaction + SAVEPOINT

Oracle 的 `PRAGMA AUTONOMOUS_TRANSACTION` 提供独立事务，与 SAVEPOINT 结合使用：

```sql
CREATE PROCEDURE log_error(p_msg VARCHAR2) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO error_log VALUES (p_msg, SYSDATE);
    COMMIT;  -- 独立提交，不影响调用者事务
END;
/

CREATE PROCEDURE business_op AS
BEGIN
    SAVEPOINT sp_start;
    UPDATE orders SET status = 'processing';
    -- 失败
    ROLLBACK TO SAVEPOINT sp_start;
    log_error('业务失败');  -- autonomous，独立写入
END;
/
```

## 引擎实现建议

### 1. 保存点的存储层支持

```
基于 undo log 的引擎（Oracle/MySQL InnoDB/DB2）：
  - SAVEPOINT 记录当前 undo log 位置 (LSN)
  - ROLLBACK TO 遍历 undo 链，应用反向操作到 LSN
  - RELEASE 仅删除保存点标记，undo 继续保留到事务结束
  - 性能：O(被回滚的操作数)

基于子事务的引擎（PostgreSQL/YugabyteDB）：
  - 每个 SAVEPOINT 分配新的 virtual XID
  - MVCC 可见性通过 pg_subtrans 父子关系判断
  - ROLLBACK TO 将子事务标记为 aborted
  - RELEASE 合并子事务 XID 到父事务
  - 性能：O(1) for SAVEPOINT/RELEASE；O(扫描活跃元组) for ROLLBACK TO

基于内存缓冲区的引擎（SQLite/DuckDB）：
  - SAVEPOINT 记录当前事务缓冲区快照
  - ROLLBACK TO 丢弃缓冲区中的修改
  - RELEASE 仅删除快照标记
  - 性能：极快（单机嵌入式）
```

### 2. 并发正确性

```
保存点不影响并发控制（锁/MVCC）的正确性，但实现需注意：

锁保留：
  - SAVEPOINT 期间获取的锁，ROLLBACK TO 时是否释放？
  - SQL 标准：实现自由；大多数引擎保留锁直到事务结束
  - DB2 显式提供 ON ROLLBACK RETAIN LOCKS / RELEASE LOCKS

MVCC 可见性：
  - 子事务的修改对外部事务不可见（直到父事务提交）
  - 对自身子事务可见（按嵌套层次）
  - ROLLBACK TO 后，回滚的修改立即对自身不可见
```

### 3. 快照与可见性的互动

```
PostgreSQL 的子事务 XID 分配与快照：
  1. BEGIN → 分配主 XID
  2. SAVEPOINT → 分配子 XID，记录到 pg_subtrans
  3. 其他事务构建快照时：
     - 活跃事务列表包含主 XID
     - 不直接包含子 XID（避免快照膨胀）
     - 可见性判断时递归查 pg_subtrans
  4. 性能隐患：pg_subtrans 缓冲不足时成为瓶颈

优化建议：
  - 尽量避免深层嵌套（> 10 层）
  - 批量场景避免每行一个 SAVEPOINT
  - 监控 pg_subtrans SLRU 命中率
```

### 4. WAL/Redo 日志的保存点记录

```
SAVEPOINT 本身通常不写 WAL（保存点是内存状态）
但部分引擎在 recovery 时需要重建保存点状态：

场景：事务中途 crash
  - 基于 undo log 的引擎：recovery 时重放到事务开始，所有保存点消失
  - 基于子事务的引擎：recovery 时根据 clog 重建子事务状态

复制场景：
  - PostgreSQL 物理复制：WAL 包含子事务记录，standby 重建子事务链
  - MySQL 逻辑复制 (ROW 格式)：SAVEPOINT 不直接记录到 binlog
    仅最终的 DML 语句（按最终状态）出现在 binlog
```

### 5. 对优化器的影响

```
保存点不改变查询优化决策，但可能影响：

统计信息：
  - ROLLBACK TO 之前的 INSERT/DELETE 可能已更新 autoanalyze 计数
  - 回滚后统计数据可能与实际不一致

执行计划缓存：
  - 保存点本身不使计划缓存失效
  - 但事务中的 DDL 仍使相关计划失效

并发读（快照隔离）：
  - 其他事务看不到未提交的子事务修改
  - 子事务的回滚对其他事务完全透明
```

## 设计争议

### 1. 保存点是否应该支持并发分支？

标准的 SAVEPOINT 是**栈式**的：ROLLBACK TO 会销毁其后所有保存点。有学术研究提出"树形事务"（nested transactions 真实含义），但工业界几乎无人实现。

### 2. 同名保存点的语义

三种流派：
- **替换** (MySQL/Oracle/SQL Server/DB2/大多数)：新 SAVEPOINT 销毁旧同名
- **覆盖** (PostgreSQL)：新 SAVEPOINT 遮蔽旧同名，旧的仍然存在
- **栈式** (SQLite)：新 SAVEPOINT 推入栈，可以多个同名共存

SQL:1999 标准语焉不详，导致迁移陷阱。

### 3. 为什么 SQL Server 不支持 RELEASE SAVEPOINT？

历史原因：SQL Server 的 SAVE TRANSACTION 是 Sybase 时代继承的设计，早于 SQL:1999 标准。微软选择保持向后兼容而非增加 RELEASE。实际影响有限：大多数场景下只需要 ROLLBACK TO，RELEASE 只在**需要显式释放资源**时有用（PostgreSQL 等引擎中 RELEASE 也可以用来释放子事务的 XID）。

### 4. 为什么 OLAP 引擎普遍不支持？

OLAP 引擎的设计哲学：
- 偏向批量操作和只读查询
- 分析型查询不需要细粒度回滚
- 存储格式（列存、不可变文件）难以支持部分回滚
- 一致性保证级别较低（常是最终一致）

Snowflake / BigQuery / ClickHouse 等引擎即使添加事务支持，也多为粗粒度的全事务回滚。

## 总结对比矩阵

### 保存点支持能力总览

| 能力 | PostgreSQL | MySQL/InnoDB | Oracle | SQL Server | DB2 | SQLite | CockroachDB | TiDB | Snowflake | BigQuery |
|------|-----------|-------------|--------|-----------|-----|--------|-------------|------|-----------|----------|
| SAVEPOINT | 是 | 是 | 是 | SAVE TRAN | 是 | 是 | 是 | 是 | -- | -- |
| ROLLBACK TO | 是 | 是 | 是 | 是 | 是 | 是 | 是 | 是 | -- | -- |
| RELEASE | 是 | 是 | -- | -- | 是 | 是 | 是 | 是 | -- | -- |
| 嵌套深度 | 软限 | 无硬限 | UGA 限 | 无硬限 | 无硬限 | 无硬限 | 无硬限 | 无硬限 | -- | -- |
| 隐式保存点 (异常) | PL/pgSQL | 语句级 | 语句级+PL/SQL | 否 | BEGIN ATOMIC | 否 | 语句级 | 否 | -- | -- |
| XA 支持 | 部分 | 有限 | 是 | 是 | 有限 | 否 | 否 | 否 | -- | -- |
| 同名语义 | 覆盖 | 替换 | 替换 | 替换 | 可配置 | 栈式 | 替换 | 替换 | -- | -- |
| COMMIT AND CHAIN | 是 | 是 | -- | -- | -- | -- | -- | -- | -- | -- |

### 引擎选型建议

| 场景 | 推荐引擎/策略 | 原因 |
|------|-------------|------|
| 高保真嵌套事务语义 | PostgreSQL + 适度嵌套 | 子事务最接近真实嵌套 |
| 批量导入容错 | MySQL/InnoDB + SAVEPOINT / PG + ON CONFLICT | InnoDB 低开销 |
| ORM 框架 (Spring NESTED) | 任何 JDBC 3.0+ 支持的引擎 | JDBC API 通用 |
| PL/SQL 存储过程 | Oracle SAVEPOINT + 手动 | 语句级原子性 + 显式块级 |
| 嵌入式/移动端 | SQLite | 轻量，开销极小 |
| 分布式事务 | DB2 / CockroachDB 20.1+ | 支持 XA / 分布式保存点 |
| 分析型 (OLAP) | -- (SAVEPOINT 无意义) | 用批量重试替代 |
| 流处理 | Flink Checkpoint | 概念上类似但不同 |

### 常见陷阱一览

| 陷阱 | 引擎 | 应对 |
|------|------|------|
| SAVE TRAN 不支持 RELEASE | SQL Server | 不需要显式释放；仅作为回滚点 |
| BEGIN TRAN 嵌套只是计数 | SQL Server | 用 SAVE TRAN 实现嵌套 |
| EXCEPTION 不自动回滚 | Oracle | 显式 SAVEPOINT + ROLLBACK TO |
| 子事务 overflow | PostgreSQL | 避免大循环 SAVEPOINT，改用批量 |
| autocommit 下立即失效 | MySQL | 显式 START TRANSACTION |
| XACT_ABORT=ON 吞掉保存点 | SQL Server | 设置 XACT_ABORT=OFF 或精细错误处理 |
| 同名 SAVEPOINT 语义差异 | 跨引擎 | 避免同名，用唯一名字 |
| XA PREPARE 后禁用 | 多数 | PREPARE 前处理保存点 |
| 触发器中 ROLLBACK 炸事务 | SQL Server | 谨慎在触发器中回滚 |
| ClickHouse/OLAP 不支持 | 多数 OLAP | 改用批量重试 |

## 关键发现

1. **保存点是 SQL:1999 标准**，但各引擎实现差异显著：三语句（SAVEPOINT/ROLLBACK TO/RELEASE）完整支持的只有约 22 个引擎，SQL Server/Azure Synapse 缺 RELEASE，Oracle 缺 RELEASE。

2. **PostgreSQL 的子事务是双刃剑**：MVCC 架构让它成为少数真正接近"嵌套事务"语义的引擎，但高频子事务触发 pg_subtrans 瓶颈，是 GitLab/Rails 等生态已知痛点。

3. **MySQL InnoDB 的实现最"经济"**：基于 undo log 记录位置，无独立子事务，开销远小于 PostgreSQL，但也不提供真正的嵌套事务语义。

4. **OLAP 引擎普遍不支持**：Snowflake、BigQuery、ClickHouse、Redshift、Trino、Spark SQL、Flink、Databricks 均无 SAVEPOINT。这反映 OLAP 的批量事务哲学。

5. **TiDB 6.2 (2022) 才补齐**：此前作为 MySQL 兼容数据库，TiDB 长期不支持 SAVEPOINT，使得依赖嵌套事务的应用（如 Spring NESTED）无法使用。CockroachDB 的保存点从 19.2 的特殊重试用途演进到 20.1 的标准支持。

6. **Oracle 和 PostgreSQL 的异常处理语义相反**：PostgreSQL BEGIN/EXCEPTION 隐式创建子事务（异常自动回滚块内修改）；Oracle BEGIN/EXCEPTION 不自动回滚，需手动 SAVEPOINT + ROLLBACK TO。

7. **Spring @Transactional(NESTED) = JDBC Savepoint**：几乎所有 ORM 的"嵌套事务传播"都是 JDBC 保存点的封装。如果底层数据库不支持 SAVEPOINT（如 Snowflake/BigQuery），NESTED 会退化为 REQUIRED 或报错。

8. **SQL Server 的 SAVE TRANSACTION 有多重陷阱**：没有 RELEASE、BEGIN TRAN 嵌套只是计数器、XACT_ABORT=ON 模式下几乎失效、触发器中 ROLLBACK 会爆炸。

9. **保存点性能模型差异巨大**：MySQL InnoDB (O(1))、SQLite (O(1))、PostgreSQL (子事务开销随深度增加)、CockroachDB (分布式协调开销)、DuckDB (内存嵌入式最快)。

10. **分布式事务 (XA) 对保存点的限制**：XA PREPARE 后大多数引擎禁止保存点操作；保存点无法跨 XA 分支。需要跨服务事务时，保存点只在单分支内有效。

## 参考资料

- SQL:1999 标准: ISO/IEC 9075-2, Section 17.9–17.11 (SAVEPOINT / ROLLBACK TO SAVEPOINT / RELEASE SAVEPOINT)
- PostgreSQL: [SAVEPOINT](https://www.postgresql.org/docs/current/sql-savepoint.html)
- PostgreSQL: [Subtransactions and performance (wiki)](https://wiki.postgresql.org/wiki/Slow_Counting#Counting_rows_in_subtransactions)
- MySQL: [SAVEPOINT, ROLLBACK TO SAVEPOINT, and RELEASE SAVEPOINT Statements](https://dev.mysql.com/doc/refman/8.0/en/savepoint.html)
- Oracle: [SAVEPOINT Statement](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/SAVEPOINT.html)
- SQL Server: [SAVE TRANSACTION (Transact-SQL)](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/save-transaction-transact-sql)
- DB2: [SAVEPOINT statement](https://www.ibm.com/docs/en/db2-for-zos/12?topic=statements-savepoint)
- SQLite: [SAVEPOINT](https://www.sqlite.org/lang_savepoint.html)
- CockroachDB: [SAVEPOINT](https://www.cockroachlabs.com/docs/stable/savepoint)
- TiDB: [SAVEPOINT](https://docs.pingcap.com/tidb/stable/sql-statement-savepoint) (6.2+)
- JDBC 3.0: Savepoint Interface (Java SE 1.4+)
- Gray, J. & Reuter, A. "Transaction Processing: Concepts and Techniques" (1993), Chapter 11
- Spring Framework: [Transaction Propagation](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-propagation.html)
- GitLab PostgreSQL subtransaction issue: [gitlab/gitlab#284227](https://gitlab.com/gitlab-org/gitlab/-/issues/284227)
