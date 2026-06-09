# RHVoice Ukraine

Ukrainian voice synthesis for iOS and macOS using RHVoice engine.

## Features

- 4 Ukrainian voices: Anatol, Marianna, Natalia, Volodymyr
- Full RHVoice engine integration
- Objective-C++ wrappers for easy integration
- Support for iOS and macOS

## Build Status

![Build Status](https://github.com/YOUR_USERNAME/RHVoiceUkraine/workflows/Build%20RHVoice%20Ukraine/badge.svg)

## Building

### macOS

```bash
cd RHVoice
mkdir build_macos_x86_64
cd build_macos_x86_64
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
make -j$(sysctl -n hw.ncpu)
```

### iOS

```bash
cd RHVoice
mkdir build_ios_device
cd build_ios_device
cmake .. \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DBUILD_SHARED_LIBS=OFF
make
```

## Testing

```bash
cd MacOSTest
./rhvoice_test
```

## License

LGPL-2.1 (RHVoice engine)

## Author

Andriy Butenko
