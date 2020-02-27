/*******************************************************************************************************************  
  Script Description: [LongRunningQueries]

  This script is my standard XE template for finding long running queries. It is designed to find all queries, be they
    stored proc calls, statements in a stored proc, etc, that take over five seconds to run. You can alter that default 
    threshold for you environement by altering the value of the variable @TimeInSeconds. Enter that value in seconds, and
    the template will convert that into Microseconds that XE expects. 

  This XE generally has a very low overhead. You should be able to leave this running for hours, days, weeks at a time, but
     be aware that every server is different and be sure to monitor the server for any performance issues after putting the
	XE session in place. 

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
				if you are creating this XE session in SSMS on a user's workstation, it will not create the file in that 
				user's C:\Temp directory, it will create it in the SQL Server's C:\Temp. 

				Do not end this parameter with a "\" or you will break the template. 

				The output file will start with the name of the XE session, but date and time stamped. Below is an example
				file name:
				    C:\Temp\LongRunningQueries_0_132267873224230000.xel

				If the template errs with a "The system cannot find the path specified" error, it means that SQL cannot write 
				to the directory you specified, as it may not exist or SQL lacks access. 

				This template will create files that contain up to 512 MB of data. If you fill the first file, it will create
				another, until there are five files total. This means the XE output files can take up to 2.5 GB of space on a 
				drive. This is important to note when creating a session on the C:\ drive of a customer's SQL Server, to ensure
				you don't fill the disk and bring down the server!

  By default, this Template will create the Extended Event Session and start it. Make sure to turn it off when you are done!
  
  Revision History:
  Date         Name             Label/PTS    Description
  -----------  ---------------  ----------  ----------------------------------------               
  04/03/2019    David Rainey    V 1.0       Initial Release 
  04/11/2019	 David Rainey    V 1.1       Added rcp_completed and sql_batch_completed
  08/13/2019    David Rainey    V 1.2       Added option for Ring Buffer
  02/25/2020	 David Rainey    V 1.3       Added filter options for User or Database. 
********************************************************************************************************************/

declare @FileOut Nvarchar(500);
declare @TimeInSeconds int;
Declare @OutputType varchar(100);
declare @Db sysname;
declare @User sysname;
declare @JustCreateDeployScript bit;
declare @OverrideXE bit;

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

    /* @TimeInSeconds
	   This is the threshold. A query (Be it a single statement or a stored proc call) must run for longer than this threshold to be recorded. Note that 
	    this is in seconds. The Template will take that value and convert it into the Microseconds value that XE uses. Note that this value cannot be set
	    to more than 2,147. Hopefully you don't need to monitor for a query taking longer than 35 minutes! If you do, good luck! */

set @TimeInSeconds = 5;

/* begin Output configuration */
	/* Options for @OutputType are File or Ring. 
			File - outputs to a flatfile, obviously. You need to use the @FileOut parameter to set the location of the output file. The outout
				   location must be from the SQL Server's perspective, not where you are running the query form (aka SSMS on an app server). 
			Ring - outputs to a ring buffer, meaning the data is not persisted, just captured in memory. */

set @OutputType = 'File'

    /* @FileOut
		    This is required when @OutputType is set to 'File'. Just specify which directory that SQL Server should write the output file to. Note that 
		    this is from the SQL Server's perspective. Do not end this variable with a '\'.  */
set @FileOut = 'C:\temp'; 

     /* options for @JustCreateDeployScript.
		     0 - Default. When this is zero, it will just attempt to create the XE session.
			1 - Instead of creating the XE session it will just return a script that will create 
			     a session with these settings. Note that this does not create the statement to
				turn on the XE session, you must do that manually. */

set @JustCreateDeployScript = 0

    /* Options for Override XE Session
			0 - Default. This will warn you if an XE with this name already exists and stop the script. The new XE will not be applied.
			1 - This will drop any existing XE with this name and create a new one. */

set @OverrideXE = 0;


/* End User Configuration */
/* --------------------------------------------------------------------------------------------------------------- */

set @FileOut = @FileOut + '\LongRunningQueries.xel'; 

