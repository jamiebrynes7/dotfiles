## Red flags:

- `==` instead of `===`
- `any` type abuse
- Missing null checks before property access
- `var` in modern codebases
- Uncontrolled re-renders in React (missing memoization, unstable references)
- `useEffect` dependency array lies, stale closures, missing cleanup functions
- `key` prop abuse (using index as key for dynamic lists)
- Inline object/function props causing unnecessary re-renders
- Unhandled promise rejections
- Missing `await` on async calls
