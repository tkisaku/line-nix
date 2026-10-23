{
  description = "Run the Windows version of LINE on Linux with Wine";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      # The Full variant embeds the matching Wine Mono and Gecko installers.
      wine = pkgs.wineWow64Packages.stableFull;

      line-wine-script = pkgs.writeShellApplication {
        name = "line-wine";
        runtimeInputs = with pkgs; [
          coreutils
          findutils
          gnugrep
          openssl
          osslsigncode
          wine
          winetricks
        ];
        text = ''
                    set -o pipefail

                    data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
                    export WINEPREFIX="''${LINE_WINEPREFIX:-$data_home/line-wine}"
                    export WINEARCH=win64
                    export WINEDLLOVERRIDES="winemenubuilder.exe=d"

                    usage() {
                      cat <<'EOF'
          Usage:
            line-wine                         Start LINE
            line-wine --install LineInst.exe  Install or update LINE
            line-wine --winecfg               Open Wine configuration
            line-wine --winetricks ARGS       Run winetricks

          Environment:
            LINE_WINEPREFIX  Override the Wine prefix (default: $XDG_DATA_HOME/line-wine)
          EOF
                    }

          initialise_prefix() {
            runtime_id="${wine}"
            runtime_marker="$WINEPREFIX/.line-wine-runtime"
            installed_runtime="$(cat "$runtime_marker" 2>/dev/null || true)"
            signature_id="$runtime_id-line-signature-v1"
            signature_marker="$WINEPREFIX/.line-wine-signature"
            installed_signature="$(cat "$signature_marker" 2>/dev/null || true)"

            mkdir -p "$WINEPREFIX"
            if [[ ! -d "$WINEPREFIX/drive_c" ]]; then
              wineboot --init
            elif [[ "$installed_runtime" != "$runtime_id" ]]; then
              # Refresh an existing prefix when the packaged Wine runtime changes.
              # This Wine build embeds Mono and Gecko, so this requires no download.
              wineboot --update
            fi

            if [[ "$installed_runtime" != "$runtime_id" ]]; then
              wineserver --wait
              printf '%s\n' "$runtime_id" > "$runtime_marker"
            fi

            if [[ "$installed_signature" != "$signature_id" ]]; then
              sign_wine_dlls
              printf '%s\n' "$signature_id" > "$signature_marker"
            fi
          }

          sign_wine_dlls() {
            local signing_dir="$WINEPREFIX/.line-wine-signing"
            local certificate="$signing_dir/line-compat.crt"
            local private_key="$signing_dir/line-compat.key"
            local dll signed_dll
            local signed=0
            local failed=0

            mkdir -p "$signing_dir"
            chmod 700 "$signing_dir"

            if [[ ! -f "$certificate" || ! -f "$private_key" ]]; then
              openssl req -x509 -new -nodes -sha256 -newkey rsa:2048 \
                -days 3650 \
                -subj '/O=Microsoft Corporation/CN=Microsoft Windows' \
                -addext 'subjectAltName=DNS:microsoft.com' \
                -keyout "$private_key" \
                -out "$certificate" >/dev/null 2>&1
              chmod 600 "$private_key"
            fi

            echo "Applying local compatibility signatures to Wine DLLs..."
            while IFS= read -r -d "" dll; do
              signed_dll="$dll.line-signed"
              if osslsigncode sign \
                -h sha256 \
                -certs "$certificate" \
                -key "$private_key" \
                -n 'LINE Wine local compatibility' \
                -in "$dll" \
                -out "$signed_dll" >/dev/null 2>&1; then
                chmod --reference="$dll" "$signed_dll"
                mv -f "$signed_dll" "$dll"
                signed=$((signed + 1))
              else
                rm -f "$signed_dll"
                failed=$((failed + 1))
              fi
            done < <(
              find \
                "$WINEPREFIX/drive_c/windows/system32" \
                "$WINEPREFIX/drive_c/windows/syswow64" \
                -maxdepth 1 -type f -iname '*.dll' -print0
            )
            echo "Compatibility signatures applied: $signed (skipped: $failed)"
          }

                    find_line() {
                      local candidate
                      local wine_user="''${USER:-$(id -un)}"
                      local -a candidates=(
                        "$WINEPREFIX/drive_c/users/$wine_user/AppData/Local/LINE/bin/LineLauncher.exe"
                        "$WINEPREFIX/drive_c/users/$wine_user/AppData/Local/LINE/bin/LINE.exe"
                        "$WINEPREFIX/drive_c/Program Files/LINE/LINE.exe"
                        "$WINEPREFIX/drive_c/Program Files (x86)/LINE/LINE.exe"
                      )

                      for candidate in "''${candidates[@]}"; do
                        if [[ -f "$candidate" ]]; then
                          printf '%s\n' "$candidate"
                          return 0
                        fi
                      done

                      find "$WINEPREFIX/drive_c/users" -type f \
                        \( -iname 'LineLauncher.exe' -o -iname 'LINE.exe' \) \
                        -print -quit 2>/dev/null
                    }

                    case "''${1:-}" in
                      --help|-h)
                        usage
                        exit 0
                        ;;
                      --winecfg)
                        initialise_prefix
                        exec winecfg
                        ;;
                      --install)
                        if [[ $# -ne 2 ]]; then
                          echo "error: --install requires the path to LineInst.exe" >&2
                          usage >&2
                          exit 2
                        fi
                        installer="$(realpath "$2")"
                        if [[ ! -f "$installer" ]]; then
                          echo "error: installer not found: $installer" >&2
                          exit 1
                        fi
                        initialise_prefix
                        wine "$installer"
                        wineserver --wait
                        exit 0
                        ;;
                      --winetricks)
                        initialise_prefix
                        shift
                        WINE_BIN="$(dirname "$(readlink -f "$(command -v wine)")")/.wine" \
                        exec winetricks "$@"
                        ;;
                      "")
                        initialise_prefix
                        line_exe="$(find_line)"
                        if [[ -z "$line_exe" ]]; then
                          echo "LINE is not installed in $WINEPREFIX" >&2
                          echo "Run: line-wine --install /path/to/LineInst.exe" >&2
                          exit 1
                        fi
                        exec wine "$line_exe"
                        ;;
                      *)
                        echo "error: unknown argument: $1" >&2
                        usage >&2
                        exit 2
                        ;;
                    esac
        '';
      };

      desktopItem = pkgs.makeDesktopItem {
        name = "line-wine";
        desktopName = "LINE (Wine)";
        comment = "Run the Windows version of LINE using Wine";
        exec = "line-wine";
        icon = "wine";
        categories = [
          "Network"
          "InstantMessaging"
        ];
        terminal = false;
      };

      line-wine = pkgs.symlinkJoin {
        name = "line-wine";
        paths = [
          line-wine-script
          desktopItem
        ];
      };
    in
    {
      packages.${system} = {
        inherit line-wine;
        default = line-wine;
      };

      apps.${system} = {
        line-wine = {
          type = "app";
          program = "${line-wine}/bin/line-wine";
          meta.description = "Run the Windows version of LINE using Wine";
        };
        default = self.apps.${system}.line-wine;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ line-wine ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
