#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

language_hint="${LANG:-} $(defaults read -g AppleLanguages 2>/dev/null || true)"
case "$language_hint" in
  *zh-Hans*|*zh_CN*) language=zh ;;
  *ja*|*JP*) language=ja ;;
  *es*) language=es ;;
  *fr*) language=fr ;;
  *) language=en ;;
esac

case "$language" in
  zh)
    arch_error="FilmCutter 1.1 仅支持 Apple Silicon。"; os_error="FilmCutter 需要 macOS 14 或更高版本。"; incomplete="发布包不完整。"; checksum_error="文件校验失败"; upgrade="升级 FilmCutter"; upgrade_to="至 1.1？[y/N]"; failed="安装失败，已恢复之前的版本。"; installed="FilmCutter 1.1 已安装到 ~/Applications。" ;;
  ja)
    arch_error="FilmCutter 1.1はApple Silicon専用です。"; os_error="FilmCutterにはmacOS 14以降が必要です。"; incomplete="リリースパッケージが不完全です。"; checksum_error="チェックサム検証に失敗しました"; upgrade="FilmCutterを"; upgrade_to="から1.1へ更新しますか？ [y/N]"; failed="インストールに失敗したため、以前のバージョンを復元しました。"; installed="FilmCutter 1.1を~/Applicationsにインストールしました。" ;;
  es)
    arch_error="FilmCutter 1.1 requiere Apple Silicon."; os_error="FilmCutter requiere macOS 14 o posterior."; incomplete="El paquete de publicación está incompleto."; checksum_error="Falló la verificación"; upgrade="Actualizar FilmCutter"; upgrade_to="a 1.1? [y/N]"; failed="La instalación falló; se restauró la versión anterior."; installed="FilmCutter 1.1 se instaló en ~/Applications." ;;
  fr)
    arch_error="FilmCutter 1.1 nécessite Apple Silicon."; os_error="FilmCutter nécessite macOS 14 ou version ultérieure."; incomplete="Le paquet de publication est incomplet."; checksum_error="Échec de la vérification"; upgrade="Mettre FilmCutter"; upgrade_to="à niveau vers 1.1 ? [y/N]"; failed="L’installation a échoué ; la version précédente a été restaurée."; installed="FilmCutter 1.1 est installé dans ~/Applications." ;;
  *)
    arch_error="FilmCutter 1.1 requires Apple Silicon."; os_error="FilmCutter requires macOS 14 or later."; incomplete="Incomplete release package."; checksum_error="Checksum verification failed"; upgrade="Upgrade FilmCutter"; upgrade_to="to 1.1? [y/N]"; failed="Installation failed; the previous version was restored."; installed="FilmCutter 1.1 is installed in ~/Applications." ;;
esac

pause_and_exit() { echo "$1"; read -k 1; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || pause_and_exit "$arch_error"
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 14 )) || pause_and_exit "$os_error"
[[ -d FilmCutter.app && -f CHECKSUMS.txt ]] || pause_and_exit "$incomplete"
while IFS= read -r line; do
  expected="${line%% *}"
  relative="${line#*  }"
  actual="$(shasum -a 256 "$relative" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || pause_and_exit "$checksum_error: $relative"
done < CHECKSUMS.txt
TARGET="$HOME/Applications/FilmCutter.app"
BACKUP="$HOME/Applications/.FilmCutter.previous.app"
mkdir -p "$HOME/Applications"
if [[ -d "$TARGET" ]]; then
  old=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET/Contents/Info.plist" 2>/dev/null || echo unknown)
  echo "$upgrade $old $upgrade_to"
  read answer
  [[ "$answer" == [yY] ]] || exit 0
  rm -rf "$BACKUP"
  mv "$TARGET" "$BACKUP"
fi
if ! ditto FilmCutter.app "$TARGET" || ! codesign --verify --deep --strict "$TARGET"; then
  rm -rf "$TARGET"
  [[ -d "$BACKUP" ]] && mv "$BACKUP" "$TARGET"
  echo "$failed"
  read -k 1; exit 1
fi
[[ "${FILMCUTTER_SKIP_LAUNCH:-0}" == "1" ]] || open "$TARGET"
echo "$installed"
