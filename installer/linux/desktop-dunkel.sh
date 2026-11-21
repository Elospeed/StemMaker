# Hell oder dunkel wie der Linux-Desktop (StemMaker-Design "Automatisch", ab 2.5).
# Wird in AppRun eingefügt. Setzt ELOSPEED_DESKTOP_DUNKEL=1, wenn der Desktop
# dunkel ist; StemMaker und die AddOns lesen das (uWineFarben).
# Erkennt GNOME/Ubuntu und Cinnamon/Mint (color-scheme, GTK-Thema), XFCE und KDE.
if [ -z "${ELOSPEED_DESKTOP_DUNKEL:-}" ]; then
  ELOSPEED_DESKTOP_DUNKEL=0
  _hinweise="${GTK_THEME:-}"
  if command -v gsettings >/dev/null 2>&1; then
    for _k in "org.gnome.desktop.interface color-scheme" "org.x.apps.portal color-scheme" \
              "org.cinnamon.desktop.interface gtk-theme" "org.gnome.desktop.interface gtk-theme" \
              "org.mate.interface gtk-theme"; do
      _hinweise="$_hinweise $(timeout 2 gsettings get $_k 2>/dev/null)"
    done
  fi
  if command -v xfconf-query >/dev/null 2>&1; then
    _hinweise="$_hinweise $(timeout 2 xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null)"
  fi
  _kde="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"
  if [ -f "$_kde" ]; then
    _hinweise="$_hinweise $(grep -i '^ColorScheme=' "$_kde" 2>/dev/null)"
  fi
  case "$_hinweise" in
    *[Dd]ark*|*[Dd]unkel*) ELOSPEED_DESKTOP_DUNKEL=1 ;;
  esac
  unset _hinweise _k _kde
fi
export ELOSPEED_DESKTOP_DUNKEL
