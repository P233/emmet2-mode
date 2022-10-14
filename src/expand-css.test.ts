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
// Deno.test("p[$a $b 2]", () => assertEquals(expandCSS("p[$a $b 2]"), "padding: $a $b 2px;"));

// alias abbreviations
// Deno.test("posa", () => assertEquals(expandCSS("posa"), "position: absolute;\nindex: ;""));
// Deno.test("posf", () => assertEquals(expandCSS("posf"), "position: fixed;\nindex: ;""));

// Deno.test("all0", () => assertEquals(expandCSS("all0"), "top: 0;\nright: 0;\nbottom: 0;\nleft: 0;"));
// Deno.test("all8", () => assertEquals(expandCSS("all8"), "top: 8px;\nright: 8px;\nbottom: 8px;\nleft: 8px;"));
// Deno.test("all8!", () => assertEquals(expandCSS("all8!"), "top: 8px !important;\nright: 8px !important;\nbottom: 8px !important;\nleft: 8px !important;"));
