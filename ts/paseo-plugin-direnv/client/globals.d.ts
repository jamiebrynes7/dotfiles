// The runtime globals the client half uses, declared by hand because tsconfig leaves
// out the DOM lib: upstream's cross-platform rules forbid it, since browser-only APIs
// typecheck there and then crash on iOS and Android. All of these exist on every
// platform the app runs on.
declare const console: {
  error(...data: unknown[]): void;
};
declare function setTimeout(handler: () => void, timeout: number): number;
declare function clearTimeout(id: number | undefined): void;
