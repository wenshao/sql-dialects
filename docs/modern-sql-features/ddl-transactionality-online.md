# DDL 事务性与 Online DDL：各 SQL 方言全对比

DDL 操作在生产环境中的行为差异巨大。有些引擎允许 CREATE TABLE 和 DROP TABLE 在事务中回滚，有些引擎在执行 DDL 时自动提交当前事务，还有些引擎根本不支持 DDL 事务。与此同时，ALTER TABLE 是否阻塞读写、是否需要重建表，直接决定了线上变更的风险等级。本文系统对比 17 个引擎在这两个维度上的行为。

## DDL 事务性矩阵

DDL 事务性是指：DDL 语句能否参与事务？执行 DDL 时是否隐式提交当前事务？DDL 失败后能否回滚？

### 第一梯队：事务性 DDL（可回滚）

这些引擎的 DDL 可以放在 BEGIN...COMMIT/ROLLBACK 事务块中，与 DML 一起原子提交或回滚。

```sql
-- PostgreSQL: DDL 完全参与事务
BEGIN;
CREATE TABLE t1 (id INT PRIMARY KEY);
INSERT INTO t1 VALUES (1);
CREATE INDEX idx_t1 ON t1(id);
ROLLBACK;
-- t1 不存在, 所有操作都已回滚

-- SQL Server: DDL 同样参与事务
BEGIN TRANSACTION;
CREATE TABLE t1 (id INT PRIMARY KEY);
INSERT INTO t1 VALUES (1);
ROLLBACK;
-- t1 不存在

-- CockroachDB: 继承 PostgreSQL 的事务 DDL 语义
BEGIN;
CREATE TABLE t1 (id INT PRIMARY KEY);
ALTER TABLE t1 ADD COLUMN name STRING;
ROLLBACK;
-- 全部回滚

-- Redshift: 支持事务 DDL (继承自 PostgreSQL)
BEGIN;
CREATE TABLE t1 (id INT);
DROP TABLE t1;
COMMIT;
-- 原子执行

-- DuckDB: 完整的事务 DDL 支持
BEGIN;
CREATE TABLE t1 (id INT);
INSERT INTO t1 VALUES (1);
ROLLBACK;
-- 全部回滚
```

### 第二梯队：隐式提交（DDL 自动提交当前事务）

这些引擎在遇到 DDL 语句时，会先隐式提交当前未提交的事务，然后执行 DDL，DDL 完成后再次隐式提交。DDL 不能回滚。

```sql
-- MySQL: DDL 触发隐式 COMMIT
BEGIN;
INSERT INTO t1 VALUES (1);
CREATE TABLE t2 (id INT);  -- 隐式 COMMIT: INSERT 已提交!
ROLLBACK;
-- INSERT 已经提交, 无法回滚
-- t2 已经创建, 无法回滚
-- MySQL 8.0 的 Atomic DDL: DDL 语句本身是原子的 (要么全做, 要么全不做)
-- 但 DDL 仍然触发隐式 COMMIT, 不能参与用户事务

-- Oracle: DDL 触发隐式 COMMIT (DDL 之前和之后各一次)
-- 无论 AUTOCOMMIT 设置如何, DDL 总是自动提交
INSERT INTO t1 VALUES (1);
CREATE TABLE t2 (id NUMBER);
-- INSERT 已隐式提交
-- Oracle 没有办法将 DDL 与 DML 放在同一个事务中

-- TiDB: 继承 MySQL 的隐式提交行为
BEGIN;
INSERT INTO t1 VALUES (1);
ALTER TABLE t1 ADD COLUMN name VARCHAR(100);  -- 隐式 COMMIT
ROLLBACK;
-- INSERT 无法回滚

-- OceanBase (MySQL 模式): 继承 MySQL 的隐式提交行为
-- OceanBase (Oracle 模式): 继承 Oracle 的隐式提交行为

-- Snowflake: DDL 自动提交
BEGIN;
INSERT INTO t1 VALUES (1);
CREATE TABLE t2 (id INT);  -- 自动提交
ROLLBACK;
-- INSERT 已提交, t2 已创建
```

### 第三梯队：无事务 DDL / DDL 不参与事务

这些引擎要么不支持多语句事务，要么 DDL 完全在事务体系之外执行。

