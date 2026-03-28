# ksqlDB: 字符串函数

拼接

```sql
SELECT CONCAT(event_type, ':', event_id) FROM events EMIT CHANGES;
```

## 大小写

```sql
SELECT UCASE(event_type) FROM events EMIT CHANGES;     -- 大写
SELECT LCASE(event_type) FROM events EMIT CHANGES;     -- 小写
```

## 截取

```sql
SELECT SUBSTRING(message, 1, 10) FROM events EMIT CHANGES;
```

## 长度

```sql
SELECT LEN(message) FROM events EMIT CHANGES;
```

## 去空格

```sql
SELECT TRIM(message) FROM events EMIT CHANGES;
```

## 查找

```sql
SELECT INSTR(message, 'error') FROM events EMIT CHANGES;
```

## 替换

```sql
SELECT REPLACE(message, 'error', 'warning') FROM events EMIT CHANGES;
```

## 分割

```sql
SELECT SPLIT(message, ',') FROM events EMIT CHANGES;     -- 返回 ARRAY
```

## LIKE 匹配

```sql
SELECT * FROM events WHERE message LIKE '%error%' EMIT CHANGES;
```

## MASK 系列（数据脱敏）

```sql
SELECT MASK(email) FROM events EMIT CHANGES;              -- 脱敏所有字符
SELECT MASK_LEFT(email, 3) FROM events EMIT CHANGES;      -- 脱敏左侧 3 个字符
SELECT MASK_RIGHT(email, 4) FROM events EMIT CHANGES;     -- 脱敏右侧 4 个字符
SELECT MASK_KEEP_LEFT(email, 3) FROM events EMIT CHANGES; -- 保留左侧 3 个
SELECT MASK_KEEP_RIGHT(email, 4) FROM events EMIT CHANGES;-- 保留右侧 4 个
```

## INITCAP（首字母大写）

```sql
SELECT INITCAP(username) FROM events EMIT CHANGES;
```

## ENCODE / DECODE

```sql
SELECT ENCODE(message, 'base64') FROM events EMIT CHANGES;
```

## CHR / ASCII

```sql
SELECT CHR(65) FROM events EMIT CHANGES;                 -- 'A'
```

注意：ksqlDB 使用 UCASE/LCASE 而非 UPPER/LOWER
注意：使用 LEN 而非 LENGTH
注意：MASK 系列函数用于数据脱敏
注意：不支持 || 拼接运算符
注意：不支持正则函数
