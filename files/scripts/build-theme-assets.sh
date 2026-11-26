#!/usr/bin/env bash
set -euo pipefail

# Sol OS (BC-250 Edition) — Sol Eclipse theme asset builder.
# Runs inside the sol-theme-builder BlueBuild stage (OUT_PREFIX=/out by default)
# and generates Plymouth splash assets, Plasma KSplash eclipse graphic, hicolor/pixmap
# logos, and the 1080p VP9 Steam/Gamescope startup video from the SolEclipse wallpaper.

OUT_PREFIX="${OUT_PREFIX:-/out}"
SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"
WORK_DIR="$(mktemp -d /tmp/sol-theme-assets.XXXXXX)"
trap 'rm -rf "${WORK_DIR}"' EXIT

log() {
  printf '[build-theme-assets] %s\n' "$*"
}

die() {
  printf '[build-theme-assets] ERROR: %s\n' "$*" >&2
  exit 1
}

detect_pkg_mgr() {
  if command -v dnf5 >/dev/null 2>&1; then
    printf 'dnf5\n'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf\n'
  else
    return 1
  fi
}

ensure_ffmpeg() {
  if command -v ffmpeg >/dev/null 2>&1; then
    log "ffmpeg already present: $(command -v ffmpeg)"
    return 0
  fi

  local pkg_mgr=""
  pkg_mgr="$(detect_pkg_mgr)" || die "ffmpeg is missing and neither dnf5 nor dnf was found."

  log "ffmpeg not found; installing ffmpeg-free via ${pkg_mgr}..."
  if ! "${pkg_mgr}" install -y ffmpeg-free; then
    log "ffmpeg-free installation failed; falling back to ffmpeg..."
    "${pkg_mgr}" install -y ffmpeg || die "Failed to install ffmpeg-free or ffmpeg."
  fi

  command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg still unavailable after package installation."
}

ensure_pillow() {
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import PIL' >/dev/null 2>&1; then
    log "python3 PIL (Pillow) already present."
    return 0
  fi

  local pkg_mgr=""
  pkg_mgr="$(detect_pkg_mgr)" || die "python3 PIL is missing and neither dnf5 nor dnf was found."

  if ! command -v python3 >/dev/null 2>&1; then
    log "python3 not found; installing python3 and python3-pillow via ${pkg_mgr}..."
    "${pkg_mgr}" install -y python3 python3-pillow
  else
    log "python3 PIL not found; installing python3-pillow via ${pkg_mgr}..."
    "${pkg_mgr}" install -y python3-pillow
  fi

  python3 -c 'import PIL' >/dev/null 2>&1 || die "python3 failed to import PIL after installing python3-pillow."
}

