const bridge = window.webkit?.messageHandlers?.realtime;

const statusDot = document.getElementById("statusDot");
const statusLabel = document.getElementById("statusLabel");
const startButton = document.getElementById("startButton");
const stopButton = document.getElementById("stopButton");
const transcriptEl = document.getElementById("transcript");
const todoListEl = document.getElementById("todoList");
const copyAllButton = document.getElementById("copyAllButton");
const copyTranscriptButton = document.getElementById("copyTranscriptButton");
const copyTodosButton = document.getElementById("copyTodosButton");

const MANUAL_TRANSCRIPT_COMMIT_MS = 10_000;
const TRANSCRIPT_SECTION_BREAK_MS = 18_000;

let pc = null;
let dc = null;
let localStream = null;
let isRunning = false;
let isStopping = false;
let transcriptItems = [];
let transcriptChunksById = new Map();
let todos = new Map();
let handledCalls = new Set();
let todoExtractionTimer = null;
let todoExtractionTimeout = null;
let todoExtractionInFlight = false;
let todoExtractionQueued = false;
let todoExtractionWaiters = [];
let lastExtractionTranscript = "";
let inputCommitTimer = null;
let lastTranscriptChunkAt = 0;

function postToSwift(type, payload = {}) {
  bridge?.postMessage({ type, ...payload });
}

function setStatus(label, mode = "") {
  statusLabel.textContent = label;
  statusDot.className = `status-dot ${mode}`.trim();
}

function setControls(running) {
  startButton.disabled = running;
  stopButton.disabled = !running;
}

