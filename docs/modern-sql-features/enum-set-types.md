# ENUM 与 SET 类型 (ENUM and SET Types)

枚举类型用一个紧凑的整数承载一组受限的字符串取值——它在存储上看起来是 `TINYINT`，在查询里看起来是 `VARCHAR`，在 ALTER 里却又是另一回事。MySQL 的 `SET` 更进一步，把 64 个布尔标志压进一个 8 字节整数。这些类型至今仍是引擎实现差异最大的语义点之一。

## 类型语义概述

### ENUM：受约束的字符串集合

ENUM 类型存储一个**预先声明的字符串列表中的某一个值**。从用户视角是字符串，从存储视角是整数索引：

```sql
-- MySQL 经典 ENUM 用法
CREATE TABLE orders (
    id INT PRIMARY KEY,
    status ENUM('pending', 'paid', 'shipped', 'delivered', 'cancelled')
);

INSERT INTO orders VALUES (1, 'paid');
SELECT status FROM orders WHERE id = 1;  -- 'paid'

-- 物理存储：'paid' 实际占用 1 字节（索引 2，因为 'pending' 是 1）
-- 查询时引擎查表把整数翻译回字符串
```

存储模型：
- **1 字节**：当 ENUM 取值不超过 255 个时
- **2 字节**：当 ENUM 取值在 256 到 65535 之间时
- 字符串本身只在元数据中存储一次，每行只存索引

### SET：MySQL 独有的位集合类型

SET 是 MySQL 独有的类型，在一行中可以同时存储**多个**预声明值的组合，物理上是一个 64 位的位掩码：

```sql
-- 一个用户可以同时拥有多种偏好
CREATE TABLE users (
    id INT PRIMARY KEY,
    preferences SET('email', 'sms', 'push', 'newsletter', 'survey')
);

INSERT INTO users VALUES (1, 'email,push');
INSERT INTO users VALUES (2, 'sms,newsletter,survey');

-- 查询：FIND_IN_SET 或字符串匹配
SELECT * FROM users WHERE FIND_IN_SET('push', preferences) > 0;
SELECT * FROM users WHERE preferences & 4;  -- 按位与

-- 物理存储：'email,push' = 0b00101 = 5 = 1 字节
-- 'sms,newsletter,survey' = 0b11010 = 26 = 1 字节
```

存储模型（位掩码）：
- **1 字节**：1-8 个成员
- **2 字节**：9-16 个成员
- **3 字节**：17-24 个成员
- **4 字节**：25-32 个成员
- **8 字节**：33-64 个成员
- 上限严格固定为 64 个成员

### ALTER 的隐藏代价

ENUM 在大多数引擎上**不能轻易添加或重排取值**。这是工程上最常被低估的成本：

```sql
-- MySQL：ALTER TABLE 修改 ENUM 取值
-- 添加新值（追加到末尾，通常是 in-place）
ALTER TABLE orders MODIFY status
    ENUM('pending', 'paid', 'shipped', 'delivered', 'cancelled', 'refunded');

-- 重排或删除（必须重写整张表，可能耗时数小时）
ALTER TABLE orders MODIFY status
    ENUM('paid', 'pending', 'shipped', 'delivered', 'cancelled');
-- 索引 1 从 'pending' 变成 'paid'，所有行需要重新映射
```

PostgreSQL 通过独立的 `CREATE TYPE ... AS ENUM` 提供更优雅的方案，但仍有限制：

```sql
CREATE TYPE order_status AS ENUM ('pending', 'paid', 'shipped');

-- 9.1+ 支持 ALTER TYPE ADD VALUE
ALTER TYPE order_status ADD VALUE 'refunded';                -- 追加
ALTER TYPE order_status ADD VALUE 'reviewing' BEFORE 'paid'; -- 插入

-- 限制：12.0 之前 ADD VALUE 不能在事务中使用
-- 限制：至今不能 DROP 或 RENAME 单个值（必须重建类型）
```

## SQL 标准

### SQL:2003 之前：无 ENUM

SQL-92、SQL:1999、SQL:2003 标准都**没有定义 ENUM 类型**。受限字符串集合的标准做法是 `CHECK` 约束：

```sql
-- SQL 标准方案：CHECK 约束
CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    status VARCHAR(20) NOT NULL
        CHECK (status IN ('pending', 'paid', 'shipped', 'delivered', 'cancelled'))
);
```

### SQL:2008：DOMAIN 与 CHECK

SQL:2008 引入 `CREATE DOMAIN` 用于复用约束定义：

```sql
-- SQL:2008 标准 DOMAIN
CREATE DOMAIN order_status_domain AS VARCHAR(20)
    CHECK (VALUE IN ('pending', 'paid', 'shipped', 'delivered', 'cancelled'));

CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    status order_status_domain NOT NULL
);
```

DOMAIN 在 PostgreSQL、Oracle、DB2 上有较好支持，但在 MySQL、SQL Server 上不可用。即使在支持 DOMAIN 的引擎上，DOMAIN 仍然按 VARCHAR 实际长度存储，没有 ENUM 的整数压缩优势。

### SET 完全是非标准

`SET` 类型从未进入任何 ISO SQL 标准，是 MySQL 引入的扩展。其最近的标准对应物是 SQL:1999 引入的 `MULTISET`（更强的类型，但仅 DB2 与 Oracle 部分实现）。

## 跨引擎支持矩阵（45+ 引擎）

### 矩阵一：原生 ENUM 类型支持

