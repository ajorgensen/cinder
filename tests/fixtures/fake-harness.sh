#!/bin/sh

prompt="$1"

if [ -n "$CINDER_TEST_SLEEP" ]; then
	sleep "$CINDER_TEST_SLEEP"
fi

if [ -n "$CINDER_TEST_STDOUT" ]; then
	printf '%s\n' "$CINDER_TEST_STDOUT"
else
	printf '%s\n' "$prompt"
fi

if [ -n "$CINDER_TEST_STDERR" ]; then
	printf '%s\n' "$CINDER_TEST_STDERR" >&2
fi

if [ -n "$CINDER_TEST_EDIT_FILE" ]; then
	printf '%s' "$CINDER_TEST_EDIT_CONTENT" >"$CINDER_TEST_EDIT_FILE"
fi

exit "${CINDER_TEST_EXIT_CODE:-0}"
