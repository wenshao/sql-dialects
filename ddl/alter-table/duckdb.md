# DuckDB: ALTER TABLE

> 参考资料:
> - [DuckDB Documentation - ALTER TABLE](https://duckdb.org/docs/sql/statements/alter_table)

**引擎定位**: 嵌入式 OLAP 分析引擎，类似 SQLite 的定位。列式存储 + 向量化执行，PostgreSQL 兼容语法。

## 基本语法

添加列
```sql
ALTER TABLE users ADD COLUMN phone VARCHAR;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR;
ALTER TABLE users ADD COLUMN status VARCHAR DEFAULT 'active' NOT NULL;

```

删除列
```sql
ALTER TABLE users DROP COLUMN bio;
ALTER TABLE users DROP COLUMN IF EXISTS bio;

```

重命名列
```sql
ALTER TABLE users RENAME COLUMN username TO user_name;

```

修改列类型
```sql
ALTER TABLE users ALTER COLUMN age TYPE BIGINT;
ALTER TABLE users ALTER COLUMN age SET DATA TYPE BIGINT;   -- SQL 标准写法

```

设置/删除默认值
```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 'active';
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

```

设置/删除 NOT NULL
```sql
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

```

重命名表
```sql
ALTER TABLE users RENAME TO app_users;

```

## 语法设计分析（对 SQL 引擎开发者）


### 列式存储的 ALTER TABLE: 为什么大多数操作是即时的

DuckDB 使用列式存储，ALTER TABLE 的实现与行式存储有本质区别:

行式存储（MySQL InnoDB）:
  ADD COLUMN: 可能需要重写所有数据页（每行都需要新增字段空间）
  MySQL 8.0.12+ ALGORITHM=INSTANT 仅支持末尾添加列

列式存储（DuckDB）:
  ADD COLUMN: 只需创建新的列段，已有列不受影响（即时完成）
  DROP COLUMN: 标记列为删除，惰性回收空间（即时完成）
  ALTER TYPE: 可能需要读取旧列数据并写入新格式（但只重写一列）

**设计 trade-off:**
  列存的 ALTER TABLE 天然更快（列之间独立存储）
  但修改列类型仍需要扫描该列所有数据（不过只是一列，不是全表）

**对比:** ALTER TABLE 性能:
  MySQL:      ADD COLUMN 可能需要全表重写（COPY 算法），8.0+ INSTANT 部分操作即时
  PostgreSQL: ADD COLUMN + DEFAULT 在 11+ 即时（之前需要重写全表）
  DuckDB:     大多数操作即时（列存优势）
  Databricks: Schema Evolution 只修改 Delta Log 元数据（不重写数据文件）

### PostgreSQL 兼容的 ALTER 语法

DuckDB 遵循 PostgreSQL 的 ALTER TABLE 语法:
  ALTER TABLE ... ALTER COLUMN ... TYPE ...（PostgreSQL 风格）
  而非:
  ALTER TABLE ... MODIFY COLUMN ...（MySQL 风格）
  ALTER TABLE ... ALTER COLUMN ... SET DATA TYPE ...（SQL 标准风格）
DuckDB 同时支持 TYPE 和 SET DATA TYPE
```sql
ALTER TABLE products ALTER COLUMN price TYPE DOUBLE;          -- PostgreSQL 风格
ALTER TABLE products ALTER COLUMN price SET DATA TYPE DOUBLE; -- SQL 标准风格

```

### IF NOT EXISTS / IF EXISTS: 幂等性设计

```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR;
ALTER TABLE users DROP COLUMN IF EXISTS bio;
```

设计价值: 让 DDL 迁移脚本可以安全重复执行
**对比:**
  MySQL:      不支持 ADD COLUMN IF NOT EXISTS（需要存储过程包装）
  PostgreSQL: 支持 ADD COLUMN IF NOT EXISTS（9.6+）
  Databricks: 支持
  Flink:      不支持

## 嵌套类型的 ALTER（DuckDB 特色）

DuckDB 支持 STRUCT/MAP/LIST 嵌套类型，但 ALTER 内部字段需要重建:

添加 STRUCT 列
```sql
ALTER TABLE users ADD COLUMN address STRUCT(street VARCHAR, city VARCHAR, zip VARCHAR);

```

修改 STRUCT 内部字段（不支持直接 ALTER，需要重建）:
```sql
ALTER TABLE users ADD COLUMN address_v2 STRUCT(
    street VARCHAR, city VARCHAR, zip VARCHAR, country VARCHAR
);
UPDATE users SET address_v2 = struct_pack(
    street := address.street, city := address.city,
    zip := address.zip, country := 'CN'
);
ALTER TABLE users DROP COLUMN address;
ALTER TABLE users RENAME COLUMN address_v2 TO address;

```

添加 LIST / MAP 列
```sql
ALTER TABLE users ADD COLUMN tags VARCHAR[];
ALTER TABLE users ADD COLUMN meta MAP(VARCHAR, VARCHAR);

```

修改 LIST 元素类型
```sql
ALTER TABLE users ALTER COLUMN scores SET DATA TYPE BIGINT[];

```

**设计分析:**
STRUCT 是固定 Schema 的嵌套类型，修改内部字段需要重写列数据。
MAP 是动态键值对，不需要 ALTER 内部结构。
列式存储下嵌套类型的编码（类似 Parquet Dremel 编码）使部分更新困难。

**对比:**
  Trino:      ROW 类型，ALTER 内部字段取决于 Connector
  Databricks: STRUCT 类型，支持 ADD COLUMN 到 STRUCT 内部
  Flink:      ROW 类型，ALTER 取决于 Catalog

## 约束管理

添加主键
```sql
ALTER TABLE users ADD PRIMARY KEY (id);

```

添加唯一约束
```sql
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

```

删除约束
```sql
ALTER TABLE users DROP CONSTRAINT uk_email;

```

DuckDB 约束特点:
  PRIMARY KEY: 强制执行（使用 ART 索引检查唯一性）
  UNIQUE: 强制执行
  NOT NULL: 强制执行
  CHECK: 强制执行
  FOREIGN KEY: 有限支持

**对比:**
  MySQL/PostgreSQL: 所有约束强制执行
  Databricks: CHECK/NOT NULL 强制执行，PK/FK/UNIQUE 信息性
  Flink: PRIMARY KEY NOT ENFORCED 只是语义提示
  Trino: 无约束语法

## 不支持的操作与替代方案

DuckDB 不支持:
  ALTER TABLE ... ADD INDEX（无传统 B-Tree 索引，用 Zone Maps 替代）
  ALTER TABLE ... AFTER/FIRST（列总是添加到末尾）
  ALTER TABLE ... USING expr（自定义类型转换表达式）
  ALTER TABLE ... SET SCHEMA（无 Schema 迁移）
  ALTER TABLE ... SET TABLESPACE（无表空间概念）

无索引的设计理由:
  DuckDB 是 OLAP 引擎，使用以下替代方案:
  Zone Maps（min/max 统计信息，自动维护）
  ART Index（仅用于 PRIMARY KEY 约束检查）
  并行全表扫描（列存 + 向量化执行，分析查询比索引更快）

## 横向对比: ALTER TABLE 能力矩阵

操作                DuckDB   MySQL      PostgreSQL  Flink    Databricks
ADD COLUMN          即时     可能重写    11+即时     部分     即时(元数据)
DROP COLUMN         即时     INSTANT    即时        部分     即时(需CM)
RENAME COLUMN       即时     即时       即时        部分     即时(需CM)
ALTER TYPE          扫描列   可能重写    需USING     部分     只允许放宽
ADD IF NOT EXISTS   支持     不支持     支持        不支持   支持
ADD CONSTRAINT      支持     支持       支持        PK only  信息性
ADD INDEX           不支持   支持       支持        不支持   不支持

## 对引擎开发者的启示

DuckDB 的 ALTER TABLE 设计体现了列式存储的天然优势:
列之间独立存储 → ADD/DROP COLUMN 只影响目标列 → 即时完成。

与行式存储形成对比:
行式存储中一行的所有列物理相邻 → 修改任何列可能影响所有行。

嵌套类型（STRUCT）的 ALTER 是列存引擎的设计难点:
STRUCT 内部字段在列存中是"扁平化"存储的（类似 Parquet 的 Dremel 编码），
修改内部字段相当于修改底层编码结构，比修改普通列更复杂。
Databricks 支持 ADD COLUMN 到 STRUCT 内部是因为 Delta Log 做了额外映射。
