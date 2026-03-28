# Redshift: 约束

> 参考资料:
> - [Redshift SQL Reference](https://docs.aws.amazon.com/redshift/latest/dg/cm_chap_SQLCommandRef.html)
> - [Redshift SQL Functions](https://docs.aws.amazon.com/redshift/latest/dg/c_SQL_functions.html)
> - [Redshift Data Types](https://docs.aws.amazon.com/redshift/latest/dg/c_Supported_data_types.html)


Redshift 的约束大多是信息性的，只有 NOT NULL 和 DEFAULT 被强制执行

## NOT NULL（强制执行）


```sql
CREATE TABLE users (
    id       BIGINT NOT NULL IDENTITY(1, 1),
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255)                    -- 默认允许 NULL
);
```


注意：不支持通过 ALTER TABLE 修改 NOT NULL 约束
需要通过 CTAS 重建表

## DEFAULT（强制执行）


```sql
CREATE TABLE users (
    id         BIGINT IDENTITY(1, 1),
    status     SMALLINT DEFAULT 1,
    created_at TIMESTAMP DEFAULT GETDATE(),
    updated_at TIMESTAMP DEFAULT SYSDATE       -- SYSDATE 也可用
);

ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```


## PRIMARY KEY（信息性，不强制执行）


```sql
CREATE TABLE users (
    id       BIGINT NOT NULL IDENTITY(1, 1),
    username VARCHAR(64) NOT NULL,
    PRIMARY KEY (id)
);
```


添加主键
```sql
ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);
```


复合主键
```sql
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);
```


## UNIQUE（信息性，不强制执行）


```sql
CREATE TABLE users (
    id       BIGINT IDENTITY(1, 1),
    email    VARCHAR(255),
    UNIQUE (email)
);

ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
```


## FOREIGN KEY（信息性，不强制执行）


```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id);
```


不支持 ON DELETE / ON UPDATE 动作（因为不强制执行）

## CHECK（不支持）

Redshift 不支持 CHECK 约束

## 删除约束


```sql
ALTER TABLE users DROP CONSTRAINT pk_users;
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;
```


## 信息性约束的作用

虽然不强制执行，但查询优化器使用约束信息：
1. 消除冗余的 JOIN
2. 优化 DISTINCT / GROUP BY
3. 简化谓词推导

示例：如果声明了 PK/FK，优化器可能消除不必要的 JOIN
前提：数据确实满足约束条件

## 查看约束


通过系统表查看
```sql
SELECT conname, contype, conrelid::regclass
FROM pg_constraint
WHERE conrelid = 'users'::regclass;
-- contype: p=主键, u=唯一, f=外键
```


通过 SVV 视图
```sql
SELECT * FROM svv_table_info WHERE "table" = 'users';
```


通过 information_schema
```sql
SELECT * FROM information_schema.table_constraints
WHERE table_name = 'users';
```


## 数据质量保障（替代约束的方案）


在 ETL 管道中验证数据
```sql
SELECT COUNT(*) AS duplicates
FROM (SELECT id, COUNT(*) FROM users GROUP BY id HAVING COUNT(*) > 1);

SELECT COUNT(*) AS orphans
FROM orders o
LEFT JOIN users u ON o.user_id = u.id
WHERE u.id IS NULL;
```


注意：只有 NOT NULL 和 DEFAULT 被强制执行
注意：PK、UNIQUE、FK 都是信息性的，不会阻止违反约束的数据
注意：不支持 CHECK 约束
注意：数据完整性需要在 ETL 管道或应用层保证
注意：正确声明信息性约束可以提升查询性能
