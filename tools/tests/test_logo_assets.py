import tempfile
import unittest
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from tools.sync_logo_assets import generate_assets


class LogoAssetsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.root = Path(cls.directory.name)
        source = Path(__file__).resolve().parents[2] / 'assets/img/logo/logo.svg'
        target = cls.root / 'assets/img/logo/logo.svg'
        target.parent.mkdir(parents=True)
        target.write_bytes(source.read_bytes())
        cls.source_bytes = source.read_bytes()
        generate_assets(cls.root)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def test_theme_variants_preserve_alpha_and_invert_visible_rgb(self):
        assets = self.root / 'windows/packaging/sparse/Assets'
        for size in (16, 24, 48, 256):
            with Image.open(assets / f'Square44x44Logo.targetsize-{size}_altform-unplated.png') as dark:
                with Image.open(assets / f'Square44x44Logo.targetsize-{size}_altform-lightunplated.png') as light:
                    self.assertEqual(dark.getchannel('A').tobytes(), light.getchannel('A').tobytes())
                    mask = light.getchannel('A').point(lambda value: 255 if value == 255 else 0)
                    combined = ImageChops.add(dark.convert('RGB'), light.convert('RGB'))
                    self.assertEqual(ImageStat.Stat(combined, mask).mean, [255, 255, 255])
                    self.assertGreater(ImageStat.Stat(dark.convert('L'), mask).mean[0], 180)
                    self.assertLess(ImageStat.Stat(light.convert('L'), mask).mean[0], 75)

    def test_default_icon_preserves_source_color_without_outline(self):
        with Image.open(self.root / 'assets/img/logo/logo.ico') as icon:
            self.assertTrue({(16, 16), (24, 24), (32, 32), (48, 48), (256, 256)} <= icon.ico.sizes())
            for size in (16, 24, 32, 48):
                frame = icon.ico.getimage((size, size)).convert('RGBA')
                self.assertEqual(frame.getpixel((0, 0))[3], 0)
                pixels = [frame.getpixel((x, y)) for y in range(size) for x in range(size)]
                self.assertTrue(any(a > 200 for r, g, b, a in pixels))
                self.assertTrue(all(40 <= r <= 55 and r == g == b for r, g, b, a in pixels if a > 200))
                with Image.open(self.root / 'assets/img/logo/logo-light.ico') as light:
                    self.assertEqual(frame.tobytes(), light.ico.getimage((size, size)).convert('RGBA').tobytes())

    def test_generated_icos_match_their_package_theme(self):
        for name, variant in [('logo-dark.ico', 'unplated'), ('logo-light.ico', 'lightunplated')]:
            with Image.open(self.root / 'assets/img/logo' / name) as icon:
                with Image.open(self.root / f'windows/packaging/sparse/Assets/Square44x44Logo.targetsize-32_altform-{variant}.png') as package:
                    self.assertEqual(icon.ico.getimage((32, 32)).convert('RGBA').tobytes(), package.convert('RGBA').tobytes())
        self.assertEqual((self.root / 'assets/img/logo/logo.svg').read_bytes(), self.source_bytes)
        with Image.open(self.root / 'assets/img/logo/logo.png') as image:
            self.assertEqual(image.size, (1024, 1024))
            self.assertEqual(image.getpixel((287, 249))[3], 0)


if __name__ == '__main__':
    unittest.main()
