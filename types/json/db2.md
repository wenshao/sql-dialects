# IBM Db2: JSON Support

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)
> - Db2 supports JSON in multiple ways:
> - 1. BSON storage (Db2 JSON functions, Db2 10.5+)
> - 2. ISO SQL/JSON functions (Db2 11.1+, recommended)
> - 3. JSON stored as VARCHAR/CLOB with SQL/JSON functions
> - JSON column (stored as CLOB or VARCHAR)

```sql
CREATE TABLE events (
    id   BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
    data CLOB(1M),
    PRIMARY KEY (id)
);
```

## Insert JSON

```sql
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
```

## JSON_VALUE (extract scalar value, Db2 11.1+)

```sql
SELECT JSON_VALUE(data, '$.name') FROM events;                 -- 'alice'
SELECT JSON_VALUE(data, '$.age' RETURNING INTEGER) FROM events; -- 25
```

## JSON_QUERY (extract JSON object/array)

```sql
SELECT JSON_QUERY(data, '$.tags') FROM events;                 -- ["vip","new"]
SELECT JSON_QUERY(data, '$.tags[0]') FROM events;              -- "vip"
```

## JSON_EXISTS (check if path exists)

```sql
SELECT * FROM events WHERE JSON_EXISTS(data, '$.name');
SELECT * FROM events WHERE JSON_EXISTS(data, '$.tags[*] ? (@ == "vip")');
```

## JSON_TABLE (shred JSON into relational columns, Db2 11.1+)

```sql
SELECT jt.*
FROM events,
JSON_TABLE(data, '$'
    COLUMNS (
        name VARCHAR(100) PATH '$.name',
        age  INTEGER      PATH '$.age'
    )
) AS jt;
```

## JSON_TABLE with nested arrays

```sql
SELECT jt.*
FROM events,
JSON_TABLE(data, '$'
    COLUMNS (
        name VARCHAR(100) PATH '$.name',
        NESTED PATH '$.tags[*]' COLUMNS (
            tag VARCHAR(50) PATH '$'
        )
    )
) AS jt;
```

## JSON_ARRAY (construct JSON array)

```sql
SELECT JSON_ARRAY(username, email) FROM users;
```

## JSON_OBJECT (construct JSON object)

```sql
SELECT JSON_OBJECT('name': username, 'age': age) FROM users;
```

## JSON_ARRAYAGG (aggregate into JSON array)

```sql
SELECT JSON_ARRAYAGG(username ORDER BY username) FROM users;
```

## JSON_OBJECTAGG (aggregate into JSON object)

```sql
SELECT JSON_OBJECTAGG(username: age) FROM users;
```

## Query conditions

```sql
SELECT * FROM events WHERE JSON_VALUE(data, '$.name') = 'alice';
SELECT * FROM events WHERE JSON_VALUE(data, '$.age' RETURNING INTEGER) > 20;
```

BSON functions (older API)
SELECT SYSTOOLS.BSON_GET(data, 'name') FROM events;
Note: ISO SQL/JSON functions (Db2 11.1+) are the recommended approach
Note: JSON stored as CLOB or VARCHAR (no native JSON type)
Note: JSON_TABLE is very powerful for shredding JSON into relational format
Note: for high-performance JSON, consider pureJSON collection API
