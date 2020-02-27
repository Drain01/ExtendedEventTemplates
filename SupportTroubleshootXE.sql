/*******************************************************************************************************************  
  Script Description: [SupportTroubleshootXE]

  This is the new standard SupportTroubleshootXE Extended Event (XE) template. This template is designed to replace 
     Microsoft's Profile Trace functionality, as Profile Traces are deprecated. This template is designed to be very 
	easy to deploy. 

  This is a simple template with few options, designed to be deployed by Tier 1 Support Reps. Each Execution of this 
     template will create a uniquely named session, to prevent these sessions from overwriting each other if you are
     investigating multiple issues at once. 

  This template will write data to an output file that you can specify below. The XE session will write up to 512 MB of
     data in a single file. It will create up to five of these files, the session can take up to 2.5 GB of hard drive space.
     Be aware of this when writing a file to a SQL Server's C:\ drive, so you don't fill the drive and take down the server!

  To deploy this script, configure these three variables in the User Configuration section below. 

    @DB		 By default, this template will monitor all databases on the server except the system 
				databases (Master, module, tempdb, msdb). If you enter a Database Name here, that will
				restrict the XE to just monitor that specific database. At this time, we only support one 
				value here, so you can only restrict to one database. 

    @User 	 By default, this template will monitor all users on the server. This can result in the output
				file being filed with irrelevant data. If you enter a user name here (Like a TMW SQL Server login
				or a Windows Login), the XE will just monitor that one user. At this time, we only support one value
				here, so you can only restrict to one user. 

    @FileOut	 By default, this template will write to an output file, a .XEL file. This variable tells the template where
				to create that output file. Important to note: This is from the perspective of the SQL Server itself. So,
				if you are creating this XE session on a user's workstation, it will not create the file in that user's 
				C:\Temp directory, it will create it in the SQL Server's C:\Temp. 

				Do not end this parameter with a "\" or you will break the template. 

				The output file will start with the name of the XE session, but date and time stamped. Below is an example
				file name:
				    C:\Temp\SupportTroubleshootXE_200221_023522_0_132267873224230000.xel

				If the template errs with a "The system cannot find the path specified" error, it means that SQL cannot write 
				to the directory you specified, as it may not exist or SQL lacks access. 

				This template will create files that contain up to 512 MB of data. If you fill the first file, it will create
				another, until there are five files total. This means the XE output files can take up to 2.5 GB of space on a 
				drive. This is important to note when creating a session on the C:\ drive of a customer's SQL Server, to ensure
				you don't fill the disk and bring down the server!
  
  
  Revision History:
  Date         Name             Label/PTS    Description
  ---------  ---------------  ----------  ----------------------------------------               
  02/21/2020 David Rainey                 Initial Release
********************************************************************************************************************/
set nocount on;

declare @User sysname, @DB sysname, @FileOut Nvarchar(500), @OutputType Nvarchar(100),  @sql nvarchar(max);

/* ----------------------------------------------------------------------------------------------------------------*/
/* Begin User Configuration */

/* Enter a DB name here to restirct to one DB. */
set @DB = '';

/* Enter a username here to restrict to one user.  */
set @user = '';

/* Enter the output file location. DO NOT end with a \ mark. */
set @FileOut = N'C:\temp'

/* End User Configuration */
/* ----------------------------------------------------------------------------------------------------------------*/

set @OutputType = N'File'
-- change the first half for directory and change the second half if you need to change the file name. 


--do not create event if it already exists unless we are specifically told to. 
declare @XeName sysname;

set @XEName = 'SupportTroubleshootXE_' + cast(format(getdate(), 'yyMMdd_hhmmss') as nvarchar(13))

set @FileOut = @FileOut + N'\' + @XeName + N'.xel'; 

declare @WhereConstructor nvarchar(max);

set @WhereConstructor = N'';

