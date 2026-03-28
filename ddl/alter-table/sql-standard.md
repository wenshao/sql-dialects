# SQL 标准: ALTER TABLE

> 参考资料:
> - [ISO/IEC 9075 SQL Standard](https://www.iso.org/standard/76583.html)
> - [Modern SQL - by Markus Winand](https://modern-sql.com/)
> - [Modern SQL - ALTER TABLE](https://modern-sql.com/feature/alter-table)

## SQL-86 (SQL-1): 最初的标准

没有 ALTER TABLE 语句

## SQL-89 (SQL-1, 修正版)

没有 ALTER TABLE 语句

## SQL-92 (SQL2): 首次引入 ALTER TABLE

新增 ADD COLUMN、DROP COLUMN
新增 ADD CONSTRAINT、DROP CONSTRAINT

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
ALTER TABLE users DROP COLUMN phone CASCADE;
ALTER TABLE users DROP COLUMN phone RESTRICT;
```

```sql
ALTER TABLE users ADD CONSTRAINT uk_email UNIQUE (email);
ALTER TABLE users DROP CONSTRAINT uk_email;
```

修改默认值
```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```

## SQL:1999 (SQL3): 增强

增强了 ALTER TABLE 的能力

修改列类型（使用 ALTER COLUMN ... SET DATA TYPE）
```sql
ALTER TABLE users ALTER COLUMN phone SET DATA TYPE VARCHAR(32);
```

## SQL:2003: 自增列相关

新增对 IDENTITY 列的修改

```sql
ALTER TABLE users ALTER COLUMN id SET GENERATED ALWAYS AS IDENTITY;
ALTER TABLE users ALTER COLUMN id RESTART WITH 1000;
```

## SQL:2011: 时态表

新增系统版本化的 ALTER

```sql
ALTER TABLE users ADD PERIOD FOR SYSTEM_TIME (valid_from, valid_to);
ALTER TABLE users ADD SYSTEM VERSIONING;
ALTER TABLE users DROP SYSTEM VERSIONING;
```

## SQL:2016: 增强

NOT NULL 修改
```sql
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;
```

## 标准中定义但各实现支持不一的功能

SET DATA TYPE: PostgreSQL 用 TYPE，MySQL 用 MODIFY COLUMN
DROP COLUMN CASCADE/RESTRICT: 标准要求指定，大多数实现默认 RESTRICT
RENAME TABLE/COLUMN: 标准中未定义，属于各数据库的扩展

- **注意：没有数据库完全遵循 ALTER TABLE 标准**
- **注意：RENAME COLUMN 直到各实现自行扩展才被广泛支持**
- **注意：大多数实际使用的 ALTER TABLE 功能是实现特有的扩展**
