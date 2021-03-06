using BinaryBuilder

# CUDA is weirdly organized, with several tools in bin/lib directories, some in dedicated
# subproject folders, and others in a catch-all extras/ directory. to simplify use of
# the resulting binaries, we reorganize everything using a flat bin/lib structure.

name = "CUDA"
tag = v"0.1.4"

dependencies = []

# since this is a multi-version builder, make it possible to specify which version to build
function extract_flag(flag, val = nothing)
    for f in ARGS
        if startswith(f, flag)
            # Check if it's just `--flag` or if it's `--flag=foo`
            if f != flag
                val = split(f, '=')[2]
            end

            # Drop this value from our ARGS
            filter!(x -> x != f, ARGS)
            return (true, val)
        end
    end
    return (false, val)
end
_, requested_version = extract_flag("--version")
requested_version = VersionNumber(requested_version)
wants_version(ver::VersionNumber) = requested_version === nothing || requested_version == ver

# we really don't want to download all sources when only building a single target,
# so make it possible to request so (this especially matters on Travis CI)
requested_targets = filter(f->!startswith(f, "--"), ARGS)
wants_target(target::String) = isempty(requested_targets) || target in requested_targets
wants_target(regex::Regex) = isempty(requested_targets) || any(target->occursin(regex, target), requested_targets)


#
# CUDA 10.2
#

cuda_version = v"10.2.89"

sources_linux = [
    "http://developer.download.nvidia.com/compute/cuda/10.2/Prod/local_installers/cuda_10.2.89_440.33.01_linux.run" =>
    "560d07fdcf4a46717f2242948cd4f92c5f9b6fc7eae10dd996614da913d5ca11"
]
sources_macos = [
    "http://developer.download.nvidia.com/compute/cuda/10.2/Prod/local_installers/cuda_10.2.89_mac.dmg" =>
    "51193fff427aad0a3a15223b1a202a6c6f0964fcc6fb0e6c77ca7cd5b6944d20"
]
sources_windows = [
    "http://developer.download.nvidia.com/compute/cuda/10.2/Prod/local_installers/cuda_10.2.89_441.22_win10.exe" =>
    "b538271c4d9ffce1a8520bf992d9bd23854f0f29cee67f48c6139e4cf301e253"
]

script = raw"""
cd ${WORKSPACE}/srcdir

# use a temporary directory to avoid running out of tmpfs in srcdir on Travis
temp=${WORKSPACE}/tmpdir
mkdir ${temp}

apk add p7zip

if [[ ${target} == x86_64-linux-gnu ]]; then
    sh *-cuda_*_linux.run --tmpdir="${temp}" --target "${temp}" --noexec
    cd ${temp}/builds/cuda-toolkit
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mv bin ${prefix}
    mv targets/x86_64-linux/lib ${prefix}

    # nested
    for project in nvvm extras/CUPTI; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]]   && mv ${project}/bin/*   ${prefix}/bin
        [[ -d ${project}/lib64 ]] && mv ${project}/lib64/* ${prefix}/lib
    done
    mv nvvm/libdevice ${prefix}/share

    # clean up
    rm    ${prefix}/bin/{nvcc,nvcc.profile,cicc,cudafe++}       # CUDA C/C++ compiler
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/bin2c                                   # C/C++ utilities
    rm    ${prefix}/bin/{nvprof,nvvp,nsight,computeprof}        # profiling
    rm    ${prefix}/bin/{cuda-memcheck,cuda-gdb,cuda-gdbserver} # debugging
    rm    ${prefix}/lib/*_static*.a                             # we can't link statically
    rm -r ${prefix}/lib/stubs/                                  # stubs are a C/C++ thing
    rm    ${prefix}/bin/nsight_ee_plugins_manage.sh
    rm    ${prefix}/bin/cuda-uninstaller
elif [[ ${target} == x86_64-w64-mingw32 ]]; then
    7z x *-cuda_*_win10.exe -o${temp}
    cd ${temp}
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mkdir -p ${prefix}/bin ${prefix}/lib

    # nested
    for project in cuobjdump memcheck nvcc nvcc/nvvm nvdisasm curand cusparse npp cufft \
                   cublas cudart cusolver nvrtc nvgraph nvprof nvprune; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]] && mv ${project}/bin/* ${prefix}/bin
        [[ -d ${project}/lib/x64 ]] && mv ${project}/lib/x64/* ${prefix}/lib
    done
    mv nvcc/nvvm/libdevice ${prefix}/share
    mv cupti/extras/CUPTI/lib64/* ${prefix}/bin/

    # fixup
    chmod +x ${prefix}/bin/*.exe

    # clean up
    rm    ${prefix}/bin/{nvcc,cicc,cudafe++}.exe   # CUDA C/C++ compiler
    rm    ${prefix}/bin/nvcc.profile
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/bin2c.exe                               # C/C++ utilities
    rm    ${prefix}/bin/nvprof.exe                              # profiling
    rm    ${prefix}/bin/cuda-memcheck.exe                       # debugging
    rm    ${prefix}/lib/*_static*.lib                           # we can't link statically
elif [[ ${target} == x86_64-apple-darwin* ]]; then
    7z x *-cuda_*_mac.dmg 5.hfs -o${temp}
    cd ${temp}
    7z x 5.hfs
    tar -zxf CUDAMacOSXInstaller/CUDAMacOSXInstaller.app/Contents/Resources/payload/cuda_mac_installer_tk.tar.gz
    cd Developer/NVIDIA/CUDA-*/
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mv bin ${prefix}
    mv lib ${prefix}

    # nested
    mv nvvm/lib/* ${prefix}/lib
    mv nvvm/libdevice ${prefix}/share
    mv extras/CUPTI/lib64/* ${prefix}/lib

    # clean up
    rm    ${prefix}/bin/{nvcc,nvcc.profile,cudafe++}            # CUDA C/C++ compiler
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/bin2c                                   # C/C++ utilities
    rm    ${prefix}/bin/{nvprof,nvvp,nsight,computeprof}        # profiling
    rm    ${prefix}/bin/cuda-memcheck                           # debugging
    rm    ${prefix}/lib/*_static*.a                             # we can't link statically
    rm -r ${prefix}/lib/stubs/                                  # stubs are a C/C++ thing
    rm    ${prefix}/bin/uninstall_cuda_*.pl
    rm    ${prefix}/bin/nsight_ee_plugins_manage.sh
    rm    ${prefix}/bin/.cuda_toolkit_uninstall_manifest_do_not_delete.txt
fi
"""