function escapeHTML(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function currentTranscript() {
  return transcriptItems
    .map(sectionText)
    .filter(Boolean)
    .join("\n\n")
    .trim();
}

function syncCopyButtons() {
  const hasTranscript = currentTranscript().length > 0;
  const hasTodos = todos.size > 0;
  copyTranscriptButton.disabled = !hasTranscript;
  copyTodosButton.disabled = !hasTodos;
  copyAllButton.disabled = !hasTranscript && !hasTodos;
}

function renderTranscript() {
  const html = transcriptItems
    .map((section) => ({ text: sectionText(section), isPartial: section.chunks.some((chunk) => chunk.isPartial) }))
    .filter((section) => section.text)
    .map((section) => `<p class="${section.isPartial ? "partial" : ""}">${escapeHTML(section.text)}</p>`)
    .join("");

  transcriptEl.classList.toggle("empty", html.length === 0);
  transcriptEl.innerHTML = html || "No transcript yet";
  transcriptEl.scrollTop = transcriptEl.scrollHeight;
  syncCopyButtons();
}

function sectionText(section) {
  return section.chunks
    .map((chunk) => chunk.text.trim())
    .filter(Boolean)
    .join(" ")
    .replace(/\s+([,.;:!?])/g, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

function ensureTranscriptItem(itemId) {
  const id = itemId || "live";
  let item = transcriptChunksById.get(id);

  if (!item) {
    const now = Date.now();
    let section = transcriptItems.at(-1);
    if (!section || now - lastTranscriptChunkAt > TRANSCRIPT_SECTION_BREAK_MS) {
      section = { chunks: [] };
      transcriptItems.push(section);
    }

    item = { id, text: "", isPartial: true };
    transcriptChunksById.set(id, item);
    section.chunks.push(item);
  }

  lastTranscriptChunkAt = Date.now();
  return item;
}

function todoKey(title) {
  return String(title ?? "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

function todoMetadata(todo) {
  return [todo.due_date, todo.priority && todo.priority !== "normal" ? todo.priority : ""]
    .filter(Boolean)
    .join(", ");
}

function todoNoteLines(notes) {
  return String(notes ?? "")
    .split(/\r?\n/)
    .map((line) => line.trim().replace(/^[-*]\s+/, ""))
    .filter(Boolean);
}

function renderTodos() {
  const items = Array.from(todos.values());
  todoListEl.classList.toggle("empty", items.length === 0);
  syncCopyButtons();

  if (items.length === 0) {
    todoListEl.innerHTML = "No to-dos";
    return;
  }

  todoListEl.innerHTML = items
    .map((todo) => {
      const done = todo.status === "done";
      const meta = [todo.priority && todo.priority !== "normal" ? todo.priority : "", todo.due_date || ""]
        .filter(Boolean)
        .join(" / ");
      return `
        <article class="todo ${done ? "done" : ""}">
          <span class="check" aria-hidden="true"></span>
          <div>
            <div class="todo-title">${escapeHTML(todo.title)}</div>
            ${meta ? `<div class="todo-meta">${escapeHTML(meta)}</div>` : ""}
            ${todo.notes ? `<div class="todo-notes">${escapeHTML(todo.notes)}</div>` : ""}
          </div>
        </article>
      `;
    })
    .join("");
}

function copyTodosText() {
  return Array.from(todos.values())
    .map((todo) => {
      const checked = todo.status === "done" ? "x" : " ";
      const suffix = todoMetadata(todo);
      const task = `- [${checked}] ${todo.title}${suffix ? ` (${suffix})` : ""}`;
      const notes = todoNoteLines(todo.notes).map((line) => `  - ${line}`);
      return [task, ...notes].join("\n");
    })
    .join("\n");
}

function copyAllText() {
  return [
    `<raw_transcript>\n${currentTranscript()}\n</raw_transcript>`,
    `<structured_todos>\n${copyTodosText()}\n</structured_todos>`,
  ].join("\n\n");
}

function applyTodo(args) {
  const title = String(args.title ?? "").trim();
  if (!title) {
    return { ok: false, error: "Missing todo title" };
  }

  const key = todoKey(title);
  const replacedKey = todoKey(args.replaces_title);
  const existing = todos.get(key) ?? (replacedKey ? todos.get(replacedKey) : undefined) ?? {};
  if (replacedKey && replacedKey !== key) {
    todos.delete(replacedKey);
  }
  todos.set(key, {
    title,
    notes: args.notes ?? existing.notes ?? "",
    due_date: args.due_date ?? existing.due_date ?? "",
    priority: args.priority ?? existing.priority ?? "normal",
    status: args.status ?? existing.status ?? "open",
  });
  renderTodos();

  return { ok: true, count: todos.size };
}

function sendSessionUpdate() {
  sendEvent({
    type: "session.update",
    session: {
      type: "realtime",
      model: "gpt-realtime-2",
      output_modalities: ["text"],
      instructions:
        "You are helping turn live dictation into a concise, non-duplicative todo list. Preserve the transcript exactly through audio transcription events. Do not speak. Do not add commentary. Call upsert_todo whenever the user states an actionable task, deadline, priority, or completion status. Rewrite filler into short, clear action titles. Put supporting detail in notes as separate newline-delimited points. Maintain one todo per underlying user intent. Do not create duplicate todos for repeated statements, pauses, false starts, or rephrasing. If a new statement refines an existing todo, update the existing todo or use replaces_title instead of creating another item. Mark a todo done when the user says it is checked off, complete, finished, or already working.",
      tools: [
        {
          type: "function",
          name: "upsert_todo",
          description: "Create or update one visible todo item from the user's dictation.",
          parameters: {
            type: "object",
            properties: {
              title: {
                type: "string",
                description: "Short actionable todo title without filler words.",
              },
              replaces_title: {
                type: "string",
                description: "Optional exact title of an existing visible todo to replace when retitling, merging, or removing a duplicate.",
              },
              notes: {
                type: "string",
                description: "Optional supporting detail from the user's words. Use one line per detail so copying can format each line as a nested markdown bullet.",
              },
              due_date: {
                type: "string",
                description: "Optional due date or time phrase exactly as the user said it.",
              },
              priority: {
                type: "string",
                enum: ["low", "normal", "high"],
                description: "Task priority.",
              },
              status: {
                type: "string",
                enum: ["open", "done"],
                description: "Whether the task is still open or already done.",
              },
            },
            required: ["title"],
          },
        },
      ],
      tool_choice: "auto",
    },
  });
}

function sendEvent(event) {
  if (dc?.readyState === "open") {
    dc.send(JSON.stringify(event));
  }
}

function commitInputAudio() {
  sendEvent({ type: "input_audio_buffer.commit" });
}

function startManualTranscriptCommits() {
  clearManualTranscriptCommits();
  inputCommitTimer = setInterval(() => {
    if (isRunning && !isStopping) {
      commitInputAudio();
    }
  }, MANUAL_TRANSCRIPT_COMMIT_MS);
}

function clearManualTranscriptCommits() {
  if (inputCommitTimer) {
    clearInterval(inputCommitTimer);
    inputCommitTimer = null;
  }
}

function clearTodoExtractionTimer() {
  if (todoExtractionTimer) {
    clearTimeout(todoExtractionTimer);
    todoExtractionTimer = null;
  }
}

function clearTodoExtractionTimeout() {
  if (todoExtractionTimeout) {
    clearTimeout(todoExtractionTimeout);
    todoExtractionTimeout = null;
  }
}

function finishTodoExtraction(ok) {
  clearTodoExtractionTimeout();
  todoExtractionInFlight = false;

  const waiters = todoExtractionWaiters.splice(0);
  waiters.forEach((resolve) => resolve(ok));

  if (todoExtractionQueued && isRunning && !isStopping) {
    todoExtractionQueued = false;
    scheduleTodoExtraction(120);
  } else {
    todoExtractionQueued = false;
  }
}

function waitForCurrentTodoExtraction(maxWait = 8_500) {
  if (!todoExtractionInFlight) {
    return Promise.resolve(true);
  }

  return Promise.race([
    new Promise((resolve) => todoExtractionWaiters.push(resolve)),
    new Promise((resolve) => setTimeout(() => resolve(false), maxWait)),
  ]);
}

function scheduleTodoExtraction(delay = 750) {
  if (!isRunning || isStopping) {
    return;
  }

  const transcript = currentTranscript();
  if (!transcript || transcript === lastExtractionTranscript) {
    return;
  }

  clearTodoExtractionTimer();
  todoExtractionTimer = setTimeout(() => {
    requestTodoExtraction().catch((error) => {
      console.warn("Todo extraction failed", error);
    });
  }, delay);
}

function visibleTodosForPrompt() {
  const items = Array.from(todos.values()).map((todo) => ({
    title: todo.title,
    notes: todo.notes,
    due_date: todo.due_date,
    priority: todo.priority,
    status: todo.status,
  }));
  return items.length > 0 ? JSON.stringify(items) : "none";
}

function requestTodoExtraction({ final = false } = {}) {
  return new Promise((resolve) => {
    if (dc?.readyState !== "open") {
      resolve(false);
      return;
    }

    const transcript = currentTranscript();
    if (!transcript || (!final && transcript === lastExtractionTranscript)) {
      resolve(false);
      return;
    }

    if (todoExtractionInFlight) {
      todoExtractionQueued = true;
      resolve(false);
      return;
    }

    todoExtractionInFlight = true;
    todoExtractionWaiters.push(resolve);
    lastExtractionTranscript = transcript;

    sendEvent({
      type: "response.create",
      response: {
        output_modalities: ["text"],
        instructions: `Review the latest transcript and update the visible todo list. Current visible todos: ${visibleTodosForPrompt()}. Call upsert_todo for any actionable task, deadline, priority, or completion status. Do not output commentary. Rewrite filler into short, clear action titles. Use notes for supporting detail, with one newline-delimited point per detail. Maintain one todo per underlying user intent. Do not create duplicate todos for repeated statements, pauses, false starts, or rephrasing. If a new statement refines an existing todo, update the existing todo using its current title, or set replaces_title to the existing title when retitling or merging. Mark a todo done when the user says it is checked off, complete, finished, or already working.`,
      },
    });

    todoExtractionTimeout = setTimeout(() => {
      finishTodoExtraction(false);
    }, final ? 8_000 : 5_000);
  });
}

function handleFunctionCall(functionCall) {
  if (!functionCall || functionCall.name !== "upsert_todo") {
    return;
  }

  const callId = functionCall.call_id || functionCall.callId || functionCall.id;
  if (callId && handledCalls.has(callId)) {
    return;
  }
  if (callId) {
    handledCalls.add(callId);
  }

  let args = {};
  try {
    args = JSON.parse(functionCall.arguments || "{}");
  } catch {
    args = {};
  }

  const result = applyTodo(args);
  if (callId) {
    sendEvent({
      type: "conversation.item.create",
      item: {
        type: "function_call_output",
        call_id: callId,
        output: JSON.stringify(result),
      },
    });
  }
}

function handleRealtimeEvent(event) {
  switch (event.type) {
    case "input_audio_buffer.committed":
      if (event.item_id) {
        ensureTranscriptItem(event.item_id);
      }
      break;
    case "conversation.item.input_audio_transcription.delta": {
      const itemId = event.item_id || "live";
      const item = ensureTranscriptItem(itemId);
      item.text = `${item.text}${event.delta || ""}`;
      item.isPartial = true;
      renderTranscript();
      break;
    }
    case "conversation.item.input_audio_transcription.completed": {
      const itemId = event.item_id || "live";
      const item = ensureTranscriptItem(itemId);
      item.text = String(event.transcript || item.text || "").trim();
      item.isPartial = false;
      renderTranscript();
      scheduleTodoExtraction();
      break;
    }
    case "conversation.item.input_audio_transcription.failed":
      setStatus("Transcription failed", "error");
      break;
    case "response.done":
      (event.response?.output || []).forEach(handleFunctionCall);
      finishTodoExtraction(true);
      break;
    case "response.failed":
    case "response.cancelled":
    case "response.incomplete":
      finishTodoExtraction(false);
      break;
    case "response.output_item.done":
    case "conversation.item.done":
      handleFunctionCall(event.item);
      break;
    case "response.function_call_arguments.done":
      handleFunctionCall(event);
      break;
    case "error":
      setStatus("Error", "error");
      stopRealtime({ notify: false, updateStatus: false });
      postToSwift("error", { message: event.error?.message || "Realtime session failed." });
      break;
    default:
      break;
  }
}

function resetSessionUI() {
  clearManualTranscriptCommits();
  clearTodoExtractionTimer();
  clearTodoExtractionTimeout();
  transcriptItems = [];
  transcriptChunksById = new Map();
  todos = new Map();
  handledCalls = new Set();
  todoExtractionInFlight = false;
  todoExtractionQueued = false;
  todoExtractionWaiters.splice(0).forEach((resolve) => resolve(false));
  lastExtractionTranscript = "";
  lastTranscriptChunkAt = 0;
  isStopping = false;
  renderTranscript();
  renderTodos();
}

async function startRealtime() {
  if (isRunning) {
    return;
  }

  resetSessionUI();
  setStatus("Connecting", "connecting");
  setControls(true);
  isRunning = true;

  try {
    pc = new RTCPeerConnection();
    dc = pc.createDataChannel("oai-events");

    dc.addEventListener("open", () => {
      sendSessionUpdate();
      sendEvent({ type: "input_audio_buffer.clear" });
      startManualTranscriptCommits();
      setStatus("Listening", "live");
      postToSwift("sessionStarted");
    });

    dc.addEventListener("message", (message) => {
      try {
        handleRealtimeEvent(JSON.parse(message.data));
      } catch (error) {
        console.warn("Failed to parse realtime event", error);
      }
    });

    pc.addEventListener("connectionstatechange", () => {
      if (pc.connectionState === "failed") {
        setStatus("Connection failed", "error");
        stopRealtime({ notify: false, updateStatus: false });
        postToSwift("error", { message: "Realtime WebRTC connection failed." });
      }
    });

    localStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
    });
    localStream.getTracks().forEach((track) => pc.addTrack(track, localStream));

    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    const sdpResponse = await fetch("/session", {
      method: "POST",
      body: offer.sdp,
      headers: {
        "Content-Type": "application/sdp",
      },
    });

    const answerSDP = await sdpResponse.text();
    if (!sdpResponse.ok) {
      throw new Error(answerSDP || "Failed to create Realtime session.");
    }

    await pc.setRemoteDescription({
      type: "answer",
      sdp: answerSDP,
    });
  } catch (error) {
    await stopRealtime({ notify: false, updateStatus: false });
    const message = error?.message || "Realtime session failed.";
    setStatus("Error", "error");
    postToSwift("error", { message });
  }
}

async function stopRealtime({ notify = true, updateStatus = true } = {}) {
  if (!isRunning && !pc && !localStream) {
    if (notify) {
      postToSwift("sessionStopped", { transcript: currentTranscript() });
    }
    return;
  }

  isStopping = true;
  clearManualTranscriptCommits();
  clearTodoExtractionTimer();

  if (updateStatus) {
    setStatus(notify ? "Finishing" : "Stopping", "connecting");
  }
  stopButton.disabled = true;

  if (notify) {
    await new Promise((resolve) => setTimeout(resolve, 250));
    commitInputAudio();
  }

  try {
    pc?.getSenders().forEach((sender) => sender.track?.stop());
  } catch {}

  localStream?.getTracks().forEach((track) => track.stop());

  if (notify) {
    await new Promise((resolve) => setTimeout(resolve, 1_200));
    await waitForCurrentTodoExtraction();
    await requestTodoExtraction({ final: true });
  }

  try {
    dc?.close();
  } catch {}

  try {
    pc?.close();
  } catch {}

  dc = null;
  pc = null;
  localStream = null;
  isRunning = false;
  setControls(false);
  if (updateStatus) {
    setStatus("Stopped", "");
  }

  if (notify) {
    postToSwift("sessionStopped", { transcript: currentTranscript() });
  }
}

window.startRealtimeFromNative = startRealtime;
window.stopRealtimeFromNative = () => stopRealtime({ notify: true });
window.realtimeCopyAcknowledged = (copyId = "todos") => {
  const buttons = {
    all: copyAllButton,
    transcript: copyTranscriptButton,
    todos: copyTodosButton,
  };
  const button = buttons[copyId] ?? copyTodosButton;
  button.classList.add("copied");
  setTimeout(() => {
    button.classList.remove("copied");
  }, 900);
};

function copySection(copyId, text) {
  if (!text.trim()) {
    return;
  }
  postToSwift("copyText", { copyId, text });
}

startButton.addEventListener("click", () => postToSwift("startRequested"));
stopButton.addEventListener("click", () => stopRealtime({ notify: true }));
copyAllButton.addEventListener("click", () => copySection("all", copyAllText()));
copyTranscriptButton.addEventListener("click", () => copySection("transcript", currentTranscript()));
copyTodosButton.addEventListener("click", () => copySection("todos", copyTodosText()));

renderTranscript();
renderTodos();

const params = new URLSearchParams(window.location.search);
if (params.get("autostart") === "1") {
  startRealtime();
}
