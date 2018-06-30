#!/bin/sh

if [ "`id -u`" != "0" ]; then
  echo "sorry, this must be done as root." 1>&2
  exit 1
fi

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

target_archs="aarch64 amd64 armv7"
target_aarch64="arm64"
target_amd64="amd64"
target_armv7="arm"
kernconf_aarch64="MYHW"
kernconf_amd64="MYVIRTHW"
kernconf_armv7="MYHW MYHW-ROUTER"

usage()
{
  cat 1>&2 <<EOF
usage: src.sh command [options]

Commands:
  build
  package
  update-kernel
  cleanup-kernel
  update-world
  cleanup-world
  update-chroot

Options for build:
  -jN
  --clean
  --no_clean
  --native
  --non-native
EOF
}

build()
{
  local j_option clean_option native_option
  j_option="-j4"
  clean_option="-DNO_CLEAN"
  native_option=1
  
  for i in $@; do
    case $i in
      -j*)
        j_option=$i
        ;;
      --clean)
        clean_option=""
        ;;
      --no_clean)
        clean_option="-DNO_CLEAN"
        ;;
      --native)
        native_option=1
        ;;
      --non-native)
        native_option=0
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done
  
  # mergemaster -p || exit 1
  
  local machine_arch target_arch target kernconf
  machine_arch="$(uname -p)"
  for target_arch in ${target_archs}; do
    eval target=\${target_${target_arch}}
    if [ -z "${target}" ]; then
      echo "empty target for ${target_arch}" 1>&2
      exit 1
    fi
    eval kernconf=\${kernconf_${target_arch}}
    if [ -z "${kernconf}" ]; then
      echo "empty kernconf for ${target_arch}" 1>&2
      exit 1
    fi
    
    if [ ${native_option} -eq 1 -a "${machine_arch}" = "${target_arch}" -o ${native_option} -eq 0 -a "${machine_arch}" != "${target_arch}" ]; then
      export TARGET=${target} TARGET_ARCH=${target_arch}
      make ${j_option} ${clean_option} buildworld || exit 1
      make ${j_option} buildkernel KERNCONF="${kernconf}" || exit 1
      unset TARGET TARGET_ARCH
    fi
  done
}

