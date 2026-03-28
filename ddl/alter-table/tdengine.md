# TDengine: ALTER TABLE

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)


## 修改超级表（STable）


## 添加列（数据列）

```sql
ALTER STABLE meters ADD COLUMN power FLOAT;
```

## 删除列

```sql
ALTER STABLE meters DROP COLUMN power;
```

## 修改列宽度（仅 NCHAR/BINARY，只能增大）

```sql
ALTER STABLE sensors MODIFY COLUMN info NCHAR(500);
```

## 添加标签（TAG）

```sql
ALTER STABLE meters ADD TAG region NCHAR(32);
```

## 删除标签

```sql
ALTER STABLE meters DROP TAG region;
```

## 修改标签名

```sql
ALTER STABLE meters RENAME TAG location TO site;
```

## 修改标签列宽度（仅 NCHAR/BINARY）

```sql
ALTER STABLE meters MODIFY TAG location NCHAR(128);
```

## 修改子表


## 修改子表标签值

```sql
ALTER TABLE d1001 SET TAG location = 'Beijing.Dongcheng';
ALTER TABLE d1001 SET TAG group_id = 5;
```

## 修改普通表


## 添加列

```sql
ALTER TABLE log ADD COLUMN source NCHAR(64);
```

## 删除列

```sql
ALTER TABLE log DROP COLUMN source;
```

## 修改列宽度

```sql
ALTER TABLE log MODIFY COLUMN content NCHAR(500);
```

## 修改数据库


## 修改数据保留时间

```sql
ALTER DATABASE power KEEP 730;
```

## 修改缓存大小

```sql
ALTER DATABASE power BLOCKS 8;
```

注意：不支持修改列类型（只能修改 NCHAR/BINARY 的宽度）
注意：不支持重命名表
注意：不支持重命名列（只能重命名标签）
注意：第一列（TIMESTAMP）不能删除或修改
注意：标签值通过 SET TAG 修改，而非 UPDATE
