"DECLARE @xmlDoc XML;

SET @xmlDoc = CAST(@includedJobsXmlString AS XML);

IF OBJECT_ID('tempdb.dbo.#included_jobs') IS NOT NULL DROP TABLE #included_jobs;

CREATE TABLE #included_jobs (
 job_name SYSNAME COLLATE SQL_Latin1_General_CP1_CS_AS NOT NULL
);

INSERT INTO #included_jobs(job_name)
 SELECT DISTINCT xc.value('.', 'SYSNAME') 
 FROM @xmlDoc.nodes('/*/*') as xt(xc);

IF OBJECT_ID('tempdb.dbo.#job_activity') IS NOT NULL DROP TABLE #job_activity;

CREATE TABLE #job_activity (
 [session_id] INT NOT NULL
 ,[job_id] UNIQUEIDENTIFIER NOT NULL
 ,[job_name] SYSNAME COLLATE SQL_Latin1_General_CP1_CS_AS NOT NULL
 ,[run_requested_date] DATETIME NULL
 ,[run_requested_source] SYSNAME COLLATE SQL_Latin1_General_CP1_CS_AS NULL
 ,[queued_date] DATETIME NULL
 ,[start_execution_date] DATETIME NULL
 ,[last_executed_step_id] INT NULL
 ,[last_exectued_step_date] DATETIME NULL
 ,[stop_execution_date] DATETIME NULL
 ,[next_scheduled_run_date] DATETIME NULL
 ,[job_history_id] INT NULL
 ,[message] NVARCHAR(1024) COLLATE SQL_Latin1_General_CP1_CS_AS NULL
 ,[run_status] INT NULL
 ,[operator_id_emailed] INT NULL
 ,[operator_id_netsent] INT NULL
 ,[operator_id_paged] INT NULL
 ,[execution_time_minutes] INT NULL
 );

INSERT INTO #job_activity (
 [session_id]
 ,[job_id]
 ,[job_name]
 ,[run_requested_date]
 ,[run_requested_source]
 ,[queued_date]
 ,[start_execution_date]
 ,[last_executed_step_id]
 ,[last_exectued_step_date]
 ,[stop_execution_date]
 ,[next_scheduled_run_date]
 ,[job_history_id]
 ,[message]
 ,[run_status]
 ,[operator_id_emailed]
 ,[operator_id_netsent]
 ,[operator_id_paged]
 )
EXECUTE [msdb].[dbo].[sp_help_jobactivity];

WITH cs_cte AS(
 SELECT DISTINCT
  job_id
 FROM
  msdb.dbo.sysjobschedules sjs
  join msdb.dbo.sysschedules ss on ss.schedule_id = sjs.schedule_id
 WHERE ss.freq_type = 64
)
SELECT 
 [ja].[job_name] AS [JobName]
 ,DATEDIFF(minute, [start_execution_date], GETDATE()) AS [ExecutionTimeMinutes]
FROM #job_activity [ja]
LEFT JOIN cs_cte ON ja.job_id = cs_cte.job_id
LEFT JOIN #included_jobs ij ON ij.job_name COLLATE SQL_Latin1_General_CP1_CS_AS = ja.job_name
WHERE [start_execution_date] IS NOT NULL AND [run_status] IS NULL 
AND (cs_cte.job_id IS NULL OR ij.job_name IS NOT NULL);

DROP TABLE #included_jobs;
DROP TABLE #job_activity;"