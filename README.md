# asus-screenpad-linux

Scripts para que el ScreenPad de la ZenBook Pro 15 UX580 (UX580GE/GD) funcione en Linux con el driver propietario de NVIDIA: encendido, modos con Fn+F6 y un launcher táctil al estilo de ScreenXpert. Lo uso en Arch con COSMIC (Wayland).

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
- Para los modos: `python-evdev` y `python-gobject`
- Para el launcher y su configuración: `gtk4`, `gtk4-layer-shell` y `libadwaita`

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

## Modos y Fn+F6

En Windows, Fn+F6 cambia el modo del ScreenPad. En Linux el kernel la entrega como `KEY_TOUCHPAD_TOGGLE` en *Asus WMI hotkeys*, y algunos escritorios (COSMIC, GNOME, KDE) la usan para apagar el touchpad por su cuenta. `install.sh` la cambia por `KEY_MACRO1` con una regla hwdb (`udev/70-screenpad.hwdb`), que ningún escritorio usa, y `screenpadd` la escucha directamente con evdev, así que funciona en cualquier compositor:

| Modo | Pantalla | Pad |
|---|---|---|
| `launcher` | el launcher | táctil |
| `monitor` | monitor extendido normal | touchpad |
| `dark` | brillo 0, negra | touchpad, gastando menos batería |
| `off` | apagada | bloqueado |

Cada pulsación pasa al siguiente modo y muestra un aviso. `launcher` se salta si el launcher no está corriendo. El orden se cambia en `~/.config/screenpad/config.toml`:

```toml
cycle = ["launcher", "monitor", "dark", "off"]
startup_mode = "last"    # modo al iniciar sesión: "last" (el último) o uno de los cuatro
off_blocks_pad = true    # en "off", bloquear también el pad
isolate_pointer = true   # en launcher y dark, que el cursor no pase al pad (solo COSMIC)
```

COSMIC no deja separar dos pantallas, así que con `isolate_pointer` el pad se mueve a la esquina inferior derecha de la pantalla principal en los modos `launcher` y `dark`, donde comparten solo 4 px de borde. En `monitor` vuelve a la posición que tenía.

Con `startup_mode = "off"` y `off_blocks_pad = false`, el panel arranca apagado y el pad funciona como touchpad: útil mientras se prueba algo que pueda colgar el escritorio.

`install.sh` agrega dos permisos para que esto funcione sin contraseña:

- una regla udev (`udev/70-screenpad.rules`) que da a la sesión acceso de lectura **solo** a las teclas ASUS y al touchpad del pad, no al teclado;
- una regla sudoers (`sudoers/screenpad`) que permite `screenpad on|replug|off|status|brightness` sin contraseña. `dump-edid` queda fuera, porque escribe archivos como root.

El brillo se maneja por WMI y no por `/sys/class/backlight`. En 0 apaga solo la retroiluminación: la salida sigue conectada y el touchpad sigue funcionando.

## Launcher

`screenpad-launcher` es la pantalla del modo `launcher`: hora y fecha, una cuadrícula de 4×2 con páginas y una barra con touchpad, inicio y Control Center. El nodo táctil del panel nunca emite, así que el launcher lee el pad con evdev, lo toma en exclusiva y traduce cada toque a la posición en pantalla. No depende del compositor.

- **Tocar** abre la app.
- **Mantener presionado** levanta el mosaico: se arrastra para reordenar, al borde para cambiar de página, y sobre la barra roja para quitarlo del inicio.
- **Deslizar de lado** cambia de página.
- **Todas las apps** lista todo lo instalado. Mantener presionada una app la agrega al inicio o la quita.
- **Cuatro dedos** (un toque corto) entran a un touchpad temporal: el fondo difuminado con la estela de los dedos y el pad libre para mover el cursor. Se vuelve con cuatro dedos o tras unos segundos sin tocar.

El botón de Control Center abre por ahora `screenpad-config` en la pantalla principal: el fondo (predeterminado, color o imagen), el difuminado del touchpad temporal y los segundos para volver. Escribe en `config.toml`, y el launcher aplica los cambios al instante:

```toml
background_mode = "default"   # "default", "color" o "image"
background_color = "#1b2433"
background = "~/Imágenes/fondo.jpg"
background_blur = 12          # px, solo en el touchpad temporal
touchpad_return = 4           # s sin tocar para volver al launcher; 0 = nunca
```

