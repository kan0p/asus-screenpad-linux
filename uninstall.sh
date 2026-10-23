#!/bin/sh
# deshace install.sh
set -e
[ "$(id -u)" = 0 ] || { echo "ejecuta como root: sudo ./uninstall.sh" >&2; exit 1; }
USUARIO=${SUDO_USER:-}
if [ -n "$USUARIO" ]; then
    systemctl --user -M "$USUARIO@" disable --now screenpadd.service 2>/dev/null || true
fi
systemctl disable --now screenpad.service 2>/dev/null || true
/usr/local/bin/screenpad off 2>/dev/null || true
rm -f /usr/local/bin/screenpad /usr/local/bin/screenpadd /usr/local/bin/screenpadctl
rm -f /etc/systemd/system/screenpad.service /etc/systemd/user/screenpadd.service
rm -f /etc/modules-load.d/screenpad.conf /etc/udev/rules.d/70-screenpad.rules /etc/sudoers.d/screenpad
rm -f /etc/udev/hwdb.d/70-screenpad.hwdb
rm -rf /usr/local/lib/screenpad /var/lib/screenpad
systemd-hwdb update 2>/dev/null || udevadm hwdb --update
udevadm control --reload
udevadm trigger --action=change --subsystem-match=input
systemctl daemon-reload
echo "Desinstalación completa."