```sql
-- BigQuery: 没有传统事务, DDL 独立执行
-- BigQuery 的多语句事务 (BETA) 明确排除 DDL
-- 每条 DDL 独立执行, 无法回滚
CREATE TABLE dataset.t1 (id INT64);
-- 无法回滚

-- ClickHouse: 无事务支持
-- DDL 和 DML 都没有事务语义 (无 BEGIN/COMMIT/ROLLBACK)
-- 每条语句独立执行
ALTER TABLE t1 ADD COLUMN name String;
-- 立即生效, 无回滚机制

-- Hive: 有限的 ACID 事务 (仅限 ORC 格式 + 事务表)
-- DDL 不参与事务
CREATE TABLE t1 (id INT) STORED AS ORC;
-- 独立执行

-- Spark SQL: DDL 不支持事务
-- Delta Lake 提供有限的 DML 事务, 但 DDL 独立
CREATE TABLE t1 (id INT) USING DELTA;
-- 独立执行

-- StarRocks: DDL 不参与事务
CREATE TABLE t1 (id INT) DISTRIBUTED BY HASH(id);
-- 独立执行, 无回滚

-- Doris: DDL 不参与事务
CREATE TABLE t1 (id INT) DISTRIBUTED BY HASH(id);
-- 独立执行, 无回滚

-- MaxCompute: 无事务 DDL
-- DDL 作为独立作业提交执行
CREATE TABLE t1 (id BIGINT);
-- 独立执行
```

### DDL 事务性总结矩阵

| 引擎 | DDL 可回滚? | 隐式 COMMIT? | DDL 原子性 | 备注 |
|------|:-----------:|:----------:|:---------:|------|
| **PostgreSQL** | YES | NO | 语句级+事务级 | DDL 完全参与事务, 可与 DML 混合回滚 |
| **SQL Server** | YES | NO | 语句级+事务级 | DDL 完全参与事务 |
| **CockroachDB** | YES | NO | 语句级+事务级 | 继承 PG 语义, 分布式事务 DDL |
| **Redshift** | YES | NO | 语句级+事务级 | 继承 PG 语义 |
| **DuckDB** | YES | NO | 语句级+事务级 | 嵌入式引擎, 完整事务 DDL |
| **MySQL** | NO | YES | 语句级 (8.0+) | 8.0 Atomic DDL: DDL 本身原子, 但触发隐式提交 |
| **Oracle** | NO | YES | 语句级 | DDL 前后各一次隐式 COMMIT |
| **TiDB** | NO | YES | 语句级 | 兼容 MySQL 隐式提交行为 |
| **OceanBase** | NO | YES | 语句级 | MySQL/Oracle 模式分别继承对应行为 |
| **Snowflake** | NO | YES | 语句级 | DDL 自动提交 |
| **BigQuery** | NO | N/A | 语句级 | 多语句事务明确排除 DDL |
| **ClickHouse** | NO | N/A | 语句级 | 无事务机制 |
| **Hive** | NO | N/A | 语句级 | DDL 独立于 ACID 事务 |
| **Spark SQL** | NO | N/A | 语句级 | Delta Lake DML 事务不含 DDL |
| **StarRocks** | NO | N/A | 语句级 | DDL 独立执行 |
| **Doris** | NO | N/A | 语句级 | DDL 独立执行 |
| **MaxCompute** | NO | N/A | 作业级 | DDL 作为独立作业提交 |

## Online DDL 支持矩阵

Online DDL 决定了生产环境中执行 ALTER TABLE 时是否会阻塞业务读写。以下从四个核心操作维度对比各引擎。

### OLTP 引擎

#### MySQL

```
ADD COLUMN:
  - INSTANT (8.0.12+): 只改元数据, 毫秒级完成, 不阻塞 DML
    - 8.0.12: 仅支持末尾添加
    - 8.0.29+: 支持任意位置
  - INPLACE (5.6+): 允许并发 DML, 但可能需要重建表
  - COPY: 全程锁表

DROP COLUMN:
  - INSTANT (8.0.29+): 只改元数据
  - COPY (8.0.28-): 需要重建表, 全程锁表

MODIFY TYPE (改变列类型):
  - 几乎总是 COPY 算法, 需要重建表
  - 生产环境建议用 gh-ost 或 pt-online-schema-change

ADD INDEX:
  - INPLACE (5.6+): 允许并发 DML, 不重建表
  - LOCK=NONE: 不阻塞读写
  - 但仍需要全表扫描构建索引
```

#### PostgreSQL

