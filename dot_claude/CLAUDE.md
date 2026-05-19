# Global rules

## Environment
- Shell is zsh on Fedora with the Sway/Wayland desktop. Sessions usually run
  inside tmux, but not always; do not assume a tmux session exists before
  relying on it.

## Shell / search
- `grep` is aliased to ripgrep (`rg`). Use ripgrep regex, not GNU/BSD grep:
  alternation `a|b`, `+`, `?`, `{n,m}` and groups work with no flag. Never pass
  `-E` (in `rg` it means `--encoding`, not extended-regex, and breaks the
  command). Avoid grep-only constructs (BRE escapes `\(` `\{`, GNU `-G`/`-z`
  semantics, `grep -r`/`-I`/`-n` flag habits that differ in `rg`).
  - Wrong: `grep -E 'foo|bar'`   Right: `rg 'foo|bar'`

## Writing style
- Never use em-dashes (—) or en-dashes (–) in any output: chat responses, code,
  comments, commit messages, or files you edit. Rewrite with a comma,
  parentheses, or two sentences. A plain hyphen (-) is fine.
- No emojis in responses, code, or commit messages unless explicitly requested.
- Be concise: lead with the answer, skip preamble, postamble, and flattery.

## Delegation
- When work splits into distinct, independent components and quality control
  matters more than speed, prefer dispatching an agent team with each agent in
  its own tmux pane over working single-threaded. For quick or tightly-coupled
  work, stay single-threaded.
