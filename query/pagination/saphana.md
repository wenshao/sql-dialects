# SAP HANA: Pagination

> 参考资料:
> - [SAP HANA SQL Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/)
> - [SAP HANA SQLScript Reference](https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/)
> - LIMIT / OFFSET

```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;
```

## LIMIT only

```sql
SELECT * FROM users ORDER BY id LIMIT 10;
```

## TOP (alternative syntax)

```sql
SELECT TOP 10 * FROM users ORDER BY id;
```

## SQL standard syntax

```sql
SELECT * FROM users ORDER BY id OFFSET 20 ROWS FETCH FIRST 10 ROWS ONLY;
```

## Window function for pagination

```sql
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (ORDER BY id) AS rn
    FROM users
) t
WHERE rn BETWEEN 21 AND 30;
```

## Top-N per group

```sql
SELECT * FROM (
    SELECT username, city, age,
        ROW_NUMBER() OVER (PARTITION BY city ORDER BY age DESC) AS rn
    FROM users
) t WHERE rn <= 3;
```

## Keyset pagination (cursor-based)

```sql
SELECT * FROM users WHERE id > 100 ORDER BY id LIMIT 10;
```

## BINNING for equal-width buckets (SAP HANA-specific)

```sql
SELECT username, age,
    BINNING(VALUE => age, BIN_COUNT => 10) OVER () AS page
FROM users;
```

## WITH HINT for pagination optimization

```sql
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20
WITH HINT (USE_OLAP_PLAN);
```

Note: SAP HANA supports both LIMIT/OFFSET and FETCH FIRST syntax
Note: for large datasets, keyset pagination avoids scanning skipped rows
Note: in-memory engine makes OFFSET less costly than disk-based systems