El orden del inicio se guarda en `~/.local/state/screenpad/inicio.json`.

cosmic-comp 1.10 desconecta a la aplicación que oculta o destruye una superficie layer-shell. Por eso el launcher nunca se oculta: fuera de su modo queda de 1×1 píxel, transparente, en la capa del fondo. Cuando la salida del pad desaparece (modo `off`, `replug`) el compositor la destruye igual; el servicio se reinicia solo y no crea la ventana hasta que la salida vuelve.

## Comandos

```
screenpad on                 enciende el panel y carga el EDID (lo que corre al arrancar)
screenpad replug [0-255]     igual, pero desconecta y reconecta la salida (con el brillo dado)
screenpad off                quita el override y apaga el panel
screenpad status             estado WMI y salidas HDMI de la NVIDIA
screenpad brightness [0-255] lee o fija el brillo
screenpad dump-edid ARCHIVO  guarda el EDID ya corregido
```

Todos necesitan root. `replug` existe porque COSMIC se queda con el EDID anterior. Si el panel queda negro después de cambiar algo, suele bastar con eso.

Si la detección automática no encuentra el conector o el bus, se pueden fijar en `/etc/screenpad.conf`:

```sh
CONNECTOR=HDMI-A-4
I2C_BUS=11
EDID=/ruta/al/edid.bin
```

Desde la sesión, sin root:

```
screenpadctl status          modo, brillo y ciclo actuales
screenpadctl next            lo mismo que Fn+F6
screenpadctl mode dark       launcher, monitor, dark u off
screenpadctl brightness 180  brillo de los modos encendidos (1-255)
```

## Otros problemas que tuve

- **Touchpad muerto.** COSMIC dejó `input_touchpad_override` en `ForceDisable` cuando apareció el segundo monitor. Lo cambié a `None` en `~/.config/cosmic/com.system76.CosmicComp/v1/input_touchpad_override`.
- **Cursor invisible.** Por defecto el ScreenPad quedaba en 0,0, a la izquierda de la pantalla principal, y el cursor se iba ahí. Con la disposición de arriba se arregla.
- **No aparece después de reiniciar.** Revisa `journalctl -u screenpad`. Ahí queda registrado si no encontró la GPU o el EDID.
- **Fn+F6 no hace nada.** Revisa `journalctl --user -u screenpadd`. Si dice "sin acceso", la regla udev no se aplicó: cierra sesión y vuelve a entrar.
- **El launcher no aparece.** Revisa `journalctl --user -u screenpad-launcher`. Busca la salida en `/var/lib/screenpad/conector`; si no la encuentra, se puede fijar con `output = "HDMI-A-4"` en `config.toml`.

## Archivos

- `screenpad`: encendido, EDID y brillo (sh, con un poco de Python para el I2C)
- `screenpadd`: servicio de sesión con los modos y Fn+F6 (Python, `python-evdev`, `python-gobject`)
- `screenpadctl`: control de `screenpadd` desde la terminal
- `screenpad-launcher`: el launcher (GTK4 y gtk4-layer-shell)
- `screenpad-config`: la configuración en la pantalla principal (libadwaita)
- `icons/`: mosaicos e íconos de interfaz del launcher
- `systemd/`: `screenpad.service` (sistema), `screenpadd.service` y `screenpad-launcher.service` (sesión)
- `udev/`, `sudoers/`: permisos y el cambio de Fn+F6 a `KEY_MACRO1`
- `install.sh`, `uninstall.sh`
- `edid/ux580-tsb-original.bin`: el EDID tal como sale del puente, con el checksum malo
- `edid/ux580-tsb-fixed.bin`: el mismo, corregido

## Probado en

ZenBook Pro 15 UX580GE, Arch Linux (kernel 7.2), COSMIC 1.10 en Wayland, nvidia 580.178.

Si te funciona en otra configuración, avísame con un issue y lo agrego. El ScreenPad Plus de las Zenbook Duo tiene otro cableado, así que esto no aplica ahí.

La temporización 1080x1920 la saqué de [SinanAkkoyun/ScreenpadLinux](https://github.com/SinanAkkoyun/ScreenpadLinux).

## Licencia

GPL-3.0-or-later, ver [LICENSE](LICENSE).
