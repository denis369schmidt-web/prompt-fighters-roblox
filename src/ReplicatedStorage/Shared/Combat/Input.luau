--!strict
-- One frame of controls. Players and bots produce the same Command; the server only ever sees Commands,
-- and over the network they travel as a bitmask plus the stick axis (Input.encode / Input.decode).

export type Command = {
	move: number, -- -1 .. 1
	up: boolean,
	down: boolean,
	jump: boolean, -- pressed this frame
	jumpHeld: boolean,
	standard: boolean, -- pressed this frame
	standardHeld: boolean,
	special: boolean,
	specialHeld: boolean,
	block: boolean, -- held
	grab: boolean,
	smash: boolean, -- direction + attack in one (right stick / swipe)
	drop: boolean,
}

local Input = {}

local BITS: { [string]: number } = {
	up = 1,
	down = 2,
	jump = 4,
	jumpHeld = 8,
	standard = 16,
	standardHeld = 32,
	special = 64,
	specialHeld = 128,
	block = 256,
	grab = 512,
	smash = 1024,
	drop = 2048,
}
Input.BITS = BITS

function Input.idle(): Command
	return {
		move = 0,
		up = false,
		down = false,
		jump = false,
		jumpHeld = false,
		standard = false,
		standardHeld = false,
		special = false,
		specialHeld = false,
		block = false,
		grab = false,
		smash = false,
		drop = false,
	}
end

-- Command -> (bitmask, axis in -127..127). Axis is quantised so it fits in one byte.
function Input.encode(cmd: Command): (number, number)
	local mask = 0
	for name, bit in BITS do
		if (cmd :: any)[name] then
			mask += bit
		end
	end
	return mask, math.clamp(math.round(cmd.move * 127), -127, 127)
end

-- Never trusts the client: bad types or ranges become an idle command.
function Input.decode(mask: any, axis: any): Command
	local cmd = Input.idle()
	if type(mask) ~= "number" or type(axis) ~= "number" or mask ~= mask or axis ~= axis then
		return cmd
	end
	mask = math.clamp(math.floor(mask), 0, 4095)
	for name, bit in BITS do
		(cmd :: any)[name] = bit32.btest(mask, bit)
	end
	cmd.move = math.clamp(math.floor(axis), -127, 127) / 127
	return cmd
end

return Input
