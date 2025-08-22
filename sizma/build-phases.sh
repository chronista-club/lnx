#!/bin/bash

# Rust Audio Engine Library Copy Script

RUST_LIB_PATH="${PROJECT_DIR}/../lnx-audio-engine/target/release/liblnx_audio_engine.dylib"
FRAMEWORKS_PATH="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"

# Create Frameworks directory if it doesn't exist
mkdir -p "${FRAMEWORKS_PATH}"

# Copy the library if it exists
if [ -f "${RUST_LIB_PATH}" ]; then
    echo "Copying Rust audio engine library..."
    cp "${RUST_LIB_PATH}" "${FRAMEWORKS_PATH}/"
    
    # Update the library's install name
    install_name_tool -id "@rpath/liblnx_audio_engine.dylib" "${FRAMEWORKS_PATH}/liblnx_audio_engine.dylib"
    
    # Code sign the library
    codesign --force --sign - "${FRAMEWORKS_PATH}/liblnx_audio_engine.dylib"
    
    echo "✅ Rust audio engine library copied successfully"
else
    echo "⚠️ Warning: Rust audio engine library not found at ${RUST_LIB_PATH}"
    echo "Please build the Rust library first: cd ../lnx-audio-engine && cargo build --release"
fi