copy_native_tools()
{
  dir=$1
  
  install -d -m 755 "${dir}/bin" || exit 1
  install -d -m 755 "${dir}/sbin" || exit 1
  install -d -m 755 "${dir}/usr" || exit 1
  install -d -m 755 "${dir}/usr/bin" || exit 1
  install -d -m 755 "${dir}/usr/sbin" || exit 1
  install -d -m 755 "${dir}/rescue" || exit 1
  
  install -c -m 755 "/usr/obj/usr/src/${NB_MACHINE}.${NB_MACHINE_ARCH}/rescue/rescue/rescue" "${dir}/rescue/rescue" || exit 1
  strip "${dir}/rescue/rescue" || exit 1
  
  for i in [ bunzip2 bzcat bzip2 cat chflags chgrp chmod chown cp csh date echo ed ex expr groups gunzip gzcat gzip head hostname id less link ln ls lzcat lzma md5 mkdir more mv realpath rm rmdir sed sh sleep tail tar tee test unlink unlzma unxz unzstd xz xzcat zcat zstd zstdcat; do
    install -l h "${dir}/rescue/rescue" "${dir}/rescue/$i" || exit 1
  done
  for i in [ cat chflags chmod cp csh date echo ed expr hostname link ln ls mkdir mv realpath rm rmdir sh sleep test unlink; do
    install -l h "${dir}/rescue/$i" "${dir}/bin/$i" || exit 1
  done
  for i in md5; do
    install -l h "${dir}/rescue/$i" "${dir}/sbin/$i" || exit 1
  done
  for i in bunzip2 bzcat bzip2 chgrp ex groups gunzip gzcat gzip head id less lzcat lzma more sed tail tar tee unlzma unxz unzstd xz xzcat zcat zstd zstdcat; do
    install -l h "${dir}/rescue/$i" "${dir}/usr/bin/$i" || exit 1
  done
  for i in chown; do
    install -l h "${dir}/rescue/$i" "${dir}/usr/sbin/$i" || exit 1
  done
  install -c -m 755 "/usr/obj/usr/src/${NB_MACHINE}.${NB_MACHINE_ARCH}/tmp/obj-tools/usr.bin/localedef/localedef" "${dir}/usr/bin/localedef" || exit 1
  install -c -m 755 "/usr/obj/usr/src/${NB_MACHINE}.${NB_MACHINE_ARCH}/tmp/obj-tools/usr.bin/xinstall/xinstall" "${dir}/usr/bin/install" || exit 1
  install -c -m 755 "/usr/obj/usr/src/${NB_MACHINE}.${NB_MACHINE_ARCH}/tmp/obj-tools/usr.bin/yacc/yacc" "${dir}/usr/bin/yacc" || exit 1
  install -c -m 755 "/usr/obj/usr/src/${NB_MACHINE}.${NB_MACHINE_ARCH}/tmp/obj-tools/usr.bin/mandoc/mandoc" "${dir}/usr/bin/mandoc" || exit 1
  install -c -m 755 "/usr/obj/usr/src/${NB_MACHINE}.${NB_MACHINE_ARCH}/usr.bin/clang/clang/clang" "${dir}/usr/bin/clang" || exit 1
  strip "${dir}/usr/bin/clang" || exit 1
  install -l h "${dir}/usr/bin/clang" "${dir}/usr/bin/clang++" || exit 1
  install -l h "${dir}/usr/bin/clang" "${dir}/usr/bin/clang-cpp" || exit 1
  install -c -m 755 "/usr/obj/usr/src/${NB_MACHINE}.${NB_MACHINE_ARCH}/usr.bin/bmake/make" "${dir}/usr/bin/make" || exit 1
  strip "${dir}/usr/bin/make" || exit 1
}

create_native_tools_cross_env()
{
  dir=$1
  
  install -d -m 755 "${dir}/etc" || exit 1
  install -d -m 755 "${dir}/usr" || exit 1
  install -d -m 755 "${dir}/usr/bin" || exit 1
  
  local machine_arch machine_vendor machine_sys machine_abi
  if [ "${TARGET_ARCH}" = "amd64" ]; then
    machine_arch="x86_64"
  else
    machine_arch="${TARGET_ARCH}"
  fi
  machine_vendor="unknown"
  machine_sys="freebsd12.0"
  if [ "${TARGET}" = "arm" ]; then
    if [ "${TARGET_ARCH}" = "armv7" -o "${TARGET_ARCH}" = "armv6" ]; then
      machine_abi="gnueabihf"
    else
      machine_abi="gnueabi"
    fi
  fi
  if [ -n "${machine_abi}" ]; then
    machine_triple="${machine_arch}-${machine_vendor}-${machine_sys}-${machine_abi}"
  else
    machine_triple="${machine_arch}-${machine_vendor}-${machine_sys}"
  fi
  printf "#!/bin/sh\nexec /usr/bin/clang --target=${machine_triple} \"\$@\"\n" > "${dir}/usr/bin/cc.crosscompile" || exit 1
  chmod 755 "${dir}/usr/bin/cc.crosscompile" || exit 1
  printf "#!/bin/sh\nexec /usr/bin/clang++ --target=${machine_triple} \"\$@\"\n" > "${dir}/usr/bin/c++.crosscompile" || exit 1
  chmod 755 "${dir}/usr/bin/c++.crosscompile" || exit 1
  printf "#!/bin/sh\nexec /usr/bin/clang-cpp --target=${machine_triple} \"\$@\"\n" > "${dir}/usr/bin/cpp.crosscompile" || exit 1
  chmod 755 "${dir}/usr/bin/cpp.crosscompile" || exit 1
  
  printf "# source file for build env variables\n" > "$dir"/etc/cross-build-env.sh || exit 1
  printf "export MACHINE=${TARGET}\n" >> "$dir"/etc/cross-build-env.sh || exit 1
  printf "export MACHINE_ARCH=${TARGET_ARCH}\n" >> "$dir"/etc/cross-build-env.sh || exit 1
  printf "# export CC=\"/usr/bin/clang --target=${machine_triple}\"\n" >> "$dir"/etc/cross-build-env.sh || exit 1
  printf "# export CXX=\"/usr/bin/clang++ --target=${machine_triple}\"\n" >> "$dir"/etc/cross-build-env.sh || exit 1
  printf "# export CPP=\"/usr/bin/clang-cpp --target=${machine_triple}\"\n" >> "$dir"/etc/cross-build-env.sh || exit 1
  printf "export CC=/usr/bin/cc.crosscompile\n" >> "$dir"/etc/cross-build-env.sh || exit 1
  printf "export CXX=/usr/bin/c++.crosscompile\n" >> "$dir"/etc/cross-build-env.sh || exit 1
  printf "export CPP=/usr/bin/cpp.crosscompile\n" >> "$dir"/etc/cross-build-env.sh || exit 1
  printf "export QEMU_EMULATING=1\n" >> "$dir"/etc/cross-build-env.sh || exit 1
}

copy_native_cross_tools()
{
  dir=$1
  
  install -d -m 755 "${dir}/usr" || exit 1
  install -d -m 755 "${dir}/usr/bin" || exit 1
  
  # [as, objdump] not built for aarch64
  for i in nm objcopy size strings strip; do
    install -c -m 755 "/usr/obj/usr/src/${TARGET}.${TARGET_ARCH}/tmp/usr/bin/$i" "${dir}/usr/bin/$i" || exit 1
  done
}

package()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  revision="$(awk -F= '/^REVISION/ { gsub("\"",""); print $2 }' sys/conf/newvers.sh)"
  branch="$(awk -F= '/^BRANCH/ { gsub("\"",""); print $2 }' sys/conf/newvers.sh)"
  svn_revision="$(svn info | awk '/^Revision:/ { print $2 }')"
  timestamp=$(date +%Y%m%d)
  workdir="/usr/wrkdir/src-dist"
  distsdir="/usr/obj/${revision}-${branch}-r${svn_revision}M-${timestamp}"
  
  if [ -e "${workdir}" ]; then
    chflags -R noschg "${workdir}" || exit 1
    rm -Rf "${workdir}" || exit 1
  fi
  
  if [ ! -e "${distsdir}" ]; then
    mkdir "${distsdir}" || exit 1
  fi
  
  for target_arch in ${target_archs}; do
    eval target=\${target_${target_arch}}
    if [ -z "${target}" ]; then
      echo "empty target for ${target_arch}" 1>&2
      exit 1
    fi
    eval kernconf=\${kernconf_${target_arch}}
    if [ -z "${kernconf}" ]; then
      echo "empty kernconf for ${target_arch}" 1>&2
      exit 1
    fi
    packagedir="${distsdir}/${target_arch}"
    
    if [ ! -e "${packagedir}" ]; then
      mkdir "${packagedir}" || exit 1
    fi
    
    export TARGET=${target} TARGET_ARCH=${target_arch}
    NB_MACHINE=${target} NB_MACHINE_ARCH=${target_arch}
    
    mkdir "${workdir}" || exit 1
    env DISTDIR="${workdir}" make distributeworld || exit 1
    ( cd tools/tools/guy && env DESTDIR="${workdir}/base" make -m $(realpath ../../../share/mk) delete-optional ) || exit 1
    ( cd tools/tools/guy && env DESTDIR="${workdir}/base" ./unused.sh delete ) || exit 1
    ( cd tools/tools/guy && env DESTDIR="${workdir}/base" ./fix_rc_scripts.sh ) || exit 1
    env DISTDIR="${workdir}" make packageworld || exit 1
    mv "${workdir}"/*.txz "${packagedir}/" || exit 1
    chflags -R noschg "${workdir}" || exit 1
    rm -Rf "${workdir}" || exit 1
    
    for i in ${kernconf}; do
      mkdir "${workdir}" || exit 1
      env DISTDIR="${workdir}" make distributekernel KERNCONF="${i}" || exit 1
      ( cd "${workdir}/kernel" && tar cvJf "${packagedir}/kernel-${i}.txz" . ) || exit 1
      rm -Rf "${workdir}" || exit 1
    done
    
    mkdir "${workdir}" || exit 1
    copy_native_tools "${workdir}"
    ( cd "${workdir}" && tar cvJf "${packagedir}/native-tools.txz" . ) || exit 1
    rm -Rf "${workdir}" || exit 1
    
    mkdir "${workdir}" || exit 1
    create_native_tools_cross_env "${workdir}"
    ( cd "${workdir}" && tar cvJf "${packagedir}/native-tools-cross-env.txz" . ) || exit 1
    rm -Rf "${workdir}" || exit 1
    
    if [ "$(uname -p)" != "${TARGET_ARCH}" ]; then
      mkdir "${workdir}" || exit 1
      copy_native_cross_tools "${workdir}"
      ( cd "${workdir}" && tar cvJf "${packagedir}/native-cross-tools-from-$(uname -p).txz" . ) || exit 1
      rm -Rf "${workdir}" || exit 1
    fi
    
    unset NB_MACHINE NB_MACHINE_ARCH
    unset TARGET TARGET_ARCH
  done
}

update_kernel()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  make installkernel || exit 1
}

cleanup_kernel()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  chflags -R noschg /boot/kernel.old /usr/lib/debug/boot/kernel.old || exit 1
  rm -Rf /boot/kernel.old /usr/lib/debug/boot/kernel.old || exit 1
}

update_world()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  make installworld || exit 1
  make delete-old || exit 1
  mergemaster -Fi || exit 1
  cd tools/tools/guy || exit 1
  make -m $(realpath ../../../share/mk) delete-optional || exit 1
  ./unused.sh delete || exit 1
  ./fix_rc_scripts.sh || exit 1
  cd ../../.. || exit 1
}

cleanup_world()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  make delete-old-libs || exit 1
}

update_chroot()
{
  if [ -n "$1" ]; then
    usage
    exit 1
  fi
  
  if [ -z "${DESTDIR}" ]; then
    echo "DESTDIR not set" 1>&2
    exit 1
  fi
  
  elf_machine=$(readelf -W -h "${DESTDIR}"/usr/lib/crt1.o | sed -n '/Machine:/s/ *Machine: *//p')
  case "${elf_machine}" in
    "Advanced Micro Devices x86-64")
      CHROOT_MACHINE=amd64
      CHROOT_MACHINE_ARCH=amd64
      ;;
    "ARM")
      CHROOT_MACHINE=arm
      CHROOT_MACHINE_ARCH=armv7
      ;;
    "AArch64")
      CHROOT_MACHINE=arm64
      CHROOT_MACHINE_ARCH=aarch64
      ;;
    *)
      printf "Cannot determine chroot machine and machine arch from /usr/lib/crt1.o\n" 1>&2
      exit 1
      ;;
  esac
  
  export TARGET=${CHROOT_MACHINE} TARGET_ARCH=${CHROOT_MACHINE_ARCH}
  NB_MACHINE=$(uname -m)
  NB_MACHINE_ARCH=$(uname -p)
  make installworld || exit 1
  make delete-old || exit 1
  mergemaster -Fi || exit 1
  cd tools/tools/guy || exit 1
  make -m $(realpath ../../../share/mk) delete-optional || exit 1
  ./unused.sh delete || exit 1
  ./fix_rc_scripts.sh || exit 1
  cd ../../.. || exit 1
  make delete-old-libs || exit 1
  if [ "$(uname -p)" != "${CHROOT_MACHINE_ARCH}" ]; then
    copy_native_tools "${DESTDIR}"
    create_native_tools_cross_env "${DESTDIR}"
    copy_native_cross_tools "${DESTDIR}"
  fi
  unset NB_MACHINE NB_MACHINE_ARCH
  unset TARGET TARGET_ARCH
}

cd ../../.. || exit 1

cmd=$1
shift

case $cmd in
  build)
    build $@
    ;;
  package)
    package $@
    ;;
  update-kernel)
    update_kernel $@
    ;;
  cleanup-kernel)
    cleanup_kernel $@
    ;;
  update-world)
    update_world $@
    ;;
  cleanup-world)
    cleanup_world $@
    ;;
  update-chroot)
    update_chroot $@
    ;;
  *)
    usage
    exit 1
    ;;
esac
