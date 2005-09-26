-- $Id$
-- copyright (c) 2005 pedro martelletto <pedro@ambientworks.net>
-- all rights reserved. part of the alua project.

module("_alua.daemon.app")

_alua.daemon.app.apptable = {} -- application table

-- makes sure a process is in an application
function _alua.daemon.app.verify_proc(context, appname, reply)
	local app = _alua.daemon.app.apptable[appname]; if not app then
		reply({ name = appname, status = "error",
			error = "application does not exist" }) end
	if not context.apptable[appname] then
		app = nil; reply({ name = appname, status = "error",
				   error = "not in such application" }) end
	return app
end

-- check if an application exists
function _alua.daemon.app.query(sock, context, argument, reply)
	local name, app = argument.name, _alua.daemon.app.apptable[name]
	if not app then return reply({ name = name, status = "ok" }) end
	if not app.cache then -- keep a cache of processes and daemons
		local processes, daemons = {}, {}
		for i in pairs(app.processes) do table.insert(processes, i) end
		app.cache = { processes = processes, daemons = daemons }
		app.cache.name = name; app.cache.master = app.master
	end; app.cache.status = "ok"; reply(app.cache)
end

-- start a new application
function _alua.daemon.app.start(sock, context, argument, reply)
	local name, app = argument.name, _alua.daemon.app.apptable[name]
	if app then return reply({ name = name, status = "error",
				   error = "application already exists" }) end
	app = { master = context.id, processes = {}, name = name }
	app.processes[app.master] = sock; _alua.daemon.app.apptable[name] = app
	context.apptable[name] = app; local callback = function (s)
		app.ndaemons = 1; app.daemons = {}
		app.daemons[_alua.daemon.self.hash] = s
		reply({ name = name, status = "ok" })
	end; _alua.daemon.get(_alua.daemon.self.hash, callback)
end