{ pkgs, ... }:

{
  # Ruby version comes from .ruby-version (also read by the Gemfile and
  # Cloudflare Pages), resolved to an exact release by nixpkgs-ruby.
  languages.ruby = {
    enable = true;
    versionFile = ./.ruby-version;
  };

  # No engines pin in package.json; use the current LTS for esbuild/wrangler.
  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_24;
  };

  # Headers/tools for gems with native extensions (openssl, io-event, ...)
  packages = with pkgs; [
    openssl
    libyaml
    pkg-config
  ];
}
