import { assertEquals, assertExists, assertMatch, assertNotMatch } from "https://deno.land/std@0.164.0/testing/asserts.ts";
import { SELECTOR_REGEX, SELECTOR_ELEMENTS_REGEX, OPINIONATED_PROPERTY_REGEX, OPINIONATED_ELEMENTS_REGEX, MARKUP_ABBR_REGEX, CSS_IN_JS_NUMBER_REGEX } from "../src/regex.ts";

// SELECTOR_REGEX
Deno.test(":fo", () => assertMatch(":fo", SELECTOR_REGEX));
Deno.test("_:fo", () => assertMatch("_:fo", SELECTOR_REGEX));
Deno.test(".c:fo", () => assertMatch(".c:fo", SELECTOR_REGEX));
Deno.test(".c:f-l", () => assertMatch(".c:f-l", SELECTOR_REGEX));
Deno.test("a.c1.c2#id:fo", () => assertMatch("a.c1.c2#id:fo", SELECTOR_REGEX));
Deno.test("a.c1.c2#id:f-c", () => assertMatch("a.c1.c2#id:f-c", SELECTOR_REGEX));
Deno.test(":n(:f-c)", () => assertMatch(":n(:f-c)", SELECTOR_REGEX));
Deno.test(":n(:f-c,:l-c)", () => assertMatch(":n(:f-c,:l-c)", SELECTOR_REGEX));
Deno.test(":n-c(2n-1)", () => assertMatch(":n-c(2n-1)", SELECTOR_REGEX));
Deno.test(":h(+p)", () => assertMatch(":h(+p)", SELECTOR_REGEX));
Deno.test(":hov:af", () => assertMatch(":hov:af", SELECTOR_REGEX));
Deno.test(":n(:l-c):af", () => assertMatch(":n(:l-c):af", SELECTOR_REGEX));

// SELECTOR_ELEMENTS_REGEX
Deno.test(":be", () => {
  const [_, prefix, pseudoSelector, pseudoFunction, pseudoParams, chainedPseudos] = ":be".match(SELECTOR_ELEMENTS_REGEX)!;
  assertExists(prefix, "");
  assertEquals(pseudoSelector, ":be");
  assertEquals(pseudoFunction, undefined);
  assertEquals(pseudoParams, undefined);
  assertEquals(chainedPseudos, undefined);
});
Deno.test("_:fc:be", () => {
  const [_, prefix, pseudoSelector, pseudoFunction, pseudoParams, chainedPseudos] = ":fc:be".match(SELECTOR_ELEMENTS_REGEX)!;
  assertExists(prefix, "_");
  assertEquals(pseudoSelector, ":fc");
  assertEquals(pseudoFunction, undefined);
  assertEquals(pseudoParams, undefined);
  assertEquals(chainedPseudos, ":be");
});
Deno.test(":n(.a,.b):be", () => {
  const [_, prefix, pseudoSelector, pseudoFunction, pseudoParams, chainedPseudos] = ":n(.a,.b):be".match(SELECTOR_ELEMENTS_REGEX)!;
  assertEquals(prefix, "");
  assertEquals(pseudoSelector, undefined);
  assertEquals(pseudoFunction, ":n");
  assertEquals(pseudoParams, ".a,.b");
  assertEquals(chainedPseudos, ":be");
});
// TODO: ":ntc(2n-1):n(body)::be"

// OPINIONATED_PROPERTY_REGEX
Deno.test("!", () => assertNotMatch("!", OPINIONATED_PROPERTY_REGEX));
Deno.test("t0", () => assertNotMatch("t0", OPINIONATED_PROPERTY_REGEX));
Deno.test("t1p", () => assertNotMatch("t1p", OPINIONATED_PROPERTY_REGEX));
Deno.test("p1px2px3px", () => assertNotMatch("p1px2px3px", OPINIONATED_PROPERTY_REGEX));
Deno.test("t$abc", () => assertNotMatch("t$abc", OPINIONATED_PROPERTY_REGEX));
Deno.test("p$a$b$c", () => assertNotMatch("p$a$b$c", OPINIONATED_PROPERTY_REGEX));
Deno.test("p$a$b$c!", () => assertNotMatch("p$a$b$c!", OPINIONATED_PROPERTY_REGEX));