```
ADD COLUMN:
  - 带常量/表达式默认值 (11+): 即时操作, 只改 pg_attribute
  - 不带默认值: 即时操作 (所有版本)
  - 带 volatile 函数默认值: 需要重写表 (少见)

DROP COLUMN:
  - 即时操作 (所有版本): 标记 attisdropped=true, 不重写表

MODIFY TYPE (ALTER TYPE):
  - 需要重写整个表, ACCESS EXCLUSIVE 锁
  - 某些兼容类型转换例外 (如 varchar(n) 增大长度)

ADD INDEX:
  - CREATE INDEX: 阻塞写入 (ShareLock)
  - CREATE INDEX CONCURRENTLY: 不阻塞写入 (两遍扫描)
  - REINDEX CONCURRENTLY (12+): 在线重建索引
```

#### Oracle

```
ADD COLUMN:
  - 带默认值 (12c+): 即时操作, 只改数据字典
  - 不带默认值: 即时操作
  - 11g 及之前带默认值: 需要回填所有行

DROP COLUMN:
  - SET UNUSED: 即时标记, 不重写
  - DROP COLUMN: 需要重写表, 锁表
  - DROP UNUSED COLUMNS: 后台清理

MODIFY TYPE:
  - 需要重写表 (多数情况)
  - DBMS_REDEFINITION: 在线重定义 (不阻塞 DML)

ADD INDEX:
  - CREATE INDEX ONLINE: 允许并发 DML
  - 默认 CREATE INDEX: 锁表
```

#### SQL Server

```
ADD COLUMN:
  - 带默认值: 即时元数据操作 (2012+ Enterprise)
  - 不带默认值 (nullable): 即时元数据操作

DROP COLUMN:
  - 即时元数据操作 (标记删除)
  - 空间在后续操作中回收

MODIFY TYPE (ALTER COLUMN):
  - WITH (ONLINE = ON): 不阻塞 DML (2016+ Enterprise)
  - 没有 ONLINE: 需要 Schema Modification Lock

ADD INDEX:
  - WITH (ONLINE = ON): 不阻塞 DML (Enterprise)
  - RESUMABLE = ON (2017+): 可暂停/恢复
  - Standard Edition: 只能离线创建
```

#### TiDB

```
所有 DDL 操作基于 Google F1 Online Schema Change 协议:

ADD COLUMN:    非阻塞, 全程不锁表
DROP COLUMN:   非阻塞, 后台 GC 清理
MODIFY TYPE:   非阻塞, 后台数据回填 (v5.0+)
ADD INDEX:     非阻塞, 后台分布式回填

F1 协议状态机:
  absent -> delete-only -> write-only -> public
  每个状态切换在集群中逐节点传播
  任意时刻集群中最多存在两个相邻状态
  保证 DML 在任何中间状态都正确

TiDB 6.2+: 并行 DDL, 多个 DDL 可同时执行
TiDB 6.5+: Fast DDL 加速索引回填 (分布式框架)
```

#### CockroachDB

```
同样基于 F1 Online Schema Change 协议:

ADD COLUMN:    非阻塞
DROP COLUMN:   非阻塞, GC job 清理
MODIFY TYPE:   非阻塞 (有类型限制)
ADD INDEX:     非阻塞, 后台回填

状态机与 TiDB 类似:
  delete-and-write-only -> backfill -> public
  所有节点通过 schema lease 机制同步

特有机制:
  - Schema change jobs 可在节点故障后恢复
  - 支持 DDL 事务: 多个 DDL 在同一事务中原子执行
  - declarative schema changer (22.2+): 重构状态机, 支持更复杂的 DDL
```

#### OceanBase

```
ADD COLUMN:    Online (不阻塞 DML, 元数据操作)
DROP COLUMN:   Online (标记删除, 后台清理)
MODIFY TYPE:   取决于类型变更, 可能需要数据回填
ADD INDEX:     Online (后台构建, 不阻塞 DML)

OceanBase 的 DDL 执行:
  - RootService 协调 DDL 任务
  - 索引构建: 分布式并行回填
  - 列操作: 元数据变更 + 增量回填
  - 兼容 MySQL/Oracle 两种模式的 DDL 语义
```

### 分析型引擎 / 云数仓

#### BigQuery

```
BigQuery 是列存 + 存算分离架构, DDL 操作特性:

ADD COLUMN:    即时 (元数据操作)
DROP COLUMN:   即时 (元数据操作, 存储后台清理)
MODIFY TYPE:   有限支持, 部分类型可扩宽
ADD INDEX:     不适用 (无用户自定义索引)

BigQuery 没有传统的"表锁"概念:
  - DDL 修改表元数据, 不影响正在运行的查询
  - 并发 DDL 通过乐观并发控制 (ETag) 避免冲突
  - 不存在"Online DDL"的概念, 因为所有 DDL 本身就不阻塞查询
```

