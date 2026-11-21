import os
from PIL import Image, ImageDraw

def draw_tenx_icon(size):
    # Render at 4x for super-sampled antialiasing
    scale = 4
    w = size * scale
    h = size * scale
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background squircle
    radius = int(w * 0.26)
    # Dark rounded rect
    draw.rounded_rectangle([2, 2, w - 3, h - 3], radius=radius, fill=(13, 17, 28, 255), outline=(43, 58, 90, 255), width=int(2 * scale))

    # Stroke width
    sw = int(w * 0.16)

    # Blade 1: Cyan/Blue (Top-Left to Bottom-Right)
    # Draw line
    p1_start = (int(w * 0.18), int(h * 0.18))
    p1_end = (int(w * 0.82), int(h * 0.82))
    draw.line([p1_start, p1_end], fill=(0, 229, 255, 255), width=sw)
    # Round caps
    draw.ellipse([p1_start[0]-sw//2, p1_start[1]-sw//2, p1_start[0]+sw//2, p1_start[1]+sw//2], fill=(0, 229, 255, 255))
    draw.ellipse([p1_end[0]-sw//2, p1_end[1]-sw//2, p1_end[0]+sw//2, p1_end[1]+sw//2], fill=(0, 102, 255, 255))

    # Blade 2: Purple/Violet (Top-Right to Bottom-Left)
    p2_start = (int(w * 0.82), int(h * 0.18))
    p2_end = (int(w * 0.18), int(h * 0.82))
    draw.line([p2_start, p2_end], fill=(192, 132, 252, 255), width=sw)
    draw.ellipse([p2_start[0]-sw//2, p2_start[1]-sw//2, p2_start[0]+sw//2, p2_start[1]+sw//2], fill=(192, 132, 252, 255))
    draw.ellipse([p2_end[0]-sw//2, p2_end[1]-sw//2, p2_end[0]+sw//2, p2_end[1]+sw//2], fill=(124, 58, 237, 255))

    # Center white core pip
    cx, cy = w // 2, h // 2
    cr = int(sw * 0.4)
    draw.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(255, 255, 255, 255))

    # Resize down with Lanczos resampling
    return img.resize((size, size), Image.Resampling.LANCZOS)

densities = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

base_dir = r"c:\Users\hp\Documents\Web-Projects\Alert-App\android\app\src\main\res"
for folder, sz in densities.items():
    folder_path = os.path.join(base_dir, folder)
    if os.path.exists(folder_path):
        icon = draw_tenx_icon(sz)
        out_path = os.path.join(folder_path, "ic_launcher.png")
        icon.save(out_path, "PNG")
        print(f"Generated {out_path} ({sz}x{sz})")

print("All TenX launcher icons generated successfully!")
