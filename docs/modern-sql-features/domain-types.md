# 域类型与用户定义类型 (Domain Types and User-Defined Types)

当业务中反复出现 `ssn VARCHAR(11)`、`email VARCHAR(255) CHECK (...)`、`price NUMERIC(12,2) CHECK (price >= 0)` 时，真正符合 SQL 精神的做法不是复制列定义，而是先 `CREATE DOMAIN ssn_t AS VARCHAR(11) CHECK (VALUE ~ '...')`，然后在所有表里直接写 `ssn ssn_t`。域类型是 SQL 对"业务语义类型"的抽象，它让类型系统为业务规则服务，而不是让每张表重新发明一次身份证号码。

## SQL 标准中的用户定义类型

### SQL:1992 引入 CREATE DOMAIN

SQL-92（ISO/IEC 9075:1992）首次标准化了 `CREATE DOMAIN`：

```sql
<domain definition> ::=
    CREATE DOMAIN <domain name> [ AS ] <data type>
        [ <default clause> ]
        [ <domain constraint>... ]
        [ <collate clause> ]

<domain constraint> ::=
    [ <constraint name definition> ]
    <check constraint definition>
    [ <constraint characteristics> ]
```

关键语义：

1. **域是带约束的基础类型**：本质是"基础类型 + CHECK + DEFAULT + 可空性"的命名封装
2. **结构透明**：域与其底层类型可以隐式互操作（不是严格的名义类型）
3. **集中定义业务规则**：改 `CHECK` 只改域定义一处，所有引用列自动生效
4. **独立于表**：多个表的列可引用同一个域

### SQL:1999 引入 CREATE TYPE

SQL:1999 (SQL3) 在第 4 部分引入了面向对象风格的 `CREATE TYPE`，区分两类：

```sql
-- Distinct type（名义子类型，强类型）
CREATE TYPE usd AS DECIMAL(12,2) FINAL;
CREATE TYPE eur AS DECIMAL(12,2) FINAL;
-- usd 和 eur 不能直接相加，必须显式 CAST

-- Structured type（结构化类型，类似类/对象）
CREATE TYPE address_t AS (
    street VARCHAR(100),
    city   VARCHAR(50),
    zip    VARCHAR(10)
) NOT FINAL;
```

- **Distinct type**：单字段、强类型、需要显式转换，适合货币、温度、身份证等语义类型
- **Structured type**：多字段、面向对象（支持继承、方法、引用），适合业务对象

### 域 vs Distinct Type vs Structured Type

| 维度 | DOMAIN (1992) | DISTINCT TYPE (1999) | STRUCTURED TYPE (1999) |
|------|---------------|---------------------|------------------------|
| 底层 | 基础类型 + 约束 | 基础类型（名义重命名） | 多字段复合 |
| 强度 | 结构化兼容（隐式互操作） | 名义类型（需 CAST） | 名义类型 |
| CHECK | 原生支持 | 不直接支持（SQL 标准） | 通过方法/触发器 |
| DEFAULT | 支持 | 支持 | 支持 |
| 用途 | 业务规则复用 | 类型安全 | 面向对象建模 |

## 支持矩阵

### CREATE DOMAIN 基础支持

| 引擎 | CREATE DOMAIN | CHECK | DEFAULT | NOT NULL | ALTER DOMAIN | 备注 |
|------|---------------|-------|---------|----------|--------------|------|
| PostgreSQL | 是 | 是 | 是 | 是 | 是 | 7.3+ (2002)，最完整 |
| Firebird | 是 | 是 | 是 | 是 | 是 | 1.0+，历史最悠久之一 |
| HSQLDB | 是 | 是 | 是 | 是 | 是 (部分) | 支持基本域 |
| DB2 | 否 (使用 DISTINCT TYPE) | -- | -- | -- | -- | 走 DISTINCT TYPE 路线 |
| Oracle | 否 (使用 OBJECT TYPE) | -- | -- | -- | -- | 走 OBJECT 路线 |
| SQL Server | 否 (使用 CREATE TYPE 别名) | 规则/约束 | 是 (默认对象) | 是 | 否 | 别名类型 |
| MySQL | 否 | CHECK 8.0.16+ | 列级 | 列级 | -- | 无 DOMAIN 概念 |
| MariaDB | 否 | CHECK 10.2.1+ | 列级 | 列级 | -- | 无 DOMAIN 概念 |
| SQLite | 否 | CHECK | 列级 | 列级 | -- | 无 DOMAIN 概念 |
| Snowflake | 否 | CHECK (不强制) | 列级 | 列级 | -- | 无 DOMAIN |
| BigQuery | 否 | -- | 列级 | 列级 | -- | 无 DOMAIN |
| Redshift | 否 | 不强制 | 列级 | 列级 | -- | 无 DOMAIN |
| DuckDB | 否 | CHECK | 列级 | 列级 | -- | 无 DOMAIN（计划中） |
| ClickHouse | 否 | -- | 列级 | Nullable 包装 | -- | 无 DOMAIN，有 Enum8/16 |
| Trino | 否 | -- | -- | -- | -- | 无 DDL DOMAIN |
| Presto | 否 | -- | -- | -- | -- | 无 DDL DOMAIN |
| Spark SQL | 否 | CHECK 3.4+ (Delta) | 列级 | 列级 | -- | 无 DOMAIN |
| Hive | 否 | CHECK | 列级 | 列级 | -- | 无 DOMAIN |
| Flink SQL | 否 | -- | -- | -- | -- | 无 DOMAIN |
| Databricks | 否 | CHECK (Delta) | 列级 | 列级 | -- | 无 DOMAIN |
| Teradata | 是 (DOMAIN-like via UDT) | -- | -- | -- | -- | 通过 DISTINCT UDT |
| Greenplum | 是 | 是 | 是 | 是 | 是 | 继承 PG |
| CockroachDB | 否 | CHECK | 列级 | 列级 | -- | 无 DOMAIN |
| TiDB | 否 | CHECK 已解析但不强制 | 列级 | 列级 | -- | 无 DOMAIN |
| OceanBase | 否 | CHECK (MySQL 模式) | 列级 | 列级 | -- | 无 DOMAIN |
| YugabyteDB | 是 | 是 | 是 | 是 | 是 | 继承 PG |
| SingleStore | 否 | -- | 列级 | 列级 | -- | 无 DOMAIN |
| Vertica | 否 | -- | 列级 | 列级 | -- | 无 DOMAIN |
| Impala | 否 | -- | 列级 | 列级 | -- | 无 DOMAIN |
| StarRocks | 否 | -- | 列级 | 列级 | -- | 无 DOMAIN |
| Doris | 否 | -- | 列级 | 列级 | -- | 无 DOMAIN |
| MonetDB | 否 | CHECK | 列级 | 列级 | -- | 仅 CHECK |
| CrateDB | 否 | CHECK 5.3+ | 列级 | 列级 | -- | 无 DOMAIN |
| TimescaleDB | 是 | 是 | 是 | 是 | 是 | 继承 PG |
| QuestDB | 否 | -- | 列级 | -- | -- | 无 DOMAIN |
| Exasol | 否 | -- | 列级 | 列级 | -- | 无 DOMAIN |
| SAP HANA | 否 (使用 DATA TYPE) | -- | 是 | 是 | -- | DATA TYPE 语法 |
| Informix | 是 | 是 | 是 | 是 | 是 | 早期支持 |
| H2 | 是 | 是 | 是 | 是 | 是 (部分) | 开源，PG 兼容 |
| Derby | 否 | CHECK | 列级 | 列级 | -- | 无 DOMAIN |
| Amazon Athena | 否 | -- | -- | -- | -- | 无 DOMAIN |
| Azure Synapse | 否 | -- | 列级 | 列级 | -- | 继承 SQL Server |
| Google Spanner | 否 | CHECK | 列级 | 列级 | -- | 无 DOMAIN |
| Materialize | 否 | -- | 列级 | 列级 | -- | 无 DOMAIN |
| RisingWave | 否 | -- | 列级 | 列级 | -- | 无 DOMAIN |
| InfluxDB (SQL) | 否 | -- | -- | -- | -- | 无 DOMAIN |
| DatabendDB | 否 | -- | 列级 | 列级 | -- | 无 DOMAIN |
| Yellowbrick | 是 | 是 | 是 | 是 | 是 (部分) | PG 兼容 |
| Firebolt | 否 | -- | 列级 | 列级 | -- | 无 DOMAIN |