products = [
    ExecutableProduct("nvdisasm", :nvdisasm),
    ExecutableProduct("cuobjdump", :cuobjdump),
    ExecutableProduct("fatbinary", :fatbinary),
    ExecutableProduct("ptxas", :ptxas),
    ExecutableProduct("nvprune", :nvprune),
    ExecutableProduct("nvlink", :nvlink),
    FileProduct("share/libdevice/libdevice.10.bc", :libdevice),
    LibraryProduct(["libcudart", "cudart64_102"], :libcudart),
    LibraryProduct(["libcufft", "cufft64_10"], :libcufft),
    LibraryProduct(["libcufftw", "cufftw64_10"], :libcufftw),
    LibraryProduct(["libcurand", "curand64_10"], :libcurand),
    LibraryProduct(["libcublas", "cublas64_10"], :libcublas),
    LibraryProduct(["libcusolver", "cusolver64_10"], :libcusolver),
    LibraryProduct(["libcusparse", "cusparse64_10"], :libcusparse),
    FileProduct(["lib/libcudadevrt.a", "lib/cudadevrt.lib"], :libcudadevrt),
]

if wants_version(v"10.2")
    version = VersionNumber("$(cuda_version)-$(tag)")
    if wants_target("x86_64-linux-gnu")
        build_tarballs(ARGS, name, version, sources_linux, script, [Linux(:x86_64)], products, dependencies)
    end
    if wants_target(r"x86_64-apple-darwin")
        build_tarballs(ARGS, name, version, sources_macos, script, [MacOS(:x86_64)], products, dependencies)
    end
    if wants_target("x86_64-w64-mingw32")
        build_tarballs(ARGS, name, version, sources_windows, script, [Windows(:x86_64)], products, dependencies)
    end
end


#
# CUDA 10.1
#

cuda_version = v"10.1.243"

sources_linux = [
    "http://developer.download.nvidia.com/compute/cuda/10.1/Prod/local_installers/cuda_10.1.243_418.87.00_linux.run" =>
    "e7c22dc21278eb1b82f34a60ad7640b41ad3943d929bebda3008b72536855d31"
]
sources_macos = [
    "http://developer.download.nvidia.com/compute/cuda/10.1/Prod/local_installers/cuda_10.1.243_mac.dmg" =>
    "432a2f07a793f21320edc5d10e7f68a8e4e89465c31e1696290bdb0ca7c8c997"
]
sources_windows = [
    "http://developer.download.nvidia.com/compute/cuda/10.1/Prod/local_installers/cuda_10.1.243_426.00_win10.exe" =>
    "35d3c99c58dd601b2a2caa28f44d828cae1eaf8beb70702732585fa001cd8ad7"
]

