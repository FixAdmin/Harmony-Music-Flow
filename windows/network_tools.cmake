# Pin the extractor and JS runtime; verify all executable downloads before use.
set(NETWORK_TOOLS_DIR "${CMAKE_BINARY_DIR}/network_tools")
file(MAKE_DIRECTORY "${NETWORK_TOOLS_DIR}")

function(fetch_network_tool NAME URL HASH)
  set(OUTPUT "${NETWORK_TOOLS_DIR}/${NAME}")
  if(EXISTS "${OUTPUT}")
    file(SHA256 "${OUTPUT}" CURRENT_HASH)
  endif()
  if(NOT CURRENT_HASH STREQUAL HASH)
    message(STATUS "Downloading bundled ${NAME}")
    file(DOWNLOAD "${URL}" "${OUTPUT}"
      EXPECTED_HASH "SHA256=${HASH}" TLS_VERIFY ON)
  endif()
  install(FILES "${OUTPUT}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/network_tools" COMPONENT Runtime)
endfunction()

fetch_network_tool("yt-dlp.exe"
  "https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp.exe"
  "66674953fe251b89f4d08c5f0e35e0728679bd67ab3d7d05c0562af101dd3e7a")
fetch_network_tool("node.exe"
  "https://nodejs.org/dist/v24.22.0/win-x64/node.exe"
  "ba93f9a70bd86fce3ebbb39ec758501458453467aa92a34a0a3602d1e3fc2b9c")

install(FILES "${CMAKE_CURRENT_LIST_DIR}/network_tools-NOTICE.txt"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/network_tools" COMPONENT Runtime)
install(FILES "${CMAKE_CURRENT_LIST_DIR}/../LICENSE" RENAME "GPL-3.0.txt"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/network_tools" COMPONENT Runtime)

foreach(NAME IN ITEMS yt-dlp node)
  if(NAME STREQUAL "yt-dlp")
    set(LICENSE_URL "https://raw.githubusercontent.com/yt-dlp/yt-dlp/2026.08.19/LICENSE")
  else()
    set(LICENSE_URL "https://raw.githubusercontent.com/nodejs/node/v24.22.0/LICENSE")
  endif()
  set(LICENSE_FILE "${NETWORK_TOOLS_DIR}/${NAME}-LICENSE.txt")
  if(NOT EXISTS "${LICENSE_FILE}")
    file(DOWNLOAD "${LICENSE_URL}" "${LICENSE_FILE}" TLS_VERIFY ON)
  endif()
  install(FILES "${LICENSE_FILE}"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/network_tools" COMPONENT Runtime)
endforeach()
