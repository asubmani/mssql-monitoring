"DECLARE @dbName sysname, @sqlFiles nvarchar(2000), @sqlGroups nvarchar(2000), @needsMaster BIT;

IF OBJECT_ID ('tempdb.dbo.#FileGroupsTable') IS NOT NULL DROP TABLE #FileGroupsTable;
CREATE TABLE #FileGroupsTable (
 GroupKey NVARCHAR(22)
 ,[DatabaseName] SYSNAME
 ,FilegroupName SYSNAME
 ,FilegroupType NVARCHAR(2)
 );

IF OBJECT_ID ('tempdb.dbo.#ResultTable') IS NOT NULL DROP TABLE #ResultTable;
CREATE TABLE #ResultTable (
 GroupKey NVARCHAR(22)
 ,[DatabaseName] SYSNAME
 ,[FileName] SYSNAME
 ,FileSizeMB FLOAT(53)
 ,FileUsedSpaceMB FLOAT(53)
 ,FileMaxSizeMB FLOAT(53)
 ,IsAutoGrowEnabled BIT
 ,IsPercentGrowth BIT
 ,FileGrowth INT
 ,VolumeMountPoint NVARCHAR(256)
 ,VolumeId NVARCHAR(256)
 ,DiskFreeSpaceMB FLOAT(53)
 ,PhysicalName NVARCHAR(260)
 );

DECLARE fileCursor CURSOR LOCAL STATIC FOR 
SELECT 
 d.[name]
 ,CAST(CASE
  WHEN d.[replica_id] IS NOT NULL OR d.is_in_standby = 1 THEN 1
  ELSE 0
 END AS BIT) AS [needsMaster] 
FROM sys.databases d
WHERE HAS_DBACCESS(d.[name]) = 1;

OPEN fileCursor;
FETCH NEXT FROM fileCursor INTO @dbName, @needsMaster;

WHILE @@Fetch_Status=0 BEGIN
 SET @sqlFiles = N'USE '+ QUOTENAME(@dbName,'""') + N';
 SELECT
  CAST(DB_ID() AS nvarchar(10)) + N''_'' + CAST(fg.data_space_id AS nvarchar(10)) AS [GroupKey]
  ,DB_NAME() AS [DatabaseName]
  ,f.name AS [FileName]
  ,CONVERT(FLOAT(53), f.size / 128.0) AS [FileSizeMB]
  ,CONVERT(FLOAT(53), FILEPROPERTY(f.name, ''SpaceUsed'') / 128.0) as [FileUsedSpaceMB]
  ,CONVERT(FLOAT(53), CASE 
   WHEN f.max_size = -1 OR f.max_size = 268435456 THEN -1 
   ELSE f.max_size / 128.0 
   END) as [FileMaxSizeMB]
  ,CASE
   WHEN f.growth = 0 THEN 0
   ELSE 1
   END AS IsAutoGrowEnabled
  ,f.is_percent_growth as [IsPercentGrowth]
  ,f.growth AS [FileGrowth]
  ,ovs.volume_mount_point AS [VolumeMountPoint]
  ,ovs.volume_id AS [VolumeId]';

 IF @needsMaster = 0
 BEGIN
  SET @sqlFiles = @sqlFiles + N'
  ,CONVERT(FLOAT(53), CASE 
   WHEN CharIndex(N''https://'',LTRIM(f.physical_name)) = 1 OR CharIndex(N''http://'',LTRIM(f.physical_name)) = 1 THEN @azureMaxFileSizeMB - f.size / 128.0
   ELSE ovs.available_bytes / 1048576.0 
   END) AS [DiskFreeSpaceMB]
  ,f.physical_name AS [PhysicalName]
 FROM sys.database_files AS f WITH (NOLOCK)';
 END;
 ELSE
 BEGIN
  SET @sqlFiles = @sqlFiles + N'
  ,CONVERT(FLOAT(53), CASE 
   WHEN CharIndex(N''https://'',LTRIM(mf.physical_name)) = 1 OR CharIndex(N''http://'',LTRIM(mf.physical_name)) = 1 THEN @azureMaxFileSizeMB - f.size / 128.0
   ELSE ovs.available_bytes / 1048576.0 
   END) AS [DiskFreeSpaceMB]
  ,mf.physical_name AS [PhysicalName]
 FROM sys.database_files AS f WITH (NOLOCK)
 JOIN sys.master_files AS mf WITH (NOLOCK) ON f.file_id = mf.file_id AND mf.database_id = DB_ID()';
 END;

 SET @sqlFiles = @sqlFiles + N'
 INNER JOIN sys.filegroups fg WITH (NOLOCK) ON f.data_space_id = fg.data_space_id
 CROSS APPLY sys.dm_os_volume_stats(DB_ID(), f.file_id) ovs
 WHERE f.[type] IN (0,1,2) AND f.is_read_only = 0
  AND (fg.[type] = @filegroupType OR @filegroupType COLLATE DATABASE_DEFAULT = N''ALL'');';

 SET @sqlGroups = N'USE '+ QUOTENAME(@dbName,'""') + N';
 SELECT 
  CAST(DB_ID() AS nvarchar(10)) + N''_'' + CAST(fg.data_space_id AS nvarchar(10)) AS [GroupKey]
  ,DB_NAME() AS [DatabaseName]
  ,fg.[name] AS [FilegroupName]
  ,fg.[type] AS [FilegroupType]
 FROM sys.filegroups fg WITH (NOLOCK)
 WHERE (fg.[type] = @filegroupType OR @filegroupType COLLATE DATABASE_DEFAULT = N''ALL'');';

 BEGIN TRY
  BEGIN TRAN
   INSERT INTO #ResultTable
   EXEC sp_executesql @sqlFiles, N'@filegroupType NVARCHAR(3), @azureMaxFileSizeMB INT', @filegroupType = @filegroupType, @azureMaxFileSizeMB = @azureMaxFileSizeMB;
   INSERT INTO #FileGroupsTable
   EXEC sp_executesql @sqlGroups, N'@filegroupType NVARCHAR(3)', @filegroupType = @filegroupType;
  COMMIT
 END TRY
 BEGIN CATCH
 END CATCH;
 FETCH NEXT FROM fileCursor INTO @dbName, @needsMaster;
END

CLOSE fileCursor;
DEALLOCATE fileCursor;

SELECT * FROM #FileGroupsTable;
SELECT * FROM #ResultTable;"
