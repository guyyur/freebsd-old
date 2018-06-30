#!/bin/sh

if [ "`id -u`" != "0" ]; then
  echo "sorry, this must be done as root." 1>&2
  exit 1
fi

target_archs="amd64"
target_amd64="amd64"
kernconf_amd64="MYHW MYVIRTHW MYVIRTHW-ROUTER"

usage()
{
  cat 1>&2 <<EOF
usage: src.sh command [options]

Commands:
  build
  package
  update-kernel
  update-kernel-cleanup
  update-world
  update-world-cleanup
  update-chroot

Options for build:
  -jN
  -clean
  -no_clean
EOF
}

build()
{
  j_option="-j4"
  clean_option="-DNO_CLEAN"
  
  for i in $@; do
    case $i in
      -j*)
        j_option=$i
        ;;
      -clean)
        clean_option=""
        ;;
      -no_clean)
        clean_option="-DNO_CLEAN"
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done
  
  # mergemaster -p || exit 1
  
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
    
    export TARGET=${target} TARGET_ARCH=${target_arch}
    make ${j_option} ${clean_option} buildworld || exit 1
    make ${j_option} buildkernel KERNCONF="${kernconf}" || exit 1
    unset TARGET TARGET_ARCH
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
  timestamp=$(date +%Y%m%d)
  workdir="/usr/wrkdir/src-dist"
  distsdir="/usr/obj/${revision}-${branch}-${timestamp}"
  
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

update_kernel_cleanup()
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

update_world_cleanup()
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
    *)
      printf "Cannot determine chroot machine and machine arch from /usr/lib/crt1.o\n" 1>&2
      exit 1
      ;;
  esac
  
  export TARGET=${CHROOT_MACHINE} TARGET_ARCH=${CHROOT_MACHINE_ARCH}
  make installworld || exit 1
  make delete-old || exit 1
  mergemaster -Fi || exit 1
  cd tools/tools/guy || exit 1
  make -m $(realpath ../../../share/mk) delete-optional || exit 1
  ./unused.sh delete || exit 1
  ./fix_rc_scripts.sh || exit 1
  cd ../../.. || exit 1
  make delete-old-libs || exit 1
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
  update-kernel-cleanup)
    update_kernel_cleanup $@
    ;;
  update-world)
    update_world $@
    ;;
  update-world-cleanup)
    update_world_cleanup $@
    ;;
  update-chroot)
    update_chroot $@
    ;;
  *)
    usage
    exit 1
    ;;
esac
