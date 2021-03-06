set quoted_identifier on ;
set ansi_nulls on ;
go

if exists (select 1 from INFORMATION_SCHEMA.ROUTINES where [routine_schema] = 'dbo' and [routine_name] = 'pr_depmap')
	drop procedure dbo.[pr_depmap] ;
go

create procedure dbo.[pr_depmap] (
	@schema nvarchar(128) = 'dbo',
	@table nvarchar(128),
	@level smallint = -1 output
)
as
begin

set nocount, xact_abort on ;

-----------------------------------------------------------------------------------------------------------------------
-- Procedure:	pr_depmap
-- Author:		Phillip Beazley (phillip@beazley.org)
-- Date:		04/30/2013
--
-- Purpose:		Provides a visual map of all tables relative to the given base.
--
-- Notes:		n/a
--
-- Depends:		n/a
--
-- REVISION HISTORY ---------------------------------------------------------------------------------------------------
-- 04/30/2013	lordbeazley	Initial creation.
-----------------------------------------------------------------------------------------------------------------------

set nocount on ;

if (not exists (select 1 from INFORMATION_SCHEMA.TABLES where [table_schema] = @schema and [table_name] = @table and [table_type] = 'BASE TABLE'))
begin
	raiserror('Base table ([%s].[%s]) does not exist.', 16, 1, @schema, @table) with nowait ;
	return ;
end

declare
	@relative nvarchar(128),
	@spacer varchar(32) = '' ;

set @level = @level + 1 ;

if (not exists (select 1 from sysforeignkeys where [rkeyid] = object_id(@table)))
begin

	-- no keys

	if (@level = 0)
		raiserror('|-0- %s', 0, 1, @table) with nowait ;
	else
	begin
		set @spacer = Space(@level * 3) ;
		raiserror('%s|-1- %s', 0, 1, @spacer, @table) with nowait ;
		return ;
	end

end
else
begin

	-- keys

	set @spacer = Space(@level * 3) ;
	if (exists (select 1 from sysforeignkeys where [rkeyid] = object_id(@table) and [rkeyid] = fkeyid))
		raiserror('%s|-3- %s', 0, 1, @spacer, @table) with nowait
	else
		raiserror('%s|-2- %s', 0, 1, @spacer, @table) with nowait ;

	-- close and deallocate cursor if it exists
	if cursor_status('local', 'fkCursor') <> -3
	begin
		if cursor_status('local', 'fkCursor') <> -1
			close fkCursor ;
		deallocate fkCursor ;
	end

	-- create list of fks
	declare fkCursor cursor local fast_forward for
	select distinct [child] = object_name([fkeyid]) from sysforeignkeys where [rkeyid] = object_id(@table) and [rkeyid] <> [fkeyid] and [keyno] = 1 order by [child] ;
	open fkCursor ;
	fetch next from fkCursor into @relative ;

	-- create fk loop
	while @@fetch_status = 0
	begin

		exec [pr_depmap] @table = @relative, @level = @level ;

		-- get next fk
		fetch next from fkCursor into @relative ;
	end

	-- close and deallocate cursor
	close fkCursor ;
	deallocate fkCursor ;

	set @level = @level - 1 ;

end

end
go
return ;

-- EXAMPLES

exec [pr_depmap] @schema = 'dbo', @table = 'item' ;
