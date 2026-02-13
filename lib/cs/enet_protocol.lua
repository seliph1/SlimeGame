return function(cs)
    -- Start module
    local enet = require "enet"
    local useCompression = true
    function cs.disableCompression()
        useCompression = false
    end
    cs.host = nil
    cs.peer = nil

    -- Load cbor serializer
    local encode = cs.cbor.encode
    local decode = cs.cbor.decode

    function cs.start(address)
        cs.reset()

        address = address or '127.0.0.1:36963'
        cs.host = enet.host_create()
        if useCompression then
             cs.host:compress_with_range_coder()
        end
        print("CS: client peer started ("..tostring( cs.host)..")")
        print("CS: attempting connection to: "..address)
        cs.host:connect(address, cs.numChannels)
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
        cs.peer:send(encode({
            message = { nArgs = select('#', ...), ... },
        }), channel, flag)
    end

    function cs.sendTable(data, channel, flag)
        if not cs.peer then return end
        cs.peer:send(encode(data), channel, flag)
    end

    function cs.send(...)
        cs.sendExt(nil, nil, ...)
    end

    function cs.kick()
        assert(cs.peer, 'client is not connected'):disconnect()
        cs.host:flush()
    end

    function cs.getPing()
        if cs.peer then
            return cs.peer:round_trip_time()
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
        -- Process network events
        if not cs.host then return end
        -- Service Loop
        while true do
            if not cs.host then break end
            local event = cs.host:service(0)
            if not event then break end

            -- Connected with server?
            if event.type == 'connect' then
                cs.peer = event.peer
                -- Ignore this, wait till we receive id (see below)
                cs.connect_handler(event)
            end

            -- Disconnected from server?
            if event.type == 'disconnect' then
                cs.disconnect_handler(event)
            end

            -- Received a request?
            if event.type == 'receive' then
                cs.request_handler(event)
            end
        end

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
        if cs.host then
            cs.host:flush() -- Tell ENet to send outgoing messages
        end
    end
    -- End module
end