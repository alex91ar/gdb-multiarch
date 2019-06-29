#!/bin/sh
#
# Copyright (C) 2012 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Rebuild the host GDB binaries from sources.
#

# include common function and variable definitions
. "$NDK_BUILDTOOLS_PATH/prebuilt-common.sh"
. "$NDK_BUILDTOOLS_PATH/common-build-host-funcs.sh"

PROGRAM_PARAMETERS=""
PROGRAM_DESCRIPTION="\
This program is used to rebuild one or more NDK gdb client programs from
sources.

By default, the script rebuilds GDB for your host system [$HOST_TAG],
but you can use --systems=<tag1>,<tag2>,.. to ask binaries that can run on
several distinct systems. Each <tag> value in the list can be one of the
following:

   linux-x86
   linux-x86_64
   windows
   windows-x86  (equivalent to 'windows')
   windows-x86_64
   darwin-x86
   darwin-x86_64

For example, here's how to rebuild the ARM toolchains on Linux
for four different systems:

  $PROGNAME --toolchain-src-dir=/path/to/toolchain/src \
    --systems=linux-x86,linux-x86_64,windows,windows-x86_64 \
    --arch=arm"

TOOLCHAIN_SRC_DIR=
register_var_option "--toolchain-src-dir=<path>" TOOLCHAIN_SRC_DIR "Select toolchain source directory"

GDB_VERSION=$DEFAULT_GDB_VERSION
register_var_option "--gdb-version=<version>" GDB_VERSION "Select GDB version(s)."

BUILD_DIR=
register_var_option "--build-dir=<path>" BUILD_DIR "Build GDB into directory"

PYTHON_VERSION=$DEFAULT_PYTHON_VERSION
register_var_option "--python-version=<version>" PYTHON_VERSION "Python version."

PYTHON_BUILD_DIR=
register_var_option "--python-build-dir=<path>" PYTHON_BUILD_DIR "Python build directory."

NDK_DIR=$ANDROID_NDK_ROOT
register_var_option "--ndk-dir=<path>" NDK_DIR "Select NDK install directory."

PACKAGE_DIR=
register_var_option "--package-dir=<path>" PACKAGE_DIR "Package prebuilt tarballs into directory."

ARCHS=$DEFAULT_ARCHS
register_var_option "--arch=<list>" ARCHS "Build GDB client for these CPU architectures."

bh_register_options

register_jobs_option

extract_parameters "$@"

if [ -n "$PARAMETERS" ]; then
    panic "This script doesn't take parameters, only options. See --help"
fi

if [ -z "$TOOLCHAIN_SRC_DIR" ]; then
    panic "Please use --toolchain-src-dir=<path> to select toolchain source directory."
fi

BH_HOST_SYSTEMS=$(commas_to_spaces $BH_HOST_SYSTEMS)

# Sanity check for all GDB versions
for VERSION in $(commas_to_spaces $GDB_VERSION); do
    GDB_SRCDIR=$TOOLCHAIN_SRC_DIR/gdb/gdb-$VERSION
    if [ ! -d "$GDB_SRCDIR" ]; then
        panic "Missing source directory: $GDB_SRCDIR"
    fi
done

if [ -z "$BUILD_DIR" ] ; then
    panic "--build-dir is required"
fi

if [ -z "$PYTHON_BUILD_DIR" ] ; then
    panic "--python-build-dir is required"
fi

INSTALL_DIR=$BUILD_DIR/install
BUILD_DIR=$BUILD_DIR/build

bh_setup_build_dir $BUILD_DIR

# Sanity check that we have the right compilers for all hosts
for SYSTEM in $BH_HOST_SYSTEMS; do
    bh_setup_build_for_host $SYSTEM
done

# Return the build install directory of a given GDB version
# $1: host system tag
# $2: gdb version
gdb_build_install_dir ()
{
    echo "$BH_BUILD_DIR/install/$1/gdb-multiarch-$2"
}

# $1: host system tag
# $2: gdb version
gdb_ndk_package_name ()
{
    echo "gdb-multiarch-$2-$1"
}


# Same as gdb_build_install_dir, but for the final NDK installation
# directory. Relative to $NDK_DIR.
# $1: gdb version
gdb_ndk_install_dir ()
{
    echo "host-tools/"
}

python_build_install_dir ()
{
    echo "$PYTHON_BUILD_DIR/$1/install/host-tools/"
}

