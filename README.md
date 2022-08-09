> :exclamation: **_Update:_**  Good news! This issue has been fixed in **MacOS Version 13.0 Beta 5 (22A5321d)** / **XCode Version 14.0 Beta 5 (14A5294e)**

This command line project reproduces a **data error** when loading multiple textures with a **single** MTLIOCommandBuffer.

This is associated to FB10582329 (Apple Feedback Assistant).

# Background

The WWDC 2022 session [Load resources faster with Metal 3](https://developer.apple.com/videos/play/wwdc2022/10104) outlines how to load textures with the new Metal 3 features with MTLIO.

Here are the session's ([7:22](https://developer.apple.com/videos/play/wwdc2022/10104/?time=442)) directions on loading textures:

```swift
// Create Metal IO Command Buffer

let ioCommandBuffer = ioCommandQueue.makeCommandBuffer()

// Encode load commands
// Encode load texture and load buffer commands
ioCommandBuffer.load(texture, slice: 0, level: 0, size: size,
                     sourceBytesPerRow:bytesPerRow, sourceBytesPerImage: bytesPerImage,
                     destinationOrigin: destOrigin,
                     sourceHandle: fileHandle, sourceHandleOffset: 0)
ioCommandBuffer.load(buffer, offset: 0, size: size,
                     sourceHandle: fileHandle, sourceHandleOffset: 0)


// Commit command buffer for execution
ioCommandBuffer.commit()
```

Here are the session's ([15:00](https://developer.apple.com/videos/play/wwdc2022/10104/?time=900)) directions for getting a file handle to a compressed file:

```swift
// Create an Metal File IO Handle

// Create handle to a compressed file
var compressedFileIOHandle : MTLIOFileHandle!
do {
    try compressedFileHandle = device.makeIOHandle(url: compressedFilePath, compressionMethod: MTLIOCompressionMethod.zlib)
} catch {
    print(error)
}
```

# Reproduction Overview

Running this project...

1. Displays XCode environment/version and MacOS version information:
    ```sh
    # Runs the following shell commands
    xcrun --show-sdk-path
    xcrun xcodebuild -version
    sw_vers
    ```
2. *Setup -* Load PNG [images](./x-mtlio-load-multiple-textures/cubemap-textures/) for each cube face.
3. *Setup -* Write the raw bytes (RGBA) using MTLIO Compression Context, using the `lz4` compression method.
4. Load each cube face into cube texture using MTLIO
    - If `let USE_SINGLE_COMMAND_BUFFER = true` (reproduces the data error)
        - A single MTLIO IO Command Buffer is used load all 6 faces (slices) into the cube texture
    - Otherwise, create/use 6 MTLIO IO Command Buffers, each loading a single face (slice) into the cube texture.
5. *Verify -* Load the bytes of each face (slice) of the cube texture and verify they match exactly originating source bytes.

# Observations

1. Consistently, the last (6th) face is incorrect.
2. **There is no indication of failure**
    - MTLIO Command Buffer status is complete
      ```
      assert(command_buffer.status == .complete)
      ```
    - Even with Diagnostics / Metal / API Validation, no error nor warning is logged.
2. Just looking at the first pixel's bytes (4 bytes), looks like the alpha channel is mixed up:
    ```
    Expected first pixel's bytes: [254, 254, 254, 255]
                                                  ^^^
      Actual first pixel's bytes: [255, 254, 254, 254]
                                   ^^^
    ```
3. No data errors when using **multiple** MTLIO Command Buffers (`let USE_SINGLE_COMMAND_BUFFER = false`).

## Example Output (Single Command Buffer)

Generated from a MacBook Pro 2021 M1 Max

```
-----------
Environment
-----------


Command: xcrun --show-sdk-path
Result: /Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk


Command: xcrun xcodebuild -version
Result: Xcode 14.0
Build version 14A5270f


Command: sw_vers
Result: ProductName:		macOS
ProductVersion:		13.0
BuildVersion:		22A5295h


----------------------------------------------------------------------------------------------------
Setup: Load PNG images for each cube face and Write raw bytes (RGBA) using MTLIO Compression Context
----------------------------------------------------------------------------------------------------

2022-07-07 18:03:23.916224-0500 x-mtlio-load-multiple-textures[35986:426065] Metal GPU Frame Capture Enabled
2022-07-07 18:03:23.916607-0500 x-mtlio-load-multiple-textures[35986:426065] Metal API Validation Enabled
Reading raw pixel bytes from PNG texture /Users/pwong/projects/x-mtlio-load-multiple-textures/x-mtlio-load-multiple-textures/cubemap-textures//cubemap_posx.png
Writing compressed cube face (0) texture bytes to /var/folders/bd/9qd81pgj4xj01bg4sgp43dvr0000gn/T/9706F1D2-F318-4A81-9E83-BB722C72F62D/0.lz w/chunk size 65536...
... write completed.
Reading raw pixel bytes from PNG texture /Users/pwong/projects/x-mtlio-load-multiple-textures/x-mtlio-load-multiple-textures/cubemap-textures//cubemap_negx.png
Writing compressed cube face (1) texture bytes to /var/folders/bd/9qd81pgj4xj01bg4sgp43dvr0000gn/T/9706F1D2-F318-4A81-9E83-BB722C72F62D/1.lz w/chunk size 65536...
... write completed.
Reading raw pixel bytes from PNG texture /Users/pwong/projects/x-mtlio-load-multiple-textures/x-mtlio-load-multiple-textures/cubemap-textures//cubemap_posy.png
Writing compressed cube face (2) texture bytes to /var/folders/bd/9qd81pgj4xj01bg4sgp43dvr0000gn/T/9706F1D2-F318-4A81-9E83-BB722C72F62D/2.lz w/chunk size 65536...
... write completed.
Reading raw pixel bytes from PNG texture /Users/pwong/projects/x-mtlio-load-multiple-textures/x-mtlio-load-multiple-textures/cubemap-textures//cubemap_negy.png
Writing compressed cube face (3) texture bytes to /var/folders/bd/9qd81pgj4xj01bg4sgp43dvr0000gn/T/9706F1D2-F318-4A81-9E83-BB722C72F62D/3.lz w/chunk size 65536...
... write completed.
Reading raw pixel bytes from PNG texture /Users/pwong/projects/x-mtlio-load-multiple-textures/x-mtlio-load-multiple-textures/cubemap-textures//cubemap_posz.png
Writing compressed cube face (4) texture bytes to /var/folders/bd/9qd81pgj4xj01bg4sgp43dvr0000gn/T/9706F1D2-F318-4A81-9E83-BB722C72F62D/4.lz w/chunk size 65536...
... write completed.
Reading raw pixel bytes from PNG texture /Users/pwong/projects/x-mtlio-load-multiple-textures/x-mtlio-load-multiple-textures/cubemap-textures//cubemap_negz.png
Writing compressed cube face (5) texture bytes to /var/folders/bd/9qd81pgj4xj01bg4sgp43dvr0000gn/T/9706F1D2-F318-4A81-9E83-BB722C72F62D/5.lz w/chunk size 65536...
... write completed.

-------------------------------------------------
Load each cube face into cube texture using MTLIO
-------------------------------------------------

Using a single command buffer...
... loading completed.

------------------------------------------------
Verify the each face (slice) of the cube texture
------------------------------------------------

Verifying bytes loaded by MTLIO into cube face 0 texture matches original source bytes
Verifying bytes loaded by MTLIO into cube face 1 texture matches original source bytes
Verifying bytes loaded by MTLIO into cube face 2 texture matches original source bytes
Verifying bytes loaded by MTLIO into cube face 3 texture matches original source bytes
Verifying bytes loaded by MTLIO into cube face 4 texture matches original source bytes
Verifying bytes loaded by MTLIO into cube face 5 texture matches original source bytes
Expected first pixel's bytes: [254, 254, 254, 255]
  Actual first pixel's bytes: [255, 254, 254, 254]
x_mtlio_load_multiple_textures/main.swift:201: Assertion failed: Loaded cube face 5 texture does not match original source bytes
```
