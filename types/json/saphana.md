# SAP HANA: JSON Support

> 参考资料:
> - [SAP HANA SQL Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/)
> - [SAP HANA SQLScript Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/)


## JSON stored in NCLOB or NVARCHAR columns

SAP HANA 2.0 SPS 04+: dedicated JSON document store

```sql
CREATE COLUMN TABLE events (
    id   BIGINT NOT NULL GENERATED ALWAYS AS IDENTITY,
    data NCLOB,
    PRIMARY KEY (id)
);
```

## Insert JSON

```sql
INSERT INTO events (data) VALUES ('{"name": "alice", "age": 25, "tags": ["vip", "new"]}');
```

## JSON_VALUE (extract scalar value)

```sql
SELECT JSON_VALUE(data, '$.name') FROM events;                    -- 'alice'
SELECT JSON_VALUE(data, '$.age' RETURNING INTEGER) FROM events;   -- 25
```

## JSON_QUERY (extract JSON object/array)

```sql
SELECT JSON_QUERY(data, '$.tags') FROM events;                    -- ["vip","new"]
SELECT JSON_QUERY(data, '$.tags[0]') FROM events;                 -- "vip"
```

JSON_EXISTS
Note: SAP HANA supports JSON path expressions
Basic path checking via JSON_VALUE returning NULL

```sql
SELECT * FROM events WHERE JSON_VALUE(data, '$.name') IS NOT NULL;
```

## JSON_TABLE (shred JSON into relational table)

```sql
SELECT jt.*
FROM events,
JSON_TABLE(data, '$'
    COLUMNS (
        name NVARCHAR(100) PATH '$.name',
        age  INTEGER       PATH '$.age'
    )
) AS jt;
```

## JSON_TABLE with nested arrays

```sql
SELECT jt.*
FROM events,
JSON_TABLE(data, '$'
    COLUMNS (
        name NVARCHAR(100) PATH '$.name',
        NESTED PATH '$.tags[*]' COLUMNS (
            tag NVARCHAR(50) PATH '$'
        )
    )
) AS jt;
```

JSON modification
No native JSON_SET; rebuild JSON or use SQLScript
JSON_MODIFY (SPS 05+)

```sql
SELECT JSON_MODIFY(data, '$.age', '26') FROM events;
```

## Construct JSON

```sql
SELECT '{"name":"' || username || '","age":' || TO_NVARCHAR(age) || '}' FROM users;
```

JSON Document Store (collection-based, SPS 04+)
CREATE COLLECTION my_collection;
INSERT INTO my_collection VALUES ('{"name": "alice", "age": 25}');
SELECT * FROM my_collection WHERE "name" = 'alice';
Query conditions

```sql
SELECT * FROM events WHERE JSON_VALUE(data, '$.name') = 'alice';
SELECT * FROM events WHERE CAST(JSON_VALUE(data, '$.age') AS INTEGER) > 20;
```

JSON aggregation
Build JSON arrays/objects from relational data in SQLScript
Note: JSON is stored in NCLOB columns (no dedicated JSON type)
Note: SAP HANA JSON Document Store provides MongoDB-like collection API
Note: JSON_TABLE is the most powerful function for shredding
Note: column store handles JSON efficiently in memory
Note: HANA XSA/Cloud support JSON natively in application layer
