/* The following is all plumbing related. */
function snapto(a, b, color) {
  jsPlumb.connect({
    source:a,
    target:b,
    anchor:["Perimeter", {shape: "Square", anchorCount:8}],
    detachable: false,
    endpoint:[ "Rectangle", { width:1, height:1 } ],
    overlays:[
      ["Arrow", {location:-1, width:10, length:14, outlineStroke:"black", outlineWidth:1 } ],
    ],
    paintStyle:{ strokeWidth:2, stroke:color},
    hoverPaintStyle:{ stroke:"orange"},
  });
}
