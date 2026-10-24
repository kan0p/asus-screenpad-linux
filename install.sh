#!/bin/sh
# instala GlassPad: scripts, EDID de respaldo, servicios y permisos
#
# uso: sudo ./install.sh [--si]        instalación manual en /usr/local, para el usuario de sudo
#      ./install.sh --paquete DESTDIR  copia en DESTDIR con prefijo /usr, sin tocar el sistema
set -e
cd "$(dirname "$0")"

PAQUETE=0
SI=0
case "${1:-}" in
    --paquete) PAQUETE=1; DESTDIR=${2:?falta DESTDIR}; PREFIX=/usr ;;
    --si) SI=1 ;;
    "") ;;
    *) echo "uso: sudo ./install.sh [--si] | ./install.sh --paquete DESTDIR" >&2; exit 1 ;;
esac

if [ $PAQUETE = 1 ]; then
    BINDIR=$PREFIX/bin
    LIBDIR=$PREFIX/lib
    SYSTEMD=$PREFIX/lib/systemd
    UDEV=$PREFIX/lib/udev
    MODULOS=$PREFIX/lib/modules-load.d
else
    [ "$(id -u)" = 0 ] || { echo "ejecuta como root: sudo ./install.sh" >&2; exit 1; }
    USUARIO=${SUDO_USER:-}
    [ -n "$USUARIO" ] && [ "$USUARIO" != root ] || {
        echo "ejecuta con sudo desde tu usuario, no como root directo" >&2; exit 1; }
    DESTDIR=
    PREFIX=/usr/local
    BINDIR=$PREFIX/bin
    LIBDIR=$PREFIX/lib
    SYSTEMD=/etc/systemd
    UDEV=/etc/udev
    MODULOS=/etc/modules-load.d
fi
SHARE=$PREFIX/share
# polkit solo lee acciones de /usr/share
POLKIT=/usr/share/polkit-1/actions

# ----- dependencias (solo instalación manual) -----------------------------------------

falta() { printf '%s\n' "$1" >> "$FALTAN"; }

revisar_dependencias() {
    FALTAN=$(mktemp)
    python3 -c 'import gi' 2>/dev/null || falta gobject
    python3 -c 'import evdev' 2>/dev/null || falta evdev
    python3 -c 'import gi; gi.require_version("Gtk", "4.0")' 2>/dev/null || falta gtk4
    python3 -c 'import gi; gi.require_version("Adw", "1")' 2>/dev/null || falta adwaita
    python3 -c 'import gi; gi.require_version("Gtk4LayerShell", "1.0")' 2>/dev/null || falta layershell
    modinfo acpi_call > /dev/null 2>&1 || falta acpi_call
    command -v wtype > /dev/null || falta wtype
    python3 -c 'import gi; gi.require_version("Playerctl", "2.0")' 2>/dev/null || falta playerctl
    command -v wpctl > /dev/null || falta wpctl
    command -v pkexec > /dev/null || falta pkexec
    [ -s "$FALTAN" ] || { rm -f "$FALTAN"; return 0; }

    if command -v pacman > /dev/null; then
        GESTOR="pacman -S --needed"
        nombres="gobject:python-gobject evdev:python-evdev gtk4:gtk4 adwaita:libadwaita
                 layershell:gtk4-layer-shell acpi_call:acpi_call-dkms wtype:wtype
                 playerctl:playerctl wpctl:wireplumber pkexec:polkit"
    elif command -v apt-get > /dev/null; then
        GESTOR="apt-get install"
        nombres="gobject:python3-gi evdev:python3-evdev gtk4:gir1.2-gtk-4.0 adwaita:gir1.2-adw-1
                 layershell:gir1.2-gtk4layershell-1.0 acpi_call:acpi-call-dkms wtype:wtype
                 playerctl:gir1.2-playerctl-2.0 wpctl:wireplumber pkexec:pkexec"
    elif command -v dnf > /dev/null; then
        GESTOR="dnf install"
        nombres="gobject:python3-gobject evdev:python3-evdev gtk4:gtk4 adwaita:libadwaita
                 layershell:gtk4-layer-shell acpi_call:akmod-acpi_call wtype:wtype
                 playerctl:playerctl wpctl:wireplumber pkexec:polkit"
    else
        echo "faltan dependencias: $(tr '\n' ' ' < "$FALTAN")" >&2
        echo "no reconozco el gestor de paquetes: instálalas a mano (ver README)" >&2
        rm -f "$FALTAN"; exit 1
    fi
    paquetes=$(for d in $(cat "$FALTAN"); do
        for par in $nombres; do [ "${par%%:*}" = "$d" ] && echo "${par#*:}"; done
    done | tr '\n' ' ')
    rm -f "$FALTAN"

    echo "Faltan paquetes: $paquetes"
    case "$paquetes" in *acpi_call-dkms*|*acpi-call-dkms*)
        echo "  (acpi_call-dkms necesita los encabezados del kernel en uso, p. ej. linux-headers)" ;;
    esac
    case "$paquetes" in *akmod-acpi_call*)
        echo "  (akmod-acpi_call está en RPM Fusion: https://rpmfusion.org)" ;;
    esac
    if [ $SI = 0 ]; then
        printf "¿Instalarlos con '%s'? [s/N] " "$GESTOR"
        read -r respuesta
        case "$respuesta" in s|S|si|sí|SI|Sí) ;; *) echo "instalación cancelada" >&2; exit 1 ;; esac
    fi
    $GESTOR $paquetes
}

# ----- instalaciones previas con los nombres screenpad* -------------------------------

