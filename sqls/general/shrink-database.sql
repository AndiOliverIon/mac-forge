-- ==============================================================================
-- Shrink Database and Log Files with Reporting
-- ==============================================================================
-- This script switches the database to SIMPLE recovery mode, shrinks 
-- both data and log files, and reports the space gained.
-- ==============================================================================

SET NOCOUNT ON;

-- Variables for size tracking
DECLARE @InitialSizeMB FLOAT;
DECLARE @FinalSizeMB FLOAT;

-- 1. Get Initial Size
SELECT @InitialSizeMB = SUM(size * 8.0 / 1024) FROM sys.database_files;
PRINT '------------------------------------------------------------';
PRINT 'Starting Shrink Operation';
PRINT 'Initial Database Size: ' + CAST(ROUND(@InitialSizeMB, 2) AS VARCHAR(20)) + ' MB';
PRINT '------------------------------------------------------------';

-- 2. Switch recovery model to SIMPLE to allow log truncation
PRINT 'Setting recovery model to SIMPLE...';
ALTER DATABASE CURRENT SET RECOVERY SIMPLE;

-- 3. Shrink the entire database (Data and Log files)
PRINT 'Performing DBCC SHRINKDATABASE...';
DBCC SHRINKDATABASE (0) WITH NO_INFOMSGS;

-- 4. Specifically target and shrink the Log file(s)
DECLARE @LogFileName NVARCHAR(255);
DECLARE log_cursor CURSOR FOR 
    SELECT name FROM sys.database_files WHERE type = 1;

OPEN log_cursor;
FETCH NEXT FROM log_cursor INTO @LogFileName;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '  - Shrinking log file: ' + @LogFileName;
    DBCC SHRINKFILE (@LogFileName, 1) WITH NO_INFOMSGS;
    FETCH NEXT FROM log_cursor INTO @LogFileName;
END
CLOSE log_cursor;
DEALLOCATE log_cursor;

-- 5. Specifically target and shrink the Data file(s)
DECLARE @DataFileName NVARCHAR(255);
DECLARE data_cursor CURSOR FOR 
    SELECT name FROM sys.database_files WHERE type = 0;

OPEN data_cursor;
FETCH NEXT FROM data_cursor INTO @DataFileName;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '  - Shrinking data file: ' + @DataFileName;
    DBCC SHRINKFILE (@DataFileName, 1) WITH NO_INFOMSGS;
    FETCH NEXT FROM data_cursor INTO @DataFileName;
END
CLOSE data_cursor;
DEALLOCATE data_cursor;

-- 6. Get Final Size and Report
SELECT @FinalSizeMB = SUM(size * 8.0 / 1024) FROM sys.database_files;

PRINT '------------------------------------------------------------';
PRINT 'Shrink Operation Completed';
PRINT 'Final Database Size:   ' + CAST(ROUND(@FinalSizeMB, 2) AS VARCHAR(20)) + ' MB';
PRINT 'Space Gained:          ' + CAST(ROUND(@InitialSizeMB - @FinalSizeMB, 2) AS VARCHAR(20)) + ' MB';
PRINT '------------------------------------------------------------';
GO
