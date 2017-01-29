#
# This file is part of build-chroot.
#
# Author(s): Jens Finkhaeuser <jens@finkhaeuser.de>
#
# Copyright (c) 2017 Jens Finkhaeuser
#
# This software is licensed under the terms of the GNU GPLv3 for personal,
# educational and non-profit use. For all other uses, alternative license
# options are available. Please contact the copyright holder for additional
# information, stating your intended usage.
#
# You can find the full text of the GPLv3 in the COPYING file in this code
# distribution.
#
# This software is distributed on an "AS IS" BASIS, WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE.

# Based on instructions from https://www.tomaz.me/2013/12/02/running-travis-ci-tests-on-arm.html

##############################################################################
# Utility Functions

function chroot_apt_sources {
  local outfile="${1}"

  case "${CHROOT_DEB_VERSION}" in
    jessie|wheezy|squeeze|lenny)
      echo "deb ${CHROOT_DEB_MIRROR} ${CHROOT_DEB_VERSION} main contrib" >"$outfile"
      echo "deb ${CHROOT_DEB_MIRROR} ${CHROOT_DEB_VERSION}-updates main contrib" >>"$outfile"
      ;;
    yakkety|xenial|trusty|precie)
      echo "deb ${CHROOT_DEB_MIRROR} ${CHROOT_DEB_VERSION} main restricted" >"$outfile"
      echo "deb ${CHROOT_DEB_MIRROR} ${CHROOT_DEB_VERSION}-updates main restricted" >>"$outfile"
      echo "deb ${CHROOT_DEB_MIRROR} ${CHROOT_DEB_VERSION}-security main restricted" >>"$outfile"
      echo "deb ${CHROOT_DEB_MIRROR} ${CHROOT_DEB_VERSION}-backports main restricted" >>"$outfile"
      ;;
    *)
      return 1
      ;;
  esac
}

function chroot_deb_source {
  # This mapping is surely incomplete, but tries to cover reasonably recent,
  # reasonably well known sources (i.e. Debian, Ubuntu)
  case "${CHROOT_DEB_VERSION}" in
    jessie|wheezy|squeeze|lenny)
      echo "ftp://ftp.debian.org/debian/"
      ;;
    yakkety|xenial|trusty|precie)
      echo "http://archive.canonical.com/ubuntu/"
      ;;
    *)
      # Default to debian
      echo "ftp://ftp.debian.org/debian/"
      ;;
  esac
}

function chroot_emulator {
  # This mapping isn't based on any solid information at this time, just by
  # trying things out.
  case "${CHROOT_ARCH}" in
    arm*)
      echo "arm"
      ;;
    *)
      # Might not work, but it's the best possible fallback here.
      echo "${CHROOT_ARCH}"
      ;;
  esac
}

function chroot_save_env {
  local tmpfile="$(mktemp)"
  printenv >"$tmpfile"
  sed -i.bak "s/^\([A-Za-z0-9_]*\)=\(.*\)/\1='\2'/" "$tmpfile"
  sed -i.bak 's/^\(.*\)$/export \1 || true/g' "$tmpfile"
  sudo mv "$tmpfile" "${CHROOT_DIR}/environment"
  cat "${CHROOT_DIR}/environment"
}

function chroot_prepare_host {
  # Install host dependencies
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get install -y ${CHROOT_HOST_DEPENDENCIES}
}

function chroot_create_chroot {
  chroot_clean
  sudo mkdir "${CHROOT_DIR}"

  # Debootstrap first stage
  sudo debootstrap --arch="${CHROOT_ARCH}" --variant=buildd --verbose --foreign \
      --include="${CHROOT_GUEST_DEPENDENCIES}" --components=main,restricted \
      --no-check-gpg --resolve-deps \
      "${CHROOT_DEB_VERSION}" "${CHROOT_DIR}" "${CHROOT_DEB_MIRROR}"

  # Copy emulator binary
  sudo cp "${CHROOT_EMULATOR}" "${CHROOT_DIR}/usr/bin/"

  # Bind proc and dev
  local fs
  for fs in dev proc ; do
    sudo rm -rf "${CHROOT_DIR}/${fs}/*"
    sudo mkdir -p "${CHROOT_DIR}/${fs}"
    sudo mount --bind "/${fs}" "${CHROOT_DIR}/${fs}"
  done

  # Debootstrap second stage in emulator
  sudo chroot "${CHROOT_DIR}" ./debootstrap/debootstrap --second-stage

  # Update the chroot's Apt repository
  local sources="$(mktemp)"
  chroot_apt_sources "${sources}"
  sudo mv "${sources}" "${CHROOT_DIR}/etc/apt/sources.list"

  sudo chroot "${CHROOT_DIR}" "${CHROOT_EMULATOR}" /usr/bin/apt-get update
}

