--!strict
-- Minimal Jest-compatible matchers, so specs can move to Jest-Lua later without rewrites.

local Expect = {}

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function show(value: any): string
	if type(value) == "string" then
		return `"{value}"`
	end
	return tostring(value)
end

function Expect.expect(actual: any)
	local function make(negate: boolean)
		local m = {}
		local function check(ok: boolean, message: string)
			if ok == negate then
				error((if negate then "not: " else "") .. message, 3)
			end
		end
		function m.toBe(expected: any)
			check(actual == expected, `expected {show(actual)} to be {show(expected)}`)
		end
		function m.toEqual(expected: any)
			check(deepEqual(actual, expected), `expected tables to be deeply equal`)
		end
		function m.toBeCloseTo(expected: number, digits: number?)
			local tolerance = 10 ^ -(digits or 2) / 2
			check(math.abs(actual - expected) < tolerance, `expected {actual} to be close to {expected}`)
		end
		function m.toBeTruthy()
			check(not not actual, `expected {show(actual)} to be truthy`)
		end
		function m.toBeNil()
			check(actual == nil, `expected {show(actual)} to be nil`)
		end
		function m.toBeGreaterThan(n: number)
			check(actual > n, `expected {actual} > {n}`)
		end
		function m.toBeGreaterThanOrEqual(n: number)
			check(actual >= n, `expected {actual} >= {n}`)
		end
		function m.toBeLessThan(n: number)
			check(actual < n, `expected {actual} < {n}`)
		end
		function m.toBeLessThanOrEqual(n: number)
			check(actual <= n, `expected {actual} <= {n}`)
		end
		function m.toHaveLength(n: number)
			check(#actual == n, `expected length {#actual} to be {n}`)
		end
		function m.toThrow()
			local ok = pcall(actual)
			check(not ok, "expected function to throw")
		end
		return m
	end
	local matchers = make(false)
	matchers.never = make(true)
	return matchers
end

return Expect