Deno.test("t(0.5)", () => assertMatch("t(0.5)", OPINIONATED_PROPERTY_REGEX));
Deno.test("p(1)(2)(3)", () => assertMatch("p(1)(2)(3)", OPINIONATED_PROPERTY_REGEX));
Deno.test("p(1)(2)(3)!", () => assertMatch("p(1)(2)(3)!", OPINIONATED_PROPERTY_REGEX));
Deno.test("all--gutter", () => assertMatch("all--gutter", OPINIONATED_PROPERTY_REGEX));
Deno.test("all--gutter!", () => assertMatch("all--gutter!", OPINIONATED_PROPERTY_REGEX));
Deno.test("p--a--b--c", () => assertMatch("p--a--b--c", OPINIONATED_PROPERTY_REGEX));
Deno.test("p--a--b--c!", () => assertMatch("p--a--b--c!", OPINIONATED_PROPERTY_REGEX));
Deno.test("p[var(--a) var(--b) var(--c)]", () => assertMatch("p[var(--a) var(--b) var(--c)]", OPINIONATED_PROPERTY_REGEX));
Deno.test("p[var(--a) var(--b) var(--c)]!", () => assertMatch("p[var(--a) var(--b) var(--c)]!", OPINIONATED_PROPERTY_REGEX));

// OPINIONATED_ELEMENTS_REGEX
Deno.test("p!", () => {
  const [_, propertyName, functionParam, customProperty, rawValue, flag] = "p!".match(OPINIONATED_ELEMENTS_REGEX)!;
  assertExists(propertyName, "p");
  assertEquals(functionParam, undefined);
  assertEquals(customProperty, undefined);
  assertEquals(rawValue, undefined);
  assertEquals(flag, "!");
});
Deno.test("p(1)(2)(3)", () => {
  const [_, propertyName, functionParam, customProperty, rawValue, flag] = "p(1)(2)(3)".match(OPINIONATED_ELEMENTS_REGEX)!;
  assertExists(propertyName, "p");
  assertEquals(functionParam, "(1)(2)(3)");
  assertEquals(customProperty, undefined);
  assertEquals(rawValue, undefined);
  assertEquals(flag, undefined);
});
Deno.test("p--p", () => {
  const [_, propertyName, functionParam, customProperty, rawValue, flag] = "p--p".match(OPINIONATED_ELEMENTS_REGEX)!;
  assertExists(propertyName, "p");
  assertEquals(functionParam, undefined);
  assertEquals(customProperty, "--p");
  assertEquals(rawValue, undefined);
  assertEquals(flag, undefined);
});
Deno.test("p[0 2px]", () => {
  const [_, propertyName, functionParam, customProperty, rawValue, flag] = "p[0 2px]".match(OPINIONATED_ELEMENTS_REGEX)!;
  assertExists(propertyName, "p");
  assertEquals(functionParam, undefined);
  assertEquals(customProperty, undefined);
  assertEquals(rawValue, "[0 2px]");
  assertEquals(flag, undefined);
});

// MARKUP_ABBR_REGEX
Deno.test("Empty string", () => assertEquals("".match(MARKUP_ABBR_REGEX), null));
Deno.test("()", () => assertEquals("()".match(MARKUP_ABBR_REGEX), null));

