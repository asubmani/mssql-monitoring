"SELECT [ReadLatency] = CAST(CASE WHEN [num_of_reads] = 0 THEN 0 
                             ELSE ([io_stall_read_ms] / [num_of_reads]) END AS float(53)),
    [WriteLatency] =  CAST(CASE WHEN [num_of_writes] = 0 THEN 0 
                            ELSE ([io_stall_write_ms] / [num_of_writes]) END AS float(53)),
    LEFT ([m_files].[physical_name], 2) AS [Disk],
    DB_NAME ([io_stats].[database_id]) AS [DatabaseName],
    [m_files].[physical_name] AS [FileName]
    FROM sys.dm_io_virtual_file_stats (NULL,NULL) AS [io_stats]
    JOIN sys.master_files AS [m_files]
    ON [io_stats].[database_id] = [m_files].[database_id]
    AND [io_stats].[file_id] = [m_files].[file_id]"