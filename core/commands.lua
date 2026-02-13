local serpent = require "lib.serpent"
local CONSOLE_ENV = {}
-- Small lua environment only acessible by this file
([[
_VERSION assert error    ipairs   next pairs
pcall    select tonumber tostring type unpack xpcall

coroutine.create coroutine.resume coroutine.running coroutine.status
coroutine.wrap   coroutine.yield

math.abs   math.acos math.asin  math.atan math.atan2 math.ceil
math.cos   math.cosh math.deg   math.exp  math.fmod  math.floor
math.frexp math.huge math.ldexp math.log  math.log10 math.max
math.min   math.modf math.pi    math.pow  math.rad   math.random
math.sin   math.sinh math.sqrt  math.tan  math.tanh

os.clock os.difftime os.time

string.byte string.char  string.find  string.format string.gmatch
string.gsub string.len   string.lower string.match  string.reverse
string.sub  string.upper

table.insert table.maxn table.remove table.sort
]]):gsub('%S+', function(id)
  local module, method = id:match('([^%.]+)%.([^%.]+)')
  if module then
    CONSOLE_ENV[module]         = CONSOLE_ENV[module] or {}
    CONSOLE_ENV[module][method] = _G[module][method]
  else
    CONSOLE_ENV[id] = _G[id]
  end
end)

