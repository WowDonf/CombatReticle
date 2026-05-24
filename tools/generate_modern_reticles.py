#!/usr/bin/env python3
# Generates the 64x64 RGBA TGA textures for reticle slots 21-30: a
# modern chevron set (singles, triples, converging pairs) plus a skull
# and shamrock icon. Sharp polygonal silhouettes with subtle axial
# brightness gradients where useful, and no hard black outline so the
# in-game color picker tints them cleanly. Pure stdlib (no Pillow).
#
# Re-run after editing any shape:
#     python3 tools/generate_modern_reticles.py

import math
import os
import sys

W, H = 64, 64
AA_PX = 1.0
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Textures")


# ---------------------------------------------------------------------------
# TGA writer (32bpp BGRA, descriptor 0x08 = bottom-up, 8-bit alpha)
# ---------------------------------------------------------------------------
def write_tga(path, rows_top_down):
    header = bytes([
        0, 0, 2, 0, 0, 0, 0, 0,
        0, 0, 0, 0,
        W & 0xff, (W >> 8) & 0xff,
        H & 0xff, (H >> 8) & 0xff,
        32, 0x08,
    ])
    body = bytearray()
    for y in range(H - 1, -1, -1):
        for x in range(W):
            r, g, b, a = rows_top_down[y][x]
            body.append(b); body.append(g); body.append(r); body.append(a)
    with open(path, "wb") as f:
        f.write(header)
        f.write(bytes(body))


# ---------------------------------------------------------------------------
# Polygon SDF (Inigo Quilez) - negative inside.
# ---------------------------------------------------------------------------
def sdf_polygon(p, vs):
    px, py = p
    n = len(vs)
    d = (px - vs[0][0]) ** 2 + (py - vs[0][1]) ** 2
    s = 1.0
    j = n - 1
    for i in range(n):
        ex = vs[j][0] - vs[i][0]
        ey = vs[j][1] - vs[i][1]
        wx = px - vs[i][0]
        wy = py - vs[i][1]
        sq = ex * ex + ey * ey
        t = 0.0 if sq == 0 else max(0.0, min(1.0, (ex * wx + ey * wy) / sq))
        bx = wx - ex * t
        by = wy - ey * t
        ds = bx * bx + by * by
        if ds < d:
            d = ds
        c1 = py >= vs[i][1]
        c2 = py < vs[j][1]
        c3 = ex * wy > ey * wx
        if (c1 and c2 and c3) or ((not c1) and (not c2) and (not c3)):
            s = -s
        j = i
    return s * math.sqrt(d)


# ---------------------------------------------------------------------------
# SDF helpers for non-polygon shapes (skull, shamrock).
# ---------------------------------------------------------------------------
def sdf_circle(p, c, r):
    return math.hypot(p[0] - c[0], p[1] - c[1]) - r


def sdf_rounded_box(p, c, half_size, r):
    dx = abs(p[0] - c[0]) - half_size[0] + r
    dy = abs(p[1] - c[1]) - half_size[1] + r
    ox = max(dx, 0.0)
    oy = max(dy, 0.0)
    return math.hypot(ox, oy) + min(max(dx, dy), 0.0) - r


# ---------------------------------------------------------------------------
# Single-SDF renderer (used by shapes built from constructive solid
# geometry - union/subtract via min/-max).
# ---------------------------------------------------------------------------
def render_sdf(sdf_fn, fill_fn=None):
    if fill_fn is None:
        fill_fn = fill_uniform(1.0)
    rows = [[(0, 0, 0, 0)] * W for _ in range(H)]
    aa = AA_PX
    for y in range(H):
        for x in range(W):
            p = (x + 0.5, y + 0.5)
            d = sdf_fn(p)
            if d <= 0:
                v = max(0, min(255, int(fill_fn(p) * 255 + 0.5)))
                rows[y][x] = (v, v, v, 255)
            elif d <= aa:
                v = max(0, min(255, int(fill_fn(p) * 255 + 0.5)))
                a = int(255 * (1 - d / aa))
                rows[y][x] = (v, v, v, a)
    return rows


# ---------------------------------------------------------------------------
# Sharp solid chevron polygon (6 verts, flat-cut back).
#   tip:        position of the V's pointed tip
#   direction:  unit vector the chevron points toward (forward)
#   half_width: half the width at the back (perpendicular to direction)
#   depth:      distance along direction from back to tip
#   thickness:  perpendicular arm thickness
# Vertices wind: outer-left, outer-tip, outer-right, inner-right (back),
# inner-tip, inner-left (back).
# ---------------------------------------------------------------------------
def chevron(tip, direction, half_width, depth, thickness):
    tx, ty = tip
    dx, dy = direction
    sx, sy = dy, -dx                       # side perpendicular ("right of forward")
    bx = tx - dx * depth                   # back center
    by = ty - dy * depth
    L = math.hypot(half_width, depth)      # arm length
    off_axial = thickness * L / half_width # how far inner tip retreats from outer tip
    off_back  = thickness * L / depth      # how far inner back corner shifts toward axis

    outer_left  = (bx - sx * half_width,           by - sy * half_width)
    outer_tip   = (tx, ty)
    outer_right = (bx + sx * half_width,           by + sy * half_width)
    inner_right = (outer_right[0] - sx * off_back, outer_right[1] - sy * off_back)
    inner_tip   = (tx - dx * off_axial,            ty - dy * off_axial)
    inner_left  = (outer_left[0]  + sx * off_back, outer_left[1]  + sy * off_back)
    return [outer_left, outer_tip, outer_right, inner_right, inner_tip, inner_left]