script = raw"""
cd ${WORKSPACE}/srcdir

# use a temporary directory to avoid running out of tmpfs in srcdir on Travis
temp=${WORKSPACE}/tmpdir
mkdir ${temp}

apk add p7zip

if [[ ${target} == x86_64-linux-gnu ]]; then
    sh *-cuda_*_linux.run --tmpdir="${temp}" --target "${temp}" --noexec
    cd ${temp}/builds/cuda-toolkit
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mv bin ${prefix}
    mv targets/x86_64-linux/lib ${prefix}

    # nested
    for project in nvvm extras/CUPTI; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]]   && mv ${project}/bin/*   ${prefix}/bin
        [[ -d ${project}/lib64 ]] && mv ${project}/lib64/* ${prefix}/lib
    done
    mv nvvm/libdevice ${prefix}/share

    # clean up
    rm    ${prefix}/bin/{nvcc,nvcc.profile,cicc,cudafe++}       # CUDA C/C++ compiler
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/{gpu-library-advisor,bin2c}             # C/C++ utilities
    rm    ${prefix}/bin/{nvprof,nvvp,nsight,computeprof}        # profiling
    rm    ${prefix}/bin/{cuda-memcheck,cuda-gdb,cuda-gdbserver} # debugging
    rm    ${prefix}/lib/*_static*.a                             # we can't link statically
    rm -r ${prefix}/lib/stubs/                                  # stubs are a C/C++ thing
    rm    ${prefix}/bin/nsight_ee_plugins_manage.sh
    rm    ${prefix}/bin/cuda-uninstaller
elif [[ ${target} == x86_64-w64-mingw32 ]]; then
    7z x *-cuda_*_win10.exe -o${temp}
    cd ${temp}
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mkdir -p ${prefix}/bin ${prefix}/lib

    # nested
    for project in cuobjdump memcheck nvcc nvcc/nvvm nvdisasm curand cusparse npp cufft \
                   cublas cudart cusolver nvrtc nvgraph nvprof nvprune; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]] && mv ${project}/bin/* ${prefix}/bin
        [[ -d ${project}/lib/x64 ]] && mv ${project}/lib/x64/* ${prefix}/lib
    done
    mv nvcc/nvvm/libdevice ${prefix}/share
    mv cupti/extras/CUPTI/lib64/* ${prefix}/bin/

    # fixup
    chmod +x ${prefix}/bin/*.exe

    # clean up
    rm    ${prefix}/bin/{nvcc,cicc,cudafe++}.exe   # CUDA C/C++ compiler
    rm    ${prefix}/bin/nvcc.profile
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/bin2c.exe                               # C/C++ utilities
    rm    ${prefix}/bin/nvprof.exe                              # profiling
    rm    ${prefix}/bin/cuda-memcheck.exe                       # debugging
    rm    ${prefix}/lib/*_static*.lib                           # we can't link statically
elif [[ ${target} == x86_64-apple-darwin* ]]; then
    7z x *-cuda_*_mac.dmg 5.hfs -o${temp}
    cd ${temp}
    7z x 5.hfs
    tar -zxf CUDAMacOSXInstaller/CUDAMacOSXInstaller.app/Contents/Resources/payload/cuda_mac_installer_tk.tar.gz
    cd Developer/NVIDIA/CUDA-*/
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mv bin ${prefix}
    mv lib ${prefix}

    # nested
    for project in nvvm extras/CUPTI; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]] && mv ${project}/bin/* ${prefix}/bin
        [[ -d ${project}/lib ]] && mv ${project}/lib/* ${prefix}/lib
    done
    mv nvvm/libdevice ${prefix}/share

    # clean up
    rm    ${prefix}/bin/{nvcc,nvcc.profile,cicc,cudafe++}       # CUDA C/C++ compiler
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/{gpu-library-advisor,bin2c}             # C/C++ utilities
    rm    ${prefix}/bin/{nvprof,nvvp,nsight,computeprof}        # profiling
    rm    ${prefix}/bin/cuda-memcheck                           # debugging
    rm    ${prefix}/lib/*_static*.a                             # we can't link statically
    rm -r ${prefix}/lib/stubs/                                  # stubs are a C/C++ thing
    rm    ${prefix}/bin/uninstall_cuda_*.pl
    rm    ${prefix}/bin/nsight_ee_plugins_manage.sh
    rm    ${prefix}/bin/.cuda_toolkit_uninstall_manifest_do_not_delete.txt
fi
"""

