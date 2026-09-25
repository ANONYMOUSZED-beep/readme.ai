"""Prompt template for sentence-level explanations."""

from __future__ import annotations

from app.prompts.sanitize import fence_safe

SENTENCE_EXPLANATION_PROMPT_VERSION = "1.0.0"

_TEMPLATE = """\
You are a concise reading assistant helping someone understand a sentence while \
they read the book "{book_title}".

Explain, in plain English, what the following sentence means. Rules:
- Explain simply, for a general reader.
- Clarify any difficult phrases within the sentence.
- Use the surrounding context; do not invent facts.
- Explain ONLY this sentence, not the wider chapter.
- The explanation must never exceed five sentences.

Sentence:
\"\"\"
{sentence}
\"\"\"

Surrounding context:
\"\"\"
{context}
\"\"\"

Respond ONLY with a JSON object: {{"explanation": string}}
"""


def render_sentence_explanation_prompt(
    *,
    sentence: str,
    context: str,
    book_title: str,
) -> str:
    """Render the sentence-explanation prompt from its template."""
    return _TEMPLATE.format(
        sentence=fence_safe(sentence),
        context=fence_safe(context),
        book_title=fence_safe(book_title) or "this book",
    )