/* Define the WHERE once and let it be used for all event. */
set @WhereConstructor = case when @db = '' then N'
		  WHERE [sqlserver].[database_name]<>N''master'' AND [sqlserver].[database_name]<>N''tempdb'' AND [sqlserver].[database_name]<>N''model'' AND [sqlserver].[database_name]<>N''msdb''' 
	   else N'    
		  WHERE  ([sqlserver].[database_name]=N'''+ @DB +''')' 
	 end
    + case when @user = '' then N') ' 
      else N'
	      and ([sqlserver].[like_i_sql_unicode_string]([sqlserver].[username],N'''+ @User +''')))'
      end

set @SQL = N'CREATE EVENT SESSION ' +quotename(@xename) + N' ON SERVER ';


set @sql = @sql + N' 
ADD EVENT sqlserver.rpc_starting(
    ACTION(sqlserver.client_app_name,sqlserver.database_name,sqlserver.sql_text,sqlserver.username)' 
    +   @WhereConstructor +','
	  + '
ADD EVENT sqlserver.sp_statement_starting(
    ACTION(sqlserver.client_app_name,sqlserver.database_name,sqlserver.sql_text,sqlserver.username)'
     +   @WhereConstructor +','
	  + '
ADD EVENT sqlserver.sql_batch_starting(
    ACTION(sqlserver.client_app_name,sqlserver.database_name,sqlserver.sql_text,sqlserver.username)
    ' 
    +   @WhereConstructor +','
	  + '
ADD EVENT sqlserver.sql_statement_starting(
    ACTION(sqlserver.client_app_name,sqlserver.database_name,sqlserver.sql_text,sqlserver.username)
    ' 
       +   @WhereConstructor +','
	



set @sql = @sql + '
ADD EVENT sqlserver.rpc_completed (
    ACTION(sqlserver.client_app_name,sqlserver.database_name,sqlserver.sql_text,sqlserver.username)
    ' 
    +   @WhereConstructor +','
	  + '
 ADD EVENT sqlserver.sp_statement_completed (
    ACTION(sqlserver.client_app_name,sqlserver.database_name,sqlserver.sql_text,sqlserver.username)
    ' 
    +   @WhereConstructor +','
	  + '
 ADD EVENT sqlserver.sql_batch_completed (
    ACTION(sqlserver.client_app_name,sqlserver.database_name,sqlserver.sql_text,sqlserver.username)
    ' 
    +   @WhereConstructor +','
	  + '
 ADD EVENT sqlserver.sql_statement_completed (
    ACTION(sqlserver.client_app_name,sqlserver.database_name,sqlserver.sql_text,sqlserver.username)
    ' 
    +   @WhereConstructor /* Important to not there is no ending , so this must be the last event added. */

if @OutputType = 'File'
begin
	set @SQL = @SQL + N'
	   ADD TARGET package0.event_file(SET filename=N'''+ @FileOut +''',max_file_size=(512))';
end;

if @OutputType = 'Ring'
begin
	set @SQL = @SQL + N'
	   ADD TARGET package0.ring_buffer(SET max_events_limit=(2000),max_memory=(4096))';
end;


begin try
    print 'Begin: Attempt to create XE Session: '+ @Xename;
    exec sp_executesql @sql;
    print 'Success: Attempt to create XE Session:';
    print 'Begin: Attempt to Start XE Session.';
    set @Sql = N'Alter event session ' + quotename(@xename) + N' on server
    State = Start;'
    exec sp_executesql @sql;
    print 'Success: Attempt to Start XE Session.';
    print 'Look for output file(s) like: ' + replace(@FileOut, '.xel', '_*.xel');
    
end try
begin catch
     DECLARE @ErrorMessage NVARCHAR(4000);  
    DECLARE @ErrorSeverity INT;  
    DECLARE @ErrorState INT;  
  
    SELECT   
        @ErrorMessage = ERROR_MESSAGE(),  
        @ErrorSeverity = ERROR_SEVERITY(),  
        @ErrorState = ERROR_STATE();  
   
    RAISERROR (@ErrorMessage, -- Message text.  
               @ErrorSeverity, -- Severity.  
               @ErrorState -- State.  
               );  

    print 'If you see a "The system cannot find the path specified" error, then SQL Server likely cannot find the output directory.';
    print 'It may not exist or the SQL Server cannot access it. Remember that the output file is from the SQL Server''s perspective.';
    print 'Dropping the XE that was created, review the directory and rerun the script.';

    /* If there was an error like a bad File Name, just rerun the script with the correct file location. Drop the session 
    with the bad file path. */
    if exists (Select 1 from sys.server_event_sessions where name = @XeName)
    begin
	   set @sql = N' Drop Event Session ' + Quotename(@xename) + N' on server';
	   exec sp_executesql @sql;
    end;
end catch;