# $1: host system tag
build_expat ()
{
    local ARGS
    local SRCDIR=$TOOLCHAIN_SRC_DIR/expat/expat-2.0.1
    local BUILDDIR=$BH_BUILD_DIR/build-expat-2.0.1-$1
    local INSTALLDIR=$BH_BUILD_DIR/install-host-$1

    ARGS=" --prefix=$INSTALLDIR"
    ARGS=$ARGS" --disable-shared --enable-static"
    ARGS=$ARGS" --build=$BH_BUILD_CONFIG"
    ARGS=$ARGS" --host=$BH_HOST_CONFIG"

    TEXT="$(bh_host_text) expat:"

    mkdir -p "$BUILDDIR" && rm -rf "$BUILDDIR"/* &&
    cd "$BUILDDIR" &&
    dump "$TEXT Building"
    run "$SRCDIR"/configure $ARGS &&
    run make -j$NUM_JOBS &&
    run make -j$NUM_JOBS install
}

# $1: host system tag
build_lzma ()
{
    local ARGS
    local SRCDIR=$TOOLCHAIN_SRC_DIR/xz
    local BUILDDIR=$BH_BUILD_DIR/build-xz-$1
    local INSTALLDIR=$BH_BUILD_DIR/install-host-$1

    ARGS=" --prefix=$INSTALLDIR"
    ARGS=$ARGS" --disable-shared --enable-static"
    ARGS=$ARGS" --disable-xz --disable-xzdec --disable-lzmadec --disable-scripts --disable-doc"
    ARGS=$ARGS" --build=$BH_BUILD_CONFIG"
    ARGS=$ARGS" --host=$BH_HOST_CONFIG"

    TEXT="$(bh_host_text) lzma:"

    mkdir -p "$BUILDDIR" && rm -rf "$BUILDDIR"/* &&
    cd "$BUILDDIR" &&
    dump "$TEXT Building"

    # HACK: git doesn't keep track of file modification date, so autoconf will sometimes (usually?)
    # want to regenerate itself. Trick it into not doing so by touching all of the source files.
    case "$BH_BUILD_CONFIG" in
      *darwin*)
        # Darwin's touch sucks.
        run find $SRCDIR -exec touch -t 197001010000 {} +
        ;;

      *)
        run find $SRCDIR -exec touch -d "`date`" {} +
        ;;
    esac

    run "$SRCDIR"/configure $ARGS &&
    run make -j$NUM_JOBS &&
    run make -j$NUM_JOBS install
}

# $1: host system tag
# $2: gdb version
# ${@:3}: target tags
build_host_gdb ()
{
    local SRCDIR=$TOOLCHAIN_SRC_DIR/gdb/gdb-$2
    local BUILDDIR=$BH_BUILD_DIR/build-gdb-$1-multiarch-$2
    local INSTALLDIR=$(gdb_build_install_dir $1 $2)
    local ARGS TEXT

    if [ ! -f "$SRCDIR/configure" ]; then
        panic "Missing configure script in $SRCDIR"
    fi

    bh_setup_host_env

    local TARGETS="$(bh_tag_to_config_triplet $1)"
    for ARCH in ${@:3}; do
        TARGETS="$TARGETS,$(bh_tag_to_config_triplet android-$ARCH)"
    done

    build_expat $1
    local EXPATPREFIX=$BH_BUILD_DIR/install-host-$1

    ARGS=" --prefix=$INSTALLDIR"
    ARGS=$ARGS" --disable-shared"

    case "$BH_BUILD_CONFIG" in
        # For some reason, multiarch + darwin doesn't build a gdb binary when
        # --build or --host are specified.
        *darwin*)
            ;;
        *)
            ARGS=$ARGS" --build=$BH_BUILD_CONFIG"
            ARGS=$ARGS" --host=$BH_HOST_CONFIG"
            ;;
    esac

    case "$1" in
      *windows)
        # The liblzma build fails when targeting windows32, for some reason.
        ;;

      *)
        build_lzma $1
        local LZMAPREFIX=$BH_BUILD_DIR/install-host-$1
        ARGS=$ARGS" --with-lzma"
        ARGS=$ARGS" --with-liblzma-prefix=$LZMAPREFIX"
        ;;
    esac

    ARGS=$ARGS" --enable-targets=$TARGETS"
    ARGS=$ARGS" --disable-werror"
    ARGS=$ARGS" --disable-nls"
    ARGS=$ARGS" --disable-docs"
    ARGS=$ARGS" --with-expat"
    ARGS=$ARGS" --with-libexpat-prefix=$EXPATPREFIX"
    ARGS=$ARGS" --without-mpc"
    ARGS=$ARGS" --without-mpfr"
    ARGS=$ARGS" --without-gmp"
    ARGS=$ARGS" --without-cloog"
    ARGS=$ARGS" --without-isl"
    ARGS=$ARGS" --disable-sim"
    ARGS=$ARGS" --enable-gdbserver=no"
    if [ -n "$PYTHON_VERSION" ]; then
        ARGS=$ARGS" --with-python=$(python_build_install_dir $1)/bin/python-config.sh"
        if [ $1 = windows-x86 -o $1 = windows-x86_64 ]; then
            # This is necessary for the Python integration to build.
            CFLAGS=$CFLAGS" -D__USE_MINGW_ANSI_STDIO=1"
            CXXFLAGS=$CXXFLAGS" -D__USE_MINGW_ANSI_STDIO=1"
        fi
    fi
    TEXT="$(bh_host_text) gdb-multiarch-$2:"

    mkdir -p "$BUILDDIR" && rm -rf "$BUILDDIR"/* &&
    cd "$BUILDDIR" &&
    dump "$TEXT Building"
    run "$SRCDIR"/configure $ARGS &&
    run make -j$NUM_JOBS &&
    run make -j$NUM_JOBS install
    fail_panic "Failed to configure/make/install gdb"
}

# Install host GDB binaries and support files to the NDK install dir.
# $1: host tag
# $2: gdb version
# ${@:3}: target tags
install_host_gdb ()
{
    local SRCDIR="$(gdb_build_install_dir $1 $2)"
    local DSTDIR="$INSTALL_DIR/$(gdb_ndk_install_dir $1)"
    local PYDIR="$INSTALL_DIR/$(python_ndk_install_dir $1)"

    build_host_gdb $@

    dump "$(bh_host_text) gdb-multiarch-$2: Installing"
    run copy_directory "$SRCDIR/bin" "$DSTDIR/bin"
    if [ -d "$SRCDIR/share/gdb" ]; then
        run copy_directory "$SRCDIR/share/gdb" "$DSTDIR/share/gdb"
    fi

    # build the gdb stub and replace gdb with it. This is done post-install
    # so files are in the correct place when determining the relative path.

    dump "$(bh_host_text) Generating gdb-stub..."
    case "$1" in
        windows*)
            GCC_FOR_STUB=${BH_HOST_CONFIG}-gcc
            GCC_FOR_STUB_TARGET=`$GCC_FOR_STUB -dumpmachine`
            if [ "$GCC_FOR_STUB_TARGET" = "i586-mingw32msvc" ]; then
                GCC_FOR_STUB=i686-w64-mingw32-gcc
                dump "Override compiler for gdb-stub: $GCC_FOR_STUB"
            fi

            run $NDK_BUILDTOOLS_PATH/build-gdb-stub.sh \
                --gdb-executable-path=${DSTDIR}/bin/gdb.exe \
                --python-prefix-dir=${PYDIR} \
                --mingw-w64-gcc=${GCC_FOR_STUB}
            fail_panic "Failed to build gdb-stub"
            ;;
        *)
            # Generate a script which sets PYTHONHOME
            GDB_PATH=${DSTDIR}/bin/gdb
            mv "$GDB_PATH" "$GDB_PATH"-orig
            cat > "$GDB_PATH" << EOF
#!/bin/bash
GDBDIR=\$(cd \$(dirname \$0) && pwd)
PYTHONHOME="\$GDBDIR/.." "\$GDBDIR/gdb-orig" "\$@"
EOF
            chmod 755 $GDB_PATH
            ;;
    esac
    dump "$(bh_host_text) Done generating gdb-stub."
}

# Package host GDB binaries into a tarball
# $1: host tag
# $2: gdb version
# ${@:3}: target tags
package_host_gdb ()
{
    local SRCDIR="$(gdb_ndk_install_dir $1)"
    local PACKAGENAME=$(gdb_ndk_package_name $1 $2).tar.bz2
    local PACKAGE="$PACKAGE_DIR/$PACKAGENAME"

    dump "$(bh_host_text) $PACKAGENAME: Packaging"
    run pack_archive "$PACKAGE" "$INSTALL_DIR" "$SRCDIR"
    fail_panic "Failed to package GDB!"
}

GDB_VERSION=$(commas_to_spaces $GDB_VERSION)
ARCHS=$(commas_to_spaces $ARCHS)

# Let's build this
for SYSTEM in $BH_HOST_SYSTEMS; do
    bh_setup_build_for_host $SYSTEM
    for VERSION in $GDB_VERSION; do
        install_host_gdb $SYSTEM $VERSION $ARCHS
    done
done

if [ "$PACKAGE_DIR" ]; then
    for SYSTEM in $BH_HOST_SYSTEMS; do
        bh_setup_build_for_host $SYSTEM
        for VERSION in $GDB_VERSION; do
            bh_do package_host_gdb $SYSTEM $VERSION $ARCHS
        done
    done
fi
