-- ZBank SQL Server database initialisation script
-- Run via sqlcmd or the docker-compose sqlserver-init service.
-- Safe to re-run: uses IF NOT EXISTS pattern.

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'auth_db')
    CREATE DATABASE auth_db;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'app_db')
    CREATE DATABASE app_db;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'credit_db')
    CREATE DATABASE credit_db;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'activation_db')
    CREATE DATABASE activation_db;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'cardmgmt_db')
    CREATE DATABASE cardmgmt_db;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'notif_db')
    CREATE DATABASE notif_db;
GO

PRINT 'All ZBank databases created successfully.';
GO
