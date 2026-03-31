#!/usr/bin/env python3

import json
import os
import sys

prompt = sys.argv[1] if len(sys.argv) > 1 else ""
final_text = os.environ.get("CINDER_TEST_JSON_TEXT", "json result")

print(json.dumps({"type": "session", "version": 3}))
print(json.dumps({"type": "agent_start"}))
print(
    json.dumps(
        {
            "type": "turn_end",
            "message": {
                "role": "assistant",
                "content": [{"type": "text", "text": final_text}],
            },
        }
    )
)

stderr_text = os.environ.get("CINDER_TEST_STDERR")
if stderr_text:
    print(stderr_text, file=sys.stderr)

edit_file = os.environ.get("CINDER_TEST_EDIT_FILE")
if edit_file:
    with open(edit_file, "w", encoding="utf-8") as handle:
        handle.write(os.environ.get("CINDER_TEST_EDIT_CONTENT", ""))

if os.environ.get("CINDER_TEST_ECHO_PROMPT"):
    print(prompt, file=sys.stderr)

sys.exit(int(os.environ.get("CINDER_TEST_EXIT_CODE", "0")))
