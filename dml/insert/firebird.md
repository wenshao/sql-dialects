# Firebird: INSERT

> 参考资料:
> - [Firebird SQL Reference](https://firebirdsql.org/en/reference-manuals/)
> - [Firebird Release Notes](https://firebirdsql.org/file/documentation/release_notes/html/en/4_0/rlsnotes40.html)


## Single row insert

```sql
INSERT INTO users (username, email, age) VALUES ('alice', 'alice@example.com', 25);
```

## Multiple rows (Firebird does not support multi-row VALUES)

Use INSERT ... SELECT with UNION ALL

```sql
INSERT INTO users (username, email, age)
SELECT 'alice', 'alice@example.com', 25 FROM RDB$DATABASE
UNION ALL
SELECT 'bob', 'bob@example.com', 30 FROM RDB$DATABASE
UNION ALL
SELECT 'charlie', 'charlie@example.com', 35 FROM RDB$DATABASE;
```

## Insert from query

```sql
INSERT INTO users_archive (username, email, age)
SELECT username, email, age FROM users WHERE age > 60;
```

## RETURNING (2.1+, returns inserted values)

```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
RETURNING id, username;
```

## RETURNING * (all columns)

```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', 25)
RETURNING *;
```

## Default values

```sql
INSERT INTO users (username, email, age)
VALUES ('alice', 'alice@example.com', DEFAULT);
```

## Insert with generator (sequence) for pre-3.0

```sql
INSERT INTO users (id, username, email)
VALUES (GEN_ID(gen_users_id, 1), 'alice', 'alice@example.com');
```

## Insert with NEXT VALUE FOR (3.0+)

```sql
INSERT INTO users (id, username, email)
VALUES (NEXT VALUE FOR seq_users, 'alice', 'alice@example.com');
```

## INSERT OR UPDATE (Firebird's upsert, based on PK/UNIQUE match)

See upsert module for details

```sql
UPDATE OR INSERT INTO users (id, username, email)
VALUES (1, 'alice', 'alice_new@example.com')
MATCHING (id);
```

## EXECUTE BLOCK for batch inserts (anonymous PL/SQL-like block)

```sql
SET TERM !! ;
EXECUTE BLOCK
AS
    DECLARE i INTEGER = 1;
BEGIN
    WHILE (i <= 100) DO
    BEGIN
        INSERT INTO users (username, email, age)
        VALUES ('user' || :i, 'user' || :i || '@example.com', 20 + MOD(:i, 50));
        i = i + 1;
    END
END!!
SET TERM ; !!
```

## Note: RDB$DATABASE is the single-row system table (like DUAL in Oracle)

Note: RETURNING is supported on INSERT, UPDATE, DELETE, and MERGE (3.0+)