find_sans_font() {
  if [ ! -d /usr/share/fonts ]; then
    return 1
  fi

  find /usr/share/fonts -type f \( -iname '*.ttf' -o -iname '*.otf' \) 2>/dev/null \
    | LC_ALL=C sort \
    | awk '
      {
        path = $0
        low = tolower(path)

        # Skip non-Latin scripts, monospace, serif, symbol, and emoji fonts
        if (low ~ /(mono|serif|symbol|emoji|math|nerd|cjk|arabic|hebrew|thai|devanagari|tamil|bengali|telugu|kannada|malayalam|gujarati|gurmukhi|oriya|sinhala|khmer|lao|myanmar|tibetan|georgian|armenian|ethiopic|cherokee|hangul|kaiti|songti|ming|gothic|mincho)/) {
          next
        }

        score = 0
        if (low ~ /notosans.*light/) {
          score = 100
        } else if (low ~ /notosans-regular/ || low ~ /notosans\[/) {
          score = 95
        } else if (low ~ /noto.*sans/ && low !~ /(bold|italic|oblique|black|thin|condensed|extra|semi|medium|ui|display)/) {
          score = 90
        } else if (low ~ /inter.*light/) {
          score = 85
        } else if (low ~ /inter.*(regular|variable)/ || low ~ /inter\[/) {
          score = 80
        } else if (low ~ /inter/ && low !~ /(bold|italic|oblique|black|thin|condensed)/) {
          score = 75
        } else if (low ~ /liberationsans-regular/) {
          score = 70
        } else if (low ~ /liberationsans/ && low !~ /(bold|italic|oblique)/) {
          score = 65
        } else if (low ~ /dejavusans\.ttf$/) {
          score = 60
        } else if (low ~ /dejavusans/ && low !~ /(bold|italic|oblique|condensed)/) {
          score = 55
        } else if (low ~ /sans/ && low ~ /(light|regular)/ && low !~ /(bold|italic|oblique|condensed)/) {
          score = 45
        } else if (low ~ /sans/ && low !~ /(bold|italic|oblique|condensed)/) {
          score = 35
        }

        if (score > best_score) {
          best_score = score
          best_path = path
        }
      }
      END {
        if (best_score > 0 && best_path != "") {
          print best_path
        }
      }
    '
}

ensure_sans_font() {
  local font_path=""
  font_path="$(find_sans_font || true)"

  if [ -z "${font_path}" ]; then
    local pkg_mgr=""
    pkg_mgr="$(detect_pkg_mgr)" || die "No scalable sans-serif font found under /usr/share/fonts and neither dnf5 nor dnf was found."
    log "No scalable sans-serif TTF/OTF font found; installing dejavu-sans-fonts via ${pkg_mgr}..."
    "${pkg_mgr}" install -y dejavu-sans-fonts
    font_path="$(find_sans_font || true)"
  fi

  [ -n "${font_path}" ] && [ -f "${font_path}" ] || die "Unable to locate a scalable sans-serif font under /usr/share/fonts."
  log "Selected sans-serif font: ${font_path}"
  printf '%s\n' "${font_path}"
}

find_wallpaper_path() {
  local dir=""
  local first_img=""

  if [ -n "${SOL_WALLPAPER_PATH:-}" ] && [ -f "${SOL_WALLPAPER_PATH}" ]; then
    printf '%s\n' "${SOL_WALLPAPER_PATH}"
    return 0
  fi

  for dir in \
    "/usr/share/wallpapers/SolEclipse/contents/images" \
    "${SCRIPT_DIR}/../system/usr/share/wallpapers/SolEclipse/contents/images"
  do
    if [ -f "${dir}/2560x1440.png" ]; then
      printf '%s\n' "${dir}/2560x1440.png"
      return 0
    fi
    if [ -d "${dir}" ]; then
      first_img="$(
        find "${dir}" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null \
          | LC_ALL=C sort \
          | awk 'NR == 1 { print; exit }'
      )"
      if [ -n "${first_img}" ] && [ -f "${first_img}" ]; then
        printf '%s\n' "${first_img}"
        return 0
      fi
    fi
  done

  return 1
}

copy_plymouth_descriptor() {
  local src="/usr/share/plymouth/themes/sol-eclipse/sol-eclipse.plymouth"
  local dst="${OUT_PREFIX}/usr/share/plymouth/themes/sol-eclipse/sol-eclipse.plymouth"

  if [ ! -f "${src}" ] && [ -f "${SCRIPT_DIR}/../system/usr/share/plymouth/themes/sol-eclipse/sol-eclipse.plymouth" ]; then
    src="${SCRIPT_DIR}/../system/usr/share/plymouth/themes/sol-eclipse/sol-eclipse.plymouth"
  fi

  if [ -f "${src}" ]; then
    if [ "${src}" != "${dst}" ]; then
      log "Copying ${src} -> ${dst}..."
      install -D -m 0644 "${src}" "${dst}"
    fi
  else
    log "Note: ${src} not present in stage; skipping descriptor copy."
  fi
}

generate_assets() {
  local font_path="$1"
  local wallpaper_path="$2"
  local py_script="${WORK_DIR}/render_sol_assets.py"

  cat <<'PYEOF' > "${py_script}"
#!/usr/bin/env python3
import math
import os
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

LANCZOS = getattr(Image, "Resampling", Image).LANCZOS
OBSIDIAN_RGB = (8, 10, 15)       # #080A0F
GOLD_MID = (217, 164, 76)        # #D9A44C
GOLD_BRIGHT = (229, 181, 103)    # #E5B567
GOLD_HIGHLIGHT = (255, 240, 200) # #FFF0C8


def clamp(val, lo, hi):
    return max(lo, min(hi, val))


def smootherstep(t):
    t = clamp(t, 0.0, 1.0)
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def ease_out_cubic(t):
    t = clamp(t, 0.0, 1.0)
    return 1.0 - (1.0 - t) ** 3


def ease_in_out_cubic(t):
    t = clamp(t, 0.0, 1.0)
    if t < 0.5:
        return 4.0 * t * t * t
    return 1.0 - ((-2.0 * t + 2.0) ** 3) / 2.0


def load_font(font_path, size_px, weight_hint=None):
    font = ImageFont.truetype(font_path, size_px)
    if weight_hint is not None and hasattr(font, "set_variation_by_axes"):
        try:
            axes = font.get_variation_axes()
            axis_vals = []
            has_wght = False
            for ax in axes:
                tag = ax.get("name", "")
                if isinstance(tag, bytes):
                    tag = tag.decode("ascii", errors="ignore")
                default_v = ax.get("default", 400)
                if tag.lower() in ("weight", "wght"):
                    axis_vals.append(clamp(weight_hint, ax.get("minimum", 100), ax.get("maximum", 900)))
                    has_wght = True
                else:
                    axis_vals.append(default_v)
            if has_wght:
                font.set_variation_by_axes(axis_vals)
        except Exception:
            pass
    return font


def build_procedural_eclipse_wallpaper(width=2560, height=1440):
    base = Image.new("RGBA", (width, height), OBSIDIAN_RGB + (255,))
    cx, cy = width // 2, height // 2

    # Outer warm solar atmosphere
    atmo = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ad = ImageDraw.Draw(atmo)
    for r, alpha, col in (
        (560, 18, (217, 164, 76)),
        (450, 34, (217, 164, 76)),
        (370, 58, (229, 181, 103)),
    ):
        ad.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col + (alpha,))
    atmo = atmo.filter(ImageFilter.GaussianBlur(radius=90))
    base = Image.alpha_composite(base, atmo)

    # Corona ring
    ring = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rd.ellipse((cx - 318, cy - 318, cx + 318, cy + 318), fill=(229, 181, 103, 215))
    rd.ellipse((cx - 294, cy - 294, cx + 294, cy + 294), fill=(255, 240, 200, 245))
    ring_glow = ring.filter(ImageFilter.GaussianBlur(radius=22))
    base = Image.alpha_composite(base, ring_glow)
    base = Image.alpha_composite(base, ring)

    # Moon disc
    moon = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    md = ImageDraw.Draw(moon)
    md.ellipse((cx - 284, cy - 284, cx + 284, cy + 284), fill=OBSIDIAN_RGB + (255,))
    base = Image.alpha_composite(base, moon)
    return base.convert("RGB")


def extract_centered_eclipse(wallpaper_path):
    if wallpaper_path and os.path.isfile(wallpaper_path):
        img = Image.open(wallpaper_path).convert("RGB")
    else:
        img = build_procedural_eclipse_wallpaper()

    w, h = img.size
    sw, sh = 160, max(64, int(round(160 * h / float(w))))
    lum_img = img.convert("L").resize((sw, sh), LANCZOS)
    pix = list(lum_img.getdata())

    border_samples = []
    for y in range(sh):
        for x in range(sw):
            if x < 6 or x >= sw - 6 or y < 4 or y >= sh - 4:
                border_samples.append(pix[y * sw + x])
    bg_lum = sorted(border_samples)[len(border_samples) // 2] if border_samples else 10
    thresh = max(bg_lum + 22, 34)

    pts = []
    x_min, x_max = int(sw * 0.14), int(sw * 0.86)
    y_min, y_max = int(sh * 0.06), int(sh * 0.94)
    sum_w = 0.0
    sum_wx = 0.0
    sum_wy = 0.0
    for y in range(y_min, y_max):
        row_off = y * sw
        for x in range(x_min, x_max):
            v = pix[row_off + x]
            if v > thresh:
                wt = float(v - thresh)
                pts.append((x, y))
                sum_w += wt
                sum_wx += x * wt
                sum_wy += y * wt

    if len(pts) >= 16 and sum_w > 0.0:
        cx_s = sum_wx / sum_w
        cy_s = sum_wy / sum_w
        dists = sorted(math.hypot(px - cx_s, py - cy_s) for px, py in pts)
        r_s = dists[int(0.95 * (len(dists) - 1))]
        cx = cx_s * (w / float(sw))
        cy = cy_s * (h / float(sh))
        r_full = r_s * (w / float(sw))
        target_side = int(clamp(r_full * 2.9, min(w, h) * 0.45, float(min(w, h))))
    else:
        cx = w / 2.0
        cy = h / 2.0
        target_side = int(min(w, h) * 0.78)

    half = min(
        target_side // 2,
        int(cx),
        int(w - cx),
        int(cy),
        int(h - cy),
    )
    if half < int(min(w, h) * 0.22):
        cx, cy = w / 2.0, h / 2.0
        half = int(min(w, h) * 0.44)

    left = int(round(cx - half))
    top = int(round(cy - half))
    right = left + half * 2
    bottom = top + half * 2
    return img.crop((left, top, right, bottom))


def make_radial_alpha_mask(size, inner_frac=0.52, outer_frac=0.95):
    half = (size - 1) / 2.0
    r0 = inner_frac * half
    r1 = outer_frac * half
    span = max(1e-6, r1 - r0)

    buf = bytearray(size * size)
    for y in range(size):
        dy = y - half
        dy2 = dy * dy
        row_off = y * size
        for x in range(size):
            dx = x - half
            r = math.sqrt(dx * dx + dy2)
            if r <= r0:
                buf[row_off + x] = 255
            elif r >= r1:
                buf[row_off + x] = 0
            else:
                u = (r - r0) / span
                s = u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
                buf[row_off + x] = int(round(255.0 * (1.0 - s)))
    return Image.frombytes("L", (size, size), bytes(buf))


def apply_radial_fade(crop_rgb, out_size, inner_frac=0.52, outer_frac=0.95):
    resized = crop_rgb.resize((out_size, out_size), LANCZOS).convert("RGBA")
    mask = make_radial_alpha_mask(out_size, inner_frac=inner_frac, outer_frac=outer_frac)
    resized.putalpha(mask)
    return resized


def make_gold_gradient(width, height, top_col, mid_col, bot_col):
    grad_1px = Image.new("RGBA", (1, height))
    rows = []
    denom = max(1, height - 1)
    for y in range(height):
        t = y / float(denom)
        if t < 0.48:
            u = t / 0.48
            c = tuple(int(round(top_col[i] * (1.0 - u) + mid_col[i] * u)) for i in range(3))
        else:
            u = (t - 0.48) / 0.52
            c = tuple(int(round(mid_col[i] * (1.0 - u) + bot_col[i] * u)) for i in range(3))
        rows.append(c + (255,))
    grad_1px.putdata(rows)
    return grad_1px.resize((width, height), Image.BILINEAR)


def draw_tracked_text_mask(mask_img, text, font, center_x, top_y, tracking_px):
    draw = ImageDraw.Draw(mask_img)
    chars = list(text)
    advances = []
    for ch in chars:
        try:
            adv = float(font.getlength(ch))
        except Exception:
            bb = draw.textbbox((0, 0), ch, font=font)
            adv = float(bb[2] - bb[0])
        advances.append(adv)

    total_w = sum(advances) + tracking_px * max(0, len(chars) - 1)
    cur_x = center_x - total_w / 2.0
    sample_bb = draw.textbbox((0, 0), text, font=font)
    draw_y = top_y - sample_bb[1]

    for ch, adv in zip(chars, advances):
        draw.text((cur_x, draw_y), ch, font=font, fill=255)
        cur_x += adv + tracking_px

    return sample_bb[3] - sample_bb[1]


def render_wordmark_rgba(font_path, out_w=560, out_h=170, scale=2):
    sw, sh = out_w * scale, out_h * scale
    canvas = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))

    sol_font = load_font(font_path, 54 * scale, weight_hint=500)
    sub_font = load_font(font_path, 21 * scale, weight_hint=300)

    sol_mask = Image.new("L", (sw, sh), 0)
    sol_h = draw_tracked_text_mask(
        sol_mask,
        "SOL",
        sol_font,
        center_x=sw / 2.0,
        top_y=18 * scale,
        tracking_px=26 * scale,
    )

    sub_mask = Image.new("L", (sw, sh), 0)
    draw_tracked_text_mask(
        sub_mask,
        "startup",
        sub_font,
        center_x=sw / 2.0,
        top_y=18 * scale + sol_h + 24 * scale,
        tracking_px=8 * scale,
    )

    # Warm glow behind typography
    glow_mask = ImageChops.lighter(sol_mask, sub_mask)
    glow_blur = glow_mask.filter(ImageFilter.GaussianBlur(radius=11 * scale))
    glow_blur = glow_blur.point(lambda p: int(p * 0.42))
    glow_layer = Image.new("RGBA", (sw, sh), GOLD_MID + (0,))
    glow_layer.putalpha(glow_blur)
    canvas = Image.alpha_composite(canvas, glow_layer)

    # Brushed solar gold fill for "SOL"
    sol_grad = make_gold_gradient(sw, sh, (249, 224, 160), GOLD_BRIGHT, (189, 132, 46))
    sol_grad.putalpha(sol_mask)
    canvas = Image.alpha_composite(canvas, sol_grad)

    # Subtle warm champagne gold fill for "startup"
    sub_grad = make_gold_gradient(sw, sh, (236, 201, 134), (212, 162, 82), (176, 128, 52))
    sub_mask_soft = sub_mask.point(lambda p: int(p * 0.90))
    sub_grad.putalpha(sub_mask_soft)
    canvas = Image.alpha_composite(canvas, sub_grad)

    return canvas.resize((out_w, out_h), LANCZOS)