> 统计：约 10 个引擎原生支持 SQL 标准 `CREATE DOMAIN` 语法，约 38 个引擎不支持或走其他路径（DISTINCT TYPE、OBJECT TYPE、ALIAS TYPE 或纯列级 CHECK）。

### CREATE TYPE AS（用户定义类型）支持矩阵

| 引擎 | Distinct/Alias Type | Structured/Composite | Enum | Range | 备注 |
|------|--------------------|-----------------------|------|-------|------|
| PostgreSQL | 是 (`CREATE TYPE ... AS`) | 是 (composite) | 是 (8.3+) | 是 (9.2+) + 多范围 (14+) | 全能王 |
| Oracle | 是 (`OBJECT`) | 是 (`OBJECT`, 带方法) | 否 | 否 | OO 风格 |
| SQL Server | 是 (`CREATE TYPE FROM`) | 是 (`AS TABLE` TVP) | 否 | 否 | 表值参数独特 |
| DB2 | 是 (`DISTINCT TYPE`) | 是 (`STRUCTURED TYPE`) | 否 | 否 | 严格名义类型 |
| Firebird | 否 (通过 DOMAIN) | 否 | 否 (通过 DOMAIN+CHECK) | 否 | 仅 DOMAIN |
| H2 | 否 (通过 DOMAIN) | 否 | 是 (ENUM) | 否 | 部分支持 ENUM |
| HSQLDB | 是 (`CREATE TYPE`) | 否 | 否 | 否 | 基础别名类型 |
| MySQL | 否 | JSON 近似 | `ENUM('a','b')` 列类型 | 否 | ENUM 是列类型而非独立类型 |
| MariaDB | 否 | JSON 近似 | `ENUM` 列类型 | 否 | 同 MySQL |
| SQLite | 否 | 否 | 否 | 否 | 动态类型，无 DDL |
| Snowflake | 否 | `OBJECT`/`VARIANT` | 否 | 否 | 半结构化 |
| BigQuery | 否 | `STRUCT` | 否 | 否 | STRUCT 是内建复合类型 |
| Redshift | 否 | `SUPER` | 否 | 否 | SUPER 是半结构化 |
| DuckDB | 是 (`CREATE TYPE ... AS`) | 是 (`STRUCT(...)`) | 是 (`ENUM`) | 否 | 轻量但完整 |
| ClickHouse | 否 | `Tuple`/`Nested` | `Enum8`/`Enum16` | 否 | 数据类型内建 |
| Trino | 否 | `ROW` 内建 | 否 | 否 | ROW 类型 |
| Presto | 否 | `ROW` 内建 | 否 | 否 | 同 Trino |
| Spark SQL | 否 | `STRUCT` | 否 | 否 | STRUCT 是内建 |
| Hive | 否 | `STRUCT` | 否 | 否 | STRUCT 内建 |
| Flink SQL | 否 | `ROW` | 否 | 否 | ROW 内建 |
| Databricks | 否 | `STRUCT` | 否 | 否 | 同 Spark |
| Teradata | 是 (`DISTINCT UDT`) | 是 (`STRUCTURED UDT`) | 否 | 周期类型 (PERIOD) | 支持结构化 UDT |
| Greenplum | 是 | 是 (composite) | 是 | 是 | 继承 PG |
| CockroachDB | 否 | 否 | 是 (`CREATE TYPE AS ENUM`) | 否 | 仅 ENUM |
| TiDB | 否 | 否 | `ENUM` 列类型 | 否 | MySQL 兼容 |
| OceanBase | 否 (Oracle 模式支持 OBJECT) | Oracle 模式支持 | MySQL 模式 `ENUM` | 否 | 多模式 |
| YugabyteDB | 是 | 是 | 是 | 是 | 继承 PG |
| SingleStore | 否 | 否 | `ENUM` 列类型 | 否 | MySQL 兼容 |
| Vertica | 否 | `ROW`/`ARRAY` | 否 | 否 | 复合内建 |
| Impala | 否 | `STRUCT` | 否 | 否 | STRUCT 内建 |
| StarRocks | 否 | `STRUCT` | 否 | 否 | 2.5+ |
| Doris | 否 | `STRUCT` | 否 | 否 | 2.0+ |
| MonetDB | 否 | 否 | 否 | 否 | -- |
| CrateDB | 否 | `OBJECT` | 否 | 否 | JSON-like OBJECT |
| TimescaleDB | 是 | 是 | 是 | 是 | 继承 PG |
| QuestDB | 否 | 否 | `SYMBOL` 列类型 | 否 | SYMBOL 用于离散字符串 |
| Exasol | 否 | 否 | 否 | 否 | -- |
| SAP HANA | 是 (`DATA TYPE`) | 是 (`TABLE TYPE`) | 否 | 否 | 表类型广泛用于 SQLScript |
| Informix | 是 (`OPAQUE`, `DISTINCT`) | 是 (`ROW`, `NAMED ROW`) | 否 | 否 | DataBlade 遗产 |
| Derby | 是 (`CREATE TYPE ... EXTERNAL NAME`) | 否 | 否 | 否 | 映射 Java 类 |
| Amazon Athena | 否 | `ROW`/`STRUCT` | 否 | 否 | Presto/Trino 内建 |
| Azure Synapse | 是 (alias) | `AS TABLE` | 否 | 否 | 继承 SQL Server |
| Google Spanner | 否 | `STRUCT` (查询) | 否 | 否 | 仅查询内 STRUCT |
| Materialize | 是 (部分) | `LIST`/`MAP`/`RECORD` | 否 | 否 | 继承 PG 语法 |
| RisingWave | 是 (部分) | `STRUCT` | 否 | 否 | PG 协议 |
| InfluxDB (SQL) | 否 | 否 | 否 | 否 | -- |
| DatabendDB | 否 | `TUPLE` | 否 | 否 | 内建 |
| Yellowbrick | 是 | 是 | 是 | 否 | PG 兼容 |
| Firebolt | 否 | 否 | 否 | 否 | -- |