| 引擎 | 原生 ENUM | 引入版本 | 类型语法 | 替代方案 |
|------|----------|---------|---------|---------|
| MySQL | 是 | 4.0 (2003) | `ENUM('a','b',...)` | -- |
| MariaDB | 是 | 5.1+ (继承 MySQL) | `ENUM('a','b',...)` | -- |
| PostgreSQL | 是 | 8.3 (2008) | `CREATE TYPE ... AS ENUM` | -- |
| ClickHouse | 是 | 早期 (2016+) | `Enum8` / `Enum16` | -- |
| CockroachDB | 是 | 20.2 (2020-11) | `CREATE TYPE ... AS ENUM` | -- |
| YugabyteDB | 是 | 2.0+ (继承 PG) | `CREATE TYPE ... AS ENUM` | -- |
| Greenplum | 是 | 5.0+ (继承 PG) | `CREATE TYPE ... AS ENUM` | -- |
| TimescaleDB | 是 | 全版本 (继承 PG) | `CREATE TYPE ... AS ENUM` | -- |
| Citus | 是 | 全版本 (继承 PG) | `CREATE TYPE ... AS ENUM` | -- |
| Neon | 是 | 全版本 (继承 PG) | `CREATE TYPE ... AS ENUM` | -- |
| Aurora MySQL | 是 | 全版本 (继承 MySQL) | `ENUM('a','b',...)` | -- |
| Aurora PostgreSQL | 是 | 全版本 (继承 PG) | `CREATE TYPE ... AS ENUM` | -- |
| TiDB | 是 | 早期 (兼容 MySQL) | `ENUM('a','b',...)` | -- |
| OceanBase | 是 | MySQL 模式 | `ENUM('a','b',...)` | -- |
| PolarDB | 是 | MySQL/PG 模式 | 同上游 | -- |
| Vitess | 是 | 全版本 (代理 MySQL) | `ENUM('a','b',...)` | -- |
| SingleStore (MemSQL) | 是 | 7.0+ | `ENUM('a','b',...)` | -- |
| Doris | 不支持 | -- | -- | `VARCHAR + CHECK`（弱） |
| StarRocks | 不支持 | -- | -- | `VARCHAR` |
| Oracle | 不支持 | -- | -- | `CHECK` 约束或 `VARRAY` |
| SQL Server | 不支持 | -- | -- | `CHECK` 约束 |
| Azure Synapse | 不支持 | -- | -- | `CHECK` 约束 |
| Azure SQL DB | 不支持 | -- | -- | `CHECK` 约束 |
| Snowflake | 不支持 | -- | -- | `VARCHAR + CHECK` |
| BigQuery | 不支持 | -- | -- | `STRING + CHECK`（弱） |
| Redshift | 不支持 | -- | -- | `VARCHAR + CHECK`（弱） |
| Databricks | 不支持 | -- | -- | `STRING + CHECK` |
| Spark SQL | 不支持 | -- | -- | `STRING + CHECK`（弱） |
| Trino | 不支持 | -- | -- | 无（连接器透传） |
| Presto | 不支持 | -- | -- | 无（连接器透传） |
| Hive | 不支持 | -- | -- | `STRING` |
| Impala | 不支持 | -- | -- | `STRING` |
| DB2 | 不支持 | -- | -- | `CHECK` 约束或 `DISTINCT TYPE` |
| SAP HANA | 不支持 | -- | -- | `CHECK` 约束 |
| SAP ASE | 不支持 | -- | -- | `RULE` 或 `CHECK` |
| Sybase IQ | 不支持 | -- | -- | `CHECK` 约束 |
| Teradata | 不支持 | -- | -- | `CHECK` 约束 |
| Vertica | 不支持 | -- | -- | `CHECK` 约束 |
| Informix | 不支持 | -- | -- | `CHECK` 约束 |
| Firebird | 不支持 | -- | -- | `DOMAIN + CHECK` |
| H2 | 是 | 1.4.200+ | `ENUM('a','b',...)` (MySQL 兼容) | -- |
| HSQLDB | 不支持 | -- | -- | `CHECK` 约束 |
| Derby | 不支持 | -- | -- | `CHECK` 约束 |
| SQLite | 不支持 | -- | -- | `TEXT + CHECK` |
| DuckDB | 是 | 0.4 (2022) | `CREATE TYPE ... AS ENUM` | -- |
| QuestDB | 是 | 7.0+ | `SYMBOL` (变种) | -- |
| Crate DB | 不支持 | -- | -- | `TEXT + CHECK` |
| Materialize | 是 | 全版本 (继承 PG) | `CREATE TYPE ... AS ENUM` | -- |
| Exasol | 不支持 | -- | -- | `CHECK` 约束 |
| Yellowbrick | 不支持 | -- | -- | `VARCHAR + CHECK` |
| Firebolt | 不支持 | -- | -- | `TEXT + CHECK` |
| RisingWave | 不支持 | -- | -- | `VARCHAR` |
| MonetDB | 不支持 | -- | -- | `CHECK` 约束 |
| KingbaseES | 是 | (继承 PG) | `CREATE TYPE ... AS ENUM` | -- |
| OpenGauss | 是 | (继承 PG) | `CREATE TYPE ... AS ENUM` | -- |

> 统计：约 25 个引擎提供原生 ENUM，30+ 引擎只能用 `CHECK` 约束模拟。两大阵营泾渭分明：MySQL/PG 系列原生支持，分析型/商业 OLTP 多数不支持。

### 矩阵二：SET / 多值位集合支持

| 引擎 | 原生 SET | 上限 | 物理存储 | 替代方案 |
|------|---------|------|---------|---------|
| MySQL | 是 | 64 | 1/2/3/4/8 字节位掩码 | -- |
| MariaDB | 是 | 64 | 同 MySQL | -- |
| TiDB | 是 (兼容) | 64 | 同 MySQL | -- |
| OceanBase | 是 (MySQL 模式) | 64 | 同 MySQL | -- |
| Aurora MySQL | 是 | 64 | 同 MySQL | -- |
| Vitess | 是 | 64 | 同 MySQL | -- |
| SingleStore | 是 | 64 | 同 MySQL | -- |
| H2 | 不支持 | -- | -- | `BIT` 列或 `BIGINT` 位掩码 |
| PostgreSQL | 不支持 | -- | -- | `bit varying`、`int[]`、自定义类型 |
| ClickHouse | 不支持 | -- | -- | `Array(Enum8)` |
| Oracle | 不支持 | -- | -- | `RAW` 位掩码或 `VARRAY` |
| SQL Server | 不支持 | -- | -- | `BIGINT` 位掩码或多个 `BIT` 列 |
| 其他 | 不支持 | -- | -- | `BIGINT` + 位运算 |

> SET 是 MySQL 生态独有特性。即使 MariaDB / TiDB / OceanBase 也仅是为兼容 MySQL 协议而实现，原生开发的引擎几乎一致选择不实现这一类型。

### 矩阵三：ENUM 取值变更能力（ALTER）

| 引擎 | 添加值 | 在中间插入 | 重命名值 | 删除值 | 是否需要重写表 |
|------|-------|-----------|---------|-------|--------------|
| MySQL | 是（追加） | 是（中间） | 是（按位置匹配） | 是 | 取决于位置；末尾追加可 in-place |
| MariaDB | 是 | 是 | 是 | 是 | 同 MySQL |
| PostgreSQL | 9.1+ `ADD VALUE` | 9.1+ `BEFORE/AFTER` | 10+ `RENAME VALUE` | 不支持 | 否（仅元数据） |
| CockroachDB | 是 | 是 | 是 | 是 | 否（在线 schema 变更） |
| ClickHouse | 是 (`MODIFY`) | 是 | 是 | 是（不安全） | 否（元数据级） |
| DuckDB | 是 (`ALTER TYPE ADD VALUE`) | 否 | 否 | 否 | 不需要 |
| H2 | 重建列 | -- | -- | -- | 是 |
| TiDB | 是 (兼容 MySQL) | 是 | 是 | 是 | 末尾可在线 |
| OceanBase | 是 (MySQL 模式) | 是 | -- | -- | 末尾可在线 |
| 其他（CHECK 约束方案） | DROP + ADD CONSTRAINT | -- | -- | -- | 视约束验证而定 |