products = [
    ExecutableProduct("nvdisasm", :nvdisasm),
    ExecutableProduct("cuobjdump", :cuobjdump),
    ExecutableProduct("fatbinary", :fatbinary),
    ExecutableProduct("ptxas", :ptxas),
    ExecutableProduct("nvprune", :nvprune),
    ExecutableProduct("nvlink", :nvlink),
    FileProduct("share/libdevice/libdevice.10.bc", :libdevice),
    LibraryProduct(["libcudart", "cudart64_101"], :libcudart),
    LibraryProduct(["libcufft", "cufft64_10"], :libcufft),
    LibraryProduct(["libcufftw", "cufftw64_10"], :libcufftw),
    LibraryProduct(["libcurand", "curand64_10"], :libcurand),
    LibraryProduct(["libcublas", "cublas64_10"], :libcublas),
    LibraryProduct(["libcusolver", "cusolver64_10"], :libcusolver),
    LibraryProduct(["libcusparse", "cusparse64_10"], :libcusparse),
    FileProduct(["lib/libcudadevrt.a", "lib/cudadevrt.lib"], :libcudadevrt),
]

if wants_version(v"10.1")
    version = VersionNumber("$(cuda_version)-$(tag)")
    if wants_target("x86_64-linux-gnu")
        build_tarballs(ARGS, name, version, sources_linux, script, [Linux(:x86_64)], products, dependencies)
    end
    if wants_target(r"x86_64-apple-darwin")
        build_tarballs(ARGS, name, version, sources_macos, script, [MacOS(:x86_64)], products, dependencies)
    end
    if wants_target("x86_64-w64-mingw32")
        build_tarballs(ARGS, name, version, sources_windows, script, [Windows(:x86_64)], products, dependencies)
    end
end


#
# CUDA 10.0
#

cuda_version = v"10.0.130"

sources_linux = [
    "https://developer.nvidia.com/compute/cuda/10.0/Prod/local_installers/cuda_10.0.130_410.48_linux" =>
    "92351f0e4346694d0fcb4ea1539856c9eb82060c25654463bfd8574ec35ee39a"
]
sources_macos = [
    "https://developer.nvidia.com/compute/cuda/10.0/Prod/local_installers/cuda_10.0.130_mac" =>
    "4f76261ed46d0d08a597117b8cacba58824b8bb1e1d852745658ac873aae5c8e"
]
sources_windows = [
    "https://developer.nvidia.com/compute/cuda/10.0/Prod/local_installers/cuda_10.0.130_411.31_win10" =>
    "9dae54904570272c1fcdb10f5f19c71196b4fdf3ad722afa0862a238d7c75e6f"
]

