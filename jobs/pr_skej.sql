set quoted_identifier on ;
set ansi_nulls on ;
go

use [msdb] ;
go

if exists (select 1 from INFORMATION_SCHEMA.ROUTINES where [routine_schema] = 'dbo' and [routine_name] = 'pr_skej')
	drop procedure dbo.[pr_skej] ;
go

create procedure dbo.[pr_skej] (
	@empty varchar(3) = '--'
)
as
begin

set nocount, xact_abort on ;

-----------------------------------------------------------------------------------------------------------------------
-- Procedure:	pr_skej
-- Author:		Phillip Beazley (phillip@beazley.org)
-- Date:		06/05/2012
--
-- Purpose:		Creates a single page view of job schedules.
--
-- Notes:		n/a
--
-- Depends:		n/a
--
-- REVISION HISTORY ---------------------------------------------------------------------------------------------------
-- 06/05/2012	lordbeazley	Initial creation.
-----------------------------------------------------------------------------------------------------------------------

declare
	@idlePercent int,
	@idleDuration int ;

exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'IdleCPUPercent', @idlePercent output, N'no_output' ;
exec master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'IdleCPUDuration', @idleDuration output, N'no_output' ;

select
	[Server] = Convert(nvarchar(128), serverproperty('servername')),
	[Job Name] = s.[name],
	[Enabled] =
		case s.[enabled]
			when 0 then 'No'
			when 1 then 'Yes'
			else @empty
		end,
	[Schedule Name] = Coalesce(ss.[name], @empty),
	[Enabled] =
		case ss.[enabled]
			when 0 then 'No'
			when 1 then 'Yes'
			else @empty
		end,
	[Frequency] =
		case ss.[freq_type]
			when 1 then 'Once'
			when 4 then 'Daily'
			when 8 then (
				case when ss.[freq_recurrence_factor] > 1
					then 'Every ' + Convert(varchar(9), ss.[freq_recurrence_factor]) + ' Weeks'
					else 'Weekly'
				end
			)
			when 16 then (
				case when ss.[freq_recurrence_factor] > 1
					then 'Every ' + Convert(varchar(9), ss.[freq_recurrence_factor]) + ' Months'
					else 'Monthly'
				end
			)
			when 32 then 'Every ' + Convert(varchar(9), ss.[freq_recurrence_factor]) + ' Months'
			when 64 then 'SQL Startup'
			when 128 then 'SQL Idle'
			else @empty
		end,
	[Interval] =
		case
			when ss.[freq_type] = 1 then 'One time only'
			when (ss.[freq_type] = 4 and ss.[freq_interval] = 1) then 'Every Day'
			when (ss.[freq_type] = 4 and ss.[freq_interval] > 1) then 'Every ' + Convert(varchar(9), ss.[freq_interval]) + ' Days'
			when ss.[freq_type] = 8
				then (
					select
						'Weekly Schedule' = [day1] + [day2] + [day3] + [day4] + [day5] + [day6] + [day7]
					from
						(
							select
								ss.[schedule_id],
								ss.[freq_interval],
								case when ss.[freq_interval] & 1 <> 0 then 'Sun ' else '' end as [day1],
								case when ss.[freq_interval] & 2 <> 0 then 'Mon ' else '' end as [day2],
								case when ss.[freq_interval] & 4 <> 0 then 'Tue ' else '' end as [day3],
								case when ss.[freq_interval] & 8 <> 0 then 'Wed ' else '' end as [day4],
								case when ss.[freq_interval] & 16 <> 0 then 'Thu ' else '' end as [day5],
								case when ss.[freq_interval] & 32 <> 0 then 'Fri ' else '' end as [day6],
								case when ss.[freq_interval] & 64 <> 0 then 'Sat ' else '' end as [day7]
							from
								msdb.dbo.[sysschedules] [ss] with (nolock)
							where
								ss.[freq_type] = 8
						) [f]
					where
						f.[schedule_id] = sj.[schedule_id]
				)
			when ss.[freq_type] = 16
				then 'Day ' + Convert(varchar(9), ss.[freq_interval])
			when ss.[freq_type] = 32
				then (
					select
						[freq_rel] + [wday]
					from
						(
							select
								ss.[schedule_id],
								case ss.[freq_relative_interval]
									when 1 then 'First'
									when 2 then 'Second'
									when 4 then 'Third'
									when 8 then 'Fourth'
									when 16 then 'Last'
									else @empty
								end as [freq_rel],
								case ss.[freq_interval]
									when 1 then ' Sun'
									when 2 then ' Mon'
									when 3 then ' Tue'
									when 4 then ' Wed'
									when 5 then ' Thu'
									when 6 then ' Fri'
									when 7 then ' Sat'
									when 8 then ' Day'
									when 9 then ' Weekday'
									when 10 then ' Weekend'
									else @empty
								end as [wday]
							from
								msdb.dbo.[sysschedules] [ss] with (nolock)
							where
								ss.[freq_type] = 32
						) [ws]
					where
						ws.[schedule_id] = ss.[schedule_id]
				)
			when ss.[freq_type] = 64 then 'SQL Startup'
			when ss.[freq_type] = 128 then FormatMessage(14578, Coalesce(@idlePercent, 10), Coalesce(@idleDuration, 600))
			else @empty
		end,
	[Time] =
		case ss.[freq_subday_type]
			when 1 then Left(Stuff((Stuff((Replicate('0', 6 - Len(Active_Start_Time))) + Convert(varchar(6), Active_Start_Time), 3, 0, ':')), 6, 0, ':'), 8)
			when 2 then 'Every ' + Convert(varchar(10), ss.[freq_subday_interval]) + ' seconds'
			when 4 then 'Every ' + Convert(varchar(10), ss.[freq_subday_interval]) + ' minutes'
			when 8 then 'Every ' + Convert(varchar(10), ss.[freq_subday_interval]) + ' hours'
			else @empty
		end,
	[Next Run Time] =
		Coalesce(
			case sj.[next_run_date]
				when 0 then @empty
				else Convert(char(10), Convert(datetime, Convert(char(8), sj.[next_run_date])), 120)
					+ ' ' + Left(Stuff((Stuff((Replicate('0', 6 - Len(sj.[next_run_time])))
					+ Convert(varchar(6), sj.[next_run_time]), 3, 0, ':')), 6, 0, ':'), 8)
			end
		, @empty),
	[Last Run Time] =
		Coalesce((
			select top 1
				Convert(char(10), Convert(datetime, Convert(char(8), [run_date])), 120)
				+ ' ' + Left(Stuff((Stuff((Replicate('0', 6 - Len([run_time])))
				+ Convert(varchar(6), [run_time]), 3, 0, ':')), 6, 0, ':'), 8)
			from
				msdb.dbo.[sysjobhistory] with (nolock)
			where
				[job_id] = s.[job_id]
				and [step_id] = 0
			order by
				[instance_id] desc
		), @empty),
	[Last Status] =
		Coalesce((
			select top 1
				case [run_status]
					when 1 then 'SUCCESS'
					when 0 then 'FAIL'
				else
					Convert(varchar(64), [run_status])
				end
			from
				msdb.dbo.[sysjobhistory] with (nolock)
			where
				[job_id] = s.[job_id]
				and [step_id] = 0
			order by
				[instance_id] desc
		), @empty)
from
	msdb.dbo.[sysjobs] [s]
	left outer join msdb.dbo.[sysjobschedules] [sj] on s.[job_id] = sj.[job_id]
	left outer join msdb.dbo.[sysschedules] [ss] on sj.[schedule_id] = ss.[schedule_id]
order by
	s.[name] asc,
	ss.[enabled] desc,
	sj.[schedule_id] asc ;

end
go
return ;

-- EXAMPLES

exec msdb..[pr_skej] ;
