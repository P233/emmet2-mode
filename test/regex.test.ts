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
Deno.test(":n(:l-c):af", () => assertEquals(selectorRegex.test(":n(:l-c):af"), true));

const propertyRegex = /^-?[a-z]+((\(-?\d*\.?\d+\))*|--[\w-]+|\[.+?\])!?$/;

Deno.test("!", () => assertEquals(propertyRegex.test("!"), false));
Deno.test("t0", () => assertEquals(propertyRegex.test("t0"), false));
Deno.test("t1p", () => assertEquals(propertyRegex.test("t1p"), false));
Deno.test("p1px2px3px", () => assertEquals(propertyRegex.test("p1px2px3px"), false));
Deno.test("t$abc", () => assertEquals(propertyRegex.test("t$abc"), false));
Deno.test("p$a$b$c", () => assertEquals(propertyRegex.test("p$a$b$c"), false));
Deno.test("p$a$b$c!", () => assertEquals(propertyRegex.test("p$a$b$c!"), false));

Deno.test("t(0.5)", () => assertEquals(propertyRegex.test("t(0.5)"), true));
Deno.test("p(1)(2)(3)", () => assertEquals(propertyRegex.test("p(1)(2)(3)"), true));
Deno.test("p(1)(2)(3)!", () => assertEquals(propertyRegex.test("p(1)(2)(3)!"), true));
Deno.test("all--gutter", () => assertEquals(propertyRegex.test("all--gutter"), true));
Deno.test("all--gutter!", () => assertEquals(propertyRegex.test("all--gutter!"), true));
Deno.test("p--a--b--c", () => assertEquals(propertyRegex.test("p--a--b--c"), true));
Deno.test("p--a--b--c!", () => assertEquals(propertyRegex.test("p--a--b--c!"), true));
Deno.test("p[var(--a) var(--b) var(--c)]", () => assertEquals(propertyRegex.test("p[var(--a) var(--b) var(--c)]"), true));
Deno.test("p[var(--a) var(--b) var(--c)]!", () => assertEquals(propertyRegex.test("p[var(--a) var(--b) var(--c)]!"), true));
