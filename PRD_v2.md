# PRD v2: Showcasing Genkit in a Flutter GenUI Shopping Assistant

## Context

We have a Flutter web app — a GenUI shopping assistant that was migrated from Firebase AI to Genkit. The basic migration works but barely showcases Genkit's capabilities. The app just calls `generate()` with tools, which isn't meaningfully different from what Firebase AI did.

**Goal:** Enhance the app to actually demonstrate why Genkit matters — flows, middleware, custom tools, structured output — and write a blog post that documents these features for developers evaluating Genkit for their Flutter apps.

## Starting Point

Branch: `genkit-refactor` (commit `9b74bf6`)

The app already has:
- `GenkitContentGenerator` implementing GenUI's `ContentGenerator` interface
- Three GenUI tools registered with proper `inputSchema` via `A2uiSchemas`
- Gemini 2.5 Flash with thinking disabled (`thinkingBudget: 0`)
- Working product cards, carousels, and price filters

## Two-Loop Architecture

This PRD is executed by **two parallel Ralph loops**:

1. **Ralph-Code** — implements one code task at a time, commits, marks it done in `progress_code.txt`
2. **Ralph-Blog** — watches `progress_code.txt` for completed tasks, reviews the git diff, and writes the corresponding blog section in `blog_v2.md`

Ralph-Blog should NOT write code. Ralph-Code should NOT write blog content.

## Output Files

- **`progress_code.txt`** — Updated by Ralph-Code after each task. Format: `Task N: DONE — <one-line summary>`
- **`progress_blog.txt`** — Updated by Ralph-Blog after each section. Format: `Section for Task N: DONE`
- **`blog_v2.md`** — The blog post, built incrementally by Ralph-Blog.

## CRITICAL RULES

### For Ralph-Code:
- **ONE TASK PER ITERATION.** Do not attempt multiple tasks.
- After each task: run `flutter build web --dart-define=GOOGLE_API_KEY=$GOOGLE_API_KEY` to verify compilation
- Commit changes with a conventional commit message
- Update `progress_code.txt` with exactly one line: `Task N: DONE — <summary>`
- Do NOT write blog content, do NOT modify `blog_v2.md`

### For Ralph-Blog:
- Check `progress_code.txt` for the next task marked DONE that doesn't have a corresponding section in `blog_v2.md`
- If no new completed task, output `<promise>WAITING</promise>` and stop
- Read the git diff for that task's commit to understand what changed
- Write one blog section for that task, appending to `blog_v2.md`
- Update `progress_blog.txt`
- Do NOT write code, do NOT modify any `.dart`, `.yaml`, or config files

## Blog Guidelines