script = raw"""
cd ${WORKSPACE}/srcdir

# use a temporary directory to avoid running out of tmpfs in srcdir on Travis
temp=${WORKSPACE}/tmpdir
mkdir ${temp}

apk add p7zip

if [[ ${target} == x86_64-linux-gnu ]]; then
    sh *-cuda_*_linux --tmpdir="${temp}" --extract="${temp}"
    cd ${temp}
    sh cuda-linux.*.run --noexec --keep
    cd pkg
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mv bin ${prefix}
    mv lib64 ${prefix}/lib

    # nested
    for project in nvvm extras/CUPTI; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]] && mv ${project}/bin/* ${prefix}/bin
        [[ -d ${project}/lib64 ]] && mv ${project}/lib64/* ${prefix}/lib
    done
    mv nvvm/libdevice ${prefix}/share

    # clean up
    rm    ${prefix}/bin/{nvcc,nvcc.profile,cicc,cudafe++}       # CUDA C/C++ compiler
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/{gpu-library-advisor,bin2c}             # C/C++ utilities
    rm    ${prefix}/bin/{nvprof,nvvp,nsight}                    # profiling
    rm    ${prefix}/bin/{cuda-memcheck,cuda-gdb,cuda-gdbserver} # debugging
    rm    ${prefix}/lib/*_static*.a                             # we can't link statically
    rm -r ${prefix}/lib/stubs/                                  # stubs are a C/C++ thing
    rm    ${prefix}/bin/nsight_ee_plugins_manage.sh
elif [[ ${target} == x86_64-w64-mingw32 ]]; then
    7z x *-cuda_*_win10 -o${temp}
    cd ${temp}
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mkdir -p ${prefix}/bin ${prefix}/lib

    # nested
    for project in cuobjdump memcheck nvcc nvcc/nvvm nvdisasm curand cusparse npp cufft \
                   cublas cudart cusolver nvrtc nvgraph nvprof nvprune; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]] && mv ${project}/bin/* ${prefix}/bin
        [[ -d ${project}/lib/x64 ]] && mv ${project}/lib/x64/* ${prefix}/lib
    done
    mv nvcc/nvvm/libdevice ${prefix}/share
    mv cupti/extras/CUPTI/libx64/* ${prefix}/bin/

    # fixup
    chmod +x ${prefix}/bin/*.exe

    # clean up
    rm    ${prefix}/bin/{nvcc,cicc,cudafe++}.exe   # CUDA C/C++ compiler
    rm    ${prefix}/bin/nvcc.profile
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/bin2c.exe                               # C/C++ utilities
    rm    ${prefix}/bin/nvprof.exe                              # profiling
    rm    ${prefix}/bin/cuda-memcheck.exe                       # debugging
    rm    ${prefix}/lib/*_static*.lib                           # we can't link statically
elif [[ ${target} == x86_64-apple-darwin* ]]; then
    7z x *-cuda_*_mac 5.hfs -o${temp}
    cd ${temp}
    7z x 5.hfs
    tar -zxf CUDAMacOSXInstaller/CUDAMacOSXInstaller.app/Contents/Resources/payload/cuda_mac_installer_tk.tar.gz
    cd Developer/NVIDIA/CUDA-*/
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mv bin ${prefix}
    mv lib ${prefix}

    # nested
    for project in nvvm extras/CUPTI; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]] && mv ${project}/bin/* ${prefix}/bin
        [[ -d ${project}/lib ]] && mv ${project}/lib/* ${prefix}/lib
    done
    mv nvvm/libdevice ${prefix}/share

    # clean up
    rm    ${prefix}/bin/{nvcc,nvcc.profile,cicc,cudafe++}       # CUDA C/C++ compiler
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/{gpu-library-advisor,bin2c}             # C/C++ utilities
    rm    ${prefix}/bin/{nvprof,nvvp,nsight}                    # profiling
    rm    ${prefix}/bin/cuda-memcheck                           # debugging
    rm    ${prefix}/lib/*_static*.a                             # we can't link statically
    rm -r ${prefix}/lib/stubs/                                  # stubs are a C/C++ thing
    rm    ${prefix}/bin/uninstall_cuda_*.pl
    rm    ${prefix}/bin/nsight_ee_plugins_manage.sh
    rm    ${prefix}/bin/.cuda_toolkit_uninstall_manifest_do_not_delete.txt
fi
"""

products = [
    ExecutableProduct("nvdisasm", :nvdisasm),
    ExecutableProduct("cuobjdump", :cuobjdump),
    ExecutableProduct("fatbinary", :fatbinary),
    ExecutableProduct("ptxas", :ptxas),
    ExecutableProduct("nvprune", :nvprune),
    ExecutableProduct("nvlink", :nvlink),
    FileProduct("share/libdevice/libdevice.10.bc", :libdevice),
    LibraryProduct(["libcudart", "cudart64_100"], :libcudart),
    LibraryProduct(["libcufft", "cufft64_100"], :libcufft),
    LibraryProduct(["libcufftw", "cufftw64_100"], :libcufftw),
    LibraryProduct(["libcurand", "curand64_100"], :libcurand),
    LibraryProduct(["libcublas", "cublas64_100"], :libcublas),
    LibraryProduct(["libcusolver", "cusolver64_100"], :libcusolver),
    LibraryProduct(["libcusparse", "cusparse64_100"], :libcusparse),
    FileProduct(["lib/libcudadevrt.a", "lib/cudadevrt.lib"], :libcudadevrt),
]

if wants_version(v"10.0")
    version = VersionNumber("$(cuda_version)-$(tag)")
    if wants_target("x86_64-linux-gnu")
        build_tarballs(ARGS, name, version, sources_linux, script, [Linux(:x86_64)], products, dependencies)
    end
    if wants_target(r"x86_64-apple-darwin")
        build_tarballs(ARGS, name, version, sources_macos, script, [MacOS(:x86_64)], products, dependencies)
    end
    if wants_target("x86_64-w64-mingw32")
        build_tarballs(ARGS, name, version, sources_windows, script, [Windows(:x86_64)], products, dependencies)
    end
end


#
# CUDA 9.2
#

cuda_version = v"9.2.148"

sources_linux = [
    "https://developer.nvidia.com/compute/cuda/9.2/Prod2/local_installers/cuda_9.2.148_396.37_linux" =>
    "f5454ec2cfdf6e02979ed2b1ebc18480d5dded2ef2279e9ce68a505056da8611"
]
sources_macos = [
    "https://developer.nvidia.com/compute/cuda/9.2/Prod2/local_installers/cuda_9.2.148_mac" =>
    "defb095aa002301f01b2f41312c9b1630328847800baa1772fe2bbb811d5fa9f"
]
sources_windows = [
    "https://developer.nvidia.com/compute/cuda/9.2/Prod2/local_installers2/cuda_9.2.148_win10" =>
    "7d99a6d135587d029c2cf159ade4e71c02fc1a922a5ffd06238b2bde8bedc362"
]

