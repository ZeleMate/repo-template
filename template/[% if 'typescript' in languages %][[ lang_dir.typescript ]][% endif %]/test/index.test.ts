import fc from "fast-check";
import { describe, expect, it } from "vitest";

import { greet } from "../src/index.js";

describe("greet", () => {
  it("greets by name", () => {
    expect(greet("world")).toBe("Hello, world!");
  });

  it("always contains the name", () => {
    fc.assert(
      fc.property(fc.string(), (name) => {
        expect(greet(name)).toContain(name);
      }),
    );
  });
});
