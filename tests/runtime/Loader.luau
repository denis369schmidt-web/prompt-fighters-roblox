--!strict
-- Loads Roblox-style ModuleScripts under Lune without Roblox Studio.
-- A source folder is exposed as a tree of fake Instances that follows Rojo's file mapping:
--   Foo.luau -> ModuleScript "Foo", Foo/ -> Folder "Foo", Foo/init.luau -> ModuleScript "Foo" with children.
-- Each module gets its own `script`, and `require(instance)` loads the file behind it (cached), so game code
-- keeps the normal `require(script.Parent.X)` style and runs unchanged in tests.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Loader = {}

local cache: { [string]: any } = {}
-- Lune's fs calls yield, and metamethods cannot yield, so the tree is scanned once up front.
local dirs: { [string]: { string } } = {}
local files: { [string]: boolean } = {}

local function scan(path: string)
	local entries = fs.readDir(path)
	table.sort(entries)
	dirs[path] = entries
	for _, entry in entries do
		local full = `{path}/{entry}`
		if fs.isDir(full) then
			scan(full)
		else
			files[full] = true
		end
	end
end
local loading: { [string]: boolean } = {}
local nodes: { [string]: any } = {}

local function basename(path: string): string
	return path:match("([^/]+)$") or path
end

local function dirname(path: string): string
	return path:match("^(.*)/[^/]+$") or "."
end

local node
local requireNode

local function childOf(parent: any, name: string): any?
	local dir = rawget(parent, "__dir")
	if not dir then
		return nil
	end
	local sub = `{dir}/{name}`
	if dirs[sub] then
		return node(sub)
	end
	for _, ext in { ".luau", ".lua" } do
		if files[sub .. ext] then
			return node(sub .. ext)
		end
	end
	return nil
end

-- path: a directory or a module file. `root` marks the top of the tree (its Parent is nil).
function node(path: string, root: boolean?): any
	if nodes[path] then
		return nodes[path]
	end
	local isDir = dirs[path] ~= nil
	local name = if isDir then basename(path) else (basename(path):gsub("%.luau?$", ""))
	local self = { Name = name, __dir = if isDir then path else nil, __root = root == true }
	if isDir then
		for _, ext in { "init.luau", "init.lua" } do
			if files[`{path}/{ext}`] then
				self.__file = `{path}/{ext}`
			end
		end
	else
		self.__file = path
	end
	self.ClassName = if self.__file then "ModuleScript" else "Folder"
	nodes[path] = setmetatable(self, {
		__index = function(t: any, key: string)
			if key == "Parent" then
				if rawget(t, "__root") then
					return nil
				end
				return node(dirname(path))
			elseif key == "FindFirstChild" then
				return function(inst: any, childName: string)
					return childOf(inst, childName)
				end
			elseif key == "WaitForChild" then
				return function(inst: any, childName: string)
					return assert(childOf(inst, childName), `{childName} is not a child of {path}`)
				end
			elseif key == "GetChildren" then
				return function(inst: any)
					local result = {}
					for _, entry in dirs[path] do
						if not entry:match("^init%.luau?$") then
							local child = childOf(inst, (entry:gsub("%.luau?$", "")))
							if child then
								table.insert(result, child)
							end
						end
					end
					return result
				end
			end
			local child = childOf(t, key)
			if child == nil then
				error(`{key} is not a valid member of {path}`, 2)
			end
			return child
		end,
		__tostring = function()
			return path
		end,
	})
	return nodes[path]
end

function requireNode(target: any): any
	if type(target) == "string" then
		return require(target)
	end
	local file = rawget(target, "__file")
	assert(file, `cannot require {tostring(target)}: not a ModuleScript`)
	if cache[file] ~= nil then
		return cache[file]
	end
	assert(not loading[file], `cyclic require of {file}`)
	loading[file] = true
	local chunk = luau.load(fs.readFile(file), {
		debugName = file,
		environment = { script = target, require = requireNode },
	})
	local result = chunk()
	loading[file] = nil
	cache[file] = result
	return result
end

-- Returns the fake Instance for a source folder, e.g. Loader.mount("src/ReplicatedStorage/Shared").
function Loader.mount(path: string): any
	scan(path)
	return node(path, true)
end

Loader.require = requireNode

return Loader
