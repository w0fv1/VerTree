import json
import unittest
from pathlib import Path
from PIL import Image, ImageStat

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'assets/img/icon'


class ActionIconsTest(unittest.TestCase):
    def test_theme_assets_are_distinct_visible_glyphs_with_identical_alpha(self):
        masks = set()
        for action in json.loads((ASSETS / 'actions.json').read_text(encoding='utf-8')):
            with Image.open(ASSETS / f"action-{action['name']}-light.ico") as light_ico:
                with Image.open(ASSETS / f"action-{action['name']}-dark.ico") as dark_ico:
                    for size in (16, 20, 32, 48):
                        light = light_ico.ico.getimage((size, size)).convert('RGBA')
                        dark = dark_ico.ico.getimage((size, size)).convert('RGBA')
                        alpha = light.getchannel('A')
                        self.assertEqual(alpha.tobytes(), dark.getchannel('A').tobytes())
                        self.assertIsNotNone(alpha.getbbox())
                        self.assertLess(ImageStat.Stat(light.convert('L'), alpha).mean[0], 50)
                        self.assertGreater(ImageStat.Stat(dark.convert('L'), alpha).mean[0], 230)
                    masks.add(alpha.tobytes())
        self.assertEqual(len(masks), 11)


if __name__ == '__main__':
    unittest.main()
