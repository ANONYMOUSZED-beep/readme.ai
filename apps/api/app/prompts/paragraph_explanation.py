"""Prompt template for paragraph-level (author intention) explanations."""

from __future__ import annotations

from app.prompts.sanitize import fence_safe

PARAGRAPH_EXPLANATION_PROMPT_VERSION = "1.0.0"

_TEMPLATE = """\
You are a concise reading assistant helping someone understand a paragraph while \
they read the book "{book_title}".

Explain what the author is trying to communicate in the following paragraph. \
Rules:
- State the central idea and any important concepts.
- Explain the author's intended meaning, in plain English.
- Use the surrounding context; do not invent facts.
- Explain ONLY this paragraph. NEVER summarize the entire chapter or book.
- The explanation must never exceed seven sentences.

Paragraph:
\"\"\"
{paragraph}
\"\"\"

Surrounding context:
\"\"\"
{context}
\"\"\"

Respond ONLY with a JSON object: {{"explanation": string}}
"""


def render_paragraph_explanation_prompt(
    *,
    paragraph: str,
    context: str,
    book_title: str,
) -> str:
    """Render the paragraph-explanation prompt from its template."""
    return _TEMPLATE.format(
        paragraph=fence_safe(paragraph),
        context=fence_safe(context),
        book_title=fence_safe(book_title) or "this book",
    )
