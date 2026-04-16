const readline = require("node:readline");

let turn = 0;
let pending = null;

function write(obj) {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
}

function textMessage(text, stopReason = "stop", errorMessage) {
  const message = {
    role: "assistant",
    content: [{ type: "text", text }],
    stopReason,
  };

  if (errorMessage) {
    message.errorMessage = errorMessage;
  }

  return message;
}

function clearPending() {
  if (pending && pending.timer) {
    clearTimeout(pending.timer);
  }

  pending = null;
}

function finishPrompt(command) {
  turn += 1;

  const fullText = `mock pi response turn ${turn}: ${command.message}`;
  const cuts = [Math.min(8, fullText.length), Math.min(24, fullText.length), fullText.length];

  write({ type: "agent_start" });

  for (const cut of cuts) {
    const partial = textMessage(fullText.slice(0, cut));
    write({ type: "message_update", message: partial, assistantMessageEvent: { type: "text" } });
  }

  const message = textMessage(fullText);
  write({ type: "message_end", message });
  write({ type: "agent_end", messages: [message] });
}

function startPrompt(command) {
  write({
    id: command.id,
    type: "response",
    command: "prompt",
    success: true,
  });

  if (command.message.includes("slow")) {
    pending = {
      message: command.message,
      timer: setTimeout(() => {
        const active = pending;
        pending = null;
        finishPrompt({ message: active.message });
      }, 250),
    };
    return;
  }

  finishPrompt(command);
}

function abortPrompt(command) {
  write({
    id: command.id,
    type: "response",
    command: "abort",
    success: true,
  });

  if (!pending) {
    return;
  }

  clearPending();

  const message = textMessage("", "aborted");
  write({ type: "message_end", message });
  write({ type: "agent_end", messages: [message] });
}

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

rl.on("line", (line) => {
  if (!line.trim()) {
    return;
  }

  const command = JSON.parse(line);

  if (command.type === "prompt") {
    startPrompt(command);
    return;
  }

  if (command.type === "abort") {
    abortPrompt(command);
    return;
  }

  write({
    id: command.id,
    type: "response",
    command: command.type,
    success: false,
    error: `unsupported command: ${command.type}`,
  });
});

process.on("SIGTERM", () => {
  clearPending();
  process.exit(0);
});
