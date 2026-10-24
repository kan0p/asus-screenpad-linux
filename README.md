# GlassPad

**GlassPad** hace que el ScreenPad de la ZenBook Pro 15 UX580 (UX580GE/GD) funcione en Linux con el driver propietario de NVIDIA: encendido, modos con Fn+F6 y **GlassPad Launcher**, un launcher táctil al estilo de ScreenXpert. Lo uso en Arch con COSMIC (Wayland).

GlassPad es un proyecto independiente, sin relación con ASUS. El repositorio se llama `asus-screenpad-linux` para que sea fácil de encontrar.

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
- Para Quick Key: `wtype` (usa el teclado virtual de Wayland; no funciona en GNOME)
- Para la música: `playerctl` (la biblioteca con su typelib) y `wpctl` de WirePlumber para el volumen

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

En Windows, Fn+F6 cambia el modo del ScreenPad. En Linux el kernel la entrega como `KEY_TOUCHPAD_TOGGLE` en *Asus WMI hotkeys*, y algunos escritorios (COSMIC, GNOME, KDE) la usan para apagar el touchpad por su cuenta. `install.sh` la cambia por `KEY_MACRO1` con una regla hwdb (`udev/70-glasspad.hwdb`), que ningún escritorio usa, y `glasspadd` la escucha directamente con evdev, así que funciona en cualquier compositor:

| Modo | Pantalla | Pad |
|---|---|---|
| `launcher` | el launcher | táctil |
| `monitor` | monitor extendido normal | touchpad |
| `dark` | brillo 0, negra | touchpad, gastando menos batería |
| `off` | apagada | bloqueado |

Cada pulsación pasa al siguiente modo y muestra un aviso. `launcher` se salta si el launcher no está corriendo. El orden se cambia en `~/.config/glasspad/config.toml`:

```toml
cycle = ["launcher", "monitor", "dark", "off"]
startup_mode = "last"    # modo al iniciar sesión: "last" (el último) o uno de los cuatro
off_blocks_pad = true    # en "off", bloquear también el pad
isolate_pointer = true   # en launcher y dark, que el cursor no pase al pad (solo COSMIC)
```

COSMIC no deja separar dos pantallas, así que con `isolate_pointer` el pad se mueve a la esquina inferior derecha de la pantalla principal en los modos `launcher` y `dark`, donde comparten solo 4 px de borde. En `monitor` vuelve a la posición que tenía.

Con `startup_mode = "off"` y `off_blocks_pad = false`, el panel arranca apagado y el pad funciona como touchpad: útil mientras se prueba algo que pueda colgar el escritorio.

`install.sh` agrega dos permisos para que esto funcione sin contraseña:

- una regla udev (`udev/70-glasspad.rules`) que da a la sesión acceso de lectura **solo** a las teclas ASUS y al touchpad del pad, no al teclado;
- una regla sudoers (`sudoers/glasspad`) que permite `screenpad on|replug|off|status|brightness` sin contraseña. `dump-edid` queda fuera, porque escribe archivos como root.

El brillo se maneja por WMI y no por `/sys/class/backlight`. En 0 apaga solo la retroiluminación: la salida sigue conectada y el touchpad sigue funcionando.

## GlassPad Launcher

`glasspad-launcher` es la pantalla del modo `launcher`: hora y fecha, una cuadrícula de 4×2 con páginas y una barra con touchpad, todas las apps (o inicio, fuera del inicio), ventanas, música y Control Center. El nodo táctil del panel nunca emite, así que el launcher lee el pad con evdev, lo toma en exclusiva y traduce cada toque a la posición en pantalla. No depende del compositor.

- **Tocar** abre la app.
- **Mantener presionado** levanta el mosaico: se arrastra para reordenar, al borde para cambiar de página, y sobre la barra roja para quitarlo del inicio.
- **Deslizar de lado** cambia de página.
- **Todas las apps**, el botón central de la barra, lista las utilidades y todo lo instalado, con filtros por categoría. Mantener presionado un elemento lo agrega al inicio o lo quita.
- **Cuatro dedos** (un toque corto) entran a un touchpad temporal: el fondo difuminado con la estela de los dedos y el pad libre para mover el cursor. Se vuelve con cuatro dedos o tras unos segundos sin tocar.

### Control Center y utilidades

El **Control Center** sube desde la barra: brillo del pad (se arrastra con el dedo), Number Key, Quick Key, touchpad temporal, bloquear la sesión, apagar el pad y ajustes.

