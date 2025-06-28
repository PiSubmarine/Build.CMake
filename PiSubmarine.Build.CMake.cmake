cmake_minimum_required (VERSION 3.25)

include(FetchContent)

if (CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
	set(PISUBMARINE_GIT_TAG "main" CACHE STRING "Git tag to be used for PiSubmarine modules.")

	if(WIN32)
		add_compile_definitions(PISUBMARINE_WIN32)
	elseif(UNIX)
		add_compile_definitions(PISUBMARINE_UNIX)
	else()
		add_compile_definitions(PISUBMARINE_BAREMETAL)
	endif()
endif()

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/app")
    add_subdirectory("app")
endif()
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src")
    add_subdirectory("src")
endif()
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/test" AND (WIN32 OR UNIX))
    add_subdirectory("test")
endif()

enable_testing()

function(PiSubmarineAddDependency git_url git_tag)

    get_filename_component(repo_filename "${git_url}" NAME_WE)

    if(git_tag)
        set(_tag_to_use "${git_tag}")
    elseif(DEFINED PISUBMARINE_GIT_TAG)
        set(_tag_to_use "${PISUBMARINE_GIT_TAG}")
    else()
        message(FATAL_ERROR "No git_tag provided and no default (PISUBMARINE_GIT_TAG) set.")
    endif()

    FetchContent_Declare(
        ${repo_filename}
        GIT_REPOSITORY ${git_url}
        GIT_TAG        ${_tag_to_use}
        GIT_SHALLOW    TRUE
        GIT_PROGRESS   TRUE
    )

    FetchContent_MakeAvailable(${repo_filename})
endfunction()


function (PiSubmarineInitModule)
	# Enable Hot Reload for MSVC compilers if supported.
	if (POLICY CMP0141)
	  cmake_policy(SET CMP0141 NEW)
	  set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT "$<IF:$<AND:$<C_COMPILER_ID:MSVC>,$<CXX_COMPILER_ID:MSVC>>,$<$<CONFIG:Debug,RelWithDebInfo>:EditAndContinue>,$<$<CONFIG:Debug,RelWithDebInfo>:ProgramDatabase>>")
	endif()

endfunction()