--check if sp already exists, if so, drop it
IF OBJECT_ID('sp_CustomerRevenue', 'P') IS NOT NULL
    DROP PROCEDURE sp_CustomerRevenue;
GO

--create sp
CREATE PROCEDURE sp_CustomerRevenue
    --input variables
    @CustomerID INT = NULL,
    @FromYear INT = NULL,
    @ToYear INT = NULL,
    @Period NVARCHAR(7) = 'Y'

AS
BEGIN
    --sp variables
    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @TableName NVARCHAR(250);
    DECLARE @MinFromYear INT;
    DECLARE @MaxFromYear INT;
    DECLARE @CustomerName NVARCHAR(200);
    DECLARE @CustomerWhere NVARCHAR(250) = '';

    --create ErrorLog table if it doesn't exist
    IF OBJECT_ID('ErrorLog', 'U') IS NULL
BEGIN
        CREATE TABLE ErrorLog
        (
            ErrorID INT PRIMARY KEY IDENTITY,
            ErrorNumber INT,
            ErrorSeverity INT,
            ErrorMessage VARCHAR(255),
            CustomerID INT,
            Period VARCHAR(8),
            CreatedAt DATETIME DEFAULT GETDATE()
        );
    END

    --start logic
    BEGIN TRY 
--max and min dates availables in the db
    IF @CustomerID IS NULL BEGIN
        SELECT @MinFromYear = MIN(YEAR(S.[Invoice Date Key]))
        FROM [Fact].[Sale] S
        SELECT @MaxFromYear = MAX(YEAR(S.[Invoice Date Key]))
        FROM [Fact].[Sale] S
        SET @CustomerName = NULL
    END ELSE BEGIN
        SELECT @MinFromYear = MIN(YEAR(S.[Invoice Date Key]))
        FROM [Fact].[Sale] S
        WHERE S.[Customer Key] = @CustomerID
        SELECT @MaxFromYear = MAX(YEAR(S.[Invoice Date Key]))
        FROM [Fact].[Sale] S
        WHERE S.[Customer Key] = @CustomerID
        SELECT @CustomerName = REPLACE([Customer],' ','_')
        FROM [Dimension].[Customer] C
        WHERE C.[Customer Key] = @CustomerID
        --stop if the customerid provided don't exists
        IF @CustomerName IS NULL BEGIN
            RAISERROR('CustomerID does not exist in the database', 16, 1);
        END
        SET @CustomerName = CONCAT(@CustomerName,'_')
        --where clause for the customer id to be implemented later
        SET @CustomerWhere = 'C.[Customer Key] = ' + CAST(@CustomerID AS VARCHAR(10)) + ' AND '
    END
-- save not null values into from and to year variables
    SET @FromYear = COALESCE(CAST(@FromYear AS NVARCHAR(10)), CAST(@MinFromYear AS NVARCHAR(4)))
    SET @ToYear = COALESCE(CAST(@ToYear AS NVARCHAR(10)), CAST(@MaxFromYear AS NVARCHAR(4)))
--one year report table name validation
    IF @FromYear = @ToYear BEGIN
        SET @TableName = COALESCE(CAST(@CustomerID AS NVARCHAR(10)), 'All') + '_' + COALESCE(CAST(@CustomerName AS NVARCHAR(200)), '') + CAST(@FromYear AS NVARCHAR(4)) + '_' + UPPER(@Period);
    END ELSE BEGIN
        SET @TableName = COALESCE(CAST(@CustomerID AS NVARCHAR(10)), 'All') + '_' + COALESCE(CAST(@CustomerName AS NVARCHAR(200)), '') + CAST(@FromYear AS NVARCHAR(4)) + '_' + CAST(@ToYear AS NVARCHAR(4)) + '_' + UPPER(@Period);
    END
    
--drop table if it exists
    SET @Sql = 'DROP TABLE IF EXISTS [' + @TableName + ']';
    EXEC sp_executesql @Sql;

--create table 
    SET @Sql = 'CREATE TABLE [' + @TableName + '] (
                    CustomerID INT,
                    CustomerName VARCHAR(50),
                    Period VARCHAR(8),
                    Revenue NUMERIC(19,2))'
    EXEC sp_executesql @Sql;

