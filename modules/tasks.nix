{
  config,
  pkgs,
  lib,
  ...
}:

# ── Task-based workspaces ──────────────────────────────────────────────────
#
# One task = one "slot" (Super+1..0) that spans every monitor.  hyprsplit gives
# each monitor its own block of workspaces; the `task` script (scripts/task.sh)
# switches all monitors to the same slot and launches a task's apps onto them.
# Task notes live in OneDrive; windows live only in the running session.
#
#   task new <name> [-d <repo>] [-w brave,code:1,claude]   create / resume
#   task switch   (Super+Tab)                              fuzzel picker
#   task close [slot|name]    task list    task fix    task wrap [name]

let
  numSlots = 10;
  vaultRel = "OneDrive/Dokumente/16_Notes";
  vault = "${config.home.homeDirectory}/${vaultRel}";
  root = "${vault}/tasks";

  # Agents launched by `task` may read the whole vault except Files/.
  denyJson = builtins.toJSON {
    permissions.deny = [ "Read(~/${vaultRel}/braindump/Files/**)" ];
  };

  # monitor = role index: 0/1 = external monitors left→right, last = laptop.
  # Roles wrap onto the monitors that exist, so one screen gets everything.
  tools = {
    brave = {
      monitor = 0;
      cmd = "brave --new-window";
    };
    code = {
      monitor = 1;
      cmd = "code --new-window @DIR@";
    };
    claude = {
      monitor = 2;
      cmd = "alacritty --working-directory @DIR@ -e claude @CLAUDE_ARGS@";
    };
    term = {
      monitor = 2;
      cmd = "alacritty --working-directory @DIR@";
    };
    notes = {
      monitor = 2;
      cmd = "subl --new-window @VAULT@ @NOTES@";
    };
    dolphin = {
      monitor = 1;
      cmd = "dolphin @DIR@";
    };
    insomnia = {
      monitor = 1;
      cmd = "insomnia";
    };
    remmina = {
      monitor = 1;
      cmd = "remmina";
    };
    brave-admin = {
      monitor = 0;
      cmd = "brave --new-window ${lib.escapeShellArgs adminTabs}";
    };
  };
  defaultTools = [
    "brave"
    "code"
    "claude"
    "notes"
  ];

  # Tabs that are always wanted in the "admin" task's Brave window.
  adminTabs = [ ];
  adminRepo = "${config.home.homeDirectory}/code/nixos-config";

  toolDefs = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (n: t: ''
      TOOL_CMD[${n}]=${lib.escapeShellArg t.cmd}
      TOOL_MON[${n}]=${toString t.monitor}
    '') tools
  );

  script =
    builtins.replaceStrings
      [
        "@N@"
        "@ROOT@"
        "@VAULT_PATH@"
        "@DENY_JSON@"
        "@DEFAULT_TOOLS@"
        "@TOOL_DEFS@"
      ]
      [
        (toString numSlots)
        (lib.escapeShellArg root)
        (lib.escapeShellArg vault)
        (lib.escapeShellArg denyJson)
        (lib.escapeShellArg (lib.concatStringsSep "," defaultTools))
        toolDefs
      ]
      (builtins.readFile ../scripts/task.sh);

  slotBinds = lib.concatMap (
    n:
    let
      slot = toString n;
      key = toString (lib.mod n 10);
    in
    [ "$mod, ${key}, exec, task goto ${slot}" ]
  ) (lib.range 1 numSlots);

  moveBinds = lib.concatMapStrings (
    n:
    let
      slot = toString n;
      key = toString (lib.mod n 10);
    in
    "bind = $mod SHIFT, ${key}, split:movetoworkspacesilent, ${slot}\n"
  ) (lib.range 1 numSlots);
in
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "task";
      runtimeInputs = with pkgs; [
        coreutils
        diffutils
        findutils
        fuzzel
        gawk
        gnugrep
        hyprland
        jq
        socat
        util-linux
      ];
      bashOptions = [
        "nounset"
        "pipefail"
      ];
      text = script;
    })
  ];

  wayland.windowManager.hyprland = {
    plugins = [ pkgs.hyprlandPlugins.hyprsplit ];

    settings = {
      plugin.hyprsplit = {
        num_workspaces = numSlots;
        # Persistent workspaces keep every slot bound to its monitor.
        persistent_workspaces = true;
        # Laptop always owns the first block, so undock/dock keeps its windows.
        monitor_priority = "eDP-1";
      };

      bind = slotBinds ++ [
        "$mod, Tab, exec, task switch"
      ];

      exec-once = [
        "task watch"
        # Login layout: slot 1 is the "admin" task.
        "task new admin -d ${adminRepo} -w code,term,brave-admin"
      ];
    };

    extraConfig = moveBinds;
  };

  programs.waybar.settings.mainBar."custom/tasks" = {
    exec = "task waybar";
    return-type = "json";
    format = "{}";
    tooltip = false;
    on-click = "task switch";
  };
}
