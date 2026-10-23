# LINE on Linux with Wine

Windows 版 LINE を Wine で起動するための Nix flake です。
現在は `x86_64-linux` に対応しています。

## 初回セットアップ

LINE の配布URLから Windows 版インストーラー (`LineInst.exe`) をダウンロードします。

```console
mkdir -p ~/Downloads
curl --fail --location \
  --output ~/Downloads/LineInst.exe \
  http://desktop.line-scdn.net/win/new/LineInst.exe
```

`--location` は配布サーバーの HTTPS へのリダイレクトを追跡するために指定しています。
ダウンロード後、インストーラーを起動します。

```console
nix run . -- --install ~/Downloads/LineInst.exe
```

インストール後は次のコマンドだけで起動できます。

```console
nix run .
```

Wine の仮想 Windows 環境と LINE のユーザーデータは、既定では
`$XDG_DATA_HOME/line-wine`（未設定時は `~/.local/share/line-wine`）に保存されます。

LINE 26.1 以降には Windows DLL の署名検査があり、未対策の Wine では
`NO_SIGNATURE` エラーが発生します。この flake は専用 Wine prefix 内の DLL に
ローカルな互換署名を付けます。これは Microsoft が発行した署名ではなく、
ホスト OS の証明書ストアや Nix ストアには登録・変更されません。

## NixOS / Home Manager から利用する

このリポジトリを flake input に追加し、パッケージへ指定します。

```nix
{
  inputs.line-nix.url = "github:YOUR_ACCOUNT/line-nix";

  outputs = { nixpkgs, line-nix, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          environment.systemPackages = [
            line-nix.packages.${pkgs.system}.default
          ];
        })
      ];
    };
  };
}
```

Home Manager の場合は `home.packages` に同じパッケージを追加してください。
アプリケーション一覧には **LINE (Wine)** として登録されます。

## 補助コマンド

```console
# Wine の設定画面を開く
nix run . -- --winecfg

# winetricks を実行する
nix run . -- --winetricks ARGS

# 別の Wine prefix を利用する
LINE_WINEPREFIX="$HOME/.wine-line-test" nix run .
```

LINE 本体や更新後のバージョンによっては Wine で動作しない場合があります。
インストーラー自体はライセンス上この flake に含めていません。

## ライセンス

このプロジェクトは [Unlicense](LICENSE) によりパブリックドメインへ提供されています。
商用・非商用を問わず、誰でも任意の目的で利用、改変、複製、再配布できます。
