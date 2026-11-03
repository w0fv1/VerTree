from pathlib import Path
from typing import Literal
from PIL import Image, ImageFilter, ImageOps


ROOT = Path(__file__).resolve().parents[1]


def render_logo(image: Image.Image, size: int, theme: Literal['default', 'dark', 'light']) -> Image.Image:
    result = image.resize((size, size), Image.Resampling.LANCZOS)
    if theme == 'dark':
        inverted = ImageOps.invert(result.convert('RGB')).convert('RGBA')
        inverted.putalpha(result.getchannel('A'))
        return inverted
    if theme == 'default':
        radius = max(1, size // 128)
        inset = radius + 1
        result = Image.new('RGBA', (size, size))
        result.alpha_composite(image.resize((size - 2 * inset, size - 2 * inset), Image.Resampling.LANCZOS), (inset, inset))
        outline = Image.new('RGBA', result.size, (255, 255, 255, 0))
        outline.putalpha(result.getchannel('A').filter(ImageFilter.MaxFilter(2 * radius + 1)))
        return Image.alpha_composite(outline, result)
    return result


def generate_assets(root: Path = ROOT) -> None:
    source = root / 'assets/img/logo/logo.png'
    app_icons = root / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    package_icons = root / 'windows/packaging/sparse/Assets'
    targets = {
        **{app_icons / f'app_icon_{size}.png': size
           for size in (16, 32, 64, 128, 256, 512, 1024)},
        package_icons / 'Square44x44Logo.png': 44,
        package_icons / 'Square150x150Logo.png': 150,
        package_icons / 'StoreLogo.png': 50,
    }
    with Image.open(source) as original:
        image = original.convert('RGBA')
        if image.width != image.height:
            raise ValueError('The shared logo must be square.')
        for target, size in targets.items():
            target.parent.mkdir(parents=True, exist_ok=True)
            render_logo(image, size, 'default' if target.parent == package_icons else 'light').save(target)
        for size in (16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 256):
            for variant, theme in [('', 'default'), ('_altform-unplated', 'dark'), ('_altform-lightunplated', 'light')]:
                render_logo(image, size, theme).save(package_icons / f'Square44x44Logo.targetsize-{size}{variant}.png')
        sizes = [(size, size) for size in (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)]
        for filename, theme in [('logo.ico', 'default'), ('logo-dark.ico', 'dark'), ('logo-light.ico', 'light')]:
            frames = [render_logo(image, size, theme) for size, _ in sizes]
            frames[-1].save(source.with_name(filename), format='ICO', sizes=sizes, append_images=frames[:-1])


if __name__ == '__main__':
    generate_assets()
