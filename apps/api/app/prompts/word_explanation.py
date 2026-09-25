"""Prompt template for single-word contextual explanations."""

from __future__ import annotations

from app.prompts.sanitize import fence_safe

# Bump when the template changes so cached/observed outputs can be attributed.
WORD_EXPLANATION_PROMPT_VERSION = "1.0.0"

_TEMPLATE = """\
You are a concise reading assistant helping someone understand a single word \
while they read the book "{book_title}".

Explain the word "{word}" as it is used in the passage below. Rules:
- Explain simply, for a general reader.
- Be concise: the explanation must never exceed three sentences.
- Use the passage context; do not invent facts or definitions.
- If unsure, give the most common meaning rather than guessing specifics.
- Provide one short example related to the book's context when possible.

Passage:
\"\"\"
{context}
\"\"\"

Respond ONLY with a JSON object using exactly these keys:
{{"word": string, "meaning": string, "explanation": string, "example": string}}
- "meaning": a brief definition (a few words).
- "explanation": at most three sentences.
- "example": one short sentence, or an empty string if none applies.
"""


def render_word_explanation_prompt(
    *,
    word: str,
    context: str,
    book_title: str,
) -> str:
    """Render the word-explanation prompt from its template."""
    return _TEMPLATE.format(
        word=fence_safe(word),
        context=fence_safe(context),
        book_title=fence_safe(book_title) or "this book",
    )