PostgreSQL 的 ENUM ALTER 设计是该领域**最优雅的现代实现**：取值仅是 `pg_enum` 系统表中的一行元数据，新增取值无需扫描数据，且支持指定逻辑顺序。

### 矩阵四：存储大小与编码

| 引擎 | 1-byte 上限 | 2-byte 上限 | 4-byte 上限 | 编码方式 |
|------|------------|------------|------------|---------|
| MySQL ENUM | 255 个 | 65535 个 | -- | 顺序索引 (1, 2, 3, ...)，0 = 错误值 |
| MySQL SET | 8 个成员 | 16 个成员 | 32/64 个成员 | 位掩码 |
| PostgreSQL ENUM | -- | -- | 4 字节 OID | 系统级 OID，无序号 |
| ClickHouse Enum8 | 256 个 | -- | -- | 有符号 INT8（-128 到 127） |
| ClickHouse Enum16 | -- | 65536 个 | -- | 有符号 INT16（-32768 到 32767） |
| CockroachDB ENUM | -- | -- | 变长 | 列表偏移 + 校验 |
| DuckDB ENUM | 256 | 65536 | 4 字节 | 字典编码（dict） |
| H2 ENUM | -- | -- | -- | 内部 INT 索引 |

> ClickHouse 的 Enum8/Enum16 提供了最直接的存储控制——你可以显式指定每个字符串到整数的映射（甚至包括负数）。这对带 wire 协议或 ETL 反向兼容场景非常有价值。

### 矩阵五：与索引、外键、CHECK 的交互

| 引擎 | 可建索引 | 外键支持 | 与 CHECK 组合 | NULL 行为 |
|------|---------|---------|---------------|---------|
| MySQL ENUM | 是（B+ 树） | 是 | 是 | NULL 与 ''（空字符串）不同 |
| MySQL SET | 是（但选择性低） | 是 | 是 | NULL 与 '' 不同 |
| PostgreSQL ENUM | 是（B-tree, hash） | 是 | 是 | 标准 NULL 语义 |
| ClickHouse Enum | 是（主键/二级） | 不支持 | 是 | -- |
| CockroachDB ENUM | 是（B+ 树） | 是 | 是 | 标准 NULL 语义 |
| DuckDB ENUM | 自动（字典） | 是 | 是 | 标准 NULL 语义 |

## 各引擎实现详解

### MySQL：ENUM 的鼻祖（4.0+, 2003）

```sql
-- 基本声明
CREATE TABLE products (
    id INT PRIMARY KEY,
    size ENUM('small', 'medium', 'large', 'xl', 'xxl') NOT NULL,
    color ENUM('red', 'blue', 'green') DEFAULT 'red'
);

-- 插入：可以用字符串
INSERT INTO products VALUES (1, 'medium', 'blue');

-- 也可以用整数（按声明顺序，从 1 开始）
INSERT INTO products VALUES (2, 3, 2);   -- 等同 ('large', 'blue')

-- 查询：返回字符串
SELECT size FROM products WHERE id = 1;  -- 'medium'

-- 但可以强制转换为整数（实现细节暴露！）
SELECT size + 0 FROM products WHERE id = 1;  -- 2

-- 排序：按声明顺序，不是字典序！
SELECT * FROM products ORDER BY size;
-- 结果顺序：small, medium, large, xl, xxl（声明顺序），不是 'large', 'medium', 'small'

-- 插入未知值
INSERT INTO products VALUES (99, 'huge', 'red');
-- strict mode：报错
-- non-strict mode：插入空字符串 '' 并发出警告，整数索引为 0
```

#### MySQL ENUM 的存储证据

```sql
-- 验证存储大小
CREATE TABLE t1 (
    s1 ENUM('a','b','c'),                    -- 1 字节
    s2 ENUM('a','b','c','d','e','f','g')     -- 1 字节（仍 < 255）
);

-- 大型 ENUM（演示 2 字节边界）
CREATE TABLE t2 (
    big_enum ENUM('v1','v2', /* ... */ 'v300')   -- 2 字节
);

-- 通过 INFORMATION_SCHEMA 查看
SELECT COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, NUMERIC_PRECISION
FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 't1';
```

#### MySQL ENUM 的 ALTER 行为

```sql
-- 末尾追加新值（in-place，元数据变更，快）
ALTER TABLE products MODIFY size
    ENUM('small', 'medium', 'large', 'xl', 'xxl', 'xxxl');

-- 在中间插入新值（需要重写表！慢且锁表）
ALTER TABLE products MODIFY size
    ENUM('xs', 'small', 'medium', 'large', 'xl', 'xxl', 'xxxl');
-- 因为 'small' 的索引从 1 变成 2，所有现有行的 1 字节存储值都需要 +1

-- 删除一个值
ALTER TABLE products MODIFY size
    ENUM('medium', 'large', 'xl', 'xxl');
-- 原来 size = 'small' 的行变成 0（无效值）

-- 在线 DDL：8.0+ 部分场景支持 ALGORITHM=INSTANT
ALTER TABLE products MODIFY size
    ENUM('small', 'medium', 'large', 'xl', 'xxl', 'xxxl'),
    ALGORITHM=INSTANT;  -- 仅末尾追加可成功
```

### MySQL SET：64 成员位集合（4.0+）

```sql
-- 基本声明
CREATE TABLE permissions (
    user_id INT PRIMARY KEY,
    perms SET('read', 'write', 'execute', 'delete', 'admin')
);

-- 插入：逗号分隔的字符串
INSERT INTO permissions VALUES (1, 'read,write');
INSERT INTO permissions VALUES (2, 'read,write,execute,admin');

-- 也可以用整数位掩码
INSERT INTO permissions VALUES (3, 5);   -- 0b00101 = 'read,execute'

-- 查询：默认返回字符串
SELECT perms FROM permissions WHERE user_id = 1;  -- 'read,write'

-- 检查特定权限
SELECT * FROM permissions WHERE FIND_IN_SET('admin', perms) > 0;
SELECT * FROM permissions WHERE perms & 16;  -- 'admin' 是第 5 位 = 16

-- 多权限：检查同时有 read 和 write
SELECT * FROM permissions
WHERE perms & 1 AND perms & 2;

-- 排序：按位掩码整数值排序，不直观
SELECT * FROM permissions ORDER BY perms;
-- 注意：'admin' (16) > 'read,write,execute,delete' (15)
```

#### MySQL SET 的位编码

