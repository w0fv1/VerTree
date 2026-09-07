# Logo 资源

只维护两份公共源文件：

- `assets/img/logo/logo.png`：界面、Linux、非 Windows 托盘和官网。
- `assets/img/logo/logo.ico`：Windows EXE、菜单、安装器、快捷方式、托盘和官网 favicon。

官网通过 Docusaurus `staticDirectories` 直接读取公共目录，不再在 `docs/static` 维护副本。`docs/build/logo.png` 和 `logo.ico` 是网站构建产物。

macOS AppIcon 需要多个尺寸，Windows 包身份需要 44、150 和 50 像素的 PNG。这些文件保留在平台要求的目录，但全部由公共 PNG 生成，不单独编辑。Dock 复用 AppIcon。

Windows 任务栏还需要 `targetsize`、`altform-unplated` 和 `altform-lightunplated` 资源，否则系统可能为透明图标加上底板。这些同样由脚本生成，不是新的 Logo 源。Windows 打包脚本自动调用 `windows/build_icon_resources.ps1` 生成 `resources.pri`，让系统按尺寸和主题选择无底板资源。手动运行 Inno Setup 前也需执行该脚本。

运行窗口通过 `System.AppUserModel.RelaunchIconResource` 指定公共 ICO，并使用 `dev.w0fv1.vertree.desktop` 作为任务栏应用标识；EXE/MSI 安装器创建的快捷方式使用同一个标识，避免升级后仍选取旧的图标关联。仅替换包图片或发送 `WM_SETICON` 不足以修复这种情况。

修改公共 PNG 后，在仓库根目录执行：

```bash
python -m pip install Pillow
python tools/sync_logo_assets.py
```

将平台生成文件与源图一起提交，再重新构建相应平台。普通克隆与构建直接使用已提交的生成文件，无须安装 Pillow。Windows 的 ICO 引用直接指向公共文件，无须另行复制或生成。

现有源 PNG 是 256 × 256；生成 512 / 1024 版本仅满足平台资源尺寸要求，不会增加原图细节。后续更新高清源图时仍替换同一个文件即可。
