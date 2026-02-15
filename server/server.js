/**
 * @usage
 * $ node server.js
 * 
 * @license
 * MIT
 * 
 * @authors
 * Gabriel Mendes
 */

console.log("******** SlimeGame Dedicated Server ********")

const state = require ("./state.js")
const cbor = require ("./cbor")
const encode = cbor.encode
const decode = cbor.decode

var initial = { Hello: "World" };
var encoded = encode(initial);
var decoded = decode(encoded);

const MAX_CLIENTS = 64
const SEND_RATE = 35
const ADDRESS = "*"
const PORT = 36963

let server = {
    "enabled": true,
    "maxClients": MAX_CLIENTS,
    "sendRate": SEND_RATE,
    "isAcceptingClients": true,
    "numChannels": 3,
    "log_level": 1,
    "started": false,
    "backgrounded": false,
    "version": "*",
    "clock": 0,
    "dt": 0,
    "stateDumpOpts": {"comment": false},
}

// State object
let share = state.new()
share.__autoSync(true)
server.share = share

// Home data holding
let homes = {}
server.homes = homes

// Server data
let peerToId = []
let idToPeer = []
let idToSession = []
let idToSessionToken = []
let idToSessionIdentity = []
let idToSettings = []
let nextId = 1
let numClients = 0
let useCompression = false

// Initialize websocket with above settings
const WebSocket = require("ws");
const WebSocketServer = WebSocket.WebSocketServer
const wss = new WebSocketServer({
    port: PORT,
    perMessageDeflate: useCompression,
});
console.log("WebSocket server started on address: " + ADDRESS + ":" + PORT)

function disableCompression(disable) {
    wss.perMessageDeflate = disable
    useCompression = false
}

function formatDate(date) {
  var hours = date.getHours();
  var minutes = date.getMinutes();
  var seconds = date.getSeconds();
  minutes = minutes < 10 ? '0'+minutes : minutes;
  seconds = seconds < 10 ? '0'+seconds : seconds;
  var strTime = hours + ':' + minutes + ":" + seconds;
  return strTime;
}


function prefixFilter(t) {
    for (const [key, value] of Object.entries(t)) {
        if (key.match("^_[^_]")) {
            delete t[key]
        }
        if (typeof value == "object") {
            prefixFilter(value)
        }
    }
}


function utf8(arrayBuffer) {
    return Buffer.from(arrayBuffer).toString('utf-8');
}

function log(level, ...args) {
    let separator = " | "
    let date = formatDate(new Date())
	let str = [
        date,
        args.join(separator)
    ]
	if (level >= server.log_level) {
		console.log(str.join(separator))
    }
}

function send(client, data) {
    client.send(encode(data))
}

function broadcast(data, isBinary) {
    wss.clients.forEach(function each(client) {
        if (client.readyState === WebSocket.OPEN) {
            client.send( encode(data), {binary: isBinary} )
        }
    })
}

wss.on('connection', function connection(client, request) {
    const remoteAddress = client._socket.remoteAddress;
    const remotePort = client._socket.remotePort;

    client.binaryType = "arraybuffer"
    client.on('error', console.error);
    client.on("message", requestHandler)
    client.on("close", disconnectHandler)

    // Assign an ID to this peer
    let peer = client
    if (numClients < server.maxClients) {
        // I dont know how to make this lua-like, so we will be using 
        // 0 indexed "tables" to achieve the same thing
        let peer_id = idToPeer.length
        peerToId[peer] = peer_id
        idToPeer[peer_id] = peer
        homes[peer_id] = {}
        numClients = numClients + 1

        connectCallback(peer_id)

        send(client, {
            "id": peer_id
        })
        
        broadcast({
            "peer_connected": peer_id
        })

        log(1, "server", "A peer connected with " + remoteAddress + ":" + remotePort)
    } else {
        send(client, {
            full: true,
            warning: "Connection refused: server is full",
        })
        log(1, "server", toString(client) + " connection refused: server is full")
        client.terminate()
    }

    
});

function requestHandler(data, isBinary) {
    const peer_id = peerToId[this]
    const peer = this
    if (isBinary) {
        // Decode the binary message with cbor
        const request= decode(data)
        if (!request) { return };

        // SERVER/CLIENT AUTHENTICATION
	    //--------------------------------------------------------------------------
        if (request.name) {
		    log(1, "server", "Client " + request.name + " joined!")
		    idToSessionIdentity[peer_id] = request.name
            identityCallback(peer_id, request.name)
	    }

       	if (request.sessionToken) {
		    idToSessionToken[peer_id] = request.sessionToken
		    log(1, "server", "Client token: " + request.sessionToken)
        }

        if (request.version) {
            log(1, "server", "Client version: " + request.version)
            console.log(request.version, server.version)
            if (request.version !== server.version) {
                send(peer, {
                    warning: "Connection refused: client version mismatch"
                })
                log(7, "server", toString(peer) + " connection refused!")
                peer.terminate()
            } else {
                send(peer, {
                    versionAck: true
                })
            }
        }

        if (request.settings) {
            for (const [key, value] of Object.entries(request.settings)) {
                idToSettings[key] = value
            }
        }

        if (request.dataRequest) {
            prejoinCallback(peer_id)
            send(peer, {
                exact: share.__diff(peer_id, true),
                joinAck: true
            })

            joinCallback(peer_id)
            broadcast({
                peer_joined: peer_id,
            })
        }

        // SERVER/CLIENT COMMS
	    //--------------------------------------------------------------------------
        if (request.message) {
            receiveCallback(peer_id, request.message)
        }

        // INPUT MANAGER
	    //--------------------------------------------------------------------------
        if (request.inputStream) {
            send(peer, {
                inputAck: request.seq
            })
            const inputStream = request.inputStream
            const sequence = request.seq

            inputResponseCallback(peer_id, inputStream, sequence)
        }

        // INPUT MANAGER
	    //--------------------------------------------------------------------------
        if (request.diff) {
            changingCallback(peer_id, request.diff)
            try {
                state.apply(homes[peer_id], request.diff)
            } catch(error) {
                console.log(error)
            }
            changedCallback(peer_id, request.diff)
        }

        if (request.exact) {
            
            let newState = state.apply(homes[peer_id], request.exact)
            changingCallback(peer_id, request.exact)
            for (const [key, value] of Object.entries(newState)) {
                homes[peer_id][key] = value
            }

            for (const [key, value] of Object.entries(homes[peer_id])) {
                if (!newState[key]) {
                    delete homes[peer_id][key]
                }
            }
            changedCallback(peer_id, request.exact)
        }

    } else {
        console.log("Message: %s", data)
    }
}

function disconnectHandler(code, reason) {
    const peer = this;
    const peer_id = idToPeer[peer];

    disconnectCallback(peer_id)

    //TODO disconnect callback
    delete homes[peer_id]
    delete idToPeer[peer_id]
    delete idToSession[peer_id]
    delete idToSessionToken[peer_id]
    delete idToSessionIdentity[peer_id]
    delete idToSettings[peer_id]

    numClients = numClients - 1;

    broadcast({
        peer_disconnected: peer_id,
    })
}

function changingCallback() {}
function changedCallback() {}
function identityCallback() {}
function prejoinCallback() {}
function joinCallback() {}
function receiveCallback() {}
function disconnectCallback() {}
function connectCallback() {}
 

module.exports = {
    server: server,
    send,
    broadcast,
    log,
    changingCallback, changedCallback, identityCallback, prejoinCallback, joinCallback, receiveCallback, 
    disconnectCallback, connectCallback
};
