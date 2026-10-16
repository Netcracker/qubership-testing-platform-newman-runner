/* global require, process, __dirname */
// Unit tests for tools/newman-inject-b3-headers.js. Run with: node --test "tests/unit/*.test.js"

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const { execFileSync, spawnSync } = require('child_process');

const SCRIPT = path.join(__dirname, '..', '..', 'tools', 'newman-inject-b3-headers.js');
const { MARKER, SNIPPET_LINES, injectB3Headers } = require(SCRIPT);

/**
 * Runs the injected pre-request script against a stand-in for the Postman `pm` object.
 *
 * @param {string|undefined} traceId - Value of the X_B3_TRACE_ID global, or undefined when unset.
 * @returns {Object<string, string>} Headers the script set on the request.
 */
function runInjectedScript(traceId) {
  const headers = {};
  const pm = {
    globals: { get: (name) => (name === 'X_B3_TRACE_ID' ? traceId : undefined) },
    request: { headers: { upsert: ({ key, value }) => { headers[key] = value; } } },
  };
  vm.runInNewContext(SNIPPET_LINES.join('\n'), { pm, Math });
  return headers;
}

function writeCollection(contents) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nmr-b3-'));
  const file = path.join(dir, 'c.postman_collection.json');
  fs.writeFileSync(file, typeof contents === 'string' ? contents : JSON.stringify(contents));
  return file;
}

test('adds the event ahead of the collection events that exist', () => {
  const userEvent = { listen: 'prerequest', script: { exec: ['console.log(1);'] } };
  const collection = { item: [], event: [userEvent] };

  assert.equal(injectB3Headers(collection), true);

  assert.equal(collection.event.length, 2);
  assert.ok(collection.event[0].script.exec.some((line) => line.includes(MARKER)));
  assert.equal(collection.event[1], userEvent);
});

test('creates the event list when the collection has none', () => {
  const collection = { item: [] };
  injectB3Headers(collection);
  assert.equal(collection.event.length, 1);
  assert.equal(collection.event[0].listen, 'prerequest');
});

test('does not add the event twice', () => {
  const collection = { item: [] };
  assert.equal(injectB3Headers(collection), true);
  assert.equal(injectB3Headers(collection), false);
  assert.equal(collection.event.length, 1);
});

test('injected script sets trace, span and sampled headers', () => {
  const headers = runInjectedScript('1234567812abc');
  assert.equal(headers['X-B3-TraceId'], '1234567812abc');
  assert.match(headers['X-B3-SpanId'], /^[0-9a-f]{16}$/);
  assert.equal(headers['X-B3-Sampled'], '1');
});

test('injected script generates a new span id on every call', () => {
  const spans = new Set(Array.from({ length: 20 }, () => runInjectedScript('t')['X-B3-SpanId']));
  assert.ok(spans.size > 1);
});

test('injected script sets nothing when the trace id is not set', () => {
  assert.deepEqual(runInjectedScript(undefined), {});
});

test('command line rewrites the file once and leaves it alone on the second run', () => {
  const file = writeCollection({ info: { name: 'c' }, item: [] });
  execFileSync(process.execPath, [SCRIPT, file]);
  const afterFirst = fs.readFileSync(file, 'utf8');
  execFileSync(process.execPath, [SCRIPT, file]);

  assert.equal(fs.readFileSync(file, 'utf8'), afterFirst);
  assert.equal(JSON.parse(afterFirst).event.length, 1);
});

test('command line accepts a collection file that starts with a byte order mark', () => {
  const bom = String.fromCharCode(0xfeff);
  const file = writeCollection(`${bom}{"item":[]}`);
  execFileSync(process.execPath, [SCRIPT, file]);
  assert.equal(JSON.parse(fs.readFileSync(file, 'utf8')).event.length, 1);
});

test('command line leaves a file that is not a collection untouched and exits non-zero', () => {
  for (const contents of ['not json', '{"foo":1}']) {
    const file = writeCollection(contents);
    const result = spawnSync(process.execPath, [SCRIPT, file]);

    assert.notEqual(result.status, 0);
    assert.equal(fs.readFileSync(file, 'utf8'), contents);
  }
});

test('command line exits non-zero without an argument', () => {
  assert.notEqual(spawnSync(process.execPath, [SCRIPT]).status, 0);
});
