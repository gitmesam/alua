-- Copyright (c) 2005 Lab//, PUC-Rio
-- All rights reserved.

-- This file is part of ALua. As a consequence, to every excerpt of code
-- hereby obtained, the respective project's licence applies. Detailed
-- information regarding ALua's licence can be found in the LICENCE file.

-- Miscellanea. Stuff that really doesn't belong anywhere else.
module("utils")

-- Auxiliary function used to dump a Lua object.
function
dump(obj)
	-- If the object is a table, dump it recursively.
	if type(obj) == "table" then
		local i, v = next(obj)
		-- If the table is empty, cheat.
		if not i then return "{}" end
		local buf = "{ "
		while i do
			-- If the element index is a string, print it.
			if type(i) == "string" then
				buf = buf .. [[["]] .. i .. [["] = ]]
			end
			buf = buf .. dump(v)
			i, v = next(obj, i)
			-- If there's a next object, comma-separate it.
			if i then buf = buf .. ", " end
		end
		return buf .. " }"
	end

	-- If it's a string, then scape it.
	if type(obj) == "string" then return string.format("%q", obj) end

	-- Numbers, booleans, userdata (unlikely), etc. go here.
	return tostring(obj)
end

-- Print information about a bogus packet.
function
bogus(sock, command, body)
	print(alua.id .. ": Bogus packet received from daemon")
	print(alua.id .. ": Discarding packet...")
end

-- Hash an (address, port, id) set.
function
hash(addr, port, id)
	-- We have to work-around a corner case here. The hash is supposed to
	-- contain valid addresses, that is, addresses that are ready to be
	-- used by socket.connect(). Unfortunately, "0.0.0.0", returned by
	-- socket.getsockname() for local sockets, isn't one of them.
	if addr == "0.0.0.0" then addr = "127.0.0.1" end
	local hash = string.format("%s:%u", addr, port)
	if id then hash = hash .. ":" .. id end
        return hash
end

-- Produce a (address, port, id) set out of hash.
function
unhash(hash)
	local _, i_, addr, port, id = string.find(hash, "(%d.+):(%d+)")
	return addr, tonumber(port), id
end