--check periods: M, Q or Y
    IF (UPPER(@Period) = 'M' OR UPPER(@Period) = 'MONTH') BEGIN
        SET @Sql = '
            INSERT INTO [' + @TableName + '] 
            SELECT 
                C.[Customer Key], 
                C.[Customer], 
                FORMAT(S.[Invoice Date Key],''MMM yyyy'') Period,
                SUM(S.[Quantity]*S.[Unit Price]) [Revenue]
            FROM [Fact].[Sale] S
            JOIN [Dimension].[Customer] C ON S.[Customer Key]=C.[Customer Key]
            JOIN [Dimension].[Date] D ON S.[Invoice Date Key]=D.[Date]
            WHERE 
                ' + @CustomerWhere + '
                D.[Calendar Year] BETWEEN ' + CAST(@FromYear AS VARCHAR(10)) + ' 
                AND ' + CAST(@ToYear AS VARCHAR(10)) + '
            GROUP BY  
                C.[Customer Key],
                C.[Customer],
                FORMAT(S.[Invoice Date Key],''MMM yyyy''),
                CAST(FORMAT(S.[Invoice Date Key], ''yyyyMM'') AS INT)
            ORDER BY 
                C.[Customer Key],
                CAST(FORMAT(S.[Invoice Date Key], ''yyyyMM'') AS INT)'
        EXEC sp_executesql @Sql;
    END ELSE IF (UPPER(@Period) = 'Q' OR UPPER(@Period) = 'QUARTER') BEGIN
        SET @Sql = '
            INSERT INTO [' + @TableName + '] 
            SELECT 
                C.[Customer Key], 
                C.[Customer], 
                CONCAT(''Q'',CAST(DATEPART(QUARTER,S.[Invoice Date Key]) AS VARCHAR),'' '',CAST(YEAR(S.[Invoice Date Key]) AS VARCHAR)) Period,
                SUM(S.[Quantity]*S.[Unit Price]) [Revenue]
            FROM [Fact].[Sale] S
            JOIN [Dimension].[Customer] C ON S.[Customer Key]=C.[Customer Key]
            JOIN [Dimension].[Date] D ON S.[Invoice Date Key]=D.[Date]
            WHERE 
                ' + @CustomerWhere + '
                D.[Calendar Year] BETWEEN ' + CAST(@FromYear AS VARCHAR(10)) + ' 
                AND ' + CAST(@ToYear AS VARCHAR(10)) + '
            GROUP BY  
                C.[Customer Key],
                C.[Customer],
                CONCAT(''Q'',CAST(DATEPART(QUARTER,S.[Invoice Date Key]) AS VARCHAR),'' '',CAST(YEAR(S.[Invoice Date Key]) AS VARCHAR)),
                CAST(CONCAT(YEAR(S.[Invoice Date Key]),
                DATEPART(QUARTER,S.[Invoice Date Key])) AS INT)
            ORDER BY 
                C.[Customer Key],
                CAST(CONCAT(YEAR(S.[Invoice Date Key]),DATEPART(QUARTER,S.[Invoice Date Key])) AS INT)'
        EXEC sp_executesql @Sql;
    END ELSE IF (UPPER(@Period) = 'Y' OR UPPER(@Period) = 'YEAR') BEGIN
        SET @Sql = '
            INSERT INTO [' + @TableName + '] 
            SELECT 
                C.[Customer Key], 
                C.[Customer], 
                CAST(YEAR(S.[Invoice Date Key]) AS VARCHAR) Period,
                SUM(S.[Quantity]*S.[Unit Price]) [Revenue]
            FROM [Fact].[Sale] S
            JOIN [Dimension].[Customer] C ON S.[Customer Key]=C.[Customer Key]
            JOIN [Dimension].[Date] D ON S.[Invoice Date Key]=D.[Date]
            WHERE 
                ' + @CustomerWhere + '
                D.[Calendar Year] BETWEEN ' + CAST(@FromYear AS VARCHAR(10)) + ' 
                AND ' + CAST(@ToYear AS VARCHAR(10)) + '
            GROUP BY 
                C.[Customer Key],
                C.[Customer],
                CAST(YEAR(S.[Invoice Date Key]) AS VARCHAR)
            ORDER BY 
                C.[Customer Key],
                CAST(YEAR(S.[Invoice Date Key]) AS VARCHAR)'
        EXEC sp_executesql @Sql;
    END ELSE
        RAISERROR('Period not recognized, try Y or Year, Q or Quarter, M or Month',16,1)
END TRY
BEGIN CATCH
    PRINT ERROR_MESSAGE()
    INSERT INTO ErrorLog
        (ErrorNumber, ErrorSeverity, ErrorMessage, CustomerID, Period)
    VALUES
        (ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_MESSAGE(), @CustomerID, @Period);
END CATCH
END