#### Snowflake

```
存算分离 + 微分区架构:

ADD COLUMN:    即时 (元数据操作)
DROP COLUMN:   即时 (元数据操作)
MODIFY TYPE:   部分支持 (如 NUMBER 精度增大), 不兼容类型需要重建
ADD INDEX:     不适用 (无用户自定义索引, 使用自动聚簇)

所有 DDL 都是元数据操作:
  - 微分区 (micro-partition) 不可变, DDL 不修改已有数据文件
  - 新写入的数据自动使用新 schema
  - Time Travel 自然保留旧 schema 数据
```

#### Redshift

```
MPP 列存架构:

ADD COLUMN:    即时 (元数据操作)
DROP COLUMN:   标记删除, VACUUM 后回收空间
MODIFY TYPE:   需要重建表 (ALTER COLUMN TYPE 有严格限制)
ADD INDEX:     不适用 (无二级索引, 使用 SORTKEY/DISTKEY)

DDL 参与事务 (继承 PostgreSQL):
  - ADD/DROP COLUMN 可在事务中回滚
  - DDL 获取 AccessExclusiveLock, 与并发 DML 互斥
  - 建议在维护窗口执行大型 DDL
```

#### ClickHouse

```
MergeTree 引擎 (列存 + LSM-like):

ADD COLUMN:    即时 (元数据操作, 旧 part 后台合并时更新)
DROP COLUMN:   即时 (元数据操作, 旧 part 后台合并时清理)
MODIFY TYPE:   异步 mutation (后台逐 part 重写)
ADD INDEX:     即时元数据操作 (数据索引在后台 merge 时构建)

特殊机制:
  - ADD/DROP COLUMN 修改列定义, 不重写已有 data part
  - 每个 data part 有独立的列文件
  - 旧 part 的缺失列: 读取时用默认值填充
  - 后台合并时将旧 part 的列补齐
  - mutations_sync 设置控制同步/异步行为
```

#### Hive

```
ADD COLUMN:    元数据操作 (Metastore 修改, 不改数据文件)
DROP COLUMN:   仅支持 REPLACE COLUMNS (替换所有列定义)
MODIFY TYPE:   元数据操作 (不验证已有数据是否兼容)
ADD INDEX:     已废弃 (Hive 3.0 移除索引功能)

Hive 的 DDL 本质上是 Metastore 元数据操作:
  - SerDe 在读取时根据当前 schema 解析数据 (schema-on-read)
  - 不存在 Online DDL 的概念, 因为 DDL 不触碰数据文件
  - 风险: ALTER COLUMN TYPE 不验证已有数据, 可能导致运行时错误
```

#### Spark SQL

```
ADD COLUMN:    元数据操作 (Hive Metastore / Delta Log)
DROP COLUMN:   Delta Lake 支持 (元数据), Hive 表不支持
MODIFY TYPE:   Delta Lake: 安全类型扩宽 (如 INT->BIGINT)
ADD INDEX:     不适用 (无索引机制)

Delta Lake 的 schema 演进:
  - mergeSchema 选项: 写入时自动添加新列
  - overwriteSchema 选项: 写入时替换整个 schema
  - ALTER TABLE 修改 Delta Log 中的 schema 元数据
  - 所有操作都不阻塞读取 (MVCC 基于 Delta Log 版本)
```

#### StarRocks

```
ADD COLUMN:
  - Fast Schema Evolution (3.0+): 即时元数据操作
  - 传统模式: 后台 SchemaChange job, 不阻塞查询但需要数据重写

DROP COLUMN:
  - Fast Schema Evolution (3.0+): 即时元数据操作
  - 传统模式: 后台 SchemaChange job

MODIFY TYPE:
  - 需要 SchemaChange job (数据回填)
  - 不阻塞查询, 但 job 完成前新 schema 不生效

ADD INDEX:
  - Bitmap Index / Bloom Filter Index: 后台构建
  - 不阻塞查询

Fast Schema Evolution 原理:
  - 每个 Tablet 记录列的 unique_id 而非位置
  - ADD/DROP COLUMN 只修改 FE 元数据
  - 旧 Tablet 的缺失列在读取时填充默认值
  - 类似 ClickHouse 的 part 机制
```