```
SET 成员到位的映射（按声明顺序）：
  第 1 个成员 → 2^0 = 1
  第 2 个成员 → 2^1 = 2
  第 3 个成员 → 2^2 = 4
  第 4 个成员 → 2^3 = 8
  ...
  第 N 个成员 → 2^(N-1)

存储字节数：
  1-8 个成员   → 1 字节 (TINYINT UNSIGNED)
  9-16 个成员  → 2 字节 (SMALLINT UNSIGNED)
  17-24 个成员 → 3 字节 (MEDIUMINT UNSIGNED)
  25-32 个成员 → 4 字节 (INT UNSIGNED)
  33-64 个成员 → 8 字节 (BIGINT UNSIGNED)

最大成员数：64（被 BIGINT 容量物理限制）
```

#### SET 重复值与去重

```sql
-- 重复元素自动去重
CREATE TABLE tags (
    item_id INT,
    labels SET('hot', 'new', 'sale', 'limited')
);

INSERT INTO tags VALUES (1, 'hot,hot,sale,hot');
SELECT labels FROM tags WHERE item_id = 1;
-- 'hot,sale'（去重后）

-- 顺序按声明顺序，不是输入顺序
INSERT INTO tags VALUES (2, 'sale,hot');
SELECT labels FROM tags WHERE item_id = 2;
-- 'hot,sale'（按声明顺序输出）
```

### PostgreSQL：CREATE TYPE AS ENUM（8.3+, 2008）

```sql
-- 创建 ENUM 类型（独立于表）
CREATE TYPE order_status AS ENUM (
    'pending', 'paid', 'shipped', 'delivered', 'cancelled'
);

-- 在多张表中复用
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    status order_status DEFAULT 'pending'
);

CREATE TABLE order_history (
    id SERIAL PRIMARY KEY,
    order_id INT,
    old_status order_status,
    new_status order_status,
    changed_at TIMESTAMPTZ DEFAULT NOW()
);

-- 插入与查询
INSERT INTO orders (status) VALUES ('paid'), ('shipped');
SELECT * FROM orders WHERE status = 'paid';

-- ENUM 之间比较：按定义顺序
SELECT * FROM orders WHERE status > 'pending';  -- paid, shipped, delivered, cancelled
SELECT * FROM orders ORDER BY status;            -- 按声明顺序

-- 但不能与字符串直接 cast 比较（需要显式转换）
SELECT * FROM orders WHERE status::text = 'paid';
SELECT * FROM orders WHERE status = 'paid'::order_status;
```

#### PostgreSQL ENUM 的元数据存储

```sql
-- pg_type 中存储 ENUM 类型本身
SELECT typname, typtype FROM pg_type WHERE typname = 'order_status';
-- typtype = 'e' 表示 enum

-- pg_enum 中存储所有取值
SELECT enumlabel, enumsortorder
FROM pg_enum
WHERE enumtypid = 'order_status'::regtype
ORDER BY enumsortorder;

--  enumlabel  | enumsortorder
-- ------------+---------------
--  pending    |             1
--  paid       |             2
--  shipped    |             3
--  delivered  |             4
--  cancelled  |             5

-- 物理存储：每行只存 4 字节 OID（指向 pg_enum 中的一行）
-- 比起 MySQL 的 1-2 字节略大，但读取时无需解码
```

#### PostgreSQL ALTER TYPE（9.1+）

```sql
-- 9.1+: 末尾追加
ALTER TYPE order_status ADD VALUE 'refunded';

-- 9.1+: 在指定位置之前插入
ALTER TYPE order_status ADD VALUE 'reviewing' BEFORE 'paid';

-- 9.1+: 在指定位置之后插入
ALTER TYPE order_status ADD VALUE 'returning' AFTER 'shipped';

-- 9.1-11.x: 不能在事务块内执行 ADD VALUE（除非新值已存在）
BEGIN;
ALTER TYPE order_status ADD VALUE 'new_value';  -- 错误！
ROLLBACK;

-- 12.0+: 可以在事务中执行
BEGIN;
ALTER TYPE order_status ADD VALUE 'new_value';  -- OK
COMMIT;

-- 10+: 重命名取值
ALTER TYPE order_status RENAME VALUE 'paid' TO 'payment_received';

-- 至今不支持的操作：
-- ALTER TYPE order_status DROP VALUE 'cancelled';   -- 错误：不支持
-- ALTER TYPE order_status REORDER ...;               -- 不支持

-- 删除值的 workaround：重建类型（数据迁移）
ALTER TYPE order_status RENAME TO order_status_old;
CREATE TYPE order_status AS ENUM ('pending', 'paid', 'shipped');
ALTER TABLE orders ALTER COLUMN status TYPE order_status
    USING status::text::order_status;
DROP TYPE order_status_old;
```

#### PostgreSQL ENUM 排序与比较

```sql
-- ENUM 的比较运算遵循声明顺序（不是字典序）
CREATE TYPE priority AS ENUM ('low', 'medium', 'high', 'critical');

CREATE TABLE tasks (id SERIAL, p priority);
INSERT INTO tasks (p) VALUES ('high'), ('low'), ('critical'), ('medium');

SELECT * FROM tasks ORDER BY p;
-- low, medium, high, critical（声明顺序，不是字典序）

SELECT * FROM tasks WHERE p > 'medium';
-- 返回 'high' 和 'critical'

-- 注意：字典序 'critical' < 'high' < 'low' < 'medium'
-- 这与 ENUM 顺序不同
```

### CockroachDB：ENUM（20.2+, 2020-11）

```sql
-- 语法与 PostgreSQL 兼容
CREATE TYPE status AS ENUM ('pending', 'active', 'inactive');

CREATE TABLE accounts (
    id UUID PRIMARY KEY,
    state status
);

-- ALTER 操作（在线 schema 变更）
ALTER TYPE status ADD VALUE 'archived';
ALTER TYPE status ADD VALUE 'reviewing' BEFORE 'active';
ALTER TYPE status RENAME VALUE 'inactive' TO 'disabled';
ALTER TYPE status DROP VALUE 'archived';   -- CRDB 比 PG 多支持 DROP！

-- 在分布式环境下，CRDB 通过元数据广播而非数据迁移完成 ENUM 变更
-- 这是少数支持 DROP VALUE 的实现之一
```

CRDB 的 ENUM 实现细节：
- 内部以变长字节序列存储（不是固定 4 字节 OID）
- 跨节点元数据通过 schema lease 机制同步
- ALTER TYPE 是在线操作，不阻塞 DML

### ClickHouse：Enum8 / Enum16（2016+）

