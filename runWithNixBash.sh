nix-shell "$1" --run "$(printf '%q ' "${@:2}")" # https://github.com/NixOS/nix/issues/534
