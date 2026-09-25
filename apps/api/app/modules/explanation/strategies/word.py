"""Word explanation strategy: meaning + concise explanation + example."""

from __future__ import annotations

import string

from app.modules.explanation.enums import SelectionType
from app.modules.explanation.provider import ExplanationProvider
from app.modules.explanation.strategies.base import StrategyResult, limit_sentences
from app.prompts.word_explanation import render_word_explanation_prompt

_MAX_SENTENCES = 3

# Punctuation a text selection commonly drags along with a word ("laptop," or
# a quoted “word”), which would otherwise leak into the prompt.
_EDGE_PUNCTUATION = (
    string.punctuation + "\u2018\u2019\u201c\u201d\u00ab\u00bb\u2013\u2014\u2026"
)


def clean_word(selected_text: str) -> str:
    """Trim surrounding punctuation from a single-word selection."""
    stripped = selected_text.strip()
    core = stripped.strip(_EDGE_PUNCTUATION)
    if not core:
        return stripped
    # Keep the final period of a dotted abbreviation such as "e.g." or "U.S.".
    end = stripped.index(core) + len(core)
    if "." in core and stripped[end : end + 1] == ".":
        core += "."
    return core


class WordExplanationStrategy:
    def __init__(self, provider: ExplanationProvider) -> None:
        self._provider = provider

    @property
    def selection_type(self) -> SelectionType:
        return SelectionType.WORD

    async def explain(
        self,
        *,
        selected_text: str,
        context: str,
        book_title: str,
    ) -> StrategyResult:
        prompt = render_word_explanation_prompt(
            word=clean_word(selected_text), context=context, book_title=book_title
        )
        generated = await self._provider.explain(prompt=prompt)
        return StrategyResult(
            explanation=limit_sentences(generated.explanation, _MAX_SENTENCES),
            meaning=generated.meaning.strip() or None,
            example=generated.example.strip() or None,
        )
