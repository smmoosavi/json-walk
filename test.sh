#!/usr/bin/env bash

set -u

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$repo_dir/json-walk.sh"

tests_run=0
tests_failed=0
TMP_STDOUT=

fail() {
    local message=$1

    printf 'FAIL: %s\n' "$message" >&2
    ((tests_failed++))
}

pass() {
    ((tests_run++))
}

shell_escape() {
    printf -v REPLY '%q' "$1"
}

build_event_line() {
    local event=$1
    local line=$event
    local field

    shift

    for field in "$@"; do
        shell_escape "$field"
        line+=$'\t'"$REPLY"
    done

    REPLY=$line
}

assert_eq() {
    local expected=$1
    local actual=$2
    local message=$3

    if [[ "$actual" != "$expected" ]]; then
        printf 'expected:\n%s\n' "$expected" >&2
        printf 'actual:\n%s\n' "$actual" >&2
        fail "$message"
        return 1
    fi

    pass
}

assert_status() {
    local expected=$1
    local actual=$2
    local message=$3

    if [[ "$actual" -ne "$expected" ]]; then
        fail "$message (expected status $expected, got $actual)"
        return 1
    fi

    pass
}

assert_stdout_lines() {
    local message=$1
    local expected=
    local line

    shift

    for line in "$@"; do
        if [[ -n $expected ]]; then
            expected+=$'\n'
        fi

        expected+="$line"
    done

    assert_eq "$expected" "$RUN_STDOUT" "$message"
}

assert_stderr_contains() {
    local needle=$1
    local message=$2

    if [[ $RUN_STDERR != *"$needle"* ]]; then
        printf 'stderr:\n%s\n' "$RUN_STDERR" >&2
        fail "$message"
        return 1
    fi

    pass
}

run_json_stdout() {
    local input=$1

    : >"$TMP_STDOUT"
    : >"$TMP_STDERR"
    json_walk "$input" >"$TMP_STDOUT" 2>"$TMP_STDERR"
    RUN_STATUS=$?
    RUN_STDOUT=$(<"$TMP_STDOUT")
    RUN_STDERR=$(<"$TMP_STDERR")
}

visitor_events=()
visitor_type_counts=()
visitor_summary=
visitor_failures=()

array_visitor() {
    visitor_events+=("$#|$*")
}

counting_visitor() {
    local event=$1

    visitor_type_counts+=("$event")
}

summary_visitor() {
    local event=$1

    case $event in
        key)
            visitor_summary+="K:$2;"
            ;;
        string|number|boolean)
            visitor_summary+="V:$1=$2;"
            ;;
        null)
            visitor_summary+="V:null;"
            ;;
        *)
            visitor_summary+="$event;"
            ;;
    esac
}

failing_visitor() {
    visitor_failures+=("$1")
    return 23
}

run_json_visitor() {
    local input=$1
    local visitor_name=$2

    : >"$TMP_STDOUT"
    : >"$TMP_STDERR"
    json_walk "$input" "$visitor_name" >"$TMP_STDOUT" 2>"$TMP_STDERR"
    RUN_STATUS=$?
    RUN_STDOUT=$(<"$TMP_STDOUT")
    RUN_STDERR=$(<"$TMP_STDERR")
}

test_stdout_scalars() {
    run_json_stdout 'null'
    assert_status 0 "$RUN_STATUS" 'null should parse'
    assert_stdout_lines 'null should emit null' 'null'

    run_json_stdout 'true'
    assert_status 0 "$RUN_STATUS" 'true should parse'
    build_event_line boolean true
    assert_stdout_lines 'true should emit boolean true' "$REPLY"

    run_json_stdout 'false'
    assert_status 0 "$RUN_STATUS" 'false should parse'
    build_event_line boolean false
    assert_stdout_lines 'false should emit boolean false' "$REPLY"

    run_json_stdout '-12.5e+2'
    assert_status 0 "$RUN_STATUS" 'number should parse'
    build_event_line number '-12.5e+2'
    assert_stdout_lines 'number should emit its literal form' "$REPLY"

    run_json_stdout $'"line\\n\\tquote:\\\"slash:\\\\"'
    assert_status 0 "$RUN_STATUS" 'string should parse'
    build_event_line string $'line\n\tquote:"slash:\\'
    assert_stdout_lines 'string should decode escapes' "$REPLY"

    run_json_stdout '"\u0041"'
    assert_status 0 "$RUN_STATUS" 'unicode escape should parse'
    build_event_line string 'A'
    assert_stdout_lines 'unicode escape should decode to a character' "$REPLY"

    run_json_stdout $'"\uD83D\uDE00"'
    assert_status 0 "$RUN_STATUS" 'unicode surrogate pair should parse'
    # todo: `string	😀` is the output, but our test can't assert it correctly!
    build_event_line string $'\355\240\275\355\270\200' # 😀
    assert_stdout_lines 'unicode surrogate pair should decode to a character' "$REPLY"
}

