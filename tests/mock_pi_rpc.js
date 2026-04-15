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

  const message = textMessage(`mock pi response turn ${turn}: ${command.message}`);

  write({ type: "agent_start" });
  write({ type: "message_update", message, assistantMessageEvent: { type: "text" } });
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