### ENUM 枚举类型支持矩阵

| 引擎 | 语法 | 独立类型还是列类型 | 版本 |
|------|------|-------------------|------|
| PostgreSQL | `CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy')` | 独立类型 | 8.3+ (2008) |
| MySQL | `col ENUM('a', 'b', 'c')` | 列类型 | 早期 |
| MariaDB | `col ENUM('a', 'b', 'c')` | 列类型 | 早期 |
| ClickHouse | `col Enum8('a' = 1, 'b' = 2)` | 列类型 | 早期 |
| DuckDB | `CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy')` | 独立类型 | 0.3+ |
| CockroachDB | `CREATE TYPE mood AS ENUM (...)` | 独立类型 | 20.2+ |
| YugabyteDB | 同 PG | 独立类型 | 继承 PG |
| H2 | `col ENUM('a', 'b', 'c')` | 列类型 | 1.4.200+ |
| TiDB | `col ENUM('a', 'b', 'c')` | 列类型 | MySQL 兼容 |
| SingleStore | `col ENUM('a', 'b', 'c')` | 列类型 | MySQL 兼容 |
| Redshift | 否 | -- | -- |
| BigQuery | 否 | -- | -- |
| Snowflake | 否 | -- | -- |
| SQL Server | 否 (用 CHECK 约束模拟) | -- | -- |
| Oracle | 否 (用 CHECK 约束模拟) | -- | -- |
| DB2 | 否 | -- | -- |

### Range / Multirange 类型（PostgreSQL 独创）

| 引擎 | Range | Multirange | 版本 |
|------|-------|-----------|------|
| PostgreSQL | `int4range`, `tsrange`, `daterange` 等 | `int4multirange` 等 | 9.2+ (2012) / 14+ (2021) |
| Greenplum | 是 | 是 | 继承 PG |
| YugabyteDB | 是 | 是 | 继承 PG |
| TimescaleDB | 是 | 是 | 继承 PG + 时间范围增强 |
| CockroachDB | 否 (计划中) | 否 | -- |
| Teradata | `PERIOD` 类型 (数据类型，非 Range) | 否 | V13+ |
| SAP HANA | 否 | 否 | -- |
| 其他引擎 | 否 | 否 | -- |

Range 是 PostgreSQL 独有的一等类型，配合 GiST 索引可高效支持 `&&`（重叠）、`@>`（包含）、`-|-`（相邻）等运算，在区间排除、价格区间、时间段冲突检测等场景几乎无法替代。

## PostgreSQL：CREATE DOMAIN 的参考实现

PostgreSQL 的 DOMAIN 实现最完整也最接近标准。

### 基本用法

```sql
-- 定义美国社保号码（SSN）域
CREATE DOMAIN us_ssn AS VARCHAR(11)
    CHECK (VALUE ~ '^\d{3}-\d{2}-\d{4}$');

-- 定义正整数
CREATE DOMAIN pos_int AS INTEGER
    CHECK (VALUE > 0);

-- 定义电子邮件
CREATE DOMAIN email AS VARCHAR(254)
    CHECK (VALUE ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- 定义价格（非负货币）
CREATE DOMAIN price AS NUMERIC(12, 2)
    DEFAULT 0.00
    CHECK (VALUE >= 0);

-- 定义百分比
CREATE DOMAIN percentage AS NUMERIC(5, 2)
    CHECK (VALUE BETWEEN 0 AND 100);

-- 定义非空字符串
CREATE DOMAIN non_empty_text AS TEXT
    CHECK (length(trim(VALUE)) > 0)
    NOT NULL;
```

### 使用域定义表

```sql
CREATE TABLE persons (
    id          SERIAL PRIMARY KEY,
    ssn         us_ssn UNIQUE,
    email_addr  email NOT NULL,
    full_name   non_empty_text
);

CREATE TABLE products (
    id            SERIAL PRIMARY KEY,
    name          non_empty_text,
    unit_price    price,
    discount_rate percentage DEFAULT 0
);

-- 业务约束被类型系统自动执行：
INSERT INTO persons (ssn, email_addr, full_name)
    VALUES ('123-45-6789', 'alice@example.com', 'Alice');

-- 违反域约束会报错：
INSERT INTO persons (ssn, email_addr, full_name)
    VALUES ('invalid', 'bob@example.com', 'Bob');
-- ERROR: value for domain us_ssn violates check constraint "us_ssn_check"
```

### ALTER DOMAIN：演化业务规则

```sql
-- 添加新约束
ALTER DOMAIN percentage
    ADD CONSTRAINT percentage_not_null CHECK (VALUE IS NOT NULL);

-- 删除约束
ALTER DOMAIN percentage DROP CONSTRAINT percentage_not_null;

-- 修改默认值
ALTER DOMAIN price SET DEFAULT 0.01;
ALTER DOMAIN price DROP DEFAULT;

-- 修改可空性
ALTER DOMAIN email SET NOT NULL;
ALTER DOMAIN email DROP NOT NULL;

-- 重命名
ALTER DOMAIN us_ssn RENAME TO social_security_number;

-- 修改所属 schema
ALTER DOMAIN us_ssn SET SCHEMA hr;
```

**注意**：`ALTER DOMAIN ADD CONSTRAINT` 会验证所有使用该域的列中现有数据，若违反则失败。可以先用 `NOT VALID` 绕过：

```sql
ALTER DOMAIN percentage
    ADD CONSTRAINT pct_range CHECK (VALUE BETWEEN 0 AND 100) NOT VALID;

-- 后续分批验证
ALTER DOMAIN percentage VALIDATE CONSTRAINT pct_range;
```

### VALUE 关键字与函数式 CHECK

```sql
-- PostgreSQL 支持函数调用在 CHECK 中
CREATE DOMAIN iso_country_code AS CHAR(2)
    CHECK (VALUE IN (SELECT code FROM country_codes));
-- 警告：不能引用其他表！PG 限制 DOMAIN CHECK 必须是不可变表达式
-- 上面的写法会在插入时看似工作但其实违反 PG 的不变性假设

-- 正确做法：使用自定义 IMMUTABLE 函数
CREATE OR REPLACE FUNCTION is_valid_country(code CHAR(2))
RETURNS BOOLEAN
IMMUTABLE
LANGUAGE plpgsql AS $$
BEGIN
    RETURN code ~ '^[A-Z]{2}$';
END;
$$;

CREATE DOMAIN iso_country_code AS CHAR(2)
    CHECK (is_valid_country(VALUE));
```

### DROP DOMAIN 与级联

```sql
-- 不能删除被列引用的域
DROP DOMAIN email;
-- ERROR: cannot drop type email because other objects depend on it

-- 级联删除所有依赖
DROP DOMAIN email CASCADE;

-- 查看依赖
SELECT c.table_schema, c.table_name, c.column_name
FROM information_schema.columns c
WHERE c.domain_name = 'email';
```

## PostgreSQL ENUM：类型 vs 约束

PostgreSQL 同时提供 ENUM 类型和 CHECK 约束两种方式限制离散取值，两者有关键差异：

