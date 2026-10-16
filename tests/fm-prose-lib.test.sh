#!/usr/bin/env bash
# fm_prose_dense_token: run-together tokens in steering text and brief specs.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-prose-lib.sh
. "$ROOT/bin/fm-prose-lib.sh"

assert_flagged() { # <text> <expected-token>
  local out
  out=$(fm_prose_dense_token "$1") || fail "expected '$1' to be flagged"
  [ "$out" = "$2" ] || fail "expected '$1' to flag '$2', got '$out'"
}

assert_clean() { # <text>
  local out
  if out=$(fm_prose_dense_token "$1"); then
    fail "expected '$1' to pass, but it flagged '$out'"
  fi
  [ -z "$out" ] || fail "a clean verdict must print nothing, got '$out'"
}

test_digit_then_letters_is_flagged() {
  assert_flagged '4focused' 4focused
  assert_flagged '58existing' 58existing
  assert_flagged 'PR11borrow' PR11borrow
  assert_flagged '2spent' 2spent
  assert_flagged 'status 2spent and 4focused' 2spent
  pass "fm-prose-lib: a digit followed by four or more letters is flagged"
}

test_long_letter_run_is_flagged() {
  assert_flagged 'exactwordsaboveONCEagainplease' exactwordsaboveONCEagainplease
  assert_flagged 'abcdefghijklmnopqrstuvwx' abcdefghijklmnopqrstuvwx
  assert_clean 'exactwordsaboveONCE'
  assert_clean 'abcdefghijklmnopqrstuvw'
  pass "fm-prose-lib: a letters-only token of 24 or more characters is flagged"
}

test_first_offender_wins_across_lines() {
  assert_flagged $'fine words here\nthen 2spent and 3other' 2spent
  assert_flagged $'fine words here\nthen 3other and 2spent' 3other
  pass "fm-prose-lib: the first offending token is reported across lines"
}

test_identifiers_are_not_flagged() {
  local ok
  for ok in 7607-r2-capture b3f73e16 59aee15dbad4e2533a v0.12.0 sha256 utf8 \
    https://github.com/x/y/pull/11 12:46:00.075Z native_ebd85a8a snake_case_with_4letters \
    'src/dir/file.sh' 'plain prose with ordinary spaces' ''; do
    assert_clean "$ok"
  done
  pass "fm-prose-lib: paths, urls, slugs, times, versions and hashes are not flagged"
}

test_surrounding_punctuation_is_stripped() {
  assert_flagged '(2spent)' 2spent
  assert_flagged '"exactwordsaboveONCEagainhere",' exactwordsaboveONCEagainhere
  # shellcheck disable=SC2016 # The backticks are literal text under test.
  assert_flagged 'see `4focused`:' 4focused
  assert_clean '(b3f73e16)'
  assert_clean '[v0.12.0],'
  pass "fm-prose-lib: surrounding punctuation is stripped before judging a token"
}

test_glob_characters_are_inert() {
  local dir out
  dir=$(fm_test_tmproot fm-prose-glob)
  : > "$dir/2spent"
  out=$(cd "$dir" && fm_prose_dense_token '* ? [a-z]*') && fail "glob tokens must not expand into file names (flagged '$out')"
  pass "fm-prose-lib: glob characters in text are never expanded"
}

test_digit_then_letters_is_flagged
test_long_letter_run_is_flagged
test_first_offender_wins_across_lines
test_identifiers_are_not_flagged
test_surrounding_punctuation_is_stripped
test_glob_characters_are_inert
echo "# all fm-prose-lib tests passed"
