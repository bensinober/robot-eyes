////////////////////
// WEB Bluetooth API
// emulates a serial port
////////////////////

var btDevice
var btCharacteristic // the btle char device to send centroids to
var eyesConnected = false

// Write eye command to eyes, check if inside byte range
async function writeToEyes(x, y) {
  if (x > 255 || y > 255) { return }
  const cmd = new Uint8Array([ 0, 2, x, y, 13 ])
  // Trick to only write every 5.th message not to congest BTLE buffer
  const ms = new Date().getMilliseconds()
  console.log(cmd)
  if (ms % 5 === 0) {
    const res = await btCharacteristic.writeValueWithoutResponse(cmd)
  }
}

async function connectToEyes() {

  // benjis microbit v1
  // fb:c9:6d:cb:9d:63
  //const serviceUUID = "e2e00001-15cf-4074-9331-6fac42a4920b"
  //const characteristicUUID = "e2e00002-15cf-4074-9331-6fac42a4920b" // serial

  // benjis microbit v2
  const serviceUUID = "e2e10001-15cf-4074-9331-6fac42a4920b"
  const characteristicUUID = "e2e10002-15cf-4074-9331-6fac42a4920b" // serial

  // hm10 robot eyes
  //const serviceUUID = 0xffe0
  //const characteristicUUID = 0xffe1

  try {
    console.log("Requesting Bluetooth Device...")
    //var ble = await navigator.bluetooth.getAvailability()
    const btDevice = await navigator.bluetooth.requestDevice({
      //acceptAllDevices: true,
      filters: [{ namePrefix: "Benji" }, { namePrefix: "Folk" }, { name:  "HMSoft"}],
      optionalServices: [serviceUUID],
      //filters: [{ services: [serviceUUID] }], // fake service to send raw data as serial
      //filters: [{ name: "HMSoft" }],

    })
    console.log("YO", btDevice, btDevice.name, btDevice.id, btDevice.gatt.connected)

    // BTLE
    const server = await btDevice.gatt.connect()
    const service = await server.getPrimaryService(serviceUUID) // fake service to send data TO
    //const characteristicUuid = 0xffe1                      // fake characteristics/type for notify and read

    let characteristics = await service.getCharacteristics()
    //console.log(`Characteristics: ${characteristics.map(c => c.uuid).join('\n' + ' '.repeat(19))}`)
    btCharacteristic = await service.getCharacteristic(characteristicUUID) //19b10001-e8f2-537e-4f6c-d104768a1214

    // now activate eyes
    eyesConnected = true

    // No notifications
    //const notifications = await btCharacteristic.startNotifications()
    //await btCharacteristic.writeValueWithoutResponse(new Uint8Array([ 200, 200  ]))
    //console.log("written!")

  } catch(error)  {
    console.log("bluetooth connect failure: " + error)
    eyesConnected = false
  }
}

export { connectToEyes, writeToEyes, eyesConnected }