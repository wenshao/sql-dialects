# OceanBase: 约束

> 参考资料:
> - [OceanBase Constraints (MySQL Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)
> - [OceanBase Constraints (Oracle Mode)](https://www.oceanbase.com/docs/common-oceanbase-database-cn)

**引擎定位**: 分布式关系型数据库，兼容 MySQL/Oracle 双模式。基于 LSM-Tree 存储，Paxos 共识。

## 基本语法 — MySQL 模式


PRIMARY KEY
```sql
CREATE TABLE users (
    id       BIGINT NOT NULL AUTO_INCREMENT,
    username VARCHAR(100) NOT NULL,
    PRIMARY KEY (id)
);

```

UNIQUE 约束
```sql
ALTER TABLE users ADD UNIQUE KEY uk_username (username);
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);

```

NOT NULL
```sql
ALTER TABLE users MODIFY COLUMN email VARCHAR(255) NOT NULL;

```

CHECK 约束（4.0+）
```sql
CREATE TABLE accounts (
    id      BIGINT NOT NULL AUTO_INCREMENT,
    balance DECIMAL(10,2),
    age     INT,
    PRIMARY KEY (id),
    CONSTRAINT chk_balance CHECK (balance >= 0),
    CONSTRAINT chk_age CHECK (age BETWEEN 0 AND 150)
);
ALTER TABLE users ADD CONSTRAINT chk_status CHECK (status IN (0, 1, 2));

```

FOREIGN KEY（完全支持且强制执行）
```sql
CREATE TABLE orders (
    id      BIGINT NOT NULL AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    amount  DECIMAL(10,2),
    PRIMARY KEY (id),
    CONSTRAINT fk_user FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE CASCADE ON UPDATE CASCADE
);

```

DEFAULT
```sql
CREATE TABLE defaults_example (
    id         BIGINT NOT NULL AUTO_INCREMENT,
    status     INT DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
);

```

## 语法设计分析（对 SQL 引擎开发者）


### 外键在分布式环境的完全支持

OceanBase 完全支持且强制执行外键约束，这在分布式引擎中较为罕见。
关键优化: Tablegroup（表组共置）使相关表的数据在同一组 OBServer 节点上，
外键检查变成本地操作而非跨节点 RPC。

**对比:**
  TiDB:        6.6+ 实验性支持外键（无共置机制，跨 Region RPC 开销大）
  CockroachDB: 完全支持（跨 Range 检查有延迟）
  Spanner:     支持（INTERLEAVE 模式下效率最高）
  Redshift:    信息性外键（不强制执行）

**对引擎开发者的启示:**
  外键的性能关键在于"参照表"和"被参照表"的数据是否共置。
  如果引擎有共置机制（Tablegroup/INTERLEAVE），外键支持就容易实现。

### 双模式的约束差异

MySQL 模式: CHECK 用 CHECK (expr)，外键用 FOREIGN KEY ... REFERENCES
Oracle 模式: 语法类似但关键字不同
  CONSTRAINT name CHECK (expr) ENABLE/DISABLE
  CONSTRAINT name REFERENCES table (col) ON DELETE CASCADE
  Oracle 模式支持 ENABLE/DISABLE 约束（MySQL 模式不支持）

## Oracle 模式约束

CREATE TABLE users_ora (
    id       NUMBER NOT NULL,
    username VARCHAR2(100) NOT NULL,
    CONSTRAINT pk_users PRIMARY KEY (id),
    CONSTRAINT uk_username UNIQUE (username),
    CONSTRAINT chk_age CHECK (age >= 0)
);

ALTER TABLE users_ora DISABLE CONSTRAINT chk_age;
ALTER TABLE users_ora ENABLE CONSTRAINT chk_age;
Oracle 模式独有: ENABLE/DISABLE 约束（临时禁用约束用于批量加载）

## 约束管理

```sql
ALTER TABLE users DROP CONSTRAINT chk_age;
ALTER TABLE orders DROP FOREIGN KEY fk_user;
ALTER TABLE users DROP INDEX uk_username;

```

查看约束
```sql
SHOW CREATE TABLE users;
SELECT * FROM information_schema.table_constraints WHERE table_name = 'users';
SELECT * FROM information_schema.key_column_usage WHERE table_name = 'users';

```

## 限制与注意事项

CHECK 约束: 4.0+ 完全支持
外键: 完全支持且强制执行（优于 TiDB）
排他约束 (EXCLUDE): 不支持
延迟约束 (DEFERRABLE): Oracle 模式部分支持
部分唯一约束: 不支持
主键决定数据分布（分区策略与主键紧密关联）

## 横向对比

## 约束强制执行:

   OceanBase:   所有约束强制执行（PK/UK/FK/CHECK/NOT NULL）
   CockroachDB: 所有约束强制执行
   TiDB:        FK 6.6+ 实验性
   Spanner:     所有约束强制执行
   Redshift:    仅 PK 强制

## ENABLE/DISABLE 约束:

   OceanBase (Oracle 模式) + Oracle: 支持
   MySQL/TiDB/PostgreSQL/CockroachDB: 不支持
   Redshift: 不适用（约束是信息性的）

## 分布式外键优化:

   OceanBase: Tablegroup 共置（外键检查本地化）
   Spanner:   INTERLEAVE IN PARENT（物理共置）
   CockroachDB: 依赖 Range 分布（可能跨节点）
   TiDB:      无共置机制（跨 Region RPC）
