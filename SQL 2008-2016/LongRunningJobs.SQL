"SET NOCOUNT ON
DECLARE @job_activity TABLE (
[session_id] [int] NOT NULL,
[job_id] [uniqueidentifier] NOT NULL,
[job_name] [sysname] COLLATE SQL_Latin1_General_CP1_CS_AS NOT NULL,
[run_requested_date] [datetime] NULL,
[run_requested_source] [sysname] COLLATE SQL_Latin1_General_CP1_CS_AS NULL,
[queued_date] [datetime] NULL,
[start_execution_date] [datetime] NULL,
[last_executed_step_id] [int] NULL,
[last_exectued_step_date] [datetime] NULL,
[stop_execution_date] [datetime] NULL,
[next_scheduled_run_date] [datetime] NULL,
[job_history_id] [int] NULL,
[message] [nvarchar](1024) COLLATE SQL_Latin1_General_CP1_CS_AS NULL,
[run_status] [int] NULL,
[operator_id_emailed] [int] NULL,
[operator_id_netsent] [int] NULL,
[operator_id_paged] [int] NULL,
[execution_time_minutes] [int] NULL )
INSERT INTO @job_activity
([session_id]
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
,[operator_id_paged])
EXECUTE [msdb].[dbo].[sp_help_jobactivity]
SELECT
[ja].[job_id]
,[ja].[job_name]
,[originating_server]
,DATEDIFF(minute, [start_execution_date], GETDATE()) AS [execution_time_minutes]
FROM @job_activity [ja]
JOIN [msdb].[dbo].[sysjobs_view] [sjv] ON [sjv].[job_id] = [ja].[job_id]
WHERE [start_execution_date] IS NOT NULL AND [run_status] IS NULL"