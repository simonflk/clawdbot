---
name: pdf-text
description: Extract plain text from PDF files.
homepage: https://poppler.freedesktop.org/
metadata: {"clawdbot":{"emoji":"🔤","requires":{"bins":["pdftotext"]},"install":[{"id":"apt","kind":"apt","package":"poppler-utils","bins":["pdftotext"],"label":"Install Poppler Utils (apt)"}]}}
---

# PDF Text Extraction

Use `pdftotext` for fast plain text, or `pdftohtml` for structured data.

## Quick start

### Plain Text
- Extract all text to stdout:
  `pdftotext input.pdf -`
- Maintain physical layout (good for tables):
  `pdftotext -layout input.pdf -`

### Structured (HTML/Markdown-friendly)
- Extract to HTML (complex layouts):
  `pdftohtml -stdout -i -noframes input.pdf`
- Extract to XML (for data processing):
  `pdftotext -bbox input.pdf -` (Outputs bounding boxes for every word)

## Tips
- Use `pdftohtml` if you need to preserve headers, bold text, or links. The agent can then convert this HTML to Markdown.
- Use `pdftotext -layout` for a "What You See Is What You Get" text version.
- If the PDF is a scanned image (no text layer), use the `pdf-to-image` skill instead.
