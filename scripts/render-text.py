#!/usr/bin/env python3
"""Render text lines to transparent PNGs with Pango.

Pango shapes every script (Arabic joining, Devanagari conjuncts, ...),
lays out right-to-left text and falls back to other fonts per glyph, none
of which Conky's own Xft text does.

usage: render-text.py OUTDIR TEXT FONT COLOR [TEXT FONT COLOR ...]

FONT is a Pango font description such as "Inter, Noto Sans CJK JP Bold 12",
COLOR is #RRGGBB. For each text one file name is printed (empty line for
empty text): text-<hash>-b<N>.png, where N is the baseline's distance from
the top of the image in pixels, with .rtl before .png when the text is
right-to-left. The image is as wide as the text's advance and as tall as
its ink, so tall fallback fonts do not push it into neighbouring lines.
Files are written to a temporary name and then renamed, so readers never
see a partial PNG. Existing files are reused.
"""
import hashlib
import os
import sys

import cairo
import gi

gi.require_version('Pango', '1.0')
gi.require_version('PangoCairo', '1.0')
from gi.repository import Pango, PangoCairo  # noqa: E402

DPI = 96  # Conky/Xft point sizes assume 96 DPI


def rgb(color):
    color = color.lstrip('#')
    try:
        return tuple(int(color[i:i + 2], 16) / 255 for i in (0, 2, 4))
    except ValueError:
        return (1.0, 1.0, 1.0)


def layout_for(ctx, text, font):
    layout = PangoCairo.create_layout(ctx)
    PangoCairo.context_set_resolution(layout.get_context(), DPI)
    layout.set_font_description(Pango.FontDescription.from_string(font))
    layout.set_text(text, -1)
    return layout


def render(outdir, text, font, color):
    if not text:
        return ''
    rtl = Pango.find_base_dir(text, -1) == Pango.Direction.RTL
    key = hashlib.md5('\0'.join((text, font, color)).encode()).hexdigest()[:16]
    prefix = 'text-%s-b' % key
    for existing in os.listdir(outdir):
        if existing.startswith(prefix) and existing.endswith('.png'):
            return existing

    probe = cairo.Context(cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1))
    probe_layout = layout_for(probe, text, font)
    ink, logical = probe_layout.get_pixel_extents()
    top = min(ink.y, logical.y + logical.height)
    width = max(1, logical.width)
    height = max(1, ink.y + ink.height - top)
    baseline = probe_layout.get_baseline() // Pango.SCALE - top
    name = '%s%d%s.png' % (prefix, baseline, '.rtl' if rtl else '')
    path = os.path.join(outdir, name)

    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    ctx = cairo.Context(surface)
    # Grayscale antialiasing: subpixel color fringes look wrong on a
    # transparent background.
    options = cairo.FontOptions()
    options.set_antialias(cairo.ANTIALIAS_GRAY)
    layout = layout_for(ctx, text, font)
    PangoCairo.context_set_font_options(layout.get_context(), options)
    layout.context_changed()
    ctx.set_source_rgb(*rgb(color))
    ctx.move_to(-logical.x, -top)
    PangoCairo.show_layout(ctx, layout)

    tmp = path + '.tmp'
    surface.write_to_png(tmp)
    os.replace(tmp, path)
    return name


def main(argv):
    if len(argv) < 2 or (len(argv) - 2) % 3:
        sys.exit(__doc__)
    outdir, specs = argv[1], argv[2:]
    for i in range(0, len(specs), 3):
        print(render(outdir, *specs[i:i + 3]))


if __name__ == '__main__':
    main(sys.argv)
