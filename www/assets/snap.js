// js to handle eye snaps

const snapCanvas = document.getElementById("snapBox")
const ctxSnap = snapCanvas.getContext("2d")
var timerId

document.getElementById("startSnap").addEventListener("click", async(evt) => {
  console.log("START SNAP")
  document.getElementById("startSnap").classList.remove("open")
  clearData()
  timerId = setInterval(function (evt) {
    dvCmd.setUint8(1, 3) // GameMode.SNAP
    ws.send(new Uint8Array(cmdBuf))
  }, 3000)
})

document.getElementById("stopSnap").addEventListener("click", async(evt) => {
  console.log("STOP SNAP")
  dvCmd.setUint8(1, 3) // GameMode.SNAP
  ws.send(new Uint8Array(cmdBuf))
  clearData()
  clearInterval(timerId)
})

const clearData = function() {
  ctxSnap.clearRect(0, 0, snapCanvas.width, snapCanvas.height)
  //imgPos = -320 // don't know why we need to start negative offset, but hey, javascript
  centroid = {x: 320, y: 240}
}

export { clearData } // (ws, dvCmd, cmdBuf, imgPos, centroid)
