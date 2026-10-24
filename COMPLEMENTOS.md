# Complementos de GlassPad Launcher

Referencia para GlassPad 0.9.1 o posterior.

Un complemento es una página más del launcher, con su mosaico en el inicio y en *Todas las apps* (categoría GlassPad), igual que Calculadora o Temporizador. Se escribe en Python con GTK4 y vive fuera del código del launcher.

## Dónde van

Cada complemento es una carpeta con un archivo `complemento.py`:

```
~/.local/share/glasspad/complementos/<nombre>/complemento.py    # del usuario
/usr/share/glasspad/complementos/<nombre>/complemento.py        # del sistema (paquetes)
```

Si las dos tienen una carpeta con el mismo nombre, se usa la del usuario. El launcher los carga al arrancar; después de agregar o cambiar uno:

```sh
systemctl --user restart glasspad-launcher
```

Un complemento nuevo aparece solo en el inicio la primera vez. Si falla al cargar, se omite y el error queda en `journalctl --user -u glasspad-launcher`.

## complemento.py

```python
from gi.repository import Gtk

NOMBRE = "Hola"          # obligatorio: texto del mosaico
ICONO = "icono.svg"      # opcional: archivo en la carpeta o nombre de ícono del tema
EN_INICIO = True         # opcional: False para que no se agregue solo al inicio


def crear(api):
    etiqueta = Gtk.Label(label="Hola")
    return api.accion(Gtk.Button(child=etiqueta, vexpand=True),
                      lambda: etiqueta.set_label("¡Tocado!"))
```

`crear(api)` se llama una vez y devuelve el `Gtk.Widget` de la página. Sin `ICONO`, se busca `icono.svg` en la carpeta. Los mosaicos del launcher son SVG de 96×96 con esquinas de radio 24.

## Toques

El pad no es una pantalla táctil para GTK: el launcher lee los toques y los entrega solo a los widgets registrados. Un `Gtk.Button` con `clicked` funciona con el mouse, pero no con el dedo. Para el pad:

- `api.accion(widget, al_tocar, al_mantener=None)`: toque y toque largo. Devuelve el widget.
- `api.deslizable(widget, al_cambiar, al_soltar=None)`: barras que se arrastran; `al_cambiar(f)` recibe la posición horizontal del dedo, de 0 a 1.
- `api.tecla(al_tocar, texto=None, icono=None, clases=())`: botón con el estilo de las teclas de Number Key, ya registrado.
- Los `Gtk.ScrolledWindow` se desplazan solos al arrastrar en vertical.

Si se reemplazan widgets registrados, hay que quitarlos con `api.vaciar(contenedor)`, que también olvida sus acciones.

## Otras funciones

- `api.css(texto)`: agrega CSS. Conviene usar clases con el nombre del complemento como prefijo.
- `api.al_mostrar(funcion)`: `funcion(visible)` al entrar o salir de la página.
- `api.avisar(texto)`: aviso breve arriba del pad.
- `api.escribir(texto)` y `api.atajo("ctrl+shift+t")`: escriben en la ventana con foco (necesitan `wtype`).
- `api.abrir("org.gnome.Nautilus.desktop")`: abre una app.
- `api.inicio()`: vuelve al inicio.
- `api.carpeta`: ruta de la carpeta del complemento.

El código corre dentro del launcher: nada debe bloquear (`GLib.timeout_add` o `Gio` asíncrono en lugar de `time.sleep` o lecturas lentas). La pantalla mide 1920×1080 una vez rotada.

## Ejemplos

El tutorial paso a paso y complementos de ejemplo, como Dados, están en [glasspad-complementos](https://github.com/kan0p/glasspad-complementos).
