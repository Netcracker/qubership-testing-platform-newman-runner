# # Copyright 2024-2025 NetCracker Technology Corporation
# #
# # Licensed under the Apache License, Version 2.0 (the "License");
# # you may not use this file except in compliance with the License.
# # You may obtain a copy of the License at
# #
# #      http://www.apache.org/licenses/LICENSE-2.0
# #
# # Unless required by applicable law or agreed to in writing, software
# # distributed under the License is distributed on an "AS IS" BASIS,
# # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# # See the License for the specific language governing permissions and
# # limitations under the License.

# convert_line.lib.sh
# ============================================
# Source-only helper: converts one JSON/JSON5 string → JSON string.
# Usage (from another script after sourcing):
#   result="$(convert_line_to_test_params "$line")" || exit 1
#   echo "$result"
#
# Requires:
#   - node in PATH
#   - local json5 module (npm i -E json5@2.2.3)
#   - base64 in PATH
# ============================================

convert_line_to_test_params() {
  local __input="${1-}"
  if [[ -z "$__input" ]]; then
    echo "convert_line_to_params_json: input string is empty" >&2
    return 1
  fi

  command -v node >/dev/null 2>&1 || { echo "node is required in PATH." >&2; return 1; }
  command -v base64 >/dev/null 2>&1 || { echo "base64 is required in PATH." >&2; return 1; }

  # Safely pass the string to Node via argv: encode to base64
  local __b64
  __b64="$(printf '%s' "$__input" | base64 | tr -d '\n')"

  node - "$__b64" <<'NODE'
let JSON5;
try { JSON5 = require('json5'); }
catch {
  console.error('json5 module not found. Install it: npm i -E json5@2.2.3');
  process.exit(1);
}

const [, , b64] = process.argv;
if (!b64) {
  console.error('No input provided (argv).');
  process.exit(1);
}

let raw;
try { raw = Buffer.from(b64, 'base64').toString('utf8').trim(); }
catch {
  console.error('Failed to decode base64 input.');
  process.exit(1);
}
if (!raw) {
  console.error('Input is empty after decoding.');
  process.exit(1);
}

const normalized = raw
  .replace(/\bTrue\b/g, 'true')
  .replace(/\bFalse\b/g, 'false')
  .replace(/\bNone\b/g, 'null');

let src;
try { src = JSON5.parse(normalized); }
catch (e) {
  console.error('Parse error (after normalizing True/False/None).', e.message || e);
  process.exit(1);
}

const toArray = (x) => Array.isArray(x) ? x : (x == null ? [] : [x]);

// --- Collections + folder flags ---
const rawCollections = toArray(src.collections);
const collections = [];
const folderFlags = [];

for (const item of rawCollections) {
  if (typeof item === 'string') {
    const m = item.match(/^(.*?\.json):(.*)$/i);
    if (m) {
      const path = m[1].trim();
      const folder = (m[2] || '').trim();
      if (path) collections.push(path);
      if (folder) folderFlags.push(`--folder ${folder}`);
      continue;
    }
  }
  collections.push(item);
}

// --- Flags order ---
// 1) flags from input (as-is)
// 2) --environment <file> (if present)
// 3) --globals <file> (if present)
// 4) folder flags
// 5) --env-var K->V for each env_vars entry
const flags = [];
flags.push(...toArray(src.flags));

if (src.env) flags.push(`--environment ${src.env}`);
if (src.globals) flags.push(`--globals ${src.globals}`);
flags.push(...folderFlags);

const envVars = src.env_vars || {};
for (const [k, v] of Object.entries(envVars)) {
  flags.push(`--env-var ${k}->${v}`);
}

const out = { collections, flags };
process.stdout.write(JSON.stringify(out, null, 2));
NODE
}
