# ios-x86_64-simulator.cmake
#
# This CMake toolchain file targets the iOS simulator on X86_64 architecture.

# Set the system name to iOS
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# Specify the target architecture
set(CMAKE_OSX_ARCHITECTURES "x86_64")

# Find the latest iOS Simulator SDK
execute_process(COMMAND xcrun --sdk iphonesimulator --show-sdk-path
                OUTPUT_VARIABLE IOS_SDK_ROOT
                OUTPUT_STRIP_TRAILING_WHITESPACE)

if(NOT IOS_SDK_ROOT)
    message(FATAL_ERROR "Could not find iOS Simulator SDK. Is Xcode installed?")
endif()

set(CMAKE_OSX_SYSROOT "${IOS_SDK_ROOT}")

# Specify the compiler
execute_process(COMMAND xcrun --sdk iphonesimulator --find clang
                OUTPUT_VARIABLE CMAKE_C_COMPILER
                OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND xcrun --sdk iphonesimulator --find clang++
                OUTPUT_VARIABLE CMAKE_CXX_COMPILER
                OUTPUT_STRIP_TRAILING_WHITESPACE)

# Set common compilation flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fembed-bitcode -mios-simulator-version-min=13.0")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fembed-bitcode -mios-simulator-version-min=13.0")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -mios-simulator-version-min=13.0")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -mios-simulator-version-min=13.0")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -mios-simulator-version-min=13.0")

# Handle Xcode specific settings
set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH YES) # Often useful for faster builds in Xcode
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED NO)
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "")

# Standard CMake settings for cross-compiling
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)