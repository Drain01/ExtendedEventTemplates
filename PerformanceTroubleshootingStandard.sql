/*******************************************************************************************************************  
  Script Description: [PerformanceTroubleshootingStandard]

  This script is my standard troubleshooting Extended Event (XE) template. It is designed to assist with performance 
    troubleshooting. The intended use is to create the session, start the session, execute the problematic query
    or app process, stop the session, then review the data. 

  This Template should work on SQL Server 2012 or higher, unless Microsoft changes the syntax again in future builds.
    Last tested version: SQL Server 2019. 

  If you have never used an XE before, do not be overwhelmed! Focus on these three variables and leave the others 
    on their default values: 

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

  By default, this Template will create the Extended Event Session and start it. Make sure to turn it off when you are done!
  
  Revision History:
  Date       Name             Label   Description
  ---------  ---------------  ----------  ----------------------------------------               
  01/16/2020 David Rainey                 Initial Release
********************************************************************************************************************/
declare @User sysname, @DB sysname, @FileOut Nvarchar(500), @OutputType varchar(100), @ShowStarting bit, @sql nvarchar(max)
, @EnableCausality bit, @OverrideXE bit, @StartSession bit, @ShowErrors bit, @JustCreateDeployScript bit;

/* --------------------------------------------------------------------------------------------------------------- */
/* Begin User Configuration */

    /* Options for @DB 
		  This parameter is blank by default, which means that the XE will record transactions for ALL databases (Well, I say all, but it filters out the 
		   system DBs: master, model, msdb, tempdb). However, if you type in a DB ID for this variable, it will filter to just that database. NOTE - This 
		   does not allow for multiple DBs at this time. */

set @DB = '';

    /* Options for @User
	   This parameter is blank by default. When it is blank, it will gather activity for ALL users, which isn't recommended on a busy production server. 
	    If you enter a user name here, it will filter to just that user name. NOTE - This does not allow for multiple users at this time. */

set @user = '';

	/* Options for @OutputType are File or Ring. 
			File - Default. Outputs to a flatfile, obviously. You need to use the @FileOut parameter to set the location of the output file. The outout
				   location must be from the SQL Server's perspective, not where you are running the query form (aka SSMS on an app server). Note that 
				   if you write to an output file, it will write up to 5 five each of which has a max size of 512 MBs. So, make sure to account for up 
				   to 2.5 GBs of space in the directory you write to. 
			Ring - outputs to a ring buffer, meaning the data is not persisted, just captured in memory.*/

set @OutputType = 'File';

    /* @FileOut
		    This is required when @OutputType is set to 'File'. Just specify which directory that SQL Server should write the output file to. Note that 
		    this is from the SQL Server's perspective. Do not end this variable with a '\'.  */
set @FileOut = 'C:\temp'; 

    /* Options for Override XE Session
			0 - Default. This will warn you if an XE with this name already exists and stop the script. The new XE will not be applied.
			1 - This will drop any existing XE with this name and create a new one. */

set @OverrideXE = 0;

    /* Options for Show Errors.
			0 - Default. The Extended Event will not show errors. 
			1 - The Extended Event will show any errors above severity 10. Errors will be restricted with the same 
				    @user or @DB restrictions, if any exist. */

set @ShowErrors = 0;

    /*Options for @ShowStarting
	   1 - Default. Show all Starting event (ex: rpc_starting). This allows you to see if a statement started but did not complete.
	   0 - Only show completed events. This results in less clutter.  */
	   
set @ShowStarting = 1;

    /* Options for Causality Tracking.
			 0 - Default. Causility Tracking is off.
			 1 - Turn on Causility Tracking. This assigns a GUID to each task (Like an INSERT) and shows all event associated with that task and the sequence in which
			      those events are applied. This can help you isolate a specific task. This adds MAJOR overhead to an XE session, so please be aware before you turn this on!
				    more info: https://www.scarydba.com/2020/01/13/causality-tracking-in-extended-events/ */

set @EnableCausality = 0;

    /* Options for Start Session
		    0 - This will create the XE but will not start it, you need to manually start it. 
		    1 - Default. This will attempt to start the XE session after creating it. */

set @StartSession = 1;

     /* options for @JustCreateDeployScript.
		     0 - Default. When this is zero, it will just attempt to create the XE session.
			1 - Instead of creating the XE session it will just return a script that will create 
			     a session with these settings. */

set @JustCreateDeployScript = 0



/* End User Configuration */
/* --------------------------------------------------------------------------------------------------------------- */
set @FileOut = @FileOut + '\PerformanceTroubleshootingStandard.xel'; 


