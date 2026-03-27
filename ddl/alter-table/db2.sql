-- IBM Db2: ALTER TABLE
--
-- 参考资料:
--   [1] Db2 SQL Reference
--       https://www.ibm.com/docs/en/db2/11.5?topic=sql
--   [2] Db2 Built-in Functions
--       https://www.ibm.com/docs/en/db2/11.5?topic=functions-built-in

-- Add column
ALTER TABLE users ADD COLUMN phone VARCHAR(20);

-- Add column with default
ALTER TABLE users ADD COLUMN status INTEGER NOT NULL DEFAULT 1;

-- Modify column type (compatible changes only)
ALTER TABLE users ALTER COLUMN phone SET DATA TYPE VARCHAR(32);

-- Rename column (Db2 11.1+)
ALTER TABLE users RENAME COLUMN phone TO mobile;

-- Drop column
ALTER TABLE users DROP COLUMN phone;

-- Set / drop default
ALTER TABLE users ALTER COLUMN status SET DEFAULT 0;
ALTER TABLE users ALTER COLUMN status DROP DEFAULT;

-- Set / drop NOT NULL
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

-- Add generated column
ALTER TABLE users ADD COLUMN full_name VARCHAR(200)
    GENERATED ALWAYS AS (first_name || ' ' || last_name);

-- Rename table
RENAME TABLE users TO members;

-- Add/drop partition (range partitioned table)
ALTER TABLE sales ADD PARTITION part_2024
    STARTING '2024-01-01' ENDING '2024-12-31';
ALTER TABLE sales DETACH PARTITION part_2020 INTO archive_2020;
ALTER TABLE sales ATTACH PARTITION part_archive
    STARTING '2019-01-01' ENDING '2019-12-31'
    FROM archive_2019;

-- Change table to append mode (optimize for insert-heavy workloads)
ALTER TABLE logs APPEND ON;

-- Activate row and column access control (RCAC)
ALTER TABLE users ACTIVATE ROW ACCESS CONTROL;
ALTER TABLE users ACTIVATE COLUMN ACCESS CONTROL;
ALTER TABLE users DEACTIVATE ROW ACCESS CONTROL;

-- Set table compression
ALTER TABLE users COMPRESS YES;

-- Add table to a different tablespace (requires ADMIN_MOVE_TABLE)
-- CALL SYSPROC.ADMIN_MOVE_TABLE('SCHEMA','USERS','NEWTBSP','NEWIDXTBSP','NEWLOBTBSP','','','','','','MOVE');

-- After schema changes, run REORG and RUNSTATS
REORG TABLE users;
RUNSTATS ON TABLE schema.users WITH DISTRIBUTION AND DETAILED INDEXES ALL;
