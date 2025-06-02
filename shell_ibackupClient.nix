# { pkgs ? import (builtins.fetchTarball { # https://nixos.wiki/wiki/FAQ/Pinning_Nixpkgs :
#   # Descriptive name to make the store path easier to identify
#   name = "nixos-unstable-2020-09-03";
#   # Commit hash for nixos-unstable as of the date above
#   url = "https://github.com/NixOS/nixpkgs/archive/702d1834218e483ab630a3414a47f3a537f94182.tar.gz";
#   # Hash obtained using `nix-prefetch-url --unpack <url>`
#   sha256 = "1vs08avqidij5mznb475k5qb74dkjvnsd745aix27qcw55rm0pwb";
# }) { }}:
# with pkgs;

{ pkgs ? import (builtins.fetchTarball { # https://nixos.wiki/wiki/FAQ/Pinning_Nixpkgs :
  # Descriptive name to make the store path easier to identify
  name = "nixos-unstable-2022-07-23";
  # Commit hash for nixos-unstable as of the date above
  url = "https://github.com/NixOS/nixpkgs/archive/8ad9860b50370b585a248c1b938cbd0d12afe1c2.tar.gz";
  # Hash obtained using `nix-prefetch-url --unpack <url>`
  sha256 = "1jr8wby66q7lyj98qalq49zmp61fzabv6jyd0r39ajn618gpfjlq";
}) { }}:
with pkgs;

let
  borgbackup_ = #borgbackup
  (callPackage ./borgbackup.nix {})# .overrideAttrs (oldAttrs: rec {
  #   patchPhase = (oldAttrs.patchPhase or "") + ''
  #     #ls -la
  #     #substituteInPlace src/borg/remote.py --replace 'self.p = Popen(borg_cmd, bufsize=0, stdin=PIPE, stdout=PIPE, stderr=PIPE, env=env, preexec_fn=ignore_sigint)' 'self.p = Popen(borg_cmd, bufsize=0, stdin=None, stdout=PIPE, stderr=PIPE, env=env, preexec_fn=ignore_sigint)' --replace 'self.p.stdin.fileno()' 'sys.stdin.fileno()'
  #     substituteInPlace src/borg/remote.py --replace 'self.p = Popen(borg_cmd, bufsize=0, stdin=PIPE, stdout=PIPE, stderr=PIPE, env=env, preexec_fn=ignore_sigint)' 'self.p = Popen(borg_cmd, bufsize=0, stdin=PIPE, stdout=PIPE, stderr=PIPE, env=env, preexec_fn=ignore_sigint)
  #             import io # https://stackoverflow.com/questions/56305530/why-cant-handle-io-unsupportedoperation-error-by-try-except
  #             ok______ = False
  #             try:
  #                 sys.stdin.fileno()
  #                 ok______ = True
  #             except io.UnsupportedOperation: # "io.UnsupportedOperation: fileno"
  #                 pass
  #             if ok______:
  #                 import getpass
  #                 self.p.stdin.write(getpass.getpass(prompt="Enter nested SSH password: ") + "\n") # Read user'''s password with my crazy system
  #     '
  #   '';
  # });
  ;
in
mkShell {
  buildInputs = [
    #netcat-gnu
    netcat
    #netcat-openbsd

    bindfs
    umount
    acl
    util-linux # for `mountpoint` command

    which

    python3
    #sudo
    bash

    borgbackup_
  ];
}
