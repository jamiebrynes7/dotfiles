import assert from "node:assert/strict";
import { test } from "node:test";
import { layout, type Lane } from "./layout.ts";
import type { BoardBean } from "./rpc.ts";

function bean(id: string, fields: Partial<BoardBean> = {}): BoardBean {
  return {
    id,
    slug: id,
    title: id,
    status: "todo",
    implicitStatus: null,
    type: "task",
    priority: "normal",
    parentId: null,
    updatedAt: "2026-01-01T00:00:00Z",
    tags: [],
    blocked: false,
    archived: false,
    ...fields,
  };
}

// Lane epic id (or null) → column → card ids, for compact assertions.
function shape(lanes: Lane[]) {
  return lanes.map((lane) => ({
    epic: lane.epic?.id ?? null,
    cells: Object.fromEntries(
      lane.cells.filter((cell) => cell.cards.length > 0).map((cell) => [
        cell.column,
        cell.cards.map((card) => card.id),
      ]),
    ),
  }));
}

test("cards file under their nearest epic ancestor, with No epic last", () => {
  const lanes = layout(
    [
      bean("loose"),
      bean("e1", { type: "epic" }),
      bean("f1", { type: "feature", parentId: "e1" }),
      bean("t1", { parentId: "f1", status: "in-progress" }),
      bean("m1", { type: "milestone" }),
      bean("t2", { parentId: "m1" }),
    ],
    false,
    false,
  );
  assert.deepEqual(shape(lanes), [
    { epic: "e1", cells: { todo: ["f1"], "in-progress": ["t1"] } },
    { epic: null, cells: { todo: ["loose", "t2"] } },
  ]);
});

test("an inherited terminal status wins over the bean's own", () => {
  const lanes = layout(
    [
      bean("e1", { type: "epic", status: "completed" }),
      bean("t1", { parentId: "e1", status: "todo", implicitStatus: "completed" }),
    ],
    false,
    false,
  );
  assert.deepEqual(shape(lanes), [{ epic: "e1", cells: { completed: ["t1"] } }]);
});

test("scrapped cards appear only with the toggle on", () => {
  const beans = [bean("a"), bean("s", { status: "scrapped" })];
  assert.deepEqual(layout(beans, false, false)[0].cells.map((cell) => cell.column), [
    "draft",
    "todo",
    "in-progress",
    "completed",
  ]);
  assert.deepEqual(shape(layout(beans, false, false)), [{ epic: null, cells: { todo: ["a"] } }]);
  assert.deepEqual(shape(layout(beans, true, false)), [
    { epic: null, cells: { todo: ["a"], scrapped: ["s"] } },
  ]);
});

test("archived cards appear only with the toggle on", () => {
  const beans = [bean("a"), bean("old", { status: "completed", archived: true })];
  assert.deepEqual(shape(layout(beans, false, false)), [{ epic: null, cells: { todo: ["a"] } }]);
  assert.deepEqual(shape(layout(beans, false, true)), [
    { epic: null, cells: { todo: ["a"], completed: ["old"] } },
  ]);
});

test("the scrapped and archived toggles are independent", () => {
  const beans = [bean("gone", { status: "scrapped", archived: true })];
  assert.deepEqual(shape(layout(beans, true, false)), []);
  assert.deepEqual(shape(layout(beans, false, true)), []);
  assert.deepEqual(shape(layout(beans, true, true)), [
    { epic: null, cells: { scrapped: ["gone"] } },
  ]);
});

test("an archived epic still heads the lane of its unarchived cards", () => {
  const lanes = layout(
    [
      bean("e1", { type: "epic", status: "completed", archived: true }),
      bean("kept", { parentId: "e1", implicitStatus: "completed" }),
      bean("old", { parentId: "e1", implicitStatus: "completed", archived: true }),
    ],
    false,
    false,
  );
  assert.deepEqual(shape(lanes), [{ epic: "e1", cells: { completed: ["kept"] } }]);
});

