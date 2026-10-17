--!strict
-- Headless test runner for Lune: `lune run tests/run.luau [filter]`.
-- Finds tests/*.spec.luau and runs them with a small Jest-style API (describe / it / expect).
-- Specs see `Shared` (ReplicatedStorage.Shared as fake Instances) and a `require` that accepts it.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local Loader = require("./runtime/Loader")
local Expect = require("./runtime/Expect")

local filter = process.args[1]
local passed, failed = 0, 0
local failures = {}
local stack: { string } = {}

local function describe(name: string, body: () -> ())
	table.insert(stack, name)
	body()
	table.remove(stack)
end

local function it(name: string, body: () -> ())
	local fullName = table.concat(stack, " > ") .. " > " .. name
	if filter and not fullName:lower():find(filter:lower(), 1, true) then
		return
	end
	local ok, err = pcall(body)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, `✗ {fullName}\n    {err}`)
	end
end

local Shared = Loader.mount("src/ReplicatedStorage/Shared")

local specs = {}
for _, entry in fs.readDir("tests") do
	if entry:match("%.spec%.luau$") then
		table.insert(specs, entry)
	end
end
table.sort(specs)

for _, spec in specs do
	local path = `tests/{spec}`
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = {
			describe = describe,
			it = it,
			expect = Expect.expect,
			Shared = Shared,
			require = Loader.require,
		},
	})
	local ok, err = pcall(chunk)
	if not ok then
		failed += 1
		table.insert(failures, `✗ {spec} failed to load\n    {err}`)
	end
end

for _, line in failures do
	print(line)
end
print(`\n{passed} passed, {failed} failed ({#specs} spec files)`)
process.exit(if failed == 0 then 0 else 1)
