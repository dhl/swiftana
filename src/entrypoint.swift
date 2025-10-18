private var solLog: (@convention(c) (UnsafePointer<UInt8>, UInt64) -> Void) {
    // `murmur32("sol_log_") == 0x2075_59bd`
    unsafeBitCast(
        UnsafeMutableRawPointer(bitPattern: 0x2075_59bd)!,
        to: (@convention(c) (UnsafePointer<UInt8>, UInt64) -> Void).self
    )
}

@_cdecl("entrypoint")
func entrypoint(_ _input: UnsafeMutablePointer<UInt8>) -> UInt64 {
    let message: StaticString = "Hello world!"
    solLog(message.utf8Start, UInt64(message.utf8CodeUnitCount))

    return 0
}
