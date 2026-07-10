{ config, pkgs, ... }:

{
  # ~/.local/bin is for user-installed binaries that live outside the Nix store
  # (e.g. GitHub Copilot CLI installed via its install script).
  # ~/.npm-global/bin is for npm -g installs (Nix store is read-only, so the
  # default global prefix /nix/store/…/lib/node_modules is not writable).
  home.sessionPath = [ "$HOME/.local/bin" "$HOME/.npm-global/bin" ];

  # Redirect npm global installs away from the read-only Nix store.
  home.sessionVariables = {
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
  };

  home.packages = with pkgs; [
    fastfetch
    tmux
  ];

  programs.bash = {
    enable = true;

    shellAliases = {
      gs = "git status";
      gl = "git log --oneline --graph --decorate";
      gp = "git push";
      k = "kubectl";
      d = "docker";
      p = "podman";
      tf = "terraform";
      lg = "lazygit";
      ls = "eza";
      ll = "eza -lah";
      cat = "bat";
    };

    initExtra = ''
      # Ensure npm global binaries are available in all interactive shells,
      # not just login shells (where home.sessionPath would apply).
      export PATH="$HOME/.npm-global/bin:$PATH"

      if [[ $- == *i* ]]; then
        fastfetch
      fi

      rebuild() {
        sudo nixos-rebuild switch --flake /home/dom/code/nixos-config#"$(hostname -s)" "$@"
      }

      # Clone a work GitHub repo using the github-work SSH alias.
      # Usage: wclone org/repo  (clones into ~/code/work/github/<repo>)
      wclone() {
        local slug="$1"
        local dest="$HOME/code/work/github/$(basename "$slug" .git)"
        git clone "git@github-work:''${slug}.git" "$dest"
      }

      # Run any npm command with the work GitHub SSH key.
      # Useful for installing private packages from work GitHub repos.
      # -F /dev/null  → skip ~/.ssh/config so id_personal is not picked up for github.com
      # -l git        → set the SSH user (normally comes from SSH config)
      # -o IdentitiesOnly=yes → ignore agent keys; only use the -i key
      # npm_config_prefix   → redirect global installs away from the read-only Nix store
      # Usage: wnpm install -g github:org/repo
      wnpm() {
        GIT_SSH_COMMAND="ssh -F /dev/null -l git -i $HOME/.ssh/id_work_github -o IdentitiesOnly=yes" \
        npm_config_prefix="$HOME/.npm-global" \
        npm "$@"
      }
    '';
  };

  programs.starship = {
    enable = true;

    settings = {
      add_newline = false;

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };

      python = {
        format = "via [🐍 $version ( venv: $virtualenv)]($style) ";
      };

      cmake = {
        disabled = true;
      };

      directory.truncation_length = 3;

      git_branch.symbol = " ";
    };
  };

  programs.fzf.enable = true;
  programs.zoxide.enable = true;
  programs.fastfetch.enable = true;

  programs.alacritty = {
    enable = true;

    settings = {
      window = {
        opacity = 0.90;
        dynamic_padding = true;
      };

      font = {
        size = 11.5;

        normal = {
          family = "JetBrainsMono Nerd Font";
          style = "Regular";
        };

        bold = {
          family = "JetBrainsMono Nerd Font";
          style = "Bold";
        };

        italic = {
          family = "JetBrainsMono Nerd Font";
          style = "Italic";
        };
      };

      scrolling.history = 50000;

      selection.save_to_clipboard = true;

      cursor = {
        style = {
          shape = "Beam";
          blinking = "Off";
        };
      };

      mouse.hide_when_typing = true;

      env = {
        TERM = "xterm-256color";
      };

      keyboard.bindings = [
        { key = "F11"; action = "ToggleFullscreen"; }
      ];
    };
  };
}