#### Doris

```
ADD COLUMN:
  - Light Schema Change (2.0+): 即时元数据操作
  - 传统模式: 后台 SchemaChange job

DROP COLUMN:
  - Light Schema Change (2.0+): 即时元数据操作
  - 传统模式: 后台 SchemaChange job

MODIFY TYPE:
  - 需要 SchemaChange job (数据回填)
  - 不阻塞查询

ADD INDEX:
  - Inverted Index / Bloom Filter Index: 后台构建
  - 不阻塞查询

Light Schema Change 原理 (与 StarRocks Fast Schema Evolution 类似):
  - 基于 column unique_id 而非列位置
  - ADD/DROP COLUMN 仅修改 FE 元数据
  - 读取时自动对齐新旧 schema
```

#### MaxCompute

```
ADD COLUMN:    元数据操作 (不修改已有分区数据)
DROP COLUMN:   不支持 (需要重建表)
MODIFY TYPE:   不支持 (需要重建表)
ADD INDEX:     不适用 (无索引机制)

MaxCompute 是全托管批处理平台:
  - DDL 修改项目 (Project) 级元数据
  - 已有分区数据不受影响 (schema-on-read)
  - 新分区自动使用新 schema
  - 不存在 Online DDL 概念 (无在线事务处理)
```

### Online DDL 总结矩阵

| 引擎 | ADD COLUMN | DROP COLUMN | MODIFY TYPE | ADD INDEX |
|------|:----------:|:-----------:|:-----------:|:---------:|
| **MySQL** | INSTANT (8.0.12+) | INSTANT (8.0.29+) | COPY (阻塞) | INPLACE (不阻塞) |
| **PostgreSQL** | 即时 (11+含默认值) | 即时 (标记删除) | 重写表 (阻塞) | CONCURRENTLY (不阻塞) |
| **Oracle** | 即时 (12c+含默认值) | SET UNUSED (即时) | DBMS_REDEF (不阻塞) | ONLINE (不阻塞) |
| **SQL Server** | 即时 (元数据) | 即时 (标记删除) | ONLINE (Enterprise) | ONLINE (Enterprise) |
| **TiDB** | 非阻塞 (F1) | 非阻塞 (F1) | 非阻塞 (5.0+) | 非阻塞 (F1) |
| **CockroachDB** | 非阻塞 (F1) | 非阻塞 (F1) | 非阻塞 (有限制) | 非阻塞 (F1) |
| **OceanBase** | 非阻塞 | 非阻塞 | 视类型而定 | 非阻塞 |
| **BigQuery** | 即时 (元数据) | 即时 (元数据) | 有限支持 | N/A (无索引) |
| **Snowflake** | 即时 (元数据) | 即时 (元数据) | 有限支持 | N/A (无索引) |
| **Redshift** | 即时 (元数据) | 标记删除 | 严格限制 | N/A (无索引) |
| **ClickHouse** | 即时 (元数据) | 即时 (元数据) | 异步 mutation | 即时 (元数据) |
| **Hive** | 元数据 | REPLACE COLUMNS | 元数据 (不验证) | N/A (已废弃) |
| **Spark SQL** | 元数据 | Delta Lake 支持 | Delta (类型扩宽) | N/A |
| **StarRocks** | Fast Schema Evo (3.0+) | Fast Schema Evo (3.0+) | SchemaChange job | 后台构建 |
| **Doris** | Light Schema Change (2.0+) | Light Schema Change (2.0+) | SchemaChange job | 后台构建 |
| **MaxCompute** | 元数据 | 不支持 | 不支持 | N/A |

## Atomic DDL

Atomic DDL 解决的是单条 DDL 语句的原子性：如果 DDL 执行到一半失败（如磁盘满、进程崩溃），表结构是否会处于不一致状态？

### MySQL 8.0 Atomic DDL

