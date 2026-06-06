# Innovatech Control - Custom QGC Build
# Note: No spaces in app name due to CMake target name restrictions
set(QGC_APP_NAME "InnovatechControl" CACHE STRING "App Name" FORCE)
set(QGC_ORG_NAME "Innovatech" CACHE STRING "Org Name" FORCE)
set(QGC_ORG_DOMAIN "innovatech.local" CACHE STRING "Domain" FORCE)

# Version 1.0 - Stable build (removes "Daily" suffix)
set(QGC_STABLE_BUILD ON CACHE BOOL "Stable Build" FORCE)

set(QGC_MACOS_ICON_PATH "${CMAKE_SOURCE_DIR}/custom/res" CACHE PATH "MacOS Icon Path" FORCE)
set(QGC_APPIMAGE_ICON_PATH "${CMAKE_SOURCE_DIR}/custom/res/icons/custom_qgroundcontrol.png" CACHE FILEPATH "AppImage Icon Path" FORCE)

if(EXISTS ${CMAKE_SOURCE_DIR}/custom/deploy/windows/installheader.bmp)
    set(QGC_WINDOWS_INSTALL_HEADER_PATH "${CMAKE_SOURCE_DIR}/custom/deploy/windows/installheader.bmp" CACHE FILEPATH "Windows Install Header Path" FORCE)
endif()

if(EXISTS ${CMAKE_SOURCE_DIR}/custom/deploy/windows/WindowsQGC.ico)
    set(QGC_WINDOWS_ICON_PATH "${CMAKE_SOURCE_DIR}/custom/deploy/windows/WindowsQGC.ico" CACHE FILEPATH "Windows Icon Path" FORCE)
endif()

# Keep APM support enabled for broader drone compatibility
# APM plugins remain enabled (defaults from CustomOptions.cmake)

# Use custom PX4 plugin factory (disable default to avoid conflicts)
set(QGC_DISABLE_PX4_PLUGIN_FACTORY ON CACHE BOOL "Disable PX4 Plugin Factory" FORCE)
