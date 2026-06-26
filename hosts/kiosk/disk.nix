{ config, ... }:

# Declarative partitioning via disko: GPT, 512M ESP + ext4 root.
# The target device comes from mfd.kiosk.diskDevice; the installer can override
# it per board.
{
  disko.devices.disk.main = {
    type = "disk";
    device = config.mfd.kiosk.diskDevice;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