test("a lane whose cards are all archived is omitted", () => {
  const lanes = layout(
    [
      bean("e1", { type: "epic", status: "completed", archived: true }),
      bean("old", { parentId: "e1", implicitStatus: "completed", archived: true }),
    ],
    false,
    false,
  );
  assert.deepEqual(shape(lanes), []);
});

test("a lane with no visible cards is omitted", () => {
  const lanes = layout(
    [
      bean("empty", { type: "epic" }),
      bean("gone", { type: "epic" }),
      bean("s", { parentId: "gone", status: "scrapped" }),
    ],
    false,
    false,
  );
  assert.deepEqual(shape(lanes), []);
});

test("lanes of completed or scrapped epics start collapsed", () => {
  const lanes = layout(
    [
      bean("open", { type: "epic" }),
      bean("done", { type: "epic", status: "completed" }),
      bean("dropped", { type: "epic", status: "scrapped" }),
      bean("a", { parentId: "open" }),
      bean("b", { parentId: "done", implicitStatus: "completed" }),
      bean("c", { parentId: "dropped", implicitStatus: "scrapped" }),
      bean("d"),
    ],
    true,
    false,
  );
  assert.deepEqual(
    lanes.map((lane) => [lane.epic?.id ?? null, lane.collapsedByDefault]),
    [
      ["open", false],
      ["done", true],
      ["dropped", true],
      [null, false],
    ],
  );
});

test("lanes order by epic priority then title; cards by priority then newest", () => {
  const lanes = layout(
    [
      bean("e-b", { type: "epic", title: "B" }),
      bean("e-a", { type: "epic", title: "A" }),
      bean("e-hi", { type: "epic", title: "Z", priority: "high" }),
      bean("x", { parentId: "e-a", updatedAt: "2026-01-01T00:00:00Z" }),
      bean("y", { parentId: "e-a", updatedAt: "2026-02-01T00:00:00Z" }),
      bean("z", { parentId: "e-a", priority: "critical" }),
      bean("w", { parentId: "e-a", priority: "low", updatedAt: "2026-03-01T00:00:00Z" }),
      bean("p", { parentId: "e-b" }),
      bean("q", { parentId: "e-hi" }),
    ],
    false,
    false,
  );
  assert.deepEqual(shape(lanes), [
    { epic: "e-hi", cells: { todo: ["q"] } },
    { epic: "e-a", cells: { todo: ["z", "y", "x", "w"] } },
    { epic: "e-b", cells: { todo: ["p"] } },
  ]);
});

test("a parent cycle does not hang", () => {
  const lanes = layout([bean("a", { parentId: "b" }), bean("b", { parentId: "a" })], false, false);
  assert.deepEqual(shape(lanes), [{ epic: null, cells: { todo: ["a", "b"] } }]);
});

test("epic lanes group by the epic's status: in progress, todo, draft, completed, scrapped", () => {
  const lanes = layout(
    [
      bean("e-done", { type: "epic", status: "completed" }),
      bean("e-todo", { type: "epic", priority: "low" }),
      bean("e-todo-hi", { type: "epic", priority: "high" }),
      bean("e-draft", { type: "epic", status: "draft" }),
      bean("e-wip", { type: "epic", status: "in-progress" }),
      bean("e-gone", { type: "epic", status: "scrapped" }),
      ...["e-done", "e-todo", "e-todo-hi", "e-draft", "e-wip", "e-gone"].map((epic) =>
        bean(`c-${epic}`, { parentId: epic }),
      ),
      bean("loose"),
    ],
    false,
    false,
  );
  assert.deepEqual(
    lanes.map((lane) => [lane.group, lane.epic?.id ?? null]),
    [
      ["in-progress", "e-wip"],
      ["todo", "e-todo-hi"],
      ["todo", "e-todo"],
      ["draft", "e-draft"],
      ["completed", "e-done"],
      ["scrapped", "e-gone"],
      ["no-epic", null],
    ],
  );
});
