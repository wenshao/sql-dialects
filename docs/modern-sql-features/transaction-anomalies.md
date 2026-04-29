# 事务异常 (Transaction Anomalies)

> 参考资料:
> - [A Critique of ANSI SQL Isolation Levels (Berenson et al., 1995)](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/tr-95-51.pdf)
> - [Weak Consistency: A Generalized Theory and Optimistic Implementations for Distributed Transactions (Adya, 1999, MIT PhD Thesis)](https://pmg.csail.mit.edu/papers/adya-phd.pdf)
> - [Serializable Isolation for Snapshot Databases (Cahill et al., SIGMOD 2008)](https://courses.cs.washington.edu/courses/cse444/08au/544M/READING-LIST/fekete-sigmod2008.pdf)
> - [PostgreSQL Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
> - [Designing Data-Intensive Applications, Chapter 7 (Kleppmann, 2017)](https://dataintensive.net/)

ANSI SQL-92 用脏读 / 不可重复读 / 幻读三种异常去定义隔离级别，但 1995 年 Berenson 等人发表的《A Critique of ANSI SQL Isolation Levels》指出：这套定义遗漏了 **Lost Update**、**Read Skew**、**Write Skew** 等真实生产中频繁发生的异常族。其中 **写偏斜 (Write Skew)** 是 Snapshot Isolation 的"沉默杀手"——两个事务各自合法、合起来违反业务约束，没有任何 SQLSTATE 报错，应用看上去一切正常，直到某天审计时才发现资金透支、值班无人、库存超卖。本文系统梳理 Berenson 1995 + Adya 1999 + Cahill 2008 三篇里程碑工作定义的全部异常分类，并跨 45+ 引擎对比各个隔离级别 (RC / RR / SI / SSI) 对每种异常的防护能力，附带可复现的 SQL 例子与典型错误模式。

本文聚焦"异常本身"——是什么、为什么、各引擎如何防护。隔离级别的语义对比见 `transaction-isolation-comparison.md`；SI / SSI 的实现机制 (SIREAD 锁 / rw-antidependency / 危险结构) 见 `snapshot-isolation-details.md`；版本链 / Read View / undo log 的底层实现见 `mvcc-implementation.md`。

## 异常清单：从 ANSI 到 Adya

### 一句话定义

```
Dirty Write   (脏写, P0/G0):
  T1 先写 x, T2 在 T1 提交前覆盖 T1 的写
  -> 提交顺序与依赖顺序矛盾, 必现错误结果

Dirty Read    (脏读, P1/G1a):
  T1 修改 x, T2 在 T1 commit/rollback 前读到 T1 的未提交修改
  -> T1 若回滚, T2 读到了从未存在的数据

Lost Update   (丢失更新, P4):
  T1 读 x=v, T2 读 x=v, 两者各自基于 v 计算并写回 x
  -> 后写者覆盖先写者, 一个更新逻辑性丢失

Fuzzy Read    (不可重复读, P2/G-single):
  T1 读 x 得 v1, T2 修改并提交 x, T1 再读 x 得 v2 != v1
  -> 同一事务内两次读结果不同

Phantom       (幻读, P3/G-single):
  T1 用谓词 P 查询得集合 S1, T2 INSERT/UPDATE 使新行满足 P 并提交
  T1 再用 P 查询得 S2 != S1
  -> "新行" 在第二次查询中突然出现 (或消失)

Read Skew     (读偏斜, A5A):
  T1 读 x 得 v_x, 然后 T2 修改 x 和 y 并提交,
  T1 再读 y 得 v_y; 此时 (v_x, v_y) 来自两个不同的状态
  -> 应用层基于 x+y 的约束被违反 (但 x, y 单独看都是合法值)

Write Skew    (写偏斜, A5B):
  T1 读 {x, y}, 基于聚合值修改 x; T2 读 {x, y}, 基于聚合值修改 y
  两个事务各自的快照都满足约束, 合并后违反约束
  -> SI 的"沉默杀手"

Predicate Read Anomaly (谓词读异常):
  Adya 形式化: 对一个谓词 P 的两次评估之间, 满足 P 的元组集合发生了变化
  覆盖 Phantom + Write Skew + Read Skew 的更广义异常族

Read-Only Anomaly (只读事务异常, Fekete 2004):
  即使是只读事务在 SI 下也可能看到不一致状态
  T1 (读写), T2 (读写), T3 (只读) 在 SI 下并发执行,
  T3 看到的数据库状态与任何串行执行结果都不等价
```

### Berenson 1995 vs Adya 1999 的命名对照

```
ANSI SQL-92        Berenson 1995             Adya 1999 (依赖图)
─────────────────  ────────────────────────  ──────────────────────────
P0 (隐含)          P0 Dirty Write            G0  ww-cycle
P1 Dirty Read      P1 Dirty Read             G1a aborted reads
                                             G1b intermediate reads
                                             G1c circular info flow
P2 Non-repeat      P2 Fuzzy Read             G2-item single-item rw
P3 Phantom         P3 Phantom                G2 anti-dependency cycles
                   A5A Read Skew             ───┐
                   A5B Write Skew            ─ ─┴─> 都属于 G2 family
                   P4 Lost Update            G-cursor / G-monotonic
                   Snapshot Isolation        PL-SI = G-SIb
                                             PL-3 = G2 (Serializable)
```

**关键观察**：Adya 用 ww/wr/rw 三种依赖边和环路结构定义隔离级别，比 ANSI 的"异常列表"更精确：

```
ww (write-write):  T1 写 x, 然后 T2 写 x (T2 看到 T1 的版本)
wr (write-read):   T1 写 x, 然后 T2 读 x (T2 看到 T1 的版本)
rw (read-write):   T1 读 x_old, 然后 T2 写 x (T2 不看到 T1 的快照)
                   注意 rw 的方向: T1 -> T2 (T1 先, T2 后, 但 T1 看不到 T2)

隔离级别 = 禁止包含特定边的环:
  RU (PL-1):  禁止 G0 (纯 ww 环)
  RC (PL-2):  禁止 G1 (G0 + 中间值/读未提交)
  SI (PL-SI): 禁止 G-SIb (起始 rw + 回到 T1, 但 T1 commit 在 T2 start 后)
  Serializable (PL-3): 禁止任何含 rw 的环 (G2)
```

Cahill 2008 在此基础上证明：**SI 与 Serializable 之间唯一的差异是允许两条相邻的 rw 边形成的环 (dangerous structure)**。这正是 SSI 算法要动态检测和中止的目标。

## 支持矩阵：45+ 引擎 × 异常 × 隔离级别

下表用 `防` 表示该隔离级别在该引擎中防止此异常，`不` 表示允许，`--` 表示该引擎不支持此隔离级别或机制不适用。条目按"引擎 - 隔离级别 - 异常"组织，覆盖核心 OLTP / 分析 / NewSQL / 嵌入式数据库共 45 个。

### Dirty Read / Dirty Write

```
引擎                    RU      RC      RR/SI   SERIALIZABLE
                        Dirty   Dirty   Dirty   Dirty
─────────────────────  ──────  ──────  ──────  ──────────────
MySQL (InnoDB 8.0)     不防(R) 防      防      防
MariaDB                不防    防      防      防
PostgreSQL             防(*1)  防      防      防
Oracle                 --      防      --      防
SQL Server (锁 RC)     不防    防      防(SI)  防
SQL Server (RCSI)      不防    防      防      防
SQLite (WAL)           --      --      --      防
DB2                    不防    防      防      防
TiDB                   --      防      防      防(*2)
CockroachDB            --      防      --      防
OceanBase              不防    防      防      防
YugabyteDB             --      防      防      防
Spanner                --      --      --      防(External Consistency)
Snowflake              --      防      --      --
BigQuery               --      --      --      防
Redshift               --      --      --      防
DuckDB                 --      --      --      防
ClickHouse             无传统事务, 单语句原子性
Vertica                --      --      --      防
SAP HANA               --      防      防      防
Greenplum              不防    防      防      防(SSI)
Trino / Presto         无 ACID 表事务 (除 Iceberg/Hive ACID)
Spark SQL              依赖 Delta/Iceberg, 表级原子
Databricks (Delta)     --      --      --      WriteSerializable
Hive (ACID)            --      --      防      --
Teradata               --      防      --      防(锁实现)
Firebird               --      防      防      防(NOWAIT)
H2                     --      防      防      防
HSQLDB                 --      防      防      防
Derby                  --      防      防      防
Informix               不防    防      防      防
MonetDB                --      --      --      防(OCC)
SingleStore            --      防      防      --
Yellowbrick            --      防      防      防
Exasol                 --      --      --      防
TimescaleDB            继承 PostgreSQL
Aurora (PG)            继承 PostgreSQL
Aurora (MySQL)         继承 MySQL
Azure Synapse          --      防      --      --
Azure SQL DB           不防    防      防      防 (默认 RCSI)
GaussDB                继承 PostgreSQL
Materialize            --      --      --      Strict Serializable
RisingWave             --      --      --      防(Stream-level)
StarRocks / Doris      表级原子, 无传统事务隔离
Crate DB               最终一致, --
Firebolt               单语句原子性
Impala                 依赖底层 (Kudu/Iceberg)

(R) = MySQL READ UNCOMMITTED 真允许脏读 (能看到其他事务未提交的修改)
(*1) PostgreSQL READ UNCOMMITTED 实际行为等同 READ COMMITTED, 不允许脏读
(*2) TiDB SERIALIZABLE 语法接受但映射到 RR/SI (实际是 SI 语义)
```

> 几乎所有引擎在 RC 及以上都防止 Dirty Read。MySQL 是少数允许 RU 真正脏读的主流引擎；PostgreSQL 把 RU 静默升级为 RC。

### Lost Update

Lost Update 是数据库实践中最常见的并发 bug。简单的 `UPDATE balance = balance + 1` 由 SQL 引擎以原子性 read-modify-write 执行，但 `SELECT balance INTO :v; ... v := v + 100; UPDATE balance = :v;` 这种应用层 read-modify-write 模式才是 Lost Update 的高发场景。

```
引擎                    RC      RR/SI                       SERIALIZABLE
                        Lost    Lost                        Lost
─────────────────────  ──────  ──────────────────────────  ──────────────
MySQL (InnoDB)         不防    不防 (默认快照读不防)(*1)   防 (锁实现)
MariaDB                不防    不防                        防
PostgreSQL             不防    防 (FUW, 报 40001)          防 (SSI)
Oracle                 不防    -- (无 RR 级别)             防 (SI 内 FUW)
SQL Server (锁 RC)     不防    防 (S 锁阻塞)               防
SQL Server (RCSI)      防(*2)  防 (SI 冲突检测)            防
SQLite                 --      --                          防 (单写者锁)
DB2                    不防    防                          防
TiDB (悲观默认)        不防(*3) 防                         不防(SI)
CockroachDB            不防    --                          防
OceanBase              不防    不防 (RR 模式)              防
YugabyteDB             不防    防 (RR=SI)                  防
Snowflake              不防    --                          --
BigQuery               --      --                          防 (OCC)
Redshift               --      --                          防 (SSI)
SAP HANA               不防    防                          防
Greenplum              不防    防                          防 (SSI)
Spanner                --      --                          防 (External Consistency)
Vertica                --      --                          防
Databricks (Delta)     --      --                          防 (OCC)
Hive (ACID)            --      防 (写写冲突)               --
Firebird               不防    防 (FCW NOWAIT)             防
H2                     不防    防                          防
HSQLDB                 不防    防                          防
MonetDB                --      --                          防 (OCC)
SingleStore            不防    --                          --
Exasol                 --      --                          防 (OCC)
Aurora (PG)            继承 PostgreSQL
Aurora (MySQL)         继承 MySQL
Azure SQL DB (RCSI)    防(*2)  防                          防

(*1) MySQL/MariaDB 默认 RR 下普通 SELECT 是快照读, 不锁行, 后续 UPDATE 不检查冲突
     -> 经典的 read-modify-write 在应用层会丢失更新
     必须用 SELECT ... FOR UPDATE 锁定行才能防止
(*2) SQL Server RCSI 在 UPDATE 时若读到的版本已过期, 会"重读最新版本", 这一行为
     在某些场景下避免了 Lost Update; 但跨语句的应用层 read-modify-write 仍可能丢失
(*3) TiDB 悲观事务默认在 SELECT FOR UPDATE 时锁定; 普通 SELECT 不锁
```

> **关键差异**：PostgreSQL RR 用 First-Updater-Wins 自动报错 (`could not serialize access due to concurrent update`)；MySQL RR 完全不防，必须显式 `FOR UPDATE`。这是 MySQL → PostgreSQL 迁移时最容易踩的坑之一。

### Phantom Read

```
引擎                    RC      RR/SI                          SERIALIZABLE
                        Phantom Phantom                        Phantom
─────────────────────  ──────  ─────────────────────────────  ──────────────
MySQL (InnoDB)         不防    防 (gap lock + next-key)(*1)   防
MariaDB                不防    防 (gap lock + next-key)        防
PostgreSQL             不防    防 (快照读层面)                防 (SSI)
Oracle                 不防    -- (无 RR)                     防 (SI 快照, 不防 WS)
SQL Server (锁 RC)     不防    --                              防 (range lock)
SQL Server (SI)        --      防 (快照读)                    --
SQLite                 --      --                              防
DB2                    不防    防                              防
TiDB                   不防    防 (快照读)(*2)                 防
CockroachDB            不防    --                              防
OceanBase RR           不防    防                              防
YugabyteDB             不防    防 (快照)                       防
Snowflake              不防    --                              --
Redshift               --      --                              防 (SSI)
BigQuery               --      --                              防 (OCC)
Spanner                --      --                              防 (External Consistency)
SAP HANA               不防    防                              防
Greenplum              不防    防                              防 (SSI 9.1+)
Vertica                --      --                              防
DuckDB                 --      --                              防
H2 (MVCC)              不防    防                              防
HSQLDB                 不防    防                              防
Firebird               不防    防 (快照)                       防
Hive (ACID)            --      防 (快照 + 锁)                  --
Aurora (PG)            继承 PostgreSQL
Aurora (MySQL)         继承 MySQL
Azure SQL DB (RCSI)    不防    防 (SI 启用时)                  防
Materialize            --      --                              防

(*1) MySQL InnoDB RR 是 SQL 标准 RR 的"加强版":
     - 普通 SELECT (快照读): MVCC 自然不见新插入
     - SELECT ... FOR UPDATE / UPDATE / DELETE (当前读): gap lock + next-key lock 阻止 INSERT
     -> 这一双重防护使 MySQL RR 实际上比标准 RR 更接近 Serializable 的幻读防护
(*2) TiDB RR (SI) 只在快照读层面防幻读; 当前读 (SELECT FOR UPDATE) 没有 gap lock,
     可被并发 INSERT 突破 -> 与 MySQL RR 的"双重防护"显著不同 (迁移陷阱)
```

### Write Skew (沉默杀手)

```
引擎                    RC       RR/SI                            SERIALIZABLE
                        WS       WS                               WS
─────────────────────  ──────   ──────────────────────────────   ──────────────
MySQL (InnoDB)         不防     不防 (RR=SI 不防 WS)             防 (锁)
MariaDB                不防     不防                              防
PostgreSQL             不防     不防 (RR=SI)                      防 (SSI 9.1+)
Oracle                 不防     -- (无 RR)                       不防 (*1)
SQL Server (锁 RC)     不防     --                                防
SQL Server (SI)        --       不防                              --
SQL Server SERIALIZABLE --      --                                防 (range lock)
SQLite                 --       --                                防 (单写者)
DB2                    不防     不防                              防
TiDB                   不防     不防 (RR=SI)                      不防 (*2)
CockroachDB            不防     --                                防 (SSI 变体)
OceanBase RR           不防     不防                              防 (悲观锁)
YugabyteDB RR          不防     不防 (RR=SI)                      防 (SSI)
Snowflake              不防     不防 (SI)                         --
Redshift               --       --                                防 (SSI)
BigQuery               --       --                                防 (OCC + 提交时检测)
Spanner                --       --                                防 (External Consistency)
SAP HANA               不防     不防                              防 (可选 SSI)
Greenplum              不防     不防                              防 (SSI 6.x+)
Vertica                --       --                                防
DuckDB                 --       --                                防 (单写者)
MonetDB                --       --                                防 (OCC + commit check)
GaussDB                继承 PostgreSQL
Aurora (PG)            继承 PostgreSQL (含 SSI)
Aurora (MySQL)         继承 MySQL (锁实现 SERIALIZABLE)
Azure SQL DB           不防     不防 (SI)                         防 (range lock)
Materialize            --       --                                防 (Strict Serializable)
RisingWave             --       --                                防

(*1) Oracle SERIALIZABLE 实际是 SI, 不防 WS  -- 这是"名字相同语义不同"的最大陷阱
     应用代码若依赖 Oracle SERIALIZABLE 防 WS, 在生产中会出错
(*2) TiDB SERIALIZABLE 语法接受但映射到 RR (= SI), 不防 WS
```

> **结论**：在 45+ 引擎中，真正在 SERIALIZABLE 级别防 Write Skew 的引擎只有 PostgreSQL (9.1+)、CockroachDB、YugabyteDB、Redshift、SQL Server (range lock)、SQLite (单写)、Spanner、SAP HANA、Greenplum、DB2、MonetDB、Materialize 等少数。Oracle 的 SERIALIZABLE 只是 SI，TiDB 的 SERIALIZABLE 实际是 SI。把"SERIALIZABLE"等同于"防所有异常"是常见错误。

### Read Skew

Read Skew 与 Phantom 的区别：Phantom 是同一谓词两次评估结果集变化；Read Skew 是单事务对**两个不同对象**的两次读返回不一致状态。

```
引擎                    RC       RR/SI    SERIALIZABLE
                        RS       RS       RS
─────────────────────  ──────   ──────   ──────────────
MySQL (InnoDB)         不防     防       防
PostgreSQL             不防     防       防
Oracle                 不防     --       防 (SI)
SQL Server (锁 RC)     不防     --       防
SQL Server (RCSI)      不防     防       防
SQL Server (SI)        --       防       --
TiDB                   不防     防       防 (SI)
CockroachDB            不防     --       防
OceanBase RR           不防     防       防
YugabyteDB             不防     防       防
Snowflake              不防     --       --
Redshift               --       --       防 (SSI)
BigQuery               --       --       防 (OCC)
Spanner                --       --       防
SAP HANA               不防     防       防
Greenplum              不防     防       防
Vertica                --       --       防
DuckDB                 --       --       防
H2 (MVCC)              不防     防       防
HSQLDB                 不防     防       防
Firebird               不防     防       防
Aurora 系              继承
Hive (ACID)            --       防       --

注: Read Skew 是 RR/SI 自动防止的异常 (因为整个事务读同一快照),
    所以只要有 SI 实现, RR 级别就能防 Read Skew。
    只有 RC (语句级快照) 不防 Read Skew。
```

## 异常实例的具体 SQL

下面给出每种异常的最小可复现 SQL 例子。除非另有说明，假设两个并发事务 T1、T2，按时间顺序交错执行。

### Lost Update

```sql
-- 表初始化
CREATE TABLE accounts (id INT PRIMARY KEY, balance INT);
INSERT INTO accounts VALUES (1, 100);

-- 期望: 两个事务各加 100, 最终余额 = 300
-- 实际: 在 RC 下默认会丢失一个更新, 余额 = 200

-- T1                                         T2
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN;                                        BEGIN;
                                              SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT balance FROM accounts WHERE id = 1;
-- 读到 100
                                              SELECT balance FROM accounts WHERE id = 1;
                                              -- 读到 100
-- 应用层计算: new_balance = 100 + 100 = 200
                                              -- 应用层计算: new_balance = 100 + 100 = 200
UPDATE accounts SET balance = 200 WHERE id = 1;
                                              UPDATE accounts SET balance = 200 WHERE id = 1;
COMMIT;
                                              COMMIT;

-- 最终 balance = 200 (而非 300), T1 的更新被丢失
```

**正确写法 1：原子表达式**

```sql
-- 让 SQL 引擎处理 read-modify-write
UPDATE accounts SET balance = balance + 100 WHERE id = 1;
```

**正确写法 2：行锁**

```sql
BEGIN;
SELECT balance FROM accounts WHERE id = 1 FOR UPDATE;  -- 排他锁
-- 应用层计算
UPDATE accounts SET balance = ... WHERE id = 1;
COMMIT;
```

**正确写法 3：乐观并发控制 (CAS)**

```sql
-- 用版本号或 expected value
UPDATE accounts
SET balance = :new_balance, version = version + 1
WHERE id = 1 AND version = :expected_version;
-- 检查 affected rows; 若为 0, 重读并重试
```

### Write Skew (Cahill 值班医生例子)

```sql
-- 表初始化
CREATE TABLE doctors (
    id INT PRIMARY KEY,
    name TEXT,
    on_call BOOLEAN
);
INSERT INTO doctors VALUES (1, 'Alice', TRUE), (2, 'Bob', TRUE);

-- 业务约束: 任何时候至少 1 名医生在岗
-- (即 SUM(on_call::INT) >= 1)

-- T1: Alice 想下班                        T2: Bob 想下班
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN;                                     BEGIN;
                                           SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- T1 检查约束
SELECT COUNT(*) FROM doctors WHERE on_call = TRUE;
-- 返回 2 (Alice 在, Bob 在), 满足约束 >= 1
                                           -- T2 检查约束
                                           SELECT COUNT(*) FROM doctors WHERE on_call = TRUE;
                                           -- 返回 2 (Alice 在, Bob 在), 满足约束 >= 1

-- T1 修改自己
UPDATE doctors SET on_call = FALSE WHERE id = 1;
                                           -- T2 修改自己
                                           UPDATE doctors SET on_call = FALSE WHERE id = 2;

COMMIT;                                    COMMIT;
-- 两者都成功, 但最终 0 名医生在岗 -> 违反约束!
-- 在 SI 下: 两事务的写集合不重叠 ({id=1} vs {id=2}), 没有 ww 冲突, 都通过 FCW/FUW 检测
-- 在真 SERIALIZABLE 下: T2 会被 SSI 检测到 rw-antidependency 环, 报 40001
```

各引擎实测结果：

```
PostgreSQL (RR / SI):    两事务都成功 -> 违反约束 (经典 SI 漏洞)
PostgreSQL (SERIALIZABLE): T2 收到 ERROR 40001 serialization_failure
Oracle (SERIALIZABLE):    两事务都成功 (Oracle SERIALIZABLE = SI, 不防 WS)
MySQL (RR):               两事务都成功 (RR = SI, 不防 WS)
                          但若两事务都用 SELECT ... FOR UPDATE, gap lock 会阻止
MySQL (SERIALIZABLE):     T1 持有 S 锁, T2 的 UPDATE 会等待 -> 串行化
SQL Server (SI):          两事务都成功 -> 违反约束
SQL Server (SERIALIZABLE): T2 等待 T1 的 range lock -> 串行化
CockroachDB (SERIALIZABLE): T2 收到 retry error -> 应用重试
YugabyteDB (SERIALIZABLE): T2 收到 40001
TiDB (SERIALIZABLE):       两事务都成功 (TiDB SERIALIZABLE = SI)
```

**SI 下修复方案**：用约束锚行将 rw 依赖物化为 ww 依赖。

```sql
-- 添加约束锚表
CREATE TABLE doctor_count (k INT PRIMARY KEY, on_call_n INT);
INSERT INTO doctor_count VALUES (1, 2);

-- 修改下班逻辑:
BEGIN;
UPDATE doctor_count SET on_call_n = on_call_n - 1 WHERE k = 1;  -- 强制 ww 序列化
SELECT on_call_n FROM doctor_count WHERE k = 1;
-- 检查 on_call_n >= 1, 否则回滚
UPDATE doctors SET on_call = FALSE WHERE id = 1;
COMMIT;

-- 现在两个并发事务在 doctor_count 上有 ww 冲突, FCW/FUW 自动序列化
```

### Read Skew (跨表求和异常)

```sql
-- 经典银行转账场景: 一个事务查总余额, 另一个事务转账
CREATE TABLE accounts (id INT PRIMARY KEY, balance INT);
INSERT INTO accounts VALUES (1, 500), (2, 500);

-- 业务事实: 总余额恒为 1000

-- T1: 报表事务 (RC, 跨多次查询)        T2: 转账
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN;
SELECT balance FROM accounts WHERE id = 1;
-- 读到 500
                                        BEGIN;
                                        UPDATE accounts SET balance = balance - 200 WHERE id = 1;
                                        UPDATE accounts SET balance = balance + 200 WHERE id = 2;
                                        COMMIT;
SELECT balance FROM accounts WHERE id = 2;
-- 读到 700 (T2 已提交)
COMMIT;
-- T1 看到 (500, 700), 总额 1200 -- 违反恒等约束
-- 这是 Read Skew: 同一报表读到了两个不同时刻的状态
```

**修复方案**：升级到 RR/SI (整个事务一个快照)：

```sql
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;  -- 或 SI
BEGIN;
SELECT balance FROM accounts WHERE id = 1;  -- 500
SELECT balance FROM accounts WHERE id = 2;  -- 500 (快照不见 T2 的更新)
COMMIT;
```

或在单条 SELECT 中合并查询：`SELECT SUM(balance) FROM accounts;`。在 RC 下，单条 SELECT 是语句级原子的（语句开始时取一个快照），不会出现 Read Skew。

### Phantom (幻读)

```sql
-- 业务场景: 检查某个用户没有 pending 订单, 然后插入新订单
CREATE TABLE orders (id SERIAL PRIMARY KEY, user_id INT, status TEXT);

-- T1                                       T2
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN;                                      BEGIN;
                                            SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- T1 检查
SELECT COUNT(*) FROM orders
WHERE user_id = 100 AND status = 'pending';
-- 返回 0
                                            -- T2 检查 (幻读的另一半)
                                            SELECT COUNT(*) FROM orders
                                            WHERE user_id = 100 AND status = 'pending';
                                            -- 返回 0

-- T1 插入
INSERT INTO orders(user_id, status)
VALUES (100, 'pending');
                                            -- T2 插入
                                            INSERT INTO orders(user_id, status)
                                            VALUES (100, 'pending');

COMMIT;                                     COMMIT;
-- 最终: user_id=100 有 2 个 pending 订单, 违反"最多 1 个"约束
```

各引擎实测：

```
PostgreSQL RC:        两事务都成功 -> 2 个 pending (RC 不防幻读)
PostgreSQL RR (SI):   两事务都成功 -> 2 个 pending (SI 不防 phantom-via-insert)
                      因为两事务的 INSERT 都是新行, 不形成 ww 冲突
PostgreSQL SERIALIZABLE: T2 收到 40001 (SSI 检测到 rw-antidependency)
MySQL RR (默认):      若用 SELECT ... FOR UPDATE, gap lock 阻止 INSERT (T2 等待)
                      若用普通 SELECT (快照读), 两事务都成功, 但插入后业务校验仍可能漏防
MySQL SERIALIZABLE:    所有 SELECT 自动加 S 锁, T2 等待 T1
Oracle SERIALIZABLE:   两事务都成功 (SI 不防 phantom-via-insert)
CockroachDB SERIALIZABLE: T2 收到 retry error
SQL Server SERIALIZABLE: range lock 阻止 T2 的 INSERT (T2 等待)
SQL Server SI:         两事务都成功 (SI 不防 phantom-via-insert)
```

**修复方案**：

```sql
-- 方案 1: 使用唯一约束 + ON CONFLICT
CREATE UNIQUE INDEX idx_one_pending_per_user ON orders(user_id)
WHERE status = 'pending';
INSERT INTO orders(user_id, status) VALUES (100, 'pending')
ON CONFLICT DO NOTHING;  -- T2 静默失败

-- 方案 2: 应用层显式锁 (SELECT ... FOR UPDATE on user 表)
SELECT id FROM users WHERE id = 100 FOR UPDATE;
-- 持有 user 行的排他锁, 排他性进入 critical section
SELECT COUNT(*) FROM orders WHERE user_id = 100 AND status = 'pending';
-- ...

-- 方案 3: 使用 SERIALIZABLE (PG SSI / CRDB / 真可串行化引擎)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- SSI 会检测到 rw-antidependency 并中止其中一个事务
```

### Dirty Write

```sql
-- T1                                       T2
BEGIN;                                      BEGIN;
UPDATE accounts SET balance = 100 WHERE id = 1;
                                            UPDATE accounts SET balance = 200 WHERE id = 1;
                                            -- 在锁实现中: T2 等待 T1 的行锁 (常见行为)
                                            -- 在某些 RU 实现中: T2 直接覆盖 (脏写)
COMMIT;                                     COMMIT;

-- 几乎所有现代引擎在所有隔离级别都防止 Dirty Write
-- (通过行级排他锁或版本时间戳)
-- ANSI SQL-92 甚至 RU 也禁止 Dirty Write (P0)
```

### Dirty Read (READ UNCOMMITTED)

```sql
-- 仅在 MySQL/SQL Server/DB2 等支持真 RU 的引擎中演示

-- T1                                       T2
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
BEGIN;                                      BEGIN;
UPDATE accounts SET balance = 999 WHERE id = 1;
                                            SELECT balance FROM accounts WHERE id = 1;
                                            -- MySQL RU: 读到 999 (T1 未提交的修改)
                                            -- PostgreSQL RU: 读到旧值 (RU 实际是 RC)
ROLLBACK;
                                            -- T2 看到的 999 实际从未存在
                                            COMMIT;
```

## 各引擎深度行为分析

### PostgreSQL：默认 RC 允许 Lost Update，RR (SI) 防

PostgreSQL 默认隔离级别是 **READ COMMITTED**，每条语句开始时取一个新快照。这一级别的 Lost Update 行为：

```sql
-- PG RC 下的 Lost Update 演示
CREATE TABLE counter (id INT PRIMARY KEY, n INT);
INSERT INTO counter VALUES (1, 0);

-- T1                                T2
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN;                               BEGIN;
                                     SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

SELECT n FROM counter WHERE id = 1;  -- 读 0
                                     SELECT n FROM counter WHERE id = 1;  -- 读 0
-- 应用层 n2 = 0 + 1 = 1               -- 应用层 n2 = 0 + 1 = 1
UPDATE counter SET n = 1 WHERE id = 1;
                                     UPDATE counter SET n = 1 WHERE id = 1;  -- 等待 T1 行锁
COMMIT;                              -- T1 提交后, T2 的 UPDATE 继续
                                     -- 注意: PG RC 下, T2 重新获取最新版本, 但 n=1 已经写完
                                     -- T2 还是用了"应用层算的 n2=1", 覆盖 T1 的 1 -> 仍然是 1
                                     -- 结果: 计数器从 0 -> 1, 但应该是 0 -> 2, 一个增量被丢失
                                     COMMIT;
```

**PG 的 RC 不防 Lost Update**。但 PG 的 RR (Snapshot Isolation) 防：

```sql
-- T1                                T2
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
BEGIN;                               BEGIN;
                                     SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT n FROM counter WHERE id = 1;  -- 0
                                     SELECT n FROM counter WHERE id = 1;  -- 0
UPDATE counter SET n = 1 WHERE id = 1;
                                     UPDATE counter SET n = 1 WHERE id = 1;
                                     -- 阻塞等待 T1
COMMIT;                              -- T1 提交后, T2 的 UPDATE 报错:
                                     -- ERROR: could not serialize access due to concurrent update
                                     -- SQLSTATE 40001
                                     -- T2 必须重试整个事务
                                     ROLLBACK;
```

PG RR 用 First-Updater-Wins 检测：T2 试图修改一个已被 T1 (在 T2 快照之后) 修改并提交的行，立即报错。这与 MySQL RR 形成鲜明对比 (MySQL RR 不防 Lost Update)。

**PG SERIALIZABLE (SSI) 防所有异常包括 Write Skew**：

```sql
-- 值班医生 Write Skew 在 PG SERIALIZABLE 下:
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- T1: SELECT count, UPDATE alice
-- T2: SELECT count, UPDATE bob

-- T1 提交时, 已记录 SIREAD 锁覆盖 alice 和 bob 行
-- T2 的 UPDATE 形成 rw-antidependency 边
-- 检测到 inConflict + outConflict 同时为 true (危险结构)
-- T2 在 COMMIT 时被中止: ERROR: could not serialize access due to read/write dependencies
-- SQLSTATE 40001
```

PG 应用层标准重试模式：

```sql
DO $$
DECLARE retries INT := 0;
BEGIN
  LOOP
    BEGIN
      -- 业务事务 ...
      COMMIT;
      EXIT;
    EXCEPTION WHEN serialization_failure THEN
      retries := retries + 1;
      IF retries > 10 THEN RAISE; END IF;
      PERFORM pg_sleep(random() * 0.1);
    END;
  END LOOP;
END $$;
```

### Oracle：SERIALIZABLE 实际是 SI，不防 Write Skew

Oracle 是工业界 MVCC 的开山鼻祖（1990 年代早于 PostgreSQL/SQL Server），但其 SERIALIZABLE 级别从未升级为真正的 SSI。

```sql
-- Oracle 默认 RC, 语句级快照
-- Lost Update 不防 (与 PG RC 一致), 必须 SELECT ... FOR UPDATE

BEGIN
  SELECT balance INTO v_bal FROM accounts WHERE id = 1 FOR UPDATE;
  v_new := v_bal + 100;
  UPDATE accounts SET balance = v_new WHERE id = 1;
  COMMIT;
END;
/

-- Oracle SERIALIZABLE: 事务级快照
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- 防 Lost Update (FUW 在 UPDATE 时检查, 报 ORA-08177)
-- 防 Phantom Read (整个事务一个快照)
-- 不防 Write Skew (这是 SI 的本质局限)
```

**Oracle 用 SI 防 Write Skew 的标准做法**：在应用层用 `SELECT ... FOR UPDATE` 或物化视图触发 ww 冲突。

```sql
-- 值班医生例子的 Oracle 修复:
-- 方案 1: 显式锁所有相关行
SELECT id FROM doctors WHERE on_call = TRUE FOR UPDATE;
-- 持有 alice 和 bob 的行锁, T2 等待
-- 然后判断 + UPDATE

-- 方案 2: 物化约束聚合
CREATE TABLE on_call_count (dept_id INT PRIMARY KEY, n INT);
-- 每次修改 on_call 时, 同时 UPDATE on_call_count -> 形成 ww
```

### SQL Server：RCSI 启用后的微妙行为

SQL Server 默认 RC 是**锁实现**（与 PG/Oracle 不同），SELECT 时加共享锁、读完释放。这导致读阻塞写。**RCSI** (Read Committed Snapshot Isolation) 通过数据库选项启用：

```sql
-- 启用 RCSI
ALTER DATABASE MyDB SET READ_COMMITTED_SNAPSHOT ON;

-- 此后 RC 改用行版本而非锁
-- 读不再阻塞写 (类似 PG/Oracle)
-- 行版本存储在 tempdb
```

**RCSI 下 Lost Update 的微妙行为**：

```sql
-- 默认 RC (锁实现)
-- T1                              T2
BEGIN TRAN;                        BEGIN TRAN;
SELECT balance FROM accounts WHERE id = 1;
-- 读完释放共享锁 (RC 加锁不持有)
                                   SELECT balance FROM accounts WHERE id = 1;
                                   -- 也读完释放
-- 应用层计算
UPDATE accounts SET balance = ... WHERE id = 1;
-- 加 X 锁
                                   UPDATE accounts SET balance = ... WHERE id = 1;
                                   -- 等待 T1 X 锁
COMMIT;                            -- T1 提交后, T2 继续
                                   -- T2 的 UPDATE 用了过期的 balance -> Lost Update
                                   COMMIT;

-- RCSI 启用后:
-- T1 的 SELECT 不加锁, 直接读最新行版本
-- T2 的 SELECT 不加锁, 也读最新行版本
-- 但 SQL Server 在 UPDATE 时检测: 若读到的版本号 < 最新版本号, "重读"最新版本
-- 这一行为在某些场景避免 Lost Update, 但跨语句应用层 RMW 仍丢失
```

**SQL Server SI**（事务级 SNAPSHOT）：

```sql
ALTER DATABASE MyDB SET ALLOW_SNAPSHOT_ISOLATION ON;
SET TRANSACTION ISOLATION LEVEL SNAPSHOT;
BEGIN TRAN;
-- 整个事务一个快照, 类似 PG RR (SI)
-- 防 Lost Update (FUW, 报 Error 3960)
-- 不防 Write Skew
COMMIT;
```

**SQL Server SERIALIZABLE**：使用 range lock 实现，能防 Write Skew 但并发度低（不是 SSI）。

### MySQL InnoDB：RR 防幻读但不防 Lost Update（默认快照读）

MySQL 是默认 RR 的少数主流引擎之一，并且其 RR 比标准 RR 更强（含 gap lock 防幻读）。但其 RR 默认**不防 Lost Update**：

```sql
-- MySQL RR 下的 Lost Update
CREATE TABLE counter (id INT PRIMARY KEY, n INT) ENGINE=InnoDB;
INSERT INTO counter VALUES (1, 0);

-- T1                                T2
START TRANSACTION;                   START TRANSACTION;
SELECT n FROM counter WHERE id = 1;  -- 快照读, 0
                                     SELECT n FROM counter WHERE id = 1;  -- 快照读, 0
-- 应用层 n2 = 1
                                     -- 应用层 n2 = 1
UPDATE counter SET n = 1 WHERE id = 1;
                                     UPDATE counter SET n = 1 WHERE id = 1;
                                     -- 阻塞等待 T1 X 锁
COMMIT;                              -- T1 提交后, T2 的 UPDATE 继续
                                     -- 关键: MySQL 不像 PG RR 那样报错;
                                     -- 直接用了"应用层算的 n=1"覆盖 -> Lost Update!
                                     COMMIT;

-- 最终 n=1 (期望 2)
```

**MySQL 修复**：

```sql
START TRANSACTION;
SELECT n FROM counter WHERE id = 1 FOR UPDATE;  -- 当前读 + 行锁
-- 应用层计算
UPDATE counter SET n = ... WHERE id = 1;
COMMIT;
```

**MySQL RR 防幻读机制**：

```sql
-- T1                                T2
START TRANSACTION;
SELECT * FROM orders WHERE user_id = 100 FOR UPDATE;
-- 加 next-key lock: (user_id, primary_key) 的索引 gap
                                     START TRANSACTION;
                                     INSERT INTO orders(user_id, ...) VALUES (100, ...);
                                     -- 被 gap lock 阻塞, 等待 T1 释放
COMMIT;                              -- T1 提交后, T2 继续
                                     COMMIT;
```

但**普通 SELECT (无 FOR UPDATE)** 在 MySQL RR 下是 MVCC 快照读，不加 gap lock。这是为什么 MySQL RR "防幻读"的说法实际只在当前读场景成立。

### CockroachDB：默认 SERIALIZABLE 防所有异常

CockroachDB 是少数默认 SERIALIZABLE 的主流引擎，使用 SSI 变体（基于时间戳推进 + 不确定区间，而非 Cahill 的 SIREAD 锁）。

```sql
-- CRDB 默认 SERIALIZABLE
BEGIN;
-- 任何 read-modify-write 都自动检测冲突
-- 冲突时: 后启动的事务收到 retry error (40001)
-- 客户端自动或显式重试
COMMIT;
```

**CRDB 的乐观并发控制**：

```
事务模型:
  1. 事务开始时分配 timestamp
  2. 所有读取记录到事务的 read set
  3. 所有写入用 intent (未提交版本) 写入 KV 存储
  4. 提交时:
     - 检查 read set 中是否有"在我快照后被修改"的行
     - 检查 write set 与并发事务的冲突
     - 必要时推进 timestamp (重新检查 read set 在新时间戳下的有效性)
     - 不可推进则中止
  5. 中止时返回 retryable error, 客户端按 driver 自动重试
```

**v23.1 起可选 RC**：

```sql
SET default_transaction_isolation = 'read committed';
BEGIN;
-- RC 行为类似 PG RC (语句级快照)
-- Lost Update 不防, 需 FOR UPDATE
COMMIT;
```

### Spanner：External Consistency 严格可串行化

Google Spanner 提供"外部一致性" (External Consistency)，比 SERIALIZABLE 更强：所有事务的提交顺序与真实时间顺序一致。

```sql
-- Spanner 单一隔离级别: SERIALIZABLE (External)
-- 通过 TrueTime + Paxos + 锁实现

BEGIN TRANSACTION;
-- 读: 全局时间戳分配, 跨数据中心一致
SELECT * FROM accounts WHERE id = 1;
-- 写: 加锁 + Paxos 复制
UPDATE accounts SET balance = balance + 100 WHERE id = 1;
COMMIT;
-- 提交时间戳由 TrueTime 保证全局有序
```

Spanner 防止所有 Berenson/Adya 异常，是 NewSQL 的"金标准"。

### MySQL Serializable：所有 SELECT 自动加 S 锁

```sql
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN;
SELECT * FROM accounts WHERE id = 1;
-- 等价于 SELECT * FROM accounts WHERE id = 1 LOCK IN SHARE MODE;
-- S 锁阻止其他事务 UPDATE/DELETE
COMMIT;
```

并发度极低（读阻塞写），生产基本不用。

### YugabyteDB / PostgreSQL Compatible

YugabyteDB 兼容 PostgreSQL 语义并实现真正的 SSI (在 SERIALIZABLE 级别)：

```sql
-- YugabyteDB 默认 RR (基于 SI)
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- 等价于 PG SSI: 检测 rw-antidependency 环, 中止其中一个
-- 应用层重试
```

YB 的 SSI 在分布式环境下基于冲突时间戳实现，与 PG 单机 SSI 在语义上等价。

### TiDB：SERIALIZABLE 接受但不真实现

```sql
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- TiDB 接受语法但映射到 RR (= SI)
-- 不报错也不警告 -> 应用以为有 SERIALIZABLE 保护, 实际只是 SI
-- 这是已知的兼容性陷阱
```

迁移到 TiDB 的 PG 应用，若依赖 SERIALIZABLE 防 Write Skew，需要主动改用 `SELECT ... FOR UPDATE` 或约束锚行模式。

### SQLite：单写者锁天然串行化

```sql
-- SQLite 默认 SERIALIZABLE (实际是单写者锁实现)
-- 多个读事务可并发, 但任何写事务独占数据库 (database-level lock)
-- WAL 模式下读写不互相阻塞 (仅写写串行)
PRAGMA journal_mode = WAL;
BEGIN;
-- ...
COMMIT;
```

SQLite 没有 Write Skew 异常（因为写入是串行的）。但是性能代价高，仅适合单进程场景。

### Snowflake / BigQuery / Redshift：分析型引擎的隔离

```sql
-- Snowflake: SI 实现, 默认 RC, 不暴露隔离级别选择
BEGIN;
-- SI 语义: 事务开始时取快照
-- 提交时 FCW 检测写冲突, 中止后提交者
COMMIT;

-- BigQuery: 多语句事务用 SI + OCC
BEGIN TRANSACTION;
-- ...
COMMIT;  -- 提交时检测冲突, 失败回滚

-- Redshift: 真正 SSI (SERIALIZABLE 默认)
-- 并发 DML 频繁失败, 客户端必须重试
```

### Hive ACID / Spark Delta：表级原子，行级 SI

```sql
-- Hive ACID 表 (transactional = true)
INSERT INTO ... VALUES (...);  -- 自动事务
-- 多行写入是原子的, 但隔离级别仅 SI (不防 WS)

-- Delta Lake / Iceberg 通过 metadata log + OCC 实现
-- WriteSerializable 比 Serializable 弱: 写串行化但允许只读看到中间状态
```

## Cahill 2008 SSI 算法走查

Cahill 等人证明的核心定理：**任何 SI 中违反 Serializable 的执行，其冲突图必含两条相邻的 rw-antidependency 边形成的环。**

### 危险结构 (Dangerous Structure)

```
T1 -rw-> T2 -rw-> T3
         其中 T2 commit 在 T1, T3 之一之前
```

观察：

```
T1 reads x, T2 writes x:           T1 -rw-> T2  (T1 没看到 T2 的写)
T2 reads y, T3 writes y:           T2 -rw-> T3  (T2 没看到 T3 的写)
若 T2 commit 在 T1 commit 前:      T1 看不到 T2 的修改, 但 T2 已提交 -> T1 应在 T2 之前
若同时 T3 也存在 rw 边到 T1 (形成环): 不可串行化
```

值班医生例子的依赖图：

```
T1: SELECT count -> 看到 alice, bob 都 on_call
T1: UPDATE alice -> alice off
T2: SELECT count -> 看到 alice (T1 未提交), bob 都 on_call
                    注意: SI 下 T2 看不到 T1 的修改 (快照)
T2: UPDATE bob -> bob off

依赖边:
  T1 reads alice (sees on_call), T2 reads alice (sees on_call) -- T2 没看到 T1 的写 -> T1 -rw-> T2
  T2 reads bob (sees on_call), T1 reads bob (sees on_call)    -- T1 没看到 T2 的写 -> T2 -rw-> T1

冲突图: T1 <-rw- T2 <-rw- T1   (环!)
       这就是危险结构, SSI 必须中止其中一个
```

### SSI 算法实现伪代码

```c
// PostgreSQL src/backend/storage/lmgr/predicate.c 实现的简化版

struct Transaction {
    bool inConflict;   // 有入向 rw 边 (其他事务 rw-> me)
    bool outConflict;  // 有出向 rw 边 (me -rw-> 其他事务)
    Set predicateLocks; // SIREAD locks
};

void on_read(Transaction t, Tuple tup) {
    // SIREAD 锁记录 t 读过这个 tuple/page
    t.predicateLocks.add(SIREADLock(tup));
}

void on_write(Transaction t, Tuple tup) {
    // 找出所有对该 tup 持有 SIREAD 锁的并发活跃事务
    for each Transaction other in activeTransactions:
        if other.predicateLocks.contains(SIREADLock(tup)) and other != t:
            // 形成 rw 边: other -rw-> t (other 读了 t 现在写的)
            other.outConflict = true;
            t.inConflict = true;

            // 危险结构检测
            if other.inConflict and t.outConflict:
                abort_one_of(t, other);
}

void on_commit(Transaction t) {
    if t.inConflict and t.outConflict:
        // 提交时再检查一遍 (有些边可能在提交时才形成)
        abort(t);

    // SIREAD 锁不能立即释放, 因为可能与未提交事务形成边
    delay_lock_release(t);
}
```

### 优化：Safe Snapshot (DEFERRABLE READ ONLY)

PG 提供 `BEGIN ISOLATION LEVEL SERIALIZABLE READ ONLY DEFERRABLE` 模式：等到一个"安全快照"再开始，确保只读事务永远不会被中止。

```sql
BEGIN ISOLATION LEVEL SERIALIZABLE READ ONLY DEFERRABLE;
-- 等待: 没有任何活跃 RW 事务的 inConflict 标志
-- 此时取快照, 保证 SIREAD 锁不会形成冲突环
SELECT ... ;
COMMIT;  -- 永不被 SSI 中止
```

适用于长 OLAP 查询 + 高频 OLTP 的混合负载，避免分析查询频繁被中止。

### CockroachDB 的不同路线

CRDB 不用 SIREAD 锁，而是用**时间戳推进** (timestamp push)：

```
事务 T 读 x@v1, 时间戳 ts(T) = 100
另一事务 W 写 x@v2, 时间戳 ts(W) = 90 (在 T 之前)
但 T 的快照看不到 W (因为 W 提交时间晚)

CRDB 检测: 试图把 ts(T) 推到 W.commit_ts + 1 = 95
若推进后 T 的其他读不再有效 (因为时间戳变了, 看到不同的快照) -> 中止 T
若推进后所有读仍有效 -> T 用新时间戳提交
```

这种实现避免了 SIREAD 锁的内存开销，更适合分布式（不需要全局协调读集合）。

## Lost Update 防护方法对比

```
方法                          适用范围                    优点                   缺点
──────────────────────────  ──────────────────────────  ─────────────────────  ─────────────────────
原子表达式                    单字段算术更新              无锁, 性能最佳         不适用复杂逻辑
UPDATE x = x+1                                                                  仅适用单字段

SELECT ... FOR UPDATE         任何 RMW 模式               显式, 可靠             阻塞其他事务
                                                                                需小心死锁

乐观锁 (版本号)               高并发 RMW                  无阻塞                 应用复杂度高
WHERE version = :v                                                              冲突时需重试

CAS (旧值检查)                同上                        同上                   同上
WHERE balance = :old

PG/SQL Server SI/RR          需要事务级一致              自动 FUW 报错          仅 PG/SQL Server
                                                          应用只需重试           MySQL 不支持

SERIALIZABLE (真 SSI)         任何场景                   完全自动                可能频繁重试
                                                                                需重试逻辑

唯一索引 + ON CONFLICT        重复检查类                  数据库层面强制          仅适用唯一约束
```

### 各引擎 Lost Update 防护推荐

```
引擎                  推荐做法
──────────────────  ────────────────────────────────────────────────────────
MySQL/MariaDB       SELECT ... FOR UPDATE (默认 RR 不防)
PostgreSQL          UPDATE x = x+1 (RC) 或 RR (自动 FUW) 或 SERIALIZABLE (SSI)
Oracle              SELECT ... FOR UPDATE (RC 不防, SERIALIZABLE 是 SI 也不防 RMW 跨快照)
SQL Server          UPDATE x = x+1 (RC) 或 RCSI (重读最新) 或 SERIALIZABLE (锁)
TiDB                乐观/悲观事务模式; SELECT ... FOR UPDATE
CockroachDB         默认 SERIALIZABLE 自动防, 客户端重试
YugabyteDB          类 PG, 默认 RR (SI) FUW + SERIALIZABLE 真 SSI
Snowflake           乐观 OCC, 提交时检测, 客户端重试
BigQuery            多语句事务 OCC + 提交时冲突检测
Spanner             默认 External Consistency, 自动防
SAP HANA            SI FUW + 可选 SSI
DB2                 RR 防 (类似 PG)
Hive ACID           写写冲突时后提交者中止
Firebird            FCW NOWAIT/WAIT
SQLite              单写者天然防
Redshift            SSI 自动防, 客户端重试
```

## Read-Only Transaction Anomaly (Fekete 2004)

Fekete et al. 2004 SIGMOD Record 论文指出：在 SI 下**只读事务**也可能看到不一致状态。

```
场景: 银行账户 X, Y, 总额可透支但收手续费
  X = 70, Y = 80, 规则: X+Y < 0 时收 1 元手续费

  T1 (存款 X):       BEGIN; UPDATE X SET bal = bal + 20; COMMIT;  -- X = 90
  T2 (取款 Y):       BEGIN; ts(T2) < ts(T1)
                     -- T2 看到 X=70, Y=80, X+Y=150
                     SELECT X.bal + Y.bal;  -- 150
                     UPDATE Y SET bal = bal - 100;  -- Y=-20
                     -- T2 判断: 150 > 0, 不收手续费
                     COMMIT;  -- 此时若 ts(T2) > ts(T1), 提交检测到冲突? 不, T2 没改 X
                     -- T2 的 ts 在 T1 之前, 没冲突, 直接成功

  T3 (只读报表):     BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
                     -- 时间点: T1 已提交, T2 已提交
                     -- 如果 ts(T3) 在 (ts(T1), 现在), T3 看到 X=90, Y=-20
                     -- 按串行化顺序应是 T2 -> T1 (因为 T2 ts 在前)
                     -- T2 看到 X=70 是合理的 (T1 还没存款)
                     -- 但 T3 看到 X=90, Y=-20 -> X+Y=70 -> 应该收手续费
                     -- 而 T2 没收! T3 的报表反映了一个"应有手续费但没收"的状态
                     SELECT X.bal, Y.bal;
                     COMMIT;
```

T3 看到的状态在任何串行执行下都不可能出现。这就是 Read-Only Anomaly。

**防护**：

- PG SSI 在必要时检测并中止只读事务（在 SI 下 PG RR 不检测，仅 SERIALIZABLE 检测）
- DEFERRABLE READ ONLY 模式：等待 safe snapshot，保证只读事务永不需要中止
- Oracle / MySQL InnoDB / SQL Server SI 不防

## 关键发现

### 发现 1：SERIALIZABLE 不等于真串行化

跨 45+ 引擎，"SERIALIZABLE"是最易混淆的术语：

```
真正可串行化 (防所有异常包括 WS):
  PostgreSQL 9.1+, CockroachDB, YugabyteDB, Redshift, SQL Server (range lock),
  SQLite (单写者), Spanner (External), SAP HANA (可选 SSI), Greenplum 6.x+,
  DB2, MonetDB, Materialize, Vertica, DuckDB, Yellowbrick

实际是 SI (不防 Write Skew):
  Oracle SERIALIZABLE, TiDB SERIALIZABLE, Snowflake (默认 SI 不暴露 SERIALIZABLE),
  Firebird, SQL Server SI/SNAPSHOT, MySQL InnoDB RR (虽然名字是 RR 但行为是 SI),
  YugabyteDB RR, OceanBase RR

锁实现 SERIALIZABLE (并发度极低):
  MySQL InnoDB SERIALIZABLE (所有 SELECT 加 S 锁),
  Teradata, 早期 DB2, 早期 SQL Server

其他:
  ClickHouse, Trino, Spark SQL: 没有传统事务隔离概念
  StarRocks, Doris: 表级原子, 无 ACID 多语句事务
```

应用代码若依赖"SERIALIZABLE"自动防 Write Skew，必须先确认实际语义。

### 发现 2：Write Skew 是最隐蔽的异常

Write Skew 没有任何 SQL 报错，没有锁等待，没有 retry hint。两个事务都成功提交，业务数据进入不一致状态，可能数小时数天后才被发现。这与 Lost Update（明显的 read-modify-write 模式）和 Phantom（明显的 INSERT 触发条件变化）相比，更难在 code review 中发现。

诊断 Write Skew 的难度：

```
Lost Update:    code review 看到 SELECT + UPDATE 即可识别 (除非用了 atomic UPDATE)
Phantom:        看到 SELECT WHERE + INSERT 即可警觉
Write Skew:     需要识别"两个独立行的修改基于同一个聚合约束"
                这通常涉及多个表 / 多个文件 / 多个微服务, code review 极难发现
```

实际生产中"在 PG RR 下提交都成功"的代码迁移到 PG SERIALIZABLE 后开始报错，往往就是隐藏 Write Skew 浮出水面。

### 发现 3：MySQL RR ≠ PostgreSQL RR

两者都叫 REPEATABLE READ，但行为差异巨大：

```
                    MySQL RR (InnoDB)         PostgreSQL RR
─────────────────  ──────────────────────────  ────────────────────────
快照读              MVCC, 事务级               MVCC, 事务级
当前读 (FOR UPDATE) Next-Key Lock + Gap Lock   行锁 (无 Gap Lock)
Phantom 防护         快照读 + 当前读双重         仅快照读
Lost Update         不防 (默认 SELECT 不锁)     防 (FUW 报 40001)
Write Skew          不防                        不防

迁移建议:
  MySQL -> PG: 应用层 SELECT ... FOR UPDATE 行为变化
               (PG 不会 gap lock 阻止 INSERT, 需要 SERIALIZABLE 或唯一约束)
  PG -> MySQL: 依赖 PG RR 自动防 Lost Update 的代码会失效
               必须改为显式 FOR UPDATE
```

这是数据库迁移最大的兼容性陷阱之一。

### 发现 4：默认隔离级别决定生产质量

各引擎默认隔离级别的选择反映其设计哲学：

```
默认 RC: PostgreSQL, Oracle, SQL Server, OceanBase (兼容 Oracle), SAP HANA
        优点: 性能好, 长事务影响小
        缺点: 不防 Read Skew / Lost Update, 应用必须主动加锁

默认 RR (实为 SI): MySQL, MariaDB, TiDB, OceanBase (兼容 MySQL), YugabyteDB
        优点: 防 Phantom + Read Skew (整个事务一个快照)
        缺点: 长事务版本链膨胀; MySQL RR 不防 Lost Update 是历史包袱

默认 SERIALIZABLE: CockroachDB, Redshift, BigQuery, Spanner, SQLite, Materialize
        优点: 应用最简单, 自动防所有异常
        缺点: 频繁 retry error, 应用必须有重试逻辑
```

发现：**选择 PostgreSQL 默认 RC 而不是 RR，意味着 PG 团队相信"性能优先 + 应用主动加锁"是更合理的工程权衡**。这一选择延续了 Oracle 的传统。

### 发现 5：Cahill SSI 是 SI 时代的 "Bug Fix"

1995 年 Berenson 论文揭示 SI 不防 Write Skew，到 2008 年 Cahill 给出可工程化的 SSI 算法，期间 13 年内：

- Oracle 选择不修复 (SERIALIZABLE 仍是 SI)
- SQL Server 加了 range lock 实现 SERIALIZABLE，但 SI 级别不修复
- PostgreSQL 9.1 (2011) 第一个主流 OLTP 引入 SSI

PG 选择 SSI 而非 range lock 的关键考虑：

```
range lock (SQL Server SERIALIZABLE):
  优点: 标准实现, 行业熟悉
  缺点: 锁阻塞读, 死锁风险, 索引依赖

SSI (Cahill):
  优点: 不阻塞任何操作, 与 SI 性能接近
  缺点: 假阳性中止, 需要应用层重试
```

PG 9.1 把 SSI 做成默认 SERIALIZABLE，影响了后续 NewSQL 的设计：CockroachDB / YugabyteDB / Redshift 都选择 SSI 路线。

### 发现 6：SI 下防 Write Skew 的工程模式

在不能升级到 SSI 的引擎 (Oracle / MySQL / SQL Server SI / TiDB / Snowflake)，防 Write Skew 的标准工程模式：

```
1. 约束锚行 (Materialized Constraint Anchor):
   把 rw 依赖物化为 ww 依赖
   UPDATE constraint_table SET counter = counter - 1;  -- 强制 ww

2. SELECT ... FOR UPDATE on 关键行:
   显式锁住决策依赖的行
   SELECT * FROM doctors WHERE on_call = TRUE FOR UPDATE;

3. 唯一索引 + ON CONFLICT:
   把"最多 N 个"约束变成"重复键冲突"
   CREATE UNIQUE INDEX ... WHERE status = 'pending';

4. 应用层分布式锁:
   Redis / ZooKeeper / etcd 持有跨数据库的锁
   适合微服务场景

5. 串行化执行 (单写者队列):
   把所有修改路由到单线程, 业务上自然串行
   适合写少读多场景
```

### 发现 7：分布式事务的隔离更复杂

跨节点 / 跨分片的事务面临额外挑战：

```
单机 SI/SSI:           内存中的版本可见性
分布式 SI:             需要全局时间戳 (HLC, TrueTime, GTM)
分布式 SSI:            需要跨节点的 rw 依赖追踪
External Consistency:  TrueTime 保证物理时间顺序

实现路线:
  Spanner: TrueTime + 锁 + Paxos -> External Consistency
  CockroachDB: HLC + 时间戳推进 + 不确定区间 -> SSI
  YugabyteDB: 混合时钟 + 冲突检测 + 继承 PG SSI -> SSI
  TiDB: Percolator (Google 早期) -> SI (不真 SSI)
  Spanner Lite (Cloud Spanner): 简化的 External Consistency
```

应用层若把单机 PG 的事务直接迁移到分布式数据库，必须重新评估隔离级别保证。

### 发现 8：异常的检测难度排序

```
最易检测 (有 SQL 错误码):
  Lost Update (PG RR FUW): SQLSTATE 40001 could not serialize access
  Write Skew (PG SSI):     SQLSTATE 40001 read/write dependencies
  CRDB Retry Error:         retry transaction

中等难度 (需要审计 / 监控):
  MySQL Lost Update:        无错误码, 需对比业务约束
  Read Skew:                需要应用层一致性检查

最难检测 (生产中长期潜伏):
  Oracle SERIALIZABLE Write Skew: 名字误导, 应用以为有保护
  SI 下的所有 Write Skew: 无任何提示
  Read-Only Anomaly:    只在 SI 下偶发, 报表数据偶尔不一致
```

工程实践：**生产环境应监控 SQLSTATE 40001 的频率作为应用层并发争用的核心指标**。频率高说明事务粒度过粗或负载过重；频率为 0 不一定说明没问题——可能是隔离级别不够。

### 发现 9：异常 vs 性能的工程取舍

```
强一致性 (Serializable / SSI):
  优点: 应用代码简单, 不易出错
  代价: 高争用场景 retry 频繁, 长事务被中止
  适合: 金融核心 / 关键业务系统

弱一致性 (RC / SI):
  优点: 高并发, 低延迟
  代价: 应用必须主动防护 (FOR UPDATE / 乐观锁 / 约束锚)
  适合: 大多数 web 应用 / 微服务

最弱 (RC + 无防护):
  优点: 极高吞吐
  代价: 数据可能不一致, 但业务上可容忍
  适合: 日志类 / 计数器类 / 最终一致场景
```

正确的工程实践是**按表 / 按业务粒度**选择隔离级别，而非整个数据库统一一个级别。例如订单表用 SERIALIZABLE，日志表用 RC。

### 发现 10：未来趋势 — 更细粒度的隔离

新一代数据库正在尝试更细粒度的隔离选择：

```
按事务标记:
  PostgreSQL: SET TRANSACTION ISOLATION LEVEL ... (per-transaction)
  CockroachDB: BEGIN ISOLATION LEVEL READ COMMITTED
  YugabyteDB: 类似

按语句标记:
  Microsoft 研究: per-statement isolation (动态决策)
  尚未进入主流引擎

按对象 / 列标记:
  研究中: 不同列要求不同一致性 (例如 balance 严格, profile 弱)
  尚未标准化

混合一致性:
  Spanner Read-Only / Bounded Staleness: 强一致 + 弱一致同库可选
  CRDB AS OF SYSTEM TIME: 历史读, 不参与冲突检测
```

异常防护与性能的取舍将从"全局静态选择"演化为"细粒度动态选择"。这要求引擎实现支持更复杂的并发控制状态，也要求应用开发者理解每种隔离的精确语义。

## 总结对比矩阵

### 异常防护能力总览（按引擎）

| 引擎 | RC Lost Update | RR/SI Write Skew | SERIALIZABLE 真串行 | 默认级别 |
|------|----------------|------------------|---------------------|---------|
| PostgreSQL | 不防 | 不防 (RR) | 是 (SSI 9.1+) | RC |
| MySQL InnoDB | 不防 | 不防 (RR) | 锁实现 | RR |
| Oracle | 不防 | -- | 否 (是 SI) | RC |
| SQL Server | 不防 | 不防 (SI) | 是 (range lock) | RC |
| SQLite | -- | -- | 是 (单写) | SERIALIZABLE |
| CockroachDB | 不防 (v23.1+) | -- | 是 (SSI) | SERIALIZABLE |
| TiDB | 不防 | 不防 | 否 (是 SI) | RR |
| YugabyteDB | 不防 | 不防 (RR) | 是 (SSI) | RR |
| OceanBase | 不防 | 不防 | 是 (悲观锁) | RC |
| Snowflake | 不防 | 不防 | -- | RC |
| BigQuery | -- | -- | 是 (OCC) | SERIALIZABLE |
| Redshift | -- | -- | 是 (SSI) | SERIALIZABLE |
| Spanner | -- | -- | 是 (External) | SERIALIZABLE |
| SAP HANA | 不防 | 不防 | 是 (可选 SSI) | RC |
| Greenplum | 不防 | 不防 | 是 (SSI 6.x+) | RC |
| DB2 | 不防 | 防 | 是 | CS |
| Aurora (PG) | 继承 PG | 继承 PG | 是 | RC |
| Aurora (MySQL) | 继承 MySQL | 继承 MySQL | 锁 | RR |
| MariaDB | 不防 | 不防 | 锁 | RR |
| H2 | 不防 | 不防 | 是 | RC |
| HSQLDB | 不防 | 不防 | 是 | RR |
| Firebird | 不防 | 不防 | 是 | SNAPSHOT |
| Vertica | -- | -- | 是 | SERIALIZABLE |
| DuckDB | -- | -- | 是 (单写) | SERIALIZABLE |
| MonetDB | -- | -- | 是 (OCC) | SERIALIZABLE |
| Exasol | -- | -- | 是 (OCC) | SERIALIZABLE |
| Materialize | -- | -- | Strict Serializable | SERIALIZABLE |
| RisingWave | -- | -- | 是 | SERIALIZABLE |
| Vertica | -- | -- | 是 | SERIALIZABLE |
| Databricks (Delta) | -- | -- | WriteSerializable | WriteSerializable |
| Spark SQL | 依赖底层 | 依赖底层 | 依赖底层 | 表级 |
| Hive (ACID) | -- | 不防 (SI) | -- | SI |
| Trino / Presto | 无传统事务 | -- | -- | -- |
| ClickHouse | 单语句原子 | -- | -- | -- |
| StarRocks | 表级原子 | -- | -- | -- |
| Doris | 表级原子 | -- | -- | -- |
| Impala | 依赖底层 | 依赖底层 | -- | -- |
| Teradata | 锁 RC | -- | 是 (锁) | SERIALIZABLE |
| SingleStore | 不防 | -- | -- | RC |
| Yellowbrick | 不防 | 不防 | 是 | RC |
| TimescaleDB | 继承 PG | 继承 PG | 继承 PG | RC |
| GaussDB | 继承 PG | 继承 PG | 继承 PG | RC |
| Azure SQL DB | 不防 | 不防 (SI) | 是 (range lock) | RC (默认 RCSI) |
| Azure Synapse | -- | -- | -- | RC |
| Informix | 不防 | 不防 | 是 (锁) | CR |
| Derby | 不防 | -- | 是 (锁) | RC |
| CrateDB | 最终一致 | -- | -- | -- |
| QuestDB | 单写者 | -- | -- | -- |
| Firebolt | 单语句 | -- | -- | -- |

> 统计：约 25 个引擎在某种隔离级别下声称防 Write Skew，其中真正实现 SSI 的约 12 个；其余依赖锁、单写者、OCC 提交时检测等机制。

### 异常 vs 隔离级别速查

| 异常 | RC | RR (SI) | SI (FUW) | SSI | SERIALIZABLE (锁) |
|------|----|---------|----------|----|-------------------|
| Dirty Write | 防 | 防 | 防 | 防 | 防 |
| Dirty Read | 防 | 防 | 防 | 防 | 防 |
| Lost Update (atomic UPDATE) | 防 | 防 | 防 | 防 | 防 |
| Lost Update (RMW 应用层) | 不防 | 部分(*1) | 防 | 防 | 防 |
| Fuzzy Read | 不防 | 防 | 防 | 防 | 防 |
| Phantom (insert 模式) | 不防 | 部分(*2) | 部分 | 防 | 防 |
| Read Skew | 不防 | 防 | 防 | 防 | 防 |
| Write Skew | 不防 | 不防 | 不防 | 防 | 防 |
| Read-Only Anomaly | 不防 | 不防 | 不防 | 防 | 防 |

```
(*1) PG RR (FUW) 防, MySQL RR (默认快照读) 不防
(*2) PG RR (SI 快照) 防快照读层面, MySQL RR 加 gap lock 双重防护;
     SI 不防 phantom-via-insert (新 INSERT 没有 ww 冲突)
```

## 参考资料

- Berenson, H., Bernstein, P., Gray, J., Melton, J., O'Neil, E., O'Neil, P. *A Critique of ANSI SQL Isolation Levels*, SIGMOD 1995. [Microsoft Research tech report](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/tr-95-51.pdf)
- Adya, A. *Weak Consistency: A Generalized Theory and Optimistic Implementations for Distributed Transactions*, PhD Thesis, MIT, 1999. [PDF](https://pmg.csail.mit.edu/papers/adya-phd.pdf)
- Cahill, M., Röhm, U., Fekete, A. *Serializable Isolation for Snapshot Databases*, SIGMOD 2008.
- Fekete, A., Liarokapis, D., O'Neil, E., O'Neil, P., Shasha, D. *Making Snapshot Isolation Serializable*, ACM TODS 2005.
- Fekete, A., O'Neil, E., O'Neil, P. *A Read-Only Transaction Anomaly Under Snapshot Isolation*, SIGMOD Record 2004.
- Bernstein, P., Hadzilacos, V., Goodman, N. *Concurrency Control and Recovery in Database Systems*, Addison-Wesley 1987. [Online](http://research.microsoft.com/en-us/people/philbe/ccontrol.aspx)
- Kleppmann, M. *Designing Data-Intensive Applications*, Chapter 7 (Transactions), O'Reilly 2017.
- Daudjee, K., Salem, K. *Lazy Database Replication with Snapshot Isolation*, VLDB 2006.
- PostgreSQL: [Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
- PostgreSQL: [SSI Wiki](https://wiki.postgresql.org/wiki/SSI)
- PostgreSQL: [Serializable Snapshot Isolation Implementation README](https://github.com/postgres/postgres/blob/master/src/backend/storage/lmgr/README-SSI)
- MySQL: [InnoDB Multi-Versioning](https://dev.mysql.com/doc/refman/8.0/en/innodb-multi-versioning.html)
- MySQL: [Locks Set by SQL Statements](https://dev.mysql.com/doc/refman/8.0/en/innodb-locks-set.html)
- Oracle: [Data Concurrency and Consistency](https://docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/data-concurrency-and-consistency.html)
- SQL Server: [SET TRANSACTION ISOLATION LEVEL](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-transaction-isolation-level-transact-sql)
- SQL Server: [Snapshot Isolation in SQL Server](https://learn.microsoft.com/en-us/dotnet/framework/data/adonet/sql/snapshot-isolation-in-sql-server)
- CockroachDB: [Serializable Isolation](https://www.cockroachlabs.com/docs/stable/demo-serializable.html)
- CockroachDB: [Read Committed Transactions (v23.1+)](https://www.cockroachlabs.com/docs/stable/read-committed.html)
- YugabyteDB: [Transaction Isolation Levels](https://docs.yugabyte.com/preview/architecture/transactions/isolation-levels/)
- TiDB: [Transaction Isolation Levels](https://docs.pingcap.com/tidb/stable/transaction-isolation-levels)
- Snowflake: [Transactions](https://docs.snowflake.com/en/sql-reference/transactions)
- BigQuery: [Multi-statement transactions](https://cloud.google.com/bigquery/docs/transactions)
- Spanner: [TrueTime and External Consistency](https://cloud.google.com/spanner/docs/true-time-external-consistency)
- SAP HANA: [Transaction Isolation Levels](https://help.sap.com/docs/SAP_HANA_PLATFORM/4ecd2ee6dffc4b73a64b1b5bdf25e1e7/45e7f17d8ed94e269eba0cf8cf69efb8.html)
- DB2: [Concurrency Control](https://www.ibm.com/docs/en/db2/11.5?topic=concurrency-isolation-levels)
