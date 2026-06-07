#!/usr/bin/env python3
# Generates the 64x64 RGBA TGA textures for reticle slots 21-40: a
# modern chevron set (singles, triples, converging pairs), a skull and
# shamrock icon, and two sets of fancy horizontal markers (feathered,
# swept, triangle-stack, hollow, harpoon, bold and broadhead arrows).
# Sharp polygonal silhouettes with subtle axial
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
# Fancy horizontal markers (slots 31-34). Each is a left+right pair of
# ornate arrows pointing inward at the player. Built from the same
# greyscale polygon/SDF primitives so the color picker tints them cleanly.
# ===========================================================================
def _norm(vx, vy):
    m = math.hypot(vx, vy) or 1.0
    return (vx / m, vy / m)


def rect(center, direction, half_len, half_w):
    """Oriented rectangle as a 4-vert polygon: `direction` is the long axis."""
    cx, cy = center
    dx, dy = direction
    sx, sy = dy, -dx
    return [
        (cx - dx * half_len - sx * half_w, cy - dy * half_len - sy * half_w),
        (cx + dx * half_len - sx * half_w, cy + dy * half_len - sy * half_w),
        (cx + dx * half_len + sx * half_w, cy + dy * half_len + sy * half_w),
        (cx - dx * half_len + sx * half_w, cy - dy * half_len + sy * half_w),
    ]


def taper_arm(tip, arm_dir, length, w_near, w_far):
    """Trapezoid that is wide at `tip` and tapers to a point going outward -
    used for sleek swept wingtips."""
    dx, dy = arm_dir
    sx, sy = dy, -dx
    far = (tip[0] + dx * length, tip[1] + dy * length)
    return [
        (tip[0] - sx * w_near, tip[1] - sy * w_near),
        (far[0] - sx * w_far,  far[1] - sy * w_far),
        (far[0] + sx * w_far,  far[1] + sy * w_far),
        (tip[0] + sx * w_near, tip[1] + sy * w_near),
    ]


def tri(tip, direction, depth, half_w):
    """Solid triangular arrowhead: tip forward, flat base `depth` behind."""
    dx, dy = direction
    sx, sy = dy, -dx
    base = (tip[0] - dx * depth, tip[1] - dy * depth)
    return [tip,
            (base[0] - sx * half_w, base[1] - sy * half_w),
            (base[0] + sx * half_w, base[1] + sy * half_w)]


# --- 31: feathered (fletched) arrows -------------------------------------
def _feathered_arrow_parts(tip, direction, length, fill):
    dx, dy = direction
    sx, sy = dy, -dx
    parts = []
    head_depth = 11
    # Barbed arrowhead (chevron with a notched back).
    parts.append((chevron(tip, direction, half_width=8, depth=head_depth, thickness=4), fill))
    # Shaft from just behind the head back to the tail.
    tail = (tip[0] - dx * length, tip[1] - dy * length)
    shaft_start = (tip[0] - dx * (head_depth - 2), tip[1] - dy * (head_depth - 2))
    shaft_center = ((shaft_start[0] + tail[0]) / 2, (shaft_start[1] + tail[1]) / 2)
    shaft_halflen = (length - (head_depth - 2)) / 2
    parts.append((rect(shaft_center, direction, shaft_halflen, 1.8), fill))
    # Three fletching barbs swept back-and-out on each side of the tail.
    top = _norm(-dx + sx * 0.9, -dy + sy * 0.9)
    bot = _norm(-dx - sx * 0.9, -dy - sy * 0.9)
    for i in range(3):
        base = (tail[0] + dx * (i * 3.2), tail[1] + dy * (i * 3.2))
        for bd in (top, bot):
            bc = (base[0] + bd[0] * 3.5, base[1] + bd[1] * 3.5)
            parts.append((rect(bc, bd, 4.0, 1.1), fill))
    return parts


def feathered_pair():
    parts = []
    parts += _feathered_arrow_parts((28, 32), (1, 0), 21,
                                    fill_axial((28, 32), (1, 0), 21, near=0.60, far=1.00))
    parts += _feathered_arrow_parts((36, 32), (-1, 0), 21,
                                    fill_axial((36, 32), (-1, 0), 21, near=0.60, far=1.00))
    return render(parts)


# --- 32: swept "pinched" chevrons ----------------------------------------
def _swept_arms(tip, direction, length, sweep, fill):
    dx, dy = direction
    sx, sy = dy, -dx
    top = _norm(-dx + sx * sweep, -dy + sy * sweep)
    bot = _norm(-dx - sx * sweep, -dy - sy * sweep)
    return [(taper_arm(tip, top, length, w_near=3.0, w_far=0.7), fill),
            (taper_arm(tip, bot, length, w_near=3.0, w_far=0.7), fill)]


