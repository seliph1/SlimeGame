---@diagnostic disable: duplicate-set-field, undefined-field

local program_mode = ""
local initializer = {
	debug = function()
		-- VS Code debugger
		local lldebugger = require "lldebugger"
		if lldebugger then
			lldebugger.start()
		end
	end,

	server = function()
		program_mode = "server"
	end,

	client = function()
		program_mode = "client"
	end,
}
local arguments = love.arg.parseGameArguments(arg)
if arguments and type(arguments) == "table" then
	for index, argument in pairs(arguments) do
		if initializer[argument] then
			initializer[argument]()
		end
	end
end

if program_mode == "server" then
	local server = require "server"
	return
elseif program_mode == "client" then
end

--------------------------------------------------------------------

require "legacy"
local loveframes = require "lib.loveframes"
local console = require "core.console"
local sti = require "lib.sti"
local client = require "core.client"

function love.load()
	love.keyboard.setTextInput(true)
end

function love.update( dt )
	client.update( dt )
	loveframes.update(dt)
end

function love.draw()
	client.draw()
	loveframes.draw()
end

function love.mousepressed(x, y, button, istouch, presses)
	loveframes.mousepressed(x, y, button, istouch, presses)
	if loveframes.GetInputObject() == false and loveframes.GetCollisionCount() < 1 then
		client.mousepressed()
	end
end

function love.mousereleased(x, y, button, istouch, presses)
	loveframes.mousereleased(x, y, button, istouch, presses)
	client.mousereleased()
end

function love.mousemoved(x, y, dx, dy, istouch)
	loveframes.mousemoved(x, y, dx, dy, istouch)
	client.mousemoved()
end

function love.wheelmoved(x, y)
	loveframes.wheelmoved(x, y)
	client.wheelmoved()
end

function love.keypressed(key, unicode)
	loveframes.keypressed(key, unicode)
	if not loveframes.GetInputObject() then
		client.keypressed()
	end
end

function love.keyreleased(key, unicode)
	loveframes.keyreleased(key)
	client.keyreleased()
end

function love.textinput(text)
	loveframes.textinput(text)
end