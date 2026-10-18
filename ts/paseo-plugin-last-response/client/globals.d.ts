// The runtime globals this plugin uses, declared by hand because tsconfig leaves out
// the DOM lib: upstream's cross-platform rules forbid it, since browser-only APIs
// typecheck there and then crash on iOS and Android. All of these exist on every
// platform the app runs on.
declare const console: {
  warn(...data: unknown[]): void;
  error(...data: unknown[]): void;
};
declare function setInterval(handler: () => void, timeout: number): number;
declare function clearInterval(id: number): void;
// Opaque: only here so `lifetime.signal` has a type to hand to the SDK.
interface AbortSignal {}
declare class AbortController {
  readonly signal: AbortSignal;
  abort(): void;
}
declare function setTimeout(handler: () => void, timeout: number): number;
declare function clearTimeout(id: number | undefined): void;
