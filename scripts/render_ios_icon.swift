import AppKit

// Original vector mark (template default): two leaves, one shared river, a coral sun.
// Replace with your own icon or tweak the colors; run: swift scripts/render_ios_icon.swift
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
let cream = NSColor(red:0.96,green:0.945,blue:0.90,alpha:1)
let green = NSColor(red:0.12,green:0.29,blue:0.23,alpha:1)
cream.setFill(); NSBezierPath(rect:NSRect(x:0,y:0,width:size,height:size)).fill()
let border = NSBezierPath(roundedRect:NSRect(x:82,y:82,width:860,height:860),xRadius:185,yRadius:185)
green.withAlphaComponent(0.14).setStroke(); border.lineWidth = 3; border.stroke()
NSColor(red:0.80,green:0.38,blue:0.27,alpha:1).setFill()
NSBezierPath(ovalIn:NSRect(x:660,y:680,width:114,height:114)).fill()
green.setFill()
let left = NSBezierPath(); left.move(to:NSPoint(x:491,y:383)); left.curve(to:NSPoint(x:254,y:755),controlPoint1:NSPoint(x:204,y:398),controlPoint2:NSPoint(x:187,y:661)); left.curve(to:NSPoint(x:491,y:383),controlPoint1:NSPoint(x:530,y:719),controlPoint2:NSPoint(x:545,y:546)); left.fill()
let right = NSBezierPath(); right.move(to:NSPoint(x:514,y:387)); right.curve(to:NSPoint(x:807,y:641),controlPoint1:NSPoint(x:513,y:607),controlPoint2:NSPoint(x:672,y:684)); right.curve(to:NSPoint(x:514,y:387),controlPoint1:NSPoint(x:822,y:446),controlPoint2:NSPoint(x:676,y:374)); right.fill()
cream.setStroke()
let vein = NSBezierPath(); vein.move(to:NSPoint(x:493,y:400)); vein.curve(to:NSPoint(x:291,y:693),controlPoint1:NSPoint(x:384,y:512),controlPoint2:NSPoint(x:320,y:618)); vein.lineWidth=13; vein.lineCapStyle = .round; vein.stroke()
let vein2 = NSBezierPath(); vein2.move(to:NSPoint(x:529,y:402)); vein2.curve(to:NSPoint(x:753,y:602),controlPoint1:NSPoint(x:602,y:490),controlPoint2:NSPoint(x:675,y:549)); vein2.lineWidth=12; vein2.lineCapStyle = .round; vein2.stroke()
green.setStroke()
let river = NSBezierPath(); river.move(to:NSPoint(x:259,y:291)); river.curve(to:NSPoint(x:512,y:290),controlPoint1:NSPoint(x:348,y:235),controlPoint2:NSPoint(x:427,y:344)); river.curve(to:NSPoint(x:765,y:289),controlPoint1:NSPoint(x:601,y:234),controlPoint2:NSPoint(x:682,y:344)); river.lineWidth=27; river.lineCapStyle = .round; river.stroke()
NSGraphicsContext.restoreGraphicsState()
let target = CommandLine.arguments.dropFirst().first ?? "ios/TripJournal/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let rgb = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:3,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
for y in 0..<size { for x in 0..<size { for component in 0..<3 { rgb.bitmapData![y * rgb.bytesPerRow + x * 3 + component] = bitmap.bitmapData![y * bitmap.bytesPerRow + x * 4 + component] } } }
try rgb.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:target))