--do not create event if it already exists unless we are specifically told to. 
if @OverrideXE = 0
begin
    if exists(select 1 from sys.server_event_sessions
    where name = 'PerformanceTroubleshootingStandard')
    begin
	   select 'Extended Event: [PerformanceTroubleshootingStandard] already exists!';
	   select 'Exiting Script Early.';
	   return
    end;
end;

if @OverrideXE = 1
begin
    if exists(select 1 from sys.server_event_sessions
    where name = 'PerformanceTroubleshootingStandard')
    begin
	   DROP EVENT SESSION [PerformanceTroubleshootingStandard] ON SERVER;
    end;
end;

declare @WhereConstructor nvarchar(max);

set @WhereConstructor = N'';

/* Where clause will be the same for most events (EXCEPT errors), so construct it first here. Note that you need to manually add
a , mark after each event, EXCEPT for the last one. It was easier to do that then create a process to remove the comma
from the last call to this @WhereConstructor. */
set @WhereConstructor = case when @db = '' then N'
		  WHERE [sqlserver].[database_name]<>N''master'' AND [sqlserver].[database_name]<>N''tempdb'' AND [sqlserver].[database_name]<>N''model'' AND [sqlserver].[database_name]<>N''msdb''' 
	   else N'    
		  WHERE  ([sqlserver].[database_name]=N'''+ @DB +''')' 
	 end
    + case when @user = '' then N') ' 
      else N'
	      and ([sqlserver].[like_i_sql_unicode_string]([sqlserver].[username],N'''+ @User +''')))'
      end

set @SQL = N'CREATE EVENT SESSION [PerformanceTroubleshootingStandard] ON SERVER ';

if @ShowStarting = 1
begin
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
	
end;

if @ShowErrors = 1
begin
    set @sql = @sql + N' ADD EVENT sqlserver.error_reported( 
	ACTION(sqlserver.client_app_name, sqlserver.client_hostname,  
		sqlserver.database_name, sqlserver.sql_text, sqlserver.username)
		WHERE ([package0].[greater_than_int64]([severity], (10))) '
	   /* Custom WHERE clause here to also include the severity. Maybe I should make a function
	   to handle the generation of the WHERE clause? Eh, sounds like a lot of work and defeats the 
	   purpose of an easy to deploy template. */
        +  case when @db = '' then N'
		  and [sqlserver].[database_name]<>N''master'' AND [sqlserver].[database_name]<>N''tempdb'' AND [sqlserver].[database_name]<>N''model'' AND [sqlserver].[database_name]<>N''msdb''' 
	   else N'    
		  and  ([sqlserver].[database_name]=N'''+ @DB +''')' 
	 end
    + case when @user = '' then N') ' 
      else N'
	      and ([sqlserver].[like_i_sql_unicode_string]([sqlserver].[username],N'''+ @User +''')))'
      end +','
end;

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
    +   @WhereConstructor /* Important, end with no ,*/

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

if @EnableCausality = 1
begin
    set @sql = @sql + N'
	   WITH (TRACK_CAUSALITY = ON);';
end;

--select @sql 
if @JustCreateDeployScript = 0
begin
    begin try
	   print 'Begin: Attempt to create XE Session: PerformanceTroubleshootingStandard' ;
	   exec sp_executesql @sql;
	   print 'Success: Attempt to create XE Session:';

	   if @StartSession = 1 and @JustCreateDeployScript = 0
	   begin
		  print 'Begin: Attempt to Start XE Session.';
		  set @Sql = N'Alter event session [PerformanceTroubleshootingStandard] on server
		  State = Start;'
		  exec sp_executesql @sql;
		  print 'Success: Attempt to Start XE Session.';
		  print 'Look for output file(s) like: PerformanceTroubleshootingStandard_*.xel';
		  print 'Make sure to turn the Extended Event off when you are done!'
	   end;
    
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

    print ''
    print 'If you see a "The system cannot find the path specified" error, then SQL Server likely cannot find the output directory.';
    print 'It may not exist or the SQL Server cannot access it. Remember that the output file is from the SQL Server''s perspective.';
    print 'Dropping the XE that was created, review the directory and rerun the script.';
    print ''

    /* If there was an error like a bad File Name, just rerun the script with the correct file location. Drop the session 
    with the bad file path. */
    if exists (Select 1 from sys.server_event_sessions where name = 'PerformanceTroubleshootingStandard')
    begin
	   set @sql = N' Drop Event Session [PerformanceTroubleshootingStandard] on server';
	   exec sp_executesql @sql;
    end;
end catch;
end;

if @JustCreateDeployScript = 1
begin
    select @sql;
end;

 --below is code to start / stop the event in a SQL job if needed. 
--start extended event
--alter event session [PerformanceTroubleshootingStandard] on server
--STATE = START;
--go

----stop the event. 
--alter event session [PerformanceTroubleshootingStandard] on server
--STATE = STOP;
--go
