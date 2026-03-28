# SAP HANA: 复合/复杂类型 (Array, Map, Struct)

> 参考资料:
> - [SAP HANA SQL Reference - ARRAY Data Type](https://help.sap.com/docs/HANA_SERVICE_CF/7c78579ce9b14a669c1f3295b0d8ca16/20a1569875191014b507cf392724b7eb.html)
> - [SAP HANA SQL Reference - JSON Functions](https://help.sap.com/docs/HANA_SERVICE_CF/7c78579ce9b14a669c1f3295b0d8ca16/3918498e41a44cbc9a4f4e5f41b29a23.html)


## ARRAY 类型（SAP HANA 2.0 SPS 02+，仅 SQL Script/过程）


## 注意: ARRAY 主要用于 SQL Script 过程中，不能作为表列类型

SQL Script 中的数组

```sql
DO BEGIN
    DECLARE arr INTEGER ARRAY;
    arr[1] := 10;
    arr[2] := 20;
    arr[3] := 30;
    SELECT CARDINALITY(:arr) AS len FROM DUMMY;
END;
```

## ARRAY_AGG: 聚合为数组

```sql
SELECT department, ARRAY_AGG(name ORDER BY name) AS members
FROM employees
GROUP BY department;
```

## UNNEST: 展开数组

```sql
DO BEGIN
    DECLARE arr VARCHAR(50) ARRAY := ARRAY('admin', 'dev', 'ops');
    SELECT * FROM UNNEST(:arr) AS t(val);
END;
```

## JSON（代替 MAP / STRUCT）


```sql
CREATE TABLE products (
    id         INTEGER PRIMARY KEY,
    name       NVARCHAR(100),
    attributes NCLOB                           -- 存储 JSON
);

INSERT INTO products VALUES (1, 'Laptop',
    '{"brand": "Dell", "specs": {"ram": "16GB", "cpu": "i7"}}');
```

## JSON 函数

```sql
SELECT JSON_VALUE(attributes, '$.brand') FROM products;
SELECT JSON_QUERY(attributes, '$.specs') FROM products;
```

## JSON_TABLE

```sql
SELECT jt.*
FROM products p,
JSON_TABLE(p.attributes, '$'
    COLUMNS (
        brand VARCHAR(50) PATH '$.brand',
        ram   VARCHAR(20) PATH '$.specs.ram'
    )
) AS jt;
```

## 注意事项


## ARRAY 类型只能在 SQL Script（过程/函数）中使用

## 不能作为表列的数据类型

## 没有 MAP / STRUCT 表列类型

## 使用 JSON 字符串存储复杂结构

## JSON_TABLE 提供展开功能
