# Amazon Redshift: ALTER TABLE

> 参考资料:
> - [Redshift ALTER TABLE](https://docs.aws.amazon.com/redshift/latest/dg/r_ALTER_TABLE.html)
> - [Redshift Table Design](https://docs.aws.amazon.com/redshift/latest/dg/c_best-practices-best-dist-key.html)


## 1. 基本语法

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users ADD COLUMN status SMALLINT DEFAULT 1;
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN phone CASCADE;
ALTER TABLE users RENAME COLUMN email TO email_address;
ALTER TABLE users RENAME TO members;
ALTER TABLE users ALTER COLUMN bio TYPE VARCHAR(65535);  -- 只能增大 VARCHAR
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```


## 2. 语法设计分析（对 SQL 引擎开发者）


### 2.1 ALTER TABLE 的严重限制（PostgreSQL 8.x 遗留）

Redshift 基于 PostgreSQL 8.0.2，许多现代 ALTER TABLE 功能缺失:

不支持的操作:
ALTER COLUMN SET NOT NULL / DROP NOT NULL（必须重建表！）
ADD COLUMN IF NOT EXISTS
多列同时添加（每条 ALTER TABLE 只能操作一列）
除增大 VARCHAR 外的类型修改

修改列属性的唯一方法 — CTAS 重建:
CREATE TABLE new_t (...) AS SELECT * FROM old_t;
DROP TABLE old_t; ALTER TABLE new_t RENAME TO old_t;
这个流程在大数据量下非常昂贵。

**设计分析:**
Redshift 作为 OLAP 引擎，表结构变更不是高频操作。
列存引擎修改列属性代价高（每列独立存储，修改需要重写整列）。

**对比:**

MySQL:      非常灵活（INSTANT/INPLACE/COPY）
PostgreSQL: 现代版本很灵活
CockroachDB: 支持大部分修改
Spanner:    也很严格（只能增大 STRING 长度）
BigQuery:   也不能修改列类型

### 2.2 DISTKEY/SORTKEY 修改

Redshift 允许修改数据分布策略，但代价是全表重建（后台执行）。
```sql
ALTER TABLE orders ALTER DISTKEY user_id;
ALTER TABLE orders ALTER DISTSTYLE KEY DISTKEY (user_id);
ALTER TABLE orders ALTER DISTSTYLE EVEN;
ALTER TABLE orders ALTER DISTSTYLE ALL;
ALTER TABLE orders ALTER DISTSTYLE AUTO;
```


修改排序键
```sql
ALTER TABLE orders ALTER SORTKEY (order_date, user_id);
ALTER TABLE orders ALTER SORTKEY AUTO;
ALTER TABLE orders ALTER SORTKEY NONE;
```


修改编码
```sql
ALTER TABLE users ALTER COLUMN bio ENCODE ZSTD;
ALTER TABLE users ALTER COLUMN status ENCODE AZ64;
ALTER TABLE orders ALTER ENCODE AUTO;
```


## 3. 约束管理（信息性约束）

```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id);
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;
ALTER TABLE users DROP CONSTRAINT uk_email;
-- 注意: 外键和唯一约束不强制执行（仅供优化器使用）
```


## 4. 数据操作

APPEND: 高效追加数据（源表数据被移动，非复制）
```sql
ALTER TABLE users_archive APPEND FROM users_staging;
-- 比 INSERT INTO ... SELECT 更快，但源表被清空
```


修改所有者
```sql
ALTER TABLE users OWNER TO new_owner;
```


## 5. CTAS 重建模式（修改不能直接修改的属性）

```sql
CREATE TABLE users_new
DISTSTYLE KEY DISTKEY (username) SORTKEY (created_at) AS
SELECT * FROM users;
DROP TABLE users;
ALTER TABLE users_new RENAME TO users;
```


## 6. 限制与注意事项

不支持多列同时添加
不支持 ADD COLUMN IF NOT EXISTS
不支持修改列 NOT NULL 属性
类型修改仅支持增大 VARCHAR 长度
ALTER DISTKEY/SORTKEY 触发后台数据重分布（大表耗时）
IDENTITY 列属性不能修改
约束是信息性的（不强制执行）

## 7. 横向对比: OLAP 引擎 ALTER TABLE

1. 列类型修改:
Redshift:   几乎不能修改（只能增大 VARCHAR）
BigQuery:   不能修改列类型
Snowflake:  支持部分（NUMBER 精度调整等）
ClickHouse: ALTER TABLE MODIFY COLUMN（支持较多类型转换）

2. 分布策略修改:
Redshift:   ALTER DISTSTYLE（全表重建）
BigQuery:   不能修改已有分区
Snowflake:  不需要（自动微分区）
ClickHouse: 不能修改 sharding_key

3. OLAP vs OLTP 的 DDL 差异:
OLTP（MySQL/PG/TiDB/CRDB）: ALTER TABLE 灵活，频繁变更是常态
OLAP（Redshift/BQ/SF）: ALTER TABLE 受限，表结构应在设计时确定
