#!/bin/sh
# deshace install.sh
set -e
[ "$(id -u)" = 0 ] || { echo "ejecuta como root: sudo ./uninstall.sh" >&2; exit 1; }
systemctl disable --now screenpad.service 2>/dev/null || true
/usr/local/bin/screenpad off 2>/dev/null || true
rm -f /usr/local/bin/screenpad /etc/systemd/system/screenpad.service /etc/modules-load.d/screenpad.conf
rm -rf /usr/local/lib/screenpad /var/lib/screenpad
systemctl daemon-reload
echo "Desinstalación completa."