# ---------------------------------------------------------------------------
# Fill functions (return brightness 0..1 for a sampled pixel).
# Greyscale only - so SetVertexColor tinting in the addon preserves the
# gradient regardless of which color the user picks.
# ---------------------------------------------------------------------------
def fill_uniform(value):
    return lambda p: value


def fill_axial(tip, direction, depth, near=0.60, far=1.00):
    """Brightness from `near` at the tip to `far` at full depth back."""
    nx, ny = -direction[0], -direction[1]
    tx, ty = tip
    def f(p):
        rel = (p[0] - tx) * nx + (p[1] - ty) * ny
        t = rel / depth
        if t < 0:
            t = 0
        elif t > 1:
            t = 1
        return near + (far - near) * t
    return f


# ---------------------------------------------------------------------------
# Renderer. parts = [(polygon_vertices, fill_fn), ...] - each part
# contributes its own interior fill; the union is what's drawn.
# ---------------------------------------------------------------------------
def render(parts):
    rows = [[(0, 0, 0, 0)] * W for _ in range(H)]
    aa = AA_PX
    for y in range(H):
        for x in range(W):
            p = (x + 0.5, y + 0.5)
            best_d = float("inf")
            best_fill = None
            for poly, fill in parts:
                d = sdf_polygon(p, poly)
                if d < best_d:
                    best_d = d
                    best_fill = fill
            if best_d <= 0:
                v = max(0, min(255, int(best_fill(p) * 255 + 0.5)))
                rows[y][x] = (v, v, v, 255)
            elif best_d <= aa:
                v = max(0, min(255, int(best_fill(p) * 255 + 0.5)))
                a = int(255 * (1 - best_d / aa))
                rows[y][x] = (v, v, v, a)
    return rows


# ===========================================================================
# Designs (slots 21-30)
# ===========================================================================
def big_down_chevron():
    # Wide stubby V pointing down at the player. Tip 2px above image
    # center so the character stays visible through the gap below.
    tip, dir_ = (32, 30), (0, 1)
    poly = chevron(tip, dir_, half_width=22, depth=22, thickness=8)
    return render([(poly, fill_axial(tip, dir_, depth=22, near=0.62, far=1.00))])


def big_up_chevron():
    tip, dir_ = (32, 34), (0, -1)
    poly = chevron(tip, dir_, half_width=22, depth=22, thickness=8)
    return render([(poly, fill_axial(tip, dir_, depth=22, near=0.62, far=1.00))])


def down_triple_chevron():
    # Three sharp V chevrons stacked above the player. The leading
    # chevron (closest to the character) is darkest; the trailing
    # chevron (farthest) is brightest - same brightness gradient as the
    # reference triple-arrow image.
    parts = []
    configs = [
        ((32, 28), 6, 17, 3, 0.55),  # leading
        ((32, 19), 6, 17, 3, 0.78),
        ((32, 10), 6, 17, 3, 1.00),  # trailing
    ]
    for tip, depth, hw, t, b in configs:
        parts.append((chevron(tip, (0, 1), hw, depth, t), fill_uniform(b)))
    return render(parts)


def up_triple_chevron():
    parts = []
    configs = [
        ((32, 36), 6, 17, 3, 0.55),
        ((32, 45), 6, 17, 3, 0.78),
        ((32, 54), 6, 17, 3, 1.00),
    ]
    for tip, depth, hw, t, b in configs:
        parts.append((chevron(tip, (0, -1), hw, depth, t), fill_uniform(b)))
    return render(parts)


def horizontal_pair():
    # A big chevron on the left pointing right + a big chevron on the
    # right pointing left, both pointing at the player.
    depth, hw, t = 14, 18, 6
    parts = []
    for tip, dir_ in [((24, 32), (1, 0)), ((40, 32), (-1, 0))]:
        parts.append((chevron(tip, dir_, hw, depth, t),
                      fill_axial(tip, dir_, depth, near=0.55, far=1.00)))
    return render(parts)


def triple_right_chevron():
    # Mirror of the triple_down stack, rotated 90°. Three chevrons on
    # the left side all pointing right at the player. Leading (closest
    # to center) is darkest; trailing chevrons grow brighter going left
    # - same gradient as the reference orange triple-arrow.
    parts = []
    configs = [
        ((26, 32), 6, 17, 3, 0.55),   # leading - closest to center
        ((17, 32), 6, 17, 3, 0.78),
        (( 8, 32), 6, 17, 3, 1.00),   # trailing - farthest from center
    ]
    for tip, depth, hw, t, b in configs:
        parts.append((chevron(tip, (1, 0), hw, depth, t), fill_uniform(b)))
    return render(parts)


