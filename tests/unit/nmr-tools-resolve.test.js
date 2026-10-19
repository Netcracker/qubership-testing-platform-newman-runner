/* global require, process, __dirname */
// Unit tests for resolve_newman_collections in tools/nmr_tools.sh.
// Run with: node --test "tests/unit/*.test.js"

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const LIB = path.join(__dirname, '..', '..', 'tools', 'nmr_tools.sh');

// The library is stored with CRLF line endings; bash cannot source that directly.
const libDir = fs.mkdtempSync(path.join(os.tmpdir(), 'nmr-lib-'));
const LIB_LF = path.join(libDir, 'nmr_tools.sh');
fs.writeFileSync(LIB_LF, fs.readFileSync(LIB, 'utf8').replace(/\r\n/g, '\n'));

/**
 * Builds a fixture repository layout used by the tests.
 * @returns {{root: string, outside: string}} search root and a directory outside of it.
 */
function makeFixture() {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'nmr-repo-'));
  const root = path.join(base, 'clone');
  const outside = path.join(base, 'outside');
  const touch = (rel) => {
    const full = path.join(root, rel);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, '{}');
  };
  touch('project/smoke/a.postman_collection.json');
  touch('project/smoke/sub/b.postman_collection.json');
  touch('project/other/c.postman_collection.json');
  touch('project/tests.json'); // explicit file without postman suffix
  touch('project/x.postman_collection.json.bak'); // not a collection
  touch('node_modules/x/n.postman_collection.json'); // pruned
  touch('.git/g.postman_collection.json'); // pruned
  fs.mkdirSync(path.join(root, 'empty_dir'));
  fs.mkdirSync(outside);
  fs.writeFileSync(path.join(outside, 'o.postman_collection.json'), '{}');
  fs.symlinkSync(outside, path.join(root, 'link_out'));
  return { root, outside, base };
}

/**
 * Runs resolve_newman_collections with the given entries.
 * @param {string} root - search root passed as TMP_DIR.
 * @param {string[]} entries - values of the collection list (execution_list names).
 * @returns {{rc: number, items: string[], stderr: string}}
 */
function resolve(root, entries) {
  const script = [
    'source "$1"',
    'root="$2"; shift 2',
    'COLS=("$@")',
    'resolve_newman_collections "$root" COLS >/dev/null 2>&2; rc=$?',
    'printf "@@RC=%s\\n" "$rc"',
    'for item in "${COLS[@]}"; do printf "@@ITEM=%s\\n" "$item"; done',
  ].join('\n');
  const res = spawnSync('bash', ['-c', script, 'bash', LIB_LF, root, ...entries], {
    encoding: 'utf8',
  });
  const rc = Number(/@@RC=(\d+)/.exec(res.stdout).at(1));
  const items = res.stdout
    .split('\n')
    .filter((line) => line.startsWith('@@ITEM='))
    .map((line) => line.slice('@@ITEM='.length));
  return { rc, items, stderr: res.stderr };
}

const SMOKE = ['project/smoke/a.postman_collection.json', 'project/smoke/sub/b.postman_collection.json'];
const OTHER = 'project/other/c.postman_collection.json';

test('file entry without postman suffix is kept as is', () => {
  const { root, base } = makeFixture();
  try {
    const r = resolve(root, ['project/tests.json']);
    assert.equal(r.rc, 0);
    assert.deepEqual(r.items, ['project/tests.json']);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('file entries do not require the search root to exist', () => {
  const missing = path.join(os.tmpdir(), 'nmr-missing-' + process.pid);
  const r = resolve(missing, ['tests']);
  assert.equal(r.rc, 0);
  assert.deepEqual(r.items, ['tests']);
});

test('directory entry expands recursively, pruning node_modules and .git', () => {
  const { root, base } = makeFixture();
  try {
    const r = resolve(root, ['project/smoke']);
    assert.equal(r.rc, 0);
    assert.deepEqual(r.items, SMOKE);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('trailing slash and ./ prefix are normalized', () => {
  const { root, base } = makeFixture();
  try {
    assert.deepEqual(resolve(root, ['project/other/']).items, [OTHER]);
    assert.deepEqual(resolve(root, ['./project/other']).items, [OTHER]);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('mixed directory and file entries are merged in order', () => {
  const { root, base } = makeFixture();
  try {
    const r = resolve(root, ['project/other', 'project/tests.json']);
    assert.equal(r.rc, 0);
    assert.deepEqual(r.items, [OTHER, 'project/tests.json']);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('file listed explicitly and inside a listed folder is deduplicated', () => {
  const { root, base } = makeFixture();
  try {
    const r = resolve(root, ['project/other', OTHER]);
    assert.equal(r.rc, 0);
    assert.deepEqual(r.items, [OTHER]);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('overlapping directories are deduplicated', () => {
  const { root, base } = makeFixture();
  try {
    const r = resolve(root, ['project/smoke', 'project/smoke/sub']);
    assert.equal(r.rc, 0);
    assert.deepEqual(r.items, SMOKE);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('"." expands to every collection in the repository', () => {
  const { root, base } = makeFixture();
  try {
    const r = resolve(root, ['.']);
    assert.equal(r.rc, 0);
    assert.deepEqual(r.items.sort(), [...SMOKE, OTHER].sort());
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('empty directory fails', () => {
  const { root, base } = makeFixture();
  try {
    const r = resolve(root, ['empty_dir']);
    assert.equal(r.rc, 1);
    assert.match(r.stderr, /No Newman collections found/);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('".." segments are rejected', () => {
  const { root, base } = makeFixture();
  try {
    assert.equal(resolve(root, ['project/../project/other']).rc, 1);
    assert.equal(resolve(root, ['../outside']).rc, 1);
    assert.equal(resolve(root, ['../escape.postman_collection.json']).rc, 1);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('absolute paths are rejected', () => {
  const { root, base } = makeFixture();
  try {
    assert.equal(resolve(root, ['/etc']).rc, 1);
    assert.equal(resolve(root, ['/etc/passwd']).rc, 1);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('symlink pointing outside the repository is rejected', () => {
  const { root, base } = makeFixture();
  try {
    const r = resolve(root, ['link_out']);
    assert.equal(r.rc, 1);
    assert.match(r.stderr, /outside of/);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('"all" discovers every collection from the root', () => {
  const { root, base } = makeFixture();
  try {
    const r = resolve(root, ['all']);
    assert.equal(r.rc, 0);
    assert.deepEqual(r.items.sort(), [...SMOKE, OTHER].sort());
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('"all" combined with other entries is rejected', () => {
  const { root, base } = makeFixture();
  try {
    assert.equal(resolve(root, ['all', 'project/tests.json']).rc, 1);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});

test('empty entry is not expanded to the repository root', () => {
  const { root, base } = makeFixture();
  try {
    const r = resolve(root, ['project/other', '']);
    assert.equal(r.rc, 0);
    assert.deepEqual(r.items, [OTHER, '']);
  } finally {
    fs.rmSync(base, { recursive: true, force: true });
  }
});
