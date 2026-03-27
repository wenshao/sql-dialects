# Online DDL 实现方案

在生产环境中，ALTER TABLE 不能阻塞读写。从 MySQL 的 COPY 算法到 gh-ost 的 binlog 复制，各引擎用不同方式解决这个核心问题。

## 核心挑战

```
传统 DDL 的问题:
  ALTER TABLE 大表 ADD COLUMN -> 锁表 -> 业务停摆

根本原因:
  修改表结构需要重写数据文件
  重写期间需要阻塞写入以保证一致性

Online DDL 的目标:
  DDL 执行期间，DML (INSERT/UPDATE/DELETE/SELECT) 可以正常进行
  对业务的影响尽可能小 (无锁 / 短暂锁)
```

## MySQL Online DDL 演进

### COPY 算法 (MySQL 5.1 及更早)

```sql
-- 最原始的 DDL 实现
ALTER TABLE employees ADD COLUMN phone VARCHAR(20);

-- 内部流程:
-- 1. 获取表的排他锁 (EXCLUSIVE LOCK) -> 阻塞所有 DML
-- 2. 创建新表结构的临时表
-- 3. 逐行复制数据到临时表
-- 4. 替换原表为临时表
-- 5. 释放锁

-- 问题:
-- 全程排他锁, 100GB 的表可能锁数小时
-- 需要额外的磁盘空间 (双倍表大小)
-- 复制过程中不记录增量变更
```

### INPLACE 算法 (MySQL 5.6+)

```sql
-- MySQL 5.6 引入 Online DDL
ALTER TABLE employees ADD COLUMN phone VARCHAR(20), ALGORITHM=INPLACE, LOCK=NONE;

-- ALGORITHM 选项:
-- INPLACE: 在原表上直接修改, 不创建临时表 (并非所有操作都支持)
-- COPY: 创建临时表并复制 (回退方案)
-- INSTANT: 只修改元数据, 不触碰数据 (MySQL 8.0+, 最快)

-- LOCK 选项:
-- NONE: 不加锁, DML 完全不阻塞
-- SHARED: 允许读, 阻塞写
-- EXCLUSIVE: 阻塞读和写
-- DEFAULT: 允许尽可能低级别的锁

-- INPLACE 的内部流程:
-- 1. 获取 MDL (Metadata Lock) 的共享锁
-- 2. 开始在原表上修改结构
-- 3. 同时将 DML 变更记录到 Online DDL Log
-- 4. 修改完成后, 回放 Online DDL Log (短暂排他锁)
-- 5. 释放锁

-- 注意: "INPLACE" 并不意味着不重建表!
-- ADD INDEX: 真正的 in-place (扫描表构建索引, 不重写表数据)
-- ADD COLUMN: 取决于列位置和默认值 (可能需要重建表)
```

### INSTANT 算法 (MySQL 8.0+)

```sql
-- MySQL 8.0.12+ 的 INSTANT DDL: 只修改元数据, 毫秒级完成

-- 支持 INSTANT 的操作:
-- 1. ADD COLUMN (末尾) - MySQL 8.0.12+
ALTER TABLE t ADD COLUMN c1 INT, ALGORITHM=INSTANT;

-- 2. ADD COLUMN (任意位置) - MySQL 8.0.29+
ALTER TABLE t ADD COLUMN c1 INT AFTER c0, ALGORITHM=INSTANT;

-- 3. DROP COLUMN - MySQL 8.0.29+
ALTER TABLE t DROP COLUMN c1, ALGORITHM=INSTANT;

-- 4. RENAME COLUMN
ALTER TABLE t RENAME COLUMN old_name TO new_name, ALGORITHM=INSTANT;

-- 5. 修改 ENUM/SET 的值列表 (添加新值)
ALTER TABLE t MODIFY COLUMN status ENUM('a','b','c','d'), ALGORITHM=INSTANT;

-- INSTANT 的原理:
-- 不修改已有数据文件
-- 在 InnoDB 数据字典中记录新的列定义和默认值
-- 读取旧行时, 缺失的列用默认值填充
-- 新写入的行包含新列

-- 限制:
-- 不能改变列类型 (VARCHAR(100) -> VARCHAR(200))
-- 不能改变列顺序 (MySQL 8.0.28 及之前)
-- 不能与其他非 INSTANT 操作组合

-- 查看某操作是否支持 INSTANT:
-- MySQL 8.0 文档中有完整的 DDL 操作与算法支持矩阵
```

