
/*Not so important*/
TRUNCATE TABLE [System].[Audit];
DELETE FROM Production.Scan;
DELETE FROM Common.BarcodeScannerLog;
DELETE FROM [System].[Log];

/* Project history traceability */
DELETE FROM Sync.LogLine;
DELETE FROM Sync.Log;
DELETE FROM Sync.Alias;