### CREATE TYPE AS ENUM

```sql
CREATE TYPE order_status AS ENUM ('pending', 'paid', 'shipped', 'delivered', 'cancelled');

CREATE TABLE orders (
    id     SERIAL PRIMARY KEY,
    status order_status NOT NULL DEFAULT 'pending'
);

INSERT INTO orders (status) VALUES ('paid');  -- 成功
INSERT INTO orders (status) VALUES ('foo');
-- ERROR: invalid input value for enum order_status: "foo"

-- ENUM 有内建排序（按声明顺序）
SELECT * FROM orders ORDER BY status;
-- pending < paid < shipped < delivered < cancelled

-- 演化：添加新值（9.1+）
ALTER TYPE order_status ADD VALUE 'refunded' AFTER 'cancelled';

-- 重命名值（10+）
ALTER TYPE order_status RENAME VALUE 'cancelled' TO 'voided';

-- 注意：不能在事务中 ALTER TYPE ADD VALUE，除非值已存在于该事务之外
```

### 使用 DOMAIN + CHECK 的等价实现

```sql
CREATE DOMAIN order_status_t AS VARCHAR(20)
    CHECK (VALUE IN ('pending', 'paid', 'shipped', 'delivered', 'cancelled'));

CREATE TABLE orders_v2 (
    id     SERIAL PRIMARY KEY,
    status order_status_t NOT NULL DEFAULT 'pending'
);
```

### ENUM vs DOMAIN + CHECK 对比

| 维度 | ENUM | DOMAIN + CHECK |
|------|------|----------------|
| 存储 | 4 字节 OID | VARCHAR（按长度） |
| 比较 | 按声明顺序 | 按字典序 |
| 添加新值 | `ALTER TYPE ADD VALUE`（瞬时） | `ALTER DOMAIN ... CHECK`（需验证全表） |
| 删除值 | 不支持（PostgreSQL 限制） | `ALTER DOMAIN ... DROP CONSTRAINT` |
| 跨数据库迁移 | PG 特有 | 标准 SQL 兼容 |
| 性能 | 整数比较，更快 | 字符串比较 |
| 序列化 | 作为文本 | 文本 |

**选型建议**：取值稳定、数量少、需要高性能时用 ENUM；取值可能频繁变动或需要跨引擎迁移时用 DOMAIN + CHECK。

## PostgreSQL 复合类型与 Range 类型

### Composite Type（结构化类型）

```sql
CREATE TYPE address AS (
    street VARCHAR(100),
    city   VARCHAR(50),
    state  CHAR(2),
    zip    VARCHAR(10)
);

CREATE TABLE customers (
    id          SERIAL PRIMARY KEY,
    name        TEXT,
    home_addr   address,
    work_addr   address
);

-- 构造与访问
INSERT INTO customers (name, home_addr)
    VALUES ('Alice', ROW('123 Main', 'Seattle', 'WA', '98101'));

SELECT (home_addr).city FROM customers;
SELECT home_addr.* FROM customers;
```

### Range Type

```sql
-- 内建范围类型
-- int4range, int8range, numrange, tsrange, tstzrange, daterange

CREATE TABLE reservations (
    id       SERIAL PRIMARY KEY,
    room_id  INTEGER,
    period   tstzrange NOT NULL,
    EXCLUDE USING gist (room_id WITH =, period WITH &&)
);

-- 插入区间
INSERT INTO reservations (room_id, period) VALUES
    (1, '[2026-04-23 09:00, 2026-04-23 10:00)'),
    (1, '[2026-04-23 10:00, 2026-04-23 11:00)');

-- 冲突会被 EXCLUDE 约束拒绝
INSERT INTO reservations (room_id, period)
    VALUES (1, '[2026-04-23 09:30, 2026-04-23 10:30)');
-- ERROR: conflicting key value violates exclusion constraint

-- 自定义范围类型
CREATE TYPE floatrange AS RANGE (
    subtype = FLOAT8,
    subtype_diff = float8mi
);

-- 范围运算
SELECT '[1, 10]'::int4range && '[5, 15]'::int4range;  -- 重叠？true
SELECT '[1, 10]'::int4range @> 5;                      -- 包含？true
SELECT '[1, 5]'::int4range -|- '[5, 10]'::int4range;   -- 相邻？false（5 同时在两者中）
```

### Multirange（14+）

```sql
-- 多段范围
SELECT int4multirange(int4range(1, 5), int4range(10, 15));

-- 联合、交集
SELECT '{[1,5), [10,15)}'::int4multirange + '{[3,12)}'::int4multirange;
-- {[1,15)}

CREATE TABLE maintenance_windows (
    server_id INTEGER PRIMARY KEY,
    windows   tstzmultirange
);
```

## Oracle：面向对象的 CREATE TYPE AS OBJECT

Oracle 选择了完全不同的路径——面向对象扩展。

### OBJECT 类型

```sql
-- 定义对象类型
CREATE OR REPLACE TYPE address_t AS OBJECT (
    street  VARCHAR2(100),
    city    VARCHAR2(50),
    state   CHAR(2),
    zip     VARCHAR2(10),
    MEMBER FUNCTION full_address RETURN VARCHAR2
);
/

-- 定义方法体
CREATE OR REPLACE TYPE BODY address_t AS
    MEMBER FUNCTION full_address RETURN VARCHAR2 IS
    BEGIN
        RETURN street || ', ' || city || ', ' || state || ' ' || zip;
    END;
END;
/

-- 使用
CREATE TABLE customers (
    id       NUMBER PRIMARY KEY,
    name     VARCHAR2(100),
    home     address_t
);

INSERT INTO customers VALUES (1, 'Alice',
    address_t('123 Main', 'Seattle', 'WA', '98101'));

SELECT c.home.full_address() FROM customers c;
```

### Object Table（行对象）

```sql
-- 对象作为整行
CREATE TABLE addresses OF address_t;

INSERT INTO addresses VALUES ('456 Oak', 'Portland', 'OR', '97201');

-- 每行有对象 ID（OID）
SELECT REF(a) FROM addresses a;
```

### DISTINCT TYPE via OBJECT

Oracle 没有独立的 DISTINCT TYPE 语法，但可用 OBJECT 模拟：

```sql
CREATE OR REPLACE TYPE usd_money AS OBJECT (amount NUMBER);
CREATE OR REPLACE TYPE eur_money AS OBJECT (amount NUMBER);

-- usd_money 和 eur_money 不能相加（类型不同）
```

### PL/SQL 记录类型（仅 PL/SQL 内部）

```sql
DECLARE
    TYPE employee_rec IS RECORD (
        id    NUMBER,
        name  VARCHAR2(100),
        sal   NUMBER(10, 2)
    );
    emp employee_rec;
BEGIN
    emp.id := 1;
    emp.name := 'Alice';
    emp.sal := 50000;
END;
```

## SQL Server：别名类型与表值参数

SQL Server 的 `CREATE TYPE` 更像是类型别名，加上独特的 "user-defined table type"。

### 别名类型

