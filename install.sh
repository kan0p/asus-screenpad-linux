#!/bin/sh
# copia scripts, EDID de respaldo, servicios y permisos; deja todo habilitado
set -e
[ "$(id -u)" = 0 ] || { echo "ejecuta como root: sudo ./install.sh" >&2; exit 1; }
USUARIO=${SUDO_USER:-}
[ -n "$USUARIO" ] && [ "$USUARIO" != root ] || { echo "ejecuta con sudo desde tu usuario, no como root directo" >&2; exit 1; }
cd "$(dirname "$0")"

python3 -c 'import evdev, gi' 2>/dev/null || {
    echo "faltan dependencias de Python: python-evdev y python-gobject" >&2; exit 1; }
python3 -c 'import gi; gi.require_version("Gtk4LayerShell", "1.0"); gi.require_version("Adw", "1")' 2>/dev/null || {
    echo "faltan gtk4-layer-shell y libadwaita (launcher y configuración)" >&2; exit 1; }

primera=1
systemctl is-enabled --quiet screenpad.service 2>/dev/null && primera=0

# instalaciones previas con los nombres screenpad*
systemctl --user -M "$USUARIO@" disable --now screenpadd.service screenpad-launcher.service 2>/dev/null || true
systemctl disable --now screenpad-numpad.socket screenpad-numpad.service 2>/dev/null || true
rm -f /usr/local/bin/screenpadd /usr/local/bin/screenpadctl /usr/local/bin/screenpad-launcher \
      /usr/local/bin/screenpad-config /usr/local/bin/screenpad-numpad \
      /etc/systemd/user/screenpadd.service /etc/systemd/user/screenpad-launcher.service \
      /etc/systemd/system/screenpad-numpad.service /etc/systemd/system/screenpad-numpad.socket \
      /etc/udev/rules.d/70-screenpad.rules /etc/udev/hwdb.d/70-screenpad.hwdb /etc/sudoers.d/screenpad \
      /usr/local/share/applications/io.github.kan0p.ScreenPad.Config.desktop
rm -rf /usr/local/share/screenpad

# sistema: encendido del panel y EDID
install -Dm755 screenpad /usr/local/bin/screenpad
install -Dm644 edid/ux580-tsb-fixed.bin /usr/local/lib/screenpad/ux580-tsb-fixed.bin
install -Dm644 systemd/screenpad.service /etc/systemd/system/screenpad.service
printf 'acpi_call\ni2c-dev\n' > /etc/modules-load.d/screenpad.conf

# sesión: modos y Fn+F6
install -Dm755 glasspadd /usr/local/bin/glasspadd
install -Dm755 glasspad /usr/local/bin/glasspad
ln -sf glasspad /usr/local/bin/gpad
install -Dm644 systemd/glasspadd.service /etc/systemd/user/glasspadd.service

# teclado numérico virtual de Number Key (root, socket solo para el usuario)
printf 'uinput\n' > /etc/modules-load.d/glasspad.conf
modprobe uinput 2>/dev/null || true
install -Dm755 glasspad-numpad /usr/local/bin/glasspad-numpad
install -Dm644 systemd/glasspad-numpad.service /etc/systemd/system/glasspad-numpad.service
sed "s/^SocketUser=USUARIO$/SocketUser=$USUARIO/" systemd/glasspad-numpad.socket \
    | install -Dm644 /dev/stdin /etc/systemd/system/glasspad-numpad.socket

# launcher y configuración
install -Dm755 glasspad-launcher /usr/local/bin/glasspad-launcher
install -Dm755 glasspad-config /usr/local/bin/glasspad-config
install -Dm644 systemd/glasspad-launcher.service /etc/systemd/user/glasspad-launcher.service
for f in icons/*/*.svg; do install -Dm644 "$f" "/usr/local/share/glasspad/$f"; done
install -Dm644 /dev/stdin /usr/local/share/applications/io.github.kan0p.GlassPad.Config.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=GlassPad Configurator
Comment=Configuración de GlassPad y del ScreenPad
Exec=glasspad-config
Icon=input-touchpad
Categories=Settings;HardwareSettings;
EOF

# permisos: lectura de las teclas ASUS y del pad, screenpad sin contraseña y
# remapeo de Fn+F6 (hwdb)
install -Dm644 udev/70-glasspad.rules /etc/udev/rules.d/70-glasspad.rules
install -Dm644 udev/70-glasspad.hwdb /etc/udev/hwdb.d/70-glasspad.hwdb
tmp=$(mktemp)
sed "s/^USUARIO /$USUARIO /" sudoers/glasspad > "$tmp"
visudo -cqf "$tmp" || { rm -f "$tmp"; echo "la regla sudoers no es válida, no se instaló" >&2; exit 1; }
install -m440 "$tmp" /etc/sudoers.d/glasspad
rm -f "$tmp"
systemd-hwdb update 2>/dev/null || udevadm hwdb --update
udevadm control --reload
udevadm trigger --action=change --subsystem-match=input

systemctl daemon-reload
systemctl enable screenpad.service
systemctl enable glasspad-numpad.socket glasspad-numpad.service
systemctl restart glasspad-numpad.socket glasspad-numpad.service
[ $primera = 1 ] && /usr/local/bin/screenpad on

if systemctl --user -M "$USUARIO@" daemon-reload 2>/dev/null; then
    systemctl --user -M "$USUARIO@" enable glasspadd.service glasspad-launcher.service
    systemctl --user -M "$USUARIO@" restart glasspadd.service glasspad-launcher.service
else
    echo "activa los servicios de sesión con: systemctl --user enable --now glasspadd glasspad-launcher"
fi
command -v wtype > /dev/null || echo "aviso: Quick Key necesita wtype"
python3 -c 'import gi; gi.require_version("Playerctl", "2.0")' 2>/dev/null \
    || echo "aviso: los controles de música necesitan playerctl"
echo "Instalación completa. Fn+F6 cambia el modo del ScreenPad; 'glasspad' (o 'gpad') lo controla desde la terminal."