- **Number Key**: teclado numérico que escribe en la app activa.
- **Quick Key**: hasta 16 atajos que se mandan a la app activa con `wtype`. Cambian según la app activa: hay perfiles para navegadores, terminales, editores de código y oficina (en `atajos.toml`), y cada uno puede crear el suyo para cualquier app desde el Configurator.
- **Calculadora**: `%` es porcentaje; **Insertar** escribe el resultado en la app activa.
- **Calendario**: el mes con el día de hoy; se desliza de lado para cambiar de mes.
- **Temporizador y cronómetro**: temporizador con presets y ajuste de a 10 s, alarma y aviso al terminar; cronómetro con vueltas.
- **Monitor**: CPU y temperatura, memoria, GPU NVIDIA, consumo de la batería, red y disco, con gráfico de los últimos 60 s. Solo mide mientras está abierto.
- **Zoom**: acercar, alejar y volver a normal con el zoom de COSMIC, o pellizcando con dos dedos sobre el pad.
- **Portapapeles**: historial de los últimos 25 textos e imágenes copiados (imágenes de hasta 10 MB), con anclar y borrar. Tocar un elemento lo pega en la app activa.
- **Ventanas**: las ventanas abiertas, agrupadas por pantalla. Tocar una la trae al frente; cada una se puede minimizar, cerrar o mover entre la pantalla principal y el pad.

Son mosaicos que se pueden poner en el inicio; al instalar (o al llegar una nueva) aparecen solos, salvo Ventanas, que está en la barra.

Las ventanas que están en el pad pasan solas a la pantalla principal al salir del modo `monitor` (launcher, dark u off) y regresan al volver. Ventanas usa los protocolos de COSMIC (`ext_foreign_toplevel_list_v1`, `zcosmic_toplevel_info_v1`, `zcosmic_toplevel_manager_v1` y `ext_workspace_manager_v1`) con un cliente Wayland propio, sin dependencias.

### Música

Cuando una app reproduce algo (YouTube en el navegador, Spotify, VLC…), la barra muestra un ecualizador animado con el título. Lo detecta por MPRIS, igual que el panel del escritorio. Al tocarlo se abre una ventana con la carátula, el progreso (se arrastra para adelantar), anterior, pausa y siguiente, y el volumen general del sistema. Aleatorio, repetir e "Ir a la app" aparecen solo si la app los admite. Con varias apps a la vez, arriba se elige cuál controlar. El botón se oculta si el reproductor se detiene o tras 10 minutos en pausa.

### Portapapeles

`glasspadd` guarda el historial con el protocolo `ext_data_control_v1` de Wayland: lo copiado queda solo en memoria (las imágenes, en `/run/user/…`, privado del usuario) y lo anclado se guarda en `~/.local/state/glasspad/`. Se ignora lo que los gestores de contraseñas marcan como secreto. Si la app que copió algo se cierra, GlassPad vuelve a poner lo último copiado en el portapapeles.

Con **Super+V** (se registra en COSMIC desde el Configurator) el historial aparece en el pad si está en modo `launcher`, o en un panel abajo a la derecha de la pantalla principal en los demás modos: flechas, Enter para pegar y Escape para cerrar. En las terminales pega con Ctrl+Shift+V. `glasspad clipboard` hace lo mismo desde la terminal.

### Teclado numérico virtual

Algunas apps (Word online, por ejemplo) ignoran las teclas del teclado virtual de Wayland. Por eso Number Key, el botón Insertar y el Zoom usan `glasspad-numpad`, un servicio de sistema que crea con `uinput` un teclado que **solo tiene las teclas del teclado numérico** (0–9, `/ * - +`, decimal, Enter y Borrar) y **dos combinaciones fijas**: Super+punto y Super+coma, el zoom de COSMIC. Las apps lo ven como un teclado numérico USB.

- Recibe los pedidos por `/run/glasspad-numpad.sock`, que systemd crea con permisos solo para el usuario que instaló.
- Descarta cualquier otra tecla o combinación, así que no puede escribir texto ni ejecutar otros atajos.
- Corre sin red, con el sistema de archivos en solo lectura y con acceso únicamente a `/dev/uinput` y a los dispositivos de entrada.
- Con Bloq Num apagado lo enciende solo durante cada envío. La tecla decimal escribe lo que defina la distribución de teclado (punto en la latinoamericana).

Si el servicio no está, el launcher usa `wtype`.

### Configuración