```sql
-- 定义别名类型
CREATE TYPE SSN FROM VARCHAR(11) NOT NULL;
CREATE TYPE Phone FROM VARCHAR(20) NULL;
CREATE TYPE Money2 FROM DECIMAL(18, 2) NOT NULL;

-- 使用
CREATE TABLE Persons (
    Id        INT PRIMARY KEY,
    SSN       SSN,
    HomePhone Phone,
    Salary    Money2
);

-- 注意：CREATE TYPE FROM 不支持 CHECK
-- 约束需通过绑定 RULE（已废弃）或表上的 CHECK 约束实现
```

### 规则与默认对象（已废弃但仍可用）

```sql
-- 旧语法（SQL Server 2000 时代）
CREATE RULE ssn_rule AS @ssn LIKE '[0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]';
sp_bindrule 'ssn_rule', 'SSN';

CREATE DEFAULT zero_default AS 0;
sp_bindefault 'zero_default', 'Money2';

-- 微软已标记这两个特性为 deprecated，推荐改用 CHECK 约束
```

### 表值参数（TVP）：CREATE TYPE AS TABLE

这是 SQL Server 独有的强大特性：

```sql
-- 定义表类型
CREATE TYPE OrderLineTable AS TABLE (
    ProductId  INT NOT NULL,
    Quantity   INT NOT NULL,
    UnitPrice  DECIMAL(12, 2) NOT NULL,
    PRIMARY KEY (ProductId)
);

-- 在存储过程中作为参数
CREATE PROCEDURE InsertOrderLines
    @OrderId INT,
    @Lines   OrderLineTable READONLY
AS
BEGIN
    INSERT INTO OrderLines (OrderId, ProductId, Quantity, UnitPrice)
    SELECT @OrderId, ProductId, Quantity, UnitPrice FROM @Lines;
END;

-- 客户端批量传入（ADO.NET / JDBC 均支持）
DECLARE @lines OrderLineTable;
INSERT INTO @lines VALUES (1, 10, 9.99), (2, 5, 19.99);
EXEC InsertOrderLines 1001, @lines;
```

TVP 是 SQL Server 替代 "many INSERT" 或 "IN (...)" 的推荐方式，单次调用可传入数千行，且走表扫描而非参数化路径。

## DB2：DISTINCT TYPE 的严格名义类型

DB2 的 `CREATE DISTINCT TYPE` 是 SQL:1999 标准的直接实现：

```sql
-- 定义 DISTINCT TYPE
CREATE DISTINCT TYPE us_dollar AS DECIMAL(12, 2) WITH COMPARISONS;
CREATE DISTINCT TYPE euro      AS DECIMAL(12, 2) WITH COMPARISONS;

-- WITH COMPARISONS 自动生成与源类型的比较函数
-- 但类型严格不兼容：
CREATE TABLE accounts (
    id        INTEGER,
    balance   us_dollar
);

-- 错误：DECIMAL 不能直接赋给 us_dollar
UPDATE accounts SET balance = 100.00 WHERE id = 1;
-- SQL0401N  The data types of the operands for the operation "=" are not compatible.

-- 正确：必须 CAST
UPDATE accounts SET balance = us_dollar(100.00) WHERE id = 1;

-- 不同 DISTINCT TYPE 之间也不兼容
SELECT us_dollar(10) + euro(5);  -- 错误
```

### STRUCTURED TYPE（OO 风格）

```sql
CREATE TYPE address AS (
    street VARCHAR(100),
    city   VARCHAR(50),
    zip    VARCHAR(10)
) MODE DB2SQL;

-- 类型层次
CREATE TYPE us_address UNDER address AS (
    state CHAR(2)
) MODE DB2SQL;

-- 方法
ALTER TYPE address
    ADD METHOD full_addr() RETURNS VARCHAR(200)
    LANGUAGE SQL DETERMINISTIC CONTAINS SQL;

CREATE METHOD full_addr() FOR address
    RETURN street || ', ' || city || ' ' || zip;
```

## Firebird：域类型的先驱

Firebird 自 1.0 起就有完整的 `CREATE DOMAIN`：

```sql
CREATE DOMAIN D_BOOLEAN AS SMALLINT
    DEFAULT 0
    NOT NULL
    CHECK (VALUE IN (0, 1));

CREATE DOMAIN D_EMAIL AS VARCHAR(254)
    CHECK (VALUE LIKE '%_@_%._%');

CREATE DOMAIN D_POSITIVE AS NUMERIC(18, 4)
    CHECK (VALUE > 0);

-- 使用
CREATE TABLE employees (
    id        INTEGER NOT NULL PRIMARY KEY,
    name      VARCHAR(100),
    email     D_EMAIL,
    salary    D_POSITIVE,
    is_active D_BOOLEAN
);

-- ALTER DOMAIN
ALTER DOMAIN D_POSITIVE DROP CONSTRAINT;
ALTER DOMAIN D_POSITIVE ADD CONSTRAINT CHECK (VALUE > 0.01);
ALTER DOMAIN D_POSITIVE SET DEFAULT 1.0000;
ALTER DOMAIN D_EMAIL TYPE VARCHAR(320);  -- 修改底层类型
```

Firebird 在存储过程和触发器中也能直接以域作为变量类型：

```sql
CREATE PROCEDURE validate_email(mail D_EMAIL)
RETURNS (is_valid D_BOOLEAN)
AS
BEGIN
    is_valid = IIF(mail LIKE '%@%', 1, 0);
END;
```

## H2 与 HSQLDB：嵌入式数据库的域支持

### H2

```sql
-- H2 支持 PostgreSQL 风格的 CREATE DOMAIN
CREATE DOMAIN email AS VARCHAR(254) CHECK (POSITION('@' IN VALUE) > 1);
CREATE DOMAIN positive_money AS DECIMAL(12, 2) DEFAULT 0 CHECK (VALUE >= 0);

CREATE TABLE users (
    id    INT PRIMARY KEY,
    mail  email,
    credit positive_money
);

-- H2 也支持 ENUM 类型
CREATE TYPE mood AS ENUM ('happy', 'sad', 'neutral');
CREATE TABLE posts (mood mood);

-- H2 兼容 PG 的 ALTER DOMAIN
ALTER DOMAIN positive_money SET DEFAULT 1.00;
```

### HSQLDB

```sql
-- HSQLDB 支持 SQL 标准 DOMAIN
CREATE DOMAIN pct_t AS DECIMAL(5, 2)
    DEFAULT 0
    CHECK (VALUE BETWEEN 0 AND 100);

CREATE TYPE money_alias AS DECIMAL(12, 2);  -- 别名类型
```

## MySQL / MariaDB：没有 DOMAIN，用 CHECK 替代

MySQL 不支持 `CREATE DOMAIN`，但从 8.0.16 起支持 CHECK 约束：

```sql
-- MySQL 8.0.16+
CREATE TABLE persons (
    id    INT AUTO_INCREMENT PRIMARY KEY,
    ssn   VARCHAR(11) CHECK (ssn REGEXP '^[0-9]{3}-[0-9]{2}-[0-9]{4}$'),
    email VARCHAR(254) CHECK (email LIKE '%@%.%'),
    age   INT CHECK (age BETWEEN 0 AND 150)
);

-- MySQL 8.0.16 之前：CHECK 被解析但忽略（需要 TRIGGER 模拟）
DELIMITER //
CREATE TRIGGER validate_email_before_insert
BEFORE INSERT ON persons
FOR EACH ROW
BEGIN
    IF NEW.email NOT LIKE '%@%.%' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid email format';
    END IF;
END//
DELIMITER ;
```

