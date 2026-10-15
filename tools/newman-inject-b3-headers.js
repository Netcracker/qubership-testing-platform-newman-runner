#!/usr/bin/env node
/* global require, process, console, module */
// newman-inject-b3-headers.js — idempotently adds a collection-level pre-request
// script that stamps every request with B3 trace/span headers.
//
// Usage: node newman-inject-b3-headers.js <collection.json>
//
// Runs once per Newman collection, against the file inside the temporary clone
// (never the user's source repository). The injected script reads the trace id
// from the X_B3_TRACE_ID global variable (set per collection run via
// `newman run --global-var`, see start_tests.sh) and generates a fresh span id
// per request with Math.random(): a span id is a correlation id, not a security
// token, and the Postman sandbox has no Node crypto module.
//
// The script is added as the first collection-level event, so a pre-request
// script of your own runs after it and can still override the headers.

const fs = require('fs');

const MARKER = '__ATP_B3_HEADERS__';

const SNIPPET_LINES = [
  `// ${MARKER} — auto-injected, do not edit by hand`,
  '(function () {',
  "  var traceId = pm.globals.get('X_B3_TRACE_ID');",
  '  if (!traceId) { return; }',
  "  var spanId = '';",
  '  for (var i = 0; i < 16; i++) { spanId += Math.floor(Math.random() * 16).toString(16); }',
  "  pm.request.headers.upsert({ key: 'X-B3-TraceId', value: traceId });",
  "  pm.request.headers.upsert({ key: 'X-B3-SpanId', value: spanId });",
  "  pm.request.headers.upsert({ key: 'X-B3-Sampled', value: '1' });",
  '})();',
];

/**
 * Tells whether the collection already carries the injected script.
 *
 * @param {object} collection - Parsed Postman collection.
 * @returns {boolean} `true` if a collection-level pre-request event contains the marker.
 */
function hasInjectedScript(collection) {
  return (collection.event || []).some(
    (event) =>
      event.listen === 'prerequest' &&
      event.script &&
      Array.isArray(event.script.exec) &&
      event.script.exec.some((line) => String(line).includes(MARKER))
  );
}

/**
 * Adds the B3 pre-request event to the collection, ahead of any event it already has.
 *
 * @param {object} collection - Parsed Postman collection, changed in place.
 * @returns {boolean} `true` if the event was added, `false` if it was already present.
 */
function injectB3Headers(collection) {
  if (hasInjectedScript(collection)) {
    return false;
  }
  const event = {
    listen: 'prerequest',
    script: { type: 'text/javascript', exec: SNIPPET_LINES },
  };
  collection.event = [event, ...(collection.event || [])];
  return true;
}

function main() {
  const collectionPath = process.argv[2];
  if (!collectionPath) {
    console.error('Usage: newman-inject-b3-headers.js <collection.json>');
    process.exit(1);
  }

  let collection;
  try {
    let raw = fs.readFileSync(collectionPath, 'utf8');
    if (raw.charCodeAt(0) === 0xfeff) {
      raw = raw.slice(1);
    }
    collection = JSON.parse(raw);
  } catch (err) {
    console.error(`⚠️ Cannot read ${collectionPath} as JSON, B3 headers not injected: ${err.message}`);
    process.exit(1);
  }

  if (collection === null || typeof collection !== 'object' || !Array.isArray(collection.item)) {
    console.error(`⚠️ ${collectionPath} is not a Postman collection (no "item" array), B3 headers not injected`);
    process.exit(1);
  }

  if (injectB3Headers(collection)) {
    fs.writeFileSync(collectionPath, `${JSON.stringify(collection, null, 2)}\n`);
    console.log(`🔗 B3 trace headers injected into ${collectionPath}`);
  } else {
    console.log(`ℹ️ B3 trace headers already injected into ${collectionPath}`);
  }
}

if (require.main === module) {
  main();
}

module.exports = { MARKER, SNIPPET_LINES, injectB3Headers };