def render_spinner_frame(angle_deg, out_size=64, supersample=4):
    sz = out_size * supersample
    cx = cy = sz / 2.0
    radius = sz * 0.375

    # Faint obsidian-gold track ring
    track = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    td = ImageDraw.Draw(track)
    track_w = max(2, int(round(sz * 0.018)))
    td.ellipse(
        (cx - radius, cy - radius, cx + radius, cy + radius),
        outline=GOLD_MID + (38,),
        width=track_w,
    )

    # Tapered sweeping solar arc
    arc = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arc)
    arc_span = 135.0
    steps = 180
    head_rad_deg = -90.0 + angle_deg

    for s in range(steps + 1):
        frac = s / float(steps)
        deg = head_rad_deg - arc_span * (1.0 - frac)
        rad = math.radians(deg)
        px = cx + radius * math.cos(rad)
        py = cy + radius * math.sin(rad)

        intensity = frac ** 1.5
        alpha = int(round(255.0 * (frac ** 1.35)))
        r_brush = sz * (0.008 + 0.013 * intensity)

        if frac < 0.72:
            u = frac / 0.72
            col = (
                int(round(184 + (229 - 184) * u)),
                int(round(124 + (181 - 124) * u)),
                int(round(40 + (103 - 40) * u)),
            )
        else:
            u = (frac - 0.72) / 0.28
            col = (
                int(round(229 + (255 - 229) * u)),
                int(round(181 + (242 - 181) * u)),
                int(round(103 + (210 - 103) * u)),
            )

        ad.ellipse((px - r_brush, py - r_brush, px + r_brush, py + r_brush), fill=col + (alpha,))

    glow = arc.filter(ImageFilter.GaussianBlur(radius=supersample * 2.2))
    r_g, g_g, b_g, a_g = glow.split()
    glow = Image.merge("RGBA", (r_g, g_g, b_g, a_g.point(lambda p: int(p * 0.65))))

    combined = Image.alpha_composite(track, glow)
    combined = Image.alpha_composite(combined, arc)
    return combined.resize((out_size, out_size), LANCZOS)