```sql
-- Enum8: 256 个取值上限
CREATE TABLE events (
    event_time DateTime,
    event_type Enum8(
        'click' = 1,
        'view' = 2,
        'purchase' = 3,
        'refund' = -1   -- 可以是负数！
    ),
    user_id UInt64
) ENGINE = MergeTree() ORDER BY event_time;

-- Enum16: 65536 个取值上限
CREATE TABLE detailed_events (
    event_code Enum16(
        'success' = 200,
        'redirect' = 301,
        'not_found' = 404,
        'server_error' = 500
        /* 大量自定义状态码 */
    )
) ENGINE = MergeTree() ORDER BY tuple();

-- 插入：可以用字符串或整数
INSERT INTO events VALUES
    ('2024-01-01 10:00:00', 'click', 1001),
    ('2024-01-01 10:00:01', 2, 1002);  -- 2 = 'view'

-- 查询：返回字符串
SELECT event_type FROM events;

-- 转换为整数
SELECT CAST(event_type, 'Int8') FROM events;
SELECT toInt8(event_type) FROM events;

-- 集合操作：可以用字符串或整数
SELECT * FROM events WHERE event_type IN ('click', 'view');
SELECT * FROM events WHERE event_type IN (1, 2);
```

#### ClickHouse Enum 的存储优化

```sql
-- ClickHouse 列存使得 Enum 压缩比极佳
CREATE TABLE access_logs (
    timestamp DateTime,
    method Enum8('GET' = 1, 'POST' = 2, 'PUT' = 3, 'DELETE' = 4, 'PATCH' = 5),
    status_code Enum16('200' = 200, '301' = 301, '404' = 404, '500' = 500),
    bytes_sent UInt64
) ENGINE = MergeTree()
ORDER BY timestamp;

-- 压缩效果对比（10 亿行）：
-- VARCHAR  method:      ~30 GB（带字典编码）
-- Enum8    method:      ~120 MB（10^9 字节，常常压到 ~20 MB after LZ4）
-- 压缩率提升约 1000-1500 倍
```

#### ClickHouse Enum 的 ALTER

```sql
-- 修改 Enum：必须保持现有取值不变（仅添加）
ALTER TABLE events MODIFY COLUMN event_type
    Enum8('click' = 1, 'view' = 2, 'purchase' = 3, 'refund' = -1, 'cancel' = 4);
-- OK：添加 'cancel' = 4

-- 危险操作：修改现有取值的整数值（可能导致数据损坏！）
ALTER TABLE events MODIFY COLUMN event_type
    Enum8('click' = 5, 'view' = 2, 'purchase' = 3);  -- 错误！

-- 安全的处理方式：先迁移到 String，再迁回新 Enum
ALTER TABLE events MODIFY COLUMN event_type String;
ALTER TABLE events MODIFY COLUMN event_type
    Enum8('click' = 1, 'view' = 2, 'purchase' = 3, 'cancel' = 4);
```

### DuckDB：ENUM（0.4+, 2022）

```sql
-- 创建 ENUM 类型
CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy', 'ecstatic');

CREATE TABLE diary (
    day DATE,
    mood mood
);

INSERT INTO diary VALUES
    ('2024-01-01', 'happy'),
    ('2024-01-02', 'ok'),
    ('2024-01-03', 'ecstatic');

-- 查询
SELECT * FROM diary ORDER BY mood;
-- sad, ok, happy, ecstatic（按声明顺序）

-- ALTER：仅支持追加
ALTER TYPE mood ADD VALUE 'manic';

-- 自动推断 ENUM
CREATE TYPE auto_status AS ENUM (SELECT DISTINCT status FROM raw_data);
-- 从查询结果生成 ENUM 类型！
```

DuckDB 的 ENUM 在内部使用字典编码：
- 列上的每个取值是一个小整数
- 字典本身存在列元数据中
- 分组、连接、过滤都对整数操作，性能优于字符串

### SQL Server：用 CHECK 约束模拟

```sql
-- 没有原生 ENUM，使用 CHECK 约束
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    Status VARCHAR(20) NOT NULL
        CONSTRAINT CK_OrderStatus CHECK (
            Status IN ('Pending', 'Paid', 'Shipped', 'Delivered', 'Cancelled')
        )
);

-- 添加新值：DROP CONSTRAINT + ADD CONSTRAINT
ALTER TABLE Orders DROP CONSTRAINT CK_OrderStatus;
ALTER TABLE Orders ADD CONSTRAINT CK_OrderStatus CHECK (
    Status IN ('Pending', 'Paid', 'Shipped', 'Delivered', 'Cancelled', 'Refunded')
);

-- 用查找表方案（更工程化）
CREATE TABLE OrderStatusLookup (
    StatusID TINYINT PRIMARY KEY,
    StatusName VARCHAR(20) NOT NULL UNIQUE
);

INSERT INTO OrderStatusLookup VALUES
    (1, 'Pending'), (2, 'Paid'), (3, 'Shipped'), (4, 'Delivered'), (5, 'Cancelled');

CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    StatusID TINYINT NOT NULL FOREIGN KEY REFERENCES OrderStatusLookup(StatusID)
);

-- 查询时 JOIN
SELECT o.OrderID, s.StatusName
FROM Orders o JOIN OrderStatusLookup s ON o.StatusID = s.StatusID;
```

### Oracle：CHECK 约束或自定义类型

```sql
-- 方案 1：CHECK 约束
CREATE TABLE orders (
    id NUMBER PRIMARY KEY,
    status VARCHAR2(20) NOT NULL
        CONSTRAINT chk_status CHECK (
            status IN ('PENDING', 'PAID', 'SHIPPED', 'DELIVERED', 'CANCELLED')
        )
);

-- 方案 2：用对象类型 + 校验函数
CREATE OR REPLACE TYPE order_status_t AS OBJECT (
    val VARCHAR2(20),
    MEMBER FUNCTION is_valid RETURN BOOLEAN
);

-- 方案 3：用 VARRAY（多值场景，类似 SET）
CREATE TYPE permission_array AS VARRAY(10) OF VARCHAR2(20);

CREATE TABLE users (
    id NUMBER PRIMARY KEY,
    perms permission_array
);

INSERT INTO users VALUES (1, permission_array('read', 'write', 'admin'));
```

### SAP HANA：CHECK 约束

```sql
-- 没有原生 ENUM
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    status NVARCHAR(20) NOT NULL,
    CONSTRAINT chk_status CHECK (
        status IN ('pending', 'paid', 'shipped', 'delivered', 'cancelled')
    )
);

-- 推荐用 CDS 视图层定义枚举语义
-- 在 ABAP 上层用 Domain 控制取值
```

### SQLite：TEXT + CHECK 是事实标准

```sql
-- SQLite 没有 ENUM，但 CHECK 约束很好用
CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    status TEXT NOT NULL CHECK (
        status IN ('pending', 'paid', 'shipped', 'delivered', 'cancelled')
    )
);

-- 由于 SQLite 的弱类型，约束可能被绕过
INSERT INTO orders VALUES (1, 'pending');  -- OK

-- 严格模式 (3.37+) 才能保证类型
CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    status TEXT NOT NULL CHECK (status IN ('pending', 'paid', 'shipped'))
) STRICT;
```