def swept_pair():
    # Tips sit ~12px apart with the arms swept outward, so the two sides
    # read as a clean ">  <" pair rather than crossing into an X.
    parts = []
    parts += _swept_arms((26, 32), (1, 0), 15, 0.70,
                         fill_axial((26, 32), (1, 0), 13, near=0.60, far=1.00))
    parts += _swept_arms((38, 32), (-1, 0), 15, 0.70,
                         fill_axial((38, 32), (-1, 0), 13, near=0.60, far=1.00))
    return render(parts)


# --- 33: layered triangle stack ------------------------------------------
def triangle_stack_pair():
    parts = []
    # (tip_x, depth, half_w, brightness) - leading (toward center) brightest.
    right = [(12, 7, 7, 0.55), (21, 8, 8, 0.78), (31, 9, 9, 1.00)]
    left  = [(52, 7, 7, 0.55), (43, 8, 8, 0.78), (33, 9, 9, 1.00)]
    for tx, depth, hw, b in right:
        parts.append((tri((tx, 32), (1, 0), depth, hw), fill_uniform(b)))
    for tx, depth, hw, b in left:
        parts.append((tri((tx, 32), (-1, 0), depth, hw), fill_uniform(b)))
    return render(parts)


# --- 34: hollow double-line arrows ---------------------------------------
def _tri_sdf(p, tip, direction, depth, half_w):
    dx, dy = direction
    sx, sy = dy, -dx
    base = (tip[0] - dx * depth, tip[1] - dy * depth)
    return sdf_polygon(p, [tip,
                           (base[0] - sx * half_w, base[1] - sy * half_w),
                           (base[0] + sx * half_w, base[1] + sy * half_w)])


def hollow_pair():
    line = 1.7  # wall thickness
    arrows = [
        ((20, 32), (1, 0), 11, 11),
        ((30, 32), (1, 0), 11, 11),
        ((44, 32), (-1, 0), 11, 11),
        ((34, 32), (-1, 0), 11, 11),
    ]

    def sdf(p):
        d = float("inf")
        for tip, dir_, depth, hw in arrows:
            outer = _tri_sdf(p, tip, dir_, depth, hw)
            back = line * 2.2
            inner_tip = (tip[0] - dir_[0] * back, tip[1] - dir_[1] * back)
            inner = _tri_sdf(p, inner_tip, dir_, depth - back, hw - line * 2.0)
            shell = max(outer, -inner)
            if shell < d:
                d = shell
        return d
    return render_sdf(sdf)


# --- 35: double swept chevrons -------------------------------------------
def double_swept_pair():
    # Leading tips kept ~12px apart so the inner pair stays a ">  <", not an X.
    parts = []
    for tx, b in [(17, 0.62), (26, 1.00)]:
        parts += _swept_arms((tx, 32), (1, 0), 12, 0.70, fill_uniform(b))
    for tx, b in [(47, 0.62), (38, 1.00)]:
        parts += _swept_arms((tx, 32), (-1, 0), 12, 0.70, fill_uniform(b))
    return render(parts)


# --- 36: triple swept chevrons -------------------------------------------
def triple_swept_pair():
    parts = []
    for tx, b in [(10, 0.50), (18, 0.75), (26, 1.00)]:
        parts += _swept_arms((tx, 32), (1, 0), 10, 0.72, fill_uniform(b))
    for tx, b in [(54, 0.50), (46, 0.75), (38, 1.00)]:
        parts += _swept_arms((tx, 32), (-1, 0), 10, 0.72, fill_uniform(b))
    return render(parts)


# --- 37: hollow triangle stack -------------------------------------------
def hollow_triangle_stack_pair():
    line = 1.6
    tris = []
    for tx, depth, hw in [(12, 7, 7), (21, 8, 8), (30, 9, 9)]:
        tris.append(((tx, 32), (1, 0), depth, hw))
    for tx, depth, hw in [(52, 7, 7), (43, 8, 8), (34, 9, 9)]:
        tris.append(((tx, 32), (-1, 0), depth, hw))

    def sdf(p):
        d = float("inf")
        for tip, dir_, depth, hw in tris:
            outer = _tri_sdf(p, tip, dir_, depth, hw)
            back = line * 2.0
            inner_tip = (tip[0] - dir_[0] * back, tip[1] - dir_[1] * back)
            inner = _tri_sdf(p, inner_tip, dir_, depth - back, hw - line * 1.8)
            shell = max(outer, -inner)
            if shell < d:
                d = shell
        return d
    return render_sdf(sdf)


