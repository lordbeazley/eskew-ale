declare	@table sysname = null ;

select top 100 percent with ties
	[table] = t.[name],
	[trigger] = tr.[name],
	[status] = case when 1 = ObjectProperty(tr.[id], 'ExecIsTriggerDisabled') then 'Disabled' else 'Enabled' end
from
	sysobjects [t]
	inner join sysobjects [tr] on t.[id] = tr.[parent_obj]
		and (t.[xtype] in ('U', 'V'))
		and (tr.[xtype] = 'TR')
--		and (@table is null or t.[name] like @table)
		and t.[name] = Coalesce(@table, t.[name])
order by
	t.[name] asc,
	tr.[name] asc ;
go