def render_eclipse_logo(size=512):
    sz = 1024
    cx = cy = sz // 2
    canvas = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))

    # Outer soft solar corona halo (clipped smoothly away from edges)
    halo = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    hd.ellipse((cx - 356, cy - 356, cx + 356, cy + 356), outline=GOLD_MID + (145,), width=44)
    hd.ellipse((cx - 336, cy - 336, cx + 336, cy + 336), outline=GOLD_BRIGHT + (210,), width=24)
    # Subtle solar prominence arc on upper-right edge
    hd.arc((cx - 348, cy - 348, cx + 348, cy + 348), start=285, end=25, fill=GOLD_HIGHLIGHT + (220,), width=28)
    halo_outer = halo.filter(ImageFilter.GaussianBlur(radius=42))
    halo_inner = halo.filter(ImageFilter.GaussianBlur(radius=14))

    fade_mask = make_radial_alpha_mask(sz, inner_frac=0.66, outer_frac=0.96)
    for layer, scale_a in ((halo_outer, 0.85), (halo_inner, 0.78)):
        r, g, b, a = layer.split()
        a_masked = ImageChops.multiply(a, fade_mask).point(lambda p: int(p * scale_a))
        masked = Image.merge("RGBA", (r, g, b, a_masked))
        canvas = Image.alpha_composite(canvas, masked)

    # Crisp metallic golden corona ring with diagonal lighting
    ring_mask = Image.new("L", (sz, sz), 0)
    rmd = ImageDraw.Draw(ring_mask)
    rmd.ellipse((cx - 334, cy - 334, cx + 334, cy + 334), fill=255)
    rmd.ellipse((cx - 284, cy - 284, cx + 284, cy + 284), fill=0)

    ring_grad = make_gold_gradient(sz, sz, GOLD_HIGHLIGHT, GOLD_BRIGHT, (186, 127, 42))
    ring_grad.putalpha(ring_mask)
    canvas = Image.alpha_composite(canvas, ring_grad)

    # Crescent highlight rim on upper-right edge
    rim = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    rim_d = ImageDraw.Draw(rim)
    rim_d.arc((cx - 328, cy - 328, cx + 328, cy + 328), start=280, end=20, fill=(255, 247, 224, 210), width=14)
    rim = rim.filter(ImageFilter.GaussianBlur(radius=4))
    canvas = Image.alpha_composite(canvas, rim)

    # Opaque obsidian moon disc with hairline warm inner rim
    moon = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
    md = ImageDraw.Draw(moon)
    md.ellipse((cx - 286, cy - 286, cx + 286, cy + 286), fill=OBSIDIAN_RGB + (255,))
    md.ellipse((cx - 285, cy - 285, cx + 285, cy + 285), outline=GOLD_BRIGHT + (80,), width=4)
    canvas = Image.alpha_composite(canvas, moon)

    return canvas.resize((size, size), LANCZOS)


