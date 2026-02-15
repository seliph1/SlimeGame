
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
            cs.peer = cs.host
            local event = {
                peer = cs.host,
                type = "connect",
                data = encode({
                    code = code,
                    address = address,
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

    function cs.sendTable(data)
        if not cs.peer then return end
        cs.host:sendBinary(encode(data))
    end

    function cs.sendMessage(...)
        if not cs.peer then return end
        local str = {}
	    for i = 1, select("#", ...) do
    		local v = select(i, ...)
		    v = tostring(v)
            table.insert(str, v)
        end
        cs.host:send(table.concat(str," "))
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