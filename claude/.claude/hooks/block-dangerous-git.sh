#!/bin/bash
# Claude Code PreToolUse hook for Bash: asks for confirmation before commands that
# are destructive on the remote (force pushes, remote deletes, risky gh calls).
# Local-only git operations and plain pushes are allowed.
# Inspired by https://github.com/mattpocock/skills/tree/main/skills/misc/git-guardrails-claude-code
# Printing permissionDecision "ask" makes Claude Code show the permission prompt.
# A guardrail against mistakes, not a security boundary: it can't see through
# scripts, variables or curl calls to the GitHub API.
# Requires jq.

ask() {
  # Built by hand so it works without jq; drop control chars, escape for JSON.
  local reason
  reason=$(printf '%s' "$1" | tr -d '\000-\037')
  reason="${reason//\\/\\\\}"
  reason="${reason//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "${reason}"
  exit 0
}

check_git() {
  # Skip git's global options so "git -C dir push" is seen as "git push".
  while [ $# -gt 0 ]; do
    case "$1" in
      -c)
        [[ "$2" =~ ^(alias\.|remote\..*\.push=) ]] && ask "git -c $2 can hide a force push"
        shift; shift ;;
      -C|--git-dir|--work-tree|--namespace|--config-env) shift; shift ;;
      -*) shift ;;
      *) break ;;
    esac
  done

  local sub="$1"
  shift
  case "${sub}" in
    push) check_git_push "$@" ;;
    config) check_git_config "$@" ;;
  esac
}

check_git_push() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --force|--force-with-lease*|--force-if-includes) ask "git push ${arg} overwrites remote history" ;;
      --delete|--mirror|--prune) ask "git push ${arg} deletes remote branches or tags" ;;
      --*) ;;
      # Short flags can be combined, e.g. -fu.
      -*f*) ask "git push -f overwrites remote history" ;;
      -*d*) ask "git push -d deletes remote branches or tags" ;;
      +*) ask "git push ${arg} is a force push" ;;
      :*) ask "git push ${arg} deletes a remote branch or tag" ;;
    esac
  done
}

# Aliases and push refspecs can turn a harmless-looking push into a force push.
check_git_config() {
  local arg
  for arg in "$@"; do
    [[ "${arg}" =~ ^(alias\.|remote\..*\.push$) ]] && ask "git config ${arg} can hide a force push"
  done
}

check_gh() {
  local words=() method="" fields="" delete_branch="" force=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -X|--method) method="$2"; shift ;;
      -X*) method="${1#-X}" ;;
      --method=*) method="${1#--method=}" ;;
      -f|-F|--field|--raw-field|--input) fields=1; shift ;;
      -f*|-F*|--field=*|--raw-field=*|--input=*) fields=1 ;;
      -R|--repo|--hostname) shift ;;
      -d|--delete-branch) delete_branch=1 ;;
      --force) force=1 ;;
      -*) ;;
      *) words+=("$1") ;;
    esac
    shift
  done

  local cmd="${words[0]} ${words[1]}"
  case "${cmd}" in
    "repo delete"|"repo archive"|"repo rename"|"repo edit"|"pr merge"|"issue delete"|"issue transfer"|"workflow disable")
      ask "gh ${cmd} is destructive or hard to undo" ;;
    "secret set"|"variable set") ask "gh ${cmd} overwrites the existing value" ;;
    "repo sync") [ -n "${force}" ] && ask "gh repo sync --force resets the remote branch" ;;
    "pr close") [ -n "${delete_branch}" ] && ask "gh pr close --delete-branch deletes the remote branch" ;;
    "repo deploy-key") [ "${words[2]}" = delete ] && ask "gh repo deploy-key delete deletes data on GitHub" ;;
    "alias set"|"alias import") ask "gh ${cmd} can hide destructive commands" ;;
    "api "*)
      method=$(printf '%s' "${method}" | tr '[:lower:]' '[:upper:]')
      if [ -n "${method}" ]; then
        [ "${method}" != GET ] && ask "gh api -X ${method} modifies data on GitHub"
      elif [ -n "${fields}" ]; then
        # Fields switch gh api to POST; graphql always posts, so look for a mutation.
        # Queries are often multi-line, so search the whole command.
        if [ "${words[1]}" != graphql ] || [[ "${COMMAND}" == *mutation* ]]; then
          ask "gh api with fields modifies data on GitHub"
        fi
      fi ;;
    # Local only.
    "alias "*|"extension "*|"config "*) ;;
    *" delete"|*" remove"|*" rm"|*" delete-asset"|*" item-delete"|*" field-delete")
      ask "gh ${cmd} deletes data on GitHub" ;;
  esac
}

INPUT=$(cat)
# Parsing the hook input reliably needs jq, so without it ask about everything.
if ! command -v jq >/dev/null 2>&1; then
  ask "jq is not installed, so git guardrails can't check this command. Install jq to fix this."
fi
COMMAND=$(printf '%s' "${INPUT}" | jq -r '.tool_input.command // empty')

# Join backslash line continuations, then check every command in a chain or
# pipeline on its own.
COMMAND="${COMMAND//\\$'\n'/ }"
segments=$(printf '%s\n' "${COMMAND}" | tr ';|&(){}`' '\n')
while IFS= read -r segment; do
  segment="${segment//[\"\']/}"
  read -ra tokens <<< "${segment}"
  set -- "${tokens[@]}"

  # Skip env assignments, shell keywords and wrappers that run the rest as a command.
  while [ $# -gt 0 ]; do
    case "$1" in
      *=*|if|then|else|elif|while|until|do|!) shift ;;
      sudo|env|command|exec|time|nohup|nice|eval)
        shift
        while [[ "$1" == -* ]]; do shift; done ;;
      timeout)
        shift
        while [[ "$1" == -* ]]; do
          case "$1" in -k|-s) shift ;; esac
          shift
        done
        # The duration.
        shift ;;
      xargs)
        shift
        while [[ "$1" == -* ]]; do
          case "$1" in -n|-L|-P|-I|-s|-d|-a|-E) shift ;; esac
          shift
        done ;;
      sh|bash|zsh) [ "$2" = -c ] || break; shift; shift ;;
      *) break ;;
    esac
  done

  [ $# -gt 0 ] || continue
  tool="${1##*/}"
  shift
  case "${tool%.exe}" in
    git) check_git "$@" ;;
    gh) check_gh "$@" ;;
  esac
done <<< "${segments}"

exit 0
