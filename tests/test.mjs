import { describe, test } from "node:test";
import { spawnSync } from "node:child_process";
import { strict as assert } from "node:assert";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = join(__dirname, "..");
const jsonWalkScript = join(projectRoot, "json-walk.sh");

/**
 * Run json-walk.sh with input and return parsed events
 */
function runJsonWalk(jsonInput) {
  const cmd = spawnSync("bash", [jsonWalkScript, jsonInput], { encoding: "utf-8" });
  const output = cmd.stdout.trim();
  return output
    .trim()
    .split("\n")
    .filter((line) => line)
    .map((line) => {
      const [type, ...rest] = line.split("\t");
      return { type, value: rest.join("\t") };
    });
}

/**
 * Run print-ids.sh visitor with json input and return extracted IDs
 */
function runPrintIds(jsonInput) {
  const printIdsScript = join(__dirname, "print-ids.sh");
  const cmd = spawnSync("bash", [printIdsScript, jsonInput], { encoding: "utf-8" });
  const output = cmd.stdout.trim();
  return output
    .split("\n")
    .filter((line) => line.startsWith("ID:"))
    .map((line) => line.replace(/^ID: ?/, ""));
}

function decodeJsonString(content) {
  const cmd = spawnSync("bash", ["-c", 'source "$1"; jsonwalk_decode_string "$2"', "bash", jsonWalkScript, content], {
    encoding: "utf-8",
  });
  assert.equal(cmd.status, 0, cmd.stderr);
  return cmd.stdout;
}

describe("json-walk basic values", () => {
  test("null value", () => {
    const events = runJsonWalk("null");
    assert.deepEqual(events, [{ type: "null", value: "" }]);
  });

  test("number value", () => {
    const events = runJsonWalk("42");
    assert.deepEqual(events, [{ type: "number", value: "42" }]);
  });

  test("string value", () => {
    const events = runJsonWalk('"hello"');
    assert.deepEqual(events, [{ type: "string", value: "hello" }]);
  });

  test("boolean true", () => {
    const events = runJsonWalk("true");
    assert.deepEqual(events, [{ type: "boolean", value: "true" }]);
  });

  test("boolean false", () => {
    const events = runJsonWalk("false");
    assert.deepEqual(events, [{ type: "boolean", value: "false" }]);
  });

  test("negative number", () => {
    const events = runJsonWalk("-123");
    assert.deepEqual(events, [{ type: "number", value: "-123" }]);
  });

  test("float number", () => {
    const events = runJsonWalk("3.14");
    assert.deepEqual(events, [{ type: "number", value: "3.14" }]);
  });

  test("empty string", () => {
    const events = runJsonWalk('""');
    assert.deepEqual(events, [{ type: "string", value: "" }]);
  });

  test("string with emojis", () => {
    const events = runJsonWalk('"Hello, 👋🌍!"');
    assert.deepEqual(events, [{ type: "string", value: "Hello, 👋🌍!" }]);
  });
  test("string with unicode escape remains raw", () => {
    const events = runJsonWalk('"\\uD83D\\uDE00"');
    assert.deepEqual(events, [{ type: "string", value: "\\uD83D\\uDE00" }]);
  });

  test("string with escapes remains raw", () => {
    const events = runJsonWalk('"Line1\\nLine2\\tTabbed"');
    assert.deepEqual(events, [{ type: "string", value: "Line1\\nLine2\\tTabbed" }]);
  });

  test("raw unicode escape can be decoded explicitly", () => {
    assert.equal(decodeJsonString("\\u0041"), "A");
    assert.equal(decodeJsonString("\\uD83D\\uDE00"), "😀");
  });

  test("raw special escapes can be decoded explicitly", () => {
    assert.equal(decodeJsonString("Line1\\nLine2\\tTabbed"), "Line1\nLine2\tTabbed");
  });
});

describe("json-walk arrays", () => {
  test("empty array", () => {
    const events = runJsonWalk("[]");
    assert.deepEqual(events, [
      { type: "start_array", value: "" },
      { type: "end_array", value: "" },
    ]);
  });

  test("array of numbers", () => {
    const events = runJsonWalk("[1, 2, 3]");
    assert.deepEqual(events, [
      { type: "start_array", value: "" },
      { type: "number", value: "1" },
      { type: "number", value: "2" },
      { type: "number", value: "3" },
      { type: "end_array", value: "" },
    ]);
  });

  test("array of mixed values", () => {
    const events = runJsonWalk('[null, true, "test"]');
    assert.deepEqual(events, [
      { type: "start_array", value: "" },
      { type: "null", value: "" },
      { type: "boolean", value: "true" },
      { type: "string", value: "test" },
      { type: "end_array", value: "" },
    ]);
  });
});

