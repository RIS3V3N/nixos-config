{ pkgs, ... }:

# ── Screen recording (Super+Shift+Print) ───────────────────────────────────
#
# Super+Shift+Print  not recording: drag a region (Esc cancels) → records it
#                    recording:     stops every recording and saves it
#
# Files go to ~/Videos/Recordings/recording-<date>-<time>.mp4.  While a
# recording runs, Waybar shows a red "REC mm:ss"; clicking it stops too.
# Detection is by process, so this also stops recordings started elsewhere
# (e.g. the `gifrec` alias).

let
  screen-record = pkgs.writeShellApplication {
    name = "screen-record";
    runtimeInputs = with pkgs; [
      wf-recorder
      slurp
      libnotify
      procps # pgrep / pkill
      coreutils
    ];
    text = ''
      dir="$HOME/Videos/Recordings"
      run="''${XDG_RUNTIME_DIR:-/tmp}/screen-record"
      mkdir -p "$dir" "$run"

      notify() {
        notify-send -t "$1" -h string:x-dunst-stack-tag:screen-record "Screen recording" "$2" || true
      }

      case "''${1:-toggle}" in
        status)
          # Waybar: empty output hides the module.
          pgrep -x wf-recorder >/dev/null || exit 0
          start=$(stat -c %Y "$run/started" 2>/dev/null || date +%s)
          secs=$(($(date +%s) - start))
          printf '{"text":"󰑋 REC %02d:%02d","tooltip":"Recording — click or Super+Shift+Print to stop","class":"recording"}\n' \
            $((secs / 60)) $((secs % 60))
          ;;
        toggle)
          if pgrep -x wf-recorder >/dev/null; then
            # SIGINT so wf-recorder finalizes the file.
            pkill -INT -x wf-recorder
            for _ in $(seq 50); do pgrep -x wf-recorder >/dev/null || break; sleep 0.1; done
            notify 6000 "Saved: $(cat "$run/file" 2>/dev/null || echo "$dir")"
            rm -f "$run/started" "$run/file"
          else
            geometry=$(slurp) || exit 0 # Esc: cancelled
            file="$dir/recording-$(date +%F-%H%M%S).mp4"
            echo "$file" >"$run/file"
            touch "$run/started"
            wf-recorder -g "$geometry" -f "$file" >/dev/null 2>&1 &
            notify 4000 "🔴 Recording… press Super+Shift+Print again to stop"
          fi
          ;;
      esac
    '';
  };
in
{
  home.packages = [ screen-record ];

  wayland.windowManager.hyprland.settings.bind = [
    "$mod SHIFT, Print, exec, screen-record"
  ];

  programs.waybar.settings.mainBar."custom/recording" = {
    exec = "screen-record status";
    return-type = "json";
    interval = 1;
    on-click = "screen-record";
  };

  programs.waybar.style = ''
    #custom-recording {
      background: rgba(243, 139, 168, 0.88);
      color: #1e1e2e;
      padding: 6px 12px;
      margin: 0 4px;
      border-radius: 12px;
      font-weight: bold;
    }
  '';
}