- Write for a Flutter developer evaluating Genkit — they want to see what Genkit can do that Firebase AI can't
- Show code snippets from the actual committed code (read the files, don't invent code)
- Explain the **why** not just the **what** — what problem does each Genkit feature solve?
- Keep it concise: each section should be 150-300 words + code snippets
- No emojis in prose. One at the very end is fine.
- Don't start sections with "In this section we'll..." — just start with the interesting part

## Important Technical Notes

- This is a **Flutter web** app. Run with `flutter run -d chrome --web-port=8080 --dart-define=GOOGLE_API_KEY=$GOOGLE_API_KEY`
- Genkit Dart is v0.12.0 with `genkit_google_genai` v0.2.3
- Gemini 2.5 Flash requires `ThinkingConfig(thinkingBudget: 0, includeThoughts: false)` to avoid null parsing bugs in the plugin
- The `schemantic` package is used for tool schemas, `json_schema_builder` for GenUI's A2uiSchemas
- Run `flutter pub get` after modifying pubspec.yaml
- After each code change, verify with `flutter build web`

---

## Code Tasks

### Task 1: Wrap content generation in a Genkit Flow

Right now, `sendRequest()` calls `_genkit.generate()` directly. Wrap it in a Genkit flow using `_genkit.defineFlow()`.

- [ ] Define a `shoppingAssistantFlow` using `_genkit.defineFlow()`
- [ ] The flow should encapsulate the generate call with tools
- [ ] Use proper `inputSchema` and `outputSchema` for the flow
- [ ] Call the flow from `sendRequest()` instead of calling `generate()` directly
- [ ] Verify the app still works (build succeeds)

**Why this matters for the blog:** Flows are Genkit's core abstraction — named, observable, composable units of AI work. This is the #1 thing that differentiates Genkit from raw API calls.

### Task 2: Add retry middleware

Add Genkit's built-in retry middleware to the generate call to handle transient Gemini API failures gracefully.

- [ ] Import and configure the `retry` middleware from `package:genkit/genkit.dart`
- [ ] Add it to the `generate()` call via the `use` parameter
- [ ] Configure reasonable defaults: 3 retries, exponential backoff, retry on UNAVAILABLE/RESOURCE_EXHAUSTED
- [ ] Verify build succeeds

**Why this matters for the blog:** Shows Genkit's middleware system — pluggable, composable request processing that you'd otherwise have to build yourself.

### Task 3: Add a custom "product search" tool

Add a tool beyond UI rendering — a `searchProducts` tool that the model can call to "search" for products by category/query. This demonstrates Genkit's tool system for business logic, not just UI.

- [ ] Define a `searchProducts` tool with `inputSchema` (query string, optional category, optional maxResults)
- [ ] Implement it with hardcoded product data (no real backend needed — this is a demo)
- [ ] The tool should return product data that the model can then render using the existing `surfaceUpdate`/`beginRendering` tools
- [ ] Register the tool alongside the existing GenUI tools
- [ ] Update the system prompt to tell the model about the search tool
- [ ] Verify build succeeds and the model uses the tool in conversation

**Why this matters for the blog:** Shows how Genkit tools go beyond UI rendering — you can give the model access to business logic, databases, APIs.

### Task 4: Add structured output for product recommendations

Use Genkit's structured output (`outputSchema`) to get typed product recommendation data from the model, instead of relying only on tool calls for structured responses.

- [ ] Define a `ProductRecommendation` schema using `schemantic` (or manual `SchemanticType.from()`)
- [ ] Create a helper method or flow that uses `outputSchema` to get structured recommendations
- [ ] Use this for a "quick recommendation" feature — e.g., when the user asks "what should I buy?"
- [ ] Verify build succeeds

**Why this matters for the blog:** Structured output is one of Genkit's most practical features — guaranteed JSON conforming to a schema, no parsing gymnastics.

### Task 5: Add conversation context/memory

Use Genkit's context system to pass conversation metadata (user preferences, cart state) through the generation pipeline.

- [ ] Define a simple in-memory cart/preferences state
- [ ] Pass it via the `context` parameter on `generate()`
- [ ] Access it in tool handlers to personalize responses (e.g., "you already have X in your cart")
- [ ] Verify build succeeds

**Why this matters for the blog:** Shows how Genkit's context flows through the entire pipeline — tools, middleware, flows all have access to shared state.

### Task 6: Final polish and cleanup

- [ ] Review all code for consistency
- [ ] Remove any debug prints or unused imports
- [ ] Ensure all tools have proper descriptions
- [ ] Run `flutter build web` one final time
- [ ] Update `progress_code.txt` with COMPLETE

---

## Blog Structure (for Ralph-Blog reference)

Ralph-Blog should produce `blog_v2.md` with roughly this structure. Each section corresponds to a code task:

1. **Introduction** — What we're building, why Genkit (write this before any code tasks are done, based on the PRD context)
2. **Section for Task 1** — Genkit Flows: from raw API calls to observable pipelines
3. **Section for Task 2** — Middleware: retry logic you don't have to write
4. **Section for Task 3** — Custom tools: giving the model access to your business logic
5. **Section for Task 4** — Structured output: typed responses without parsing
6. **Section for Task 5** — Context: threading state through the AI pipeline
7. **Conclusion** — What we gained, next steps, links (write this after all code tasks are done)

Each section should:
- Open with the problem/motivation (1-2 sentences)
- Show the key code snippet from the actual diff
- Explain what Genkit is doing and why it matters
- Close with what the user sees or what this enables
