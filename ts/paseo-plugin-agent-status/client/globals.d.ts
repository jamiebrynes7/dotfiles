// Declared by hand because tsconfig leaves out the DOM lib: upstream's cross-platform
// rules forbid it, since browser-only APIs typecheck there and then crash on iOS and
// Android. These exist on every platform the app runs on.
declare function setInterval(handler: () => void, timeout: number): number;
declare function clearInterval(id: number | undefined): void;
