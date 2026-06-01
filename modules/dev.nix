{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Python toolchain
    python3
    uv
    ruff
    pyright
    # Container / infra
    lazydocker
    # CLI utilities
    btop
    eza
    bat
    fd
    ripgrep
    jq
  ];

  programs.vscode = {
    enable = true;
    package = pkgs.vscode.fhs;
    mutableExtensionsDir = true;

    profiles.default = {
      userSettings = {
        "editor.fontFamily" = "JetBrainsMono Nerd Font";
        "editor.fontLigatures" = true;
        "editor.formatOnSave" = true;
        "editor.minimap.enabled" = false;
        "terminal.integrated.defaultProfile.linux" = "bash";
        "files.trimTrailingWhitespace" = true;
      };
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

  # VSCode needs gnome-libsecret to avoid keyring warnings
  home.file.".vscode/argv.json".text = ''
    {
      "password-store": "gnome-libsecret"
    }
  '';

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