-- Client only commands
local commands = {
	-------------------------------------------------------
	-- UI/MISC
	-------------------------------------------------------
    warning = {
        action = function(...)
			local message = table.concat({...}," ")
            local LF = require "lib.loveframes"
			local width, height = 300, 150
            local frame = LF.Create("frame"):SetSize(width, height):SetState("*"):Center()
			local panel = LF.Create("panel", frame):SetSize(width-20, height-50):SetPos(10, 30)
            local messagebox = LF.Create("messagebox", panel)
            messagebox:SetMaxWidth(width-20):SetText("©255000000"..message):Center()
        end
    };

	scale = {
		action = function(bool)
			local client = require "core.client"
			client.scale = (bool == "true")
		end;
	};

	-------------------------------------------------------
	-- DEBUG
	-------------------------------------------------------

	clear = {
		---Clear console
		action = function()
			local console = require "core.console"
			console.window:Clear()
		end;
	};


	lua = {
		---Evaluates a lua expression
		---@param ... string
		action = function(...)
			local block = table.concat({...}, " ")
			local expression, error_message = loadstring( block, "")
			local ui = require "core.interface.ui"
			local client = require "core.client"
			CONSOLE_ENV.print = print
			CONSOLE_ENV.client = client
			CONSOLE_ENV.ui = ui
			CONSOLE_ENV.msg = ui.chat_frame_server_message
			CONSOLE_ENV.dump = serpent.dump

			if expression then
				setfenv(expression, CONSOLE_ENV)
				local status, error_message = pcall(expression)
				if not status then
					print("©255000000LUA ERROR: "..error_message)
				end
			else
				print("©255000000LUA ERROR: "..error_message)
			end
		end;
	};

	print = {
		action = function(...)
			local block = table.concat({...}, " ")
			local expression, error_message = loadstring( "return ".. block)
			local ui = require "core.interface.ui"
			local console = require "core.console"
			local client = require "core.client"

			CONSOLE_ENV.client = client
			CONSOLE_ENV.ui = ui

			if expression then
				setfenv(expression, CONSOLE_ENV)
				local output = { pcall(expression) }
				if not output[1] then
					console.window:AddElement("©255000000LUA ERROR: "..output[2])
				else
					for i = 2, #output do
						local value = output[i]
						console.window:AddElement( tostring(value) )
					end
				end
			else
				console.window:AddElement("©255000000LUA ERROR: "..error_message)
			end
		end,
		syntax = "",
	};

	dump = {
		action = function(...)
			local block = table.concat({...}, " ")
			local expression, error_message = loadstring( "return ".. block)
			local ui = require "core.interface.ui"
			local console = require "core.console"
			local client = require "core.client"

			CONSOLE_ENV.client = client
			CONSOLE_ENV.ui = ui

			if expression then
				setfenv(expression, CONSOLE_ENV)
				local output = { pcall(expression) }
				if not output[1] then
					console.window:AddElement("©255000000LUA ERROR: "..output[2])
				else
					for i = 2, #output do
						local value = output[i]
						local dump = serpent.block(value, {
							nocode=true,
							comment=true,
							sortkeys=true,
						})
						console.window:AddElement(dump)
					end
				end
			else
				console.window:AddElement("©255000000LUA ERROR: "..error_message)
			end
		end,
		syntax = "",
	};

	debug = {
		---Clear console
		action = function(level)
			local client = require "core.client"
			client.debug_level = tonumber(level) or 0
		end;
	};

	utf8 = {
		action = function()
			local frases = {
				{ idioma = "Português", frase = "Você já viu o avião de João?" },
				{ idioma = "Inglês", frase = "The quick brown fox jumps over the lazy dog." },
				{ idioma = "Francês", frase = "Où est l'hôtel près du marché ?" },
				{ idioma = "Alemão", frase = "Fußgängerüberweg vor der Straße." },
				{ idioma = "Espanhol", frase = "El niño pidió piñata para su cumpleaños." },
				{ idioma = "Polonês", frase = "Źródło wód żółtych wciąż bije." },
				{ idioma = "Russo", frase = "Москва — столица России." },
				{ idioma = "Grego", frase = "Η Αθήνα είναι όμορφη πόλη." },
				{ idioma = "Árabe", frase = "اللغة العربية جميلة جدًا." },
				{ idioma = "Hebraico", frase = "השפה העברית עתיקה מאוד." },
				{ idioma = "Chinês", frase = "中文字符测试示例。" },
				{ idioma = "Japonês", frase = "日本語の文字をテストします。" },
				{ idioma = "Coreano", frase = "한국어 문자를 시험합니다." },
				{ idioma = "Tailandês", frase = "ภาษาไทยสวยงามมาก." },
			}

			for k,v in ipairs(frases) do
				print(v.idioma, v.frase)
			end
		end;
	};

	vsync = {
		---@param mode "on"|"off"|"true"|"false"
		action = function(mode)
			local width, height = love.graphics.getDimensions()
			if mode == "true" or mode == "on" then
				love.window.updateMode(width, height, {
					vsync = true;
				})
				print("vsync on")
			elseif mode == "false" or mode == "off" then
				love.window.updateMode(width, height, {
					vsync = false;
				})
				print("vsync off")
			else
				return "unknown value "..mode
			end
		end
	};

	sendrate = {
		---@param rate number
		action = function(rate)
			local client = require "core.client"
			local old_rate = client.sendRate
			local new_rate = tonumber(rate) or 35

			client.sendRate = new_rate
			return string.format(
				"Global sendRate changed from %.2f to %.2f.",
				old_rate,
				new_rate
			)
		end
	};

	get = {
		action = function(url, options)
			local thread = love.thread.newThread("core/http_thread.lua")
			if thread then
				thread:start(url, options)
			end
		end
	};

	help = {
		action = function(property, ...)
			local console = require "core.console"
			local commands = console.input.commands
		
			for name, data in pairs(commands) do
				local argNames = {}
				local action = data.action

				for i = 1, debug.getinfo(action).nparams, 1 do
					table.insert(argNames, debug.getlocal(action, i))
				end

				print(name, table.concat( argNames, ", " ))
			end
		end
	};

	-------------------------------------------------------
	-- REMOTE ACTIONS
	-------------------------------------------------------

	connect = {
		action = function(ip, port)
			local client = require "core.client"
			if not client.connected then
				ip = ip or "127.0.0.1"
				port = port or "36963"
				client.load()
				client.start(string.format("%s:%s", ip, port))
			end
		end,
		syntax = "connect <ip:port>",
	};

	disconnect = {
		action = function()
			local client = require "core.client"
			local LF = require "lib.loveframes"
			if client.connected then
				client.kick()
			end
		end,
	};

	setname = {
		action = function(...)
			local client = require "core.client"
			if client.connected then
				local name = table.concat({...}," ")
				client.send("setname "..name)
			end
		end;
	};

	say = {
		action = function(...)
			local client = require "core.client"
			local message = table.concat({...}, " ")
			client.send(string.format("say %s", message))
		end;
	};

	equip = {
		action = function(target_id, item_type)
			local client = require "core.client"
			client.send( string.format("equip %s %s", target_id, item_type) )
		end
	};

	rcon = {
		action = function(...)
			local command = table.concat({...}, " ")
			local client = require "core.client"
			client.send(string.format("rcon %s", command))
		end,
		syntax = "",
	}
}

return commands