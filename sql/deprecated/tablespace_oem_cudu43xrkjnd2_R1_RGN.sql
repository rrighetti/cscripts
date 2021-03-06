SELECT
        /*+ first_rows */
        pdb.name                                ,
        ts.tablespace_name                      ,
        NVL(t.bytes/1024/1024,0) allocated_space,
        NVL(DECODE(un.bytes,NULL,DECODE(ts.contents,'TEMPORARY', DECODE(ts.extent_management,'LOCAL',u.bytes,t.bytes - NVL(u.bytes, 0)), t.bytes - NVL(u.bytes, 0)), un.bytes)/1024/1024,0) used_space
FROM    cdb_tablespaces ts,
        v$containers pdb  ,
        (
                SELECT  con_id         ,
                        tablespace_name,
                        SUM(bytes) bytes
                FROM    cdb_free_space
                GROUP BY con_id,
                        tablespace_name
                UNION ALL
                SELECT  con_id         ,
                        tablespace_name,
                        NVL(SUM(bytes_used), 0)
                FROM    gv$temp_extent_pool
                GROUP BY con_id,
                        tablespace_name
        )
        u,
        (
                SELECT  con_id         ,
                        tablespace_name,
                        SUM(NVL(bytes, 0)) bytes
                FROM    cdb_data_files
                GROUP BY con_id,
                        tablespace_name
                UNION ALL
                SELECT  con_id         ,
                        tablespace_name,
                        SUM(NVL(bytes, 0)) bytes
                FROM    cdb_temp_files
                GROUP BY con_id,
                        tablespace_name
        )
        t,
        (
                SELECT  ts.con_id         ,
                        ts.tablespace_name,
                        NVL(um.used_space*ts.block_size, 0) bytes
                FROM    cdb_tablespaces ts,
                        cdb_tablespace_usage_metrics um
                WHERE   ts.tablespace_name = um.tablespace_name(+)
                        AND ts.con_id      = um.con_id(+)
                        AND ts.contents    ='UNDO'
        )
        un
WHERE   ts.tablespace_name     = t.tablespace_name(+)
        AND ts.tablespace_name = u.tablespace_name(+)
        AND ts.tablespace_name = un.tablespace_name(+)
        AND ts.con_id          = pdb.con_id
        AND ts.con_id          = u.con_id(+)
        AND ts.con_id          = t.con_id(+)
        AND ts.con_id          = un.con_id(+)
ORDER BY 1,2
/

*****************************************************************************************

WITH
t AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       con_id,
       tablespace_name,
       SUM(NVL(bytes, 0)) bytes
  FROM cdb_data_files
 GROUP BY 
       con_id,
       tablespace_name
 UNION ALL
SELECT /*+ MATERIALIZE NO_MERGE */
       con_id,
       tablespace_name,
       SUM(NVL(bytes, 0)) bytes
  FROM cdb_temp_files
 GROUP BY 
       con_id,
       tablespace_name
),
u AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       con_id,
       tablespace_name,
       SUM(bytes) bytes
  FROM cdb_free_space
 GROUP BY 
        con_id,
        tablespace_name
 UNION ALL
SELECT /*+ MATERIALIZE NO_MERGE */
       con_id,
       tablespace_name,
       NVL(SUM(bytes_used), 0) bytes
  FROM gv$temp_extent_pool
 GROUP BY 
       con_id,
       tablespace_name
),
un AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       ts.con_id,
       ts.tablespace_name,
       NVL(um.used_space * ts.block_size, 0) bytes
  FROM cdb_tablespaces              ts,
       cdb_tablespace_usage_metrics um
 WHERE ts.contents           = 'UNDO'
   AND um.tablespace_name(+) = ts.tablespace_name
   AND um.con_id(+)          = ts.con_id
),
oem AS (
SELECT /*+ MATERIALIZE NO_MERGE */
       ts.con_id,
       pdb.name pdb_name,
       ts.tablespace_name,
       ts.contents,
       ts.block_size,
       NVL(t.bytes / POWER(2,20), 0) allocated_space, -- MBs
       NVL(
       CASE ts.contents
       WHEN 'UNDO'         THEN un.bytes
       WHEN 'PERMANENT'    THEN t.bytes - NVL(u.bytes, 0)
       WHEN 'TEMPORARY'    THEN
         CASE ts.extent_management
         WHEN 'LOCAL'      THEN u.bytes
         WHEN 'DICTIONARY' THEN t.bytes - NVL(u.bytes, 0)
         END
       END 
       / POWER(2,20), 0) used_space -- MBs
  FROM cdb_tablespaces ts,
       v$containers    pdb,
       t,
       u,
       un
 WHERE pdb.con_id            = ts.con_id
   AND t.tablespace_name(+)  = ts.tablespace_name
   AND t.con_id(+)           = ts.con_id
   AND u.tablespace_name(+)  = ts.tablespace_name
   AND u.con_id(+)           = ts.con_id
   AND un.tablespace_name(+) = ts.tablespace_name
   AND un.con_id(+)          = ts.con_id
)
SELECT o.con_id,
       o.pdb_name,
       o.tablespace_name,
       o.contents,
       --o.block_size,
       ROUND(o.allocated_space, 3) oem_allocated_space_mbs,
       ROUND(o.used_space, 3) oem_used_space_mbs,
       ROUND(100 * o.used_space / o.allocated_space, 3) oem_used_percent, -- as per allocated space
       ROUND(m.tablespace_size * o.block_size / POWER(2, 20), 3) met_max_size_mbs,
       ROUND(m.used_space * o.block_size / POWER(2, 20), 3) met_used_space_mbs,
       ROUND(m.used_percent, 3) met_used_percent -- as per maximum size (considering auto extend)
  FROM oem                          o,
       cdb_tablespace_usage_metrics m
 WHERE m.tablespace_name(+) = o.tablespace_name
   AND m.con_id(+)          = o.con_id
 ORDER BY
       o.con_id,
       o.tablespace_name
/