Deno.test("nav>ul>li", () => assertExists("nav>ul>li".match(MARKUP_ABBR_REGEX)));
Deno.test("div+p+bq", () => assertExists("div+p+bq".match(MARKUP_ABBR_REGEX)));
Deno.test("div+div>p>span+em^bq", () => assertExists("div+div>p>span+em^bq".match(MARKUP_ABBR_REGEX)));
Deno.test("div+div>p>span+em^^bq", () => assertExists("div+div>p>span+em^^bq".match(MARKUP_ABBR_REGEX)));
Deno.test("div>(header>ul>li*2>a)+footer>p", () => assertExists("div>(header>ul>li*2>a)+footer>p".match(MARKUP_ABBR_REGEX)));
Deno.test("(div>dl>(dt+dd)*3)+footer>p", () => assertExists("(div>dl>(dt+dd)*3)+footer>p".match(MARKUP_ABBR_REGEX)));
Deno.test("ul>li*5", () => assertExists("ul>li*5".match(MARKUP_ABBR_REGEX)));
Deno.test("ul>li.item$*5", () => assertExists("ul>li.item$*5".match(MARKUP_ABBR_REGEX)));
Deno.test("h$[title=item$]{Header $}*3", () => assertExists("h$[title=item$]{Header $}*3".match(MARKUP_ABBR_REGEX)));
Deno.test("ul>li.item$$$*5", () => assertExists("ul>li.item$$$*5".match(MARKUP_ABBR_REGEX)));
Deno.test("ul>li.item$@-*5", () => assertExists("ul>li.item$@-*5".match(MARKUP_ABBR_REGEX)));
Deno.test("ul>li.item$@3*5", () => assertExists("ul>li.item$@3*5".match(MARKUP_ABBR_REGEX)));
Deno.test("#header", () => assertExists("#header".match(MARKUP_ABBR_REGEX)));
Deno.test(".title", () => assertExists(".title".match(MARKUP_ABBR_REGEX)));
Deno.test("form#search.wide", () => assertExists("form#search.wide".match(MARKUP_ABBR_REGEX)));
Deno.test("p.class1.class2.class3", () => assertExists("p.class1.class2.class3".match(MARKUP_ABBR_REGEX)));
Deno.test('p[title="Hello world"]', () => assertExists('p[title="Hello world"]'.match(MARKUP_ABBR_REGEX)));
Deno.test("td[rowspan=2 colspan=3 title]", () => assertExists("td[rowspan=2 colspan=3 title]".match(MARKUP_ABBR_REGEX)));
Deno.test('[a="value1" b="value2"]', () => assertExists('[a="value1" b="value2"]'.match(MARKUP_ABBR_REGEX)));
Deno.test("a{Click me}", () => assertExists("a{Click me}".match(MARKUP_ABBR_REGEX)));
Deno.test("p>{Click }+a{here}+{ to continue}", () => assertExists("p>{Click }+a{here}+{ to continue}".match(MARKUP_ABBR_REGEX)));
Deno.test(".class", () => assertExists(".class".match(MARKUP_ABBR_REGEX)));
Deno.test("em>.class", () => assertExists("em>.class".match(MARKUP_ABBR_REGEX)));
Deno.test("ul>.class", () => assertExists("ul>.class".match(MARKUP_ABBR_REGEX)));
Deno.test("table>.row>.col", () => assertExists("table>.row>.col".match(MARKUP_ABBR_REGEX)));
Deno.test("input:color", () => assertExists("input:color".match(MARKUP_ABBR_REGEX)));

// CSS_IN_JS_NUMBER_REGEX
Deno.test("12px 12px", () => assertNotMatch("12px 12px", CSS_IN_JS_NUMBER_REGEX));
Deno.test("12px !important", () => assertNotMatch("12px !important", CSS_IN_JS_NUMBER_REGEX));
Deno.test("center", () => assertNotMatch("center", CSS_IN_JS_NUMBER_REGEX));

Deno.test("0", () => assertMatch("0", CSS_IN_JS_NUMBER_REGEX));
Deno.test("0.5", () => assertMatch("0.5", CSS_IN_JS_NUMBER_REGEX));
Deno.test("-100", () => assertMatch("-100", CSS_IN_JS_NUMBER_REGEX));
Deno.test("12px", () => assertMatch("12px", CSS_IN_JS_NUMBER_REGEX));
