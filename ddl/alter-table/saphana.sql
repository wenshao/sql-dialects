-- SAP HANA: ALTER TABLE
--
-- 参考资料:
--   [1] SAP HANA SQL Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/4fe29514fd584807ac9f2a04f6754767/
--   [2] SAP HANA SQLScript Reference
--       https://help.sap.com/docs/SAP_HANA_PLATFORM/de2486ee947e43e684d39702027f8a94/

-- Add column
ALTER TABLE users ADD (phone NVARCHAR(20));

-- Add multiple columns
ALTER TABLE users ADD (
    city    NVARCHAR(64),
    country NVARCHAR(64)
);

-- Drop column
ALTER TABLE users DROP (phone);

-- Drop multiple columns
ALTER TABLE users DROP (city, country);

-- Modify column type
ALTER TABLE users ALTER (phone NVARCHAR(32));

-- Rename column
RENAME COLUMN users.phone TO mobile;

-- Set / drop default
ALTER TABLE users ALTER (status INTEGER DEFAULT 0);
ALTER TABLE users ALTER (status INTEGER DEFAULT NULL);

-- Set / drop NOT NULL
ALTER TABLE users ALTER (phone NVARCHAR(20) NOT NULL);
ALTER TABLE users ALTER (phone NVARCHAR(20) NULL);

-- Rename table
RENAME TABLE users TO members;

-- Move between schemas
ALTER TABLE users MOVE TO new_schema;

-- Change store type (ROW <-> COLUMN)
-- Note: requires recreating internally; data preserved
-- Only possible via migration procedures or CTAS

-- Add/modify partitioning
ALTER TABLE events PARTITION BY RANGE (event_date) (
    PARTITION '2023-01-01' <= VALUES < '2024-01-01',
    PARTITION '2024-01-01' <= VALUES < '2025-01-01',
    PARTITION OTHERS
);

ALTER TABLE events ADD PARTITION
    '2025-01-01' <= VALUES < '2026-01-01';

ALTER TABLE events DROP PARTITION
    VALUES = '2023-01-01';

-- Merge partitions
ALTER TABLE events MERGE PARTITIONS 1, 2 INTO PARTITION
    '2023-01-01' <= VALUES < '2025-01-01';

-- Enable/disable delta merge (column store)
ALTER TABLE users DISABLE AUTOMERGE;
ALTER TABLE users ENABLE AUTOMERGE;
MERGE DELTA OF users;

-- Add system versioning
ALTER TABLE employees ADD (
    valid_from TIMESTAMP GENERATED ALWAYS AS ROW START,
    valid_to   TIMESTAMP GENERATED ALWAYS AS ROW END,
    PERIOD FOR SYSTEM_TIME (valid_from, valid_to)
);
ALTER TABLE employees ADD SYSTEM VERSIONING;

-- Preload table into memory
ALTER TABLE users PRELOAD ALL;
ALTER TABLE users PRELOAD NONE;

-- Set table to unloaded (release memory)
ALTER TABLE users UNLOAD;
