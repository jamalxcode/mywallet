#!/bin/bash
# or: #!/usr/bin/env bash

# Allow override of wordlist file via env or arg
WORDLIST_FILE="${1:-${WORDLIST_FILE:-english.txt}}"

# Check that the wordlist exists
if [ ! -f "$WORDLIST_FILE" ]; then
  echo "Error: $WORDLIST_FILE (BIP39 wordlist) not found."
  echo "You can get it from https://raw.githubusercontent.com/bitcoin/bips/master/bip-0039/english.txt"
  exit 1
fi

# Read stdin line by line and convert to words
while IFS= read -r number; do
  # Trim whitespace
  number=$(echo "$number" | tr -d '[:space:]')
  # Skip empty lines
  [ -z "$number" ] && continue

  # Validate input: integer between 0 and 2047
  case "$number" in
    ''|*[!0-9]*) 
      echo "Invalid number: $number" >&2
      continue
      ;;
  esac

  if [ "$number" -ge 0 ] && [ "$number" -le 2047 ]; then
    word=$(sed -n "$((number + 1))p" "$WORDLIST_FILE")
    echo "$word"
  else
    echo "Invalid number: $number" >&2
  fi
done
