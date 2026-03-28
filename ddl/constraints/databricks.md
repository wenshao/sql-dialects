# Databricks SQL: 约束

> 参考资料:
> - [Databricks SQL Language Reference](https://docs.databricks.com/en/sql/language-manual/index.html)
> - [Databricks SQL - Built-in Functions](https://docs.databricks.com/en/sql/language-manual/sql-ref-functions-builtin.html)
> - [Delta Lake Documentation](https://docs.delta.io/latest/index.html)


Databricks SQL 支持两类约束：
1. CHECK 约束（强制执行）
2. 信息性约束：PRIMARY KEY、FOREIGN KEY、UNIQUE（不强制执行）

## NOT NULL（强制执行）


```sql
CREATE TABLE users (
    id       BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
    username STRING NOT NULL,
    email    STRING                          -- 默认允许 NULL
);

ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
```


## DEFAULT


```sql
CREATE TABLE users (
    id         BIGINT GENERATED ALWAYS AS IDENTITY,
    status     INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT current_timestamp()
);

ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```


## CHECK 约束（强制执行！）

Delta Lake 会在写入时验证 CHECK 约束

内联 CHECK
```sql
CREATE TABLE users (
    id       BIGINT GENERATED ALWAYS AS IDENTITY,
    age      INT,
    status   INT,
    CONSTRAINT chk_age CHECK (age > 0 AND age < 200),
    CONSTRAINT chk_status CHECK (status IN (0, 1, 2))
);
```


ALTER TABLE 添加 CHECK
```sql
ALTER TABLE users ADD CONSTRAINT chk_email_format
    CHECK (email LIKE '%@%.%');
ALTER TABLE orders ADD CONSTRAINT chk_positive_amount
    CHECK (amount >= 0);
```


删除 CHECK 约束
```sql
ALTER TABLE users DROP CONSTRAINT chk_email_format;
```


CHECK 约束验证示例：
INSERT INTO users (username, age) VALUES ('test', -1);
会报错：CHECK constraint chk_age violated

## PRIMARY KEY（信息性，不强制执行）


```sql
CREATE TABLE users (
    id       BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
    username STRING NOT NULL,
    CONSTRAINT pk_users PRIMARY KEY (id)
);

ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (id);
```


复合主键
```sql
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    CONSTRAINT pk_order_items PRIMARY KEY (order_id, item_id)
);
```


## FOREIGN KEY（信息性，不强制执行）


```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id);
```


复合外键
```sql
ALTER TABLE order_items ADD CONSTRAINT fk_items_order
    FOREIGN KEY (order_id) REFERENCES orders (id);
```


## UNIQUE（信息性，不强制执行）


```sql
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
ALTER TABLE users ADD CONSTRAINT uk_username UNIQUE (username);
```


## GENERATED ALWAYS AS（计算列约束）


```sql
CREATE TABLE orders (
    quantity   INT,
    unit_price DECIMAL(10, 2),
    total      DECIMAL(10, 2) GENERATED ALWAYS AS (quantity * unit_price),
    order_year INT GENERATED ALWAYS AS (YEAR(order_date)),
    order_date DATE
);
```


## 删除约束


```sql
ALTER TABLE users DROP CONSTRAINT pk_users;
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE orders DROP CONSTRAINT fk_orders_user;
ALTER TABLE users DROP CONSTRAINT chk_age;
```


## 查看约束


```sql
DESCRIBE EXTENDED users;
SHOW TBLPROPERTIES users;
```


查看表的约束信息
```sql
SELECT * FROM information_schema.table_constraints
WHERE table_name = 'users';
```


查看 CHECK 约束详情
```sql
SELECT * FROM information_schema.check_constraints
WHERE constraint_schema = 'default';
```


## 信息性约束的作用

PK/FK/UNIQUE 虽然不强制执行，但用于：
1. 查询优化器生成更好的执行计划
2. BI 工具（如 Power BI、Tableau）自动检测表关系
3. 数据文档化

## 数据质量保障


Delta Lake 的 Expectations（数据质量规则）
在 DLT 管道中使用：
@dlt.expect("valid_age", "age > 0 AND age < 200")
@dlt.expect_or_drop("has_email", "email IS NOT NULL")
@dlt.expect_or_fail("unique_id", "id IS NOT NULL")

SQL 方式验证数据
```sql
SELECT COUNT(*) AS duplicates
FROM (SELECT id, COUNT(*) FROM users GROUP BY id HAVING COUNT(*) > 1);
```


注意：CHECK 约束是强制执行的，违反时写入会失败
注意：PK、FK、UNIQUE 是信息性的，不强制执行
注意：GENERATED ALWAYS AS 列不能手动写入
注意：Unity Catalog 提供额外的数据治理能力
注意：DLT（Delta Live Tables）提供管道级数据质量规则
