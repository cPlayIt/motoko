process.on('unhandledRejection', error => { assert.fail(error); });

const assert = require('assert').strict;

// Load moc.js
const m = require('moc.js');

// Compile the empty module in plain and dfinity mode
const empty_wasm_plain = m.Motoko.compileWasm('wasm', '');
const empty_wasm_dfinity = m.Motoko.compileWasm('dfinity', '');

// For the plain module...
// Check that the code looks like a WebAssembly binary
assert.equal(typeof(empty_wasm_plain), 'object');
assert.equal(empty_wasm_plain.code.substr(0,4), '\0asm');
assert.equal(empty_wasm_plain.code.substr(4,4), '\1\0\0\0');
assert.equal(typeof(empty_wasm_plain.diagnostics), 'object');
assert.equal(empty_wasm_plain.diagnostics.length, 0);

// Check that the WebAssembly binary can be loaded
WebAssembly.compile(Buffer.from(empty_wasm_plain.code, 'ascii'));

// Now again for the definity module
assert.equal(typeof(empty_wasm_dfinity), 'object');
assert.equal(empty_wasm_dfinity.code.substr(0,4), '\0asm');
assert.equal(empty_wasm_dfinity.code.substr(4,4), '\1\0\0\0');
assert.equal(typeof(empty_wasm_dfinity.diagnostics), 'object');
assert.equal(empty_wasm_dfinity.diagnostics.length, 0);

WebAssembly.compile(Buffer.from(empty_wasm_dfinity.code, 'ascii'));

// The plain and the dfinity module should not be the same
assert.notEqual(empty_wasm_plain.code, empty_wasm_dfinity.code);

// Check if error messages are correctly returned
const bad_result = m.Motoko.compileWasm('dfinity', '1+');
// Uncomment to see what to paste below
// console.log(JSON.stringify(bad_result, null, 2));
assert.deepStrictEqual(bad_result, {
  "diagnostics": [
    {
      "range": {
        "start": {
          "line": 0,
          "character": 2
        },
        "end": {
          "line": 0,
          "character": 2
        }
      },
      "severity": 1,
      "source": "motoko",
      "message": "unexpected token \'\', \nexpected one of token or <phrase> sequence:\n  <exp_bin(ob)>"
    }
  ],
  "code": null,
  "map": null
});

// Check the check command (should print errors, but have no code)
assert.deepStrictEqual(m.Motoko.check('1'), {
  "diagnostics": [],
  "code": null
});

assert.deepStrictEqual(m.Motoko.check('1+'), {
  "diagnostics": [
    {
      "range": {
        "start": {
          "line": 0,
          "character": 2
        },
        "end": {
          "line": 0,
          "character": 2
        }
      },
      "severity": 1,
      "source": "motoko",
      "message": "unexpected token \'\', \nexpected one of token or <phrase> sequence:\n  <exp_bin(ob)>"
    }
  ],
  "code": null
});

// Create a source map, and check some of its structure
const with_map = m.Motoko.compileWasm('dfinity', '');
assert.equal(typeof(with_map.map), 'string')
let map
assert.doesNotThrow(() => map = JSON.parse(with_map.map), SyntaxError)
assert.ok(Array.isArray(map.sources))
assert.ok(Array.isArray(map.sourcesContent))
assert.equal(typeof(map.mappings), 'string')
assert.equal(typeof(map.version), 'number')
