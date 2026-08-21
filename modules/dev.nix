{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # Python toolchain
    python3
    uv
    ruff
    pyright
    # PHP toolchain
    php
    phpPackages.composer
    # Container / infra
    lazydocker
    kubectl
    k9s
    terraform
    # Git
    lazygit
    # GitHub / HTTP
    gh
    xh
    # Nix
    nix-output-monitor
    # CLI utilities
    btop
    htop
    eza
    fd
    ripgrep
    jq
    yq-go
    shellcheck
    google-cloud-sdk
    azure-cli
    # Node.js
    nodejs_24
    nodePackages.pnpm
    p7zip
    tcpdump
    gh # GitHub CLI (gh) is used for GitHub API calls, e.g. to create PRs, view issues, etc.
    glab # GitLab CLI (glab) is used for GitLab API calls, e.g. to create MRs, view issues, etc.
    codex
    claude-code
  ];

  # ── bat ────────────────────────────────────────────────────────────────
  programs.bat = {
    enable = true;
    config = {
      # Never invoke a pager — output goes straight to stdout like cat.
      # Prevents scripts and AI agents from hanging waiting for keypress.
      pager = "never";
    };
  };

  # ── Git ────────────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    lfs.enable = true;
    # Email/name/signingKey live in untracked files (not in this repo):
    #   ~/.config/git/local          → personal (GitHub)
    #   ~/.config/git/work-gitlab    → work GitLab
    #   ~/.config/git/work-github    → work GitHub
    #   ~/.config/git/work-bitbucket → work Bitbucket
    includes = [
      { path = "~/.config/git/local"; }
      { path = "~/.config/git/work-gitlab";    condition = "gitdir:~/code/work/gitlab/"; }
      { path = "~/.config/git/work-github";    condition = "gitdir:~/code/work/github/"; }
      { path = "~/.config/git/work-bitbucket"; condition = "gitdir:~/code/work/bitbucket/"; }
    ];
    settings = {
      user.name = "dom";
      push.autoSetupRemote = true;
      pull.rebase = true;
      init.defaultBranch = "main";
      diff.colorMoved = "default";
      rerere.enabled = true;
      commit.gpgsign = true;
      gpg.format = "ssh";          # use SSH keys for signing (no separate GPG key needed)
      gpg.ssh.allowedSignersFile = "~/.config/git/allowed_signers";
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
      dark = true;
    };
  };

  # ── SSH ────────────────────────────────────────────────────────────────
  # Key files must be generated manually and are not stored in this repo.
  # Generate: ssh-keygen -t ed25519 -C "<email>" -f ~/.ssh/id_<name>
  # Then add the public key to the respective hosting account.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {

      # GitLab — only one account, real hostname → copy-paste clone URLs work
      "gitlab.com" = {
        hostname = "gitlab.com";
        user = "git";
        identityFile = "~/.ssh/id_work_gitlab";
      };

      # Bitbucket Cloud — not currently used but kept for reference
      # "bitbucket.org" = {
      #   hostname = "bitbucket.org";
      #   user = "git";
      #   identityFile = "~/.ssh/id_work_bitbucket";
      # };

      # Self-hosted Bitbucket — HostName and Port live in ~/.ssh/config.local
      # (untracked, never committed).  Create it with:
      #   Host bitbucket-work
      #     HostName bitbucket.yourcompany.com
      #     Port     7999
      # Clone: ssh://git@bitbucket-work/proj/repo.git  (or use bclone)
      "bitbucket-work" = {
        user = "git";
        identityFile = "~/.ssh/id_work_bitbucket";
      };

      # Personal GitHub — default for git@github.com:… copy-paste URLs
      # Work: use  git@github-work:org/repo.git  (see wclone in shell.nix)
      "github-work" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_work_github";
      };

      # Personal GitHub — default for git@github.com:… copy-paste URLs
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_personal";
      };

      # Required placeholder so that programs.ssh.extraConfig can be set
      # (Home Manager enforces that matchBlocks."*" is declared first).
      #
      # addKeysToAgent: automatically register any identity file used for a
      # successful connection (e.g. `ssh -i ~/.ssh/qsys-id ...`) with the
      # running agent (gpg-agent, via enableSshSupport below) after the first
      # passphrase prompt. Without this, ad-hoc keys not covered by the
      # ssh-add call in hyprland.nix's exec-once (or ~/.ssh/extra-keys) are
      # unknown to gpg-agent, which then refuses to sign with them
      # ("agent refused operation") — forcing you to spin up a fresh
      # `ssh-agent` per session as a workaround.
      "*" = {
        addKeysToAgent = "yes";
      };
    };

    # Top-level Include — must be outside any Host block so the included files
    # are parsed as standalone Host entries.  SSH collects all matching blocks
    # across the full config before connecting, so HostName/Port defined here
    # are applied even though this section appears after the specific Host blocks.
    #   config.hosts  — individual host entries (servers, services, jump hosts)
    #   config.local  — machine-local overrides (ProxyJump, port forwards, …)
    extraConfig = "Include ~/.ssh/config.hosts ~/.ssh/config.local";
  };

  # ── GPG + agent (also handles SSH keys via enableSshSupport) ───────────
  programs.gpg.enable = true;

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;   # replaces ssh-agent; SSH_AUTH_SOCK → gpg-agent
    pinentry.package = pkgs.pinentry-gnome3;  # graphical prompt on Wayland
    defaultCacheTtl = 86400;   # 24 h — passphrase cached after first use
    maxCacheTtl = 604800;      # 7 days
  };

  # gnome-keyring (services.gnome.gnome-keyring in configuration.nix, needed
  # for nm-applet's VPN secrets/SSO) ships its own gcr-ssh-agent, which
  # socket-activates on /run/user/$UID/gcr/ssh and races gpg-agent for
  # SSH_AUTH_SOCK — and usually wins, since it's started at login. Its
  # ssh-agent component has a bug where it accepts ED25519-CERT keys during
  # auth negotiation but then fails to actually sign with them
  # ("agent refused operation"), regardless of whether the key was
  # registered with it.
  #
  # Overriding gcr-ssh-agent's own systemd units directly is fragile — home-
  # manager's partial unit overrides drop required settings (e.g.
  # ListenStream=) from the package-provided unit, causing systemd to reject
  # it outright ("bad unit file setting"). Simpler and more robust: just
  # force SSH_AUTH_SOCK to always point at gpg-agent's socket, so it doesn't
  # matter which one wins the race — every new shell overrides it back.
  # Path is XDG_RUNTIME_DIR-based (not ~/.gnupg), confirmed via
  # `gpgconf --list-dirs agent-ssh-socket`.
  home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh";

  programs.vscode = {
    enable = true;
    package = pkgs.vscode.fhs;
    mutableExtensionsDir = true;

    # NOTE: `userSettings` is deliberately NOT set here.
    #
    # home-manager would symlink settings.json into the read-only Nix store,
    # and VS Code writes to that file at runtime — chat agent auto-approve
    # decisions, "don't ask again" prompts, trusted folders, UI state. Those
    # writes fail with EROFS.
    #
    # Instead ../vscode/settings.json is symlinked out-of-store below: still
    # version-controlled in this repo, but writable by VS Code, and changes
    # show up in `git status` without needing a rebuild.
    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        ms-python.python
        ms-python.vscode-pylance
        ms-python.debugpy
        redhat.vscode-yaml
        esbenp.prettier-vscode
        timonwong.shellcheck
        ms-azuretools.vscode-docker
        ms-vscode-remote.remote-containers
        ms-vscode-remote.remote-ssh
        ms-vscode-remote.remote-ssh-edit
        ms-vscode.remote-explorer
        ms-vscode.cmake-tools
        ms-vscode.cpptools
        ms-vscode.cpptools-extension-pack
        ms-vscode.makefile-tools
        eamodio.gitlens
        github.vscode-github-actions
        donjayamanne.githistory
        twxs.cmake
      ];
    };
  };

  # settings.json → this repo's working copy (writable, so VS Code can persist
  # its own runtime changes; tracked by git, so they are versioned).
  #
  # Only individual files are linked, not the whole ~/.config/Code/User dir:
  # globalStorage/, workspaceStorage/ and History/ are hundreds of megabytes of
  # machine-local cache that must stay out of the repo.
  xdg.configFile."Code/User/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/code/nixos-config/vscode/settings.json";

  # VSCode needs gnome-libsecret to avoid keyring warnings
  home.file.".vscode/argv.json".text = ''
    {
      "password-store": "gnome-libsecret"
    }
  '';

  # SSH refuses to use ~/.ssh/config when it's a symlink into the Nix store
  # (store files are owned by root / world-readable). Copy it to a real file.
  home.activation.sshConfigCopy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -L "$HOME/.ssh/config" ]; then
      target=$(readlink "$HOME/.ssh/config")
      cp "$target" "$HOME/.ssh/config.tmp"
      mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
      chmod 600 "$HOME/.ssh/config"
    fi
  '';

  # Remove legacy ~/.gitconfig so git uses Home Manager's ~/.config/git/config
  # (git prefers ~/.gitconfig over XDG config when both exist)
  home.activation.removeStaleGitconfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rm -f $HOME/.gitconfig
  '';

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