limpiar_nombres_viejos() {
    systemctl --user -M "$USUARIO@" disable --now screenpadd.service screenpad-launcher.service \
        2>/dev/null || true
    systemctl disable --now screenpad-numpad.socket screenpad-numpad.service 2>/dev/null || true
    rm -f /usr/local/bin/screenpadd /usr/local/bin/screenpadctl /usr/local/bin/screenpad-launcher \
          /usr/local/bin/screenpad-config /usr/local/bin/screenpad-numpad \
          /etc/systemd/user/screenpadd.service /etc/systemd/user/screenpad-launcher.service \
          /etc/systemd/system/screenpad-numpad.service /etc/systemd/system/screenpad-numpad.socket \
          /etc/udev/rules.d/70-screenpad.rules /etc/udev/hwdb.d/70-screenpad.hwdb \
          /etc/sudoers.d/screenpad /usr/local/share/applications/io.github.kan0p.ScreenPad.Config.desktop
    rm -rf /usr/local/share/screenpad
    # permisos anteriores a polkit
    rm -f /etc/sudoers.d/glasspad /etc/sysusers.d/glasspad.conf
    getent group glasspad > /dev/null && groupdel glasspad
    true
}

# ----- copia de archivos ----------------------------------------------------------------

con_rutas() { sed "s|@BINDIR@|$BINDIR|g" "$1"; }

copiar() {
    D=$DESTDIR
    install -Dm755 screenpad "$D$BINDIR/screenpad"
    install -Dm755 glasspadd "$D$BINDIR/glasspadd"
    install -Dm755 glasspad "$D$BINDIR/glasspad"
    ln -sf glasspad "$D$BINDIR/gpad"
    install -Dm755 glasspad-launcher "$D$BINDIR/glasspad-launcher"
    install -Dm755 glasspad-config "$D$BINDIR/glasspad-config"
    install -Dm755 glasspad-numpad "$D$BINDIR/glasspad-numpad"

    install -Dm644 edid/ux580-tsb-fixed.bin "$D$LIBDIR/screenpad/ux580-tsb-fixed.bin"
    for f in icons/*/*.svg; do install -Dm644 "$f" "$D$SHARE/glasspad/$f"; done
    install -Dm644 atajos.toml "$D$SHARE/glasspad/atajos.toml"
    install -Dm644 /dev/stdin "$D$SHARE/applications/io.github.kan0p.GlassPad.Config.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=GlassPad Configurator
Comment=Configuración de GlassPad y del ScreenPad
Exec=$BINDIR/glasspad-config
Icon=input-touchpad
Categories=Settings;HardwareSettings;
EOF

    for f in screenpad.service glasspad-numpad.service glasspad-numpad.socket; do
        con_rutas "systemd/$f" | install -Dm644 /dev/stdin "$D$SYSTEMD/system/$f"
    done
    for f in glasspadd.service glasspad-launcher.service; do
        con_rutas "systemd/$f" | install -Dm644 /dev/stdin "$D$SYSTEMD/user/$f"
    done
    printf 'acpi_call\ni2c-dev\n' | install -Dm644 /dev/stdin "$D$MODULOS/screenpad.conf"
    printf 'uinput\n' | install -Dm644 /dev/stdin "$D$MODULOS/glasspad.conf"

    install -Dm644 udev/70-glasspad.rules "$D$UDEV/rules.d/70-glasspad.rules"
    install -Dm644 udev/70-glasspad.hwdb "$D$UDEV/hwdb.d/70-glasspad.hwdb"
    con_rutas polkit/io.github.kan0p.glasspad.policy \
        | install -Dm644 /dev/stdin "$D$POLKIT/io.github.kan0p.glasspad.policy"
}

# habilitados en el paquete: el sistema al arrancar y la sesión de cada usuario
habilitar_en_paquete() {
    D=$DESTDIR$SYSTEMD
    install -d "$D/system/multi-user.target.wants" "$D/system/sockets.target.wants" \
        "$D/user/graphical-session.target.wants"
    ln -sf ../screenpad.service "$D/system/multi-user.target.wants/screenpad.service"
    ln -sf ../glasspad-numpad.service "$D/system/multi-user.target.wants/glasspad-numpad.service"
    ln -sf ../glasspad-numpad.socket "$D/system/sockets.target.wants/glasspad-numpad.socket"
    for f in glasspadd.service glasspad-launcher.service; do
        ln -sf "../$f" "$D/user/graphical-session.target.wants/$f"
    done
}

# ----- instalación manual: permisos, servicios y arranque -------------------------------

activar() {
    modprobe uinput 2>/dev/null || true
    systemd-hwdb update 2>/dev/null || udevadm hwdb --update
    udevadm control --reload
    udevadm trigger --action=change --subsystem-match=input

    primera=1
    systemctl is-enabled --quiet screenpad.service 2>/dev/null && primera=0
    systemctl daemon-reload
    systemctl enable screenpad.service glasspad-numpad.socket glasspad-numpad.service
    systemctl restart glasspad-numpad.socket glasspad-numpad.service
    # replug: el compositor solo relee el EDID si la salida se reconecta
    [ $primera = 1 ] && "$BINDIR/screenpad" replug

    if systemctl --user -M "$USUARIO@" daemon-reload 2>/dev/null; then
        systemctl --user -M "$USUARIO@" enable glasspadd.service glasspad-launcher.service
        systemctl --user -M "$USUARIO@" restart glasspadd.service glasspad-launcher.service
    else
        echo "activa los servicios de sesión con: systemctl --user enable --now glasspadd glasspad-launcher"
    fi
}

if [ $PAQUETE = 1 ]; then
    copiar
    habilitar_en_paquete
else
    revisar_dependencias
    limpiar_nombres_viejos
    copiar
    activar
    echo "Instalación completa. Fn+F6 cambia el modo del ScreenPad; 'glasspad' (o 'gpad') lo controla desde la terminal."
fi
