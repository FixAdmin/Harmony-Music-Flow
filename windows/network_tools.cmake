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

set(YT_DLP_VERSION "2026.11.23")
fetch_network_tool("yt-dlp.exe"
  "https://github.com/yt-dlp/yt-dlp/releases/download/${YT_DLP_VERSION}/yt-dlp.exe"
  "622ed48023cac1daa52a3bf3a6ac38f03514de214b5f0fa069389fd0f6d17e5c")
fetch_network_tool("node.exe"
  "https://nodejs.org/dist/v24.22.0/win-x64/node.exe"
  "ba93f9a70bd86fce3ebbb39ec758501458453467aa92a34a0a3602d1e3fc2b9c")

install(FILES "${CMAKE_CURRENT_LIST_DIR}/network_tools-NOTICE.txt"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/network_tools" COMPONENT Runtime)
install(FILES "${CMAKE_CURRENT_LIST_DIR}/../LICENSE" RENAME "GPL-3.0.txt"
  DESTINATION "${CMAKE_INSTALL_PREFIX}/network_tools" COMPONENT Runtime)

foreach(NAME IN ITEMS yt-dlp node)
  if(NAME STREQUAL "yt-dlp")
    set(LICENSE_URL "https://raw.githubusercontent.com/yt-dlp/yt-dlp/${YT_DLP_VERSION}/LICENSE")
    set(LICENSE_FILE "${NETWORK_TOOLS_DIR}/${NAME}-${YT_DLP_VERSION}-LICENSE.txt")
  else()
    set(LICENSE_URL "https://raw.githubusercontent.com/nodejs/node/v24.22.0/LICENSE")
    set(LICENSE_FILE "${NETWORK_TOOLS_DIR}/${NAME}-LICENSE.txt")
  endif()
  if(NOT EXISTS "${LICENSE_FILE}")
    file(DOWNLOAD "${LICENSE_URL}" "${LICENSE_FILE}" TLS_VERIFY ON)
  endif()
  install(FILES "${LICENSE_FILE}"
    RENAME "${NAME}-LICENSE.txt"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/network_tools" COMPONENT Runtime)
endforeach()
