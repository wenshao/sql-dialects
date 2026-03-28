# MariaDB: ALTER TABLE

MySQL 语法基础上的独有扩展

参考资料:
[1] MariaDB Knowledge Base - ALTER TABLE
https://mariadb.com/kb/en/alter-table/

## 1. 基本语法 (与 MySQL 大致相同)

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20) AFTER email;
ALTER TABLE users DROP COLUMN bio;
ALTER TABLE users MODIFY COLUMN username VARCHAR(128) NOT NULL;
ALTER TABLE users CHANGE COLUMN age user_age SMALLINT;
ALTER TABLE users RENAME TO members;
```


## 2. MariaDB 独有: ALGORITHM 和 LOCK

MariaDB 10.0+ 支持 Online DDL, 语法与 MySQL 5.6+ 类似
```sql
ALTER TABLE users ADD COLUMN status TINYINT DEFAULT 0,
    ALGORITHM=INPLACE, LOCK=NONE;
```

ALGORITHM: COPY | INPLACE | INSTANT (10.3.2+) | NOCOPY (10.3.2+)
NOCOPY 是 MariaDB 独有: 允许元数据修改但不允许数据重建
**对比 MySQL: MySQL 8.0 只有 COPY/INPLACE/INSTANT**


INSTANT ALTER (10.3.2+):
MariaDB 的 INSTANT 比 MySQL 8.0.12 更早实现
```sql
ALTER TABLE users ADD COLUMN verified BOOLEAN DEFAULT FALSE, ALGORITHM=INSTANT;
```

MariaDB INSTANT 支持: ADD COLUMN (任意位置), 修改 DEFAULT, DROP COLUMN (10.4+)
MySQL 8.0 INSTANT: 仅支持 ADD COLUMN (末尾) 直到 8.0.29 才支持任意位置

## 3. INVISIBLE 列操作 (10.3.3+)

```sql
ALTER TABLE users ALTER COLUMN phone SET INVISIBLE;
ALTER TABLE users ALTER COLUMN phone SET VISIBLE;
-- 不需要重建表, 只修改元数据, 是 INSTANT 操作
```


## 4. 系统版本控制的 ALTER

为现有表启用系统版本控制
```sql
ALTER TABLE users ADD SYSTEM VERSIONING;
-- 移除系统版本控制 (历史数据丢失)
ALTER TABLE users DROP SYSTEM VERSIONING;
-- 清理历史数据
DELETE HISTORY FROM contracts WHERE row_end < '2023-01-01';
-- 10.4+: 可将历史数据路由到不同的存储引擎
ALTER TABLE products ADD PARTITION BY SYSTEM_TIME (
    PARTITION p_history HISTORY ENGINE=Archive,
    PARTITION p_current CURRENT ENGINE=InnoDB
);
```


## 5. IF EXISTS / IF NOT EXISTS 扩展

MariaDB 在更多 DDL 中支持 IF EXISTS (MySQL 部分不支持)
```sql
ALTER TABLE users DROP COLUMN IF EXISTS phone;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);
```

这避免了脚本执行时的错误, 提高了幂等性
**对比 MySQL: ALTER TABLE ... DROP COLUMN IF EXISTS 在 8.0 中不支持**


## 6. 索引操作差异

MariaDB 10.6+: IGNORED 索引 (等价于 MySQL 的 INVISIBLE INDEX)
```sql
ALTER TABLE users ALTER INDEX uk_username IGNORED;
ALTER TABLE users ALTER INDEX uk_username NOT IGNORED;
```

语义相同: 优化器忽略该索引, 但仍维护更新
设计分歧: MySQL 选择 INVISIBLE/VISIBLE 关键字, MariaDB 选择 IGNORED/NOT IGNORED

## 7. 引擎切换

```sql
ALTER TABLE users ENGINE=Aria;
```

Aria 是 MariaDB 独有的崩溃安全 MyISAM 替代品
Aria 特点: 支持崩溃恢复, 行级锁(部分场景), 但无事务
**对比: MySQL 中 MyISAM 无崩溃安全替代品**


## 8. 对引擎开发者: Online DDL 实现差异

MariaDB 的 Online DDL 与 MySQL 的实现路径已经分叉:
- MariaDB 在 InnoDB 层独立维护 Online DDL 代码
- 10.3+ 的 INSTANT DDL 比 MySQL 更激进 (支持更多操作)
- 10.4+ 的 DROP COLUMN INSTANT 是 MariaDB 领先特性
- MariaDB 的 ALTER TABLE ... ALGORITHM 语法更丰富 (多了 NOCOPY)

核心权衡:
INSTANT 更快但实现复杂: 需要在行格式中记录列变更历史
INPLACE 重建索引但不锁表: 需要 row log 记录并发 DML
COPY 最安全但最慢: 创建新表 → 复制数据 → 原子交换
