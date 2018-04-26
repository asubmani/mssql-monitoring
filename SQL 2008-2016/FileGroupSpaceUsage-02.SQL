SET NOCOUNT ON 
SELECT df.size / 128.0 as fileSize, 
 df.file_id as fileId,
 FILEPROPERTY(df.name, 'SpaceUsed') / 128.0 as fileUsed,
 CASE WHEN df.max_size = -1 OR df.max_size = 268435456 THEN -1 ELSE df.max_size / 128.0 END as fileMaxSize,
 CASE WHEN df.growth = 0 THEN 0 ELSE 1 END as IsAutoGrow, 
 df.is_percent_growth as isPercentGrowth, 
 df.growth as fileGrowth, mf.physical_name 
FROM sys.database_files df WITH (NOLOCK)
JOIN sys.master_files mf WITH (NOLOCK) ON df.file_id = mf.file_id AND mf.database_id = ?
WHERE df.type IN (0,1) AND df.is_read_only = 0