describe("json-walk objects", () => {
  test("empty object", () => {
    const events = runJsonWalk("{}");
    assert.deepEqual(events, [
      { type: "start_object", value: "" },
      { type: "end_object", value: "" },
    ]);
  });

  test("object with single property", () => {
    const events = runJsonWalk('{"name": "John"}');
    assert.deepEqual(events, [
      { type: "start_object", value: "" },
      { type: "key", value: "name" },
      { type: "string", value: "John" },
      { type: "end_object", value: "" },
    ]);
  });

  test("object with multiple properties", () => {
    const events = runJsonWalk('{"id": 1, "active": true}');
    assert.deepEqual(events, [
      { type: "start_object", value: "" },
      { type: "key", value: "id" },
      { type: "number", value: "1" },
      { type: "key", value: "active" },
      { type: "boolean", value: "true" },
      { type: "end_object", value: "" },
    ]);
  });
});

describe("json-walk array of objects", () => {
  test("array of objects with id field", () => {
    const events = runJsonWalk('[{"id": 4}, {"id": 5}]');
    assert.deepEqual(events, [
      { type: "start_array", value: "" },
      { type: "start_object", value: "" },
      { type: "key", value: "id" },
      { type: "number", value: "4" },
      { type: "end_object", value: "" },
      { type: "start_object", value: "" },
      { type: "key", value: "id" },
      { type: "number", value: "5" },
      { type: "end_object", value: "" },
      { type: "end_array", value: "" },
    ]);
  });
});

describe("json-walk nested structures", () => {
  test("nested arrays", () => {
    const events = runJsonWalk("[[1, 2], [3, 4]]");
    assert.deepEqual(events, [
      { type: "start_array", value: "" },
      { type: "start_array", value: "" },
      { type: "number", value: "1" },
      { type: "number", value: "2" },
      { type: "end_array", value: "" },
      { type: "start_array", value: "" },
      { type: "number", value: "3" },
      { type: "number", value: "4" },
      { type: "end_array", value: "" },
      { type: "end_array", value: "" },
    ]);
  });

  test("nested objects", () => {
    const events = runJsonWalk('{"user": {"name": "Alice"}}');
    assert.deepEqual(events, [
      { type: "start_object", value: "" },
      { type: "key", value: "user" },
      { type: "start_object", value: "" },
      { type: "key", value: "name" },
      { type: "string", value: "Alice" },
      { type: "end_object", value: "" },
      { type: "end_object", value: "" },
    ]);
  });
});

describe("print-ids visitor", () => {
  test("extract single id from object", () => {
    const ids = runPrintIds('{"id": 42}');
    assert.deepEqual(ids, ["42"]);
  });

  test("extract multiple ids from array of objects", () => {
    const ids = runPrintIds('[{"id": 4}, {"id": 5}]');
    assert.deepEqual(ids, ["4", "5"]);
  });

  test("extract ids with other properties", () => {
    const ids = runPrintIds('[{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]');
    assert.deepEqual(ids, ["1", "2"]);
  });

  test("extract string ids", () => {
    const ids = runPrintIds('[{"id": "user-1"}, {"id": "user-2"}]');
    assert.deepEqual(ids, ["user-1", "user-2"]);
  });

  test("no ids returns empty", () => {
    const ids = runPrintIds('[{"name": "Alice"}, {"name": "Bob"}]');
    assert.deepEqual(ids, []);
  });

  test("nested objects capture both top-level and nested ids", () => {
    const ids = runPrintIds('[{"id": 1, "user": {"id": 99}}]');
    // Visitor captures all id values it encounters, including nested ones
    assert.deepEqual(ids, ["1", "99"]);
  });

  test("id field with null value", () => {
    const ids = runPrintIds('{"id": null}');
    // null has no second argument to visitor, so value is empty string
    assert.deepEqual(ids, [""]);
  });

  test("id field with boolean value", () => {
    const ids = runPrintIds('{"id": true}');
    assert.deepEqual(ids, ["true"]);
  });
});
