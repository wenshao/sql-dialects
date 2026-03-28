# TiDB: 数值类型

> 参考资料:
> - [TiDB SQL Reference](https://docs.pingcap.com/tidb/stable/sql-statement-overview)
> - [TiDB - MySQL Compatibility](https://docs.pingcap.com/tidb/stable/mysql-compatibility)
> - [TiDB - Functions and Operators](https://docs.pingcap.com/tidb/stable/functions-and-operators-overview)

**引擎定位**: 分布式 HTAP 数据库，兼容 MySQL 协议。基于 TiKV 行存 + TiFlash 列存，Raft 共识。

```sql
CREATE TABLE examples (
    tiny_val   TINYINT,
    small_val  SMALLINT,
    int_val    INT,
    big_val    BIGINT,
    pos_val    INT UNSIGNED,
    flag       TINYINT(1)
);

```

BOOL/BOOLEAN (same as MySQL)
```sql
CREATE TABLE t (active BOOLEAN DEFAULT TRUE);

```

DECIMAL (same as MySQL)
```sql
CREATE TABLE prices (
    price    DECIMAL(10,2),
    rate     DECIMAL(5,4)
);

```

AUTO_INCREMENT (same as MySQL, but consider AUTO_RANDOM for distributed)
```sql
CREATE TABLE t1 (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY);

```

AUTO_RANDOM: distributed auto-generated ID (3.1+)
Randomizes high bits to avoid write hotspot
```sql
CREATE TABLE t2 (id BIGINT NOT NULL AUTO_RANDOM PRIMARY KEY);

```

AUTO_RANDOM bit configuration
```sql
CREATE TABLE t3 (id BIGINT NOT NULL AUTO_RANDOM(5) PRIMARY KEY);
```

5 shard bits = 32 shards, remaining bits for auto-increment sequence

AUTO_INCREMENT behavior differences:
TiDB allocates AUTO_INCREMENT IDs in batches per TiDB server instance
IDs are globally unique but NOT necessarily sequential
Different TiDB servers may generate IDs in different ranges
Example: Server A gets 1-30000, Server B gets 30001-60000

Auto-ID cache control (6.4+)
Control batch allocation size
```sql
CREATE TABLE t (id BIGINT AUTO_INCREMENT PRIMARY KEY) AUTO_ID_CACHE 1;
```

AUTO_ID_CACHE 1: allocate one at a time (sequential, but slower)
AUTO_ID_CACHE 0: use centralized allocation (globally sequential, 6.4+)

FLOAT/DOUBLE (same as MySQL, same precision caveats)
```sql
CREATE TABLE t (
    val_f FLOAT,
    val_d DOUBLE
);

```

Display width deprecated (same as MySQL 8.0.17+)
INT(11) display width is parsed but ignored

UNSIGNED (same as MySQL)
UNSIGNED on FLOAT/DOUBLE/DECIMAL is deprecated (same as MySQL 8.0.17+)

BIT type (same as MySQL)
```sql
CREATE TABLE t (flags BIT(8));

```

Limitations:
AUTO_INCREMENT IDs are not globally sequential (allocated in batches)
AUTO_RANDOM column must be BIGINT and first column of PRIMARY KEY
Numeric precision follows MySQL rules
No difference in numeric type storage or range vs MySQL
FLOAT(M,D) / DOUBLE(M,D) syntax deprecated (same as MySQL 8.0.17+)
