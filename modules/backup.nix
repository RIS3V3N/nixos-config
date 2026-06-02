{ config, pkgs, ... }:

# Restic backups via rclone → OneDrive.
#
# One-time setup (run as dom, after first rebuild):
#
#   1. Configure rclone OneDrive remote (must be named "onedrive"):
#        rclone config
#
#   2. Create the encryption password file (keep this safe, loss = data loss):
#        mkdir -p ~/.config/restic
#        pwgen -s 64 1 > ~/.config/restic/password
#        chmod 600 ~/.config/restic/password
#
#   3. Initialise the repository:
#        restic -r rclone:onedrive:Backups/nixhorse init \
#          --password-file ~/.config/restic/password
#
# After that the systemd timer runs daily automatically.

{
  services.restic.backups.home = {
    user = "dom";

    repository = "rclone:onedrive:Backups/nixhorse";
    passwordFile = "/home/dom/.config/restic/password";

    paths = [
      "/home/dom"
    ];

    exclude = [
      # Caches and ephemeral data
      "/home/dom/.cache"
      "/home/dom/.local/share/Trash"
      "/home/dom/.local/share/containers"
      "/home/dom/Downloads"
      # Build artifacts
      "node_modules"
      "target"
      "__pycache__"
      ".venv"
      # Large media that is already in OneDrive via the sync daemon
      "/home/dom/Dokumente/15_Work/SV/Notes"
      "/home/dom/Dokumente/16_Notes"
    ];

    # Retention: keep daily snapshots for 1 week, weekly for 1 month, monthly for 6 months
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];

    timerConfig = {
      OnCalendar = "daily";
      Persistent = true; # run missed backup if machine was off
    };
  };

  environment.systemPackages = [ pkgs.restic pkgs.rclone ];
}