def paste_with_opacity(base_rgb, overlay_rgba, pos, opacity):
    if opacity <= 0.001:
        return
    ox, oy = pos
    ow, oh = overlay_rgba.size
    region = base_rgb.crop((ox, oy, ox + ow, oy + oh)).convert("RGBA")
    if opacity < 0.999:
        r, g, b, a = overlay_rgba.split()
        a = a.point(lambda p: int(p * opacity))
        ov = Image.merge("RGBA", (r, g, b, a))
    else:
        ov = overlay_rgba
    composited = Image.alpha_composite(region, ov).convert("RGB")
    base_rgb.paste(composited, (ox, oy))


def main():
    out_prefix = sys.argv[1]
    font_path = sys.argv[2]
    wallpaper_path = sys.argv[3] if len(sys.argv) > 3 else ""

    eclipse_crop = extract_centered_eclipse(wallpaper_path)

    # 1) Plasma KSplash eclipse.png (640x640 RGBA)
    splash_dir = os.path.join(
        out_prefix,
        "usr/share/plasma/look-and-feel/org.sol-os.eclipse/contents/splash/images",
    )
    os.makedirs(splash_dir, exist_ok=True)
    eclipse_splash = apply_radial_fade(eclipse_crop, 640, inner_frac=0.50, outer_frac=0.95)
    eclipse_splash.save(os.path.join(splash_dir, "eclipse.png"), format="PNG", optimize=True)

    # 2) Plymouth watermark.png (680x680 RGBA)
    plymouth_dir = os.path.join(out_prefix, "usr/share/plymouth/themes/sol-eclipse")
    os.makedirs(plymouth_dir, exist_ok=True)

    wm = Image.new("RGBA", (680, 680), (0, 0, 0, 0))
    wm_eclipse = apply_radial_fade(eclipse_crop, 420, inner_frac=0.46, outer_frac=0.95)
    wm.alpha_composite(wm_eclipse, dest=((680 - 420) // 2, 24))

    wordmark = render_wordmark_rgba(font_path, out_w=560, out_h=170, scale=2)
    wm.alpha_composite(wordmark, dest=((680 - 560) // 2, 464))
    wm.save(os.path.join(plymouth_dir, "watermark.png"), format="PNG", optimize=True)

    # 3) Plymouth throbber-0001.png .. throbber-0036.png (64x64 RGBA, 10 deg/frame)
    for i in range(36):
        frame = render_spinner_frame(i * 10.0, out_size=64, supersample=4)
        frame.save(
            os.path.join(plymouth_dir, "throbber-%04d.png" % (i + 1)),
            format="PNG",
            optimize=True,
        )

    # 4) Transparent RGBA golden eclipse logos
    pixmaps_dir = os.path.join(out_prefix, "usr/share/pixmaps")
    icon_256_dir = os.path.join(out_prefix, "usr/share/icons/hicolor/256x256/apps")
    icon_512_dir = os.path.join(out_prefix, "usr/share/icons/hicolor/512x512/apps")
    os.makedirs(pixmaps_dir, exist_ok=True)
    os.makedirs(icon_256_dir, exist_ok=True)
    os.makedirs(icon_512_dir, exist_ok=True)

    logo_512 = render_eclipse_logo(512)
    logo_256 = logo_512.resize((256, 256), LANCZOS)
    logo_512.save(os.path.join(icon_512_dir, "sol-os-logo.png"), format="PNG", optimize=True)
    logo_256.save(os.path.join(icon_256_dir, "sol-os-logo.png"), format="PNG", optimize=True)
    logo_256.save(os.path.join(pixmaps_dir, "sol-os-logo.png"), format="PNG", optimize=True)

    # 5) CSS Loader Solar Eclipse 1920x1080 JPEG backdrop
    css_dir = os.path.join(out_prefix, "usr/share/sol-os/theme/css-loader/Sol-Eclipse")
    os.makedirs(css_dir, exist_ok=True)
    if wallpaper_path and os.path.isfile(wallpaper_path):
        backdrop_rgb = Image.open(wallpaper_path).convert("RGB").resize((1920, 1080), LANCZOS)
    else:
        backdrop_rgb = build_procedural_eclipse_wallpaper(width=1920, height=1080)
    backdrop_rgb.save(os.path.join(css_dir, "backdrop.jpg"), format="JPEG", quality=88, optimize=True)

    # 6) 1920x1080 30fps 4.0s (120 frames) VP9 Steam/Gamescope startup video
    theme_dir = os.path.join(out_prefix, "usr/share/sol-os/theme")
    os.makedirs(theme_dir, exist_ok=True)
    webm_path = os.path.join(theme_dir, "sol_startup.webm")

    vid_w, vid_h = 1920, 1080
    bg_rgb = Image.new("RGB", (vid_w, vid_h), OBSIDIAN_RGB)
    vid_eclipse = apply_radial_fade(eclipse_crop, 520, inner_frac=0.48, outer_frac=0.95)
    vid_wordmark = render_wordmark_rgba(font_path, out_w=640, out_h=190, scale=2)
    spinner_frames = [render_spinner_frame(i * 10.0, out_size=72, supersample=4) for i in range(36)]

    ffmpeg_cmd = [
        "ffmpeg",
        "-y",
        "-f", "rawvideo",
        "-pix_fmt", "rgb24",
        "-s", "1920x1080",
        "-r", "30",
        "-i", "-",
        "-c:v", "libvpx-vp9",
        "-pix_fmt", "yuv420p",
        "-b:v", "0",
        "-crf", "28",
        "-an",
        webm_path,
    ]
    proc = subprocess.Popen(ffmpeg_cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE)

    eclipse_x = (vid_w - 520) // 2
    eclipse_y = 148
    text_x = (vid_w - 640) // 2
    text_base_y = 656
    spin_x = (vid_w - 72) // 2
    spin_y = 876

    try:
        for f in range(120):
            frame = bg_rgb.copy()

            # Smooth fade-in of solar eclipse from #080A0F (frames 0..27)
            eclipse_alpha = ease_out_cubic(f / 27.0)
            # Subtle warm pulse during mid hold
            pulse = 1.0 + 0.04 * math.sin((f / 30.0) * math.pi * 1.2)
            eclipse_op = clamp(eclipse_alpha * pulse, 0.0, 1.0)
            paste_with_opacity(frame, vid_eclipse, (eclipse_x, eclipse_y), eclipse_op)

            # Wide-tracked SOL / startup reveal with slight upward float (frames 18..44)
            text_t = clamp((f - 18) / 26.0, 0.0, 1.0)
            text_alpha = ease_out_cubic(text_t)
            text_y_off = int(round((1.0 - ease_out_cubic(text_t)) * 14.0))
            paste_with_opacity(frame, vid_wordmark, (text_x, text_base_y + text_y_off), text_alpha)

            # Smooth golden spinner rotation (frames 26..119)
            spin_alpha = ease_out_cubic((f - 26) / 18.0)
            spin_img = spinner_frames[f % 36]
            paste_with_opacity(frame, spin_img, (spin_x, spin_y), spin_alpha)

            # Clean fade back to #080A0F (frames 94..119)
            if f >= 94:
                fade_out = ease_in_out_cubic((f - 94) / 25.0)
                if fade_out > 0.0:
                    frame = Image.blend(frame, bg_rgb, fade_out)

            proc.stdin.write(frame.tobytes())
    finally:
        if proc.stdin:
            proc.stdin.close()

    _, err_bytes = proc.communicate()
    if proc.returncode != 0:
        err_text = err_bytes.decode("utf-8", errors="replace")
        raise RuntimeError("ffmpeg failed (rc=%d):\n%s" % (proc.returncode, err_text))


if __name__ == "__main__":
    main()
PYEOF

  log "Generating Sol Eclipse theme images, logos, Plymouth frames, and startup video into ${OUT_PREFIX}..."
  python3 "${py_script}" "${OUT_PREFIX}" "${font_path}" "${wallpaper_path}"
}

verify_outputs() {
  local missing=0
  local i
  local frame_file=""
  local f=""

  for f in \
    "${OUT_PREFIX}/usr/share/plasma/look-and-feel/org.sol-os.eclipse/contents/splash/images/eclipse.png" \
    "${OUT_PREFIX}/usr/share/plymouth/themes/sol-eclipse/watermark.png" \
    "${OUT_PREFIX}/usr/share/pixmaps/sol-os-logo.png" \
    "${OUT_PREFIX}/usr/share/icons/hicolor/256x256/apps/sol-os-logo.png" \
    "${OUT_PREFIX}/usr/share/icons/hicolor/512x512/apps/sol-os-logo.png" \
    "${OUT_PREFIX}/usr/share/sol-os/theme/css-loader/Sol-Eclipse/backdrop.jpg" \
    "${OUT_PREFIX}/usr/share/sol-os/theme/sol_startup.webm"
  do
    if [ ! -s "${f}" ]; then
      log "ERROR: Generated asset missing or empty: ${f}"
      missing=1
    fi
  done

  i=1
  while [ "${i}" -le 36 ]; do
    frame_file="$(printf '%s/usr/share/plymouth/themes/sol-eclipse/throbber-%04d.png' "${OUT_PREFIX}" "${i}")"
    if [ ! -s "${frame_file}" ]; then
      log "ERROR: Generated throbber frame missing or empty: ${frame_file}"
      missing=1
    fi
    i=$((i + 1))
  done

  if [ "${missing}" -ne 0 ]; then
    die "Asset verification failed; one or more generated files are missing or empty."
  fi

  log "Verified all generated theme assets under ${OUT_PREFIX}."
}

main() {
  local font_path=""
  local wallpaper_path=""

  ensure_ffmpeg
  ensure_pillow
  font_path="$(ensure_sans_font)"

  if wallpaper_path="$(find_wallpaper_path)"; then
    log "Using wallpaper source: ${wallpaper_path}"
  else
    log "WARNING: SolEclipse wallpaper not found; falling back to procedural eclipse generator."
    wallpaper_path=""
  fi

  copy_plymouth_descriptor
  generate_assets "${font_path}" "${wallpaper_path}"
  verify_outputs
  log "Done."
}

main "$@"
