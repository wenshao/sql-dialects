# DamengDB (达梦): 约束 (Constraints)

DamengDB is a Chinese enterprise database with Oracle-compatible syntax.

> 参考资料:
> - [DamengDB SQL 开发指南](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB 系统管理员手册](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)
> - [DamengDB SQL 语言手册 - 约束](https://eco.dameng.com/document/dm/zh-cn/sql-dev/chapter08-constraints.html)
> - [Oracle Database Constraints Documentation](https://docs.oracle.com/en/database/oracle/oracle-database/23/adfns/constraints.html)


## PRIMARY KEY（主键约束）


## 表级约束（推荐: 命名约束便于管理）

```sql
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);
```

## 复合主键

```sql
ALTER TABLE order_items ADD CONSTRAINT pk_order_items
    PRIMARY KEY (order_id, item_id);
```

## 内联约束（在 CREATE TABLE 中直接定义）

```sql
CREATE TABLE users (
    id         BIGINT       NOT NULL,
    username   VARCHAR(64)  NOT NULL,
    email      VARCHAR(255) NOT NULL,
    age        INT,
    CONSTRAINT pk_users PRIMARY KEY (id)    -- 命名内联约束
);
```

## 也可以省略 CONSTRAINT 关键字（自动生成约束名）

```sql
CREATE TABLE products (
    id   BIGINT      NOT NULL PRIMARY KEY,  -- 内联主键（自动命名）
    name VARCHAR(255) NOT NULL
);
```

## UNIQUE 约束（唯一性约束）


## 表级唯一约束

```sql
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
```

## 复合唯一约束

```sql
ALTER TABLE users ADD CONSTRAINT uk_name_email UNIQUE (username, email);
```

## 内联唯一约束

```sql
CREATE TABLE products (
    id  BIGINT      NOT NULL PRIMARY KEY,
    sku VARCHAR(64) NOT NULL UNIQUE,          -- 内联唯一约束
    name VARCHAR(255) NOT NULL
);
```

唯一约束与索引的关系（与 Oracle 相同）:
DamengDB 自动为 UNIQUE 约束创建唯一索引
约束名和索引名相同
删除约束时自动删除对应索引

## FOREIGN KEY 约束（外键约束）


```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE;
```

支持的引用操作:
ON DELETE: CASCADE / SET NULL / NO ACTION（默认）
ON UPDATE: 仅支持 NO ACTION（与 Oracle 相同）
不支持 ON UPDATE CASCADE / SET NULL / SET DEFAULT
复合外键

```sql
ALTER TABLE order_items ADD CONSTRAINT fk_items_order
    FOREIGN KEY (order_id) REFERENCES orders (id);
```

## 自引用外键（同一表内的父子关系）

```sql
ALTER TABLE employees ADD CONSTRAINT fk_manager
    FOREIGN KEY (manager_id) REFERENCES employees (id);
```

## NOT NULL 约束

## DamengDB 的 NOT NULL 语法与 Oracle 高度一致

```sql
ALTER TABLE users MODIFY (email NOT NULL);    -- 添加 NOT NULL
ALTER TABLE users MODIFY (email NULL);        -- 允许 NULL
```

## 也可以使用 CONSTRAINT 子句命名 NOT NULL 约束

```sql
ALTER TABLE users MODIFY email CONSTRAINT nn_email NOT NULL;
```

## DEFAULT 约束

```sql
ALTER TABLE users MODIFY (status DEFAULT 1);
ALTER TABLE users MODIFY (status DEFAULT 0);
```

## 默认值可以是函数表达式

```sql
ALTER TABLE users MODIFY (created_at DEFAULT SYSDATE);
ALTER TABLE users MODIFY (updated_at DEFAULT CURRENT_TIMESTAMP);
```

## CHECK 约束

```sql
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE events ADD CONSTRAINT chk_dates CHECK (end_date > start_date);
ALTER TABLE products ADD CONSTRAINT chk_price CHECK (price > 0);
```

CHECK 约束的条件限制（与 Oracle 相同）:
不能包含子查询
不能包含 SYSDATE 等不确定函数
不能引用其他表的列
不能包含用户自定义函数

## 可延迟约束（Deferred Constraints）

可延迟约束允许在事务提交时才验证约束（而非每条 DML 时验证）。
这是 DamengDB 与 Oracle 共有的高级特性，大多数数据库不支持。
DEFERRABLE INITIALLY DEFERRED: 事务提交时才检查

```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    DEFERRABLE INITIALLY DEFERRED;
```

## DEFERRABLE INITIALLY IMMEDIATE: 默认立即检查，但可切换

```sql
ALTER TABLE order_items ADD CONSTRAINT fk_items_order
    FOREIGN KEY (order_id) REFERENCES orders (id)
    DEFERRABLE INITIALLY IMMEDIATE;
```

## 在会话中切换延迟模式

```sql
SET CONSTRAINTS fk_orders_user DEFERRED;   -- 延迟检查
SET CONSTRAINTS fk_orders_user IMMEDIATE;  -- 立即检查
SET CONSTRAINTS ALL DEFERRED;              -- 延迟所有可延迟约束
```

使用场景: 批量导入数据时临时延迟外键检查，提升性能
对比 PostgreSQL: 也支持 DEFERRABLE（是少数支持该特性的数据库之一）
对比 MySQL: 不支持可延迟约束
对比 SQL Server: 不支持可延迟约束

## 约束启用/禁用（ENABLE / DISABLE）

## DamengDB 支持在不删除约束的情况下启用/禁用约束（Oracle 兼容）

禁用约束（不删除，不验证）

```sql
ALTER TABLE users DISABLE CONSTRAINT chk_age;
```

## 启用约束（验证已有数据）

```sql
ALTER TABLE users ENABLE CONSTRAINT chk_age;
```

## 启用但不验证已有数据（NOVALIDATE）

```sql
ALTER TABLE users ENABLE NOVALIDATE CONSTRAINT chk_age;
```

## VALIDATE: 检查所有数据（默认行为）

```sql
ALTER TABLE users ENABLE VALIDATE CONSTRAINT chk_age;
```

## 禁用主键/唯一约束时可以选择保留索引

```sql
ALTER TABLE users DISABLE CONSTRAINT pk_users;        -- 禁用约束且删除索引
```

## 删除约束

```sql
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE users DROP CONSTRAINT uk_email CASCADE;  -- 级联删除依赖约束
```

## 删除主键约束（如果有外键引用，需要 CASCADE）

```sql
ALTER TABLE users DROP PRIMARY KEY;
ALTER TABLE users DROP PRIMARY KEY CASCADE;  -- 同时删除引用该主键的外键
```

## 查看约束元数据

## DamengDB 使用与 Oracle 兼容的系统视图

```sql
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE, SEARCH_CONDITION, STATUS, DEFERRED
FROM USER_CONSTRAINTS
WHERE TABLE_NAME = 'USERS';

SELECT CONSTRAINT_NAME, COLUMN_NAME, POSITION
FROM USER_CONS_COLUMNS
WHERE TABLE_NAME = 'USERS'
ORDER BY CONSTRAINT_NAME, POSITION;
```

## 查看所有可延迟约束

```sql
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE, DEFERRABLE, DEFERRED
FROM USER_CONSTRAINTS
WHERE DEFERRABLE = 'DEFERRABLE';
```

## 与 Oracle 的差异

DamengDB 约束语法与 Oracle 高度兼容，但存在以下差异:
11.1 基本兼容:
CONSTRAINT / MODIFY / ENABLE / DISABLE / DEFERRABLE 语法一致
USER_CONSTRAINTS / USER_CONS_COLUMNS 系统视图结构一致
CHECK 约束条件限制一致
11.2 细微差异:
Oracle 支持 ON UPDATE CASCADE（11g+），DamengDB 仅支持 NO ACTION
Oracle 支持 NOVALIDATE 与 RELY 组合（用于查询重写），DamengDB 不支持
Oracle 的 USING INDEX 子句更丰富（可指定索引表空间等）
Oracle 支持 RELY / NORELY 子句（物化视图查询重写信任标记）
Oracle 支持 ENABLE VALIDATE / ENABLE NOVALIDATE 更细粒度控制
11.3 性能差异:
DamengDB 单机部署，约束验证无分布式开销
Oracle RAC 集群下约束验证需要跨节点协调（但用户透明）

## 设计分析（对 SQL 引擎开发者）


12.1 可延迟约束的实现复杂度:
- **立即约束**: 每条 DML 后立即验证，简单直观
- **延迟约束**: 在事务提交时批量验证，需要:
a. 在事务上下文中记录所有待验证的约束
b. 提交时按正确顺序验证（先 CHECK，再 UNIQUE，最后 FK）
c. 验证失败需要回滚整个事务
- **启发**: 可延迟约束是高级特性，大多数应用不需要，但对数据迁移场景很有价值
12.2 NOVALIDATE 的设计意义:
- **数据仓库场景**: 历史数据可能有脏数据，但新数据需要约束
- **数据迁移场景**: 先导入数据（不验证），后启用约束（NOVALIDATE）
- **性能**: NOVALIDATE 启用约束不需要扫描全表（瞬间完成）
12.3 跨方言对比:
- **DamengDB**: Oracle 兼容，DEFERRABLE, ENABLE/DISABLE, NOVALIDATE
- **Oracle**: 最完整（RELY, USING INDEX, EXCEPTIONS INTO 等）
- **PostgreSQL**: DEFERRABLE（仅 FK 和 UNIQUE），无 ENABLE/DISABLE
- **MySQL**: 无 DEFERRABLE，无 ENABLE/DISABLE（约束始终生效）
- **SQL Server**: 无 DEFERRABLE，NOCHECK 类似 DISABLE，但语法不同
- **SQLite**: 简单约束支持，PRAGMA foreign_keys 控制外键开关
12.4 版本演进:
- **DM7**: 基础约束支持（PK, UK, FK, CHECK, NOT NULL）
- **DM8**: DEFERRABLE, ENABLE/DISABLE, NOVALIDATE 增强
- **DM8 最新**: 完整 Oracle 约束兼容，系统视图对齐
