import { assertEquals } from "https://deno.land/std@0.164.0/testing/asserts.ts";

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

const htmlAbbrRegex = /[a-zA-Z.]+(\w*|>|-|#|:|@|\^|\$|\+|\.|\*|\/|\(.+\)|\[.+?\]|\{.+\})+\s?/;

Deno.test("nav>ul>li", () => assertEquals(htmlAbbrRegex.test("nav>ul>li"), true));
Deno.test("div+p+bq", () => assertEquals(htmlAbbrRegex.test("div+p+bq"), true));
Deno.test("div+div>p>span+em^bq", () => assertEquals(htmlAbbrRegex.test("div+div>p>span+em^bq"), true));
Deno.test("div+div>p>span+em^^bq", () => assertEquals(htmlAbbrRegex.test("div+div>p>span+em^^bq"), true));
Deno.test("div>(header>ul>li*2>a)+footer>p", () => assertEquals(htmlAbbrRegex.test("div>(header>ul>li*2>a)+footer>p"), true));
Deno.test("(div>dl>(dt+dd)*3)+footer>p", () => assertEquals(htmlAbbrRegex.test("(div>dl>(dt+dd)*3)+footer>p"), true));
Deno.test("ul>li*5", () => assertEquals(htmlAbbrRegex.test("ul>li*5"), true));
Deno.test("ul>li.item$*5", () => assertEquals(htmlAbbrRegex.test("ul>li.item$*5"), true));
Deno.test("h$[title=item$]{Header $}*3", () => assertEquals(htmlAbbrRegex.test("h$[title=item$]{Header $}*3"), true));
Deno.test("ul>li.item$$$*5", () => assertEquals(htmlAbbrRegex.test("ul>li.item$$$*5"), true));
Deno.test("ul>li.item$@-*5", () => assertEquals(htmlAbbrRegex.test("ul>li.item$@-*5"), true));
Deno.test("ul>li.item$@3*5", () => assertEquals(htmlAbbrRegex.test("ul>li.item$@3*5"), true));
Deno.test("#header", () => assertEquals(htmlAbbrRegex.test("#header"), true));
Deno.test(".title", () => assertEquals(htmlAbbrRegex.test(".title"), true));
Deno.test("form#search.wide", () => assertEquals(htmlAbbrRegex.test("form#search.wide"), true));
Deno.test("p.class1.class2.class3", () => assertEquals(htmlAbbrRegex.test("p.class1.class2.class3"), true));
Deno.test('p[title="Hello world"]', () => assertEquals(htmlAbbrRegex.test('p[title="Hello world"]'), true));
Deno.test("td[rowspan=2 colspan=3 title]", () => assertEquals(htmlAbbrRegex.test("td[rowspan=2 colspan=3 title]"), true));
Deno.test('[a="value1" b="value2"]', () => assertEquals(htmlAbbrRegex.test('[a="value1" b="value2"]'), true));
Deno.test("a{Click me}", () => assertEquals(htmlAbbrRegex.test("a{Click me}"), true));
Deno.test("p>{Click }+a{here}+{ to continue}", () => assertEquals(htmlAbbrRegex.test("p>{Click }+a{here}+{ to continue}"), true));
Deno.test(".class", () => assertEquals(htmlAbbrRegex.test(".class"), true));
Deno.test("em>.class", () => assertEquals(htmlAbbrRegex.test("em>.class"), true));
Deno.test("ul>.class", () => assertEquals(htmlAbbrRegex.test("ul>.class"), true));
Deno.test("table>.row>.col", () => assertEquals(htmlAbbrRegex.test("table>.row>.col"), true));
Deno.test("input:color", () => assertEquals(htmlAbbrRegex.test("input:color"), true));