**GlassPad Configurator** (`glasspad-config`; Ajustes en el Control Center, o "GlassPad Configurator" en el menú de apps) se abre en la pantalla principal y tiene cuatro pestañas:

- **Apariencia**: fondo, difuminado y cuánto oscurecerlo.
- **ScreenPad**: modos de Fn+F6, modo al iniciar sesión, bloquear el pad en apagado, alejar el cursor, atenuar, modo con batería y touchpad temporal.
- **Quick Key**: elegir el perfil (generales o de una app) y agregar, editar, reordenar, quitar o restablecer atajos, grabando la combinación con el teclado.
- **Portapapeles**: activar el historial, registrar Super+V en COSMIC y borrar el historial.

**Atenuar** baja el brillo del pad (al 5 % por omisión) sin apagarlo, tras unos minutos sin tocarlo o mientras la ventana activa de la pantalla principal está en pantalla completa; al tocar el pad vuelve. **Con batería** puede pasar a otro modo y volver al anterior al enchufar. La parte superior del launcher muestra la batería y su porcentaje.

Todo se guarda en `config.toml` y se aplica al instante:

```toml
background_mode = "default"   # "default", "color" o "image"
background_color = "#1b2433"
background = "~/Imágenes/fondo.jpg"
background_blur = 12          # px, solo en el touchpad temporal
background_dim = 0            # % de negro sobre el fondo
touchpad_return = 4           # s sin tocar para volver al launcher; 0 = nunca
quick_keys = [["Copiar", "edit-copy-symbolic", "ctrl+c"], ["Captura", "applets-screenshooter-symbolic", "Print"]]
idle_dim = true               # atenuar tras idle_dim_minutes sin tocar el pad
idle_dim_minutes = 2
fullscreen_dim = true         # atenuar con pantalla completa en la principal
dim_level = 5                 # % del brillo máximo
battery_mode = ""             # modo al usar batería; "" = no cambiar
clipboard_history = true      # historial del portapapeles
```

El orden del inicio se guarda en `~/.local/state/glasspad/inicio.json`. Al instalar, el inicio trae las utilidades de GlassPad; las apps las agrega cada uno.

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

Desde la sesión, sin root, con `glasspad` o su alias `gpad`:

```
glasspad status          modo, brillo y ciclo actuales
glasspad next            lo mismo que Fn+F6
glasspad mode dark       launcher, monitor, dark u off
glasspad brightness 180  brillo de los modos encendidos (1-255)
glasspad clipboard       muestra el historial del portapapeles (lo que hace Super+V)
```

## Otros problemas que tuve

- **Touchpad muerto.** COSMIC dejó `input_touchpad_override` en `ForceDisable` cuando apareció el segundo monitor. Lo cambié a `None` en `~/.config/cosmic/com.system76.CosmicComp/v1/input_touchpad_override`.
- **Cursor invisible.** Por defecto el ScreenPad quedaba en 0,0, a la izquierda de la pantalla principal, y el cursor se iba ahí. Con la disposición de arriba se arregla.
- **No aparece después de reiniciar.** Revisa `journalctl -u screenpad`. Ahí queda registrado si no encontró la GPU o el EDID.
- **Fn+F6 no hace nada.** Revisa `journalctl --user -u glasspadd`. Si dice "sin acceso", la regla udev no se aplicó: cierra sesión y vuelve a entrar.
- **El launcher no aparece.** Revisa `journalctl --user -u glasspad-launcher`. Busca la salida en `/var/lib/screenpad/conector`; si no la encuentra, se puede fijar con `output = "HDMI-A-4"` en `config.toml`.

## Archivos

- `screenpad`: encendido, EDID y brillo (sh, con un poco de Python para el I2C)
- `glasspadd`: servicio de sesión con los modos y Fn+F6 (Python, `python-evdev`, `python-gobject`)
- `glasspad` (alias `gpad`): control de `glasspadd` desde la terminal
- `glasspad-launcher`: GlassPad Launcher (GTK4 y gtk4-layer-shell)
- `glasspad-config`: GlassPad Configurator, en la pantalla principal (libadwaita)
- `glasspad-numpad`: teclado numérico virtual de Number Key (root, `python-evdev`)
- `icons/`: mosaicos e íconos de interfaz del launcher
- `atajos.toml`: perfiles de Quick Key por tipo de app
- `systemd/`: `screenpad.service` y `glasspad-numpad.socket`/`.service` (sistema), `glasspadd.service` y `glasspad-launcher.service` (sesión)
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
