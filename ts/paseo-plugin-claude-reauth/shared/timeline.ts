import { z } from "zod";

export const AUTH_EXPIRED_KIND = "auth-expired";

/** `message` is the original reply, kept so the card loses nothing it replaced. */
export const AuthExpiredData = z.object({ message: z.string() });
export type AuthExpiredData = z.infer<typeof AuthExpiredData>;