### MySQL DDL 操作支持矩阵 (精选)

| 操作 | INSTANT | INPLACE | COPY | 备注 |
|------|---------|---------|------|------|
| ADD COLUMN (末尾) | 8.0.12+ | 5.6+ | Y | INSTANT 首选 |
| ADD COLUMN (中间) | 8.0.29+ | 5.6+ | Y | |
| DROP COLUMN | 8.0.29+ | N | Y | INSTANT 或 COPY |
| CHANGE 列类型 | N | 部分 | Y | 通常需要 COPY |
| ADD INDEX | N | 5.6+ | Y | INPLACE 不重建表 |
| DROP INDEX | N | 5.6+ | Y | INPLACE |
| ADD PRIMARY KEY | N | 5.6+ | Y | 需要重建表 |
| OPTIMIZE TABLE | N | 5.6+ | Y | 重建表 |

## 第三方 Online DDL 工具

### pt-online-schema-change (Percona)

```
工作原理: 触发器 + 影子表

步骤:
  1. 创建影子表 (与原表结构相同)
  2. 在影子表上执行 DDL
  3. 在原表上创建 INSERT/UPDATE/DELETE 触发器
     - 触发器将 DML 同步到影子表
  4. 分批复制原表数据到影子表 (chunk by chunk)
  5. 最终: 原子性重命名 (RENAME TABLE 原表->旧表, 影子表->原表)

优点:
  - 适用于 MySQL 5.1+ (不依赖 InnoDB Online DDL)
  - 成熟稳定, 在生产环境中使用了十余年

缺点:
  - 触发器有性能开销 (约 10-30% 的写入性能下降)
  - 触发器在 MySQL 中是行级的, 大批量写入时特别慢
  - 不支持外键引用的表 (触发器冲突)
  - RENAME TABLE 需要短暂的 metadata lock
```

```sql
-- 使用示例:
-- pt-online-schema-change --alter "ADD COLUMN phone VARCHAR(20)" \
--   --execute D=mydb,t=employees

-- 等效的 SQL 操作 (内部逻辑):
-- 1. CREATE TABLE _employees_new LIKE employees;
-- 2. ALTER TABLE _employees_new ADD COLUMN phone VARCHAR(20);
-- 3. 创建触发器:
CREATE TRIGGER pt_osc_ins AFTER INSERT ON employees
FOR EACH ROW REPLACE INTO _employees_new (...) VALUES (...);

CREATE TRIGGER pt_osc_upd AFTER UPDATE ON employees
FOR EACH ROW REPLACE INTO _employees_new (...) VALUES (...);

CREATE TRIGGER pt_osc_del AFTER DELETE ON employees
FOR EACH ROW DELETE FROM _employees_new WHERE id = OLD.id;

-- 4. 分批复制:
INSERT INTO _employees_new SELECT * FROM employees WHERE id BETWEEN 1 AND 1000;
INSERT INTO _employees_new SELECT * FROM employees WHERE id BETWEEN 1001 AND 2000;
-- ...

-- 5. 原子切换:
RENAME TABLE employees TO _employees_old, _employees_new TO employees;
DROP TABLE _employees_old;
```

### gh-ost (GitHub)

```
工作原理: binlog 复制 + 影子表 (无触发器!)

步骤:
  1. 创建影子表, 执行 DDL
  2. 作为 MySQL 从库连接, 读取 binlog
  3. 分批复制原表数据到影子表
  4. 同时从 binlog 中捕获对原表的 DML, 回放到影子表
  5. 数据追平后, 原子性切换 (RENAME TABLE 或 cut-over)

核心优势: 不使用触发器!
  - 避免了触发器的性能开销
  - 避免了触发器在高并发下的锁竞争
  - 可以在迁移过程中暂停/恢复
  - 可以动态调整迁移速度 (throttle)

binlog 解析:
  - 连接为一个 MySQL replica
  - 解析 ROW 格式的 binlog events
  - 将对原表的 DML 转换为对影子表的 DML
  - 支持: INSERT, UPDATE, DELETE
```

