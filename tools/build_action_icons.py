import argparse
import json
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]


def generate(sdk: Path, root: Path = ROOT) -> None:
    assets = root / 'assets/img/icon'
    actions = json.loads((assets / 'actions.json').read_text(encoding='utf-8'))
    definitions = (sdk / 'packages/flutter/lib/src/material/icons.dart').read_text(encoding='utf-8')
    font_root = sdk / 'bin/cache/artifacts/material_fonts'
    font = ImageFont.truetype(str(font_root / 'materialicons-regular.otf'), 768)
    dart = ["import 'package:flutter/material.dart';", '', 'enum AppActionIcon {']
    header = ['#pragma once', '', '#define VERTREE_DARK_ICON_OFFSET 1000']
    resources = ['#include "resource.h"', '']
    for action in actions:
        name, material, resource, symbol = (action[k] for k in ('name', 'material', 'resourceId', 'symbol'))
        match = re.search(r'static const IconData ' + re.escape(material) + r' = IconData\((0x[0-9a-f]+),', definitions)
        if match is None:
            raise ValueError(f'Unknown Material icon: {material}')
        glyph = chr(int(match[1], 16))
        mask = Image.new('L', (1024, 1024))
        draw = ImageDraw.Draw(mask)
        left, top, right, bottom = draw.textbbox((0, 0), glyph, font=font)
        draw.text(((1024-right-left)/2, (1024-bottom-top)/2), glyph, font=font, fill=255)
        if not mask.getbbox():
            raise ValueError(f'Empty glyph: {material}')
        sizes = [(n, n) for n in (16, 20, 24, 32, 40, 48, 64, 128, 256)]
        for variant, color in [('light', (32, 32, 32)), ('dark', (245, 245, 245)), ('neutral', (32, 32, 32))]:
            frames = []
            for size, _ in sizes:
                alpha = mask.resize((size, size), Image.Resampling.LANCZOS)
                frame = Image.new('RGBA', (size, size), (*color, 0))
                frame.putalpha(alpha)
                if variant == 'neutral':
                    outline = Image.new('RGBA', (size, size), (245, 245, 245, 0))
                    outline.putalpha(alpha.filter(ImageFilter.MaxFilter(3)))
                    frame = Image.alpha_composite(outline, frame)
                frames.append(frame)
            filename = f'action-{name}' + ('' if variant == 'neutral' else f'-{variant}')
            frames[-1].save(assets / f'{filename}.ico', sizes=sizes, append_images=frames[:-1])
            if variant == 'neutral':
                frames[5].save(assets / f'{filename}.png')
        dart.append(f'  {name}(Icons.{material})' + (';' if action == actions[-1] else ','))
        header.append(f'#define IDI_VERTREE_{symbol} {resource}')
        for suffix, offset in [('light', 0), ('dark', 1000)]:
            resources.append(f'{resource+offset} ICON "../../assets/img/icon/action-{name}-{suffix}.ico"')
    dart.extend(['', '  const AppActionIcon(this.data);', '  final IconData data;', '', "  String asset({String extension = 'png'}) =>", "      'assets/img/icon/action-$name.$extension';", '}', ''])
    (root / 'lib/component/action_icons.dart').write_text('\n'.join(dart), encoding='utf-8')
    (root / 'windows/context_menu/action_icons.h').write_text('\n'.join(header)+'\n', encoding='utf-8')
    (root / 'windows/context_menu/action_icons.rc').write_text('\n'.join(resources)+'\n', encoding='utf-8')
    (assets / 'LICENSE-material-icons.txt').write_bytes((font_root / 'materialicons_license.txt').read_bytes())


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--flutter-sdk', required=True, type=Path)
    generate(parser.parse_args().flutter_sdk)
