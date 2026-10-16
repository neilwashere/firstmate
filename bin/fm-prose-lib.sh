# shellcheck shell=bash
# Run-together token detector for text a worker reads: steering messages
# (bin/fm-send.sh) and a brief's `## Firstmate spec` (bin/fm-spawn.sh).
# Usage: . bin/fm-prose-lib.sh; fm_prose_dense_token "<text>"
#
# Agents that squeeze words together to fit a line cap write text such as
# `2spentmax4` or `exactwordsaboveONCEagain`, which a worker then follows
# literally instead of reading as prose. This file is the single owner of what
# counts as run-together.
#
# fm_prose_dense_token <text>: print the first offending token and return 0, or
# print nothing and return 1 when the text is clean. Text is split on
# whitespace and each token loses surrounding ( ) [ ] { } < > " ' ` , ; :
# before it is judged. A token is offending when it
#   - has a digit immediately followed by four or more ASCII letters, contains
#     none of / - _ . :, and is not a 7 to 64 character hex string; or
#   - is only ASCII letters and at least 24 characters long.
# A token containing / - _ . or : is never offending, so paths, URLs, slugs,
# times, versions and prefixed hashes pass. Written for bash 3.2.

fm_prose_dense_token() { # <text>
  local LC_ALL=C
  local tok prev
  local digit_letters='[0-9][A-Za-z]{4,}'
  local hex_run='^[0-9A-Fa-f]{7,64}$'
  local letters_only='^[A-Za-z]{24,}$'
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    prev=
    while [ "$tok" != "$prev" ]; do
      prev=$tok
      case "$tok" in
      [\(\)\[\]\{\}\<\>\"\'\`,\;:]*) tok=${tok#?} ;;
      esac
      case "$tok" in
      *[\(\)\[\]\{\}\<\>\"\'\`,\;:]) tok=${tok%?} ;;
      esac
    done
    [ -n "$tok" ] || continue
    case "$tok" in
    */* | *-* | *_* | *.* | *:*) continue ;;
    esac
    if [[ $tok =~ $letters_only ]]; then
      printf '%s\n' "$tok"
      return 0
    fi
    if [[ $tok =~ $digit_letters ]] && ! [[ $tok =~ $hex_run ]]; then
      printf '%s\n' "$tok"
      return 0
    fi
  done < <(printf '%s\n' "$1" | tr -s '[:space:]' '\n')
  return 1
}