### Snowflake：VARCHAR + 约束

```sql
-- Snowflake 没有 ENUM
CREATE TABLE orders (
    id NUMBER AUTOINCREMENT,
    status VARCHAR(20) NOT NULL
);

-- Snowflake 的 CHECK 约束默认不强制（仅元数据）
ALTER TABLE orders ADD CONSTRAINT chk_status
    CHECK (status IN ('pending', 'paid', 'shipped'));

-- 强制约束需要在应用层或 dbt test 验证
```

注意：Snowflake 的 CHECK 约束**默认是非强制的**——它们只用于 query optimizer 的提示。这意味着 `CHECK (status IN (...))` 不会阻止违法数据入库。这是分析型仓库与 OLTP 数据库在约束语义上的根本差异。

### BigQuery：STRING + 弱约束

```sql
-- BigQuery 没有 ENUM
CREATE TABLE `dataset.orders` (
    id INT64,
    status STRING NOT NULL
);

-- BigQuery 没有 CHECK 约束！
-- 只能在应用层或 dbt 验证

-- 数组也可以用来模拟 SET
CREATE TABLE `dataset.users` (
    id INT64,
    perms ARRAY<STRING>
);
```

### Redshift：VARCHAR + CHECK（弱）

```sql
CREATE TABLE orders (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    status VARCHAR(20) NOT NULL,
    CONSTRAINT chk_status CHECK (
        status IN ('pending', 'paid', 'shipped')
    )
);

-- Redshift 的 CHECK / FK / UNIQUE 都是 informational
-- 不会在 INSERT/UPDATE 时验证
-- 但 query optimizer 可能利用这些信息
```

### H2：MySQL 兼容 ENUM

```sql
-- H2 1.4.200+ 在 MySQL 兼容模式下支持 ENUM 语法
CREATE TABLE orders (
    id INT PRIMARY KEY,
    status ENUM('pending', 'paid', 'shipped', 'delivered', 'cancelled')
);

-- 内部存储：4 字节 INT 索引
-- 不像 MySQL 的 1-2 字节优化
```

### Materialize：继承 PostgreSQL 完整 ENUM

```sql
-- Materialize 实时视图引擎完整继承 PG ENUM
CREATE TYPE log_level AS ENUM ('debug', 'info', 'warn', 'error', 'fatal');

CREATE MATERIALIZED VIEW error_summary AS
SELECT level, COUNT(*) FROM logs WHERE level >= 'warn' GROUP BY level;
```

### QuestDB：SYMBOL（ENUM 变种）

```sql
-- QuestDB 的 SYMBOL 是 ENUM 的变种：自动构建字典
CREATE TABLE trades (
    ts TIMESTAMP,
    symbol SYMBOL CAPACITY 1024 CACHE,
    price DOUBLE,
    volume LONG
) timestamp(ts) PARTITION BY DAY;

-- SYMBOL 在写入时自动添加新值（不需要预声明）
-- 内部用 4 字节 INT 索引 + 字典文件
INSERT INTO trades VALUES (NOW(), 'AAPL', 150.25, 100);
INSERT INTO trades VALUES (NOW(), 'GOOG', 2800.50, 50);  -- 新 symbol 自动加入字典
```

QuestDB 的 SYMBOL 是 ENUM 与 INTERN 字符串的混合：
- 不需要 `CREATE TYPE`，写入时即扩展
- 适合金融时序数据（股票代码、交易所等）
- 容量与缓存策略可调

## MySQL ENUM 的常见陷阱

### 陷阱 1：整数索引泄漏

```sql
-- ENUM 的整数性质会在某些上下文中泄漏
CREATE TABLE t (e ENUM('a', 'b', 'c'));
INSERT INTO t VALUES ('a'), ('b'), ('c');

SELECT e FROM t;            -- 'a', 'b', 'c'
SELECT e + 0 FROM t;        -- 1, 2, 3（暴露索引）

-- 隐式转换可能导致意外
SELECT * FROM t WHERE e = 1;  -- 返回 e = 'a' 的行
SELECT * FROM t WHERE e = '1';  -- 不同行为：尝试匹配字符串 '1'

-- 整数值 0 的特殊语义
-- ENUM 中没有的字符串在非严格模式下变成 ''（索引 0）
INSERT INTO t VALUES ('xxx');
SELECT e, e + 0 FROM t WHERE e = '';
-- 结果：'', 0
```

### 陷阱 2：NULL vs 空字符串

```sql
-- ENUM 中的 NULL 与 ''（空字符串）是不同的
CREATE TABLE t (e ENUM('a', 'b', 'c') NULL);

INSERT INTO t VALUES (NULL);                  -- 真正的 NULL
INSERT INTO t VALUES (0);                     -- 不存在的索引 → ''
-- INSERT INTO t VALUES ('xxx');              -- 严格模式报错；非严格模式 → ''

SELECT * FROM t WHERE e IS NULL;              -- 1 行
SELECT * FROM t WHERE e = '';                 -- 1 行
SELECT * FROM t WHERE e IS NULL OR e = '';    -- 2 行（含义不同）
```

### 陷阱 3：声明顺序影响排序

```sql
CREATE TABLE priority_test (
    p ENUM('LOW', 'MEDIUM', 'HIGH', 'URGENT')
);

INSERT INTO priority_test VALUES ('HIGH'), ('LOW'), ('URGENT'), ('MEDIUM');

SELECT * FROM priority_test ORDER BY p;
-- 'LOW', 'MEDIUM', 'HIGH', 'URGENT'（声明顺序）

-- 用 ORDER BY CAST(p AS CHAR) 才能按字典序
SELECT * FROM priority_test ORDER BY CAST(p AS CHAR);
-- 'HIGH', 'LOW', 'MEDIUM', 'URGENT'
```

### 陷阱 4：INSERT 数字与字符串的歧义

```sql
CREATE TABLE t (e ENUM('1', '2', '3'));   -- 取值是字符串 '1', '2', '3'

INSERT INTO t VALUES ('1');               -- 索引 1 = '1'
INSERT INTO t VALUES (1);                 -- 索引 1 = '1'（同上）
INSERT INTO t VALUES (3);                 -- 索引 3 = '3'
INSERT INTO t VALUES ('3');               -- 索引 3 = '3'

-- 现在如果 ENUM 中包含数字字符串：
CREATE TABLE t2 (e ENUM('apple', '2', 'banana'));
INSERT INTO t2 VALUES (2);                -- 索引 2 = '2'（按位置）
INSERT INTO t2 VALUES ('2');              -- 索引 2 = '2'（按值）
-- 看似一致，但底层逻辑完全不同
```

### 陷阱 5：ALTER TABLE MODIFY ENUM 的复制开销

