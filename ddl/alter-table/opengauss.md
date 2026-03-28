# openGauss/GaussDB: ALTER TABLE

PostgreSQL compatible syntax with openGauss extensions.

> 参考资料:
> - [openGauss SQL Reference](https://docs.opengauss.org/zh/docs/latest/docs/SQLReference/SQL-reference.html)
> - [GaussDB Documentation](https://support.huaweicloud.com/gaussdb/index.html)


## 添加列

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
```

## 添加列（带约束）

```sql
ALTER TABLE users ADD COLUMN status INTEGER NOT NULL DEFAULT 1;
```

## 修改列类型

```sql
ALTER TABLE users ALTER COLUMN phone TYPE VARCHAR(32);
ALTER TABLE users ALTER COLUMN age TYPE TEXT USING age::TEXT;
```

## 重命名列

```sql
ALTER TABLE users RENAME COLUMN phone TO mobile;
```

## 删除列

```sql
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP COLUMN IF EXISTS phone;
```

## 一次多个操作

```sql
ALTER TABLE users
    ADD COLUMN city VARCHAR(64),
    ADD COLUMN country VARCHAR(64),
    DROP COLUMN IF EXISTS phone;
```

## 修改默认值

```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```

## 设置 / 去除 NOT NULL

```sql
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;
```

## 重命名表

```sql
ALTER TABLE users RENAME TO members;
```

## 修改 schema

```sql
ALTER TABLE users SET SCHEMA archive;
```

## 分区管理

添加分区

```sql
ALTER TABLE logs ADD PARTITION p2026 VALUES LESS THAN ('2027-01-01');
```

## 删除分区

```sql
ALTER TABLE logs DROP PARTITION p2023;
```

## 合并分区

```sql
ALTER TABLE logs MERGE PARTITIONS p2023, p2024 INTO PARTITION p_old;
```

## 分裂分区

```sql
ALTER TABLE logs SPLIT PARTITION pmax AT ('2027-01-01') INTO (
    PARTITION p2026,
    PARTITION pmax
);
```

## 修改表存储参数

```sql
ALTER TABLE users SET (FILLFACTOR = 80);
```

修改分布方式（GaussDB 分布式版本）
ALTER TABLE users DISTRIBUTE BY HASH(id);
行存改列存
ALTER TABLE analytics SET (ORIENTATION = COLUMN);
注意事项：
添加带默认值的列是即时的（不重写表）
分区管理语法与 PostgreSQL 有差异（openGauss 使用自己的分区语法）
GaussDB 分布式版本支持在线修改分布方式