script = raw"""
cd ${WORKSPACE}/srcdir

# use a temporary directory to avoid running out of tmpfs in srcdir on Travis
temp=${WORKSPACE}/tmpdir
mkdir ${temp}

apk add p7zip

if [[ ${target} == x86_64-linux-gnu ]]; then
    sh *-cuda_*_linux --tmpdir="${temp}" --extract="${temp}"
    cd ${temp}
    sh cuda-linux.*.run --noexec --keep
    cd pkg
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mv bin ${prefix}
    mv lib64 ${prefix}/lib

    # nested
    for project in nvvm extras/CUPTI; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]] && mv ${project}/bin/* ${prefix}/bin
        [[ -d ${project}/lib64 ]] && mv ${project}/lib64/* ${prefix}/lib
    done
    mv nvvm/libdevice ${prefix}/share

    # clean up
    rm    ${prefix}/bin/{nvcc,nvcc.profile,cicc,cudafe++}       # CUDA C/C++ compiler
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/{gpu-library-advisor,bin2c}             # C/C++ utilities
    rm    ${prefix}/bin/{nvprof,nvvp,nsight}                    # profiling
    rm    ${prefix}/bin/{cuda-memcheck,cuda-gdb,cuda-gdbserver} # debugging
    rm    ${prefix}/lib/*_static*.a                             # we can't link statically
    rm -r ${prefix}/lib/stubs/                                  # stubs are a C/C++ thing
    rm    ${prefix}/bin/nsight_ee_plugins_manage.sh
elif [[ ${target} == x86_64-w64-mingw32 ]]; then
    7z x *-cuda_*_win10 -o${temp}
    cd ${temp}
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mkdir -p ${prefix}/bin ${prefix}/lib

    # nested
    for project in cuobjdump memcheck nvcc nvcc/nvvm nvdisasm curand cusparse npp cufft \
                   cublas cudart cusolver nvrtc nvgraph nvprof nvprune; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]] && mv ${project}/bin/* ${prefix}/bin
        [[ -d ${project}/lib/x64 ]] && mv ${project}/lib/x64/* ${prefix}/lib
    done
    mv nvcc/nvvm/libdevice ${prefix}/share
    mv cupti/extras/CUPTI/libx64/* ${prefix}/bin/

    # fixup
    chmod +x ${prefix}/bin/*.exe

    # clean up
    rm    ${prefix}/bin/{nvcc,cicc,cudafe++}.exe   # CUDA C/C++ compiler
    rm    ${prefix}/bin/nvcc.profile
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/bin2c.exe                               # C/C++ utilities
    rm    ${prefix}/bin/nvprof.exe                              # profiling
    rm    ${prefix}/bin/cuda-memcheck.exe                       # debugging
    rm    ${prefix}/lib/*_static*.lib                           # we can't link statically
elif [[ ${target} == x86_64-apple-darwin* ]]; then
    7z x *-cuda_*_mac -o${temp}
    cd ${temp}
    tar -xzf CUDAMacOSXInstaller/CUDAMacOSXInstaller.app/Contents/Resources/payload/cuda_mac_installer_tk.tar.gz
    cd Developer/NVIDIA/CUDA-*/
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mv bin ${prefix}
    mv lib ${prefix}

    # nested
    for project in nvvm extras/CUPTI; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]] && mv ${project}/bin/* ${prefix}/bin
        [[ -d ${project}/lib ]] && mv ${project}/lib/* ${prefix}/lib
    done
    mv nvvm/libdevice ${prefix}/share

    # clean up
    rm    ${prefix}/bin/{nvcc,nvcc.profile,cicc,cudafe++}       # CUDA C/C++ compiler
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/{gpu-library-advisor,bin2c}             # C/C++ utilities
    rm    ${prefix}/bin/{nvprof,nvvp,nsight}                    # profiling
    rm    ${prefix}/bin/cuda-memcheck                           # debugging
    rm    ${prefix}/lib/*_static*.a                             # we can't link statically
    rm -r ${prefix}/lib/stubs/                                  # stubs are a C/C++ thing
    rm    ${prefix}/bin/uninstall_cuda_*.pl
    rm    ${prefix}/bin/nsight_ee_plugins_manage.sh
    rm    ${prefix}/bin/.cuda_toolkit_uninstall_manifest_do_not_delete.txt
fi
"""

