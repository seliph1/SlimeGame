
return function(cs)
    -- Start module
    local websocket = require(cs.lib_path .. "websocket")
    cs.host = nil
    cs.peer = nil

    -- Load cbor serializer
    local encode = cs.cbor.encode
    local decode = cs.cbor.decode
    --local serpent = require "lib.serpent"

    function cs.start(address)
        if cs.reset then
            cs.reset()
        end

        address = address or '127.0.0.1:36963'
        local ip, port = string.match(address, "(%d+%.%d+%.%d+%.%d+):(%d+)")
        cs.host = websocket.new(ip, port)
        print("CS: client peer started ("..address..")")
        print("CS: attempting connection to: "..address)

        -- Create callbacks
        function cs.host:onconnect(code)
            local event = {
                peer = cs.host,
                type = "connect",
                data = encode({
                    code = code,
                })
            }
            cs.connect_handler(event)
        end

        function cs.host:ondisconnect(code, reason)
            local event = {
                peer = cs.host,
                type = "disconnect",
                data = encode({
                    code = code,
                    reason = reason,
                })
            }
            cs.disconnect_handler(event)
            print("CS: close code "..code..", reason: "..reason)
        end

        function cs.host:onmessage(message)
            local event = {
                peer = cs.host,
                type = "receive",
                data = message,
            }
            cs.request_handler(event)
        end

        function cs.host:onerror(e)
            print(e)
        end
    end


    function cs.reset()
        if cs.resetflags then
            cs.resetflags()
        end
        cs.host = nil
        cs.peer = nil
    end

    function cs.sendExt(channel, flag, ...)
        if not cs.peer then return end
        cs.host:send(encode({
            message = { nArgs = select('#', ...), ... },
        }), channel, flag)
    end

    function cs.sendTable(data, channel, flag)
        if not cs.peer then return end
        cs.host:send(encode(data), channel, flag)
    end

    function cs.send(...)
        cs.sendExt(nil, nil, ...)
    end

    function cs.kick()
        assert(cs.peer, 'client is not connected'):disconnect()
        --cs.host:flush()
    end

    function cs.getPing()
        if cs.peer then
            return math.random(100)
        else
            return 0
        end
    end

    function cs.getHost()
        return cs.host
    end

    function cs.getPeer()
        return cs.peer
    end

    function cs.preupdate(dt)
        if not cs.host then return end
        cs.host:update()
    end

    local accumulator = 0
    function cs.postupdate(dt)
        accumulator = accumulator + dt
        local tickStep = 1 / cs.sendRate
        while accumulator >= tickStep do
            cs.sendState(tickStep)
            accumulator = accumulator - tickStep
        end
    end

    function cs.flush()
    end
    -- End module
end

-- Server
--[[
package.preload["socket"] = function()end
local ws = require"websocket"
local client = {
    socket = {},
    _buffer = "",
    _length = 2,
    _head = nil,
}
local res, head, err
local function receive(t)
    return function(_, n)
        if #t>0 then
            local ret = t[1]
            if n<#ret then
                ret, t[1] = ret:sub(1,n), ret:sub(n+1)
            else
                table.remove(t, 1)
            end
            return ret, nil, nil
        else
            return nil, "timeout", nil
        end
    end
end

--空消息
client.socket.receive = receive{"\x81", "\x00"}
res, head, err = ws.read(client)
assert(res==nil and head==nil and err=="buffer length less than 2")
res, head, err = ws.read(client)
assert(res=="" and head==0x81 and err==nil)

--1字节消息
client.socket.receive = receive{"\x81\x01"}
res, head, err = ws.read(client)
assert(res==nil and head==nil and err==nil)
client.socket.receive = receive{"\x31"}
res, head, err = ws.read(client)
assert(res=="1" and head==0x81 and err==nil)

--5字节消息
client.socket.receive = receive{"\x81\x05", "12", "345"}
res, head, err = ws.read(client)
assert(res==nil and head==nil and err=="buffer length less than 5")
res, head, err = ws.read(client)
assert(res=="12345" and head==0x81 and err==nil)

--200字节消息
local s = "" for i=1,100 do s=s..i%5 end
client.socket.receive = receive{"\x81\x7e", "\x00", "\xc8", s, s}
res, head, err = ws.read(client)
assert(res==nil and head==nil and err=="buffer length less than 4")
res, head, err = ws.read(client)
assert(res==nil and head==nil and err=="buffer length less than 200")
res, head, err = ws.read(client)
assert(res==s..s and head==0x81 and err==nil)

print(ws.read(client))
]]