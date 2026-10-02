#!/usr/bin/env bash
# ~/.claude/hooks/pipeline-registry-write-guard.sh
# PreToolUse(Edit|Write|NotebookEdit|Bash) hook: blocks AI mutations of
# .claude/pipeline-registry.json.
#
# The registry is the allow/block authority for pipeline stage safety —
# an agent that can rewrite it can grant itself prod stages. Only a human
# may change it, via a normal reviewed commit (see the pipeline-ops skill's
# REGISTRY.md). Pairs with the committed-registry integrity check in
# pipeline-validator.sh / pipeline-guard.sh, which refuses to trust an
# uncommitted registry even if a write slips past this hook.
#
# Bash commands are blocked when the registry file is the TARGET of a write:
# a redirect target (>, >>, >|, &>), an argument of a file-writing command
# (tee, mv, cp, rm, truncate, install, sponge, ln, shred, rsync, dd of=,
# git rm/mv), or an argument of an in-place editor (sed -i, perl -i). Plain
# reads (jq/cat/grep/diff, piping its content elsewhere) are allowed, and so
# is a heredoc whose BODY merely mentions the file name — bodies are stripped
# before matching, because a log entry about the registry is not a write to
# it. Two conservative fallbacks keep this from becoming a loophole:
#   - a heredoc fed to an interpreter (bash, python, perl, ...) keeps its body,
#     and any command that invokes an interpreter or an opaque runner (eval,
#     xargs, find, ssh, awk, ...) is judged by the old broad rule: the name
#     mentioned anywhere plus any write indicator blocks;
#   - a write target that cannot be resolved ($var, $(...), backticks) while
#     the name is mentioned anywhere blocks, because the hook cannot know what
#     it expands to.

set -uo pipefail  # no -e: emit our own error messages, never crash silently

REGISTRY_BASENAME="pipeline-registry.json"

# Commands whose arguments name the files they write (dd via of=).
WRITE_CMDS='tee|mv|cp|rm|unlink|truncate|install|sponge|ln|shred|rsync|dd'
# In-place editors: write only with an -i style flag.
INPLACE_CMDS='sed|perl'
# Interpreters and opaque runners: the hook cannot see what they will do with
# the file, so the broad rule applies to the whole command.
OPAQUE_CMDS='bash|sh|zsh|dash|ksh|fish|python[0-9.]*|perl|ruby|node|php|lua|awk|gawk|mawk|nawk|eval|exec|source|ssh|xargs|find|parallel|expect|script|su|sudo'
# Wrappers skipped to find the real command word of a simple command.
WRAPPER_CMDS='command|builtin|nohup|nice|time|env|doas'
# Inline-code write markers (python/node/ruby/perl one-liners and scripts)
# and find's mutating actions.
CODE_WRITE_MARKERS="open[(][^)]*['\"][rbt+]*[wax]|open[(][^)]*['\"]r[+]|mode[[:space:]]*=[[:space:]]*['\"][rbt+]*[wax]|write_text|write_bytes|writeFile|writeFileSync|createWriteStream|File[.](write|open)|os[.](remove|unlink|rename|replace|truncate)|shutil[.](copy|move)|unlink[(]|rename[(]|-delete|-exec|-ok"
# Regex fragments for bash [[ =~ ]], kept in variables: a backslash-escaped
# or quoted metacharacter written inline in the test would change meaning
# (\> is a GNU word boundary, \| differs between ERE dialects).
SEP='(^|[;&|( ])'
OPAQUE_RE="${SEP}(${OPAQUE_CMDS})([[:space:]]|\$)"
WRITE_CMD_RE="${SEP}(${WRITE_CMDS})[[:space:]]"
INPLACE_RE="${SEP}(${INPLACE_CMDS})[[:space:]]+(-[a-zA-Z]*i|--in-place)"
# [n]>, >>, >| followed by the target token; group 2 is the remainder.
REDIRECT_RE='[0-9]*>{1,2}[|]?[[:space:]]*([^[:space:];&|<>()]+)(.*)$'

block() {
  cat >&2 <<EOF
[pipeline-registry-write-guard] BLOCKED — $1

$REGISTRY_BASENAME is the allow/block authority for pipeline stage safety.
AI agents must never modify it. Report this to the user and let a HUMAN
edit and commit the file (authoring guide: skills/pipeline-ops/REGISTRY.md).

If you were only READING it, do so without redirects or in-place tools:
  jq '.' .claude/pipeline-registry.json
EOF
  exit 2
}

