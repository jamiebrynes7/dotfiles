import { stat } from "node:fs/promises";
import { z } from "zod";
import { BeanDetail, type BeanResult, type Board, type Fingerprint } from "../shared/rpc.ts";
import { CliError, graphql, type CliOptions } from "./cli.ts";
import { findProject, fingerprintOf } from "./project.ts";

// `isBlocked` covers explicit blockers and a blocked ancestor alike, which is what
// the card's marker means.
const BOARD_FIELDS = `
  beans { id slug path title status implicitStatus type priority parentId updatedAt tags }
  blocked: beans(filter: { isBlocked: true }) { id }`;
const BOARD_QUERY = `{${BOARD_FIELDS}
}`;
// The search text travels only as `$search`; the query itself stays fixed.
const SEARCH_QUERY = `query Board($search: String!) {${BOARD_FIELDS}
  matches: beans(filter: { search: $search }) { id }
}`;

const BoardResponse = z.object({
  beans: z.array(
    z.object({
      id: z.string(),
      slug: z.string().nullable(),
      path: z.string(),
      title: z.string(),
      status: z.string(),
      implicitStatus: z.string().nullable(),
      type: z.string(),
      priority: z.string().nullable(),
      parentId: z.string().nullable(),
      updatedAt: z.string(),
      tags: z.array(z.string()),
    }),
  ),
  blocked: z.array(z.object({ id: z.string() })),
  matches: z.array(z.object({ id: z.string() })).optional(),
});

export async function readFingerprint(directory: string): Promise<Fingerprint> {
  const project = await findProject(directory);
  if (!project) return { kind: "none", directory };
  return { kind: "project", fingerprint: await fingerprintOf(project) };
}

type ProjectRead<T> = { kind: "none"; directory: string } | ({ kind: "project"; fingerprint: string } & T);

// The fingerprint is taken before the query, so a change landing mid-query shows up
// as a mismatch on the next poll instead of being lost. `empty` answers for a
// project whose data directory is missing, which the CLI refuses but a fresh
// checkout of a project with no beans has (git tracks no empty directories).
async function readProject<T>(
  directory: string,
  empty: T,
  query: () => Promise<T>,
): Promise<ProjectRead<T>> {
  const project = await findProject(directory);
  if (!project) return { kind: "none", directory };
  const fingerprint = await fingerprintOf(project);
  const hasData = await stat(project.dataDir).then(
    () => true,
    (error: NodeJS.ErrnoException) => {
      if (error.code === "ENOENT") return false;
      throw error;
    },
  );
  return { kind: "project", fingerprint, ...(hasData ? await query() : empty) };
}

function parse<Schema extends z.ZodType>(schema: Schema, data: unknown, what: string): z.output<Schema> {
  const parsed = schema.safeParse(data);
  if (!parsed.success) {
    throw new Error(`beans returned an unexpected ${what} shape: ${z.prettifyError(parsed.error)}`);
  }
  return parsed.data;
}

// What the CLI prints when Bleve's query-string parser rejects the search text: a
// grammar error (`title:` with no term), a lexer error (an unclosed quote, a bad
// fuzziness), or a bad `/regexp/`. A GraphQL error in our own fixed query reads
// differently, so it is never mistaken for one.
const SEARCH_PARSE_ERROR = /^Error: graphql: (syntax error|parse error: .*|error parsing regexp: .*)$/m;

/**
 * Every bean, plus the ids the CLI's full-text `search` matches when one is given.
 * A search the CLI cannot parse matches nothing and says why in `searchError`, since
 * half-typed queries (`title:`) hit that constantly; the beans then come from a
 * second, unsearched read, so the client can still show the full board at once
 * when the box is cleared.
 * A blank search is no search: the CLI would match every bean.
 */
export function readBoard(
  directory: string,
  search: string | null,
  options: CliOptions = {},
): Promise<Board> {
  const query = search?.trim() || null;
  const empty = { beans: [], matches: query === null ? null : [], searchError: null };
  return readProject(directory, empty, async () => {
    if (query === null) {
      return { ...toBoard(await graphql(directory, BOARD_QUERY, {}, options)), searchError: null };
    }
    let response;
    try {
      response = await graphql(directory, SEARCH_QUERY, { search: query }, options);
    } catch (error) {
      const parseError = error instanceof CliError && SEARCH_PARSE_ERROR.exec(error.stderr);
      if (!parseError) throw error;
      const { beans } = toBoard(await graphql(directory, BOARD_QUERY, {}, options));
      return { beans, matches: [], searchError: parseError[1] };
    }
    const board = toBoard(response);
    if (!board.matches) throw new Error("beans returned no search matches");
    return { ...board, searchError: null };
  });
}

function toBoard(response: unknown) {
  const data = parse(BoardResponse, response, "board");
  const blocked = new Set(data.blocked.map((bean) => bean.id));
  return {
    beans: data.beans.map(({ path, ...bean }) => ({
      ...bean,
      priority: bean.priority ?? "normal",
      blocked: blocked.has(bean.id),
      // The schema has no archived field; the CLI reports only the file's location.
      archived: path.startsWith("archive/"),
    })),
    matches: data.matches?.map((bean) => bean.id) ?? null,
  };
}

const BEAN_QUERY = `query Bean($id: ID!) {
  bean(id: $id) {
    id slug title status implicitStatus type priority tags body createdAt updatedAt
    parent { id title status type }
    blockedBy { id title status type }
    children { id title status type }
  }
}`;

const BeanResponse = z.object({
  bean: BeanDetail.extend({ priority: z.string().nullable() }).nullable(),
});

export function readBean(
  directory: string,
  beanId: string,
  options: CliOptions = {},
): Promise<BeanResult> {
  return readProject(directory, { bean: null }, async () => {
    const data = parse(BeanResponse, await graphql(directory, BEAN_QUERY, { id: beanId }, options), "bean");
    return { bean: data.bean && { ...data.bean, priority: data.bean.priority ?? "normal" } };
  });
}