MariaDB 从 10.2.1 起就强制 CHECK，早于 MySQL。

### ENUM 列类型（MySQL/MariaDB）

```sql
CREATE TABLE orders (
    id     INT AUTO_INCREMENT PRIMARY KEY,
    status ENUM('pending', 'paid', 'shipped', 'cancelled') DEFAULT 'pending'
);

-- ENUM 在 MySQL 中是列类型，不是独立类型
-- 底层存储为 1 或 2 字节整数（TINYINT / SMALLINT）
-- 添加值需 ALTER TABLE，成本高

ALTER TABLE orders MODIFY status
    ENUM('pending', 'paid', 'shipped', 'cancelled', 'refunded');
```

## Snowflake：无 DOMAIN，使用 VARCHAR + CHECK 模式

Snowflake 没有 DOMAIN 概念，CHECK 约束虽可声明但不强制：

```sql
-- 声明 CHECK 但 Snowflake 不强制（INFORMATIONAL）
CREATE TABLE persons (
    ssn   VARCHAR(11) CHECK (ssn RLIKE '^[0-9]{3}-[0-9]{2}-[0-9]{4}$'),
    email VARCHAR(254) CHECK (email LIKE '%@%.%')
);

-- 推荐做法：在应用层验证 + 用 MASKING POLICY 做行级控制
CREATE MASKING POLICY ssn_mask AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('HR_ADMIN') THEN val
        ELSE 'XXX-XX-' || RIGHT(val, 4)
    END;

ALTER TABLE persons MODIFY COLUMN ssn SET MASKING POLICY ssn_mask;
```

Snowflake 的设计哲学是分析优先，数据完整性靠上游管道保证而非数据库约束。

## BigQuery / SQLite：极简类型系统

### BigQuery

```sql
-- BigQuery 无 DOMAIN / CREATE TYPE（除 STRUCT 内建）
-- CHECK 约束不支持，但支持 NOT NULL 和 REQUIRED 模式

CREATE TABLE dataset.persons (
    id    INT64 NOT NULL,
    ssn   STRING,  -- 格式靠 ETL 或 DBT 测试保证
    email STRING
);

-- 复合类型用 STRUCT
CREATE TABLE dataset.customers (
    id   INT64,
    addr STRUCT<
        street STRING,
        city   STRING,
        zip    STRING
    >
);
```

### SQLite

```sql
-- SQLite 有动态类型系统（type affinity），无 DOMAIN
CREATE TABLE persons (
    id    INTEGER PRIMARY KEY,
    ssn   TEXT CHECK (ssn GLOB '[0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]'),
    email TEXT CHECK (email LIKE '%@%.%')
);

-- SQLite 3.37+ 有 STRICT 表（强类型）
CREATE TABLE persons_v2 (
    id    INTEGER PRIMARY KEY,
    ssn   TEXT,
    email TEXT
) STRICT;
```

## DuckDB：轻量但完整的 CREATE TYPE

```sql
-- DuckDB 支持 CREATE TYPE AS ENUM
CREATE TYPE mood AS ENUM ('happy', 'sad', 'neutral');

-- DuckDB 支持 CREATE TYPE 作为别名
CREATE TYPE pos_int AS INTEGER;

-- STRUCT 内建
CREATE TABLE customers (
    id   INTEGER,
    addr STRUCT(street VARCHAR, city VARCHAR, zip VARCHAR)
);

-- DuckDB 不支持 CREATE DOMAIN（截至 1.1）
-- CHECK 放在列级：
CREATE TABLE prices (
    sku    VARCHAR,
    amount DECIMAL(12, 2) CHECK (amount >= 0)
);
```

## ClickHouse：Enum8/Enum16 + Nullable

```sql
-- ClickHouse 使用 Enum8 / Enum16 作为列类型
CREATE TABLE events (
    id        UInt64,
    event_type Enum8('click' = 1, 'view' = 2, 'purchase' = 3),
    status    Enum16('pending' = 1, 'done' = 2, 'failed' = 3)
) ENGINE = MergeTree()
ORDER BY id;

-- 可空性是"类型包装器"
CREATE TABLE persons (
    id    UInt64,
    name  Nullable(String),
    email Nullable(String)
) ENGINE = MergeTree()
ORDER BY id;

-- 无 DOMAIN / CHECK
-- 业务规则靠物化视图 + 约束检查
ALTER TABLE events ADD CONSTRAINT pos_id CHECK id > 0;
```

## CockroachDB / YugabyteDB：分布式 PostgreSQL

CockroachDB 仅支持 ENUM 而无完整 DOMAIN：

```sql
-- CockroachDB
CREATE TYPE status AS ENUM ('active', 'inactive', 'pending');
CREATE TABLE users (id UUID PRIMARY KEY, state status);

ALTER TYPE status ADD VALUE 'archived';
-- CRDB 不支持 CREATE DOMAIN
```

YugabyteDB（YSQL 兼容 PG）完整支持：

```sql
-- YugabyteDB - 继承 PG 的 DOMAIN / TYPE 全部功能
CREATE DOMAIN email AS VARCHAR(254) CHECK (VALUE LIKE '%@%.%');
CREATE TYPE mood AS ENUM ('happy', 'sad');
CREATE TYPE address AS (street TEXT, city TEXT, zip TEXT);
```

## SAP HANA：DATA TYPE 语法

```sql
-- SAP HANA 使用 CREATE TYPE 命名 DATA TYPE
CREATE TYPE money_t AS DECIMAL(12, 2);
CREATE TYPE phone_t AS VARCHAR(20);

-- 表类型（用于 SQLScript）
CREATE TYPE order_line_t AS TABLE (
    product_id INTEGER,
    quantity   INTEGER,
    price      DECIMAL(12, 2)
);

-- SQLScript 过程使用
CREATE PROCEDURE proc_orders(IN lines order_line_t) AS
BEGIN
    INSERT INTO order_lines SELECT * FROM :lines;
END;
```

## Teradata：DISTINCT UDT 与 STRUCTURED UDT

```sql
-- 距离类型（DISTINCT UDT）
CREATE TYPE us_dollar AS DECIMAL(12, 2) FINAL;
CREATE TYPE euro      AS DECIMAL(12, 2) FINAL;

-- 结构化类型
CREATE TYPE address_t AS (
    street VARCHAR(100),
    city   VARCHAR(50),
    zip    VARCHAR(10)
) NOT FINAL;

-- PERIOD 类型（范围的 Teradata 版本）
CREATE TABLE reservations (
    room_id  INT,
    period   PERIOD(TIMESTAMP)
);

INSERT INTO reservations VALUES
    (1, PERIOD(TIMESTAMP '2026-04-23 09:00:00', TIMESTAMP '2026-04-23 10:00:00'));
```

## Informix：DataBlade 类型体系

