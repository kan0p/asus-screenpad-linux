#!/bin/sh
# deshace install.sh (instalación manual en /usr/local)
set -e
[ "$(id -u)" = 0 ] || { echo "ejecuta como root: sudo ./uninstall.sh" >&2; exit 1; }
USUARIO=${SUDO_USER:-}
if [ -n "$USUARIO" ]; then
    systemctl --user -M "$USUARIO@" disable --now glasspad-launcher.service glasspadd.service \
        2>/dev/null || true
    systemctl --user -M "$USUARIO@" disable --now screenpad-launcher.service screenpadd.service \
        2>/dev/null || true
fi
systemctl disable --now glasspad-numpad.service glasspad-numpad.socket 2>/dev/null || true
systemctl disable --now screenpad-numpad.service screenpad-numpad.socket 2>/dev/null || true
systemctl disable --now screenpad.service 2>/dev/null || true
/usr/local/bin/screenpad off 2>/dev/null || true

B=/usr/local/bin
rm -f $B/screenpad $B/glasspadd $B/glasspad $B/gpad $B/glasspad-launcher $B/glasspad-config \
      $B/glasspad-numpad $B/screenpadd $B/screenpadctl $B/screenpad-launcher $B/screenpad-config \
      $B/screenpad-numpad
rm -f /etc/systemd/system/screenpad.service /etc/systemd/system/glasspad-numpad.service \
      /etc/systemd/system/glasspad-numpad.socket /etc/systemd/user/glasspadd.service \
      /etc/systemd/user/glasspad-launcher.service /etc/systemd/system/screenpad-numpad.service \
      /etc/systemd/system/screenpad-numpad.socket /etc/systemd/user/screenpadd.service \
      /etc/systemd/user/screenpad-launcher.service
rm -f /etc/modules-load.d/screenpad.conf /etc/modules-load.d/glasspad.conf \
      /etc/sysusers.d/glasspad.conf /usr/share/polkit-1/actions/io.github.kan0p.glasspad.policy \
      /etc/udev/rules.d/70-glasspad.rules /etc/udev/hwdb.d/70-glasspad.hwdb \
      /etc/udev/rules.d/70-screenpad.rules /etc/udev/hwdb.d/70-screenpad.hwdb \
      /etc/sudoers.d/glasspad /etc/sudoers.d/screenpad \
      /usr/local/share/applications/io.github.kan0p.GlassPad.Config.desktop \
      /usr/local/share/applications/io.github.kan0p.ScreenPad.Config.desktop
rm -rf /usr/local/lib/screenpad /var/lib/screenpad /usr/local/share/glasspad /usr/local/share/screenpad
getent group glasspad > /dev/null && groupdel glasspad
systemd-hwdb update 2>/dev/null || udevadm hwdb --update
udevadm control --reload
udevadm trigger --action=change --subsystem-match=input
systemctl daemon-reload
echo "Desinstalación completa. La configuración de cada usuario queda en ~/.config/glasspad y"
echo "~/.local/state/glasspad; bórrala a mano si ya no la necesitas."
