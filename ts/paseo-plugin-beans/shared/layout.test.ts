import assert from "node:assert/strict";
import { test } from "node:test";
import { columnCounts, laneCount, layout, progress, type Lane } from "./layout.ts";
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

function cellShape(cells: Lane["rows"][number]["cells"]) {
  return Object.fromEntries(
    cells.filter((cell) => cell.cards.length > 0).map((cell) => [
      cell.column,
      cell.cards.map((card) => card.id),
    ]),
  );
}

// Lane epic id (or null) → column → card ids across all rows, for compact assertions.
function shape(lanes: Lane[]) {
  return lanes.map((lane) => ({
    epic: lane.epic?.id ?? null,
    cells: cellShape(
      lane.rows[0].cells.map((cell, index) => ({
        column: cell.column,
        cards: lane.rows.flatMap((row) => row.cells[index].cards),
      })),
    ),
  }));
}

// Lane epic id (or null) → rows, each its feature id (or null) and column → card ids.
function rows(lanes: Lane[]) {
  return lanes.map((lane) => ({
    epic: lane.epic?.id ?? null,
    rows: lane.rows.map((row) => ({ feature: row.feature?.id ?? null, cells: cellShape(row.cells) })),
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
  assert.deepEqual(layout(beans, false, false)[0].rows[0].cells.map((cell) => cell.column), [
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

test("a match set places only matching cards and drops lanes left without any", () => {
  const beans = [
    bean("e1", { type: "epic" }),
    bean("t1", { parentId: "e1" }),
    bean("t2", { parentId: "e1" }),
    bean("e2", { type: "epic" }),
    bean("t3", { parentId: "e2" }),
    bean("loose"),
  ];
  assert.deepEqual(shape(layout(beans, false, false, new Set(["t2", "loose"]))), [
    { epic: "e1", cells: { todo: ["t2"] } },
    { epic: null, cells: { todo: ["loose"] } },
  ]);
  assert.deepEqual(shape(layout(beans, false, false, new Set())), []);
});

test("a matching card keeps its lane even when only the epic is archived or unmatched", () => {
  const beans = [
    bean("e1", { type: "epic", status: "completed", archived: true }),
    bean("t1", { parentId: "e1", status: "completed" }),
  ];
  assert.deepEqual(shape(layout(beans, false, false, new Set(["t1"]))), [
    { epic: "e1", cells: { completed: ["t1"] } },
  ]);
});

test("a match set does not override the scrapped and archived toggles", () => {
  const beans = [bean("s", { status: "scrapped" }), bean("a", { archived: true }), bean("t")];
  const all = new Set(["s", "a", "t"]);
  assert.deepEqual(shape(layout(beans, false, false, all)), [{ epic: null, cells: { todo: ["t"] } }]);
  assert.deepEqual(shape(layout(beans, true, true, all)), [
    { epic: null, cells: { todo: ["a", "t"], scrapped: ["s"] } },
  ]);
});

test("a matching epic keeps its whole lane, still subject to the toggles", () => {
  const beans = [
    bean("e1", { type: "epic" }),
    bean("t1", { parentId: "e1" }),
    bean("t2", { parentId: "e1", status: "in-progress" }),
    bean("t3", { parentId: "e1", archived: true }),
    bean("e2", { type: "epic" }),
    bean("t4", { parentId: "e2" }),
  ];
  assert.deepEqual(shape(layout(beans, false, false, new Set(["e1"]))), [
    { epic: "e1", cells: { todo: ["t1"], "in-progress": ["t2"] } },
  ]);
});

test("cards file into the row of their nearest feature, with Other last", () => {
  const lanes = layout(
    [
      bean("e1", { type: "epic" }),
      bean("f1", { type: "feature", parentId: "e1", status: "in-progress" }),
      bean("t1", { parentId: "f1" }),
      bean("b1", { type: "bug", parentId: "f1", status: "completed" }),
      bean("f2", { type: "feature", parentId: "e1" }),
      bean("sub", { parentId: "t1", status: "draft" }),
      bean("t2", { parentId: "e1" }),
      bean("f3", { type: "feature", parentId: "e1", status: "draft" }),
    ],
    false,
    false,
  );
  assert.deepEqual(rows(lanes), [
    {
      epic: "e1",
      rows: [
        { feature: "f1", cells: { draft: ["sub"], todo: ["t1"], "in-progress": ["f1"], completed: ["b1"] } },
        { feature: null, cells: { draft: ["f3"], todo: ["f2", "t2"] } },
      ],
    },
  ]);
});

test("features without an epic get rows in the No epic lane", () => {
  const lanes = layout(
    [bean("f1", { type: "feature" }), bean("t1", { parentId: "f1" }), bean("loose")],
    false,
    false,
  );
  assert.deepEqual(rows(lanes), [
    {
      epic: null,
      rows: [
        { feature: "f1", cells: { todo: ["f1", "t1"] } },
        { feature: null, cells: { todo: ["loose"] } },
      ],
    },
  ]);
});

test("a lane with no features has a single unlabelled row", () => {
  const lanes = layout([bean("e1", { type: "epic" }), bean("t1", { parentId: "e1" })], false, false);
  assert.deepEqual(rows(lanes), [{ epic: "e1", rows: [{ feature: null, cells: { todo: ["t1"] } }] }]);
});

test("a lane with only feature rows has no Other row", () => {
  const lanes = layout(
    [bean("e1", { type: "epic" }), bean("f1", { type: "feature", parentId: "e1" }), bean("t1", { parentId: "f1" })],
    false,
    false,
  );
  assert.deepEqual(rows(lanes), [{ epic: "e1", rows: [{ feature: "f1", cells: { todo: ["f1", "t1"] } }] }]);
});

test("a feature whose descendants are all hidden is a plain card in Other", () => {
  const lanes = layout(
    [
      bean("f1", { type: "feature" }),
      bean("s", { parentId: "f1", status: "scrapped" }),
      bean("a", { parentId: "f1", archived: true }),
    ],
    false,
    false,
  );
  assert.deepEqual(rows(lanes), [{ epic: null, rows: [{ feature: null, cells: { todo: ["f1"] } }] }]);
});

test("feature rows order by status group, then priority, then title", () => {
  const features = [
    bean("f-done", { type: "feature", status: "completed" }),
    bean("f-todo-b", { type: "feature", title: "B" }),
    bean("f-todo-a", { type: "feature", title: "A" }),
    bean("f-todo-hi", { type: "feature", title: "Z", priority: "high" }),
    bean("f-draft", { type: "feature", status: "draft" }),
    bean("f-wip", { type: "feature", status: "in-progress" }),
  ];
  const lanes = layout(
    [...features, ...features.map((f) => bean(`c-${f.id}`, { parentId: f.id })), bean("loose")],
    false,
    false,
  );
  assert.deepEqual(
    lanes[0].rows.map((row) => row.feature?.id ?? null),
    ["f-wip", "f-todo-hi", "f-todo-a", "f-todo-b", "f-draft", "f-done", null],
  );
});

test("the feature card comes first in its cell, whatever its priority", () => {
  const lanes = layout(
    [
      bean("f1", { type: "feature", priority: "low" }),
      bean("t1", { parentId: "f1", priority: "critical" }),
    ],
    false,
    false,
  );
  assert.deepEqual(rows(lanes)[0].rows[0].cells, { todo: ["f1", "t1"] });
});

test("rows of completed or scrapped features start collapsed; Other never does", () => {
  const lanes = layout(
    [
      bean("f-open", { type: "feature" }),
      bean("f-done", { type: "feature", status: "completed" }),
      bean("f-gone", { type: "feature", status: "scrapped" }),
      bean("a", { parentId: "f-open" }),
      bean("b", { parentId: "f-done", implicitStatus: "completed" }),
      bean("c", { parentId: "f-gone", implicitStatus: "scrapped" }),
      bean("d"),
    ],
    true,
    false,
  );
  assert.deepEqual(
    lanes[0].rows.map((row) => [row.feature?.id ?? null, row.collapsedByDefault]),
    [
      ["f-open", false],
      ["f-done", true],
      ["f-gone", true],
      [null, false],
    ],
  );
});

test("progress counts non-scrapped descendants, done by effective status, ignoring toggles", () => {
  const counts = progress([
    bean("f1", { type: "feature" }),
    bean("t1", { parentId: "f1", status: "completed", archived: true }),
    bean("t2", { parentId: "f1" }),
    bean("t3", { parentId: "f1", status: "scrapped" }),
    bean("sub", { parentId: "t2", implicitStatus: "completed" }),
    bean("f2", { type: "feature" }),
    bean("e1", { type: "epic" }),
    bean("t4", { parentId: "e1" }),
  ]);
  assert.deepEqual(Object.fromEntries(counts), { f1: { done: 2, total: 3 } });
});

test("a feature matching nothing heads its row as context for a matching descendant", () => {
  const beans = [
    bean("f1", { type: "feature" }),
    bean("t1", { parentId: "f1" }),
    bean("t2", { parentId: "f1" }),
    bean("loose"),
  ];
  const lanes = layout(beans, false, false, new Set(["t1"]));
  assert.deepEqual(rows(lanes), [{ epic: null, rows: [{ feature: "f1", cells: { todo: ["f1", "t1"] } }] }]);
  assert.equal(lanes[0].rows[0].featureIsContext, true);
});

test("a matching feature shows every visible card in its row", () => {
  const beans = [
    bean("f1", { type: "feature" }),
    bean("t1", { parentId: "f1" }),
    bean("t2", { parentId: "f1", archived: true }),
    bean("loose"),
  ];
  const lanes = layout(beans, false, false, new Set(["f1"]));
  assert.deepEqual(rows(lanes), [{ epic: null, rows: [{ feature: "f1", cells: { todo: ["f1", "t1"] } }] }]);
  assert.equal(lanes[0].rows[0].featureIsContext, false);
});

test("a matching epic shows its feature rows whole", () => {
  const beans = [
    bean("e1", { type: "epic" }),
    bean("f1", { type: "feature", parentId: "e1" }),
    bean("t1", { parentId: "f1" }),
    bean("t2", { parentId: "e1" }),
  ];
  assert.deepEqual(rows(layout(beans, false, false, new Set(["e1"]))), [
    {
      epic: "e1",
      rows: [
        { feature: "f1", cells: { todo: ["f1", "t1"] } },
        { feature: null, cells: { todo: ["t2"] } },
      ],
    },
  ]);
});

test("an archived feature still heads the row of its unarchived descendants, as context", () => {
  const beans = [bean("f1", { type: "feature", archived: true }), bean("t1", { parentId: "f1" })];
  const hidden = layout(beans, false, false);
  assert.deepEqual(rows(hidden), [{ epic: null, rows: [{ feature: "f1", cells: { todo: ["f1", "t1"] } }] }]);
  assert.equal(hidden[0].rows[0].featureIsContext, true);
  assert.equal(layout(beans, false, true)[0].rows[0].featureIsContext, false);
});

test("counts leave out context cards", () => {
  const beans = [
    bean("f1", { type: "feature", status: "in-progress" }),
    bean("t1", { parentId: "f1" }),
    bean("t2", { parentId: "f1" }),
    bean("loose"),
  ];
  const [searched] = layout(beans, false, false, new Set(["t1", "loose"]));
  assert.equal(laneCount(searched), 2);
  assert.deepEqual(columnCounts(searched), [0, 2, 0, 0]);
  const [full] = layout(beans, false, false);
  assert.equal(laneCount(full), 4);
  assert.deepEqual(columnCounts(full), [0, 3, 1, 0]);
});

test("a feature above the lane's epic does not claim its cards", () => {
  const beans = [
    bean("f0", { type: "feature" }),
    bean("e1", { type: "epic", parentId: "f0" }),
    bean("t1", { parentId: "e1" }),
  ];
  assert.deepEqual(rows(layout(beans, false, false)), [
    { epic: "e1", rows: [{ feature: null, cells: { todo: ["t1"] } }] },
    { epic: null, rows: [{ feature: null, cells: { todo: ["f0"] } }] },
  ]);
  assert.deepEqual(Object.fromEntries(progress(beans)), {});
});

test("nested features each head their own row", () => {
  const beans = [
    bean("e1", { type: "epic" }),
    bean("f1", { type: "feature", parentId: "e1", status: "in-progress" }),
    bean("f2", { type: "feature", parentId: "f1" }),
    bean("t1", { parentId: "f2", status: "completed" }),
  ];
  assert.deepEqual(rows(layout(beans, false, false)), [
    {
      epic: "e1",
      rows: [
        { feature: "f1", cells: { "in-progress": ["f1"] } },
        { feature: "f2", cells: { todo: ["f2"], completed: ["t1"] } },
      ],
    },
  ]);
  assert.deepEqual(Object.fromEntries(progress(beans)), {
    f1: { done: 1, total: 2 },
    f2: { done: 1, total: 1 },
  });
});

test("a dangling parent or a feature cycle files into Other without hanging", () => {
  const lanes = layout(
    [
      bean("orphan", { parentId: "missing" }),
      bean("fa", { type: "feature", parentId: "fb" }),
      bean("fb", { type: "feature", parentId: "fa" }),
    ],
    false,
    false,
  );
  assert.deepEqual(rows(lanes), [
    {
      epic: null,
      rows: [
        { feature: "fa", cells: { todo: ["fa"] } },
        { feature: "fb", cells: { todo: ["fb"] } },
        { feature: null, cells: { todo: ["orphan"] } },
      ],
    },
  ]);
});

test("a feature in a hidden column heads no row; its cards fall to Other", () => {
  const lanes = layout(
    [bean("f1", { type: "feature", status: "scrapped" }), bean("t1", { parentId: "f1", status: "completed" })],
    false,
    false,
  );
  assert.deepEqual(rows(lanes), [{ epic: null, rows: [{ feature: null, cells: { completed: ["t1"] } }] }]);
});

test("search and archive together: an archived, unmatched feature is context for a match", () => {
  const beans = [
    bean("f1", { type: "feature", archived: true }),
    bean("t1", { parentId: "f1" }),
    bean("t2", { parentId: "f1" }),
  ];
  const [lane] = layout(beans, false, false, new Set(["t1"]));
  assert.deepEqual(rows([lane]), [{ epic: null, rows: [{ feature: "f1", cells: { todo: ["f1", "t1"] } }] }]);
  assert.equal(lane.rows[0].featureIsContext, true);
  assert.equal(layout(beans, false, false, new Set(["f1"]))[0].rows[0].featureIsContext, true);
});
