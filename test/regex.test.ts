import { assertEquals } from "https://deno.land/std@0.159.0/testing/asserts.ts";

const selectorRegex = /^[\w.#-]*:[\w-]+(\(.+\))?(:.+)?$/;

Deno.test(":fo", () => assertEquals(selectorRegex.test(":fo"), true));
Deno.test("_:fo", () => assertEquals(selectorRegex.test("_:fo"), true));
Deno.test(".c:fo", () => assertEquals(selectorRegex.test(".c:fo"), true));
Deno.test(".c:f-l", () => assertEquals(selectorRegex.test(".c:f-l"), true));
Deno.test("a.c1.c2#id:fo", () => assertEquals(selectorRegex.test("a.c1.c2#id:fo"), true));
Deno.test("a.c1.c2#id:f-c", () => assertEquals(selectorRegex.test("a.c1.c2#id:f-c"), true));
Deno.test(":n(:f-c)", () => assertEquals(selectorRegex.test(":n(:f-c)"), true));
Deno.test(":n(:f-c,:l-c)", () => assertEquals(selectorRegex.test(":n(:f-c,:l-c)"), true));
Deno.test(":n-c(2n-1)", () => assertEquals(selectorRegex.test(":n-c(2n-1)"), true));
Deno.test(":h(+p)", () => assertEquals(selectorRegex.test(":h(+p)"), true));
Deno.test(":hov:af", () => assertEquals(selectorRegex.test(":hov:af"), true));
Deno.test(":n(:l-c):af", () => assertEquals(selectorRegex.test(":hov:af"), true));
