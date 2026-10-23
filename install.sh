#!/bin/sh
# copia scripts, EDID de respaldo, servicios y permisos; deja todo habilitado
set -e
[ "$(id -u)" = 0 ] || { echo "ejecuta como root: sudo ./install.sh" >&2; exit 1; }
USUARIO=${SUDO_USER:-}
[ -n "$USUARIO" ] && [ "$USUARIO" != root ] || { echo "ejecuta con sudo desde tu usuario, no como root directo" >&2; exit 1; }
cd "$(dirname "$0")"

python3 -c 'import evdev, gi' 2>/dev/null || {
    echo "faltan dependencias de Python: python-evdev y python-gobject" >&2; exit 1; }

primera=1
systemctl is-enabled --quiet screenpad.service 2>/dev/null && primera=0

# sistema: encendido del panel y EDID
install -Dm755 screenpad /usr/local/bin/screenpad
install -Dm644 edid/ux580-tsb-fixed.bin /usr/local/lib/screenpad/ux580-tsb-fixed.bin
install -Dm644 systemd/screenpad.service /etc/systemd/system/screenpad.service
printf 'acpi_call\ni2c-dev\n' > /etc/modules-load.d/screenpad.conf

# sesión: modos y Fn+F6
install -Dm755 screenpadd /usr/local/bin/screenpadd
install -Dm755 screenpadctl /usr/local/bin/screenpadctl
install -Dm644 systemd/screenpadd.service /etc/systemd/user/screenpadd.service

# permisos: lectura de las teclas ASUS y del pad, y screenpad sin contraseña;
# Fn+F6 deja de ser KEY_TOUCHPAD_TOGGLE para que el escritorio no la tome
install -Dm644 udev/70-screenpad.rules /etc/udev/rules.d/70-screenpad.rules
install -Dm644 udev/70-screenpad.hwdb /etc/udev/hwdb.d/70-screenpad.hwdb
tmp=$(mktemp)
sed "s/^USUARIO /$USUARIO /" sudoers/screenpad > "$tmp"
visudo -cqf "$tmp" || { rm -f "$tmp"; echo "la regla sudoers no es válida, no se instaló" >&2; exit 1; }
install -m440 "$tmp" /etc/sudoers.d/screenpad
rm -f "$tmp"
systemd-hwdb update 2>/dev/null || udevadm hwdb --update
udevadm control --reload
udevadm trigger --action=change --subsystem-match=input

systemctl daemon-reload
systemctl enable screenpad.service
[ $primera = 1 ] && /usr/local/bin/screenpad on

if systemctl --user -M "$USUARIO@" daemon-reload 2>/dev/null; then
    systemctl --user -M "$USUARIO@" enable screenpadd.service
    systemctl --user -M "$USUARIO@" restart screenpadd.service
else
    echo "activa el servicio de sesión con: systemctl --user enable --now screenpadd"
fi
echo "Instalación completa. Fn+F6 cambia el modo del ScreenPad."
