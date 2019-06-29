#!/usr/bin/env python
#
# Copyright (C) 2015 The Android Open Source Project
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
"""Builds GDB for Android."""
from __future__ import print_function

import os
import site

site.addsitedir(os.path.join(os.path.dirname(__file__), '../../ndk/build/lib'))


import build_support  # pylint: disable=import-error,wrong-import-position


def main(args):
    # Always build all architectures for gdb, since we're building multiarch
    arches = build_support.ALL_ARCHITECTURES

    toolchain_src_arg = '--toolchain-src-dir={}'.format(
        build_support.toolchain_path())
    ndk_dir_arg = '--ndk-dir={}'.format(build_support.ndk_path())
    arch_arg = '--arch={}'.format(','.join(arches))
    systems_arg = f'--systems={build_support.host_to_tag(args.host)}'

    build_cmd = [
        'bash', 'build-gdb.sh', toolchain_src_arg, ndk_dir_arg, arch_arg,
        systems_arg, build_support.jobs_arg(),
    ]

    build_cmd.append('--build-dir=' + os.path.join(args.out_dir, 'gdb'))
    build_cmd.append(
        '--python-build-dir=' + os.path.join(args.out_dir, 'python'))

    print('Building {} gdb: {}'.format(args.host.value, ' '.join(arches)))
    print(' '.join(build_cmd))
    build_support.build(build_cmd, args, intermediate_package=True)


if __name__ == '__main__':
    build_support.run(main)
