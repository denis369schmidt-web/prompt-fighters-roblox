--!strict
-- Loads Roblox-style ModuleScripts under Lune without Roblox Studio.
-- A source folder is exposed as a tree of fake Instances that follows Rojo's file mapping:
--   Foo.luau -> ModuleScript "Foo", Foo/ -> Folder "Foo", Foo/init.luau -> ModuleScript "Foo" with children.
-- Each module gets its own `script`, and `require(instance)` loads the file behind it (cached), so game code
-- keeps the normal `require(script.Parent.X)` style and runs unchanged in tests.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")

local Loader = {}

-- A headless place for world-building modules (World/ArenaBuilder, World/LobbyBuilder): real Lune Instances for
-- Workspace and Lighting, and ReplicatedStorage resolving to the mounted Shared folder.
local place = roblox.Instance.new("DataModel")
local services: { [string]: any } = {}
Loader.workspace = place:GetService("Workspace")
Loader.game = {
	GetService = function(_, name: string): any
		return services[name] or place:GetService(name)
	end,
}

-- Roblox's Random, which Lune does not ship.
local RandomShim = {}
RandomShim.__index = RandomShim
function RandomShim.new(seed: number?)
	local state = math.floor(seed or 1) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return setmetatable({ state = state }, RandomShim)
end
function RandomShim:NextNumber(lo: number?, hi: number?): number
	self.state = (self.state * 16807) % 2147483647
	local t = self.state / 2147483647
	return (lo or 0) + ((hi or 1) - (lo or 0)) * t
end
function RandomShim:NextInteger(lo: number, hi: number): number
	return lo + math.floor(self:NextNumber() * (hi - lo + 1))
end

-- Coroutine helpers are no-ops: world builders only use them for ambient loops (lightning).
local taskStub = {
	spawn = function() end,
	delay = function() end,
	defer = function() end,
	wait = function()
		return 0
	end,
}

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
		environment = {
			script = target,
			require = requireNode,
			-- Roblox datatypes from Lune, so instance-building modules (e.g. Visual/RigBuilder) run headless.
			Instance = roblox.Instance,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			Enum = roblox.Enum,
			Vector2 = roblox.Vector2,
			UDim = roblox.UDim,
			UDim2 = roblox.UDim2,
			NumberRange = roblox.NumberRange,
			NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
			Random = RandomShim,
			game = Loader.game,
			workspace = Loader.workspace,
			task = taskStub,
		},
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

-- Makes game:GetService(name) return `value` (e.g. ReplicatedStorage -> { Shared = mounted folder }).
function Loader.provide(name: string, value: any)
	services[name] = value
end

Loader.require = requireNode

return Loader
