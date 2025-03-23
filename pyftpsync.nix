# Based on https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/development/python-modules/mako/default.nix#L60 commit https://github.com/NixOS/nixpkgs/commit/0215034f25d23eb6da0f8006a941ccbfd4d9c355

{ lib
, buildPythonPackage
, pythonOlder
, fetchPypi
, isPyPy

# Python packages
, pysftp
, colorama
, keyring
, pyyaml

# tests
, pytestCheckHook
}:

buildPythonPackage rec {
  pname = "pyftpsync";
  version = "4.1.0";

  disabled = pythonOlder "3.8";

  src = fetchPypi {
    inherit pname;
    inherit version;
    hash = "sha256-9sc54fGv1HnRQfVekEtwnwSvdHBVlDVa8ZrXj5OFR0M=";
  };

  propagatedBuildInputs = [
    pysftp
    colorama
    keyring
    pyyaml
  ];

  passthru.optional-dependencies = {
    # babel = [
    #   babel
    # ];
  };

  nativeCheckInputs = [
    # chameleon
    # lingua
    # mock
    pytestCheckHook
  ]
  #++ passthru.optional-dependencies.babel
  ;

  doCheck = false;

  # disabledTests = lib.optionals isPyPy [
  #   # https://github.com/sqlalchemy/mako/issues/315
  #   "test_alternating_file_names"
  #   # https://github.com/sqlalchemy/mako/issues/238
  #   "test_file_success"
  #   "test_stdin_success"
  #   # fails on pypy2.7
  #   "test_bytestring_passthru"
  # ];

  meta = with lib; {
    description = "Synchronize directories using FTP(S), SFTP, or file system access.";
    homepage = "https://github.com/mar10/pyftpsync"; # or https://pyftpsync.readthedocs.io/en/latest/
    changelog = "https://github.com/mar10/pyftpsync/blob/master/CHANGELOG.md"; # or https://pyftpsync.readthedocs.io/en/latest/changes.html
    license = licenses.mit;
    platforms = platforms.unix;
    maintainers = with maintainers; [  ];
  };
}