```sql
-- MySQL 8.0 之前:
-- DROP TABLE t1, t2, t3;
-- 如果 t2 删除时 crash, 可能 t1 已删除, t2/t3 未删除
-- 数据字典 (.frm 文件) 与 InnoDB 数据文件可能不一致

-- MySQL 8.0 Atomic DDL:
-- 数据字典统一存储在 InnoDB (mysql.* 表)
-- DDL 操作写入 DDL Log (InnoDB 表)
-- crash recovery 时通过 DDL Log 回滚未完成的 DDL

DROP TABLE t1, t2, t3;
-- 要么全部删除, 要么全部保留 (crash-safe)

CREATE TABLE t1 (
    id INT PRIMARY KEY,
    name VARCHAR(100),
    INDEX idx_name(name)
);
-- 如果创建过程中 crash: 表不存在 (原子回滚)
-- 不会残留 .frm 文件或孤立的 InnoDB 表空间

-- Atomic DDL 的范围:
-- 覆盖: CREATE/ALTER/DROP TABLE, CREATE/DROP INDEX, TRUNCATE TABLE
-- 不覆盖: 表空间相关操作, 安装/卸载插件
-- 注意: Atomic DDL != Transactional DDL
-- DDL 仍然触发隐式 COMMIT, 不能在用户事务中回滚
```

### PostgreSQL：完整事务 DDL

```sql
-- PostgreSQL 的 DDL 是完整的事务操作
-- 不仅是语句级原子, 更是事务级原子

BEGIN;
CREATE TABLE t1 (id INT PRIMARY KEY);
CREATE TABLE t2 (id INT REFERENCES t1(id));
-- 如果任何一步失败, 所有 DDL 都回滚

-- 实现原理:
-- DDL 修改系统目录表 (pg_class, pg_attribute 等)
-- 系统目录表与用户表使用相同的 MVCC + WAL 机制
-- DDL 的修改在 COMMIT 前对其他事务不可见
-- ROLLBACK 时, 系统目录表的修改通过 MVCC 撤销

-- 结合 SAVEPOINT:
BEGIN;
CREATE TABLE t1 (id INT);
SAVEPOINT sp1;
CREATE TABLE t2 (id INT);
ROLLBACK TO sp1;  -- 只回滚 t2 的创建
COMMIT;
-- t1 存在, t2 不存在
```

### Oracle：自动提交 + 语句级原子

```sql
-- Oracle 的 DDL 总是自动提交
-- 每条 DDL 语句本身是原子的 (要么成功要么失败)
-- 但不能在事务中与其他语句一起回滚

CREATE TABLE t1 (id NUMBER PRIMARY KEY);
-- 自动提交, 立即生效

-- 如果 DDL 内部失败 (如表已存在), 不会有副作用
-- 但如果 DDL 成功, 无法回滚

-- DDL 隐式提交的时机:
-- 1. DDL 语句执行前: COMMIT 当前未提交的 DML
-- 2. DDL 语句执行
-- 3. DDL 语句执行后: COMMIT DDL 的变更
-- 即使 DDL 失败, 步骤 1 的 COMMIT 已经生效!
```

### Atomic DDL 对比

| 引擎 | DDL 语句原子性 | DDL Crash-Safe | 实现机制 |
|------|:-----------:|:-------------:|---------|
| **MySQL 8.0+** | YES | YES | DDL Log + InnoDB 数据字典 |
| **MySQL 5.7-** | 部分 | NO | .frm 文件 + InnoDB 分离 |
| **PostgreSQL** | YES | YES | WAL + 系统目录表 MVCC |
| **Oracle** | YES | YES | Redo Log + 数据字典 |
| **SQL Server** | YES | YES | WAL + 系统目录 |
| **CockroachDB** | YES | YES | Raft + 分布式事务 |
| **TiDB** | YES | YES | TiKV 事务 + Schema 版本 |
| **ClickHouse** | 部分 | 部分 | ZooKeeper/ClickHouse Keeper 协调 |
| **Snowflake** | YES | YES | 元数据服务 (全托管) |
| **BigQuery** | YES | YES | 元数据服务 (全托管) |

## Schema Migration 策略

不同引擎的 DDL 特性决定了线上变更的策略选择。以下是各引擎推荐的 zero-downtime schema migration 模式。

### OLTP 引擎

