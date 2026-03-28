# MySQL: 约束

> 参考资料:
> - [MySQL 8.0 Reference Manual - Constraints](https://dev.mysql.com/doc/refman/8.0/en/constraints.html)
> - [MySQL 8.0 Reference Manual - CHECK Constraints](https://dev.mysql.com/doc/refman/8.0/en/create-table-check-constraints.html)
> - [MySQL 8.0 Reference Manual - FOREIGN KEY Constraints](https://dev.mysql.com/doc/refman/8.0/en/create-table-foreign-keys.html)
> - [MySQL 8.0 Reference Manual - Constraint Enforcement](https://dev.mysql.com/doc/refman/8.0/en/constraint-primary-key.html)

## 基本语法

PRIMARY KEY（InnoDB 中即聚集索引，决定数据的物理存储顺序）
```sql
CREATE TABLE users (
    id BIGINT NOT NULL AUTO_INCREMENT,
    PRIMARY KEY (id)
);
-- 复合主键
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);
```

UNIQUE（MySQL 中唯一约束通过唯一索引实现，两者等价）
```sql
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
ALTER TABLE users ADD CONSTRAINT uk_name_email UNIQUE (username, email);
```

FOREIGN KEY
```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;
```

引用动作: CASCADE / SET NULL / RESTRICT / NO ACTION / SET DEFAULT(InnoDB 不支持 SET DEFAULT)
RESTRICT vs NO ACTION: 在 MySQL 中行为相同（立即检查）
  在 PostgreSQL/SQL Server 中: NO ACTION 可以延迟到事务提交时检查（DEFERRABLE）

NOT NULL
```sql
ALTER TABLE users MODIFY COLUMN email VARCHAR(255) NOT NULL;
```

DEFAULT
```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;
```

CHECK（8.0.16+）
```sql
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
```

删除约束
```sql
ALTER TABLE users DROP INDEX uk_email;                 -- 删除唯一约束（通过删索引）
ALTER TABLE orders DROP FOREIGN KEY fk_orders_user;    -- 删除外键
ALTER TABLE users DROP CHECK chk_age;                  -- 8.0.16+

-- 查看约束
SELECT * FROM information_schema.TABLE_CONSTRAINTS WHERE TABLE_NAME = 'users';
SELECT * FROM information_schema.CHECK_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE();
```

## CHECK 约束的历史: 一个著名的设计教训（对 SQL 引擎开发者）

### 三个阶段:

MySQL 5.7 及之前: 解析 CHECK 语法但不执行！
  CREATE TABLE t (age INT CHECK (age >= 0));  -- 语法通过，但约束不生效
  INSERT INTO t VALUES (-1);                  -- 成功！没有任何报错
  这是数据库历史上最著名的 "接受但不执行" 问题之一

MySQL 8.0.15: 仍然只解析不执行（虽然文档说支持，但实际没有）

MySQL 8.0.16+: CHECK 约束真正生效
  INSERT INTO t VALUES (-1);                  -- 报错: Check constraint 'chk_age' is violated
> **注意**: 从不执行到执行的迁移可能导致现有数据违反约束
        MySQL 不会自动校验已有数据，只在新 INSERT/UPDATE 时检查

### 为什么这是一个严重的设计失误？

  a. 违反最小惊讶原则: 用户写了 CHECK 约束，合理期望它会工作
  b. 数据完整性无声失败: 没有警告、没有错误，脏数据安静地流入
  c. 跨数据库迁移风险: 从 PostgreSQL/Oracle 迁移到 MySQL 的应用，CHECK 约束失效但无人知晓

对引擎开发者的教训:
  原则: 要么执行，要么拒绝语法。绝对不要接受但不执行。
  如果暂时不支持某个功能，应该返回 "语法不支持" 错误，而不是静默忽略。
  很多新引擎在兼容 MySQL 语法时也犯了类似错误（如某些 NewSQL 引擎解析外键但不执行）。

## 外键的性能影响和分布式困境（对 SQL 引擎开发者）

### 外键在单机 InnoDB 中的开销

  每次 INSERT/UPDATE 子表时: 需要在父表的索引上做一次查找（验证引用存在）
  每次 DELETE/UPDATE 父表时: 需要在子表的索引上做一次查找（检查是否被引用）
  这些检查需要额外的锁:
    - INSERT 子表时: 对父表的引用行加 SHARED 锁（防止父行被并发删除）
    - CASCADE DELETE 时: 对子表行加 EXCLUSIVE 锁
  高并发 OLTP: 外键检查的锁竞争可能成为瓶颈（每次 DML 多一次索引查找 + 加锁）

### 分布式环境下的外键困境

  分布式数据库中，父子表可能在不同的节点/分片上:
  - 外键检查变成分布式事务（跨节点加锁 + 验证）
  - 性能代价: 单次写入从 1 次本地 I/O 变成 1 次本地 + 1 次跨网络 RPC
  - CASCADE 操作: 可能涉及多个节点的协调，延迟不可控

  各分布式引擎的策略:
    TiDB:       6.6+ 支持外键（之前 6 年不支持），但文档建议谨慎使用
    CockroachDB: 支持外键（强一致性保证），但跨 region 时性能下降显著
    Vitess:     不支持跨 shard 的外键
    PlanetScale: 明确不支持外键（fork 自 Vitess），推荐应用层保证完整性
    BigQuery:   外键是信息性的（ENFORCED 或 NOT ENFORCED），默认不强制执行
    Snowflake:  外键是信息性的，不强制执行（优化器可利用约束信息做优化）

### 外键 vs 应用层约束: 设计选择

  赞成外键: 数据完整性由数据库保证，应用层 bug 不会导致孤儿数据
  反对外键: 性能开销、分布式困难、schema 变更复杂（有外键的表 DDL 受限）
  业界趋势: 大厂多数放弃外键（Facebook/Uber/GitHub 的 MySQL 实践中不使用外键）
            应用层通过定期一致性检查脚本 + 监控告警替代

## 横向对比: 各引擎的约束执行策略

### CHECK 约束:

  MySQL 8.0.16+: 真正执行
  PostgreSQL:    从第一个版本就完整支持，最可靠的 CHECK 实现
  Oracle:        完整支持，可以设为 ENABLE/DISABLE/VALIDATE/NOVALIDATE（4 种组合）
                 NOVALIDATE = 新数据检查但不验证已有数据（适合数据迁移后启用约束）
  SQL Server:    完整支持，WITH NOCHECK 选项类似 Oracle 的 NOVALIDATE
  SQLite:        支持，但需要注意: 通过 ALTER TABLE 添加的列不支持 CHECK

### 约束延迟检查（DEFERRABLE）:

  PostgreSQL:    SET CONSTRAINTS ... DEFERRED（约束延迟到事务提交时检查）
                 用途: 循环外键（A 引用 B，B 引用 A）可以在同一事务中插入
  Oracle:        INITIALLY DEFERRED / INITIALLY IMMEDIATE
  MySQL:         不支持延迟约束检查！所有约束都是即时检查的
                 这意味着在 MySQL 中无法处理循环引用的 INSERT
  SQL Server:    不支持延迟约束

### 分布式 / 分析型引擎的约束策略:

  BigQuery:      PRIMARY KEY / FOREIGN KEY / NOT NULL 全部是信息性的（NOT ENFORCED）
                 优化器利用这些约束信息做查询优化（如 join elimination），但不强制执行
  Snowflake:     NOT NULL 强制执行，其他约束信息性
  Redshift:      所有约束信息性（优化器参考用），但 NOT NULL 强制执行
  ClickHouse:    没有传统约束概念，数据质量由 ETL 管道保证
  Hive:          不支持约束（3.0+ 开始添加信息性约束）

设计哲学:
  OLTP 引擎: 约束强制执行是核心特性（数据完整性优先）
  OLAP/数仓引擎: 约束信息性为主（查询优化优先，数据质量由上游保证）
  分布式 OLTP: 折中方案（本地约束强制执行，跨节点约束有限支持或不支持）

### 约束命名规范:

  MySQL:      约束名可选，系统自动生成（如 users_chk_1），不同约束类型命名规则不同
  PostgreSQL: 约束名可选，自动生成格式统一（如 users_age_check）
  Oracle:     未命名约束自动生成 SYS_C00xxxx，强烈建议显式命名（否则运维噩梦）
  最佳实践:   永远显式命名约束（便于后续 ALTER TABLE DROP CONSTRAINT）

对引擎开发者的总结:
  1) CHECK 约束: 要么完整实现并执行，要么不接受语法。MySQL 的教训已成反面教材。
  2) 外键: 单机引擎应完整支持；分布式引擎可以选择 "信息性外键"（供优化器使用但不强制执行）
  3) DEFERRABLE: 如果目标是 PostgreSQL 兼容，这是必须实现的特性
  4) 约束验证模式: 支持 NOVALIDATE 模式对数据迁移场景极其有用
