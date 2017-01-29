build-chroot
============

QEMU/chroot build environment for cross-platform building.

This bash script defines a function for creating a [Debian](https://www.debian.org/)
like chroot environment, using [QEMU](http://wiki.qemu.org/) for emulating
non-native hardware.

It's been tested on Ubuntu based systems, such as used in [Travis CI](travis-ci.org).

Usage
-----

```bash
source chroot.sh

chroot_try_enter \
  /path/to/this/script \
  target-architecture \
  host-os \
  source-directory-to-clone \
  debian-distro \
  any other arguments you want to pass to this script
ret=$?

case "${ret}" in
  1)
    exit "$ret"
    ;;
  2)
    chroot_clean
    exit "$ret"
    ;;
  3)
    chroot_clean
    exit 0
    ;;
esac

# your build instructions here
```

- The function tries to create a chroot environment with the specified
  Debian-like distribution, for the target architecture, via `debootstrap`.
- It then uses `rsync` to clone the specified source directory into the
  chroot environment.
- Lastly, it tries to run itself (this script) in the QEMU emulator
  matching the target architecture.

Return codes are:

- *0*: you are in the target architecture. That might be the host OS or
  the emulated OS.
- *1*: Cannot run an emulator on this host OS.
- *2*: Chroot/QEMU exited unsusccessfully.
- *3*: Chroot/QEMU exited successfully.

Requirements
------------

- [GNU Bash](https://www.gnu.org/software/bash/)
- a complete set of command line tools such as `sed`, `grep`, etc.
- `sudo` access
- [rsync](https://linux.die.net/man/1/rsync)
- A Debian-like host system. OSX host systems are explitcly recognised, but not
  supported.
- `debootstrap`

Disclaimer
----------

This script is largely written to build [meta](https://github.com/jfinkhaeuser/meta)
on Travis CI. It might not work well elsewhere.

License
-------

See [LICENSE](./LICENSE).

Authors
-------

See [Authors](./AUTHORS.md).
