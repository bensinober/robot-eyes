import { eyesConnected, writeToEyes } from "./eyes.js"

const drawSvg = document.querySelector("#drawSvg")
const svgBoundingRect = drawSvg.getBoundingClientRect()
var strPath = ""
var ptBuffer = []      // buffer for smoothing points
var activePath = null  // svg path
const ptBufferSize = 20

function reset() {
  console.log("clicked new")
  drawSvg.innerHTML = ""
}

// START SVG DRAW
function startDraw(event) {
  activePath = document.createElementNS("http://www.w3.org/2000/svg", "path")
  activePath.setAttribute("fill", "none")
  activePath.setAttribute("stroke", "#000")
  activePath.setAttribute("stroke-width", 3)
  ptBuffer = []
  var pt = getMousePosition(event)
  appendToBuffer(pt.coord)
  strPath = "M" + pt.coord.x + " " + pt.coord.y
  activePath.setAttribute("d", strPath)
  drawSvg.appendChild(activePath)
}


function draw(event) {
  if (activePath) {
    const pos = getMousePosition(event)
    appendToBuffer(pos.coord)
    updateSvgPath()

    if (eyesConnected === true) {
      writeToEyes(pos.rel.x, pos.rel.y)
    }
  }
}

function stopDraw() {
  if (activePath) {
    activePath = null
  }
}

function getMousePosition(event) {
  const x = Math.floor(event.clientX - svgBoundingRect.left)
  const y = Math.floor(event.clientY - svgBoundingRect.top)
  const relX = Math.round(x / svgBoundingRect.width * 255)
  const relY = Math.round((svgBoundingRect.height - y) / svgBoundingRect.height * 255) // invert and compress y-axis
  return { coord: {x, y}, rel: {x: relX, y: relY} }
}

function appendToBuffer(coord) {
  ptBuffer.push(coord)
  while (ptBuffer.length > ptBufferSize) {
    ptBuffer.shift()
  }
}

function getAveragePoint(offset) {
  var len = ptBuffer.length
  if (len % 2 === 1 || len >= ptBufferSize) {
    var totalX = 0
    var totalY = 0
    var pt, i
    var count = 0
    for (i = offset; i < len; i++) {
      count++
      pt = ptBuffer[i]
      totalX += pt.x
      totalY += pt.y
    }
    return {
      x: totalX / count,
      y: totalY / count,
    }
  }
  return null
}

// Update active SVG path with smoothness
function updateSvgPath() {
  let coord = getAveragePoint(0)
  if (coord) {
    // Get the smoothed part of the path that will not change
    strPath += " L" + coord.x + " " + coord.y
    // Get the last part of the path (close to the current mouse position)
    // This part will change if the mouse moves again
    var tmpPath = ""
    for (var offset = 2; offset < ptBuffer.length; offset += 2) {
      coord = getAveragePoint(offset)
      tmpPath += " L" + coord.x + " " + coord.y
    }
    // Set the complete current path coordinates
    activePath.setAttribute("d", strPath + tmpPath)
  }
}


export { reset, draw, startDraw, stopDraw }