```bash
# gh-ost 使用示例:
# gh-ost \
#   --host=master.db.example.com \
#   --database=mydb \
#   --table=employees \
#   --alter="ADD COLUMN phone VARCHAR(20)" \
#   --execute

# 关键参数:
# --chunk-size=1000          分批复制的批次大小
# --max-load=Threads_running=25  负载控制: 超过阈值自动暂停
# --critical-load=Threads_running=100  紧急负载: 立即中止
# --throttle-control-replicas  监控从库延迟
# --postpone-cut-over-flag-file  手动控制切换时机
```

### pt-osc vs gh-ost 对比

| 特性 | pt-online-schema-change | gh-ost |
|------|----------------------|--------|
| 同步机制 | 触发器 | binlog 复制 |
| 性能影响 | 中等 (触发器开销) | 低 (无触发器) |
| 暂停/恢复 | 困难 | 原生支持 |
| 动态限速 | 有限 | 灵活 |
| 外键支持 | 不支持 | 不支持 |
| 依赖 | 无特殊依赖 | 需要 ROW 格式 binlog |
| 切换方式 | RENAME TABLE | 多种 cut-over 策略 |

## PostgreSQL 的 Online DDL

### ADD COLUMN (PostgreSQL 11+)

```sql
-- PostgreSQL 11+: ADD COLUMN 带常量默认值是即时操作!
ALTER TABLE employees ADD COLUMN phone TEXT DEFAULT 'unknown';
-- 不重写表! 只修改系统目录 (pg_attribute + pg_attrdef)
-- 旧行读取时, 缺失的列返回默认值

-- PostgreSQL 10 及之前: 需要重写整个表!
-- 这是一个重大改进

-- 非常量默认值仍然需要重写:
ALTER TABLE employees ADD COLUMN created_at TIMESTAMP DEFAULT now();
-- PostgreSQL 11+: 也是即时操作! (记录 DDL 时间作为默认值)

-- ALTER TYPE 仍然需要重写:
ALTER TABLE employees ALTER COLUMN phone TYPE VARCHAR(100);
-- 需要重写整个表 (获取 ACCESS EXCLUSIVE 锁)
```

### CREATE INDEX CONCURRENTLY

```sql
-- PostgreSQL: 并发创建索引 (不阻塞写入)
CREATE INDEX CONCURRENTLY idx_phone ON employees(phone);

-- 内部流程:
-- 1. 开始事务, 获取 ShareUpdateExclusiveLock (不阻塞 DML)
-- 2. 第一次扫描: 构建索引 (此时不阻塞插入)
-- 3. 第二次扫描: 处理第一次扫描期间新插入的行
-- 4. 标记索引为有效 (短暂的 ShareLock)

-- 注意事项:
-- 1. 耗时更长 (两次扫描)
-- 2. 不能在事务块中使用
-- 3. 如果失败, 会留下 INVALID 索引, 需要手动 DROP

-- REINDEX 也支持 CONCURRENTLY (PostgreSQL 12+):
REINDEX INDEX CONCURRENTLY idx_phone;

-- 检查无效索引:
SELECT indexrelid::regclass, indisvalid
FROM pg_index WHERE NOT indisvalid;
```

### 其他 PostgreSQL DDL 特性

```sql
-- DROP COLUMN: 不重写表!
ALTER TABLE employees DROP COLUMN phone;
-- PostgreSQL 只标记列为已删除 (pg_attribute.attisdropped = true)
-- 空间不会立即回收, 但不需要重写
-- VACUUM FULL 时才真正移除死列的空间

-- RENAME: 即时
ALTER TABLE employees RENAME COLUMN phone TO mobile;
-- 只修改 pg_attribute, 不触碰数据

-- ALTER TABLE SET NOT NULL:
ALTER TABLE employees ALTER COLUMN name SET NOT NULL;
-- PostgreSQL 12+: 如果已有 CHECK 约束保证非 NULL, 无需全表扫描
-- PostgreSQL 11-: 需要全表扫描验证 (ACCESS EXCLUSIVE 锁)
```