function chroot_sync_sources {
  # Create dir and copy files to our chroot environment
  sudo mkdir -p "${CHROOT_DIR}/${CHROOT_SOURCE_DIR}"
  sudo rsync -av "${CHROOT_SOURCE_DIR}/" "${CHROOT_DIR}/${CHROOT_SOURCE_DIR}/"
}

function chroot_mark_done {
  sudo touch "${CHROOT_DIR}/${CHROOT_FLAG_FILE}"
}

function chroot_setup {
  # Setup tasks
  chroot_prepare_host
  chroot_create_chroot
  chroot_save_env
  chroot_sync_sources
  chroot_mark_done
}



##############################################################################
# API Functions

function chroot_clean {
  local fs
  for fs in dev proc ; do
    sudo umount -f "${CHROOT_DIR}/${fs}" || true
  done

  sudo rm -rf "${CHROOT_DIR}"
  return 0
}

##
# usage:
#   chroot_try_enter /path/to/caller/script target-architecture [host-os] [source-dir]
#
# Exit status:
#   0 - We're inside target architecture - might be a chroot, or the host OS
#   1 - Can't emulate on this host, aborting.
#   2 - Chroot exited unsuccessfully
#   3 - Chroot exited successfully
function chroot_try_enter {
  ##############################################################################
  # Parameter checking
  local the_script="${1}"
  shift
  CHROOT_ARCH="${1}"
  shift

  local p
  for p in the_script CHROOT_ARCH ; do
    test -z "${!p}" && exit 1
  done

  CHROOT_HOST_OS="${1}"
  test -z "${CHROOT_HOST_OS}" && CHROOT_HOST_OS="$(uname)"
  shift

  CHROOT_SOURCE_DIR="${1}"
  test -z "${CHROOT_SOURCE_DIR}" && CHROOT_SOURCE_DIR="$(pwd)"
  test -d "${CHROOT_SOURCE_DIR}" || exit 1
  shift

  CHROOT_DEB_VERSION="${1}"
  test -z "${CHROOT_DEB_VERSION}" && CHROOT_DEB_VERSION="jessie"
  shift

  ##############################################################################
  # Constants and defaults
  CHROOT_DEB_MIRROR="$(chroot_deb_source)"

  test -z "${CHROOT_DIR}" && CHROOT_DIR="/tmp/chroot-${CHROOT_ARCH}"
  CHROOT_NAME="${CHROOT_DEB_VERSION}-${CHROOT_ARCH}-sbuild"

  # Debian package dependencies for the host
  CHROOT_HOST_DEPENDENCIES="debootstrap qemu-user-static binfmt-support"

  # Debian package dependencies for the chrooted environment
  CHROOT_GUEST_DEPENDENCIES="fakeroot,build-essential,git,sudo"

  # Flag file for noticing we're in chroot
  CHROOT_FLAG_FILE="/.chroot-${CHROOT_DEB_VERSION}-${CHROOT_ARCH}"

  # Emulator binary
  CHROOT_EMULATOR="/usr/bin/qemu-$(chroot_emulator ${CHROOT_ARCH})-static"

  ##############################################################################
  # Main part

  # It's possible that the host architecture is already the same as the
  # requested, in which case we don't need to do anything.
  if [ "$(uname -m)" = "${CHROOT_ARCH}" ] ; then
    echo "Host and requested architecture are both ${CHROOT_ARCH}, nothing to do."
    return 0
  fi

  # Otherwise, check if the host is supported for chroot emulation
  case "${CHROOT_HOST_OS}" in
    osx|Darwin)
      echo "Can't emulate on host OS '${CHROOT_HOST_OS}', aborting."
      return 1
      ;;
    *)
      ;;
  esac
  
  # If we're already inside the chroot, we don't need to do anything more except
  # restore the environment.
  if [ -e "${CHROOT_FLAG_FILE}" ] ; then
    echo "Running inside chrooted environment"

    . /environment
    echo "environment is set"

    return 0
  fi

  # Great, now we re-run the same script we're already in, but inside the
  # chroot.
  echo "Setting up chroot on '${CHROOT_HOST_OS}' for '${CHROOT_ARCH}'..."
  chroot_setup

  echo "Switching to chroot."
  . "${CHROOT_DIR}/environment"
  sudo chroot "${CHROOT_DIR}" "${CHROOT_EMULATOR}" \
      /bin/bash -e -c "cd '${CHROOT_SOURCE_DIR}' && '${the_script}' $@"

  ret="$?"
  if [ "${ret}" = 0 ] ; then
    # Build was successful.
    return 3
  else
    # Build was unsuccessful
    return 2
  fi
}