```sql
-- 在大表上 ALTER TABLE MODIFY ENUM 在中间插入新值
-- 可能导致：
-- 1. 锁表（ALGORITHM=COPY）
-- 2. 长时间复制（GB 级数据需要小时）
-- 3. 中断业务

-- 工程实践：
-- 1. 始终在末尾追加新 ENUM 值（保持索引稳定）
-- 2. 提前规划 ENUM 取值，避免后期插入
-- 3. 复杂场景考虑迁移到 VARCHAR + CHECK 或查找表
```

### 陷阱 6：从 ENUM 转字符串的方向不对称

```sql
-- ENUM 转字符串：自动
SELECT CAST(status AS CHAR) FROM orders;

-- 字符串转 ENUM：需要显式
INSERT INTO orders (status) VALUES ('paid');                        -- OK
INSERT INTO orders (status) VALUES (CAST('paid' AS ENUM(...)));     -- 不行
-- ENUM 不能在 SQL 表达式中"创建"，必须先有列

-- 跨表赋值：列定义必须一致
INSERT INTO orders_archive (status) SELECT status FROM orders;       -- OK
-- 如果 orders_archive.status 的 ENUM 取值集合与 orders.status 不同，
-- 引擎按字符串值匹配（不是按整数索引）
```

## MySQL SET 的使用陷阱

### 重复成员被默默去重

```sql
CREATE TABLE t (s SET('a', 'b', 'c'));
INSERT INTO t VALUES ('a,b,a,b,a');
SELECT s FROM t;
-- 'a,b'（去重并按声明顺序）
```

### 顺序由声明决定，不是输入

```sql
INSERT INTO t VALUES ('c,a,b');
SELECT s FROM t;
-- 'a,b,c'（按 SET 声明的顺序，不是 'c,a,b'）
```

### 整数与字符串的等价

```sql
INSERT INTO t VALUES (5);          -- 0b101 = 'a,c'
INSERT INTO t VALUES ('a,c');      -- 同上

-- 不能存超过最大值的数
INSERT INTO t VALUES (8);          -- 0b1000，超过 SET('a','b','c') 的 0b111 = 7
-- 严格模式：报错
-- 非严格模式：截断到 7
```

### 检查多个值的"全部包含"

```sql
-- 包含 'a' 且包含 'b'
SELECT * FROM t WHERE s & 1 AND s & 2;       -- 位运算
SELECT * FROM t WHERE FIND_IN_SET('a', s) > 0 AND FIND_IN_SET('b', s) > 0;

-- 仅包含 'a' 和 'b'（不多不少）
SELECT * FROM t WHERE s = 'a,b';
-- 错误！'b,a' 实际存储是 'a,b' 但应用层可能写成 'b,a'
-- 安全做法：转整数比较
SELECT * FROM t WHERE s = 3;  -- 0b011 = 'a,b'
```

## PostgreSQL ENUM 的 BEFORE/AFTER 实战

### 渐进式状态机演化

```sql
-- 阶段 1：初始状态机
CREATE TYPE order_state AS ENUM ('created', 'paid', 'shipped');

CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    state order_state DEFAULT 'created'
);

-- 阶段 2：业务发展，需要在中间插入审核步骤
ALTER TYPE order_state ADD VALUE 'reviewing' AFTER 'created';
ALTER TYPE order_state ADD VALUE 'approved' AFTER 'reviewing';

-- 验证：新顺序
SELECT enumlabel, enumsortorder
FROM pg_enum WHERE enumtypid = 'order_state'::regtype
ORDER BY enumsortorder;

--  enumlabel | enumsortorder
-- -----------+---------------
--  created   |             1
--  reviewing |           1.5  -- 注意：实际是 1.5
--  approved  |          1.75
--  paid      |             2
--  shipped   |             3

-- PostgreSQL 内部用浮点数 enumsortorder 实现"插入到中间"
-- 但元数据膨胀后，建议偶尔重建类型
```

### REINDEX 与 enum 类型变更

```sql
-- ALTER TYPE ADD VALUE 不需要重建索引（仅是元数据）
-- ALTER TYPE RENAME VALUE 也不需要

-- 但如果你 ALTER COLUMN TYPE order_state（重新创建类型并迁移）
-- 那么所有相关索引都会重建（所以慎用）
```

### Enum 与 partition 的交互

```sql
-- ENUM 可以作为分区键
CREATE TABLE orders (
    id BIGSERIAL,
    state order_state,
    created_at TIMESTAMPTZ
) PARTITION BY LIST (state);

CREATE TABLE orders_active PARTITION OF orders FOR VALUES IN ('created', 'reviewing', 'approved');
CREATE TABLE orders_done PARTITION OF orders FOR VALUES IN ('paid', 'shipped');

-- 注意：ALTER TYPE ADD VALUE 后新值没有对应的分区！
ALTER TYPE order_state ADD VALUE 'cancelled';
INSERT INTO orders (state) VALUES ('cancelled');
-- 错误：no partition of relation "orders" found for row

-- 必须为新值创建分区
CREATE TABLE orders_cancelled PARTITION OF orders FOR VALUES IN ('cancelled');
```

## ClickHouse Enum 与压缩

### 列存场景的极致压缩

```sql
CREATE TABLE access_logs_string (
    ts DateTime,
    method String,
    status UInt16
) ENGINE = MergeTree() ORDER BY ts;

CREATE TABLE access_logs_enum (
    ts DateTime,
    method Enum8('GET' = 1, 'POST' = 2, 'PUT' = 3, 'DELETE' = 4),
    status UInt16
) ENGINE = MergeTree() ORDER BY ts;

-- 插入 1 亿行相同数据
INSERT INTO access_logs_string SELECT
    now() - rand() % 86400,
    arrayElement(['GET', 'POST', 'PUT', 'DELETE'], rand() % 4 + 1),
    arrayElement([200, 301, 404, 500], rand() % 4 + 1)
FROM numbers(100000000);

INSERT INTO access_logs_enum SELECT * FROM access_logs_string;

-- 查看磁盘占用
SELECT table, formatReadableSize(sum(bytes_on_disk)) AS size
FROM system.parts
WHERE table LIKE 'access_logs%' AND active
GROUP BY table;

--   table              | size
-- --------------------+--------
--  access_logs_string | 380 MB    -- 字符串 + LZ4
--  access_logs_enum   | 95 MB     -- INT8 + LZ4，~4x 压缩

-- 在更长字符串场景下差距更大（如完整 URL，可达 10x+）
```

### Enum 与字典编码（LowCardinality）的对比

