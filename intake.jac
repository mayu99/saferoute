"""LLM-based intake parsing for free-text household requests.

parse_request() asks an LLM to pull structured needs out of whatever a
household actually typed. If that call fails or times out (missing API
key, network issue, rate limit, malformed output after retries — any of
it), parse_request_fallback() does the same job with plain keyword
detection instead. intake() is the single entry point api.jac calls: it
never raises, and always returns SOMETHING usable, because a disaster
intake form must not hard-fail on a network blip.
"""

import from byllm.exceptions { ByLLMError }

import from schema { Household, Need, Requires }

obj ParsedNeeds {
    has household_size: int = 1;
    has mobility_support: bool = False;
    has has_pets: bool = False;
    has medical_needs: bool = False;
    has preferred_language: str = "English";
    has urgency: str = "normal";
}

sem ParsedNeeds.household_size = "How many people are in this household, including whoever is speaking.";
sem ParsedNeeds.mobility_support = "True if anyone in the household uses a wheelchair, walker, cane, or other mobility aid, or otherwise has limited mobility.";
sem ParsedNeeds.has_pets = "True if the household has a pet (dog, cat, or other animal) that needs to come with them.";
sem ParsedNeeds.medical_needs = "True if the household mentions a medical condition, medication, or need for medical staff or care.";
sem ParsedNeeds.preferred_language = "The language the household prefers to communicate in, if one is mentioned or implied; otherwise \"English\".";
sem ParsedNeeds.urgency = "One of \"low\", \"normal\", or \"high\" - how urgent the request sounds from its wording.";

def parse_request(raw_text: str) -> ParsedNeeds by llm();
sem parse_request = "Extract structured shelter-intake needs from a household's free-text disaster-relief request.";
sem parse_request.raw_text = "The household's raw free-text request, as typed by an intake worker or the household itself.";

# ─── Deterministic fallback: no network call, no API key, can't fail ───

def guess_household_size(text: str) -> int {
    word_numbers: dict[str, int] = {
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    };
    for (word, n) in word_numbers.items() {
        if f" {word} " in f" {text} " {
            return n;
        }
    }
    for tok in text.split() {
        cleaned = tok.strip(".,!?");
        if cleaned.isdigit() {
            return int(cleaned);
        }
    }
    return 1;
}

def contains_any(text: str, keywords: list) -> bool {
    for kw in keywords {
        if kw in text {
            return True;
        }
    }
    return False;
}

def parse_request_fallback(raw_text: str) -> ParsedNeeds {
    text = raw_text.lower();

    mobility_support = contains_any(
        text, ["wheelchair", "walker", "cane", "crutch", "mobility scooter", "mobility aid"]
    );
    has_pets = contains_any(text, ["pet", "dog", "cat", "puppy", "kitten"]);
    medical_needs = contains_any(
        text,
        ["medical", "medication", "insulin", "oxygen", "diabetic", "prescription", "injury", "injured", "illness"]
    );

    preferred_language = "English";
    for lang in ["spanish", "mandarin", "cantonese", "vietnamese", "tagalog", "russian", "korean", "arabic", "asl"] {
        if lang in text {
            preferred_language = lang.title();
            break;
        }
    }

    urgency = "normal";
    if contains_any(text, ["urgent", "emergency", "immediately", "asap", "critical", "right now"]) {
        urgency = "high";
    }

    return ParsedNeeds(
        household_size=guess_household_size(text),
        mobility_support=mobility_support,
        has_pets=has_pets,
        medical_needs=medical_needs,
        preferred_language=preferred_language,
        urgency=urgency,
    );
}

# ─── Turn a ParsedNeeds into graph state ────────────────────────────

def apply_parsed_needs(hh: Household, parsed: ParsedNeeds) -> list {
    hh.size = parsed.household_size;
    needs: list = [];

    if parsed.mobility_support {
        hh +>:Requires:+> Need(kind="wheelchair");
        needs.append("wheelchair");
    }
    if parsed.has_pets {
        hh +>:Requires:+> Need(kind="pets");
        needs.append("pets");
    }
    if parsed.medical_needs {
        hh +>:Requires:+> Need(kind="medical");
        needs.append("medical");
    }
    lang = parsed.preferred_language.strip();
    if len(lang) > 0 and lang.lower() not in ["english", "en", "none", "unspecified"] {
        hh +>:Requires:+> Need(kind="language", detail=lang);
        needs.append(f"language:{lang}");
    }
    if parsed.urgency.lower() in ["high", "urgent", "critical", "emergency"] {
        hh +>:Requires:+> Need(kind="urgency", detail=parsed.urgency, severity=3);
        needs.append("urgency:high");
    }

    return needs;
}

# ─── Single entry point: try the LLM, fall back on ANY failure ─────

def intake(hh: Household, raw_text: str) -> dict {
    method = "llm";
    try {
        parsed = parse_request(raw_text);
    } except ByLLMError as e {
        print(f"[intake] LLM parse failed ({e}); falling back to keyword detection.");
        parsed = parse_request_fallback(raw_text);
        method = "keyword_fallback";
    } except Exception as e {
        print(f"[intake] LLM parse failed unexpectedly ({e}); falling back to keyword detection.");
        parsed = parse_request_fallback(raw_text);
        method = "keyword_fallback";
    }

    needs = apply_parsed_needs(hh, parsed);
    return {
        "needs": needs,
        "parse_method": method,
        "household_size": parsed.household_size,
        "urgency": parsed.urgency,
    };
}

with entry:__main__ {
    sample = "my mom uses a walker and we can't leave our cat behind, there's four of us";

    print("=== parse_request_fallback() directly ===");
    fallback_result = parse_request_fallback(sample);
    print(
        f"household_size={fallback_result.household_size} "
        f"mobility_support={fallback_result.mobility_support} "
        f"has_pets={fallback_result.has_pets} "
        f"medical_needs={fallback_result.medical_needs} "
        f"preferred_language={fallback_result.preferred_language} "
        f"urgency={fallback_result.urgency}"
    );

    print();
    print("=== parse_request() via LLM, direct ===");
    try {
        llm_result = parse_request(sample);
        print(
            f"household_size={llm_result.household_size} "
            f"mobility_support={llm_result.mobility_support} "
            f"has_pets={llm_result.has_pets} "
            f"medical_needs={llm_result.medical_needs} "
            f"preferred_language={llm_result.preferred_language} "
            f"urgency={llm_result.urgency}"
        );
    } except Exception as e {
        print(f"(LLM call failed here too: {e})");
    }

    print();
    print("=== intake() — the actual entry point api.jac calls ===");
    hh = Household(ref="TEST-1", raw_request=sample);
    root ++> hh;
    result = intake(hh, sample);
    print(f"parse_method={result['parse_method']}");
    print(f"household.size={hh.size}");
    print(f"needs={result['needs']}");
}
