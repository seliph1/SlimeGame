local cs = {}
-- Get the current lib path
local lib_path = (...):gsub('%.init$', '') .. "."

-- Load required libs
cs.cbor = require( lib_path.."cbor" )
cs.state = require( lib_path.."state" )
cs.List = require( lib_path.."list" )
cs.Buffer = require( lib_path.."buffer" )

-- Load the table lib helpers
local Buffer = cs.Buffer
local List = cs.List

-- Load cbor serializer
local encode = cs.cbor.encode
local decode = cs.cbor.decode

-- Set up main tables
cs.key = {}
cs.mouse = {}
cs.enabled = false
cs.sessionToken = os.time()
cs.sendRate = 30
cs.tickRate = 60
cs.packet_mean = 0
cs.packet_last = 0
cs.numChannels = 3
cs.connected = false
cs.joined = false
cs.id = nil
cs.dt = 0
cs.backgrounded = false
cs.name = "Player"
cs.version = "*"
cs.inputSequence = 0
cs.remoteInputSequence = 0
cs.requestPrediction = false
cs.inputCache = List.new()
cs.stateBuffer = List.new()
cs.lastState = nil
cs.snapshot = Buffer.new(10)
cs.stateDumpOpts = { comment = false }
cs.inputEnabled = true
cs.binds = {}

-- Load share.lua variable pointers
local state = cs.state
local share = {}
local share_local = {}
local share_lerp = {}

cs.share = share
cs.share_local = share_local
cs.share_lerp = share_lerp

local home = state.new()
home:__autoSync(true)
cs.home = home

-- Fill the table with required network procedures.
-- Usually enet or websocket
require ( lib_path .. "enet_protocol" ) (cs)

function cs.sendInput(key, act)
    if not cs.joined then return end
    local bind = cs.binds[key]
    if not (bind and cs.peer and cs.inputEnabled) then return end
    act = act or state.DIFF_NIL

    if bind.type == "stream" then
        -- Do nothing.
        -- This is handled in cs.postupdate
        return
    end

    if bind.type == "toggle" then
        -- This is handled in cs.postupdate
        -- As a "home" state change
        home[bind.input] = act
        return
    end

    if bind.type == "pulse" then
        -- Send keypresses as a one-time pulse action.
        -- Doesn't overlap with stream-like actions.
        -- Also sends keyrelease pulses
        cs.inputSequence = cs.inputSequence + 1
        local inputStream = {[bind.input] = act}
        local inputFrame = {
            inputStream = inputStream,
            seq = cs.inputSequence
        }
        -- Runs the response client-side, should we ever need that
        -- Also don't send anything if the input is confirmed to be false
        if cs.input_response then
            -- 19/10/2025: we needed that.
            if act == state.DIFF_NIL then
                cs.input_response(cs.id, {}, cs.inputSequence)
            else
                cs.input_response(cs.id, inputStream, cs.inputSequence)
            end
        end
        -- Sends input to server
        cs.sendTable(inputFrame, 1, "reliable")

        -- Stores the inputState so we can later do some cs prediction
        cs.inputCache:push(inputFrame)
    end
end

function cs.sendState(dt)
    -- Dont send any input updates if not joined.
    -- Likewise, server wont accept these inputs.
    if not cs.joined then return end

    -- Apply all of the changed states at once from the buffer in a single tick.
    if cs.stateBuffer:count() > 0 then
        for index, lastState in cs.stateBuffer:walk() do
            if cs.changing then
                cs.changing(lastState)
            end
            state.apply(share_local, lastState)
            state.apply(share, lastState)
            if cs.changed then
                cs.changed(lastState)
            end
        end
        cs.stateBuffer:clear()
    end

    -- Adds from client keypresses to the input stream table
    local inputStream
    for key, pressed in pairs(cs.key) do
        local bind = cs.binds[key]
        -- There are tree types of inputs
        -- "Stream" type input refers to a line of keys pressed at a time, continually
        if bind and bind.type == "stream" then
            inputStream = inputStream or {}
            inputStream[bind.input] = pressed
        end
    end

    -- Runs through the table and sends the input stream to server
    if cs.peer and cs.inputEnabled and inputStream then
        cs.inputSequence = cs.inputSequence + 1
        local inputState = {
            inputStream = inputStream,
            seq = cs.inputSequence
        }

        -- Runs the response client-side, should we ever need that
        if cs.input_response then
            cs.input_response(cs.id, inputStream, cs.inputSequence)
        end

        -- Sends input to server
        cs.sendTable(inputState, 1, "reliable") --print(serpent.line(inputStream))

        -- Stores the inputState so we can later do some client prediction
        cs.inputCache:push(inputState)
    end

    -- Run the tick callback
    if cs.tick then
        cs.tick(dt)
    end

    -- Send home updates to server
    if cs.peer then
        local diff = cs.home:__diff()
        if diff ~= nil then
            local homeState = {
                diff = diff,
            }
            cs.sendTable(homeState, 1, "reliable")
        end
    end
    home:__flush() -- Make sure to reset diff state after sending!
    cs.flush()
