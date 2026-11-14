# OEP launcher sources.
#
# This file is added to the krkrz_ios build with -DOEP_APP_DIR=<OEP/ios>; the hook
# in the (patched) krkrz_ios CMakeLists.txt calls add_subdirectory() after the
# engine target exists.  The launcher is compiled into the engine's own app
# bundle target so that SDL keeps its UIKit delegate and the engine stays a
# statically linked library.

if(NOT TARGET krkrz)
    message(FATAL_ERROR "OEP: target 'krkrz' does not exist; krkrz_ios must include OEP/ios after the engine")
endif()

set(OEP_IOS_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(OEP_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../core")

set(OEP_SWIFT_SOURCES
    App/Model.swift
    App/Bridge.swift
    App/BundledContent.swift
    App/LibraryStore.swift
    App/ImportService.swift
    App/SessionController.swift
    App/Theme.swift
    App/SharedViews.swift
    App/RootView.swift
    App/HomeView.swift
    App/LibraryView.swift
    App/GameDetailView.swift
    App/AddGameView.swift
    App/DocumentPicker.swift
    App/SettingsView.swift
    App/DiagnosticsView.swift
    App/SecondaryViews.swift
    App/SessionOverlays.swift
)

set(OEP_HOST_SOURCES
    Host/OEPHostMain.mm
    Host/OEPEngineHost.mm
    Host/OEPCoreBridge.mm
)

# Portable core (XP3 reader, engine detection, scan, log).  Built as a static
# library; the tools and tests are built separately on the development machine.
set(OEP_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(OEP_BUILD_CLI OFF CACHE BOOL "" FORCE)
add_subdirectory("${OEP_CORE_DIR}" "${CMAKE_BINARY_DIR}/oep_core")

target_sources(krkrz PRIVATE ${OEP_SWIFT_SOURCES} ${OEP_HOST_SOURCES})
target_link_libraries(krkrz PRIVATE oep_core)
target_include_directories(krkrz PRIVATE
    "${OEP_IOS_DIR}/Host"
    "${OEP_CORE_DIR}/include"
)

target_compile_definitions(krkrz PRIVATE OEP_HOST_APP=1)
target_compile_definitions(krkrz PRIVATE "OEP_ENGINE_VERSION=\"KiriKiri Z 1.2.0.3 (TJS2 2.4.28)\"")

set_target_properties(krkrz PROPERTIES
    XCODE_ATTRIBUTE_SWIFT_VERSION "5.0"
    XCODE_ATTRIBUTE_SWIFT_STRICT_CONCURRENCY "minimal"
    XCODE_ATTRIBUTE_SWIFT_OBJC_BRIDGING_HEADER "${OEP_IOS_DIR}/Host/OEPHost-Bridging-Header.h"
    XCODE_ATTRIBUTE_CLANG_ENABLE_MODULES "YES"
    XCODE_ATTRIBUTE_ENABLE_MODULES "YES"
    XCODE_ATTRIBUTE_SWIFT_EMIT_LOC_STRINGS "NO"
)

# The launcher must see the same iOS deployment target as the engine (16.0).
if(DEFINED APP_DEPLOYMENT_TARGET)
    set_target_properties(krkrz PROPERTIES
        XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "${APP_DEPLOYMENT_TARGET}")
endif()

message(STATUS "[OEP] launcher sources added to target krkrz (${OEP_IOS_DIR})")
