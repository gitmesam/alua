-- $Id$
-- copyright (c) 2005 pedro martelletto <pedro@ambientworks.net>
-- all rights reserved. part of the alua project.

module("_alua.daemon", package.seeall)

-- external modules
require("socket")
require("posix")

-- internal modules
require("_alua.event")
require("_alua.netio")
require("_alua.utils")
require("_alua.spawn")
require("_alua.message")

_alua.daemon.daemons = {}
_alua.daemon.ndaemons = 0
_alua.daemon.processes = {}

local idcount = 0 -- count of local processes

-- generate a new process id
function _alua.daemon.get_new_process_id()
	local id = string.format("%s:%u", _alua.daemon.self.hash, idcount)
	idcount = idcount + 1; return id
end

-- Auxiliary funcion for syncing two daemons' processes list.
local function sync_proclist(s)
  -- Get a list of local processes.
  local lprocs = {}
  for p in pairs(_alua.daemon.processes) do
    table.insert(lprocs, p)
  end
  -- Send it to the remote daemon, and get its list back.
  local reply = _alua.netio.sync(s, "sync", { procs = lprocs })
  for _, p in pairs(reply.arguments.procs) do
    if not _alua.daemon.processes[p] then
      _alua.daemon.processes[p] = s
    end
  end
end

-- Get a connection with a daemon.
function _alua.daemon.get(hash, callback)
  local s = _alua.daemon.daemons[hash]
  if s then
    -- Already connected.
    if callback then
      callback(s)
    end
    return s
  end
  local s, e = socket.connect(_alua.daemon.unhash(hash))
  local _context = { command_table = _alua.daemon.command_table }
  local _callback = { read = _alua.netio.handler }
  _alua.event.add(s, _callback, _context)
  if callback then
    -- Async.
    local f = function (reply)
      callback(s)
    end
    _alua.netio.async(s, "auth", { mode = "daemon",
      id = _alua.daemon.self.hash }, f)
  elseif not s then
    return nil, e
  else
    _alua.netio.sync(s, "auth", { mode = "daemon",
      id = _alua.daemon.self.hash })
    sync_proclist(s)
  end
  _alua.daemon.daemons[hash] = s
  _alua.daemon.ndaemons = _alua.daemon.ndaemons + 1
  return s
end

-- hash an (address, port, id) set
function _alua.daemon.hash(addr, port)
        if addr == "0.0.0.0" then addr = "127.0.0.1" end -- workaround
        return string.format("%s:%u", addr, port)
end

-- unhash a (address, port, id) set
function _alua.daemon.unhash(hash)
        local _, i_, addr, port, id = string.find(hash, "(%d.+):(%d+)")
        return addr, tonumber(port), id
end

-- Extend our network of daemons.
local function process_link(s, context, arg, reply, nof)
  local t = { daemons = {}, status = "ok" }
  for _, hash in pairs(arg.daemons or {}) do
    local s, id, e = _alua.daemon.get(hash)
    if not s then
      t.daemons[hash] = e
    else
      t.daemons[hash] = "ok"
      if not nof then
        -- Forward link request.
        if _alua.daemon.self.hash ~= hash then
          _alua.netio.async(s, "link", arg)
        end
      end
    end
  end
  for d in pairs(_alua.daemon.daemons) do
    if not t.daemons[d] then
      t.daemons[d] = "ok"
    end
  end
  reply(t)
end

-- Extend our network of daemons, request coming from a daemon.
local function daemon_link(s, context, arg, reply)
  local callback = function (s)
    process_link(s, context, arg, reply, true)
  end
  _alua.daemon.get(_alua.daemon.self.hash, callback)
end

-- Send our process list to another daemon.
local function daemon_sync(s, context, arg, reply)
  local procs = {}
  for p in pairs(_alua.daemon.processes) do
    table.insert(procs, p)
  end
  for _, p in pairs(arg.procs) do
    if not _alua.daemon.processes[p] then
      _alua.daemon.processes[p] = s
    end
  end
  reply({ procs = procs })
end

-- Authenticate a remote endpoint, either as a process or a daemon.
local function proto_auth(sock, context, argument, reply)
  context.mode = argument.mode
  if argument.mode == "process" then
    context.id = _alua.daemon.get_new_process_id()
    context.command_table = _alua.daemon.process_command_table
    _alua.daemon.processes[context.id] = sock
  end
  if argument.mode == "daemon" then
    context.id = argument.id
    context.command_table = _alua.daemon.command_table
    _alua.daemon.daemons[context.id] = sock
  end
  -- If we don't have a connection to ourselves, it's a good time to get one.
  _alua.daemon.get(_alua.daemon.self.hash, function (s)
    _alua.daemon.processes[_alua.daemon.self.hash] = s
    alua.id = _alua.daemon.self.hash
    reply({ id = context.id })
  end)
end

-- Dequeue an incoming connection, set it to a raw context.
function _alua.daemon.incoming_connection(sock, context)
        local incoming_sock, e = sock:accept()
	local commands = { ["auth"] = proto_auth }
        local callback = { read = _alua.netio.handler }
        _alua.event.add(incoming_sock, callback, { command_table = commands })
end

-- Create a new daemon, as requested by the user.
function _alua.daemon.create(user_conf)
  local sock, callback, f, e
  _alua.daemon.self = { addr = "*", port = 6080 }
  if user_conf then
    for i, v in pairs(user_conf) do
      _alua.daemon.self[i] = v
    end
  end
  sock, e = socket.bind(_alua.daemon.self.addr, _alua.daemon.self.port)
  if not sock then
    return nil, e
  end
  _alua.daemon.self.socket = sock
  _alua.daemon.self.hash = _alua.daemon.hash(sock:getsockname())
  f, e = posix.fork()
  if not f then
    return nil, e
  end -- fork() failed
  if f > 0 then
    return _alua.daemon.self.hash
  end -- parent
  callback = { read = _alua.daemon.incoming_connection }
  _alua.event.add(_alua.daemon.self.socket, callback)
  while true do
    _alua.event.loop()
    _alua.timer.poll()
  end
end

-- Connect to a daemon, as requested by the user.
function _alua.daemon.connect_process(daemon, auth_callback)
        local sock, e = socket.connect(_alua.daemon.unhash(daemon))
        if not sock then return nil, nil, e end
        local reply, e = _alua.netio.sync(sock, "auth", { mode = "process" })
        if not reply then return nil, nil, e end
        return sock, reply.arguments.id
end

-- Get information about an incoming/leaving process.
function _alua.daemon.notify(s, context, arg, reply)
  _alua.daemon.processes[arg.id] = s
end

_alua.daemon.process_command_table = {
	["link"] = process_link,
	["spawn"] = _alua.daemon.spawn.from_process,
	["message"] = _alua.daemon.message.from_process,
}

_alua.daemon.command_table = {
	["link"] = daemon_link,
	["sync"] = daemon_sync,
	["spawn"] = _alua.daemon.spawn.from_daemon,
	["notify"] = _alua.daemon.notify,
	["message"] = _alua.daemon.message.from_daemon,
}

_alua.utils.protect(_alua.daemon.process_command_table,
		    _alua.utils.invalid_command)
_alua.utils.protect(_alua.daemon.command_table,
		    _alua.utils.invalid_command)
