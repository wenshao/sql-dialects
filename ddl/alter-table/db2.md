# IBM Db2: ALTER TABLE

> 参考资料:
> - [Db2 SQL Reference](https://www.ibm.com/docs/en/db2/11.5?topic=sql)
> - [Db2 Built-in Functions](https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in)
> - Add column

```sql
ALTER TABLE users ADD COLUMN phone VARCHAR(20);
```

## Add column with default

```sql
ALTER TABLE users ADD COLUMN status INTEGER NOT NULL DEFAULT 1;
```

## Modify column type (compatible changes only)

```sql
ALTER TABLE users ALTER COLUMN phone SET DATA TYPE VARCHAR(32);
```

## Rename column (Db2 11.1+)

```sql
ALTER TABLE users RENAME COLUMN phone TO mobile;
```

## Drop column

```sql
ALTER TABLE users DROP COLUMN phone;
```

## Set / drop default

```sql
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;
```

## Set / drop NOT NULL

```sql
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;
```

## Add generated column

```sql
ALTER TABLE users ADD COLUMN full_name VARCHAR(200)
    GENERATED ALWAYS AS (first_name || ' ' || last_name);
```

## Rename table

```sql
RENAME TABLE users TO members;
```

## Add/drop partition (range partitioned table)

```sql
ALTER TABLE sales ADD PARTITION part_2024
    STARTING '2024-01-01' ENDING '2024-12-31';
ALTER TABLE sales DETACH PARTITION part_2020 INTO archive_2020;
ALTER TABLE sales ATTACH PARTITION part_archive
    STARTING '2019-01-01' ENDING '2019-12-31'
    FROM archive_2019;
```

## Change table to append mode (optimize for insert-heavy workloads)

```sql
ALTER TABLE logs APPEND ON;
```

## Activate row and column access control (RCAC)

```sql
ALTER TABLE users ACTIVATE ROW ACCESS CONTROL;
ALTER TABLE users ACTIVATE COLUMN ACCESS CONTROL;
ALTER TABLE users DEACTIVATE ROW ACCESS CONTROL;
```

## Set table compression

```sql
ALTER TABLE users COMPRESS YES;
```

Add table to a different tablespace (requires ADMIN_MOVE_TABLE)
CALL SYSPROC.ADMIN_MOVE_TABLE('SCHEMA','USERS','NEWTBSP','NEWIDXTBSP','NEWLOBTBSP','','','','','','MOVE');
After schema changes, run REORG and RUNSTATS

```sql
REORG TABLE users;
RUNSTATS ON TABLE schema.users WITH DISTRIBUTION AND DETAILED INDEXES ALL;
```
