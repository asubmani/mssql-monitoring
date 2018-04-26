"SET NOCOUNT ON 
DECLARE @wait_threshold INT 
SET @wait_threshold = 1000 * 60 * ? 
DECLARE @servermajorversion INT 
SET @servermajorversion = REPLACE (LEFT (CONVERT (varchar, SERVERPROPERTY ('ProductVersion')), 2), '.', '') 
 
IF OBJECT_ID ('tempdb.dbo.#tmp_blockers') IS NOT NULL DROP TABLE #tmp_blockers 
IF OBJECT_ID ('tempdb.dbo.#tmp_head_blockers') IS NOT NULL DROP TABLE #tmp_head_blockers 
IF OBJECT_ID ('tempdb.dbo.#tmp_head_blocker_depth') IS NOT NULL DROP TABLE #tmp_head_blocker_depth 
 
 
SELECT 
 S.session_id, 
 CASE  
  WHEN R.blocking_session_id IS NULL OR R.blocking_session_id = 0 THEN 'TRUE' 
  ELSE 'FALSE' 
 END AS head_blocker, 
 R.blocking_session_id, 
 R.status AS request_status, 
 S.status AS session_status,  
 CAST(LEFT(CASE R.sql_handle 
  WHEN NULL THEN 
   (SELECT text FROM sys.dm_exec_sql_text(R.sql_handle))  
  ELSE  
   (SELECT text FROM sys.dm_exec_sql_text(C.most_recent_sql_handle)) 
 END, 4000) AS NVARCHAR(4000)) AS sql_stmnt, 
 S.program_name, 
 S.host_name, 
 S.host_process_id, 
 S.is_user_process, 
 S.login_name, 
 S.login_time, 
 R.start_time AS request_start_time, 
 R.wait_type, 
 R.last_wait_type, 
 CONVERT(NUMERIC(9,3),(R.wait_time / 1000.0)) AS wait_time_in_sec,  
 R.command, 
 R.wait_resource, 
 CASE COALESCE(R.transaction_isolation_level, S.transaction_isolation_level) 
  WHEN 0 THEN '0-Unspecified' 
  WHEN 1 THEN '1-ReadUncomitted' 
  WHEN 2 THEN '2-ReadCommitted' 
  WHEN 3 THEN '3-Repeatable' 
  WHEN 4 THEN '4-Serializable' 
  WHEN 5 THEN '5-Snapshot' 
  ELSE CONVERT(VARCHAR(10), COALESCE(R.transaction_isolation_level, S.transaction_isolation_level)) + '-Unknown'  
 END AS transaction_isolation_level, 
 --SQLBUD #487091 
 CASE  
  WHEN R.open_transaction_count IS NULL THEN (SELECT open_tran FROM sys.sysprocesses AS SP WHERE SP.spid = S.session_id) 
  ELSE R.open_transaction_count 
 END AS open_transaction_count, 
 R.open_resultset_count, 
 CONVERT (decimal(5,2), R.percent_complete) AS percent_complete,  
 R.estimated_completion_time, 
 --SQLBUD #438189 (fixed in SP2) 
    CASE WHEN (@servermajorversion > 9) OR (@servermajorversion = 9 AND SERVERPROPERTY ('ProductLevel') >= 'SP2' COLLATE Latin1_General_BIN)  
      THEN R.logical_reads ELSE R.logical_reads - S.logical_reads END AS request_logical_reads,  
    CASE WHEN (@servermajorversion > 9) OR (@servermajorversion = 9 AND SERVERPROPERTY ('ProductLevel') >= 'SP2' COLLATE Latin1_General_BIN)  
      THEN R.reads ELSE R.reads - S.reads END AS request_reads,  
    CASE WHEN (@servermajorversion > 9) OR (@servermajorversion = 9 AND SERVERPROPERTY ('ProductLevel') >= 'SP2' COLLATE Latin1_General_BIN) 
      THEN R.writes ELSE R.writes - S.writes END AS request_writes,  
 R.cpu_time AS request_cpu_time, 
 R.lock_timeout, 
 R.deadlock_priority, 
 R.row_count AS request_row_count, 
 R.prev_error AS request_prev_error, 
 R.nest_level, 
 R.granted_query_memory, 
 R.user_id, 
 R.transaction_id, 
 S.cpu_time AS session_cpu_time, 
 S.memory_usage, 
 S.reads AS session_reads, 
 S.logical_reads AS session_logical_reads, 
 S.writes AS session_writes, 
 S.prev_error AS session_prev_error, 
 S.row_count AS session_row_count 
INTO 
 #tmp_blockers 
FROM  
 (sys.dm_exec_sessions AS S  
  LEFT OUTER JOIN sys.dm_exec_requests AS R ON R.session_id = S.session_id) 
  LEFT OUTER JOIN sys.dm_exec_connections AS C ON C.session_id = S. session_id 
WHERE  
 ( --Active Request 
  R.session_id IS NOT NULL AND  
  R.blocking_session_id != 0 AND  
  S.session_id != @@SPID AND 
  R.wait_time > @wait_threshold AND 
  (S.is_user_process = 1 OR R.status COLLATE Latin1_General_BIN NOT IN ('background', 'sleeping'))) 
    OR --Head Blocker  
    (S.session_id IN 
  (SELECT S.session_id  
   FROM sys.dm_exec_sessions AS S 
              INNER JOIN sys.dm_exec_requests AS BER ON BER.blocking_session_id = S.session_id 
              LEFT OUTER JOIN sys.dm_exec_requests AS ER ON ER.session_id = S.session_id 
          WHERE 
              (ER.blocking_session_id = 0 OR ER.blocking_session_id IS NULL) 
              AND BER.wait_time > @wait_threshold)); 
     
