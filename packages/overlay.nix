final: prev: {
  x1e80100-linux = final.linuxPackages_x1e;
  linuxPackages_x1e = final.callPackage ./x1e-linux.nix { };
  slbounce = final.callPackage ./slbounce.nix { };
}
