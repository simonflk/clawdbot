---
name: pdf-to-image
description: Convert PDF pages to images (PNG/JPEG) for processing by vision-capable models.
homepage: https://poppler.freedesktop.org/
metadata: {"clawdbot":{"emoji":"📄","requires":{"bins":["pdftocairo"]},"install":[{"id":"apt","kind":"apt","package":"poppler-utils","bins":["pdftocairo"],"label":"Install Poppler Utils (apt)"}]}}
---

# PDF to Image

Use `pdftocairo` to convert PDF pages into images. This is useful for models like z.ai that can process images but not raw PDFs.

## Quick start

- Convert first page to PNG:
  `pdftocairo -png -singlefile input.pdf output` (creates `output.png`)
- Convert all pages to PNG (numbered):
  `pdftocairo -png input.pdf page` (creates `page-1.png`, `page-2.png`, etc.)
- Convert to JPEG with specific resolution (DPI):
  `pdftocairo -jpeg -r 300 input.pdf output`

## Tips
- Use `-singlefile` if you only need the first page to save processing time.
- Standard DPI is 150; use `-r 300` for high-detail documents.
- If the model has a small context window, prefer converting only the relevant pages using `-f <page>` and `-l <page>`.