products = [
    ExecutableProduct("nvdisasm", :nvdisasm),
    ExecutableProduct("cuobjdump", :cuobjdump),
    ExecutableProduct("fatbinary", :fatbinary),
    ExecutableProduct("ptxas", :ptxas),
    ExecutableProduct("nvprune", :nvprune),
    ExecutableProduct("nvlink", :nvlink),
    FileProduct("share/libdevice/libdevice.10.bc", :libdevice),
    LibraryProduct(["libcudart", "cudart64_92"], :libcudart),
    LibraryProduct(["libcufft", "cufft64_92"], :libcufft),
    LibraryProduct(["libcufftw", "cufftw64_92"], :libcufftw),
    LibraryProduct(["libcurand", "curand64_92"], :libcurand),
    LibraryProduct(["libcublas", "cublas64_92"], :libcublas),
    LibraryProduct(["libcusolver", "cusolver64_92"], :libcusolver),
    LibraryProduct(["libcusparse", "cusparse64_92"], :libcusparse),
    FileProduct(["lib/libcudadevrt.a", "lib/cudadevrt.lib"], :libcudadevrt),
]

if wants_version(v"9.2")
    version = VersionNumber("$(cuda_version)-$(tag)")
    if wants_target("x86_64-linux-gnu")
        build_tarballs(ARGS, name, version, sources_linux, script, [Linux(:x86_64)], products, dependencies)
    end
    if wants_target(r"x86_64-apple-darwin")
        build_tarballs(ARGS, name, version, sources_macos, script, [MacOS(:x86_64)], products, dependencies)
    end
    if wants_target("x86_64-w64-mingw32")
        build_tarballs(ARGS, name, version, sources_windows, script, [Windows(:x86_64)], products, dependencies)
    end
end


#
# CUDA 9.0
#

cuda_version = v"9.0.176"

sources_linux = [
    "https://developer.nvidia.com/compute/cuda/9.0/Prod/local_installers/cuda_9.0.176_384.81_linux-run" =>
    "96863423feaa50b5c1c5e1b9ec537ef7ba77576a3986652351ae43e66bcd080c"
]
sources_macos = [
    "https://developer.nvidia.com/compute/cuda/9.0/Prod/local_installers/cuda_9.0.176_mac-dmg" =>
    "8fad950098337d2611d64617ca9f62c319d97c5e882b8368ed196e994bdaf225"
]
sources_windows = [
    "https://developer.nvidia.com/compute/cuda/9.0/Prod/local_installers/cuda_9.0.176_win10-exe" =>
    "615946c36c415d7d37b22dbade54469f0ed037b1b6470d6b8a108ab585e2621a"
]

