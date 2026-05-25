function fail(message) {
  print "Invalid VCAP_SERVICES JSON: " message > "/dev/stderr"
  exit 1
}

function add_token(type, value) {
  token_count++
  token_type[token_count] = type
  token_value[token_count] = value
}

function scan_string(    value, escape, hex) {
  value = ""
  cursor++

  while (cursor <= input_length) {
    char = substr(input, cursor, 1)

    if (char == "\"") {
      add_token("string", value)
      cursor++
      return
    }

    if (char == "\\") {
      cursor++
      if (cursor > input_length) {
        fail("unterminated string escape")
      }

      escape = substr(input, cursor, 1)
      if (escape == "\"" || escape == "\\" || escape == "/") {
        value = value escape
      } else if (escape == "b") {
        value = value "\b"
      } else if (escape == "f") {
        value = value "\f"
      } else if (escape == "n") {
        value = value "\n"
      } else if (escape == "r") {
        value = value "\r"
      } else if (escape == "t") {
        value = value "\t"
      } else if (escape == "u") {
        hex = substr(input, cursor + 1, 4)
        if (hex !~ /^[0-9a-fA-F]{4}$/) {
          fail("invalid unicode escape")
        }
        value = value "\\u" hex
        cursor += 4
      } else {
        fail("invalid string escape")
      }
    } else {
      value = value char
    }

    cursor++
  }

  fail("unterminated string")
}

function scan_literal(expected) {
  if (substr(input, cursor, length(expected)) != expected) {
    fail("invalid token")
  }
  add_token("literal", expected)
  cursor += length(expected)
}

function scan_number(    start) {
  start = cursor
  while (cursor <= input_length && substr(input, cursor, 1) ~ /[-+0-9.eE]/) {
    cursor++
  }
  add_token("number", substr(input, start, cursor - start))
}

function tokenize() {
  cursor = 1

  while (cursor <= input_length) {
    char = substr(input, cursor, 1)

    if (char ~ /[[:space:]]/) {
      cursor++
    } else if (char == "\"") {
      scan_string()
    } else if (char ~ /[{}\[\]:,]/) {
      add_token(char, char)
      cursor++
    } else if (substr(input, cursor, 1) ~ /[-0-9]/) {
      scan_number()
    } else if (substr(input, cursor, 4) == "true") {
      scan_literal("true")
    } else if (substr(input, cursor, 5) == "false") {
      scan_literal("false")
    } else if (substr(input, cursor, 4) == "null") {
      scan_literal("null")
    } else {
      fail("unexpected character")
    }
  }
}

function token_is(type) {
  return token_type[position] == type
}

function expect(type,    value) {
  if (!token_is(type)) {
    fail("expected " type)
  }
  value = token_value[position]
  position++
  return value
}

function skip_value() {
  if (token_is("{")) {
    skip_object()
  } else if (token_is("[")) {
    skip_array()
  } else if (token_is("string") || token_is("number") || token_is("literal")) {
    position++
  } else {
    fail("expected value")
  }
}

function skip_object() {
  expect("{")
  if (token_is("}")) {
    expect("}")
    return
  }

  while (1) {
    expect("string")
    expect(":")
    skip_value()

    if (token_is("}")) {
      expect("}")
      return
    }
    expect(",")
  }
}

function skip_array() {
  expect("[")
  if (token_is("]")) {
    expect("]")
    return
  }

  while (1) {
    skip_value()

    if (token_is("]")) {
      expect("]")
      return
    }
    expect(",")
  }
}

function parse_string_value(    value) {
  if (!token_is("string")) {
    skip_value()
    return ""
  }
  value = token_value[position]
  position++
  return value
}

function parse_tags(    tags, tag) {
  tags = ""

  if (!token_is("[")) {
    skip_value()
    return tags
  }

  expect("[")
  if (token_is("]")) {
    expect("]")
    return tags
  }

  while (1) {
    if (token_is("string")) {
      tag = tolower(token_value[position])
      tags = tags "|" tag "|"
      position++
    } else {
      skip_value()
    }

    if (token_is("]")) {
      expect("]")
      return tags
    }
    expect(",")
  }
}

function parse_credentials(    key, url) {
  url = ""

  if (!token_is("{")) {
    skip_value()
    return url
  }

  expect("{")
  if (token_is("}")) {
    expect("}")
    return url
  }

  while (1) {
    key = expect("string")
    expect(":")

    if (key == "certificate_authority_url") {
      url = parse_string_value()
    } else {
      skip_value()
    }

    if (token_is("}")) {
      expect("}")
      return url
    }
    expect(",")
  }
}

function binding_matches(label, name, tags) {
  return label == "csb-aws-aurora-postgresql" ||
    name == "csb-aws-aurora-postgresql" ||
    (index(tags, "|aurora|") && (index(tags, "|postgres|") || index(tags, "|postgresql|")))
}

function parse_binding(    key, label, name, tags, url) {
  label = ""
  name = ""
  tags = ""
  url = ""

  expect("{")
  if (token_is("}")) {
    expect("}")
    return
  }

  while (1) {
    key = expect("string")
    expect(":")

    if (key == "label") {
      label = parse_string_value()
    } else if (key == "name") {
      name = parse_string_value()
    } else if (key == "tags") {
      tags = parse_tags()
    } else if (key == "credentials") {
      url = parse_credentials()
    } else {
      skip_value()
    }

    if (token_is("}")) {
      expect("}")
      if (url != "" && binding_matches(label, name, tags) && !(url in seen_urls)) {
        seen_urls[url] = 1
        print url
      }
      return
    }
    expect(",")
  }
}

function parse_service_array() {
  expect("[")
  if (token_is("]")) {
    expect("]")
    return
  }

  while (1) {
    if (token_is("{")) {
      parse_binding()
    } else {
      skip_value()
    }

    if (token_is("]")) {
      expect("]")
      return
    }
    expect(",")
  }
}

function parse_root(    key) {
  expect("{")
  if (token_is("}")) {
    expect("}")
    return
  }

  while (1) {
    key = expect("string")
    expect(":")

    if (token_is("[")) {
      parse_service_array()
    } else {
      skip_value()
    }

    if (token_is("}")) {
      expect("}")
      return
    }
    expect(",")
  }
}

BEGIN {
  input = ENVIRON["VCAP_SERVICES"]
  if (input ~ /^[[:space:]]*$/) {
    exit 0
  }

  input_length = length(input)
  tokenize()
  position = 1
  parse_root()

  if (position <= token_count) {
    fail("unexpected trailing content")
  }
}