# --- 38: harpoon arrows ---------------------------------------------------
def _harpoon_parts(tip, direction, length, fill):
    dx, dy = direction
    sx, sy = dy, -dx
    parts = []
    head_depth, head_hw = 9, 5
    parts.append((tri(tip, direction, head_depth, head_hw), fill))
    base = (tip[0] - dx * head_depth, tip[1] - dy * head_depth)
    # Backward-hooking flukes from the head's base corners.
    for side in (1, -1):
        corner = (base[0] + sx * side * head_hw, base[1] + sy * side * head_hw)
        bdir = _norm(-dx + sx * side * 1.1, -dy + sy * side * 1.1)
        parts.append((taper_arm(corner, bdir, 7, w_near=2.2, w_far=0.6), fill))
    # Shaft from head base back to the tail.
    tail = (tip[0] - dx * length, tip[1] - dy * length)
    sc = ((base[0] + tail[0]) / 2, (base[1] + tail[1]) / 2)
    parts.append((rect(sc, direction, (length - head_depth) / 2, 1.6), fill))
    return parts


def harpoon_pair():
    parts = []
    parts += _harpoon_parts((30, 32), (1, 0), 20, fill_axial((30, 32), (1, 0), 20, 0.60, 1.00))
    parts += _harpoon_parts((34, 32), (-1, 0), 20, fill_axial((34, 32), (-1, 0), 20, 0.60, 1.00))
    return render(parts)


# --- 39: bold solid arrows ------------------------------------------------
def bold_arrow_pair():
    parts = []
    for tip, dir_ in [((30, 32), (1, 0)), ((34, 32), (-1, 0))]:
        dx, dy = dir_
        fill = fill_axial(tip, dir_, 22, near=0.55, far=1.00)
        parts.append((tri(tip, dir_, 12, 11), fill))
        base = (tip[0] - dx * 12, tip[1] - dy * 12)
        tail = (tip[0] - dx * 22, tip[1] - dy * 22)
        sc = ((base[0] + tail[0]) / 2, (base[1] + tail[1]) / 2)
        parts.append((rect(sc, dir_, 5, 4.5), fill))
    return render(parts)


# --- 40: broadhead (barbed) arrows ---------------------------------------
def barbed_head(tip, direction, depth, half_w, notch):
    """Concave-backed arrowhead: two backward barbs with a notch between."""
    dx, dy = direction
    sx, sy = dy, -dx
    wing_t = (tip[0] - dx * depth - sx * half_w, tip[1] - dy * depth - sy * half_w)
    wing_b = (tip[0] - dx * depth + sx * half_w, tip[1] - dy * depth + sy * half_w)
    notch_pt = (tip[0] - dx * (depth - notch), tip[1] - dy * (depth - notch))
    return [tip, wing_t, notch_pt, wing_b]


def broadhead_pair():
    parts = []
    for tip, dir_ in [((30, 32), (1, 0)), ((34, 32), (-1, 0))]:
        dx, dy = dir_
        fill = fill_axial(tip, dir_, 22, near=0.55, far=1.00)
        parts.append((barbed_head(tip, dir_, depth=14, half_w=12, notch=7), fill))
        base = (tip[0] - dx * 14, tip[1] - dy * 14)
        tail = (tip[0] - dx * 23, tip[1] - dy * 23)
        sc = ((base[0] + tail[0]) / 2, (base[1] + tail[1]) / 2)
        parts.append((rect(sc, dir_, 4.5, 2.2), fill))
    return render(parts)


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
    ("reticle_31_feathered_arrows.tga",     feathered_pair),
    ("reticle_32_swept_chevrons.tga",       swept_pair),
    ("reticle_33_triangle_stack.tga",       triangle_stack_pair),
    ("reticle_34_hollow_arrows.tga",        hollow_pair),
    ("reticle_35_double_swept.tga",         double_swept_pair),
    ("reticle_36_triple_swept.tga",         triple_swept_pair),
    ("reticle_37_hollow_triangle_stack.tga", hollow_triangle_stack_pair),
    ("reticle_38_harpoon_arrows.tga",       harpoon_pair),
    ("reticle_39_bold_arrows.tga",          bold_arrow_pair),
    ("reticle_40_broadhead_arrows.tga",     broadhead_pair),
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
