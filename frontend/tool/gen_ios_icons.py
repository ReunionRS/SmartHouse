import json
from pathlib import Path

from PIL import Image


project_root = Path(__file__).resolve().parent.parent
icon_directory = project_root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
logo_path = project_root / "Logo.png"

with Image.open(logo_path) as source:
    logo = source.convert("RGBA")
    width, height = logo.size
    print("Logo size", (width, height))

    with (icon_directory / "Contents.json").open(encoding="utf-8") as file:
        contents = json.load(file)

    for item in contents["images"]:
        filename = item.get("filename")
        if not filename:
            continue

        scale = int(item["scale"].removesuffix("x"))
        base_size = float(item["size"].split("x")[0])
        target = max(int(base_size * scale), 1)
        canvas = Image.new("RGBA", (target, target), (0, 0, 0, 0))
        ratio = min(target / width, target / height)
        resized = logo.resize(
            (int(width * ratio), int(height * ratio)),
            Image.Resampling.LANCZOS,
        )
        position = ((target - resized.width) // 2, (target - resized.height) // 2)
        canvas.paste(resized, position, resized)
        canvas.save(icon_directory / filename, format="PNG")
        print("Generated", filename, "size", target)

    print("Icons updated in", icon_directory)