def triple_left_chevron():
    parts = []
    configs = [
        ((38, 32), 6, 17, 3, 0.55),
        ((47, 32), 6, 17, 3, 0.78),
        ((56, 32), 6, 17, 3, 1.00),
    ]
    for tip, depth, hw, t, b in configs:
        parts.append((chevron(tip, (-1, 0), hw, depth, t), fill_uniform(b)))
    return render(parts)


def horizontal_converging_triple():
    # Three chevrons from each side converging on the player. Each side
    # has its own gradient - leading (closest to center) darkest,
    # trailing brightest - so the eye reads two arrival vectors.
    parts = []
    right_configs = [
        ((26, 32), 6, 12, 3, 0.55),
        ((18, 32), 6, 12, 3, 0.78),
        ((10, 32), 6, 12, 3, 1.00),
    ]
    left_configs = [
        ((38, 32), 6, 12, 3, 0.55),
        ((46, 32), 6, 12, 3, 0.78),
        ((54, 32), 6, 12, 3, 1.00),
    ]
    for tip, depth, hw, t, b in right_configs:
        parts.append((chevron(tip, (1, 0), hw, depth, t), fill_uniform(b)))
    for tip, depth, hw, t, b in left_configs:
        parts.append((chevron(tip, (-1, 0), hw, depth, t), fill_uniform(b)))
    return render(parts)


def skull():
    # Iconic skull silhouette: cranium circle + rounded-box jaw, with the
    # eye sockets, nose triangle, and mouth gap subtracted so they show
    # through as transparent holes.
    def sdf(p):
        cranium = sdf_circle(p, (32, 25), 16)
        jaw     = sdf_rounded_box(p, (32, 44), (10, 8), 4)
        body    = min(cranium, jaw)
        eye_l   = sdf_circle(p, (25, 26), 5)
        eye_r   = sdf_circle(p, (39, 26), 5)
        # Upside-down triangular nose hole - apex up toward the eyes.
        nose    = sdf_polygon(p, [(32, 30), (29, 37), (35, 37)])
        # Mouth: a thin horizontal slit through the jaw.
        mouth   = sdf_rounded_box(p, (32, 47), (6, 0.9), 0.7)
        d = body
        d = max(d, -eye_l)
        d = max(d, -eye_r)
        d = max(d, -nose)
        d = max(d, -mouth)
        return d
    return render_sdf(sdf)


def shamrock():
    # Three distinct circular leaves arranged 120° around a small
    # connecting hub, with a stem below. Spacing leaves the leaves
    # individually readable rather than merging into one blob.
    def sdf(p):
        leaf_r = 9
        top    = sdf_circle(p, (32, 16), leaf_r)
        botL   = sdf_circle(p, (22, 36), leaf_r)
        botR   = sdf_circle(p, (42, 36), leaf_r)
        leaves = min(top, botL, botR)
        hub    = sdf_circle(p, (32, 28), 6)
        stem   = sdf_rounded_box(p, (32, 50), (1.5, 7), 1.2)
        return min(leaves, hub, stem)
    return render_sdf(sdf)


def sharp_down_chevron():
    # Long, narrow spike variant. Steeper arm angle than big_down_chevron
    # for a more aggressive silhouette.
    tip, dir_ = (32, 30), (0, 1)
    poly = chevron(tip, dir_, half_width=10, depth=24, thickness=5)
    return render([(poly, fill_axial(tip, dir_, depth=24, near=0.55, far=1.00))])


def sharp_up_chevron():
    tip, dir_ = (32, 34), (0, -1)
    poly = chevron(tip, dir_, half_width=10, depth=24, thickness=5)
    return render([(poly, fill_axial(tip, dir_, depth=24, near=0.55, far=1.00))])


# ===========================================================================
# Driver. Filenames describe the actual visual; the Lua side references
# the same paths.
# ===========================================================================
DESIGNS = [
    ("reticle_21_down_chevron.tga",         big_down_chevron),
    ("reticle_22_up_chevron.tga",           big_up_chevron),
    ("reticle_23_triple_down_chevrons.tga", down_triple_chevron),
    ("reticle_24_triple_up_chevrons.tga",   up_triple_chevron),
    ("reticle_25_skull.tga",                skull),
    ("reticle_26_horizontal_pair.tga",      horizontal_pair),
    ("reticle_27_shamrock.tga",             shamrock),
    ("reticle_28_converging_triple.tga",    horizontal_converging_triple),
    ("reticle_29_sharp_down_chevron.tga",   sharp_down_chevron),
    ("reticle_30_sharp_up_chevron.tga",     sharp_up_chevron),
]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for fname, fn in DESIGNS:
        path = os.path.join(OUT_DIR, fname)
        sys.stdout.write(f"rendering {fname} ... ")
        sys.stdout.flush()
        write_tga(path, fn())
        sys.stdout.write("ok\n")


if __name__ == "__main__":
    main()
