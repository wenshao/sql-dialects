# TDengine: 字符串函数

## TDengine 字符串函数较为有限

CONCAT（拼接）

```sql
SELECT CONCAT(location, '-', CAST(group_id AS NCHAR(10))) FROM meters;
```

## CONCAT_WS（带分隔符拼接）

```sql
SELECT CONCAT_WS(',', location, CAST(group_id AS NCHAR(10))) FROM meters;
```

## LENGTH（字节长度）

```sql
SELECT LENGTH(location) FROM meters;
```

## CHAR_LENGTH（字符长度）

```sql
SELECT CHAR_LENGTH(location) FROM meters;
```

## LOWER / UPPER

```sql
SELECT LOWER(location) FROM meters;
SELECT UPPER(location) FROM meters;
```

## LTRIM / RTRIM / TRIM

```sql
SELECT LTRIM(location) FROM meters;
SELECT RTRIM(location) FROM meters;
SELECT TRIM(location) FROM meters;
```

## SUBSTR（截取）

```sql
SELECT SUBSTR(location, 1, 7) FROM meters;
```

## CAST 类型转换

```sql
SELECT CAST(current AS NCHAR(10)) FROM d1001;
SELECT CAST('10.5' AS FLOAT) FROM d1001;
```

## 不支持的字符串函数


不支持 REPLACE
不支持 REVERSE
不支持 REPEAT
不支持 LPAD / RPAD
不支持 POSITION / LOCATE / INSTR
不支持正则函数（REGEXP_REPLACE 等）
不支持 STRING_AGG / GROUP_CONCAT
注意：TDengine 字符串函数非常有限
注意：复杂字符串处理建议在应用层完成
注意：CONCAT 和 SUBSTR 是最常用的字符串函数
