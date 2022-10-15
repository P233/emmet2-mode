import { assertEquals } from "https://deno.land/std@0.159.0/testing/asserts.ts";
import expandCSS from "./expand-css.ts";

// default emmet css abbreviations
Deno.test("t0", () => assertEquals(expandCSS("t0"), "top: 0;"));
Deno.test("t1", () => assertEquals(expandCSS("t1"), "top: 1px;"));
Deno.test("t1p", () => assertEquals(expandCSS("t1p"), "top: 1%;"));
Deno.test("t1!", () => assertEquals(expandCSS("t1!"), "top: 1px !important;"));
Deno.test("t$abc", () => assertEquals(expandCSS("t$abc"), "top: $abc;"));
Deno.test("t0+r0+b0+l0", () => assertEquals(expandCSS("t0+r0+b0+l0"), "top: 0;\nright: 0;\nbottom: 0;\nleft: 0;"));

// personal opinionated css abbreviations
// Deno.test("t(2)", () => assertEquals(expandCSS("t(2)"), "top: rhythm(2);"));
// Deno.test("t(2)!", () => assertEquals(expandCSS("t(2)"), "top: rhythm(2) !important;"));
// Deno.test("fz(1)", () => assertEquals(expandCSS("fz(1)"), "font-size: ms(1);"));
// Deno.test("fz(1)!", () => assertEquals(expandCSS("fz(1)"), "font-size: ms(1) !important;"));

// property alias abbreviations
Deno.test("posa", () => assertEquals(expandCSS("posa"), "position: absolute;\nz-index: ;"));
Deno.test("posf", () => assertEquals(expandCSS("posf"), "position: fixed;\nz-index: ;"));
Deno.test("all0", () => assertEquals(expandCSS("all0"), "top: 0;\nright: 0;\nbottom: 0;\nleft: 0;"));
Deno.test("all8", () => assertEquals(expandCSS("all8"), "top: 8px;\nright: 8px;\nbottom: 8px;\nleft: 8px;"));
Deno.test("all8!", () =>
  assertEquals(
    expandCSS("all8!"),
    "top: 8px !important;\nright: 8px !important;\nbottom: 8px !important;\nleft: 8px !important;"
  )
);

// pseudo class and pseudo element abbreviations
// Deno.test(":fo", () => assertEquals(expandCSS(":fo"), "&:focus {\n\t\n}"));
// Deno.test("_:fo", () => assertEquals(expandCSS("_:fo"), ":focus {\n\t\n}"));
// Deno.test(".c:fo", () => assertEquals(expandCSS(".c:fo"), ".c:focus {\n\t\n}"));
// Deno.test(".c:fl", () => assertEquals(expandCSS(".c:fl"), ".c::first-letter {\n\t\n}"));
// Deno.test("a.c1.c2#id:fo", () => assertEquals(expandCSS("a.c1.c2#id:fo"), "a.c1.c2#id:focus {\n\t\n}"));
// Deno.test("a.c1.c2#id:fl", () => assertEquals(expandCSS("a.c1.c2#id:fl"), "a.c1.c2#id:first-letter {\n\t\n}"));
// Deno.test(":n(:fc)", () => assertEquals(expandCSS(":n(:fc)"), "&:not(:first-child) {\n\t\n}"));
// Deno.test(":n(:fc,:lc)", () => assertEquals(expandCSS(":n(:fc,:lc)"), "&:not(:first-child):not(:last-child) {\n\t\n}"));
// Deno.test(":h(+p)", () => assertEquals(expandCSS(":h(+p)"), "&:has(+ p) {\n\t\n}"));