## Oracle Online DDL

### Online DDL + Edition-Based Redefinition

```sql
-- Oracle: DBMS_REDEFINITION 包
-- 在线重定义表结构, 不阻塞 DML

-- 步骤 1: 检查是否可以在线重定义
BEGIN
    DBMS_REDEFINITION.CAN_REDEF_TABLE('SCHEMA', 'EMPLOYEES');
END;

-- 步骤 2: 创建临时表 (新结构)
CREATE TABLE employees_interim (
    id NUMBER,
    name VARCHAR2(100),
    phone VARCHAR2(20)     -- 新增列
);

-- 步骤 3: 开始重定义
BEGIN
    DBMS_REDEFINITION.START_REDEF_TABLE(
        uname => 'SCHEMA',
        orig_table => 'EMPLOYEES',
        int_table => 'EMPLOYEES_INTERIM',
        col_mapping => 'id id, name name, NULL phone'
    );
END;

-- 步骤 4: 同步增量数据 (可多次执行)
BEGIN
    DBMS_REDEFINITION.SYNC_INTERIM_TABLE('SCHEMA', 'EMPLOYEES', 'EMPLOYEES_INTERIM');
END;

-- 步骤 5: 完成重定义 (短暂锁)
BEGIN
    DBMS_REDEFINITION.FINISH_REDEF_TABLE('SCHEMA', 'EMPLOYEES', 'EMPLOYEES_INTERIM');
END;

-- Edition-Based Redefinition (EBR):
-- Oracle 11g R2+ 的高级特性
-- 通过"版本"机制实现零停机的应用升级
-- 不同的 session 可以看到表的不同版本 (通过 Cross-Edition Trigger)
```

### Oracle 即时 DDL

```sql
-- Oracle 12c+: ADD COLUMN 带默认值不重写表
ALTER TABLE employees ADD (phone VARCHAR2(20) DEFAULT 'N/A');
-- 元数据记录默认值, 旧行读取时填充

-- Oracle 12c+: ALTER TABLE 即时修改 (部分操作)
ALTER TABLE employees SET UNUSED (old_column);  -- 标记为未使用, 即时
ALTER TABLE employees DROP UNUSED COLUMNS;       -- 后台清理

-- Oracle: ADD NOT NULL COLUMN with DEFAULT
ALTER TABLE employees ADD (status VARCHAR2(10) DEFAULT 'active' NOT NULL);
-- 12c+: 即时操作! 不扫描表
```

## SQL Server Online DDL

```sql
-- SQL Server: ONLINE = ON (Enterprise Edition)
-- Enterprise 功能, Standard Edition 不支持

-- Online Index:
CREATE INDEX idx_phone ON employees(phone) WITH (ONLINE = ON);
ALTER INDEX idx_phone ON employees REBUILD WITH (ONLINE = ON);
DROP INDEX idx_phone ON employees WITH (ONLINE = ON);

-- Online ALTER COLUMN (SQL Server 2016+):
ALTER TABLE employees ALTER COLUMN phone VARCHAR(100) WITH (ONLINE = ON);

-- Resumable Index Operations (SQL Server 2017+):
CREATE INDEX idx_phone ON employees(phone)
WITH (ONLINE = ON, RESUMABLE = ON, MAX_DURATION = 240);
-- 可以暂停和恢复:
ALTER INDEX idx_phone ON employees PAUSE;
ALTER INDEX idx_phone ON employees RESUME;
-- 如果超时或服务器重启, 可以从断点继续

-- 低优先级锁等待 (SQL Server 2014+):
ALTER TABLE employees ADD phone VARCHAR(20)
WITH (ONLINE = ON, WAIT_AT_LOW_PRIORITY (MAX_DURATION = 10, ABORT_AFTER_WAIT = SELF));
-- MAX_DURATION: 等待锁的最大时间 (分钟)
-- ABORT_AFTER_WAIT: SELF (放弃 DDL) | BLOCKERS (杀掉阻塞者) | NONE
```

## ClickHouse 的异步 DDL

