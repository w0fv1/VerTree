"""Generate platform-sized icons from assets/img/logo/logo.png."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]


def main():
    source = ROOT / 'assets/img/logo/logo.png'
    app_icons = ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    package_icons = ROOT / 'windows/packaging/sparse/Assets'
    targets = {
        **{app_icons / f'app_icon_{size}.png': size
           for size in (16, 32, 64, 128, 256, 512, 1024)},
        package_icons / 'Square44x44Logo.png': 44,
        package_icons / 'Square150x150Logo.png': 150,
        package_icons / 'StoreLogo.png': 50,
        **{package_icons / f'Square44x44Logo.targetsize-{size}{variant}.png': size
           for size in (16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 256)
           for variant in ('', '_altform-unplated', '_altform-lightunplated')},
    }
    with Image.open(source) as original:
        image = original.convert('RGBA')
        if image.width != image.height:
            raise ValueError('The shared logo must be square.')
        for target, size in targets.items():
            target.parent.mkdir(parents=True, exist_ok=True)
            image.resize((size, size), Image.Resampling.LANCZOS).save(target)
            print(f'{target.relative_to(ROOT)}: {size}x{size}')


if __name__ == '__main__':
    main()