```sql
-- Informix 有丰富的 UDT 支持
CREATE OPAQUE TYPE email (internallength = 254);
CREATE DISTINCT TYPE us_phone AS VARCHAR(20);

CREATE ROW TYPE address_t (
    street VARCHAR(100),
    city   VARCHAR(50),
    zip    VARCHAR(10)
);

CREATE TABLE customers OF TYPE address_t;
```

## SQL:2003 结构化类型 vs OO 风格

SQL:1999/2003 的结构化类型与传统 OO 设计有重要差异：

### 标准 SQL:2003 语法

```sql
CREATE TYPE address_t AS (
    street VARCHAR(100),
    city   VARCHAR(50),
    zip    VARCHAR(10)
)
INSTANTIABLE
NOT FINAL
REF IS SYSTEM GENERATED;

-- 继承
CREATE TYPE us_address_t UNDER address_t AS (
    state CHAR(2)
);

-- 方法
CREATE TYPE employee_t AS (
    id   INTEGER,
    name VARCHAR(100),
    sal  DECIMAL(10, 2)
)
METHOD give_raise (pct DECIMAL(5, 2)) RETURNS DECIMAL(10, 2);

CREATE METHOD give_raise (pct DECIMAL(5, 2))
FOR employee_t
RETURNS DECIMAL(10, 2)
LANGUAGE SQL
DETERMINISTIC
CONTAINS SQL
BEGIN
    RETURN SELF.sal * (1 + pct / 100);
END;
```

### 各引擎实现差异

| 引擎 | 标准语法 | 继承 | 方法 | 引用（REF） |
|------|----------|------|------|-------------|
| Oracle | PL/SQL 扩展 | 是 | MEMBER FUNCTION | REF 类型 |
| DB2 | SQL 标准 | UNDER | CREATE METHOD | REF 类型 |
| PostgreSQL | 简化（仅 composite） | 表继承 | 通过函数 | 无 REF |
| Informix | ROW TYPE + UNDER | 是 | 通过 UDR | 无 |
| Teradata | 标准 | 否 | STATIC | 无 |
| SQL Server | 无结构化 TYPE（除 TVP） | -- | -- | -- |

## 域类型的典型应用场景

### 1. 业务标识符（如 SSN、税号、客户号）

```sql
CREATE DOMAIN tax_id AS VARCHAR(20)
    CHECK (VALUE ~ '^[A-Z]{2}[0-9]{10,18}$');

CREATE DOMAIN customer_id AS BIGINT
    CHECK (VALUE > 0 AND VALUE < 10000000000);
```

### 2. 受限字符串（电子邮件、电话、URL）

```sql
CREATE DOMAIN email AS VARCHAR(254)
    CHECK (VALUE ~ '^[^@]+@[^@]+\.[^@]+$');

CREATE DOMAIN url AS VARCHAR(2048)
    CHECK (VALUE ~ '^https?://');

CREATE DOMAIN intl_phone AS VARCHAR(25)
    CHECK (VALUE ~ '^\+[0-9]{1,3}[0-9 \-]{6,20}$');
```

### 3. 数值范围（百分比、评分、年龄）

```sql
CREATE DOMAIN percentage AS NUMERIC(5, 2)
    CHECK (VALUE BETWEEN 0 AND 100);

CREATE DOMAIN rating AS SMALLINT
    CHECK (VALUE BETWEEN 1 AND 5);

CREATE DOMAIN age AS SMALLINT
    CHECK (VALUE BETWEEN 0 AND 150);
```

### 4. 货币与金融

```sql
CREATE DOMAIN usd_money AS NUMERIC(18, 2)
    DEFAULT 0
    CHECK (VALUE >= -999999999999999.99 AND VALUE <= 999999999999999.99);

CREATE DOMAIN non_negative_money AS NUMERIC(18, 2)
    DEFAULT 0
    CHECK (VALUE >= 0);
```

### 5. ISO 标准代码

```sql
CREATE DOMAIN iso3166_alpha2 AS CHAR(2)
    CHECK (VALUE ~ '^[A-Z]{2}$');

CREATE DOMAIN iso4217_currency AS CHAR(3)
    CHECK (VALUE ~ '^[A-Z]{3}$');

CREATE DOMAIN iso639_language AS CHAR(2)
    CHECK (VALUE ~ '^[a-z]{2}$');
```

## DDL 演化与向后兼容

### 添加约束到现有域

```sql
-- PostgreSQL：新约束必须对所有现有数据成立
ALTER DOMAIN email ADD CONSTRAINT email_lowercase
    CHECK (VALUE = LOWER(VALUE));
-- 若有列值不满足，会失败

-- 对策：先 NOT VALID 声明，后分批处理
ALTER DOMAIN email ADD CONSTRAINT email_lowercase
    CHECK (VALUE = LOWER(VALUE)) NOT VALID;

-- 分批修复数据
UPDATE customers SET email = LOWER(email) WHERE email <> LOWER(email);

-- 标记为有效
ALTER DOMAIN email VALIDATE CONSTRAINT email_lowercase;
```

### 修改底层类型（部分引擎）

```sql
-- Firebird 允许
ALTER DOMAIN email TYPE VARCHAR(320);

-- PostgreSQL 不允许修改底层类型，需要删除重建
-- 迂回方案：
-- 1. CREATE DOMAIN email_new AS VARCHAR(320) CHECK (...);
-- 2. ALTER TABLE ... ALTER COLUMN email TYPE email_new USING email::text::email_new;
-- 3. DROP DOMAIN email;
-- 4. ALTER DOMAIN email_new RENAME TO email;
```

## 关键发现

1. **标准与现实的鸿沟**：SQL:1992 引入 `CREATE DOMAIN` 已 30 余年，但约 80% 的主流引擎仍不支持，反映了"标准先行、厂商各自为政"的 SQL 生态特征。

2. **PostgreSQL 是类型系统标杆**：唯一同时提供 DOMAIN、ENUM、Composite Type、Range/Multirange 的引擎，配合自定义 operator class，几乎能表达任何业务约束。

3. **两条主流路线**：
   - **SQL-92 路线**（DOMAIN 为主）：PostgreSQL、Firebird、H2、HSQLDB、Informix
   - **SQL-99 OO 路线**（CREATE TYPE）：Oracle（OBJECT）、DB2（STRUCTURED / DISTINCT）、Teradata

4. **MPP/云数仓普遍弱化类型系统**：Snowflake、BigQuery、Redshift、ClickHouse、Databricks 等倾向于"数据完整性在上游"的理念，CHECK 约束即便声明也常常不强制。

5. **SQL Server 的独特定位**：用 `CREATE TYPE FROM` 做别名类型（不支持 CHECK），但用 `CREATE TYPE AS TABLE` 为 TVP 提供了无可替代的批量参数传递能力。

6. **ENUM 的双形态**：PostgreSQL/CockroachDB/DuckDB 走独立类型路线，MySQL/MariaDB/TiDB/ClickHouse 走列类型路线。前者便于演化和跨列复用，后者与传统 SQL 引擎耦合更紧。

7. **Range 类型是 PG 独有护城河**：Range + GiST 排他约束能优雅处理时间段冲突、房间预订、价格区间等场景，其他引擎需手工实现。