# strip_heredocs: drop heredoc bodies (from the line carrying <<WORD, <<-WORD,
# <<'WORD' or <<"WORD" up to the matching terminator line) from stdin. The
# line that opens the heredoc is kept — it may redirect the body somewhere.
# A body consumed by an interpreter/opaque command is kept, joined onto its
# opening line so it is judged as part of that command. Here-strings (<<<)
# are not heredocs. Several heredocs on one line are consumed in order.
strip_heredocs() {
  awk -v opaque="(^|[;&|( \t])(${OPAQUE_CMDS})([[:space:]]|$)" '
    BEGIN { n = 0; keep_buf = "" }
    {
      if (n > 0) {
        line = $0
        if (strip[1]) sub(/^\t+/, "", line)
        if (line == term[1]) {
          for (i = 1; i < n; i++) { term[i] = term[i + 1]; strip[i] = strip[i + 1]; keep[i] = keep[i + 1] }
          n--
          if (n == 0 && keep_buf != "") { print keep_buf; keep_buf = "" }
        } else if (keep[1]) {
          keep_buf = keep_buf " " line
        }
        next
      }
      s = $0
      gsub(/<<</, "\001", s)
      is_opaque = (s ~ opaque)
      found = 0
      while (match(s, /<<-?[[:space:]]*['\''"]?[A-Za-z_][A-Za-z0-9_]*['\''"]?/)) {
        m = substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
        n++
        strip[n] = (m ~ /^<<-/)
        sub(/^<<-?[[:space:]]*/, "", m)
        gsub(/['\''"]/, "", m)
        term[n] = m
        keep[n] = is_opaque
        found = 1
      }
      if (found && is_opaque) { keep_buf = $0 } else { print }
    }
    END { if (keep_buf != "") print keep_buf }
  '
}

# unquote <token>: strip one layer of surrounding quotes.
unquote() {
  local t="$1"
  t="${t#[\"\']}"
  t="${t%[\"\']}"
  printf '%s' "$t"
}

# is_registry_target <token>: true when the token names the registry file
# (by basename) or cannot be resolved statically.
is_registry_target() {
  local t
  t=$(unquote "$1")
  [[ -z "$t" ]] && return 1
  [[ "$t" == *'$'* || "$t" == *'`'* ]] && return 0
  [[ "${t##*/}" == "$REGISTRY_BASENAME" ]]
}

# Fail closed if we cannot parse hook input at all.
command -v jq >/dev/null 2>&1 \
  && input=$(cat) \
  && tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null) \
  || block "cannot inspect tool input (jq missing or unparseable payload)"
[[ -z "$tool" ]] && block "hook payload carries no tool_name"

case "$tool" in
  Edit|Write|NotebookEdit)
    file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
    if [[ "$(basename "${file_path:-/}")" == "$REGISTRY_BASENAME" ]]; then
      block "$tool targeting $file_path"
    fi
    ;;
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
    [[ "$cmd" != *"$REGISTRY_BASENAME"* ]] && exit 0

    stripped=$(printf '%s\n' "$cmd" | strip_heredocs)
    [[ "$stripped" != *"$REGISTRY_BASENAME"* ]] && exit 0

    # Normalise: one line, single spaces; drop harmless redirects (/dev/null,
    # fd duplication) so plain reads with 2>/dev/null still pass; fold &>
    # into > so every file redirect reads as [n]>[>|][|] target.
    norm=$(printf '%s' "$stripped" | tr -s '[:space:]' ' ' \
      | sed -E 's/[0-9]*&?>+[|]?[[:space:]]*\/dev\/null//g; s/[0-9]*>&[0-9]+//g; s/&>/>/g')

    # Interpreters / opaque runners: broad rule (mention + any write indicator).
    if [[ "$norm" =~ $OPAQUE_RE ]]; then
      if [[ "$norm" == *">"* ]] \
         || [[ "$norm" =~ $WRITE_CMD_RE ]] \
         || [[ "$norm" =~ $INPLACE_RE ]] \
         || [[ "$norm" =~ $CODE_WRITE_MARKERS ]]; then
        block "command runs an interpreter/opaque runner with write indicators while mentioning $REGISTRY_BASENAME"
      fi
      exit 0
    fi

    # Redirect targets: the token right after [n]>, >>, >| .
    rest="$norm"
    while [[ "$rest" =~ $REDIRECT_RE ]]; do
      if is_registry_target "${BASH_REMATCH[1]}"; then
        block "Bash redirect targeting $REGISTRY_BASENAME (or an unresolvable target while it is mentioned)"
      fi
      rest="${BASH_REMATCH[2]}"
    done

    # File-writing commands: split into simple commands (also at $( and
    # backticks, so a substitution's command word is seen), find the command
    # word, then inspect its arguments.
    while IFS= read -r simple; do
      simple=$(printf '%s' "$simple" | tr '(){}' '    ')
      read -ra toks <<< "$simple"
      [[ ${#toks[@]} -eq 0 ]] && continue
      i=0
      while [[ $i -lt ${#toks[@]} ]] \
            && { [[ "${toks[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || [[ "${toks[$i]}" =~ ^(${WRAPPER_CMDS})$ ]]; }; do
        i=$((i + 1))
      done
      [[ $i -ge ${#toks[@]} ]] && continue
      cmdword="${toks[$i]##*/}"
      args=("${toks[@]:$((i + 1))}")

      inspect=false
      case "$cmdword" in
        tee|mv|cp|rm|unlink|truncate|install|sponge|ln|shred|rsync|dd)
          inspect=true ;;
        sed|perl)
          for a in "${args[@]}"; do
            [[ "$a" =~ ^-[a-zA-Z]*i || "$a" == "--in-place"* ]] && inspect=true
          done ;;
        git)
          [[ ${#args[@]} -gt 0 && ( "${args[0]}" == "rm" || "${args[0]}" == "mv" ) ]] && inspect=true ;;
      esac
      [[ "$inspect" == true ]] || continue

      for a in "${args[@]}"; do
        a="${a#of=}"
        if is_registry_target "$a"; then
          block "Bash '$cmdword' with $REGISTRY_BASENAME (or an unresolvable path while it is mentioned) as an argument"
        fi
      done
    done < <(printf '%s\n' "$norm" | sed -E 's/\|&|&&|\|\||[;|&`]|\$\(/\n/g')
    ;;
esac

exit 0
