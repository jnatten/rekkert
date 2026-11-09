// Composes the App Store's product page header and search results images from the raw
// shots scripts/shots.sh takes.
//
//   swift scripts/creative.swift .build/shots/raw fastlane/creative/en-US
//
// Both are shown on iOS 27 and iPadOS 27 and later, and cropped differently per device,
// so everything that matters sits in the middle. Check them in App Store Connect's Preview
// before submitting.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("usage: swift scripts/creative.swift <raw shots> <out>\n".data(using: .utf8)!)
    exit(2)
}
let raw = URL(fileURLWithPath: arguments[1])
let out = URL(fileURLWithPath: arguments[2])

func shot(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: raw.appendingPathComponent(name)) else {
        FileHandle.standardError.write("FAIL: no \(name) in \(raw.path) - run scripts/shots.sh --store\n".data(using: .utf8)!)
        exit(1)
    }
    return image
}

func pixels(_ image: NSImage) -> CGSize {
    guard let rep = image.representations.first else { return image.size }
    return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
}

let blue = Color(red: 0.129, green: 0.424, blue: 0.902)
let orange = Color(red: 0.914, green: 0.451, blue: 0.078)
let titanium = LinearGradient(
    colors: [Color(white: 0.78), Color(white: 0.52), Color(white: 0.70), Color(white: 0.46)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

struct Court: View {
    var lineFrom: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                LinearGradient(colors: [blue, blue.mix(with: .black, by: 0.55)], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [orange, orange.mix(with: .black, by: 0.55)], startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                Rectangle()
                    .fill(.white)
                    .frame(width: proxy.size.height * 0.018)
                    .mask(
                        LinearGradient(
                            stops: [.init(color: .clear, location: lineFrom),
                                    .init(color: .black, location: lineFrom == 0 ? 0 : lineFrom + 0.08)],
                            startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

struct Phone: View {
    let image: NSImage
    let width: CGFloat

    var body: some View {
        let size = pixels(image)
        let height = width * size.height / size.width
        let bezel = height * 0.038
        let radius = height * 0.14
        Image(nsImage: image)
            .resizable()
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .padding(bezel)
            .background(RoundedRectangle(cornerRadius: radius + bezel, style: .continuous).fill(.black))
            .overlay(
                RoundedRectangle(cornerRadius: radius + bezel, style: .continuous)
                    .strokeBorder(titanium, lineWidth: bezel * 0.32)
            )
            .compositingGroup()
            .shadow(color: .black.opacity(0.45), radius: height * 0.08, y: height * 0.05)
    }
}

struct Watch: View {
    let image: NSImage
    let height: CGFloat

    var body: some View {
        let size = pixels(image)
        let width = height * size.width / size.height
        let glass = width * 0.07
        let rim = width * 0.075
        let caseWidth = width + 2 * (glass + rim)
        let caseHeight = height + 2 * (glass + rim)
        let radius = caseWidth * 0.26
        ZStack {
            RoundedRectangle(cornerRadius: caseWidth * 0.1, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)], startPoint: .leading, endPoint: .trailing))
                .frame(width: caseWidth * 0.78, height: caseHeight * 2.3)
                .mask(
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3),
                                .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom))
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: rim * 0.3, style: .continuous)
                    .fill(Color(red: 1, green: 0.36, blue: 0.1))
                    .frame(width: rim * 0.7, height: caseHeight * 0.2)
                    .offset(y: -caseHeight * 0.12)
                Spacer()
                VStack(spacing: caseHeight * 0.06) {
                    RoundedRectangle(cornerRadius: rim * 0.3, style: .continuous)
                        .fill(titanium)
                        .frame(width: rim * 1.0, height: caseHeight * 0.17)
                    RoundedRectangle(cornerRadius: rim * 0.3, style: .continuous)
                        .fill(titanium)
                        .frame(width: rim * 0.6, height: caseHeight * 0.16)
                }
                .offset(y: -caseHeight * 0.04)
            }
            .frame(width: caseWidth + rim * 1.2)
            Image(nsImage: image)
                .resizable()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: width * 0.2, style: .continuous))
                .padding(glass)
                .background(RoundedRectangle(cornerRadius: radius - rim, style: .continuous).fill(.black))
                .padding(rim)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(titanium))
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: height * 0.09, y: height * 0.05)
    }
}

@MainActor
func write(_ view: some View, width: Int, height: Int, to name: String) {
    let renderer = ImageRenderer(content: view.frame(width: CGFloat(width), height: CGFloat(height)))
    renderer.scale = 1
    guard let image = renderer.cgImage,
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fatalError("could not render \(name)") }
    // App Store Connect refuses any image with an alpha channel.
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let url = out.appendingPathComponent(name)
    guard let flat = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not write \(name)") }
    CGImageDestinationAddImage(destination, flat, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(name)") }
    print("  \(url.path)  \(width)x\(height)")
}

let match = shot("match-workout.png")
let wrist = shot("watch.png")

MainActor.assumeIsolated {
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    write(
        ZStack {
            Court()
            Phone(image: match, width: 2000)
                .offset(x: -260)
            Watch(image: wrist, height: 560)
                .offset(x: 1160, y: 110)
        },
        width: 3840, height: 1646, to: "header.png")

    write(
        ZStack {
            Court(lineFrom: 0.28)
            Text("Tap either. Both follow.")
                .font(.system(size: 190, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 6)
                .offset(y: -680)
            Phone(image: match, width: 2150)
                .offset(x: -300, y: 110)
            Watch(image: wrist, height: 620)
                .offset(x: 1230, y: 230)
        },
        width: 3840, height: 2560, to: "search.png")
}
