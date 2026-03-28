# SQL Server: 序列

> 参考资料:
> - [SQL Server - IDENTITY Property](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-table-transact-sql-identity-property)
> - [SQL Server - CREATE SEQUENCE](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-sequence-transact-sql)

## IDENTITY: SQL Server 最传统的自增方式

```sql
CREATE TABLE users (
    id       BIGINT IDENTITY(1, 1) NOT NULL,  -- IDENTITY(seed, increment)
    username NVARCHAR(64) NOT NULL,
    CONSTRAINT PK_users PRIMARY KEY (id)
);
```

获取最后生成的 IDENTITY 值（三种方式，语义不同）
```sql
SELECT SCOPE_IDENTITY();           -- 当前作用域（推荐）
SELECT @@IDENTITY;                 -- 当前会话（包括触发器中生成的值！）
SELECT IDENT_CURRENT('users');     -- 指定表的最后值（跨会话，不安全）

-- 设计分析（对引擎开发者）:
--   SCOPE_IDENTITY() vs @@IDENTITY 是 SQL Server 经典陷阱:
--   如果 INSERT 触发了触发器，触发器中如果也有 INSERT 到带 IDENTITY 的表，
--   @@IDENTITY 返回触发器中的值，SCOPE_IDENTITY() 返回当前作用域的值。
--   这是数据库设计中"作用域"概念重要性的典型案例。
--
-- 横向对比:
--   MySQL:      LAST_INSERT_ID()（会话级，不受触发器影响——因为 MySQL 触发器不影响自增）
--   PostgreSQL: RETURNING id（INSERT ... RETURNING 语法，最安全最直接）
--   Oracle:     RETURNING id INTO var（需要 INTO 子句绑定变量）
--
-- 对引擎开发者的启示:
--   RETURNING 子句是获取生成值的最佳方案（无需单独查询，无作用域困惑）。
--   SQL Server 的 OUTPUT 子句（见 INSERT 章节）也实现了类似功能，
--   但 SCOPE_IDENTITY() 仍是最广泛使用的方式。
```

## IDENTITY 的特殊操作

手动插入 IDENTITY 列（必须显式启用）
```sql
SET IDENTITY_INSERT users ON;
INSERT INTO users (id, username) VALUES (100, 'manual_insert');
SET IDENTITY_INSERT users OFF;
```

> **注意**: 同一时刻只有一个表可以 SET IDENTITY_INSERT ON

重新播种（数据迁移后重设起始值）
```sql
DBCC CHECKIDENT ('users', RESEED, 1000);
```

IDENTITY 的核心限制:
  (1) 每表最多一个 IDENTITY 列
  (2) 不能跨表共享同一自增序列
  (3) 不能用在非 INSERT 语句中（不能 SELECT NEXT IDENTITY）
  (4) 添加到现有列不可能（必须重建表）
  (5) 值不保证连续（事务回滚、INSERT 失败会产生间隙）

## SEQUENCE: SQL Server 2012+ 引入

```sql
CREATE SEQUENCE user_id_seq
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    MAXVALUE 9223372036854775807
    CACHE 50       -- 预分配 50 个值到内存（提高并发性能）
    NO CYCLE;
```

使用序列
```sql
SELECT NEXT VALUE FOR user_id_seq;
INSERT INTO users (id, username) VALUES (NEXT VALUE FOR user_id_seq, 'alice');
```

在 DEFAULT 约束中使用（推荐方式）
```sql
CREATE TABLE orders (
    id     BIGINT DEFAULT (NEXT VALUE FOR user_id_seq),
    amount DECIMAL(10,2)
);
```

批量获取序列范围（高级用法，避免频繁调用）
```sql
DECLARE @first_value SQL_VARIANT, @last_value SQL_VARIANT;
EXEC sp_sequence_get_range @sequence_name = N'user_id_seq',
    @range_size = 100, @range_first_value = @first_value OUTPUT,
    @range_last_value = @last_value OUTPUT;
```

修改和删除序列
```sql
ALTER SEQUENCE user_id_seq RESTART WITH 1000;
ALTER SEQUENCE user_id_seq INCREMENT BY 2;
DROP SEQUENCE IF EXISTS user_id_seq;  -- 2016+
```

## IDENTITY vs SEQUENCE 权衡（对引擎开发者）

IDENTITY:
  + 简单，零配置
  + 与表绑定，概念直观
  - 不能跨表共享
  - 不能在 INSERT 之外使用
  - 无法修改步长（只能重建表）

SEQUENCE:
  + 独立对象，可跨表共享
  + 可在任何语句中使用（SELECT、DEFAULT、存储过程）
  + 支持 CACHE 提升并发性能
  + 支持 CYCLE（循环使用）
  - 额外管理开销
  - 2012+ 才可用

横向对比:
  Oracle:     最早引入 SEQUENCE（8i），IDENTITY 在 12c 才加入
  PostgreSQL: SERIAL 是 SEQUENCE 的语法糖，10+ 推荐用 IDENTITY
  MySQL:      只有 AUTO_INCREMENT，无 SEQUENCE（MariaDB 10.3 有）

对引擎开发者的启示:
  SEQUENCE 是更灵活的抽象，IDENTITY 是更简单的语法糖。
  理想设计: IDENTITY 在内部自动创建并管理 SEQUENCE（PostgreSQL 10+ 的做法）。
  CACHE 参数至关重要——无缓存的 SEQUENCE 在高并发下成为瓶颈（每次需要写 WAL）。

## UUID 生成: NEWID() 和 NEWSEQUENTIALID()

```sql
SELECT NEWID();  -- 随机 UUID v4，如 '7F1B7E42-3A1C-4B5D-8F2E-9C0D1E2F3A4B'

-- NEWSEQUENTIALID() 只能用在 DEFAULT 约束中（不能直接 SELECT）
CREATE TABLE sessions (
    id         UNIQUEIDENTIFIER DEFAULT NEWSEQUENTIALID(),
    user_id    BIGINT,
    created_at DATETIME2 DEFAULT SYSDATETIME()
);
```

设计分析:
  NEWID(): 完全随机，导致 B-tree 索引频繁页分裂和碎片化
  NEWSEQUENTIALID(): 单调递增的 UUID，索引友好——但只在单机上递增，
                     重启后新值可能小于之前的值（源自 UuidCreateSequential API）

横向对比:
  PostgreSQL: uuid_generate_v4()（随机）, uuid_generate_v7()（17+ 时间排序）
  MySQL:      UUID()（v1，包含 MAC 地址）, UUID_TO_BIN(UUID(), 1)（有序优化）

对引擎开发者的启示:
  UUID v7（基于时间戳的有序 UUID）是未来方向——既全局唯一又索引友好。
  SQL Server 的 NEWSEQUENTIALID() 是早期尝试，但实现不够完善。
  分布式引擎应原生支持 UUID v7 或类似的有序 UUID 生成。

## IDENTITY 缓存行为（2017+ 改进）

SQL Server 2016 及之前: IDENTITY 值缓存在内存中，SQL Server 异常重启后可能跳值
例如: 缓存了 1001-2000，用到 1005 时崩溃，重启后从 2001 开始
SQL Server 2017+: 可以通过跟踪标志 272 禁用缓存（但影响性能）
```sql
ALTER DATABASE SCOPED CONFIGURATION SET IDENTITY_CACHE = OFF;  -- 2017+
```

这与 MySQL 的 AUTO_INCREMENT 历史问题类似:
  MySQL 5.7: 自增值存内存，重启取 MAX(id)+1（可能复用已删除的 ID）
  MySQL 8.0: 自增值持久化到 redo log（不会回退）
