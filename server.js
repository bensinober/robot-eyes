// Bun server with websocket and static file serving
const BASE_PATH = "./www"
var pendingBuffer,pendingCmd, pendingSize, pendingMode

const httpServer = Bun.serve({
  port: 8665,
  host: "0.0.0.0",
  async fetch(req, server) {
    const url = new URL(req.url);
    switch (url.pathname) {
    case "/ws":
      // ws upgrade logic and channels subscription
      // valid channels are: commands, centroids, images
      const channel = new URL(req.url).searchParams.get("channels")
      return server.upgrade(req, {
        data: {
          createdAt: Date.now(),
          channels: [channel],
        }
      })
      break

    case "/api/snapimg":
      try {
        const formData = await req.formData()
        const uuid = formData.get("uuid")
        const num = formData.get("num").padStart(2, "0")
        const img = formData.get("image")
        const imgPath = `images/${uuid}_snap_${num}.png`
        await Bun.write(imgPath, img)
        //db.query(`UPDATE stats SET slideimg=?1 WHERE uuid=?2`)
        //  .run(imgPath, uuid)
        return new Response("OK")
      } catch(err) {
        console.log(err)
      }
      break

    case "/api/savemodel":
      try {
        const json = await req.json()
        const modelPath = "www/assets/model.json"
        await Bun.write(modelPath, JSON.stringify(json))
        return new Response("OK")
      } catch(err) {
        console.log(err)
      }
      break

    case "/api/loadmodel":
      // load model in server memory
      try {
        const file = Bun.file("www/assets/model.json")
        return new Response(file)
      } catch(err) {
        console.log(err)
      }
      break

    default:
      const filePath = BASE_PATH + url.pathname
      const file = Bun.file(filePath)
      return new Response(file)
    }
  },
  websocket: {
    message(ws, data) {
      ws.publish("shell-game", data)
    },
    open(ws) {
      console.log(`opened websocket type ${ws.binaryType} for channels ${ws.data.channels}`)
      for (const c of ws.data.channels) {
        ws.subscribe(c)
      }
      ws.data.sessionId = "shell-game-MCC"
    }, // a socket is opened
    close(ws, code, message) {}, // a socket is closed
    drain(ws) {}, // the socket is ready to receive more data
  },
  error() {
    return new Response(null, { status: 404 })
  },
})
console.log(`Bun http Server listening on ${httpServer.hostname}:${httpServer.port}`)
