# SQLite: ALTER TABLE

> 参考资料:
> - [SQLite Documentation - ALTER TABLE](https://www.sqlite.org/lang_altertable.html)
> - [SQLite Internals - File Format (table schema stored in sqlite_master)](https://www.sqlite.org/fileformat2.html)
> - [SQLite Documentation - CREATE TABLE (for rebuild approach)](https://www.sqlite.org/lang_createtable.html)

## 基本语法

重命名表（所有版本）
```sql
ALTER TABLE users RENAME TO members;
```

添加列（所有版本）
```sql
ALTER TABLE users ADD COLUMN phone TEXT;
```

3.25.0+: 重命名列
```sql
ALTER TABLE users RENAME COLUMN phone TO mobile;
```

3.35.0+: 删除列
```sql
ALTER TABLE users DROP COLUMN phone;
```

## 为什么 ALTER TABLE 如此受限（对引擎开发者）

### SQLite 的 schema 存储模型

SQLite 将 CREATE TABLE 语句的 SQL 文本直接存储在 sqlite_master 表中。
不像 MySQL/PostgreSQL 维护列元数据目录（column catalog），
SQLite 在打开表时重新解析这条 SQL 文本来获取 schema 信息。

这意味着:
  RENAME TABLE → 只需修改 sqlite_master 中的表名字符串
  ADD COLUMN   → 只需在 SQL 文本末尾追加列定义
  修改列类型   → 需要重写 SQL 文本 + 重写所有数据页（SQLite 选择不支持）

设计 trade-off:
  优点: 极简实现，零元数据开销，数据库文件自描述
  缺点: ALTER TABLE 能力严重受限，不支持修改列类型/约束/默认值

对比:
  MySQL:      维护 information_schema，ALTER TABLE 功能完整（Online DDL）
  PostgreSQL: 维护 pg_catalog，ADD COLUMN + DEFAULT 11+ 即时完成
  SQL Server: 维护 sys.columns，ALTER COLUMN 可直接修改类型

### ADD COLUMN 的限制及原因

新增列有诸多限制，根源在于 SQLite 追加列时不重写已有数据行:
  (a) 不能有 PRIMARY KEY 或 UNIQUE 约束 → 因为已有行未建索引
  (b) 默认值不能是 CURRENT_TIMESTAMP 等非常量表达式（3.37.0 之前）
      → 因为已有行需要填充默认值，非常量值需要逐行计算
  (c) 不支持 AFTER / FIRST 语法 → 列总是追加到末尾
      → 因为 SQLite 按物理顺序存储列，插入中间意味着重写全表

3.37.0+ 放宽了默认值限制: 允许括号包裹的常量表达式
```sql
ALTER TABLE users ADD COLUMN created_at TEXT DEFAULT (datetime('now'));
```

### DROP COLUMN 为何到 3.35.0 才支持（2021年3月）

SQLite 诞生于 2000 年，DROP COLUMN 晚了 21 年，原因:
  (a) 单文件架构: 删除列需要重写整个数据文件的所有行
  (b) 早期定位: 嵌入式数据库不需要复杂的 schema 演进
  (c) 已有替代方案: 重建表（见下文第 3 节）

3.35.0 的 DROP COLUMN 实现:
  内部仍然是重建表，但对用户透明。限制:
  - 不能删除唯一可用的列（至少保留一列）
  - 不能删除主键列
  - 不能删除有索引/触发器/外键引用的列
  - 不能删除 CHECK 约束或生成列表达式引用的列

## 重建表模式: SQLite 的 ALTER TABLE 替代方案

这是 SQLite 官方推荐的 schema 变更方法，适用于所有修改类型。
本质上是 CREATE-COPY-DROP-RENAME 四步操作。

```sql
PRAGMA foreign_keys = OFF;  -- 必须先关闭，否则 DROP 旧表会触发外键检查

BEGIN TRANSACTION;  -- DDL 在 SQLite 中是事务性的!（与 PostgreSQL 类似）

-- 步骤 1: 创建具有新 schema 的表
CREATE TABLE users_new (
    id       INTEGER PRIMARY KEY,           -- 去掉了 AUTOINCREMENT
    username TEXT    NOT NULL,
    email    TEXT    NOT NULL,
    age      INTEGER CHECK (age >= 0),      -- 新增 CHECK 约束
    phone    TEXT    NOT NULL DEFAULT ''     -- 修改了 NULL 约束
);
```

步骤 2: 复制数据
```sql
INSERT INTO users_new (id, username, email, age)
SELECT id, username, email, age FROM users;
```

步骤 3: 删除旧表
```sql
DROP TABLE users;
```

步骤 4: 重命名新表
```sql
ALTER TABLE users_new RENAME TO users;
```

步骤 5: 重建索引和触发器（被 DROP TABLE 一起删除了）
```sql
CREATE UNIQUE INDEX idx_users_email ON users(email);

COMMIT;

PRAGMA foreign_keys = ON;   -- 恢复外键检查
```

设计分析:
  优点: DDL 事务性保证操作原子性（全成功或全回滚）
  缺点: 需要全表重写，大表耗时；索引/触发器/视图需要手动重建
  对比 MySQL: ALTER TABLE ... ALGORITHM=INSTANT 零拷贝（但仅限部分操作）
  对比 PostgreSQL: 事务性 DDL 但不需要重建表（ALTER COLUMN TYPE 除外）

## PRAGMA 的 schema 修改功能

SQLite 的很多 schema 操作通过 PRAGMA 而非 ALTER TABLE 完成

启用/禁用外键检查
```sql
PRAGMA foreign_keys = ON;
PRAGMA foreign_key_check;     -- 检查所有外键完整性
```

查看表结构
```sql
PRAGMA table_info(users);     -- 列名、类型、NOT NULL、默认值、主键
PRAGMA table_xinfo(users);    -- 3.26.0+, 包含隐藏列和生成列

-- WAL 模式切换（影响并发性能，非严格意义上的 schema 变更，但影响全库行为）
PRAGMA journal_mode = WAL;
```

STRICT 表不能通过 ALTER 添加（只能在 CREATE TABLE 时声明）
3.37.0+: CREATE TABLE t (...) STRICT;

## schema 版本管理（对引擎开发者）

### user_version PRAGMA: 应用层 schema 版本追踪

```sql
PRAGMA user_version = 3;            -- 设置版本号
-- PRAGMA user_version;             -- 读取版本号
-- 应用启动时读取 user_version，决定是否执行迁移脚本。
-- 这是 Android/iOS 的 SQLite 数据库迁移的标准模式。

-- 5.2 schema_version: SQLite 内部使用
-- PRAGMA schema_version;  -- 每次 schema 变更自动递增
-- 不要手动修改（会导致 prepared statement 失效）

-- 对比其他数据库的迁移方案:
--   MySQL/PostgreSQL: Flyway/Liquibase 等外部工具管理迁移版本
--   Rails:            ActiveRecord Migrations（schema_migrations 表）
--   SQLite:           内置 PRAGMA 即可，无需外部工具（嵌入式优势）
```

## 版本演进

### (2004): 基本 ALTER TABLE（RENAME TABLE, ADD COLUMN）

### (2018): RENAME COLUMN（等了 14 年）

### (2021): DROP COLUMN（等了 17 年）

### (2021): STRICT 表模式

未支持（且可能永远不会支持）:
  ALTER COLUMN TYPE（需要重写全表数据，用重建表替代）
  ADD CONSTRAINT（需要修改 sqlite_master 中存储的 SQL 文本）
  DROP CONSTRAINT（同上）

对引擎开发者的启示:
  SQLite 的 ALTER TABLE 受限是"将 DDL SQL 文本作为 schema 元数据"这一设计选择的
  直接后果。如果要设计嵌入式数据库，需要在元数据表示方式（SQL 文本 vs 结构化目录）
  之间做权衡: SQL 文本更简洁自描述，但牺牲了 schema 演进能力。
