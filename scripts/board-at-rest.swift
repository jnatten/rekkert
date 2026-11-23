// Whether each half of the watch's board has its number, in screenshots of it.
//
//     swiftc -O -o .build/board-at-rest scripts/board-at-rest.swift
//     .build/board-at-rest shots/*.png
//
// A number at rest is solid white. One caught part way through an animation is blurred or
// see-through, and has next to no solid white in it. Exits 1 naming the screenshots where a
// half is short of it, or where no board was on screen. `scripts/board-at-rest.sh` takes them.

import CoreGraphics
import Foundation
import ImageIO

/// More than the serve mark and the undo arrow come to together, and less than the thinnest
/// digit does alone.
let enough = 700

func solidWhite(in url: URL) -> (left: Int, right: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    func channels(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let index = (y * width + x) * 4
        return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
    }
    func isTeamColour(_ x: Int, _ y: Int) -> Bool {
        let (red, green, blue) = channels(x, y)
        let brightest = max(red, green, blue)
        return brightest > 110 && brightest - min(red, green, blue) > 70
    }

    let edges = (left: width * 3 / 100, right: width * 97 / 100)
    let rows = (0 ..< height).filter { isTeamColour(edges.left, $0) || isTeamColour(edges.right, $0) }
    guard rows.count > height / 5 else { return nil }

    func count(_ columns: Range<Int>) -> Int {
        var found = 0
        for y in rows {
            for x in columns {
                let (red, green, blue) = channels(x, y)
                if red > 235, green > 235, blue > 235 { found += 1 }
            }
        }
        return found
    }
    return (count(width * 2 / 100 ..< width * 49 / 100), count(width * 51 / 100 ..< width * 98 / 100))
}

var failures: [String] = []
let paths = CommandLine.arguments.dropFirst()
for path in paths {
    let name = URL(fileURLWithPath: path).lastPathComponent
    guard let white = solidWhite(in: URL(fileURLWithPath: path)) else {
        failures.append("\(name): no board on screen")
        continue
    }
    if white.left < enough || white.right < enough {
        failures.append("\(name): a half without its number (solid white \(white.left) left, \(white.right) right)")
    }
}
for failure in failures { print("  \(failure)") }
print("  \(paths.count - failures.count) of \(paths.count) at rest")
exit(failures.isEmpty && !paths.isEmpty ? 0 : 1)