```
MySQL:
  小表 (< 1GB):
    ALTER TABLE ... ALGORITHM=INSTANT (优先)
    ALTER TABLE ... ALGORITHM=INPLACE, LOCK=NONE (次选)
  大表 (> 1GB):
    gh-ost (推荐) 或 pt-online-schema-change
    优点: 可暂停, 可限速, 可回滚 (删影子表即可)
  注意事项:
    - SET lock_wait_timeout = 5; 避免 MDL 锁等待阻塞
    - 选择低峰期执行
    - 监控从库延迟

PostgreSQL:
  ADD COLUMN: 直接执行 (11+ 即时)
  ADD INDEX: CREATE INDEX CONCURRENTLY
  ALTER TYPE: 需要 ACCESS EXCLUSIVE 锁
    策略 1: pg_repack (类似 gh-ost, 在线重建表)
    策略 2: 新列 + 双写 + 迁移 + 切换 (应用层)
  注意事项:
    - 设置 lock_timeout 避免长时间等待锁
    - statement_timeout 限制 DDL 执行时间
    - 使用事务 DDL 实现多步变更的原子性

Oracle:
  简单 DDL: ALTER TABLE 直接执行 (12c+ 即时 ADD COLUMN)
  复杂 DDL: DBMS_REDEFINITION (在线重定义)
  大规模重构: Edition-Based Redefinition (EBR)
    - 新旧版本共存, 应用逐步切换
    - Cross-Edition Trigger 同步数据

SQL Server:
  Enterprise: WITH (ONLINE = ON) 全在线
  Standard: 只能在维护窗口执行 (离线 DDL)
  大型索引: RESUMABLE = ON (可暂停/恢复)

TiDB / CockroachDB:
  所有 DDL 非阻塞, 直接执行即可
  注意: 大表 ADD INDEX 的回填可能占用 IO/CPU
    - TiDB: 调整 tidb_ddl_reorg_worker_cnt 控制并发
    - CockroachDB: schema change job 自动管理
```

### 分析型引擎

```
BigQuery / Snowflake:
  所有 DDL 都是元数据操作, 直接执行
  不需要特殊的迁移策略
  MODIFY TYPE 的限制通过 CTAS (CREATE TABLE AS SELECT) 绕过

ClickHouse:
  ADD/DROP COLUMN: 直接执行 (即时元数据)
  MODIFY TYPE: 异步 mutation
    - 监控 system.mutations 表跟踪进度
    - 大表可能耗时较长, 注意磁盘空间 (重写 data part)
  集群环境: ALTER TABLE ... ON CLUSTER cluster_name

StarRocks / Doris:
  开启 Fast Schema Evolution / Light Schema Change:
    ADD/DROP COLUMN 即时完成
  MODIFY TYPE: 后台 SchemaChange job
    - 监控 SHOW ALTER TABLE COLUMN 跟踪进度
    - job 完成前查询仍使用旧 schema

Hive / Spark:
  DDL 是元数据操作, 直接执行
  风险在于读取端: ALTER COLUMN TYPE 不验证数据兼容性
  建议: 对历史分区做数据验证或重写
```

### 通用 Zero-Downtime 模式

```
Expand-Migrate-Contract 模式 (适用于所有引擎):

  阶段 1 - Expand (扩展):
    ALTER TABLE ADD COLUMN new_col;
    -- 新列可以有默认值或允许 NULL

  阶段 2 - Migrate (迁移):
    -- 应用层开始双写 (同时写旧列和新列)
    -- 后台任务回填历史数据
    UPDATE t SET new_col = transform(old_col) WHERE new_col IS NULL;

  阶段 3 - Contract (收缩):
    -- 确认所有数据已迁移, 所有应用已切换到新列
    ALTER TABLE DROP COLUMN old_col;

  优点: 适用于任何引擎, 无论 DDL 是否在线
  缺点: 需要应用层配合, 迁移周期较长

对于不支持 Online DDL 的引擎:
  -- 方案 A: 蓝绿部署
  -- 方案 B: 影子表 + 切换 (类似 gh-ost)
  -- 方案 C: 逻辑复制到新结构的表
```

## 横向总结矩阵

