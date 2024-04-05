// test.js for calibrating eyes

const testCanvas = document.querySelector("robotEyesCanvas")
var ctxTestCanvas = testCanvas.getContext("2d")

ctxTestCanvas.fillStyle = "blue"
ctxTestCanvas.fillRect(0, 0, ctxTestCanvas.width, ctxTestCanvas.height)

ctxTestCanvas.addEventListener("mousedown", function(e) {
    getCursorPosition(ctxTestCanvas, e)
})

// TEST CANVAS FOR ROBOT EYES
function getCursorPosition(canvas, event) {
    const rect = canvas.getBoundingClientRect()
    const x = event.clientX - rect.left
    const y = event.clientY - rect.top
    console.log("x: " + x + " y: " + y)
}


export { getCursorPosition }