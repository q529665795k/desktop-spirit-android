#!/usr/bin/env python3
# 扫描 assets/ 下所有含 PNG / WAV 的子目录，自动重写 pubspec.yaml 的 flutter assets 声明。
# 背景：pubspec 里 "- assets/" 只包含 assets 根目录下的直接文件，不递归子目录；
# 本项目素材全在 assets/<动作>/ 与 assets/sfx/ 子目录里，导致 AssetManifest 为空、0 张图/0 个音效入包。
# 本脚本在 CI 的 flutter create / pub get 之后、build 之前运行，确定性生成全部目录声明。
import os

PUBSPEC = 'pubspec.yaml'
ASSETS_ROOT = 'assets'
EXTS = ('.png', '.wav')


def has_asset(files):
    return any(f.lower().endswith(EXTS) for f in files)


dirs = []
for root, _, files in os.walk(ASSETS_ROOT):
    if has_asset(files):
        rel = root.replace('\\', '/').rstrip('/') + '/'
        dirs.append(rel)
dirs = sorted(set(dirs))

block = 'flutter:\n'
block += '  uses-material-design: true\n'
block += '  assets:\n'
for d in dirs:
    block += '    - %s\n' % d

s = open(PUBSPEC, encoding='utf-8').read()
idx = s.find('\nflutter:')
if idx == -1:
    head = s.rstrip() + '\n\n'
else:
    head = s[:idx + 1]

open(PUBSPEC, 'w', encoding='utf-8').write(head + block)

counts = {'.png': 0, '.wav': 0}
for _, _, fs in os.walk(ASSETS_ROOT):
    for f in fs:
        low = f.lower()
        for e in EXTS:
            if low.endswith(e):
                counts[e] += 1
print('declared %d asset dirs, png=%d wav=%d'
      % (len(dirs), counts['.png'], counts['.wav']))
for d in dirs:
    print('  -', d)