end

function cs.request_handler(event)
    local request = decode(event.data)
    if not request then return end

    --print(string.format("%sb: %s", #event.data, event.data))

   	-- SERVER/cs PACKAGE MANAGER
	----------------------------------------------------------------------------
    -- Diff / exact? (do this first so we have it in `.connect` below)
    if request.diff then
        cs.stateBuffer:push(request.diff)
        -- Remove all inputs already acknowledged from the buffer
        for index, inputState in cs.inputCache:walk() do
            if inputState.seq <= cs.remoteInputSequence then
                cs.inputCache:remove(inputState)
            end
        end
        -- The "changed" callback is done at the end of tick, for consistency
    end

    if request.exact then -- `state.apply` may return a new value
        if cs.changing then
            cs.changing(request.exact)
        end
        -- Remote
        local new = state.apply(share, request.exact)
        for k, v in pairs(new) do
            share[k] = v
        end
        for k in pairs(share) do
            if not new[k] then
                share[k] = nil
            end
        end

        if cs.changed then
            cs.changed(request.exact)
        end

        -- Local
        local new_local = state.apply(share_local, request.exact)
        for k, v in pairs(new_local) do
            share_local[k] = v
        end
        for k in pairs(share_local) do
            if not new_local[k] then
                share_local[k] = nil
            end
        end
    end

	-- SERVER/cs AUTHENTICATION
	----------------------------------------------------------------------------
    if request.id then
        -- Turn on the connected flags and assing us a ID from server
        cs.connected = true
        cs.id = request.id

        -- Run the callback function
        if cs.connect then
            cs.connect(cs.id)
        end
        print(string.format("CS: assigned player id %s from server", cs.id))

        -- Send sessionToken now that we have an id
        -- Also send credentials to the server so he knows who this cs is.
        local local_settings = {
            screen_width = love.graphics.getWidth(),
            screen_height = love.graphics.getHeight(),
            language = "English",
            language_iso = "en",
            fullscreen = love.window.getFullscreen(),
            widescreen = true,
        }

        cs.sendData({
            sessionToken = cs.sessionToken,
            name = cs.name,
            version = cs.version,
            settings = local_settings,
        })

    end

    if request.versionAck then
        -- Server acknowledged our cs version.
        -- We now send the world request
        cs.sendTable({
            dataRequest = true,
        })
    end

    if request.joinAck then
        -- Everything is ready, so we trigger the final flag and the join callback
        if cs.join then
            cs.join(cs.id)
        end
        cs.joined = true

        -- And we also send input data to server
        cs.sendTable({
            exact = home:__diff(0, true)
        }, 1, "reliable")
    end

    if request.full then
        -- Server is Full, as said by the server
        -- So, trigger some callbacks to our client.
        if cs.full then
            cs.full()
        end
    end

    -- INPUT PACKETS
	----------------------------------------------------------------------------
    if request.inputAck then
        -- Acknowledged home/input
        -- Trigger some flags on the prediction system inherited from this lib.
        cs.remoteInputSequence = request.inputAck
        cs.requestPrediction = true
    end

    -- SERVER/cs COMMS
	----------------------------------------------------------------------------
    if request.message then
        -- We received a message from server
        -- Let's translate this message and send it to whatever callback might be relevant.
        if cs.receive then
            cs.receive(unpack(request.message, 1, request.message.nArgs))
        end
    end

    if request.warning then
        -- Sever sent us a warning.
        -- Better display it to this cs.
        if cs.warning then
            cs.warning(request.warning)
        end
    end

    if request.peer_connected then
        if cs.peer_connected then
            cs.peer_connected(request.peer_connected)
        end
    end

    if request.peer_disconnected then
        if cs.peer_disconnected then
            cs.peer_disconnected(request.peer_disconnected)
        end
    end

    if request.peer_joined then
        if cs.peer_joined then
            cs.peer_joined(request.peer_joined)
        end
    end
end

function cs.connect_handler(event)
    if cs.connect_attempt then
        cs.connect_attempt()
    end
    print("CS: connection attempt")
end

function cs.disconnect_handler(event)
    cs.reset()
    if cs.disconnect then
        cs.disconnect()
    end
    print("CS: disconnected from server")
end

function cs.void(object)
    return (object == state.DIFF_NIL)
end

function cs.attribute(attribute)
    local value = home[attribute]
    if value == state.DIFF_NIL then
        return nil
    else
        return value
    end
end

cs.attr = cs.attribute
cs.DIFF_NIL = state.DIFF_NIL

return cs