if @OutputType not in ('File', 'Ring')
begin
	print '@OutputType is not properly configured! Must be File or Ring.';
	print 'Exiting Script early.'
	return
end;

/* Change from seconds in to microseconds */
set @TimeInSeconds = @TimeInSeconds * 1000000;

if @OverrideXE = 1
begin
    if exists(select 1 from sys.server_event_sessions
    where name = 'LongRunningQueries')
    begin
	   DROP EVENT SESSION [LongRunningQueries] ON SERVER;
    end;
end;
else 
begin
    if exists (select 1 from sys.server_event_sessions where name = 'LongRunningQueries' )
    begin
	   print 'Extended Event: [LongRunningQueries] already exists!';
	   print 'Exiting Script Early.';
	   return
    end;
end;

declare @WhereConstructor nvarchar(max);

set @WhereConstructor = N'';

set @WhereConstructor = case when @db = '' then N'
		  WHERE ([duration]>(' + Cast(@TimeInSeconds as varchar(30))+')) and [sqlserver].[database_name]<>N''master'' AND [sqlserver].[database_name]<>N''tempdb'' AND [sqlserver].[database_name]<>N''model'' AND [sqlserver].[database_name]<>N''msdb''' 
	   else N'    
		  WHERE ([duration]>(' + Cast(@TimeInSeconds as varchar(30))+')) and ([sqlserver].[database_name]=N'''+ @DB +''')' 
	 end
    + case when @user = '' then N') ' 
      else N'
	      and ([sqlserver].[like_i_sql_unicode_string]([sqlserver].[username],N'''+ @User +''')))'
      end
 declare @SQL nvarchar(max);

set @SQL = N'CREATE EVENT SESSION [LongRunningQueries] ON SERVER ';





   
    Set @SQL = N'CREATE EVENT SESSION [LongRunningQueries] ON SERVER 
    ADD EVENT sqlserver.sp_statement_completed(
	   ACTION(package0.collect_system_time,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_name,sqlserver.plan_handle,sqlserver.query_hash,sqlserver.session_id)
	   ' + @WhereConstructor + ',
    ADD EVENT sqlserver.sql_statement_completed(
	   ACTION(package0.collect_system_time,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_name,sqlserver.plan_handle,sqlserver.query_hash,sqlserver.session_id)
	    ' + @WhereConstructor + ',
     ADD EVENT sqlserver.sql_batch_completed(
	   ACTION(package0.collect_system_time,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_name,sqlserver.plan_handle,sqlserver.query_hash,sqlserver.session_id)
	    ' + @WhereConstructor + ',
     ADD EVENT sqlserver.rpc_completed(
	   ACTION(package0.collect_system_time,sqlserver.client_app_name,sqlserver.client_hostname,sqlserver.database_name,sqlserver.plan_handle,sqlserver.query_hash,sqlserver.session_id)
	    ' + @WhereConstructor;

if @OutputType = 'File'
begin
    set @SQL = @SQL + N'ADD TARGET package0.event_file(SET filename=N'''+ @FileOut +''',max_file_size=(512))';
end;

if @OutputType = 'Ring'
begin
    set @SQL = @SQL + N'ADD TARGET package0.ring_buffer(SET max_events_limit=(2000),max_memory=(4096))';
end;

set @SQL = @SQL + N'WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=ON);';

if @JustCreateDeployScript = 0
begin
    begin try
	   print 'Begin: Attempt to create XE Session: LongRunningQueries' ;
	   exec sp_executesql @sql;
	   print 'Success: Attempt to create XE Session:';

	   print 'Begin: Attempt to Start XE Session.';
	   set @Sql = N'Alter event session [LongRunningQueries] on server
	   State = Start;'
	   exec sp_executesql @sql;
	   print 'Success: Attempt to Start XE Session.';

	   print 'Look for output file(s) like: LongRunningQueries_*.xel';
	   print 'Make sure to turn the Extended Event off when you are done!'
    
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



/* Code to start the session from a query */
--ALTER EVENT SESSION [LongRunningQueries] ON SERVER  
--STATE = START;  
--GO  


/* Code to stop the session from a query */
--ALTER EVENT SESSION [LongRunningQueries] ON SERVER  
--STATE = STOP;
--GO