```sql
-- LowCardinality 是 ClickHouse 的字典编码
-- 与 Enum 不同：动态扩展，不需要预声明

CREATE TABLE logs_lc (
    ts DateTime,
    user_agent LowCardinality(String)
) ENGINE = MergeTree() ORDER BY ts;

CREATE TABLE logs_enum (
    ts DateTime,
    method Enum8('GET' = 1, 'POST' = 2, 'PUT' = 3)
) ENGINE = MergeTree() ORDER BY ts;

-- 选择指南：
-- Enum:           取值固定且少（<256 / <65536），需要排序，schema 校验严格
-- LowCardinality: 取值未知或动态扩展，不需要预声明
-- String:         取值非常多或唯一（>10^5），列基数高
```

### 多值场景：Array(Enum)

```sql
-- ClickHouse 没有 SET，但可以用 Array(Enum) 模拟
CREATE TABLE user_perms (
    user_id UInt64,
    perms Array(Enum8('read' = 1, 'write' = 2, 'admin' = 3))
) ENGINE = MergeTree() ORDER BY user_id;

INSERT INTO user_perms VALUES (1, ['read', 'write']);
INSERT INTO user_perms VALUES (2, ['read', 'write', 'admin']);

-- 查询
SELECT * FROM user_perms WHERE has(perms, 'admin');
SELECT * FROM user_perms WHERE hasAll(perms, ['read', 'write']);
SELECT * FROM user_perms WHERE arrayExists(p -> p = 'admin', perms);
```

## 关键发现

1. **ENUM 是 SQL 标准从未定义的类型**：MySQL 4.0 (2003) 是最早实现，PostgreSQL 8.3 (2008) 用 `CREATE TYPE` 提供更优雅的方案。截至 2026 年，约 25 个引擎支持原生 ENUM，30+ 引擎只能用 `CHECK` 约束模拟。

2. **MySQL ENUM 的字节优化是其最大卖点**：1-2 字节存储 vs PG 的 4 字节 OID。但代价是 ALTER TABLE 在中间插入值需要重写整张表，这是大表运维的重要陷阱。

3. **PostgreSQL 的 ALTER TYPE ADD VALUE BEFORE/AFTER 是行业最佳实现**：仅修改 `pg_enum` 元数据，O(1) 时间，无需扫描数据。9.1 (2011) 引入 ADD VALUE，10 引入 RENAME VALUE，但至今不能 DROP VALUE。

4. **CockroachDB 是少数支持 ALTER TYPE DROP VALUE 的引擎**（20.2，2020 年 11 月）。其分布式 schema 变更使在线 ENUM 修改成为可能，超越了 PG 的能力边界。

5. **MySQL SET 是独有的位掩码类型**：1-8 字节存储 1-64 个布尔标志。其他引擎一律不实现，倾向于用 `bit varying`、`Array(Enum)` 或位运算模拟。SET 上限严格固定为 64，由 BIGINT 容量决定。

6. **ClickHouse Enum8/Enum16 提供最大编码控制**：可显式指定每个字符串到整数（含负数）的映射。在列存压缩中收益巨大，对 GET/POST 这类高频低基数列可达 10x+ 压缩率。

7. **DuckDB 0.4 (2022) 引入的 ENUM 自动化**：支持 `CREATE TYPE x AS ENUM (SELECT DISTINCT ... FROM ...)`，从查询结果生成枚举。这是分析场景的实用扩展。

8. **分析型仓库一律不支持 ENUM**：BigQuery、Snowflake、Redshift、Databricks、Spark SQL 都没有原生 ENUM。它们的 CHECK 约束多为 informational（不强制），需要在 dbt/应用层验证。

9. **ENUM 排序是按声明顺序，不是字典序**：MySQL、PostgreSQL、ClickHouse、DuckDB 一致采用此语义。这与字符串 `ORDER BY` 行为不同，是数据迁移/复制时容易踩坑的差异。

10. **MySQL ENUM 的 0 索引语义"NULL ≠ '' ≠ 错误值"**：插入未声明值在非严格模式下变成空字符串（索引 0），与真正的 NULL 不同。这是约束语义弱化的典型例子，建议始终启用 `STRICT_TRANS_TABLES`。

11. **QuestDB 的 SYMBOL 是 ENUM 的金融时序变种**：写入时自动扩展字典，4 字节 INT 索引。适合股票代码这类高频出现但取值不预知的场景。

12. **Materialize、CockroachDB、YugabyteDB 都继承 PG ENUM 完整语义**：包括 `BEFORE/AFTER` 插入。这反映了 PG 协议生态的强大兼容力。

## 引擎选型建议

| 场景 | 推荐 | 原因 |
|------|------|------|
| 严格状态机的 OLTP | PostgreSQL ENUM | ALTER TYPE 元数据级，BEFORE/AFTER 灵活 |
| MySQL 生态 + 节省字节 | MySQL ENUM | 1-2 字节存储，4.0+ 全兼容 |
| 多标签 / 位集合 | MySQL SET | 64 位上限内最紧凑 |
| 列存分析 + 高频低基数列 | ClickHouse Enum8 | 1 字节 + 10x 压缩 |
| 不预知的高频字典 | QuestDB SYMBOL / ClickHouse LowCardinality | 自动扩展 |
| 分布式 + ENUM 演化 | CockroachDB | 在线 ALTER + DROP VALUE 支持 |
| 跨数据库可移植 | VARCHAR + CHECK 约束 | SQL 标准兼容 |
| 严格 OLTP 状态机 + 类型复用 | PostgreSQL `CREATE DOMAIN` | SQL:2008 标准 |
| 模式自动推断 | DuckDB ENUM | `AS ENUM (SELECT DISTINCT ...)` |

## 参考资料

- MySQL 文档：[The ENUM Type](https://dev.mysql.com/doc/refman/8.0/en/enum.html)
- MySQL 文档：[The SET Type](https://dev.mysql.com/doc/refman/8.0/en/set.html)
- PostgreSQL 文档：[Enumerated Types](https://www.postgresql.org/docs/current/datatype-enum.html)
- PostgreSQL 文档：[ALTER TYPE](https://www.postgresql.org/docs/current/sql-altertype.html)
- CockroachDB 文档：[ENUM types](https://www.cockroachlabs.com/docs/stable/enum.html)
- ClickHouse 文档：[Enum8, Enum16](https://clickhouse.com/docs/en/sql-reference/data-types/enum)
- DuckDB 文档：[Enum Data Types](https://duckdb.org/docs/sql/data_types/enum)
- QuestDB 文档：[SYMBOL Type](https://questdb.io/docs/concept/symbol/)
- SQL:2008 标准: ISO/IEC 9075-2:2008, Section 4.16 (User-Defined Types) and 11.24 (CREATE DOMAIN)
- Materialize 文档：[CREATE TYPE](https://materialize.com/docs/sql/create-type/)
- Snowflake 文档：[Constraint Properties](https://docs.snowflake.com/en/sql-reference/constraints-overview)
- BigQuery 文档：[Data Types](https://cloud.google.com/bigquery/docs/reference/standard-sql/data-types)
