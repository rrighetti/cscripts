-- IOD_SPACE_TAB_MODIFICATIONS_HIST (IOD_REPETITIVE_SPACE_TAB_MODIFICATIONS_HIST)
-- Table Modifications History - Collector
--
-- exit graciously if executed on standby
WHENEVER SQLERROR EXIT SUCCESS;
DECLARE
  l_open_mode VARCHAR2(20);
BEGIN
  SELECT open_mode INTO l_open_mode FROM v$database;
  IF l_open_mode <> 'READ WRITE' THEN
    raise_application_error(-20000, 'Must execute on PRIMARY');
  END IF;
END;
/
WHENEVER SQLERROR CONTINUE;
--
-- exit graciously if package does not exist
WHENEVER SQLERROR EXIT SUCCESS;
BEGIN
  DBMS_OUTPUT.PUT_LINE('API version: '||c##iod.iod_space.gk_package_version);
END;
/
WHENEVER SQLERROR EXIT FAILURE;
--
SET HEA ON LIN 500 PAGES 100 TAB OFF FEED OFF ECHO OFF VER OFF TRIMS ON TRIM ON TI OFF TIMI OFF;
SET HEA OFF;
--
COL zip_file_name NEW_V zip_file_name;
COL output_file_name NEW_V output_file_name;
SELECT '/tmp/iod_space_tab_modifications_hist_'||LOWER(name)||'_'||LOWER(REPLACE(SUBSTR(host_name, 1 + INSTR(host_name, '.', 1, 2), 30), '.', '_')) zip_file_name FROM v$database, v$instance;
SELECT '&&zip_file_name._'||TO_CHAR(SYSDATE, 'dd"T"hh24') output_file_name FROM DUAL;
--
SET TIMI ON;
SET SERVEROUT ON SIZE UNLIMITED;
SPO &&output_file_name..txt;
--
DECLARE
  l_cursor_id INTEGER;
  l_statement CLOB;
  l_rows  INTEGER;
  l_identifier_must_be_declared EXCEPTION;
  PRAGMA EXCEPTION_INIT(l_identifier_must_be_declared, -06550);
BEGIN
  l_statement := 'BEGIN DBMS_STATS.FLUSH_DATABASE_MONITORING_INFO; END;';
  l_cursor_id := DBMS_SQL.OPEN_CURSOR;
  FOR i IN (SELECT name FROM v$containers WHERE open_mode = 'READ WRITE')
  LOOP
    BEGIN
      DBMS_SQL.PARSE(c => l_cursor_id, statement => l_statement, language_flag => DBMS_SQL.NATIVE, container => i.name);
      l_rows := DBMS_SQL.EXECUTE(c => l_cursor_id);
    EXCEPTION
      WHEN l_identifier_must_be_declared THEN
        DBMS_OUTPUT.PUT_LINE(i.name||' '||SQLERRM);
    END;
  END LOOP;
  DBMS_SQL.CLOSE_CURSOR(c => l_cursor_id);
END;
/
EXEC c##iod.iod_space.tab_modifications_hist;
--
SPO OFF;
HOS zip -mj &&zip_file_name..zip &&output_file_name..txt
HOS unzip -l &&zip_file_name..zip
WHENEVER SQLERROR CONTINUE;