test_stdout_compound_values() {
    run_json_stdout '[]'
    assert_status 0 "$RUN_STATUS" 'empty array should parse'
    assert_stdout_lines 'empty array should emit matching boundaries' start_array end_array

    run_json_stdout '{}'
    assert_status 0 "$RUN_STATUS" 'empty object should parse'
    assert_stdout_lines 'empty object should emit matching boundaries' start_object end_object

    run_json_stdout $'{\n  "a": [null, true, 3],\n  "b": {\n    "c": "x"\n  }\n}'
    assert_status 0 "$RUN_STATUS" 'pretty-printed nested object should parse'
    build_event_line key 'a'
    local key_a=$REPLY
    build_event_line boolean true
    local bool_true=$REPLY
    build_event_line number '3'
    local num_three=$REPLY
    build_event_line key 'b'
    local key_b=$REPLY
    build_event_line key 'c'
    local key_c=$REPLY
    build_event_line string 'x'
    local string_x=$REPLY
    assert_stdout_lines 'nested structures should emit in traversal order' \
        start_object \
        "$key_a" \
        start_array \
        null \
        "$bool_true" \
        "$num_three" \
        end_array \
        "$key_b" \
        start_object \
        "$key_c" \
        "$string_x" \
        end_object \
        end_object

    run_json_stdout '{"x":"a\tb"}'
    assert_status 0 "$RUN_STATUS" 'stdout mode should still parse strings containing tabs'
    build_event_line key 'x'
    key_a=$REPLY
    build_event_line string $'a\tb'
    string_x=$REPLY
    assert_stdout_lines 'stdout mode should shell-escape ambiguous values' start_object "$key_a" "$string_x" end_object
}

test_invalid_json_rejected() {
    run_json_stdout 'true trailing'
    assert_status 1 "$RUN_STATUS" 'trailing characters should fail'

    run_json_stdout 'tru'
    assert_status 1 "$RUN_STATUS" 'truncated literal should fail'

    run_json_stdout '{"a" 1}'
    assert_status 1 "$RUN_STATUS" 'missing colon should fail'

    run_json_stdout '[1 2]'
    assert_status 1 "$RUN_STATUS" 'missing comma should fail'

    run_json_stdout '"\q"'
    assert_status 1 "$RUN_STATUS" 'invalid string escape should fail'
    assert_stderr_contains 'Invalid string escape' 'invalid escapes should be rejected'

    run_json_stdout '"\u00xz"'
    assert_status 1 "$RUN_STATUS" 'invalid unicode escape should fail'
    assert_stderr_contains 'Invalid unicode escape' 'invalid unicode hex should be rejected'

    run_json_stdout $'"bad\x01"'
    assert_status 1 "$RUN_STATUS" 'unescaped control characters should fail'
    assert_stderr_contains 'Unescaped control character' 'raw control characters should be rejected'

    run_json_stdout '{foo:1}'
    assert_status 1 "$RUN_STATUS" 'bare object keys should fail'
    assert_stderr_contains 'Expected string key' 'object keys should require opening quotes'

    run_json_stdout '{"a":1,}'
    assert_status 1 "$RUN_STATUS" 'trailing commas in objects should fail'
    assert_stderr_contains 'Expected string key' 'trailing commas should fail at the next object key'
}

test_array_visitor_shape() {
    visitor_events=()

    run_json_visitor '{"name":"json","items":[1,false,null]}' array_visitor
    assert_status 0 "$RUN_STATUS" 'array visitor should parse object input'
    assert_eq $'1|start_object\n2|key name\n2|string json\n2|key items\n1|start_array\n2|number 1\n2|boolean false\n1|null\n1|end_array\n1|end_object' "$(printf '%s\n' "${visitor_events[@]}")" 'array visitor should receive event/value argument shapes'
}

test_counting_visitor_shape() {
    visitor_type_counts=()

    run_json_visitor '[{"id":1},{"id":2}]' counting_visitor
    assert_status 0 "$RUN_STATUS" 'counting visitor should parse array input'
    assert_eq $'start_array\nstart_object\nkey\nnumber\nend_object\nstart_object\nkey\nnumber\nend_object\nend_array' "$(printf '%s\n' "${visitor_type_counts[@]}")" 'counting visitor should receive event names only in order'
}

test_summary_visitor_shape() {
    visitor_summary=

    run_json_visitor '{"ok":true,"meta":{"value":null}}' summary_visitor
    assert_status 0 "$RUN_STATUS" 'summary visitor should parse nested object input'
    assert_eq 'start_object;K:ok;V:boolean=true;K:meta;start_object;K:value;V:null;end_object;end_object;' "$visitor_summary" 'summary visitor should handle mixed event forms'
}

test_visitor_failure_propagates() {
    visitor_failures=()

    run_json_visitor '[1,2]' failing_visitor
    assert_status 23 "$RUN_STATUS" 'visitor failures should propagate to the caller'
    assert_eq 'start_array' "$(printf '%s\n' "${visitor_failures[@]}")" 'parsing should stop on the first visitor failure'
}

main() {
    TMP_STDERR=$(mktemp)
    TMP_STDOUT=$(mktemp)
    trap 'rm -f "$TMP_STDOUT" "$TMP_STDERR"' EXIT

    test_stdout_scalars
    test_stdout_compound_values
    test_invalid_json_rejected
    test_array_visitor_shape
    test_counting_visitor_shape
    test_summary_visitor_shape
    test_visitor_failure_propagates

    if [[ $tests_failed -ne 0 ]]; then
        printf 'FAILED: %d assertion(s)\n' "$tests_failed" >&2
        exit 1
    fi

    printf 'PASS: %d assertion(s)\n' "$tests_run"
}

main "$@"