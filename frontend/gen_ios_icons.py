import json
import os
from PIL import Image

root = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
logo_path = 'Logo.png'
with Image.open(logo_path) as logo:
    logo = logo.convert('RGBA')
    w, h = logo.size
    print('Logo size', (w, h))
    with open(os.path.join(root, 'Contents.json'), 'r') as f:
        contents = json.load(f)
    for item in contents['images']:
        filename = item.get('filename')
        if not filename:
            continue
        size_str = item['size']
        scale = int(item['scale'].replace('x', ''))
        base_size = float(size_str.split('x')[0])
        target = int(base_size * scale)
        target = max(target, 1)
        canvas = Image.new('RGBA', (target, target), (0, 0, 0, 0))
        ratio = min(target / w, target / h)
        new_w = int(w * ratio)
        new_h = int(h * ratio)
        resized = logo.resize((new_w, new_h), Image.LANCZOS)
        paste_x = (target - new_w) // 2
        paste_y = (target - new_h) // 2
        canvas.paste(resized, (paste_x, paste_y), resized)
        out_path = os.path.join(root, filename)
        canvas.save(out_path, format='PNG')
        print('Generated', filename, 'size', target)
    print('Icons updated in', root)
