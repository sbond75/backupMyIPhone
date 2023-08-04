{ pkgs ? import (builtins.fetchTarball { # https://nixos.wiki/wiki/FAQ/Pinning_Nixpkgs :
  # Descriptive name to make the store path easier to identify
  name = "nixos-unstable-2020-09-03";
  # Commit hash for nixos-unstable as of the date above
  url = "https://github.com/NixOS/nixpkgs/archive/702d1834218e483ab630a3414a47f3a537f94182.tar.gz";
  # Hash obtained using `nix-prefetch-url --unpack <url>`
  sha256 = "1vs08avqidij5mznb475k5qb74dkjvnsd745aix27qcw55rm0pwb";
}) {
  # Apply overlay (for raspberry pi to work)
  overlays = (self: super: {
    libxcrypt = if super.system == "armv7l-linux" then (super.libxcrypt.overrideAttrs {
      doCheck = false;
    }) else super.libxcrypt;
  });
}}:
with pkgs;

mkShell {
  buildInputs = [
    (callPackage ./libimobiledevice/libimobiledevice_new.nix {
      enablePython=false;
      #enablePython=true; # doesn't work
    })
    usbmuxd
    pkg-config

    python3
    util-linux
    lsof
    (callPackage ./btrbk.nix {})
    procps
    which
  ];
}
