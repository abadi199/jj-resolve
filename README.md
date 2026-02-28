# jj-resolve

GTK-based GUI built with Zig and zig-gobject.

## macOS development setup (Apple Silicon)

### Prerequisites
- Zig 0.15.2+
- Homebrew
- direnv

### Install dependencies
```sh
brew install gtk4 libadwaita gtksourceview5 gobject-introspection pkg-config
```

### Environment variables (direnv)
1) Copy the example env file and allow it:
```sh
cp .envrc.macos .envrc
direnv allow
```

The default `.envrc.macos` sets:
- `PKG_CONFIG_PATH` to Homebrew's pkg-config directories.

### Build and run
```sh
zig build
zig build run
```