8. **DISTINCT TYPE 在 DB2/Teradata 最严格**：完全名义类型，跨类型运算必须 CAST，类型安全最高但使用繁琐。相比之下 PostgreSQL 的 DOMAIN 是结构化兼容的，使用更轻便但类型强度较弱。

9. **Oracle 的 OBJECT 是 PL/SQL 附属**：真正的 OO 能力（继承、方法、REF）深度绑定 PL/SQL，纯 SQL 场景使用成本高。

10. **演化成本的差异**：PG ENUM 的 `ADD VALUE` 是瞬时的（只改系统表），而 DOMAIN CHECK 的修改需要扫描全表验证——在大表上，选择 ENUM 还是 DOMAIN 会影响运维窗口。

11. **SQL Server TVP 的独特价值**：作为"表作为参数"的标准化实现，SQL Server 的 `CREATE TYPE AS TABLE` 是其他引擎难以复制的接口能力，常被用于批量 upsert、报表参数、动态 IN 列表替代。

12. **无 DOMAIN 引擎的补偿机制**：MySQL 依赖 CHECK + TRIGGER，Snowflake 依赖 MASKING POLICY + 上游验证，BigQuery 依赖 DBT/数据血缘工具——不同引擎用不同层次的工具填补类型系统的缺口。

## 对引擎开发者的建议

### 1. 域与底层类型的互转语义

```
关键决策：域是结构化兼容还是名义类型？

结构化兼容（PostgreSQL DOMAIN）:
  - VALUE 赋值无需 CAST
  - 运算结果是基础类型，重新赋给域列时重新验证 CHECK
  - 实现简单，兼容性好

名义类型（DB2 DISTINCT TYPE）:
  - 跨类型运算必须 CAST
  - 类型安全更强
  - 需要为每个域重新生成比较/运算函数（WITH COMPARISONS）
```

### 2. CHECK 约束的求值时机

```
插入/更新时点检：最常见的实现
  - INSERT / UPDATE 时对新值运行 CHECK 表达式
  - 失败则回滚语句

ALTER DOMAIN 时的全表验证：
  - 新增 CHECK 需扫描所有引用列
  - 大表上可能阻塞长时间
  - 推荐提供 NOT VALID + VALIDATE 两步法

不变性要求：
  - CHECK 表达式应为 IMMUTABLE
  - 不能引用其他表（避免时间依赖）
  - PostgreSQL 不严格检查，但违反会导致一致性问题
```

### 3. 跨表共享的元数据管理

```
域的依赖追踪：
  - 系统表记录：域 → 引用它的列
  - DROP DOMAIN 前检查依赖
  - CASCADE 时自动改列类型回底层类型？还是拒绝？

元数据缓存：
  - 域的 CHECK 表达式应预编译
  - 频繁 INSERT 场景下，解析每次约束代价高
  - PostgreSQL 的做法：在 CacheInvalidRelcache 触发时清理
```

### 4. 并行与分区场景

```
分布式引擎的挑战：
  - 域定义需全局一致（通过元数据广播）
  - ENUM 值添加需要 DDL 串行化
  - CockroachDB 的做法：ENUM 变更走异步迁移协议

分区表：
  - 每个分区复用同一域，CHECK 在分区路由前还是后？
  - PostgreSQL 在每个分区独立验证，开销可并行
```

### 5. 类型系统与查询优化器交互

```
CHECK 约束可用于：
  - 常量折叠: percent_col <= 100 恒成立 → 可消除下推
  - 分区消除: CHECK VALUE IN ('A','B') → 分区选择
  - Null 推断: NOT NULL 域 → NULL 检查可消除

建议在优化器的 ConstraintExclusion 阶段读取域约束，
与列约束一视同仁，最大化可消除的谓词。
```

### 6. 序列化与客户端协议

```
域值在客户端协议中的表示：
  - PostgreSQL 线协议: 域作为底层类型 OID 传输，客户端看不到域
    优点: 驱动不需更新
    缺点: ORM 难以识别业务类型
  - DB2 DISTINCT TYPE: 有独立 OID，驱动需支持

推荐: 协议中同时携带底层类型 OID 和域名，便于 ORM 映射
```

### 7. ALTER DOMAIN 的在线 DDL

```
难点：修改域会影响所有引用列
  - 加 CHECK: 需扫描所有引用列验证 → 长时间持锁
  - 改底层类型: 需重写所有引用列数据 → 代价巨大

在线方案:
  1. 新约束先标记 NOT VALID（不验证新值）
  2. 后台逐步扫描验证
  3. 验证完成后标记 VALIDATED
  4. 对于改底层类型，采用双写方案:
     - 添加新列（新类型）
     - 双写旧列和新列
     - 迁移完成后交换
```

## 参考资料

- SQL:1992 标准: ISO/IEC 9075:1992，Section 11.24 (CREATE DOMAIN)
- SQL:1999 标准: ISO/IEC 9075-2:1999，第 4 部分 (User-Defined Types)
- SQL:2003 标准: ISO/IEC 9075-2:2003，Section 11.51 (user-defined type definition)
- PostgreSQL: [CREATE DOMAIN](https://www.postgresql.org/docs/current/sql-createdomain.html)
- PostgreSQL: [CREATE TYPE](https://www.postgresql.org/docs/current/sql-createtype.html)
- PostgreSQL: [Range Types](https://www.postgresql.org/docs/current/rangetypes.html)
- PostgreSQL: [Enumerated Types](https://www.postgresql.org/docs/current/datatype-enum.html)
- Oracle: [CREATE TYPE](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/CREATE-TYPE-Statement.html)
- SQL Server: [CREATE TYPE](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-type-transact-sql)
- SQL Server: [User-Defined Table Types](https://learn.microsoft.com/en-us/sql/relational-databases/tables/use-table-valued-parameters-database-engine)
- DB2: [CREATE DISTINCT TYPE](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-distinct-type)
- DB2: [CREATE TYPE (structured)](https://www.ibm.com/docs/en/db2/11.5?topic=statements-create-type-structured)
- Firebird: [CREATE DOMAIN](https://firebirdsql.org/file/documentation/html/en/refdocs/fblangref50/firebird-50-language-reference.html#fblangref50-ddl-domain)
- H2: [CREATE DOMAIN](http://www.h2database.com/html/commands.html#create_domain)
- HSQLDB: [CREATE DOMAIN](http://hsqldb.org/doc/2.0/guide/builtinfunctions-chapt.html)
- MySQL: [CHECK constraints](https://dev.mysql.com/doc/refman/8.0/en/create-table-check-constraints.html)
- Snowflake: [Constraints](https://docs.snowflake.com/en/sql-reference/constraints-overview)
- Teradata: [DISTINCT UDT](https://docs.teradata.com/r/Teradata-Database-SQL-Data-Types-and-Literals)
- CockroachDB: [ENUM Types](https://www.cockroachlabs.com/docs/stable/enum)
- SAP HANA: [CREATE TYPE](https://help.sap.com/docs/SAP_HANA_PLATFORM)
- Date, C. J. "A Guide to the SQL Standard" (第4版，1997)，DOMAIN 一章
- Melton, J. "Understanding SQL's Stored Procedures" (1998)，用户定义类型章节
