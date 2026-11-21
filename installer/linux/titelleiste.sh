# Skalierung und Titelleiste (ab 2.5). Wird in AppRun vor dem Programmstart
# eingefügt.
#
# Skalierung: Xft.dpi des Desktops bei jedem Start an Wine geben, nicht nur
# beim ersten. Nur wenn sie sich seit dem letzten Start geändert hat, damit
# eine eigene Einstellung in winecfg bleibt.
_dpi="${STEMMAKER_DPI:-}"
if [ -z "$_dpi" ] && command -v xrdb >/dev/null 2>&1; then
  _dpi=$(xrdb -query 2>/dev/null | awk '/^Xft.dpi:/{print int($2)}')
fi
if [ -n "$_dpi" ] && [ "$_dpi" -ge 96 ] 2>/dev/null && \
   [ "$_dpi" != "$(cat "$DATA/desktop-dpi" 2>/dev/null)" ]; then
  "$WINE" reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d "$_dpi" /f >/dev/null 2>&1
  "$WINESERVER" -w
  echo "$_dpi" > "$DATA/desktop-dpi" 2>/dev/null
fi
unset _dpi

# Titelleiste: Den Rahmen zeichnet der Fenstermanager des Desktops. Er wird
# dunkel, wenn das Fenster _GTK_THEME_VARIANT=dark trägt (GNOME, Cinnamon,
# MATE, XFCE). Ein Hintergrund-Prozess setzt das für die Fenster von
# StemMaker und den AddOns, passend zum Design in StemMaker (Wine-Farbe
# "Window" in user.reg, siehe uWineFarben). Ohne xprop passiert nichts.
_titelleisten() {
  local fremd="" leer=0 zyklus=0 ids id klasse art w
  while :; do
    art=light
    w=$(awk '/^\[/{f=($0 ~ /^\[Control Panel\\\\Colors\]/)} f && /^"Window"=/{gsub(/[^0-9 ]/,"");print $1;exit}' "$WINEPREFIX/user.reg" 2>/dev/null)
    [ -n "$w" ] && [ "$w" -lt 128 ] && art=dark
    ids=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*')
    leer=$((leer + 1))
    # Fensternummern werden wiederverwendet: Listen ab und zu leeren
    zyklus=$((zyklus + 1))
    [ $((zyklus % 30)) -eq 0 ] && fremd=""
    for id in $ids; do
      case " $fremd " in *" $id "*) continue ;; esac
      klasse=$(xprop -id "$id" WM_CLASS 2>/dev/null)
      case "$klasse" in
        *[Ss]tem[Mm]aker.exe*|*[Ss]tem[Pp]layer.exe*|*[Ss]tem[Tt]agger.exe*|*[Ss]tem[Pp]acker.exe*|*[Ss]tem[Dd]ecks.exe*|*[Ss]tem51.exe*)
          leer=0
          # Wine verwendet Fensternummern wieder: darum jedes Mal den Wert
          # am Fenster prüfen und nur setzen, wenn er fehlt oder anders ist
          case "$(xprop -id "$id" _GTK_THEME_VARIANT 2>/dev/null)" in
            *\"$art\"*) ;;
            *) xprop -id "$id" -f _GTK_THEME_VARIANT 8u -set _GTK_THEME_VARIANT "$art" 2>/dev/null ;;
          esac ;;
        # fremd merken, aber nur wenn WM_CLASS schon gesetzt ist (Wine setzt
        # sie bei neuen Fenstern manchmal erst kurz nach dem Erscheinen)
        *\"*) fremd="$fremd $id" ;;
      esac
    done
    # Ende, wenn 60 s lang kein Fenster von StemMaker offen war
    [ "$leer" -ge 60 ] && break
    sleep 1
  done
}
if [ -n "${DISPLAY:-}" ] && command -v xprop >/dev/null 2>&1; then
  case "${1:-}" in
    --cli|--winecfg|--run) ;;
    *) (_titelleisten >/dev/null 2>&1 &) ;;
  esac
fi
