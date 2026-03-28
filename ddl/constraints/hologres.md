# Hologres: 约束

> 参考资料:
> - [Hologres SQL - CREATE TABLE](https://help.aliyun.com/zh/hologres/user-guide/create-table)
> - [Hologres - Data Types](https://help.aliyun.com/zh/hologres/user-guide/data-types)


## Hologres 兼容 PostgreSQL 语法，支持多种约束

与 BigQuery/Snowflake 不同，Hologres 的约束是强制执行的

## PRIMARY KEY（强制执行）


```sql
CREATE TABLE users (
    id       BIGINT NOT NULL,
    username TEXT NOT NULL,
    PRIMARY KEY (id)
);
```

## 复合主键

```sql
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);
```

## 分区表的主键必须包含分区列

```sql
CREATE TABLE orders (
    id         BIGINT NOT NULL,
    order_date DATE NOT NULL,
    amount     NUMERIC(10,2),
    PRIMARY KEY (id, order_date)
)
PARTITION BY LIST (order_date);
```

## 注意：Hologres 的 PRIMARY KEY 是强制执行的

插入重复主键的数据会报错或被覆盖（取决于配置）

## NOT NULL


```sql
CREATE TABLE users (
    id       BIGINT NOT NULL,
    username TEXT NOT NULL,
    email    TEXT               -- 默认允许 NULL
);
```

## 修改 NOT NULL

```sql
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
```

## DEFAULT


```sql
CREATE TABLE users (
    id         BIGSERIAL PRIMARY KEY,
    status     INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```

## UNIQUE（支持但有限制）


## 行存表支持 UNIQUE 约束

```sql
CREATE TABLE users (
    id       BIGINT NOT NULL,
    email    TEXT UNIQUE,
    PRIMARY KEY (id)
);
CALL set_table_property('users', 'orientation', 'row');
```

## 列存表不支持 UNIQUE 约束（除了 PRIMARY KEY）

## FOREIGN KEY（不支持）


## Hologres 不支持 FOREIGN KEY 约束

需要在应用层保证引用完整性

## CHECK（不支持）


## Hologres 不支持 CHECK 约束

需要在应用层或 ETL 中验证

## 主键冲突处理


## 插入时主键冲突的处理策略

通过表属性设置

```sql
CALL set_table_property('users', 'mutate_type', 'insertorignore');
```

## INSERT ON CONFLICT（PostgreSQL 兼容语法）

```sql
INSERT INTO users (id, username, email) VALUES (1, 'alice', 'alice@example.com')
ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username, email = EXCLUDED.email;

INSERT INTO users (id, username, email) VALUES (1, 'alice', 'alice@example.com')
ON CONFLICT (id) DO NOTHING;
```

## 查看约束


## 兼容 PostgreSQL 查询

```sql
SELECT * FROM information_schema.table_constraints
WHERE table_name = 'users';
```

注意：Hologres 的 PRIMARY KEY 是强制执行的
注意：列存表不支持 UNIQUE（主键除外）
注意：不支持 FOREIGN KEY 和 CHECK
注意：主键冲突处理可以通过 mutate_type 属性配置
注意：兼容 PostgreSQL 的 ON CONFLICT 语法
