# Dados: complemento de ejemplo para GlassPad Launcher
import random

from gi.repository import GLib, Gtk

NOMBRE = "Dados"
ICONO = "icono.svg"
CARAS = "⚀⚁⚂⚃⚄⚅"


def crear(api):
    api.css("""
    .dados-cara { font-size: 260px; }
    .dados-total { font-size: 34px; opacity: 0.7; }
    """)
    dados = [Gtk.Label(label=CARAS[0], css_classes=["dados-cara"]) for _ in range(2)]
    total = Gtk.Label(label="Toca para tirar", css_classes=["dados-total"])
    giro = {"id": 0, "vueltas": 0}

    def mostrar_tirada():
        valores = [random.randint(1, 6) for _ in dados]
        for d, v in zip(dados, valores):
            d.set_label(CARAS[v - 1])
        return valores

    def paso():
        valores = mostrar_tirada()
        giro["vueltas"] -= 1
        if giro["vueltas"] > 0:
            return True
        giro["id"] = 0
        total.set_label(f"Total: {sum(valores)}")
        return False

    def tirar():
        if giro["id"]:
            return
        giro["vueltas"] = 8
        giro["id"] = GLib.timeout_add(60, paso)

    fila = Gtk.Box(spacing=80, halign=Gtk.Align.CENTER)
    for d in dados:
        fila.append(d)
    caja = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=30, valign=Gtk.Align.CENTER)
    caja.append(fila)
    caja.append(total)
    boton = Gtk.Button(child=caja, css_classes=["flat"], vexpand=True)
    api.al_mostrar(lambda visible: visible or total.set_label("Toca para tirar"))
    return api.accion(boton, tirar, lambda: api.escribir(total.get_label()))
