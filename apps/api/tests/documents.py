"""Builders for small, genuine PDF and EPUB files used as test fixtures.

The files are generated in memory (no binary fixtures in the repository) and
are valid enough for real parsers: the PDF has a correct cross-reference table
and the EPUB carries a proper container, package document, and spine.
"""

from __future__ import annotations

import io
import zipfile


def _pdf_string(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    return f"({escaped})"


def make_pdf(
    pages: list[list[str]],
    *,
    title: str | None = None,
    author: str | None = None,
) -> bytes:
    """Build a text PDF with one entry per page, each a list of lines."""
    page_count = len(pages)
    font_id = 3 + 2 * page_count
    info_id = font_id + 1
    objects: dict[int, bytes] = {
        1: b"<< /Type /Catalog /Pages 2 0 R >>",
        2: (
            "<< /Type /Pages /Kids ["
            + " ".join(f"{3 + 2 * i} 0 R" for i in range(page_count))
            + f"] /Count {page_count} >>"
        ).encode(),
        font_id: b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    }
    for index, lines in enumerate(pages):
        page_id, content_id = 3 + 2 * index, 4 + 2 * index
        operations = ["BT", "/F1 11 Tf", "14 TL", "72 740 Td"]
        for line in lines:
            operations.append(f"{_pdf_string(line)} Tj T*")
        operations.append("ET")
        stream = "\n".join(operations).encode("latin-1")
        objects[page_id] = (
            f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            f"/Contents {content_id} 0 R "
            f"/Resources << /Font << /F1 {font_id} 0 R >> >> >>"
        ).encode()
        objects[content_id] = (
            f"<< /Length {len(stream)} >>\nstream\n".encode() + stream + b"\nendstream"
        )

    trailer_info = ""
    if title is not None or author is not None:
        fields = []
        if title is not None:
            fields.append(f"/Title {_pdf_string(title)}")
        if author is not None:
            fields.append(f"/Author {_pdf_string(author)}")
        objects[info_id] = f"<< {' '.join(fields)} >>".encode("latin-1")
        trailer_info = f" /Info {info_id} 0 R"

    output = io.BytesIO()
    output.write(b"%PDF-1.4\n")
    offsets: dict[int, int] = {}
    for number in sorted(objects):
        offsets[number] = output.tell()
        output.write(f"{number} 0 obj\n".encode() + objects[number] + b"\nendobj\n")
    xref_offset = output.tell()
    size = max(objects) + 1
    output.write(f"xref\n0 {size}\n0000000000 65535 f \n".encode())
    for number in range(1, size):
        if number in offsets:
            output.write(f"{offsets[number]:010d} 00000 n \n".encode())
        else:
            output.write(b"0000000000 65535 f \n")
    output.write(
        f"trailer\n<< /Size {size} /Root 1 0 R{trailer_info} >>\n"
        f"startxref\n{xref_offset}\n%%EOF\n".encode()
    )
    return output.getvalue()


_CONTAINER = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf"
      media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""


def make_epub(
    chapters: list[str],
    *,
    title: str = "Test Book",
    author: str = "Ada Author",
    language: str = "en",
    encrypted: bool = False,
    extra_manifest: str = "",
    extra_spine: str = "",
) -> bytes:
    """Build an EPUB whose spine holds one XHTML document per ``chapters`` body."""
    manifest = "\n".join(
        f'<item id="c{i}" href="text/chapter%20{i}.xhtml" '
        'media-type="application/xhtml+xml"/>'
        for i in range(len(chapters))
    )
    spine = "\n".join(f'<itemref idref="c{i}"/>' for i in range(len(chapters)))
    opf = f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="id">urn:uuid:test</dc:identifier>
    <dc:title>{title}</dc:title>
    <dc:creator>{author}</dc:creator>
    <dc:language>{language}</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml"
      properties="nav"/>
    {manifest}
    {extra_manifest}
  </manifest>
  <spine>
    <itemref idref="nav"/>
    {spine}
    {extra_spine}
  </spine>
</package>
"""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr(
            "mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED
        )
        archive.writestr("META-INF/container.xml", _CONTAINER)
        archive.writestr("OEBPS/content.opf", opf)
        archive.writestr(
            "OEBPS/nav.xhtml",
            "<html><body><nav><ol><li>Table of contents</li></ol></nav>"
            "</body></html>",
        )
        for index, body in enumerate(chapters):
            archive.writestr(
                f"OEBPS/text/chapter {index}.xhtml",
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<html xmlns="http://www.w3.org/1999/xhtml">'
                f"<head><title>Chapter {index}</title>"
                "<style>p { color: red; }</style></head>"
                f"<body>{body}</body></html>",
            )
        if encrypted:
            archive.writestr(
                "META-INF/encryption.xml",
                '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"'
                ' xmlns:enc="http://www.w3.org/2001/04/xmlenc#">'
                "<enc:EncryptedData><enc:CipherData>"
                '<enc:CipherReference URI="OEBPS/text/chapter%200.xhtml"/>'
                "</enc:CipherData></enc:EncryptedData></encryption>",
            )
    return buffer.getvalue()
