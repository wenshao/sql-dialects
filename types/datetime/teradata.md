# Teradata: Date/Time Types

> 参考资料:
> - [Teradata SQL Reference](https://docs.teradata.com/r/Teradata-VantageTM-SQL-Functions-Expressions-and-Predicates)
> - [Teradata Database Documentation](https://docs.teradata.com/)


DATE: 4 bytes, integer internally (YYYYMMDD - 19000000)
TIME: time of day, optional precision TIME(n), 0-6 fractional seconds
TIMESTAMP: date + time, optional precision TIMESTAMP(n)
TIME WITH TIME ZONE: time with zone offset
TIMESTAMP WITH TIME ZONE: timestamp with zone offset

```sql
CREATE TABLE events (
    id         INTEGER NOT NULL,
    event_date DATE,
    event_time TIME(0),               -- no fractional seconds
    created_at TIMESTAMP(6),          -- microsecond precision
    tz_stamp   TIMESTAMP(0) WITH TIME ZONE
)
PRIMARY INDEX (id);
```


INTERVAL types (Teradata supports rich interval types)
INTERVAL YEAR, INTERVAL MONTH, INTERVAL YEAR TO MONTH
INTERVAL DAY, INTERVAL HOUR, INTERVAL MINUTE, INTERVAL SECOND
INTERVAL DAY TO HOUR, INTERVAL DAY TO MINUTE, INTERVAL DAY TO SECOND
INTERVAL HOUR TO MINUTE, INTERVAL HOUR TO SECOND, INTERVAL MINUTE TO SECOND
```sql
CREATE TABLE durations (
    rental_period INTERVAL DAY(3) TO SECOND(0),
    age_range     INTERVAL YEAR(2) TO MONTH
);
```


PERIOD types (Teradata-specific: temporal period)
PERIOD(DATE): range of dates
PERIOD(TIME): range of times
PERIOD(TIMESTAMP): range of timestamps
```sql
CREATE TABLE contracts (
    contract_id  INTEGER,
    valid_period PERIOD(DATE),
    active_time  PERIOD(TIMESTAMP(0))
)
PRIMARY INDEX (contract_id);
```


Insert with PERIOD
```sql
INSERT INTO contracts VALUES (1, PERIOD(DATE '2024-01-01', DATE '2024-12-31'), NULL);
```


Current date/time
```sql
SELECT CURRENT_DATE;                 -- DATE
SELECT CURRENT_TIME;                 -- TIME WITH TIME ZONE
SELECT CURRENT_TIMESTAMP;            -- TIMESTAMP WITH TIME ZONE
SELECT CURRENT_TIMESTAMP(0);         -- truncated to seconds
```


Date arithmetic
```sql
SELECT CURRENT_DATE + INTERVAL '1' DAY;
SELECT CURRENT_DATE - INTERVAL '3' MONTH;
SELECT CURRENT_TIMESTAMP + INTERVAL '2' HOUR;
SELECT (DATE '2024-12-31') - (DATE '2024-01-01');  -- returns INTERVAL
```


EXTRACT
```sql
SELECT EXTRACT(YEAR FROM CURRENT_DATE);
SELECT EXTRACT(MONTH FROM CURRENT_DATE);
SELECT EXTRACT(DAY FROM CURRENT_DATE);
SELECT EXTRACT(HOUR FROM CURRENT_TIMESTAMP);
```


FORMAT (Teradata-specific date formatting)
```sql
SELECT CURRENT_DATE (FORMAT 'YYYY-MM-DD');
SELECT CURRENT_TIMESTAMP (FORMAT 'YYYY-MM-DDBHH:MI:SS');
```


PERIOD operations
```sql
SELECT * FROM contracts WHERE PERIOD(DATE '2024-06-01', DATE '2024-06-30') OVERLAPS valid_period;
SELECT BEGIN(valid_period), END(valid_period) FROM contracts;
```


Note: DATE is internally an integer (YYYYMMDD - 19000000)
Note: PERIOD types are unique to Teradata
Note: NORMALIZE merges overlapping periods
Note: no INTERVAL LITERAL shorthand; use INTERVAL 'n' UNIT syntax
