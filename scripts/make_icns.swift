import Foundation

guard CommandLine.arguments.count >= 3 else {
    fatalError("Usage: make_icns output.icns type=path.png ...")
}

func appendUInt32BE(_ value: UInt32, to data: inout Data) {
    data.append(UInt8((value >> 24) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
}

func appendASCII(_ value: String, to data: inout Data) {
    data.append(value.data(using: .ascii)!)
}

let output = CommandLine.arguments[1]
var chunks: [(String, Data)] = []

for arg in CommandLine.arguments.dropFirst(2) {
    let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
    guard parts.count == 2, parts[0].count == 4 else {
        fatalError("Invalid chunk argument: \(arg)")
    }
    chunks.append((parts[0], try Data(contentsOf: URL(fileURLWithPath: parts[1]))))
}

let totalLength = 8 + chunks.reduce(0) { $0 + 8 + $1.1.count }
var icns = Data()
appendASCII("icns", to: &icns)
appendUInt32BE(UInt32(totalLength), to: &icns)

for (type, png) in chunks {
    appendASCII(type, to: &icns)
    appendUInt32BE(UInt32(8 + png.count), to: &icns)
    icns.append(png)
}

try icns.write(to: URL(fileURLWithPath: output))
print(output)
