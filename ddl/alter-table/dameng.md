# DamengDB (达梦): ALTER TABLE

Oracle compatible syntax.

> 参考资料:
> - [DamengDB SQL Reference](https://eco.dameng.com/document/dm/zh-cn/sql-dev/index.html)
> - [DamengDB System Admin Manual](https://eco.dameng.com/document/dm/zh-cn/pm/index.html)
> - 添加列

```sql
ALTER TABLE users ADD (phone VARCHAR(20));
ALTER TABLE users ADD (phone VARCHAR(20) DEFAULT 'N/A' NOT NULL);
```

## 添加多列

```sql
ALTER TABLE users ADD (
    city    VARCHAR(64),
    country VARCHAR(64)
);
```

## 修改列类型 / 大小

```sql
ALTER TABLE users MODIFY (phone VARCHAR(32));
ALTER TABLE users MODIFY (phone VARCHAR(32) NOT NULL);
```

## 多列一起修改

```sql
ALTER TABLE users MODIFY (
    phone VARCHAR(32) NOT NULL,
    email VARCHAR(320)
);
```

## 重命名列

```sql
ALTER TABLE users RENAME COLUMN phone TO mobile;
```

## 删除列

```sql
ALTER TABLE users DROP COLUMN phone;
ALTER TABLE users DROP (phone, city);  -- 一次删除多列
```

## 标记列为未使用（大表删列更快）

```sql
ALTER TABLE users SET UNUSED COLUMN phone;
ALTER TABLE users DROP UNUSED COLUMNS;
```

## 修改默认值

```sql
ALTER TABLE users MODIFY (status INT DEFAULT 0);
```

## 重命名表

```sql
ALTER TABLE users RENAME TO members;
```

## 只读表

```sql
ALTER TABLE users READ ONLY;
ALTER TABLE users READ WRITE;
```

## 分区管理

添加分区

```sql
ALTER TABLE logs ADD PARTITION p2026 VALUES LESS THAN (DATE '2027-01-01');
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
ALTER TABLE logs SPLIT PARTITION pmax AT (DATE '2027-01-01') INTO (
    PARTITION p2026,
    PARTITION pmax
);
```

## 交换分区

```sql
ALTER TABLE logs EXCHANGE PARTITION p2023 WITH TABLE logs_2023_archive;
```

注意事项：
语法与 Oracle 高度兼容
添加带默认值的 NOT NULL 列是即时操作
支持 SET UNUSED 延迟删除列
支持分区表的在线维护操作
