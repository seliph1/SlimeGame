local client = {}
local cwd = (...):gsub('%.init$', '') .. "."
client.cbor = require( cwd.."cbor" )
client.state = require( cwd.."state" )
client.List = require( cwd.."list" )
client.Buffer = require( cwd.."buffer" )
client.websocket = require ( cwd .. "websocket")

require ( cwd.."cs" )

return client
