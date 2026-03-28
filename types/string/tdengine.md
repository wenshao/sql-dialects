# TDengine: 字符串类型

> 参考资料:
> - [TDengine SQL Reference](https://docs.taosdata.com/taos-sql/)
> - [TDengine Function Reference](https://docs.taosdata.com/taos-sql/function/)


BINARY(n): 定长二进制字符串，最大 16374 字节
NCHAR(n): Unicode 字符串，最大 4093 个字符（UTF-8，每字符 4 字节）
VARCHAR(n): 3.0+ 别名，等同于 BINARY(n)

```sql
CREATE STABLE devices (
    ts       TIMESTAMP,
    status   BINARY(10),                -- 二进制字符串
    message  NCHAR(200),                -- Unicode 字符串
    info     NCHAR(500)
) TAGS (
    name     NCHAR(64),                 -- 标签也可以是字符串
    location NCHAR(128),
    code     BINARY(20)
);
```

## BINARY vs NCHAR


BINARY: 按字节存储，适合 ASCII 字符和二进制数据
NCHAR: 按 Unicode 字符存储，适合中文等多字节字符
BINARY 存储中文会截断（按字节计算）
NCHAR 存储中文正常（按字符计算）

```sql
INSERT INTO d1001 (ts, status, message) VALUES (NOW, 'OK', '传感器正常');
```

## 字符串限制


BINARY 最大长度：16374 字节
NCHAR 最大长度：4093 个字符
修改列宽度（只能增大，不能减小）

```sql
ALTER STABLE devices MODIFY COLUMN message NCHAR(1000);
```

## 字符串函数


## CONCAT

```sql
SELECT CONCAT(name, '-', location) FROM devices;
```

## LENGTH

```sql
SELECT LENGTH(message) FROM devices;
```

## LOWER / UPPER（3.0+）

```sql
SELECT LOWER(name) FROM devices;
```

## SUBSTR

```sql
SELECT SUBSTR(message, 1, 10) FROM devices;
```

## 不支持的字符串特性


不支持 TEXT / CLOB（使用 NCHAR(n) 替代）
不支持 ENUM 类型
不支持 COLLATION
不支持正则替换函数（仅 MATCH 查询）
注意：NCHAR 适合存储中文等 Unicode 字符
注意：BINARY 适合存储 ASCII 和二进制数据
注意：字符串列宽度只能增大，不能减小
注意：标签列和数据列都支持字符串类型
注意：VARCHAR 在 3.0+ 是 BINARY 的别名
