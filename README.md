# asus-screenpad-linux

Script para que el ScreenPad de la ZenBook Pro 15 UX580 (UX580GE/GD) funcione en Linux con el driver propietario de NVIDIA. Lo uso en Arch con COSMIC (Wayland), pero no depende del escritorio.

## Qué pasaba

Con Linux recién instalado, el ScreenPad funcionaba como touchpad y nada más: a veces se encendía la retroiluminación, pero nunca mostraba imagen. En el log aparecía esto:

```
failed to get EDID for HDMI-A-4
```

Revisando, encontré que el panel no está conectado al eDP ni a la Intel. Va a una salida HDMI de la GTX 1050 Ti a través de un puente Toshiba (en el EDID figura como `TSB`, `no-audio-HD`). Hay varios problemas encadenados:

- El panel arranca sin energía. Hasta que no se enciende por ASUS WMI (`DEVS 0x00050031`), la GPU ni lo ve.
- Encendido, el puente sí entrega un EDID por I2C (en mi caso `i2c-11`, dirección `0x50`), pero el checksum del bloque de extensión CTA está mal: trae `0x3e` y debería ser `0x6f`. El driver de NVIDIA descarta el EDID completo y marca la salida como desconectada.
- Mi primer intento fue forzar un EDID hecho a mano (2160x1080 y otras variantes), y lo único que conseguí fue una pantalla iluminada pero negra. El puente necesita el modo nativo (`1080x1920 @ 60.70 Hz`, 140 MHz, `-hsync -vsync`) enviado como HDMI, y eso solo pasa si el EDID tiene el bloque HDMI del original. Con DVI no funciona.
- Si no recibe una señal válida en unos segundos, el panel se apaga solo.

La solución fue usar el EDID real del puente con el checksum corregido.

## Cómo funciona

`screenpad.service` ejecuta `screenpad on` al arrancar. El script espera a que aparezca la tarjeta de nvidia-drm (al principio el servicio corría a los ~6 s de arrancar y fallaba porque todavía no existía), enciende el panel con `acpi_call` y busca la salida HDMI que marca hotplug. Después lee el EDID por I2C, recalcula los checksums y lo escribe en `debugfs .../edid_override`. Desde ese momento el compositor lo ve como un monitor normal de 1080x1920.

Si no puede leer el EDID, usa la última copia válida que guardó en `/var/lib/screenpad/edid.bin` y, si tampoco existe, la que viene en `edid/`. Si el servicio falla, systemd lo reintenta a los 5 s.

## Requisitos

- Driver `nvidia` con `nvidia-drm.modeset=1` (probado con 580.xx)
- `acpi_call`: `acpi_call-dkms` en Arch, `acpi-call-dkms` en Debian/Ubuntu, `akmod-acpi_call` en Fedora (RPM Fusion)
- `python3` para la lectura por I2C. Sin él funciona igual, pero con el EDID incluido.
- debugfs montado en `/sys/kernel/debug` (casi todas las distros lo montan por defecto)

## Instalación

```sh
git clone https://github.com/kan0p/asus-screenpad-linux
cd asus-screenpad-linux
sudo ./install.sh
```

Falta acomodar la pantalla. El panel es vertical, así que hay que rotarlo 270° y ponerlo debajo de la pantalla principal. Yo lo hago así en COSMIC:

```sh
cosmic-randr mode HDMI-A-4 1080 1920 --transform rotate270 --pos-x 0 --pos-y 1080
```

En X11 sería algo así (los nombres de salida cambian, revísalos con `xrandr`):

```sh
xrandr --output HDMI-0 --mode 1080x1920 --rotate right --below eDP-1
```

Para quitarlo: `sudo ./uninstall.sh`.

## Comandos

```
screenpad on                 enciende el panel y carga el EDID (lo que corre al arrancar)
screenpad replug             igual, pero desconecta y reconecta la salida
screenpad off                quita el override y apaga el panel
screenpad status             estado WMI y salidas HDMI de la NVIDIA
screenpad dump-edid ARCHIVO  guarda el EDID ya corregido
```

Todos necesitan root. `replug` existe porque COSMIC se queda con el EDID anterior. Si el panel queda negro después de cambiar algo, suele bastar con eso.

Si la detección automática no encuentra el conector o el bus, se pueden fijar en `/etc/screenpad.conf`:

```sh
CONNECTOR=HDMI-A-4
I2C_BUS=11
EDID=/ruta/al/edid.bin
```

## Otros problemas que tuve

- **Touchpad muerto.** COSMIC dejó `input_touchpad_override` en `ForceDisable` cuando apareció el segundo monitor. Lo cambié a `None` en `~/.config/cosmic/com.system76.CosmicComp/v1/input_touchpad_override`.
- **Cursor invisible.** Por defecto el ScreenPad quedaba en 0,0, a la izquierda de la pantalla principal, y el cursor se iba ahí. Con la disposición de arriba se arregla.
- **No aparece después de reiniciar.** Revisa `journalctl -u screenpad`. Ahí queda registrado si no encontró la GPU o el EDID.

## Archivos

- `screenpad`: el script (sh, con un poco de Python para el I2C)
- `screenpad.service`: unidad de systemd
- `install.sh`, `uninstall.sh`
- `edid/ux580-tsb-original.bin`: el EDID tal como sale del puente, con el checksum malo
- `edid/ux580-tsb-fixed.bin`: el mismo, corregido

## Probado en

ZenBook Pro 15 UX580GE, Arch Linux (kernel 7.2), COSMIC 1.10 en Wayland, nvidia 580.178.

Si te funciona en otra configuración, avísame con un issue y lo agrego. El ScreenPad Plus de las Zenbook Duo tiene otro cableado, así que esto no aplica ahí.

La temporización 1080x1920 la saqué de [SinanAkkoyun/ScreenpadLinux](https://github.com/SinanAkkoyun/ScreenpadLinux).

## Licencia

MIT, ver [LICENSE](LICENSE).
