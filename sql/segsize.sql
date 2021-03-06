SET HEA ON LIN 500 PAGES 100 TAB OFF FEED OFF ECHO OFF VER OFF TRIMS ON TRIM ON TI OFF TIMI OFF;

COL owner FOR A30;
SELECT username owner
  FROM dba_users
 WHERE oracle_maintained = 'N'
 ORDER BY 1
/

PRO
PRO 1. Enter OWNER (required)
DEF owner = '&1.';

COL table_name FOR A30;
SELECT table_name
  FROM dba_tables
 WHERE owner = UPPER('&&owner.')
 ORDER BY 1
/

PRO
PRO 2. Enter TABLE_NAME (required)
DEF table_name = '&2.';
PRO

COL size_mb FOR 999,990;
COL optimal_mb FOR 999,999,990;
COL type FOR A10;
COl owner FOR A30;
COL schema_object FOR A30;
BRE ON owner SKIP 1 ON type SKIP 1;
COMP SUM LAB 'TOTAL' OF size_mb ON owner;

COL current_time NEW_V current_time FOR A15;
SELECT 'current_time: ' x, TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS') current_time FROM DUAL;
COL x_host_name NEW_V x_host_name;
SELECT host_name x_host_name FROM v$instance;
COL x_db_name NEW_V x_db_name;
SELECT name x_db_name FROM v$database;
COL x_container NEW_V x_container;
SELECT 'NONE' x_container FROM DUAL;
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') x_container FROM DUAL;

SPO segsize_&&owner..&&table_name._&&current_time..txt;
PRO OWNER: &&owner.
PRO TABLE: &&table_name.
PRO DATABASE: &&x_db_name.
PRO PDB: &&x_container.
PRO HOST: &&x_host_name.

PRO
PRO dba_segments
PRO ~~~~~~~~~~~~
COL segment_name FOR A30;
WITH 
tables AS (
SELECT 'TABLE' seg_type, owner, table_name name
  FROM dba_tables
 WHERE owner = UPPER('&&owner.')
   AND table_name = UPPER('&&table_name.')
),
indexes AS (
SELECT 'INDEX' seg_type, i.owner, i.index_name name
  FROM dba_indexes i, tables t
 WHERE i.table_owner = t.owner
   AND i.table_name = t.name
),
lobs AS (
SELECT 'LOBSEGMENT' seg_type, l.owner, l.segment_name name
  FROM dba_lobs l, tables t
 WHERE l.owner = t.owner
   AND l.table_name = t.name
),
objects AS (
SELECT * FROM tables
UNION ALL
SELECT * FROM indexes
UNION ALL
SELECT * FROM lobs
)
SELECT s.owner,
       s.segment_type type,
       ROUND(s.bytes/POWER(2,20)) size_mb,
       s.segment_name,
       s.tablespace_name
  FROM dba_segments s, objects o
 WHERE s.owner = o.owner
   AND s.segment_name = o.name
   AND s.segment_type = o.seg_type
 ORDER BY 
       s.owner,
       CASE s.segment_type
         WHEN 'TABLE' THEN 1 
         WHEN 'INDEX' THEN 2
         WHEN 'LOBSEGMENT' THEN 3
         ELSE 4 
       END,
       s.segment_type,
       s.bytes DESC NULLS LAST,
       s.segment_name,
       s.partition_name
/

PRO
PRO dba_tab|ind_statistics
PRO ~~~~~~~~~~~~~~~~~~~~~~

WITH 
block AS (
SELECT TO_NUMBER(value) bsize FROM v$parameter WHERE name = 'db_block_size'
),
tables AS (
SELECT owner, table_name, tablespace_name
  FROM dba_tables
 WHERE owner = UPPER('&&owner.')
   AND table_name = UPPER('&&table_name.')
),
both AS (
SELECT s.owner,
       s.object_type,
       ROUND(s.blocks*block.bsize/POWER(2,20)) size_mb,
       s.table_name schema_object,
       t.tablespace_name,
       s.num_rows,
       s.avg_row_len
  FROM dba_tab_statistics s, tables t, block
 WHERE s.owner = t.owner
   AND s.table_name = t.table_name
 UNION ALL
SELECT s.owner,
       s.object_type,
       ROUND(s.leaf_blocks*block.bsize/POWER(2,20)) size_mb,
       s.index_name schema_object,
       t.tablespace_name,
       TO_NUMBER(NULL) num_rows,
       TO_NUMBER(NULL) avg_row_len
  FROM dba_ind_statistics s, tables t, block
 WHERE s.owner = t.owner
   AND s.table_name = t.table_name
)
SELECT owner,
       object_type type,
       size_mb,
       schema_object,
       tablespace_name,
       num_rows,
       avg_row_len,
       ROUND(num_rows*avg_row_len/POWER(2,20)) optimal_mb
  FROM both
 ORDER BY 
       owner,
       CASE type
         WHEN 'TABLE' THEN 1 
         WHEN 'INDEX' THEN 2
         ELSE 4 
       END,
       object_type,
       size_mb DESC,
       schema_object
/

SPO OFF;
CL BRE COMP;
UNDEF 1 2;