script = raw"""
cd ${WORKSPACE}/srcdir

# use a temporary directory to avoid running out of tmpfs in srcdir on Travis
temp=${WORKSPACE}/tmpdir
mkdir ${temp}

apk add p7zip

if [[ ${target} == x86_64-linux-gnu ]]; then
    sh *-cuda_*_linux-run --tmpdir="${temp}" --extract="${temp}"
    cd ${temp}
    sh cuda-linux.*.run --noexec --keep
    cd pkg
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mv bin ${prefix}
    mv lib64 ${prefix}/lib

    # nested
    for project in nvvm extras/CUPTI; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]] && mv ${project}/bin/* ${prefix}/bin
        [[ -d ${project}/lib64 ]] && mv ${project}/lib64/* ${prefix}/lib
    done
    mv nvvm/libdevice ${prefix}/share

    # clean up
    rm    ${prefix}/bin/{nvcc,nvcc.profile,cicc,cudafe++}       # CUDA C/C++ compiler
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/{gpu-library-advisor,bin2c}             # C/C++ utilities
    rm    ${prefix}/bin/{nvprof,nvvp,nsight}                    # profiling
    rm    ${prefix}/bin/{cuda-memcheck,cuda-gdb,cuda-gdbserver} # debugging
    rm    ${prefix}/lib/*_static*.a                             # we can't link statically
    rm -r ${prefix}/lib/stubs/                                  # stubs are a C/C++ thing
    rm    ${prefix}/bin/nsight_ee_plugins_manage.sh
elif [[ ${target} == x86_64-w64-mingw32 ]]; then
    7z x *-cuda_*_win10-exe -o${temp}
    cd ${temp}
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mkdir -p ${prefix}/bin ${prefix}/lib

    # nested
    for project in compiler compiler/nvvm curand cusparse npp cufft cublas cudart \
                   cusolver nvrtc nvgraph command_line_tools; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]] && mv ${project}/bin/* ${prefix}/bin
        [[ -d ${project}/lib/x64 ]] && mv ${project}/lib/x64/* ${prefix}/lib
    done
    mv compiler/nvvm/libdevice ${prefix}/share
    mv command_line_tools/extras/CUPTI/libx64/* ${prefix}/bin/

    # fixup
    chmod +x ${prefix}/bin/*.exe

    # clean up
    rm    ${prefix}/bin/{nvcc,cicc,cudafe++}.exe   # CUDA C/C++ compiler
    rm    ${prefix}/bin/nvcc.profile
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/bin2c.exe                               # C/C++ utilities
    rm    ${prefix}/bin/nvprof.exe                              # profiling
    rm    ${prefix}/bin/cuda-memcheck.exe                       # debugging
    rm    ${prefix}/lib/*_static*.lib                           # we can't link statically
elif [[ ${target} == x86_64-apple-darwin* ]]; then
    7z x *-cuda_*_mac-dmg -o${temp}
    cd ${temp}
    tar -xzf CUDAMacOSXInstaller/CUDAMacOSXInstaller.app/Contents/Resources/payload/cuda_mac_installer_tk.tar.gz
    cd Developer/NVIDIA/CUDA-*/
    find .

    # license
    mkdir -p ${prefix}/share/licenses/CUDA
    mv EULA.txt ${prefix}/share/licenses/CUDA/

    # toplevel
    mv bin ${prefix}
    mv lib ${prefix}

    # nested
    for project in nvvm extras/CUPTI; do
        [[ -d ${project} ]] || { echo "${project} does not exist!"; exit 1; }
        [[ -d ${project}/bin ]] && mv ${project}/bin/* ${prefix}/bin
        [[ -d ${project}/lib ]] && mv ${project}/lib/* ${prefix}/lib
    done
    mv nvvm/libdevice ${prefix}/share

    # clean up
    rm    ${prefix}/bin/{nvcc,nvcc.profile,cicc,cudafe++}       # CUDA C/C++ compiler
    rm -r ${prefix}/bin/crt/
    rm    ${prefix}/bin/{gpu-library-advisor,bin2c}             # C/C++ utilities
    rm    ${prefix}/bin/{nvprof,nvvp,nsight}                    # profiling
    rm    ${prefix}/bin/cuda-memcheck                           # debugging
    rm    ${prefix}/lib/*_static*.a                             # we can't link statically
    rm -r ${prefix}/lib/stubs/                                  # stubs are a C/C++ thing
    rm    ${prefix}/bin/uninstall_cuda_*.pl
    rm    ${prefix}/bin/nsight_ee_plugins_manage.sh
    rm    ${prefix}/bin/.cuda_toolkit_uninstall_manifest_do_not_delete.txt
fi
"""

products = [
    ExecutableProduct("nvdisasm", :nvdisasm),
    ExecutableProduct("cuobjdump", :cuobjdump),
    ExecutableProduct("fatbinary", :fatbinary),
    ExecutableProduct("ptxas", :ptxas),
    ExecutableProduct("nvprune", :nvprune),
    ExecutableProduct("nvlink", :nvlink),
    FileProduct("share/libdevice/libdevice.10.bc", :libdevice),
    LibraryProduct(["libcudart", "cudart64_90"], :libcudart),
    LibraryProduct(["libcufft", "cufft64_90"], :libcufft),
    LibraryProduct(["libcufftw", "cufftw64_90"], :libcufftw),
    LibraryProduct(["libcurand", "curand64_90"], :libcurand),
    LibraryProduct(["libcublas", "cublas64_90"], :libcublas),
    LibraryProduct(["libcusolver", "cusolver64_90"], :libcusolver),
    LibraryProduct(["libcusparse", "cusparse64_90"], :libcusparse),
    FileProduct(["lib/libcudadevrt.a", "lib/cudadevrt.lib"], :libcudadevrt),
]

if wants_version(v"9.0")
    version = VersionNumber("$(cuda_version)-$(tag)")
    if wants_target("x86_64-linux-gnu")
        build_tarballs(ARGS, name, version, sources_linux, script, [Linux(:x86_64)], products, dependencies)
    end
    if wants_target(r"x86_64-apple-darwin")
        build_tarballs(ARGS, name, version, sources_macos, script, [MacOS(:x86_64)], products, dependencies)
    end
    if wants_target("x86_64-w64-mingw32")
        build_tarballs(ARGS, name, version, sources_windows, script, [Windows(:x86_64)], products, dependencies)
    end
end
