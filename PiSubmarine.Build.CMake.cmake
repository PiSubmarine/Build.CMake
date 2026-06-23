cmake_minimum_required (VERSION 3.25)

include(FetchContent)

set(PISUBMARINE_BUILD_HASH_LENGTH 8 CACHE STRING "Length of the hash suffix used for shortened FetchContent names.")
set(PISUBMARINE_BUILD_MODULE_LENGTH_LIMIT 0 CACHE STRING "Maximum length for FetchContent names. Set to 0 to disable shortening.")

if(NOT PISUBMARINE_BUILD_HASH_LENGTH MATCHES "^[0-9]+$")
    message(FATAL_ERROR "PISUBMARINE_BUILD_HASH_LENGTH must be an integer.")
endif()

if(NOT PISUBMARINE_BUILD_MODULE_LENGTH_LIMIT MATCHES "^[0-9]+$")
    message(FATAL_ERROR "PISUBMARINE_BUILD_MODULE_LENGTH_LIMIT must be an integer.")
endif()

function(PiSubmarineGetModuleName REPO_URL OUT_VAR)
    # 1. Remove the trailing ".git" if it exists
    string(REGEX REPLACE "\\.git$" "" _clean_url "${REPO_URL}")

    # 2. Extract the organization and repository name
    if(_clean_url MATCHES "([^/:]+)/([^/]+)$")
        set(_org "${CMAKE_MATCH_1}")
        set(_repo "${CMAKE_MATCH_2}")

        # 3. Set the variable name contained in OUT_VAR in the parent scope
        set(${OUT_VAR} "${_org}.${_repo}" PARENT_SCOPE)
    else()
        message(FATAL_ERROR "Could not parse module name from URL: ${REPO_URL}")
        # Clear the variable in parent scope on failure
        set(${OUT_VAR} "" PARENT_SCOPE)
    endif()
endfunction()

function(PiSubmarineGetFetchContentName MODULE_NAME OUT_VAR)
    if(NOT MODULE_NAME)
        message(FATAL_ERROR "PiSubmarineGetFetchContentName: MODULE_NAME is empty")
    endif()

    if(PISUBMARINE_BUILD_MODULE_LENGTH_LIMIT EQUAL 0)
        set(${OUT_VAR} "${MODULE_NAME}" PARENT_SCOPE)
        return()
    endif()

    string(LENGTH "${MODULE_NAME}" _module_name_length)

    if(_module_name_length LESS_EQUAL PISUBMARINE_BUILD_MODULE_LENGTH_LIMIT)
        set(${OUT_VAR} "${MODULE_NAME}" PARENT_SCOPE)
        return()
    endif()

    math(EXPR _short_name_length "${PISUBMARINE_BUILD_MODULE_LENGTH_LIMIT} - 1 - ${PISUBMARINE_BUILD_HASH_LENGTH}")

    if(_short_name_length LESS 1)
        message(FATAL_ERROR "PISUBMARINE_BUILD_MODULE_LENGTH_LIMIT must be greater than PISUBMARINE_BUILD_HASH_LENGTH + 1.")
    endif()

    if(MODULE_NAME MATCHES "^[^.]+\\.(.+)$")
        set(_short_source "${CMAKE_MATCH_1}")
    else()
        set(_short_source "${MODULE_NAME}")
    endif()

    string(SUBSTRING "${_short_source}" 0 ${_short_name_length} _short_name)
    string(MD5 _module_name_hash "${MODULE_NAME}")
    string(SUBSTRING "${_module_name_hash}" 0 ${PISUBMARINE_BUILD_HASH_LENGTH} _short_hash)

    set(${OUT_VAR} "${_short_name}-${_short_hash}" PARENT_SCOPE)
endfunction()

function(PiSubmarineAddDependency git_url git_tag)

    # get_filename_component(repo_filename "${git_url}" NAME)
    PiSubmarineGetModuleName("${git_url}" repo_filename)
    PiSubmarineGetFetchContentName("${repo_filename}" fetchcontent_name)

    if(git_tag)
        set(_tag_to_use "${git_tag}")
    elseif(DEFINED PISUBMARINE_GIT_TAG)
        set(_tag_to_use "${PISUBMARINE_GIT_TAG}")
    else()
        message(FATAL_ERROR "No git_tag provided and no default (PISUBMARINE_GIT_TAG) set.")
    endif()

    FetchContent_Declare(
            ${fetchcontent_name}
            GIT_REPOSITORY ${git_url}
            GIT_TAG        ${_tag_to_use}
            GIT_SHALLOW    TRUE
            GIT_PROGRESS   TRUE
    )

    FetchContent_MakeAvailable(${fetchcontent_name})
endfunction()

function(PiSubmarineInitTarget target)
    if (NOT TARGET ${target})
        message(FATAL_ERROR "PiSubmarineInitTarget: '${target}' is not a valid target")
    endif()

    # Detect target type
    get_target_property(_type ${target} TYPE)

    if (_type STREQUAL "INTERFACE_LIBRARY")
        set(_scope INTERFACE)
    else()
        set(_scope PRIVATE)
    endif()

    set_target_properties(${target} PROPERTIES
            CXX_STANDARD 23
            CXX_STANDARD_REQUIRED ON
            CXX_EXTENSIONS OFF
    )

    # Enforce standard strictly
    set_target_properties(${target} PROPERTIES
            CXX_EXTENSIONS OFF
            CXX_STANDARD_REQUIRED ON
    )

    # MSVC runtime (only for real build targets)
    if (MSVC AND NOT _type STREQUAL "INTERFACE_LIBRARY")
        set_property(TARGET ${target} PROPERTY
                MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
        )
    endif()
endfunction()

function (PiSubmarineInitModule module_name)
    # Enable Hot Reload for MSVC compilers if supported.
    if (POLICY CMP0141)
        cmake_policy(SET CMP0141 NEW)
        set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT "$<IF:$<AND:$<C_COMPILER_ID:MSVC>,$<CXX_COMPILER_ID:MSVC>>,$<$<CONFIG:Debug,RelWithDebInfo>:EditAndContinue>,$<$<CONFIG:Debug,RelWithDebInfo>:ProgramDatabase>>")
    endif()

    if (module_name)
        set(PISUBMARINE_MODULE_NAME ${module_name} PARENT_SCOPE)
    else ()
        execute_process(
                COMMAND git config --get remote.origin.url
                WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
                OUTPUT_VARIABLE GIT_REMOTE_URL
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET
        )

        if(GIT_REMOTE_URL)
            PiSubmarineGetModuleName(${GIT_REMOTE_URL} PISUBMARINE_MODULE_NAME)
        else()
            message(FATAL_ERROR "Failed to get project name from git URL.")
        endif()

        set(PISUBMARINE_MODULE_NAME ${PISUBMARINE_MODULE_NAME} PARENT_SCOPE)
    endif ()

endfunction()

function(PiSubmarineConfigureModule)
    if(NOT PISUBMARINE_MODULE_NAME)
        message(FATAL_ERROR "PISUBMARINE_MODULE_NAME not set")
    endif()

    message("Configuring module: ${PISUBMARINE_MODULE_NAME}")

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

    if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/app")
        add_subdirectory("app")
    endif()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src")
        add_subdirectory("src")
    endif()
    if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/test" AND (WIN32 OR UNIX))
        add_subdirectory("test")
    endif()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/mock" AND (WIN32 OR UNIX))
        add_subdirectory("mock")
    endif()

    enable_testing()
endfunction()
