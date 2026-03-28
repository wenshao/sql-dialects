# SQLite: CREATE TABLE

> 参考资料:
> - [SQLite Documentation - CREATE TABLE](https://www.sqlite.org/lang_createtable.html)
> - [SQLite Documentation - Datatypes In SQLite](https://www.sqlite.org/datatype3.html)
> - [SQLite Documentation - STRICT Tables](https://www.sqlite.org/stricttables.html)
> - [SQLite Documentation - WITHOUT ROWID Tables](https://www.sqlite.org/withoutrowid.html)

## 基本建表

一个典型的业务表，但几乎每一行都藏着 SQLite 的设计哲学
```sql
CREATE TABLE users (
    id         INTEGER      PRIMARY KEY,           -- 见下文: 为什么不加 AUTOINCREMENT
    username   TEXT         NOT NULL UNIQUE,
    email      TEXT         NOT NULL UNIQUE,
    age        INTEGER,
    balance    REAL         DEFAULT 0.00,           -- SQLite 没有 DECIMAL，见类型亲和性
    bio        TEXT,
    created_at TEXT         NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT         NOT NULL DEFAULT (datetime('now'))
);
```

设计要点:
  1. INTEGER PRIMARY KEY = rowid 的别名（这是 SQLite 最核心的概念之一，见下文）
  2. 没有 AUTOINCREMENT: 故意的（见下文详解）
  3. 日期用 TEXT: SQLite 没有原生日期类型，TEXT/REAL/INTEGER 都行
     TEXT: '2024-01-15 08:30:00' (ISO 8601，人类可读，推荐)
     REAL: Julian day number (2460324.354167)
     INTEGER: Unix timestamp (1705300200)
  4. 没有 ON UPDATE: SQLite 不支持，需要触发器

SQLite 没有 ON UPDATE CURRENT_TIMESTAMP，需要用触发器
```sql
CREATE TRIGGER trg_users_updated_at
    AFTER UPDATE ON users
    FOR EACH ROW
BEGIN
    UPDATE users SET updated_at = datetime('now') WHERE id = NEW.id;
END;
```

## INTEGER PRIMARY KEY vs AUTOINCREMENT

这是从 MySQL/PostgreSQL 转过来最容易误解的地方

INTEGER PRIMARY KEY（推荐）:
  - 自动成为 rowid 的别名（SQLite 内部的 64 位行标识符）
  - 不指定值时自动分配: max(rowid) + 1
  - 删除最大 id 的行后，该 id 可能被复用
  - 性能: 通过 rowid 查找是 SQLite 最快的操作 (B-tree 叶节点直达)

INTEGER PRIMARY KEY AUTOINCREMENT（通常不需要）:
  - 额外维护一张 sqlite_sequence 表记录每张表用过的最大 id
  - 保证 id 只增不减、不复用（即使行被删除）
  - 代价: 每次 INSERT 额外读写 sqlite_sequence，约 5-10% 性能开销
  - 更严格的上限: 达到 9223372036854775807 后直接报错（不会尝试找空洞）

SQLite 官方文档原话: "AUTOINCREMENT keyword imposes extra CPU, memory, I/O,
and disk space overhead and should be avoided if not strictly needed."

什么时候真的需要 AUTOINCREMENT?
  - 法规要求 id 不可复用（如发票号、审计序号）
  - 除此之外几乎不需要

> **注意**: 必须写 INTEGER 而不是 INT!
CREATE TABLE t (id INT PRIMARY KEY);       -- 这不是 rowid 别名!
CREATE TABLE t (id INTEGER PRIMARY KEY);   -- 这才是 rowid 别名
原因: SQLite 的类型亲和性规则只认 "INTEGER" 这个精确拼写

## 类型亲和性 (Type Affinity) — SQLite 最独特的设计

SQLite 的类型系统是动态的: 类型附着在值上，不附着在列上
列声明的类型只是"建议"（affinity），不是强制约束

五种亲和性: TEXT, NUMERIC, INTEGER, REAL, BLOB
亲和性判定规则（按优先级）:
  1. 类型名含 "INT"          → INTEGER  (e.g., INT, BIGINT, SMALLINT, TINYINT)
  2. 类型名含 "CHAR/CLOB/TEXT" → TEXT   (e.g., VARCHAR(255), NCHAR, TEXT)
  3. 类型名含 "BLOB" 或无类型  → BLOB   (e.g., BLOB, 或省略类型)
  4. 类型名含 "REAL/FLOA/DOUB" → REAL   (e.g., REAL, FLOAT, DOUBLE)
  5. 其他所有               → NUMERIC   (e.g., DECIMAL, BOOLEAN, DATE, NUMERIC)

以下全部合法:
```sql
CREATE TABLE type_demo (
    a FLUFFY_BUNNY,           -- NUMERIC 亲和性（不匹配任何规则，走规则 5）
    b VARCHAR(255),           -- TEXT 亲和性（含 CHAR，规则 2）
    c BOOLEAN,                -- NUMERIC 亲和性（SQLite 没有布尔类型，存 0/1）
    d BIGINT,                 -- INTEGER 亲和性（含 INT，规则 1）
    e DECIMAL(10,2),          -- NUMERIC 亲和性（规则 5）
    f                         -- BLOB 亲和性（无类型声明，规则 3）
);
```

你可以写 INSERT INTO type_demo(a) VALUES ('hello'); -- 完全合法，即使列是 NUMERIC 亲和性
这就是为什么 "FLUFFY BUNNY" 是一个合法的类型: SQLite 真的不在乎类型名称
它只看类型名是否包含特定关键词来决定亲和性

## STRICT 表 (3.37.0+, 2021-11) — 终于有类型检查了

如果你不想要动态类型的"惊喜"，用 STRICT 表
```sql
CREATE TABLE strict_users (
    id       INTEGER PRIMARY KEY,
    name     TEXT NOT NULL,
    age      INTEGER,
    score    REAL,
    data     BLOB,
    misc     ANY                  -- STRICT 表特有的 ANY 类型，允许任何类型
) STRICT;
```

STRICT 表只允许 5 种类型: INTEGER, REAL, TEXT, BLOB, ANY
尝试插入不匹配类型的值会报错:
```sql
INSERT INTO strict_users (age) VALUES ('hello'); → Error: type mismatch
```

但 INTEGER 列仍然接受小数值 (会被截断)

> **建议**: 新项目如果用 SQLite 3.37+，优先考虑 STRICT 表
它给了你接近传统数据库的类型安全，同时保留 SQLite 的简洁

## WITHOUT ROWID 表

普通 SQLite 表底层是两棵 B-tree: 一棵用 rowid 做键（数据），一棵用于索引
WITHOUT ROWID 表只有一棵 B-tree，用 PRIMARY KEY 做键
```sql
CREATE TABLE kv_store (
    key   TEXT PRIMARY KEY,
    value BLOB
) WITHOUT ROWID;
```

什么时候用 WITHOUT ROWID:
  1. 主键不是 INTEGER (如 UUID、复合主键)
  2. 行很小 (没有大型 TEXT/BLOB 列)
  3. 查询主要通过主键
什么时候不用:
  1. 主键是 INTEGER（普通表已经用 rowid，WITHOUT ROWID 没有优势）
  2. 行很大（WITHOUT ROWID 表不适合大行，因为数据存在 B-tree 内部节点附近）
  3. 需要用 rowid 引用行（一些 ORM 和工具依赖 rowid）

典型场景: 关联表、配置表、缓存表
```sql
CREATE TABLE user_roles (
    user_id  INTEGER NOT NULL,
    role_id  INTEGER NOT NULL,
    PRIMARY KEY (user_id, role_id)
) WITHOUT ROWID;
```

复合主键 + 小行 = WITHOUT ROWID 的完美场景
比普通表节省约 10-50% 的磁盘空间

## 虚拟表 (Virtual Tables)

虚拟表是 SQLite 的扩展机制，提供了远超普通表的能力

FTS5: 全文搜索 (最常用的虚拟表)
```sql
CREATE VIRTUAL TABLE articles_fts USING fts5(
    title,
    body,
    content='articles',          -- 外部内容表 (避免数据冗余)
    content_rowid='id'
);
```

查询: SELECT * FROM articles_fts WHERE articles_fts MATCH 'sqlite AND performance';
支持: 前缀查询、短语匹配、BM25 排名、列过滤

R*Tree: 空间索引 (地理位置、范围查询)
```sql
CREATE VIRTUAL TABLE locations USING rtree(
    id,
    min_lat, max_lat,            -- 纬度范围
    min_lon, max_lon             -- 经度范围
);
```

查询: WHERE min_lat <= 40.7 AND max_lat >= 40.7 AND min_lon <= -74.0 AND max_lon >= -74.0

JSON: 虽然不是虚拟表，但 SQLite 3.38.0+ 内置 JSON 函数
json(), json_extract(), json_array(), json_object(), json_each(), json_tree()
3.38.0+ 支持 -> 和 ->> 运算符

## 文件架构的实际影响

SQLite 是一个单文件数据库。这决定了它的几乎所有特性和限制:

最大数据库大小: 281 TB (2^44 页 × 64KB/页)，但实际受文件系统限制
最大行大小: 默认 1GB (由 SQLITE_MAX_LENGTH 控制)
最大列数: 默认 2000 (可编译时调到 32767)
并发: 整个数据库一个文件 → 整个数据库一把写锁

WAL 模式 (Write-Ahead Logging):
```sql
PRAGMA journal_mode = WAL;       -- 设置后持久生效（存储在数据库文件中）
-- DELETE 模式 (默认): 写入时锁住整个数据库，读写互斥
-- WAL 模式: 读写可以并发，多个读可以同时进行，但写仍然互斥
-- WAL 模式的代价:
--   - 额外产生 .wal 和 .shm 文件
--   - 不支持网络文件系统 (NFS)! 这是最常见的坑
--   - CHECKPOINT 操作可能导致短暂延迟
--
-- 性能提示:
PRAGMA synchronous = NORMAL;     -- WAL 模式下安全且快速 (默认 FULL)
PRAGMA cache_size = -64000;      -- 64MB 页缓存 (负数 = KB)
PRAGMA mmap_size = 268435456;    -- 256MB 内存映射 (加速大型读查询)
PRAGMA temp_store = MEMORY;      -- 临时表存内存
```

## 从 MySQL/PostgreSQL 转过来的常见错误

1. 写 INT 而不是 INTEGER 作为主键 (上面已解释)
2. 期望 VARCHAR(255) 限制字符串长度 (SQLite 不强制长度)
3. 用多线程并发写入 (SQLite 写操作是序列化的)
4. 在 NFS/网络驱动器上使用 SQLite (文件锁不可靠，会导致数据损坏)
5. 认为 UNIQUE 约束在 NULL 上生效 (NULL != NULL，所以多个 NULL 不冲突)
### 期望 ALTER TABLE 和 MySQL 一样强大

   SQLite ALTER TABLE 只支持: RENAME TABLE, RENAME COLUMN, ADD COLUMN, DROP COLUMN (3.35+)
   不支持: 修改列类型、添加约束、删除约束 (需要重建表)
### 忘记设置 busy_timeout

```sql
PRAGMA busy_timeout = 5000;      -- 不设置的话，并发写入直接报 SQLITE_BUSY 错误
-- 8. 期望 DROP COLUMN 释放空间 (需要 VACUUM 才能回收空间)
```

## CREATE TABLE ... AS / IF NOT EXISTS

```sql
CREATE TABLE active_users AS
SELECT id, username, email FROM users WHERE age >= 18;
-- 注意: 新表不继承 PRIMARY KEY、UNIQUE、索引等约束

CREATE TABLE IF NOT EXISTS audit_log (
    id      INTEGER PRIMARY KEY,
    action  TEXT    NOT NULL,
    details TEXT,
    ts      TEXT    NOT NULL DEFAULT (datetime('now'))
);
```

## 版本演进总结

3.7.0  (2010): WAL 模式
3.8.2  (2013): WITHOUT ROWID 表
3.24.0 (2018): UPSERT (ON CONFLICT DO UPDATE)
3.25.0 (2018): RENAME COLUMN, 窗口函数
3.30.0 (2019): FILTER 子句
3.31.0 (2020): 生成列 (GENERATED ALWAYS AS)
3.33.0 (2020): UPDATE ... FROM (multi-table update)
3.35.0 (2021): DROP COLUMN, 内置数学函数, 物化 CTE
3.37.0 (2021): STRICT 表
3.38.0 (2022): JSON 操作符 -> / ->>
3.39.0 (2022): JSON5 支持
3.45.0 (2024): JSON 子类型改进
