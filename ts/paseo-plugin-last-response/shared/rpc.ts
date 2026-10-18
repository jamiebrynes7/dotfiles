import { defineRpc } from "@getpaseo/plugin";
import { z } from "zod";

/** When each agent's latest turn ended (epoch millis), as recorded by the daemon half. */
export const listResponseTimes = defineRpc({
  name: "last-response.list",
  input: z.object({}),
  output: z.object({ respondedAt: z.record(z.string(), z.number()) }),
});
