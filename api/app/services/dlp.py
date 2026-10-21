"""DLP masking of CSV exports (PRD FR-6.4; agreed with the lead, 19 Oct 2026).

A0 DRAFT, NEEDS ARCHITECT REVIEW (CONSTITUTION BC-09: DLP is human-written).

The exports are for what was extracted, not who did it, so personal data is masked:
- people's names in the name columns (Captured by, Decided by, Who): "Tara Tech" -> "T*** T***";
- in every text cell: email addresses ("tara@ppg.com" -> "t***@ppg.com"), phone numbers
  ("+15550100001" -> "+1******0001") and the names of the company's own users.
Limit: a name typed into a field value is caught only if it belongs to a user of the company.
Phone numbers are matched only in an international (+...) or (555) 010-0001 style, so a
serial number made of digits is not taken for one. DLP results are not stored (OPEN O-14);
the counts go into the export's audit row."""

import re
from dataclasses import dataclass, field

EMAIL = re.compile(r"\b([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b")
PHONE = re.compile(
    r"(?<![\w+])\+\d[\d\s().-]{6,18}\d(?!\w)"  # +15550100001, +1 555 010 0001
    r"|(?<!\w)\(\d{3}\)\s?\d{3}[\s.-]\d{4}(?!\w)"  # (555) 010-0001
    r"|(?<![\w-])\d{3}[.-]\d{3}[.-]\d{4}(?![\w-])"  # 555-010-0001
)
NOT_A_PERSON = {"", "System"}


def mask_name(name: str) -> str:
    return " ".join(f"{word[0]}***" for word in name.split())


def _mask_phone(match: re.Match[str]) -> str:
    text = match.group(0)
    digits = [i for i, ch in enumerate(text) if ch.isdigit()]
    keep = set(digits[-4:]) | ({digits[0]} if text.startswith("+") else set())
    return "".join("*" if i in digits and i not in keep else ch for i, ch in enumerate(text))


@dataclass
class Masker:
    """One per export: masks values and counts what it masked."""

    known_names: list[str] = field(default_factory=list)
    counts: dict[str, int] = field(default_factory=lambda: {"names": 0, "emails": 0, "phones": 0})

    def __post_init__(self) -> None:
        names = sorted({n.strip() for n in self.known_names if len(n.strip()) >= 3}, key=len)
        self._names = (
            re.compile(
                r"(?<!\w)(" + "|".join(re.escape(n) for n in reversed(names)) + r")(?!\w)",
                re.IGNORECASE,
            )
            if names
            else None
        )

    def name(self, value: object) -> object:
        """A cell of a name column."""
        if not isinstance(value, str) or value.strip() in NOT_A_PERSON:
            return value
        self.counts["names"] += 1
        return mask_name(value)

    def _count(self, kind: str, replace: str) -> str:
        self.counts[kind] += 1
        return replace

    def text(self, value: object) -> object:
        """Any other cell: emails, phone numbers and known names inside it."""
        if not isinstance(value, str) or not value:
            return value
        text = EMAIL.sub(lambda m: self._count("emails", f"{m.group(1)}***@{m.group(2)}"), value)
        text = PHONE.sub(lambda m: self._count("phones", _mask_phone(m)), text)
        if self._names is not None:
            text = self._names.sub(lambda m: self._count("names", mask_name(m.group(0))), text)
        return text

    def summary(self) -> str:
        """For the audit row: "masked 3 names, 1 email" or "nothing masked"."""
        parts = [f"{n} {kind[:-1] if n == 1 else kind}" for kind, n in self.counts.items() if n]
        return "masked " + ", ".join(parts) if parts else "nothing masked"
