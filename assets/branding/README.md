# Legion mark

`legion_mark.svg` is a vector redraw of the circular O in the [Lenovo Legion
logo on Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Lenovo_Legion_Logo.png).
The source identifies Lenovo as the author and describes the logo as public
domain due to its simple geometry. Lenovo's trademark rights still apply; this
project is not affiliated with or endorsed by Lenovo.

`legion_app.svg` places that mark on a dark tile with a light border so the
desktop icon remains visible on light and dark backgrounds. Packages use it
for the application launcher and window icon.

`legion_app.png` is its 256 × 256 raster copy, used for AppImage thumbnails.
Regenerate it after editing the SVG:

```sh
magick -background none assets/branding/legion_app.svg -resize 256x256 assets/branding/legion_app.png
```
