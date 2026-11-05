#!/usr/bin/env bash
# Builds curl 8 (libcurl, static) as an autobuild package for Vulkanstorm,
# against the Vulkanstorm OpenSSL 3.5 package, nghttp2 and zlib-ng.
#
# Changes against secondlife/3p-curl (7.54.1):
#   - source: the signed curl release tarball, SHA-256 pinned below, instead
#     of the vendored 7.54.1 tree (see README.md for the signature check);
#   - HTTP and HTTPS only: every other protocol is compiled out; no libidn2,
#     libpsl, brotli, zstd, libssh2/libssh, LDAP, GSSAPI, NTLM or HTTP/3;
#   - OpenSSL, zlib-ng and nghttp2 are given to CMake's own find modules
#     explicitly, so nothing from the build machine can be picked up;
#   - a smoke test checks the version line, the protocol list and the
#     feature list of the built curl tool.

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" ]] ; then
    # need igncr so cygwin bash will trim both '\r\n' from $(command)
    set -o igncr
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
    # dummy to avoid tedious conditionals everywhere
    function cygpath {
        # pathname comes last after switches
        local last
        eval last=\$$#
        echo "$last"
    }
fi

CURL_VERSION="8.23.0"
CURL_SHA256="e3de77cfa6367083c776a26647fc9f633b538c06c3baa73d931a252ac8f72b49"
CURL_URL="https://curl.se/download/curl-${CURL_VERSION}.tar.gz"

top="$(pwd)"
stage="$top/stage"
CURL_SOURCE_DIR="$top/curl-${CURL_VERSION}"
CURL_BUILD_DIR="$top/build"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

ZLIB_INCLUDE="${stage}"/packages/include/zlib-ng
OPENSSL_INCLUDE="${stage}"/packages/include/openssl

[ -f "$ZLIB_INCLUDE"/zlib.h ] || fail "You haven't installed the zlib package yet."
[ -f "$OPENSSL_INCLUDE"/ssl.h ] || fail "You haven't installed the openssl package yet."

