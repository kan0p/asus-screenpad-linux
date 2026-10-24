#!/bin/sh
# deshace install.sh
set -e
[ "$(id -u)" = 0 ] || { echo "ejecuta como root: sudo ./uninstall.sh" >&2; exit 1; }
USUARIO=${SUDO_USER:-}
if [ -n "$USUARIO" ]; then
    systemctl --user -M "$USUARIO@" disable --now glasspad-launcher.service glasspadd.service \
        screenpad-launcher.service screenpadd.service 2>/dev/null || true
fi
systemctl disable --now glasspad-numpad.service glasspad-numpad.socket \
    screenpad-numpad.service screenpad-numpad.socket 2>/dev/null || true
systemctl disable --now screenpad.service 2>/dev/null || true
/usr/local/bin/screenpad off 2>/dev/null || true
rm -f /usr/local/bin/screenpad /usr/local/bin/glasspadd /usr/local/bin/glasspad /usr/local/bin/gpad \
      /usr/local/bin/glasspad-launcher /usr/local/bin/glasspad-config /usr/local/bin/glasspad-numpad \
      /usr/local/bin/screenpadd /usr/local/bin/screenpadctl /usr/local/bin/screenpad-launcher \
      /usr/local/bin/screenpad-config /usr/local/bin/screenpad-numpad
rm -f /etc/systemd/system/screenpad.service /etc/systemd/system/glasspad-numpad.service \
      /etc/systemd/system/glasspad-numpad.socket /etc/systemd/user/glasspadd.service \
      /etc/systemd/user/glasspad-launcher.service /etc/systemd/system/screenpad-numpad.service \
      /etc/systemd/system/screenpad-numpad.socket /etc/systemd/user/screenpadd.service \
      /etc/systemd/user/screenpad-launcher.service
rm -f /etc/modules-load.d/screenpad.conf /etc/modules-load.d/glasspad.conf \
      /etc/udev/rules.d/70-glasspad.rules /etc/udev/hwdb.d/70-glasspad.hwdb /etc/sudoers.d/glasspad \
      /etc/udev/rules.d/70-screenpad.rules /etc/udev/hwdb.d/70-screenpad.hwdb /etc/sudoers.d/screenpad \
      /usr/local/share/applications/io.github.kan0p.GlassPad.Config.desktop \
      /usr/local/share/applications/io.github.kan0p.ScreenPad.Config.desktop
rm -rf /usr/local/lib/screenpad /var/lib/screenpad /usr/local/share/glasspad /usr/local/share/screenpad
systemd-hwdb update 2>/dev/null || udevadm hwdb --update
udevadm control --reload
udevadm trigger --action=change --subsystem-match=input
systemctl daemon-reload
echo "Desinstalación completa."