--Find Blocking Levels 
;WITH blocking_levels(session_id, blocking_session_id, blocking_level, head_blocker) AS  
( 
    SELECT session_id, blocking_session_id, 0 AS blocking_level, session_id AS head_blocker 
    FROM #tmp_blockers 
    WHERE blocking_session_id IS NULL OR blocking_session_id = 0 
    UNION ALL 
    SELECT TB.session_id, TB.blocking_session_id, BL.blocking_level + 1 AS blocking_level, BL.head_blocker 
    FROM #tmp_blockers AS TB 
        INNER JOIN blocking_levels AS BL 
        ON TB.blocking_session_id = BL.session_id 
) 
SELECT *  
INTO #tmp_head_blockers 
FROM blocking_levels 
 
SELECT COUNT(*) - 1 AS head_blocking_depth, head_blocker 
INTO #tmp_head_blocker_depth 
FROM #tmp_head_blockers 
GROUP BY head_blocker 
 
-- This query could be collapsed into the query above.  It is broken out here to avoid an excessively  
-- large memory grant due to poor cardinality estimates (no stats on many DMVs).  
 
SELECT TOP 20  
 TB.session_id, 
 TB.blocking_session_id, 
 THB.blocking_level, 
 TB.head_blocker, 
 THBD.head_blocking_depth, 
 TB.request_status, 
 TB.session_status, 
 TB.sql_stmnt, 
 TB.request_start_time, 
 TB.wait_type, 
 TB.last_wait_type, 
 TB.wait_time_in_sec, 
 TB.command, 
 TB.program_name, 
 TB.host_name, 
 TB.host_process_id, 
 TB.is_user_process, 
 TB.login_name, 
 TB.login_time, 
 TB.wait_resource, 
 TB.transaction_isolation_level, 
 TB.open_transaction_count, 
 TB.open_resultset_count, 
 COALESCE(AT.name, AT2.name) AS transaction_name, 
 COALESCE(AT.transaction_begin_time, AT2.transaction_begin_time) AS transaction_begin_time, 
 CASE COALESCE(AT.transaction_type, AT2.transaction_type) 
  WHEN 1 THEN '1-Read/write transaction' 
  WHEN 2 THEN '2-Read-only transaction' 
  WHEN 3 THEN '3-System transaction' 
  WHEN 4 THEN '4-Distributed transaction' 
  ELSE CONVERT(VARCHAR(10), COALESCE(AT.transaction_type, AT2.transaction_type)) + '-Unknown' 
 END AS transaction_type, 
 CASE COALESCE(AT.transaction_state, AT2.transaction_state) 
  WHEN 0 THEN '0-The transaction has not been completely initialized yet.' 
  WHEN 1 THEN '1-The transaction has been initialized but has not started.' 
  WHEN 2 THEN '2-The transaction is active.' 
  WHEN 3 THEN '3-The transaction has ended. This is used for read-only transactions.' 
  WHEN 4 THEN '4-The commit process has been initiated on the distributed transaction. This is for distributed transactions only. The distributed transaction is still active but further processing cannot take place.' 
  WHEN 5 THEN '5-The transaction is in a prepared state and waiting resolution.' 
  WHEN 6 THEN '6-The transaction has been committed.' 
  WHEN 7 THEN '7-The transaction is being rolled back.' 
  WHEN 8 THEN '8-The transaction has been rolled back.' 
  ELSE CONVERT(VARCHAR(10), COALESCE(AT.transaction_state, AT2.transaction_state)) + '-Unknown' 
 END AS transaction_state, 
 TB.percent_complete, 
 TB.estimated_completion_time, 
 TB.request_logical_reads, 
 TB.request_reads, 
 TB.request_writes, 
 TB.request_cpu_time, 
 TB.lock_timeout, 
 TB.deadlock_priority, 
 TB.request_row_count, 
 TB.request_prev_error, 
 TB.nest_level, 
 TB.granted_query_memory, 
 TB.user_id, 
 TB.transaction_id, 
 TB.session_cpu_time, 
 TB.memory_usage, 
 TB.session_reads, 
 TB.session_logical_reads, 
 TB.session_writes, 
 TB.session_prev_error, 
 TB.session_row_count 
FROM  
 #tmp_blockers AS TB 
  LEFT OUTER JOIN sys.dm_tran_active_transactions AS AT ON AT.transaction_id = TB.transaction_id 
   LEFT OUTER JOIN sys.dm_tran_session_transactions AS TS ON TS.session_id = TB.session_id 
    LEFT OUTER JOIN sys.dm_tran_active_transactions AS AT2 ON AT2.transaction_id = TS.transaction_id 
     LEFT OUTER JOIN #tmp_head_blockers AS THB ON THB.session_id = TB.session_id 
      LEFT OUTER JOIN #tmp_head_blocker_depth AS THBD ON THBD.head_blocker = TB.session_id 
 
ORDER BY TB.head_blocker DESC, THB.blocking_level"