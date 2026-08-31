{ config, pkgs, ... }:

{
  # ~/.local/bin is for user-installed binaries that live outside the Nix store
  # (e.g. GitHub Copilot CLI installed via its install script).
  # ~/.npm-global/bin is for npm -g installs (Nix store is read-only, so the
  # default global prefix /nix/store/…/lib/node_modules is not writable).
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.npm-global/bin"
  ];

  # Redirect npm global installs away from the read-only Nix store.
  home.sessionVariables = {
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
  };

  # Maps the @qsys-sd scope to GitHub Packages. npm expands ${GITHUB_TOKEN}
  # from the environment at read-time — the token itself is never written
  # here, so this file is safe to commit. The actual token is sourced from
  # an untracked secrets file below (same pattern as git's local includes).
  home.file.".npmrc".text = ''
    @qsys-sd:registry=https://npm.pkg.github.com
    //npm.pkg.github.com/:_authToken=''${GITHUB_TOKEN}
  '';

  home.packages = with pkgs; [
    fastfetch
    tmux
    erdtree # modern `tree` replacement (`erd`) — colors, icons, git-aware, sizes
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
      tree = "eza --tree --icons";
      dcp = "docker stop $(docker ps -aq) && docker rm $(docker ps -aq)";
    };

    initExtra = ''
            # Ensure ~/.local/bin and npm global binaries are available in all
            # interactive shells, not just login shells (where home.sessionPath
            # would apply). This must be prepended (not just appended) because
            # some tools — notably VS Code's Copilot Chat extension — inject their
            # own bundled CLI directory into PATH *before* bash even starts, which
            # would otherwise shadow the real ~/.local/bin/copilot with a broken
            # bundled stub that can't install itself (read-only Nix store).
            export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

            # GITHUB_TOKEN is read by ~/.npmrc (see home.file.".npmrc" in shell.nix)
            # to authenticate the @qsys-sd GitHub Packages scope. Kept in an
            # untracked file so the PAT never ends up in this repo. Create it with:
            #   mkdir -p ~/.config/secrets
            #   echo 'export GITHUB_TOKEN=ghp_...' > ~/.config/secrets/github-token
            #   chmod 600 ~/.config/secrets/github-token
            # Scoped to read:packages only — does not affect the public npm registry
            # or any other npm command, since it's just an unused env var otherwise.
            [ -f "$HOME/.config/secrets/github-token" ] && source "$HOME/.config/secrets/github-token"

            if [[ $- == *i* ]]; then
              fastfetch
            fi

            rebuild() {
              sudo nixos-rebuild switch --flake /home/dom/code/nixos-config#"$(hostname -s)" "$@"
            }

            ex() {
              local operation="$1"
              local source="$2"
              local destination="$3"
              local -a archive_paths=( "''${@:4}" )

              case "$operation" in
                compress)
                  if [[ -z "$source" || -z "$destination" ]]; then
                    echo "Usage: ex compress <file-or-folder> <destination-archive>" >&2
                    return 2
                  fi

                  case "$destination" in
                    *.tar) tar -cf "$destination" "$source" ;;
                    *.tar.gz|*.tgz) tar -czf "$destination" "$source" ;;
                    *.tar.bz2|*.tbz2) tar -cjf "$destination" "$source" ;;
                    *.tar.xz|*.txz) tar -cJf "$destination" "$source" ;;
                    *.tar.zst|*.tzst) tar --zstd -cf "$destination" "$source" ;;
                    *) 7z a "$destination" "$source" ;;
                  esac
                  ;;
                extract)
                  if [[ -z "$source" || -z "$destination" ]]; then
                    echo "Usage: ex extract <archive> <destination-folder> [archive-path...]" >&2
                    return 2
                  fi

                  if [[ ! -f "$source" ]]; then
                    echo "Archive not found: $source" >&2
                    return 1
                  fi

                  mkdir -p "$destination"
                  case "$source" in
                    *.tar) tar -xf "$source" -C "$destination" "''${archive_paths[@]}" ;;
                    *.tar.gz|*.tgz) tar -xzf "$source" -C "$destination" "''${archive_paths[@]}" ;;
                    *.tar.bz2|*.tbz2) tar -xjf "$source" -C "$destination" "''${archive_paths[@]}" ;;
                    *.tar.xz|*.txz) tar -xJf "$source" -C "$destination" "''${archive_paths[@]}" ;;
                    *.tar.zst|*.tzst) tar --zstd -xf "$source" -C "$destination" "''${archive_paths[@]}" ;;
                    *) 7z x "-o$destination" "$source" "''${archive_paths[@]}" ;;
                  esac
                  ;;
                add)
                  if [[ -z "$source" || -z "$destination" ]]; then
                    echo "Usage: ex add <archive> <file-or-folder>" >&2
                    return 2
                  fi

                  if [[ ! -f "$source" ]]; then
                    echo "Archive not found: $source" >&2
                    return 1
                  fi

                  if [[ ! -e "$destination" ]]; then
                    echo "File or folder not found: $destination" >&2
                    return 1
                  fi

                  case "$source" in
                    *.tar) tar --append --file="$source" "$destination" ;;
                    *.tar.*|*.tgz|*.tbz2|*.txz|*.tzst)
                      echo "Cannot add files to compressed tar archives; recreate the archive instead." >&2
                      return 1
                      ;;
                    *) 7z a "$source" "$destination" ;;
                  esac
                  ;;
                remove)
                  if [[ -z "$source" || -z "$destination" ]]; then
                    echo "Usage: ex remove <archive> <archive-path>" >&2
                    return 2
                  fi

                  if [[ ! -f "$source" ]]; then
                    echo "Archive not found: $source" >&2
                    return 1
                  fi

                  case "$source" in
                    *.tar) tar --delete --file="$source" "$destination" ;;
                    *.tar.*|*.tgz|*.tbz2|*.txz|*.tzst)
                      echo "Cannot remove files from compressed tar archives; recreate the archive instead." >&2
                      return 1
                      ;;
                    *) 7z d "$source" "$destination" ;;
                  esac
                  ;;
                *)
                  cat >&2 <<'EOF'
      Usage:
        ex compress <file-or-folder> <destination-archive>
        ex extract <archive> <destination-folder> [archive-path...]
        ex add <archive> <file-or-folder>
        ex remove <archive> <archive-path>
      EOF
                  return 2
                  ;;
              esac
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

      # Disables the "on ☁️  <gcloud account>" segment that appears whenever
      # a gcloud config/active account is present (e.g. from `gcloud auth login`).
      gcloud.disabled = true;

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
        {
          key = "F11";
          action = "ToggleFullscreen";
        }
      ];
    };
  };
}
