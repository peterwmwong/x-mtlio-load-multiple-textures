import Foundation
import Metal
import MetalKit

let USE_SINGLE_COMMAND_BUFFER = true // true reproduces data error, false has no data error
let COMPRESSION_METHOD        = MTLIOCompressionMethod.lz4
let COMPRESSION_CHUNK_SIZE    = MTLIOCompressionContextDefaultChunkSize()
let BYTES_PER_PIXEL           = MemoryLayout<SIMD4<UInt8>>.size
let CUBE_FACE_RANGE           = 0...5

public extension FileManager {
    func createTempDirectory() throws -> String {
        let tempDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(atPath: tempDirectory,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
        return tempDirectory
    }
}

func shell(_ command: String) throws {
    let task = Process()
    let pipe = Pipe()

    print("\nCommand: \(command)")
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.standardInput = nil
    try task.run()
    let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
    print("Result: \(result)")
}

assert(ProcessInfo.processInfo.arguments.count == 2, "No cubemap textures directory provided")

let cubemapTexturesDir = ProcessInfo.processInfo.arguments[1]
var isDir : ObjCBool = true
assert(FileManager.default.fileExists(atPath: cubemapTexturesDir, isDirectory: &isDir), "\(cubemapTexturesDir) does not exist")

print("""

-----------
Environment
-----------

""")
try shell("xcrun --show-sdk-path")
try shell("xcrun xcodebuild -version")
try shell("sw_vers")

print("""

----------------------------------------------------------------------------------------------------
Setup: Load PNG images for each cube face and Write raw bytes (RGBA) using MTLIO Compression Context
----------------------------------------------------------------------------------------------------

""")

let cubemapTextureFileNames = [
    "cubemap_posx.png",
    "cubemap_negx.png",
    "cubemap_posy.png",
    "cubemap_negy.png",
    "cubemap_posz.png",
    "cubemap_negz.png",
]
let cubemapTextureFaceFilesDir = try FileManager.default.createTempDirectory()
let cubemapTextureFaceFiles = CUBE_FACE_RANGE.map { face_id in
    "\(cubemapTextureFaceFilesDir)/\(face_id).lz"
}

var originalCubeFaceBytes: [[UInt8]] = []
let device = MTLCreateSystemDefaultDevice()!
var width = 0
var height = 0
var pixelFormat: MTLPixelFormat? = nil
for face_id in CUBE_FACE_RANGE {
    let filename = "\(cubemapTexturesDir)/\(cubemapTextureFileNames[face_id])"
    print("Reading raw pixel bytes from PNG texture \(filename)")
    let texture = try MTKTextureLoader(device: device).newTexture(URL: URL(filePath: filename))
    assert([.bgra8Unorm_srgb, .bgra8Unorm, .rgba8Unorm_srgb, .rgba8Unorm].contains(texture.pixelFormat), "Unexpected texture pixel format from loading image")
    assert(
        (width == 0 && texture.width > 0) || (width == texture.width),
        "Width is invalid, must match other cube faces"
    )
    assert(
        (height == 0 && texture.height > 0) || (height == texture.height),
        "Height is invalid, must match other cube faces"
    )
    assert(
        (pixelFormat == nil) || (pixelFormat == texture.pixelFormat),
        "Pixel Format is invalid, must match other cube faces"
    )
    width = texture.width
    height = texture.height
    pixelFormat = texture.pixelFormat
    let bytesPerRow = texture.width * BYTES_PER_PIXEL
    let totalBytes = bytesPerRow * texture.height
    var textureBytes: [UInt8] = Array<UInt8>.init(repeating: 0, count: totalBytes)
    texture.getBytes(&textureBytes,
                           bytesPerRow: bytesPerRow,
                           from: MTLRegion(
                            origin: MTLOrigin(x: 0, y: 0, z: 0),
                            size: MTLSize(width: texture.width, height: texture.height, depth: 1)
                           ),
                           mipmapLevel: 0)
    originalCubeFaceBytes.append(textureBytes)
    
    let tmpTextureFile = cubemapTextureFaceFiles[face_id]
    print("Writing compressed cube face (\(face_id)) texture bytes to \(tmpTextureFile) w/chunk size \(COMPRESSION_CHUNK_SIZE)...")
    let context = MTLIOCreateCompressionContext(tmpTextureFile, COMPRESSION_METHOD, COMPRESSION_CHUNK_SIZE)!
    MTLIOCompressionContextAppendData(context, &textureBytes, totalBytes)
    let compressionStatus = MTLIOFlushAndDestroyCompressionContext(context)
    assert(compressionStatus == MTLIOCompressionStatus.complete, "Failed to write \(tmpTextureFile)")
    print("... write completed.")
}



print("""

-------------------------------------------------
Load each cube face into cube texture using MTLIO
-------------------------------------------------

""")

let cubeTextureDesc = MTLTextureDescriptor()
cubeTextureDesc.width = width
cubeTextureDesc.height = height
cubeTextureDesc.pixelFormat = pixelFormat!
cubeTextureDesc.textureType = .typeCube
cubeTextureDesc.depth = 1
let cubeTexture = device.makeTexture(descriptor: cubeTextureDesc)!

let bytesPerRow = cubeTextureDesc.width * BYTES_PER_PIXEL
let bytesPerImage = bytesPerRow * cubeTextureDesc.height
let command_queue = try device.makeIOCommandQueue(descriptor: MTLIOCommandQueueDescriptor())
let single_command_buffer = USE_SINGLE_COMMAND_BUFFER ? command_queue.makeCommandBuffer() : nil

if USE_SINGLE_COMMAND_BUFFER {
    print("Using a single command buffer...")
} else {
    print("Using a command buffer for EACH face...")
}
for face_id in CUBE_FACE_RANGE {
    let command_buffer_to_use = USE_SINGLE_COMMAND_BUFFER ? single_command_buffer! : command_queue.makeCommandBuffer()
    let handle = try device.makeIOHandle(url: URL(filePath: cubemapTextureFaceFiles[face_id]), compressionMethod: COMPRESSION_METHOD)
    command_buffer_to_use.load(
        cubeTexture,
        slice: face_id,
        level: 0,
        size: MTLSizeMake(width, height, 1),
        sourceBytesPerRow: bytesPerRow,
        sourceBytesPerImage: bytesPerImage,
        destinationOrigin: MTLOriginMake(0, 0, 0),
        sourceHandle: handle,
        sourceHandleOffset: 0)
    if !USE_SINGLE_COMMAND_BUFFER {
        command_buffer_to_use.commit()
        command_buffer_to_use.waitUntilCompleted()
        assert(command_buffer_to_use.status == .complete, "Loading Cube Map textures using MTLIO failed")
    }
}
if USE_SINGLE_COMMAND_BUFFER {
    single_command_buffer!.commit()
    single_command_buffer!.waitUntilCompleted()
    assert(single_command_buffer!.status == .complete, "Loading Cube Map textures using MTLIO failed")
}
print("... loading completed.")


print("""

------------------------------------------------
Verify the each face (slice) of the cube texture
------------------------------------------------

""")

for face_id in CUBE_FACE_RANGE {
    print("Verifying bytes loaded by MTLIO into cube face \(face_id) texture matches original source bytes")
    
    var loadedCubeFaceBytes: [UInt8] = Array<UInt8>.init(repeating: 0, count: bytesPerImage)
    cubeTexture.getBytes(
        &loadedCubeFaceBytes,
        bytesPerRow: bytesPerRow,
        bytesPerImage: bytesPerImage,
        from: MTLRegionMake3D(0, 0, 0, width, height, 1),
        mipmapLevel: 0,
        slice: face_id)
    
    let expected_bytes = originalCubeFaceBytes[face_id]
    let is_same = memcmp(expected_bytes, loadedCubeFaceBytes, bytesPerImage) == 0
    if (!is_same) {
        print("Expected first pixel's bytes: \(expected_bytes[0..<BYTES_PER_PIXEL])")
        print("  Actual first pixel's bytes: \(loadedCubeFaceBytes[0..<BYTES_PER_PIXEL])")
    }
    assert(is_same, "Loaded cube face \(face_id) texture does not match original source bytes")
}
