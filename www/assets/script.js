///////////////////////
// ROBOT EYES JAVASCRIPT
///////////////////////

const GameModes = ["IDLE","START","STOP","SNAP","TRACK","TRACK_IDLE"]
var eyesActive = false
var gameMode = GameModes[0]
var centroid = {x: 320, y: 240}
var btDevice
var btCharacteristic // the btle char device to send centroids to

/*var imgPos = -320
var slideIdx = 0*/
const cmdBuf = new ArrayBuffer(6)
const dvCmd = new DataView(cmdBuf)
dvCmd.setUint8(0, 1) // command
dvCmd.setInt32(2, 0, true) // command length 0, little endian

var ctxSnap

/*document.getElementById("connectBtn").addEventListener("click", async(evt) => {
  // connect to eyes
  if ("bluetooth" in navigator) {
    try {
      //Device A4:06:E9:8E:00:0A HMSoft
      // HMSoft uU8ptu87vOOkd/NIwmqtDg== false
      //console.log("here")
      await connectToEyes()
    } catch(err) {
      console.log(err)
    }
  } else {
    console.log("you need to activate web bluetooth api in browser!")
  }
})*/


// transpond x, y (640,640) to u8 (255,255)
const writeToEyes = async function(x, y) {
    const x1 = Math.round(x / 640 * 255)
    //const x1 = Math.round(Math.abs((640 - x) / 640 * 255)) // invert x-axis
    const y1  = Math.round(Math.abs((640 - y) / 640 * 255)) // invert and compress y-axis
    const cmd = new Uint8Array([ 0, 2, x1, y1, 13])
    await btCharacteristic.writeValueWithoutResponse(cmd);
    console.log(`in: (${x}, ${y}) -- written (${x1}, ${y1})`)
}

const connectToEyes = async function() {
  const serviceUUID = 0xffe0;
  const serialUUID = 0xffe1 //       0000ffe1-0000-1000-8000-00805f9b34fb
  const characteristicUUID = 0xffe1

  try {
    console.log("Requesting Bluetooth Device...")
    //var ble = await navigator.bluetooth.getAvailability()
    const btDevice = await navigator.bluetooth.requestDevice({
      //acceptAllDevices: true,
      filters: [{ services: [serviceUUID] }], // fake service to send raw data as serial
      //filters: [{ name: "HMSoft" }],

    })
    //console.log(btDevice, btDevice.name, btDevice.id, btDevice.gatt.connected)

    // BTLE
    const server = await btDevice.gatt.connect()
    const service = await server.getPrimaryService(serviceUUID) // fake service to send data TO
    //const characteristicUuid = 0xffe1                      // fake characteristics/type for notify and read

    let characteristics = await service.getCharacteristics()
    //console.log(`Characteristics: ${characteristics.map(c => c.uuid).join('\n' + ' '.repeat(19))}`)
    btCharacteristic = await service.getCharacteristic(serialUUID) //19b10001-e8f2-537e-4f6c-d104768a1214

    // now activate eyes
    eyesActive = true
    // No notifications
    //const notifications = await btCharacteristic.startNotifications()
    //await btCharacteristic.writeValueWithoutResponse(new Uint8Array([ 200, 200  ]))
    //console.log("written!")

  } catch(error)  {
    console.log("bluetooth connect failure: " + error)
  }
}

const clearData = function() {
  //imgPos = -320 // don't know why we need to start negative offset, but hey, javascript
  centroid = {x: 320, y: 240}
}

const sendGameMode = function(mode) {
  dvCmd.setUint8(1, mode)
  ws.send(new Uint8Array(cmdBuf))
}

const setSnapContext = function(ctx) {
  ctxSnap = ctx
}

const ws = new WebSocket(`ws://${window.location.host}/ws?channels=robot-eyes`)
ws.addEventListener("open", event => ws.binaryType = "arraybuffer")
ws.addEventListener("message", async event => {
  //console.log(`INCOMING: ${event.data}`)
  const dv = new DataView(event.data);
  const cmd = dv.getUint8(0)
  const mode = dv.getUint8(1)
  const len = dv.getInt32(2, true)
  const data = event.data.slice(6)
  // Game Mode
  gameMode = GameModes[parseInt(mode, 10)]
  document.getElementById("gameMode").innerHTML = gameMode.toLowerCase()

  switch (cmd) {
  case 0:
    //console.log(`echo cmd res: ${data}`)
    break
  case 1:
    console.log("game mode change")
    break
  case 2:
    // centroid
    const x = dv.getInt32(6, true)
    const y = dv.getInt32(10, true)
    centroid = {x, y}
    const centroidDiv = document.querySelector(".centroid")
    centroidDiv.innerHTML = `${x},${y}`
    if (eyesActive) {
      writeToEyes(x, y)
    }
    break
  case 3:
    // snap
    var blob = new Blob([data], {type: "image/png"})
    var img = new Image()
    /*slideIdx++
    if (slideIdx > 2) {
      slideIdx = 0
      imgPos = -320
    }
    imgPos = imgPos + 320*/
    img.onload = function (e) {
      ctxSnap.drawImage(img, 0, 0, 640, 640)
      window.URL.revokeObjectURL(img.src)
      img = null
    }
    img.onerror = img.onabort = function () {
      img = null
      console.log("error loading image")
      return
    }
    img.src = window.URL.createObjectURL(blob)
    break
  default:
    console.log(`unknow CMD: ${cmd}`)
  }
})

export { writeToEyes, connectToEyes, sendGameMode, clearData, setSnapContext }