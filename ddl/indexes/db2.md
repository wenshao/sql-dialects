# IBM Db2: Indexes

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)


## Basic index

```sql
CREATE INDEX idx_age ON users (age);
```

## Unique index

```sql
CREATE UNIQUE INDEX uk_email ON users (email);
```

## Composite index

```sql
CREATE INDEX idx_city_age ON users (city, age);
```

## Descending index

```sql
CREATE INDEX idx_age_desc ON users (age DESC);
```

## Include columns (index-only access)

```sql
CREATE INDEX idx_username ON users (username) INCLUDE (email, age);
```

## Clustered index (data physically ordered)

```sql
CREATE INDEX idx_created ON users (created_at) CLUSTER;
```

## Expression-based index (Db2 11.1+)

```sql
CREATE INDEX idx_lower_email ON users (LOWER(email));
```

Partial index (filtered, Db2 11.1+)
Note: Db2 doesn't have partial indexes like PostgreSQL
Use MQTs or design indexes for specific query patterns
Unique where not null

```sql
CREATE UNIQUE INDEX uk_phone ON users (phone) EXCLUDE NULL KEYS;
```

## XML index (for XML column)

```sql
CREATE INDEX idx_xml_name ON xml_docs (doc)
    GENERATE KEY USING XMLPATTERN '/customer/name' AS SQL VARCHAR(100);
```

## Index on partitioned table (partitioned index)

```sql
CREATE INDEX idx_sale_date ON sales (sale_date) PARTITIONED;
```

## Non-partitioned index on partitioned table

```sql
CREATE INDEX idx_sale_amount ON sales (amount) NOT PARTITIONED;
```

## Spatial index (Db2 Spatial Extender)

```sql
CREATE INDEX idx_location ON places (location)
    EXTEND USING db2gse.spatial_index (0.5, 10, 20);
```

## Drop index

```sql
DROP INDEX idx_age;
```

## Rebuild / reorganize indexes

```sql
REORG INDEXES ALL FOR TABLE users;
```

## Collect index statistics

```sql
RUNSTATS ON TABLE schema.users FOR INDEXES ALL;
RUNSTATS ON TABLE schema.users WITH DISTRIBUTION AND DETAILED INDEXES ALL;
```

## View indexes

```sql
SELECT * FROM SYSCAT.INDEXES WHERE TABNAME = 'USERS';
SELECT * FROM SYSCAT.INDEXCOLUSE WHERE INDNAME = 'IDX_AGE';
```

## Design advisor (suggest indexes)

db2advis -d mydb -s "SELECT * FROM users WHERE age > 25"
