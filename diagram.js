/* The following is all plumbing related. */
var line_style = {
  anchor:["Perimeter", {shape: "Square", anchorCount:32}],
  detachable: false,
  endpoint:[ "Rectangle", { width:1, height:1 } ],
  overlays:[
    ["Arrow", {location:-1, width:10, length:14 } ],
  ],
}

function snapto(a, b, color) {
  jsPlumb.connect({
    source:a,
    target:b,
    paintStyle:{ strokeWidth:2, stroke:color },
  }, line_style);
  jsPlumb.draggable(a);
  jsPlumb.draggable(b);
}