| 引擎 | DDL 可回滚? | 隐式 COMMIT? | Online ADD COLUMN | Online ADD INDEX | 锁模型 |
|------|:-----------:|:-----------:|:-----------------:|:----------------:|--------|
| **PostgreSQL** | YES | NO | 即时 (11+) | CONCURRENTLY | ShareUpdateExclusive (DDL 期间); AccessExclusive (短暂, commit 阶段) |
| **SQL Server** | YES | NO | 即时 | ONLINE=ON (Enterprise) | Sch-M (Schema Modification) 或 ONLINE 模式 |
| **CockroachDB** | YES | NO | 非阻塞 (F1) | 非阻塞 (F1) | 无表锁; 分布式 lease-based schema |
| **Redshift** | YES | NO | 即时 | N/A | AccessExclusiveLock (短暂) |
| **DuckDB** | YES | NO | 即时 | 即时 (小规模) | 进程内锁 (嵌入式单进程) |
| **MySQL** | NO | YES | INSTANT (8.0.12+) | INPLACE (5.6+) | MDL (Metadata Lock) + InnoDB 行锁; INSTANT 无锁 |
| **Oracle** | NO | YES | 即时 (12c+) | ONLINE | DML 锁 + DDL 锁; ONLINE 模式降级为 Row Share |
| **TiDB** | NO | YES | 非阻塞 (F1) | 非阻塞 (F1) | 无表锁; 分布式 schema lease |
| **OceanBase** | NO | YES | 非阻塞 | 非阻塞 | 分布式 DDL 协调; 不阻塞 DML |
| **Snowflake** | NO | YES | 即时 (元数据) | N/A | 无用户可见锁 (全托管) |
| **BigQuery** | NO | N/A | 即时 (元数据) | N/A | 无锁 (乐观并发 ETag) |
| **ClickHouse** | NO | N/A | 即时 (元数据) | 即时 (元数据) | 无事务锁; part-level 操作 |
| **Hive** | NO | N/A | 元数据 (schema-on-read) | N/A | Metastore 锁 (非数据锁) |
| **Spark SQL** | NO | N/A | 元数据 | N/A | Delta Log 乐观并发 |
| **StarRocks** | NO | N/A | Fast Schema Evo (3.0+) | 后台构建 | FE 元数据锁 (短暂); 不阻塞查询 |
| **Doris** | NO | N/A | Light Schema Change (2.0+) | 后台构建 | FE 元数据锁 (短暂); 不阻塞查询 |
| **MaxCompute** | NO | N/A | 元数据 | N/A | 作业级隔离 (全托管) |

## 对引擎开发者：DDL 事务性与 Online DDL 的设计取舍

```
1. DDL 事务性:
   实现事务性 DDL 需要系统目录表使用与用户表相同的存储引擎和事务机制。
   PostgreSQL 和 SQL Server 做到了这一点, 系统目录是普通的 MVCC 表。
   MySQL 选择了不同的路径: DDL 事务独立于用户事务, 降低了实现复杂度。
   分布式引擎 (TiDB/CockroachDB) 面临额外挑战: DDL 状态需要在集群中一致传播。

2. Online DDL 的实现层次:
   Level 0: 全表重建 + 排他锁 (最简单但不可接受)
   Level 1: 影子表 + 增量同步 (应用层方案, 如 gh-ost)
   Level 2: INPLACE + 日志回放 (MySQL 5.6+)
   Level 3: 元数据版本化 (INSTANT/即时 DDL)
   Level 4: F1 协议 (分布式无锁 DDL, TiDB/CockroachDB)

3. 关键设计决策:
   - 元数据和数据分离: 越彻底, Online DDL 越容易实现
   - 列存 vs 行存: 列存天然支持按列 ADD/DROP (每列独立文件)
   - 不可变存储 (immutable): Snowflake/BigQuery/Delta Lake 的微分区不可变,
     DDL 只需修改元数据指向即可, 天然 Online
   - Schema 版本管理: 如何让旧数据兼容新 schema?
     填充默认值 (MySQL INSTANT, PG 11+, ClickHouse)
     vs 要求应用层处理 (Hive schema-on-read)
```

## 参考资料

- MySQL: [Atomic DDL](https://dev.mysql.com/doc/refman/8.0/en/atomic-ddl.html), [Online DDL](https://dev.mysql.com/doc/refman/8.0/en/innodb-online-ddl.html)
- PostgreSQL: [Transactional DDL](https://wiki.postgresql.org/wiki/Transactional_DDL_in_PostgreSQL:_A_Competitive_Analysis)
- Oracle: [DBMS_REDEFINITION](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_REDEFINITION.html)
- SQL Server: [Online Index Operations](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/perform-index-operations-online), [Resumable Index](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/guidelines-for-online-index-operations)
- TiDB: [Online DDL](https://docs.pingcap.com/tidb/stable/ddl-introduction)
- CockroachDB: [Online Schema Changes](https://www.cockroachlabs.com/docs/stable/online-schema-changes)
- Google F1: [Online, Asynchronous Schema Change in F1](https://research.google/pubs/pub41376/)
- gh-ost: [GitHub Online Schema Migration](https://github.com/github/gh-ost)
- StarRocks: [Fast Schema Evolution](https://docs.starrocks.io/docs/sql-reference/sql-statements/table_bucket_part_index/ALTER_TABLE/)
- Doris: [Light Schema Change](https://doris.apache.org/docs/advanced/alter-table/schema-change/)
