{ pkgs ? import <nixpkgs> { }}:
with pkgs;

buildGoModule {
  name = "go-fuseftp";
  src = ./go-fuseftp;
  vendorSha256 = "0b2snkj9qyg77rr7nkm2v5ljxwdcpbcbwqffbqpbbmya1d00nlv0";
}
  