sha256_of ()
{
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# Fetch (or reuse) the release tarball and check it against the pinned digest.
# CURL_TARBALL may name an already downloaded copy; it is checked the same way.
mkdir -p "$top/dl"
tarball="$top/dl/curl-${CURL_VERSION}.tar.gz"
if [ -n "${CURL_TARBALL:-}" ]; then
    cp -f "$CURL_TARBALL" "$tarball"
elif [ ! -f "$tarball" ]; then
    curl -sSfL --retry 3 -o "$tarball" "$CURL_URL"
fi
actual_sha256="$(sha256_of "$tarball")"
if [ "$actual_sha256" != "$CURL_SHA256" ]; then
    echo "SHA-256 mismatch for $tarball: $actual_sha256" 1>&2
    exit 1
fi
rm -rf "$CURL_SOURCE_DIR" "$CURL_BUILD_DIR"
tar -xzf "$tarball" -C "$top"
# Clear what an earlier build staged (stage/packages holds the dependencies);
# stale headers would otherwise go into the package through include/curl/*.h.
rm -rf "$stage/include/curl" "$stage/lib" "$stage/bin" "$stage/LICENSES" "$stage/docs" "$stage/share"

version="$(sed -nE 's/#define LIBCURL_VERSION "([^"]+)".*$/\1/p' \
           "$(cygpath -m "${CURL_SOURCE_DIR}/include/curl/curlver.h")")"
[ "$version" = "$CURL_VERSION" ] || fail "curlver.h says $version, expected $CURL_VERSION"
# autobuild reads version_file from the build directory
cp -f "$top/VERSION.txt" "$stage/VERSION.txt"

# Restore all .sos
restore_sos ()
{
    for solib in "${stage}"/packages/lib/release/lib*.so*.disable; do
        if [ -f "$solib" ]; then
            mv -f "$solib" "${solib%.disable}"
        fi
    done
}

# Restore all .dylibs
restore_dylibs ()
{
    for dylib in "$stage/packages/lib"/release/*.dylib.disable; do
        if [ -f "$dylib" ]; then
            mv "$dylib" "${dylib%.disable}"
        fi
    done
}

# Options shared by every platform. The viewer needs HTTP and HTTPS with
# cookies (in memory), proxies (HTTP, SOCKS), MIME (Linux crash reports) and
# HTTP/2 through nghttp2; nothing else.
common_opts=(
    -DBUILD_SHARED_LIBS:BOOL=OFF
    -DBUILD_STATIC_LIBS:BOOL=ON
    -DBUILD_CURL_EXE:BOOL=ON
    -DBUILD_STATIC_CURL:BOOL=ON
    -DBUILD_TESTING:BOOL=OFF
    -DBUILD_EXAMPLES:BOOL=OFF
    -DBUILD_LIBCURL_DOCS:BOOL=OFF
    -DBUILD_MISC_DOCS:BOOL=OFF
    -DENABLE_CURL_MANUAL:BOOL=OFF
    -DCURL_LTO:BOOL=OFF
    -DCURL_USE_PKGCONFIG:BOOL=OFF
    -DCURL_USE_CMAKECONFIG:BOOL=OFF
    -DCURL_USE_OPENSSL:BOOL=ON
    -DOPENSSL_USE_STATIC_LIBS:BOOL=ON
    -DUSE_NGHTTP2:BOOL=ON
    -DCURL_ZLIB:BOOL=ON
    -DENABLE_THREADED_RESOLVER:BOOL=ON
    -DENABLE_ARES:BOOL=OFF
    -DUSE_LIBIDN2:BOOL=OFF
    -DCURL_USE_LIBPSL:BOOL=OFF
    -DCURL_BROTLI:BOOL=OFF
    -DCURL_ZSTD:BOOL=OFF
    -DCURL_USE_LIBSSH2:BOOL=OFF
    -DCURL_USE_LIBSSH:BOOL=OFF
    -DCURL_USE_GSSAPI:BOOL=OFF
    -DCURL_USE_GSASL:BOOL=OFF
    -DUSE_NGTCP2:BOOL=OFF
    -DUSE_QUICHE:BOOL=OFF
    -DCURL_ENABLE_NTLM:BOOL=OFF
    -DCURL_DISABLE_LDAP:BOOL=ON
    -DCURL_DISABLE_LDAPS:BOOL=ON
    -DCURL_DISABLE_DICT:BOOL=ON
    -DCURL_DISABLE_FILE:BOOL=ON
    -DCURL_DISABLE_FTP:BOOL=ON
    -DCURL_DISABLE_GOPHER:BOOL=ON
    -DCURL_DISABLE_IMAP:BOOL=ON
    -DCURL_DISABLE_IPFS:BOOL=ON
    -DCURL_DISABLE_MQTT:BOOL=ON
    -DCURL_DISABLE_POP3:BOOL=ON
    -DCURL_DISABLE_RTSP:BOOL=ON
    -DCURL_DISABLE_SMTP:BOOL=ON
    -DCURL_DISABLE_TELNET:BOOL=ON
    -DCURL_DISABLE_TFTP:BOOL=ON
    -DCURL_DISABLE_WEBSOCKETS:BOOL=ON
)

# The curl tool's first --version line, protocols and features must match
# the configuration above.
smoke_test ()
{
    local exe="$1"
    local out
    out="$("$exe" --version | tr -d '\r')"
    echo "$out"
    local first protocols features
    first="$(echo "$out" | head -n 1)"
    protocols="$(echo "$out" | sed -n 's/^Protocols: //p')"
    features="$(echo "$out" | sed -n 's/^Features: //p')"
    expr "$first" : "curl ${version//./\\.} " > /dev/null
    expr "$first" : ".* libcurl/${version//./\\.} " > /dev/null
    expr "$first" : ".* OpenSSL/3\.5\." > /dev/null
    expr "$first" : ".* zlib/" > /dev/null
    expr "$first" : ".* nghttp2/" > /dev/null
    [ "$protocols" = "http https" ] || fail "unexpected protocols: $protocols"
    for want in AsynchDNS HTTP2 HTTPS-proxy libz SSL threadsafe; do
        echo " $features " | grep -q " $want " || fail "feature $want missing: $features"
    done
    for unwanted in IDN PSL brotli zstd NTLM Kerberos SPNEGO GSS-API HTTP3; do
        if echo " $features " | grep -q " $unwanted "; then
            fail "unwanted feature $unwanted: $features"
        fi
    done
}

mkdir -p "$CURL_BUILD_DIR"

pushd "$CURL_BUILD_DIR"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            opts="$(replace_switch /Zi /Z7 $LL_BUILD_RELEASE)"
            plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

            packages="$(cygpath -m "$stage/packages")"
            load_vsvars

            # LL_BUILD_RELEASE defines UNICODE/_UNICODE; ENABLE_UNICODE makes
            # curl's own Windows code agree with that. With MSVC, CMake's
            # FindOpenSSL derives OPENSSL_*_LIBRARY from LIB_EAY_RELEASE and
            # SSL_EAY_RELEASE, so those name the libraries.
            cmake "$(cygpath -m "${CURL_SOURCE_DIR}")" \
                -G"$AUTOBUILD_WIN_CMAKE_GEN" -A"$AUTOBUILD_WIN_VSPLATFORM" \
                -DCMAKE_C_FLAGS:STRING="$plainopts -DNGHTTP2_STATICLIB" \
                -DCMAKE_CXX_FLAGS:STRING="$opts" \
                -DCMAKE_MSVC_RUNTIME_LIBRARY:STRING=MultiThreadedDLL \
                -DENABLE_UNICODE:BOOL=ON \
                "${common_opts[@]}" \
                -DOPENSSL_INCLUDE_DIR:PATH="$packages/include" \
                -DLIB_EAY_RELEASE:FILEPATH="$packages/lib/release/libcrypto.lib" \
                -DSSL_EAY_RELEASE:FILEPATH="$packages/lib/release/libssl.lib" \
                -DZLIB_INCLUDE_DIR:PATH="$packages/include/zlib-ng" \
                -DZLIB_LIBRARY:FILEPATH="$packages/lib/release/zlib.lib" \
                -DNGHTTP2_INCLUDE_DIR:PATH="$packages/include" \
                -DNGHTTP2_LIBRARY:FILEPATH="$packages/lib/release/nghttp2.lib" \
                -DCMAKE_INSTALL_PREFIX="$(cygpath -m "$stage")"

            cmake --build . --config Release -j$AUTOBUILD_CPU_COUNT
            cmake --install . --config Release

            # Stage archives
            mkdir -p "${stage}/lib/release"
            mv "${stage}/lib/libcurl.lib" "${stage}"/lib/release/

            smoke_test "${stage}/bin/curl.exe"
        ;;

        darwin*)
            export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

            for arch in x86_64 arm64 ; do
                ARCH_ARGS="-arch $arch"
                cxx_opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
                cc_opts="$(remove_cxxstd $cxx_opts)"
                cc_opts="$(remove_switch -stdlib=libc++ $cc_opts)"
                ld_opts="$ARCH_ARGS"

                mkdir -p "build_$arch"
                pushd "build_$arch"
                    CFLAGS="$cc_opts" \
                    CXXFLAGS="$cxx_opts" \
                    LDFLAGS="$ld_opts" \
                    cmake "${CURL_SOURCE_DIR}" -G Ninja -DCMAKE_BUILD_TYPE=Release \
                        -DCMAKE_C_FLAGS:STRING="$cc_opts -DNGHTTP2_STATICLIB" \
                        -DCMAKE_CXX_FLAGS:STRING="$cxx_opts" \
                        "${common_opts[@]}" \
                        -DOPENSSL_INCLUDE_DIR:PATH="$stage/packages/include" \
                        -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="$stage/packages/lib/release/libcrypto.a" \
                        -DOPENSSL_SSL_LIBRARY:FILEPATH="$stage/packages/lib/release/libssl.a" \
                        -DZLIB_INCLUDE_DIR:PATH="$stage/packages/include/zlib-ng" \
                        -DZLIB_LIBRARY:FILEPATH="$stage/packages/lib/release/libz.a" \
                        -DNGHTTP2_INCLUDE_DIR:PATH="$stage/packages/include" \
                        -DNGHTTP2_LIBRARY:FILEPATH="$stage/packages/lib/release/libnghttp2.a" \
                        -DCMAKE_INSTALL_PREFIX="$stage" \
                        -DCMAKE_INSTALL_LIBDIR="$stage/lib/release/$arch" \
                        -DCMAKE_OSX_ARCHITECTURES="$arch" \
                        -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET}

                    cmake --build . --config Release -j$AUTOBUILD_CPU_COUNT
                    cmake --install . --config Release
                    if [ "$arch" = "$(uname -m)" ]; then
                        smoke_test "${stage}/bin/curl"
                    fi
                popd
            done

            # create fat libraries
            lipo -create -output ${stage}/lib/release/libcurl.a ${stage}/lib/release/x86_64/libcurl.a ${stage}/lib/release/arm64/libcurl.a
        ;;

        linux*)
            # Default target per --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"
            plainopts="$(remove_cxxstd $opts)"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Force static linkage to libz and openssl by moving .sos out of the way
            trap restore_sos EXIT
            for solib in "${stage}"/packages/lib/release/lib{z,ssl,crypto,nghttp2}.so*; do
                if [ -f "$solib" ]; then
                    mv -f "$solib" "$solib".disable
                fi
            done

            mkdir -p "$stage/lib/release"

            cmake "${CURL_SOURCE_DIR}" -G"Ninja" -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_C_FLAGS:STRING="$plainopts -DNGHTTP2_STATICLIB" \
                -DCMAKE_CXX_FLAGS:STRING="$opts" \
                "${common_opts[@]}" \
                -DOPENSSL_INCLUDE_DIR:PATH="$stage/packages/include" \
                -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="$stage/packages/lib/release/libcrypto.a" \
                -DOPENSSL_SSL_LIBRARY:FILEPATH="$stage/packages/lib/release/libssl.a" \
                -DZLIB_INCLUDE_DIR:PATH="$stage/packages/include/zlib-ng" \
                -DZLIB_LIBRARY:FILEPATH="$stage/packages/lib/release/libz.a" \
                -DNGHTTP2_INCLUDE_DIR:PATH="$stage/packages/include" \
                -DNGHTTP2_LIBRARY:FILEPATH="$stage/packages/lib/release/libnghttp2.a" \
                -DCMAKE_INSTALL_PREFIX="$stage" \
                -DCMAKE_INSTALL_LIBDIR=lib/release

            cmake --build . --config Release -j$AUTOBUILD_CPU_COUNT
            cmake --install . --config Release

            smoke_test "${stage}/bin/curl"
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp "${CURL_SOURCE_DIR}"/COPYING "$stage/LICENSES/curl.txt"
popd
rm -rf "$CURL_BUILD_DIR"

mkdir -p "$stage"/docs/curl/
cp -a "$top"/README.md "$stage"/docs/curl/README.Vulkanstorm.md
