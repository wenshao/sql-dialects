# SQLite: 序列

> 参考资料:
> - [SQLite Documentation - AUTOINCREMENT](https://www.sqlite.org/autoinc.html)
> - [SQLite Documentation - ROWIDs and the INTEGER PRIMARY KEY](https://www.sqlite.org/lang_createtable.html#rowid)
> - [SQLite Internals - Record Format](https://www.sqlite.org/fileformat2.html#record_format)

## SQLite 不支持 CREATE SEQUENCE（为什么）

SQLite 没有 SEQUENCE 对象。原因:
(a) 嵌入式数据库: SEQUENCE 是独立的数据库对象，需要额外管理
    SQLite 追求零管理，对象越少越好
(b) rowid 已经解决了自增需求: 每个表内置自增 rowid
(c) 无跨表 SEQUENCE 需求: 嵌入式应用通常不需要跨表共享序列

对比:
  PostgreSQL: CREATE SEQUENCE seq START 1 INCREMENT 1; + nextval('seq')
  Oracle:     CREATE SEQUENCE seq START WITH 1 INCREMENT BY 1; + seq.NEXTVAL
  SQL Server: CREATE SEQUENCE seq AS INT START WITH 1; + NEXT VALUE FOR seq
  MySQL:      无 SEQUENCE（用 AUTO_INCREMENT），8.0+ 也未添加
  ClickHouse: 无 SEQUENCE（分析引擎不需要）
  BigQuery:   无 SEQUENCE（分布式系统不适合全局自增）

## ROWID: SQLite 内置的自增机制

每个非 WITHOUT ROWID 表都有隐式的 64 位整数 rowid
```sql
CREATE TABLE users (
    id       INTEGER PRIMARY KEY,    -- id 成为 rowid 的别名
    username TEXT NOT NULL,
    email    TEXT NOT NULL
);
```

插入时 id 为 NULL 或不指定 → 自动分配 MAX(rowid) + 1
```sql
INSERT INTO users (username, email) VALUES ('alice', 'alice@e.com');
-- 等价于:
INSERT INTO users (id, username, email) VALUES (NULL, 'bob', 'bob@e.com');
```

获取最后插入的 rowid
```sql
SELECT last_insert_rowid();
```

rowid 分配算法:
  (1) 取当前 MAX(rowid) + 1
  (2) 如果 MAX(rowid) = 9223372036854775807（INT64 最大值）
      → 随机选择未使用的 rowid
      → 如果所有 rowid 都被占用（几乎不可能），INSERT 失败
  (3) 删除 MAX(rowid) 后，下一次 INSERT 可能复用该 ID
      → 这就是 AUTOINCREMENT 要解决的问题

## AUTOINCREMENT: 严格递增，绝不复用

```sql
CREATE TABLE orders (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    amount REAL
);
```

AUTOINCREMENT vs 默认行为:

| 特性           | INTEGER PRIMARY KEY | + AUTOINCREMENT     |
|----------------|---------------------|---------------------|
| 分配策略       | MAX(rowid) + 1      | MAX(rowid, seq) + 1 |
| ID 复用        | 是（删除后可能复用）| 否（严格递增）      |
| 额外开销       | 无                  | 维护 sqlite_sequence|
| 最大值后行为   | 随机选择未用 ID     | 报 SQLITE_FULL 错误 |

sqlite_sequence 表:
AUTOINCREMENT 表的当前最大 ID 记录在 sqlite_sequence 系统表中。
每次 INSERT 需要: 读取 sqlite_sequence → 比较 → 更新 → 插入行
这是额外的 I/O 开销，官方文档明确说"通常不需要 AUTOINCREMENT"。

查看 sqlite_sequence
```sql
SELECT * FROM sqlite_sequence;
```

输出: name='orders', seq=42（最后分配的 ID）

重置序列（不推荐，可能导致主键冲突）
```sql
UPDATE sqlite_sequence SET seq = 0 WHERE name = 'orders';
DELETE FROM sqlite_sequence WHERE name = 'orders';
```

## 类型陷阱: INTEGER vs INT（对引擎开发者）

只有 "INTEGER PRIMARY KEY" 才会成为 rowid 的别名。
"INT PRIMARY KEY" 不会!

```sql
CREATE TABLE t1 (id INTEGER PRIMARY KEY);  -- id = rowid 别名（自增）
CREATE TABLE t2 (id INT PRIMARY KEY);      -- id 是普通列 + 主键索引!

-- 这是因为 SQLite 的类型亲和性规则:
--   "INTEGER" → INTEGER 亲和性，触发 rowid 别名机制
--   "INT"     → INTEGER 亲和性，但关键字不是 "INTEGER"，不触发!
--
-- 这是 SQLite 最知名的陷阱之一。内部实现区分的是关键字文本，不是类型语义。
-- 如果你在设计 SQL 引擎，这是应该避免的设计: 类型别名应该完全等价。
```

## UUID 替代方案

SQLite 没有内置 UUID 函数（3.41.0 之前）

方法 1: 使用 randomblob 模拟 UUIDv4
```sql
SELECT lower(hex(randomblob(4))) || '-' ||
       lower(hex(randomblob(2))) || '-4' ||
       substr(lower(hex(randomblob(2))),2) || '-' ||
       substr('89ab', abs(random()) % 4 + 1, 1) ||
       substr(lower(hex(randomblob(2))),2) || '-' ||
       lower(hex(randomblob(6)));
```

方法 2: 加载 uuid 扩展（如果可用）
```sql
SELECT uuid();
```

方法 3: 使用 TEXT 列存储外部生成的 UUID
```sql
CREATE TABLE items (
    id   TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    name TEXT NOT NULL
);
```

## WITHOUT ROWID 表（3.8.2+）

WITHOUT ROWID 表没有隐式 rowid，主键直接存储在 B-Tree 键中
```sql
CREATE TABLE kv_store (
    key   TEXT PRIMARY KEY,
    value TEXT
) WITHOUT ROWID;
```

用途: 当主键不是整数时（如字符串键），WITHOUT ROWID 更高效
因为避免了维护 rowid 到主键的映射
但: 不能使用 AUTOINCREMENT（没有 rowid）

## 对比与引擎开发者启示

SQLite 的自增设计是最精简的:
  rowid 内置 → 零额外开销的自增主键
  AUTOINCREMENT → 可选的严格递增保证（有开销）
  无 SEQUENCE → 不需要独立对象管理

对引擎开发者的启示:
  (1) 内置 rowid 消除了 90% 的自增需求，是优雅的设计
  (2) AUTOINCREMENT 作为 opt-in 的严格保证是好的分层设计
  (3) INTEGER vs INT 的陷阱是应该避免的: 类型别名应完全等价
  (4) 嵌入式引擎不需要 SEQUENCE 对象（应用层可以自己管理）
  (5) 现代趋势是 UUID 替代自增（分布式环境），应考虑内置 UUID 函数
