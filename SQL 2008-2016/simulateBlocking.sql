-- from https://www.sqlservercentral.com/Forums/Topic946143-1292-1.aspx
--step 1
BEGIN TRAN
UPDATE TableX
SET Col = 42
WHERE Id = 66

--step 2. Open a new query window and update the same row(s).
UPDATE TableX
SET Col = 92
WHERE Id = 66 

-- to terminate
COMMIT TRAN