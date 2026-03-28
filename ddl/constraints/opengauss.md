# openGauss/GaussDB: 约束

PostgreSQL compatible syntax.

> 参考资料:
> - [openGauss SQL Reference](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html)
> - [GaussDB Documentation](https://support.huaweicloud.com/gaussdb/index.html)
> - PRIMARY KEY

```sql
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY
);
CREATE TABLE order_items (
    order_id BIGINT NOT NULL,
    item_id  BIGINT NOT NULL,
    PRIMARY KEY (order_id, item_id)
);
```

## UNIQUE

```sql
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
```

## FOREIGN KEY

```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    ON DELETE CASCADE
    ON UPDATE CASCADE;
```

## NOT NULL

```sql
ALTER TABLE users ALTER COLUMN email SET NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
```

## DEFAULT

```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 1;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```

## CHECK

```sql
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0 AND age <= 200);
ALTER TABLE events ADD CONSTRAINT chk_dates CHECK (end_date > start_date);
```

## 可延迟约束（事务提交时再校验）

```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
    FOREIGN KEY (user_id) REFERENCES users (id)
    DEFERRABLE INITIALLY DEFERRED;
```

## 删除约束

```sql
ALTER TABLE users DROP CONSTRAINT uk_email;
ALTER TABLE users DROP CONSTRAINT IF EXISTS uk_email;
```

## NOT VALID（添加约束时不校验已有数据，之后再验证）

```sql
ALTER TABLE users ADD CONSTRAINT chk_age CHECK (age >= 0) NOT VALID;
ALTER TABLE users VALIDATE CONSTRAINT chk_age;
```

## 查看约束

```sql
SELECT * FROM information_schema.table_constraints
WHERE table_name = 'users';
SELECT conname, contype, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'users'::regclass;
```

注意事项：
列存储表不支持主键和唯一约束
GaussDB 分布式版本中外键约束跨 DN 有限制
支持可延迟约束
支持 NOT VALID 添加约束后延迟验证
