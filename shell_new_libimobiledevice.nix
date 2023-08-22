{ pkgs ? (if (import <nixpkgs>).system == "armv7l-linux" then (
builtins.fetchTarball { # https://nixos.wiki/wiki/FAQ/Pinning_Nixpkgs :
  # Descriptive name to make the store path easier to identify
  name = "nixos-unstable-2023-07-31";
  # Commit hash for nixos-unstable as of the date above
  url = "https://github.com/NixOS/nixpkgs/archive/ed92e2eb043d75e0417199d9650d5849527dd404.tar.gz";
  # Hash obtained using `nix-prefetch-url --unpack <url>`
  sha256 = "1iqc7rvrwbjg3wps9zzngvb9r47akzx8c39644xbhi1sxqf5rwrk";
}
) else (
builtins.fetchTarball { # https://nixos.wiki/wiki/FAQ/Pinning_Nixpkgs :
  # Descriptive name to make the store path easier to identify
  name = "nixos-unstable-2020-09-03";
  # Commit hash for nixos-unstable as of the date above
  url = "https://github.com/NixOS/nixpkgs/archive/702d1834218e483ab630a3414a47f3a537f94182.tar.gz";
  # Hash obtained using `nix-prefetch-url --unpack <url>`
  sha256 = "1vs08avqidij5mznb475k5qb74dkjvnsd745aix27qcw55rm0pwb";
}))}:
with pkgs;

let
  libimobiledevice = (callPackage ./libimobiledevice/libimobiledevice_new.nix {
    enablePython=false;
    #enablePython=true; # doesn't work
  });
in
mkShell {
  buildInputs = [
    # (callPackage ./libimobiledevice/libimobiledevice_new.nix {
    #   enablePython=false;
    #   #enablePython=true; # doesn't work
    # })
    libimobiledevice
    #usbmuxd
    (callPackage ./usbmuxd/usbmuxd.nix {libimobiledevice=libimobiledevice;})
    pkg-config

    python3
    util-linux
    lsof
    (callPackage ./btrbk.nix {})
    procps
    which
  ];
}
