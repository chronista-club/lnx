#!/usr/bin/swift

import Foundation

// Test loading the Rust library
print("Testing Rust Audio Engine Library Loading...")

let paths = [
    NSHomeDirectory() + "/repos/sizma/audio-engine/target/release/libaudio_engine.dylib",
    FileManager.default.currentDirectoryPath + "/sizma/libaudio_engine.dylib",
]

for path in paths {
    print("\nChecking: \(path)")
    if FileManager.default.fileExists(atPath: path) {
        print("✅ File exists")
        
        if let handle = dlopen(path, RTLD_NOW) {
            print("✅ Library loaded successfully")
            
            // Test function loading
            if let sym = dlsym(handle, "lnx_engine_create") {
                print("✅ Found lnx_engine_create function")
            } else {
                print("❌ Could not find lnx_engine_create function")
            }
            
            dlclose(handle)
        } else {
            if let error = dlerror() {
                print("❌ Failed to load library: \(String(cString: error))")
            }
        }
    } else {
        print("❌ File does not exist")
    }
}

print("\n\nLibrary dependencies check:")
let dylibPath = NSHomeDirectory() + "/repos/lnx-experience/lnx-audio-engine/target/release/liblnx_audio_engine.dylib"
if FileManager.default.fileExists(atPath: dylibPath) {
    let task = Process()
    task.launchPath = "/usr/bin/otool"
    task.arguments = ["-L", dylibPath]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    
    task.launch()
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8) {
        print(output)
    }
}