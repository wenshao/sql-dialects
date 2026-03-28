# Greenplum: 约束

> 参考资料:
> - [Greenplum SQL Reference](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/ref_guide-sql_commands-sql_ref.html)
> - [Greenplum Admin Guide](https://docs.vmware.com/en/VMware-Greenplum/7/greenplum-database/admin_guide-intro-about_greenplum.html)


Greenplum 基于 PostgreSQL，支持大部分 PG 约束
但分布式架构对约束有额外限制

## NOT NULL


```sql
CREATE TABLE users (
    id       BIGINT NOT NULL,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255) NOT NULL
)
DISTRIBUTED BY (id);
```


## PRIMARY KEY（必须包含分布键）


```sql
CREATE TABLE users (
    id       BIGINT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    email    VARCHAR(255)
)
DISTRIBUTED BY (id);
```


复合主键
```sql
CREATE TABLE order_items (
    order_id   BIGINT,
    item_id    BIGINT,
    quantity   INT,
    PRIMARY KEY (order_id, item_id)
)
DISTRIBUTED BY (order_id);
```


## UNIQUE（必须包含分布键）


```sql
CREATE TABLE users (
    id       BIGINT PRIMARY KEY,
    username VARCHAR(64) UNIQUE,            -- 错误！不含分布键
    email    VARCHAR(255)
)
DISTRIBUTED BY (id);
```


正确：UNIQUE 约束包含分布键
```sql
CREATE TABLE users (
    id       BIGINT,
    username VARCHAR(64),
    email    VARCHAR(255),
    UNIQUE (id, username)
)
DISTRIBUTED BY (id);
```


## FOREIGN KEY


```sql
CREATE TABLE orders (
    id       BIGINT PRIMARY KEY,
    user_id  BIGINT REFERENCES users(id),
    amount   NUMERIC(10,2)
)
DISTRIBUTED BY (id);
```


命名外键
```sql
ALTER TABLE orders ADD CONSTRAINT fk_user
    FOREIGN KEY (user_id) REFERENCES users(id)
    ON DELETE CASCADE ON UPDATE CASCADE;
```


注意：外键不强制执行（仅声明性），优化器可能使用

## CHECK


```sql
CREATE TABLE products (
    id       BIGINT,
    name     VARCHAR(128) NOT NULL,
    price    NUMERIC(10,2) CHECK (price > 0),
    quantity INT CHECK (quantity >= 0),
    CONSTRAINT chk_valid CHECK (price * quantity < 1000000)
)
DISTRIBUTED BY (id);
```


## DEFAULT


```sql
CREATE TABLE users (
    id         BIGSERIAL PRIMARY KEY,
    status     INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    uuid       UUID DEFAULT gen_random_uuid()
)
DISTRIBUTED BY (id);
```


## EXCLUDE（排他约束）


Greenplum 支持排他约束（需要 btree_gist 扩展）
CREATE EXTENSION btree_gist;
CREATE TABLE reservations (
room_id INT,
period TSRANGE,
EXCLUDE USING GIST (room_id WITH =, period WITH &&)
) DISTRIBUTED BY (room_id);

## 约束管理


添加约束
```sql
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0);
ALTER TABLE users ADD CONSTRAINT uq_email UNIQUE (email, id);
```


删除约束
```sql
ALTER TABLE users DROP CONSTRAINT chk_age;
```


查看约束
```sql
SELECT conname, contype FROM pg_constraint
WHERE conrelid = 'users'::regclass;
```


注意：PRIMARY KEY / UNIQUE 必须包含分布键列
注意：FOREIGN KEY 仅声明性，不强制执行
注意：AO 表不支持 UNIQUE 约束
注意：CHECK 约束在每个 Segment 上独立检查
