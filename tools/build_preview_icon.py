"""Rasterize the pinned Microsoft Fluent Eye SVG into Windows menu icon sizes.

Source: microsoft/fluentui-system-icons, assets/Eye/SVG/ic_fluent_eye_24_regular.svg.
The asset's MIT license is assets/img/icon/LICENSE-fluent-icons.txt.
Requires Pillow. Does not download assets or modify the source SVG.
"""
from pathlib import Path
import hashlib
import re
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets' / 'img' / 'icon'
SVG = ASSETS / 'preview.svg'
EXPECTED = '4a9ca45d072c986e159b46c9c19d4290463edabc507db07c28e46f64bddefb47'

def main() -> None:
    source = SVG.read_bytes()
    if hashlib.sha256(source).hexdigest() != EXPECTED:
        raise ValueError('Unexpected SVG: review its geometry before updating the pinned digest')
    node = ET.fromstring(source).find('{http://www.w3.org/2000/svg}path')
    assert node is not None
    tokens = re.findall(r'[MCZ]|[-+]?(?:\d*\.\d+|\d+)', node.attrib['d'])
    contours, points = [], []
    index = 0
    current = (0.0, 0.0)
    while index < len(tokens):
        command = tokens[index]; index += 1
        if command == 'M':
            current = tuple(map(float, tokens[index:index + 2])); index += 2
            points = [current]
        elif command == 'C':
            coords = list(map(float, tokens[index:index + 6])); index += 6
            a, b, end = coords[:2], coords[2:4], coords[4:]
            for step in range(1, 65):
                t = step / 64; u = 1 - t
                points.append(tuple(u**3 * current[k] + 3*u*u*t*a[k] +
                                    3*u*t*t*b[k] + t**3 * end[k] for k in (0, 1)))
            current = tuple(end)
        elif command == 'Z':
            contours.append(points)
        else:
            raise ValueError(f'Unsupported path operation: {command}')
    if len(contours) != 3:
        raise ValueError('Expected iris, iris cutout and upper eyelid contours')
    scale = 1024 / 24
    mask = Image.new('L', (1024, 1024))
    draw = ImageDraw.Draw(mask)
    for contour, fill in zip(contours, [255, 0, 255]):
        draw.polygon([(round(x*scale), round(y*scale)) for x, y in contour], fill=fill)
    image = Image.new('RGBA', mask.size, (33, 33, 33, 0))
    image.putalpha(mask)
    image = image.resize((256, 256), Image.Resampling.LANCZOS)
    image.save(ASSETS / 'preview.png')
    image.save(ASSETS / 'preview.ico', sizes=[(n, n) for n in (16, 20, 24, 32, 40, 48, 64, 128, 256)])
    print('Updated preview.png and preview.ico from the pinned Fluent Eye SVG')

if __name__ == '__main__':
    main()
