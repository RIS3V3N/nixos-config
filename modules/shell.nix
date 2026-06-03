{ config, pkgs, ... }:

{
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
      tf = "terraform";
      lg = "lazygit";
      ls = "eza";
      ll = "eza -lah";
      cat = "bat";
    };

    initExtra = ''
      if [[ $- == *i* ]]; then
        fastfetch
      fi

      rebuild() {
        sudo nixos-rebuild switch --flake /home/dom/code/nixos-config#"$(hostname -s)" "$@"
      }

      # Clone a work GitHub repo using the github-work SSH alias.
      # Usage: wclone org/repo  (clones into ~/code/work/<repo>)
      wclone() {
        local slug="$1"
        local dest="$HOME/code/work/$(basename "$slug" .git)"
        git clone "git@github-work:''${slug}.git" "$dest"
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
    };
  };
}
