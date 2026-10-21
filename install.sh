#!/bin/sh
# copia script, EDID de respaldo y servicio; deja todo habilitado
set -e
[ "$(id -u)" = 0 ] || { echo "ejecuta como root: sudo ./install.sh" >&2; exit 1; }
cd "$(dirname "$0")"
install -Dm755 screenpad /usr/local/bin/screenpad
install -Dm644 edid/ux580-tsb-fixed.bin /usr/local/lib/screenpad/ux580-tsb-fixed.bin
install -Dm644 screenpad.service /etc/systemd/system/screenpad.service
printf 'acpi_call\ni2c-dev\n' > /etc/modules-load.d/screenpad.conf
systemctl daemon-reload
systemctl enable screenpad.service
/usr/local/bin/screenpad on
echo "Instalación completa. El ScreenPad se activará en cada arranque."
