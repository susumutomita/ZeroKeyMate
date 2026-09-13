import AppKit
import Foundation

// Reuses Mate's paper/graphite face, drawn as vector shapes at icon resolution.
let output=CommandLine.arguments.dropFirst().first ?? "apps/ios/ZeroKeyMate/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let size=NSSize(width:1024,height:1024)
let image=NSImage(size:size)
image.lockFocus()
NSColor(calibratedRed:0.958,green:0.954,blue:0.937,alpha:1).setFill()
NSBezierPath(rect:NSRect(origin:.zero,size:size)).fill()
NSColor(calibratedRed:0.105,green:0.112,blue:0.112,alpha:1).setFill()
for x in [292.0,592.0] {
    NSBezierPath(roundedRect:NSRect(x:x,y:320,width:140,height:384),xRadius:70,yRadius:70).fill()
}
image.unlockFocus()
var rect=NSRect(origin:.zero,size:size)
guard let cg=image.cgImage(forProposedRect:&rect,context:nil,hints:nil) else{fatalError("Icon rendering failed")}
let bitmap=NSBitmapImageRep(cgImage:cg)
guard let png=bitmap.representation(using:.png,properties:[:]) else{fatalError("PNG encoding failed")}
try png.write(to:URL(fileURLWithPath:output))
