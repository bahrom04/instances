{outputs, ...}: {
  imports = [outputs.nixosModules.bind];

  # Enable Nameserver hosting
  services.nameserver = {
    enable = true;
    type = "slave";
    zones = [
      # Personal Space
      "orzklv.uz"
      "kolyma.uz"
      "gulag.uz"

      # Not that personal
      "khakimovs.uz"
      "dumba.uz"

      # Projects
      "shar.af"
      "slave.uz"
      "floss.uz"
      "sabine.uz"
      "rust-lang.uz"
      "osmon-lang.uz"
      "xinux.uz"
      "haskell.uz"
      "niggerlicious.uz"
      "misskey.uz"
    ];
    masters = ["167.235.96.40"];
  };
}