```sql
-- ClickHouse: ALTER 是异步 mutation
-- MergeTree 引擎的 ALTER 不阻塞读写

-- ADD/DROP COLUMN: 即时元数据操作
ALTER TABLE events ADD COLUMN phone String DEFAULT '';
ALTER TABLE events DROP COLUMN phone;
-- 只修改元数据, 不重写数据文件
-- 旧 part 在后台合并 (merge) 时才更新列

-- Mutations (UPDATE/DELETE): 异步执行
ALTER TABLE events UPDATE phone = 'unknown' WHERE phone = '';
ALTER TABLE events DELETE WHERE created_at < '2020-01-01';
-- 这些操作创建 mutation 任务, 在后台异步执行
-- 不阻塞查询, 但完成时间不确定

-- 查看 mutation 状态:
SELECT * FROM system.mutations WHERE table = 'events';

-- 等待 mutation 完成:
ALTER TABLE events UPDATE phone = 'unknown' WHERE phone = '' SETTINGS mutations_sync = 1;
-- mutations_sync = 0: 异步 (默认)
-- mutations_sync = 1: 同步等待本副本
-- mutations_sync = 2: 同步等待所有副本

-- MODIFY COLUMN (改类型): 异步重写
ALTER TABLE events MODIFY COLUMN phone FixedString(20);
-- 后台逐个重写 data part
```

## 对引擎开发者: DDL 不阻塞 DML 是生产环境刚需

### 实现方案选择

```
方案 1: 元数据版本化 (推荐)
  - Schema 变更只修改元数据 (列定义、默认值)
  - 读取时: 根据行的 schema 版本填充缺失列
  - 后台异步重写数据文件
  - 复杂度: 中等
  - 优点: DDL 瞬间完成, 对 DML 无影响
  - 缺点: 读取路径需要处理多版本 schema

方案 2: 影子表 + 增量同步
  - 创建新结构的表, 同步数据, 最终切换
  - 同步方式: 触发器 (pt-osc) 或 binlog (gh-ost)
  - 复杂度: 高
  - 优点: 对存储引擎侵入小
  - 缺点: 需要额外空间, 切换时短暂锁

方案 3: 追加式存储
  - LSM-Tree / MergeTree 天然支持
  - 新写入的数据用新 schema
  - 后台合并时统一 schema
  - 复杂度: 低 (如果存储引擎已是 LSM-Tree)
  - 优点: 天然 Online DDL
  - 缺点: 读取时需要合并不同 schema 的数据
```

### 关键实现细节

```
1. Metadata Lock (MDL):
   - DDL 需要获取 MDL 排他锁 (至少在 commit 阶段)
   - 与正在执行的长事务冲突!
   - MySQL 经典问题: ALTER TABLE 等待 MDL 锁
     -> 后续的 SELECT 也被阻塞 (等待 ALTER 释放 MDL)
     -> 连锁阻塞, 数据库假死
   - 解决: DDL 的 MDL 锁等待设置超时
     SET lock_wait_timeout = 5;

2. Schema 版本兼容:
   - 每行数据可能对应不同的 schema 版本
   - 读取时需要 schema 适配:
     if (row.schema_version < current_schema_version) {
         apply_default_values(row, current_schema);
     }
   - 写入时使用最新 schema

3. 索引的 Online 创建:
   - 扫描数据构建索引 (允许并发写入)
   - 记录构建期间的新增/删除
   - 构建完成后回放增量
   - 标记索引为可用

4. 回滚方案:
   - DDL 应该可以安全取消/回滚
   - 特别是长时间运行的 DDL (如创建大表索引)
   - gh-ost 的暂停/恢复是很好的参考
```

## 参考资料

- MySQL: [Online DDL Operations](https://dev.mysql.com/doc/refman/8.0/en/innodb-online-ddl-operations.html)
- PostgreSQL: [ALTER TABLE](https://www.postgresql.org/docs/current/sql-altertable.html)
- Oracle: [DBMS_REDEFINITION](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_REDEFINITION.html)
- gh-ost: [GitHub Online Schema Migration](https://github.com/github/gh-ost)
- pt-online-schema-change: [Percona Toolkit](https://docs.percona.com/percona-toolkit/pt-online-schema-change.html)
- SQL Server: [Online Index Operations](https://learn.microsoft.com/en-us/sql/relational-databases/indexes/perform-index-operations-online)
