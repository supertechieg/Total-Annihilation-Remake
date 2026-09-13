"""Parse nested TA text-data sections without flattening keys across scopes.

Case-insensitive names; values remain strings. Later duplicate properties replace
earlier ones. Duplicate sections merge. Those duplicate rules are provisional.
"""
from ta_assets import FormatError


def parse(text):
    if isinstance(text, bytes):
        text = text.decode('latin-1')
    cursor = 0
    length = len(text)

    def skip():
        nonlocal cursor
        while cursor < length:
            if text[cursor].isspace() or text[cursor] == '\ufeff':
                cursor += 1
            elif text.startswith('//', cursor):
                end = text.find('\n', cursor)
                cursor = length if end < 0 else end + 1
            elif text.startswith('/*', cursor):
                end = text.find('*/', cursor + 2)
                if end < 0:
                    raise FormatError('Unterminated TDF block comment')
                cursor = end + 2
            else:
                break

    def body(nested=False, depth=0):
        nonlocal cursor
        if depth > 64:
            raise FormatError('Excessive TDF nesting')
        result = {}
        while True:
            skip()
            if cursor == length:
                if nested:
                    raise FormatError('Unclosed TDF section')
                return result
            if text[cursor] == '}':
                if not nested:
                    raise FormatError('Unexpected TDF closing brace')
                cursor += 1
                return result
            if text[cursor] == ';':
                cursor += 1
                continue
            if text[cursor] == '[':
                end = text.find(']', cursor + 1)
                if end < 0:
                    raise FormatError('Unterminated TDF section name')
                name = text[cursor + 1:end].strip().lower()
                cursor = end + 1
                skip()
                if not name or cursor == length or text[cursor] != '{':
                    raise FormatError('TDF section needs a name and opening brace')
                cursor += 1
                section = body(True, depth + 1)
                if name in result and isinstance(result[name], dict):
                    result[name].update(section)
                else:
                    result[name] = section
                continue
            start = cursor
            while cursor < length and text[cursor] not in '=;{}[]':
                cursor += 1
            if cursor == length or text[cursor] != '=':
                raise FormatError(f'Expected TDF assignment near {text[start:start + 50]!r}')
            key = text[start:cursor].strip().lower()
            if not key:
                raise FormatError('Empty TDF property name')
            cursor += 1
            value = []
            quoted = False
            while cursor < length:
                char = text[cursor]
                if char == '"':
                    quoted = not quoted
                elif not quoted and char == ';':
                    cursor += 1
                    break
                elif not quoted and char in '{}':
                    raise FormatError(f'Missing semicolon after {key}')
                value.append(char)
                cursor += 1
            else:
                raise FormatError(f'Unterminated value for {key}')
            if quoted:
                raise FormatError('Unterminated quoted TDF value')
            raw = ''.join(value).strip()
            result[key] = raw[1:-1] if raw.startswith('"') and raw.endswith('"') else raw

    return body()
